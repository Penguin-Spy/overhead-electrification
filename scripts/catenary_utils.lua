local catenary_utils = {}

--[[
  catenary pole directions: (this is how rail signals do it)
  0 (defines.direction.north) = rail on the right, vertical
  1 (defines.direction.northeast) = rail on the right, diagonal up-left
  basically clockwise with the pole on the inside, 0 = 3-o-clock
]]


-- checks if an entity is a catenary pole
---@param entity LuaEntity
---@return boolean
function catenary_utils.is_pole(entity)
  local name = entity.name
  return name == "oe-catenary-pole" or name == "oe-transformer"  -- or name == "oe-catenary-double-pole" or name == "oe-catenary-pole-rail-signal", etc
end


-- checks if this entity is a 2x2 pole (only 4 rotations)
---@param entity LuaEntity
local function is_big(entity)
  return entity.prototype.building_grid_bit_shift == 2
end

-- attempts to connect two poles, failing if they're not in the same network <br>
-- if this_pole doesn't have a network, it's added to the other_pole's network
---@param this_pole LuaEntity
---@param other_pole LuaEntity
---@return boolean success were the poles connected
local function connect_poles(this_pole, other_pole)
  -- if we have a network and it's different
  if global.catenary_networks[this_pole.electric_network_id] and this_pole.electric_network_id ~= other_pole.electric_network_id then
    return false  -- don't connect
  else            -- otherwise, they're the same network or we should connect to theirs
    -- teleport to the other pole to connect, then teleport back
    local pos = this_pole.position
    this_pole.teleport(other_pole.position)
    local success = this_pole.connect_neighbour(other_pole)
    this_pole.teleport(pos)
    return success  -- we assume teleportation always succeeds bc they're electric poles
  end
end

-- gets the rail that a catenary pole is next to
---@param pole LuaEntity
---@param direction? defines.direction
---@return LuaEntity? rail the rail, or nil if the pole is not next to a rail
---@return defines.direction? direction the direction the rail is in, or nil if no rail was found
local function get_adjacent_rail(pole, direction)
  local pos = pole.position
  local offset = is_big(pole) and 1.5 or 1

  -- yup
  if direction == defines.direction.north then
    pos.x = pos.x + offset
  elseif direction == defines.direction.east then  -- down is positive y
    pos.y = pos.y + offset
  elseif direction == defines.direction.south then
    pos.x = pos.x - offset
  elseif direction == defines.direction.west then
    pos.y = pos.y - offset
  elseif direction == defines.direction.northeast then
    pos.x = pos.x + 1
    pos.y = pos.y + 1
  elseif direction == defines.direction.southeast then
    pos.x = pos.x - 1
    pos.y = pos.y + 1
  elseif direction == defines.direction.southwest then
    pos.x = pos.x - 1
    pos.y = pos.y - 1
  elseif direction == defines.direction.northwest then
    pos.x = pos.x + 1
    pos.y = pos.y - 1
  else  -- no direction given, search for a rail clockwise (orthogonal first, then diagonal)
    for iter_dir = 0, 6, 2 do
      local rail, found_dir = get_adjacent_rail(pole, iter_dir)
      if rail then return rail, found_dir end
    end
    if not is_big(pole) then  -- if no orthogonal dir found (and not a big pole), try diagonal
      for iter_dir = 1, 7, 2 do
        local rail, found_dir = get_adjacent_rail(pole, iter_dir)
        if rail then return rail, found_dir end
      end
    end
    return nil, nil  -- no rail found
  end

  rendering.draw_circle{color = {0, 0.7, 1, 1}, radius = 0.5, width = 2, filled = false, target = pos, surface = pole.surface, only_in_alt_mode = true}
  game.print(pos)

  return pole.surface.find_entities_filtered{position = pos, type = "straight-rail"}[1], direction
end


-- checks to make sure a rail doesn't already have any catenary poles on it
---@param rail LuaEntity
---@return boolean
local function check_rail_is_clear(rail)
  return #rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = "oe-catenary-pole"} == 0
end


-- places the appropriate simple entity for that direction at the position of the pole
---@param pole LuaEntity doesn't actually need to be a pole, just used for surface & position & whatnot
---@param name string the name of the pole
---@param direction defines.direction
local function create_simple_entity_for_pole(pole, name, direction)
  return pole.surface.create_entity{
    name = name .. ((direction % 2 == 0 or is_big(pole)) and "-orthogonal" or "-diagonal"),
    position = pole.position,
    direction = direction,  -- factorio rounds down for 4-direciton entities apparently, cool!
    force = pole.force,
    player = pole.last_user
  }
end


-- finds the simple entity for the pole that's used for graphics, or creates it if it's missing
---@param pole LuaEntity
---@return LuaEntity simple_entity
local function get_simple_entity(pole)
  local simple_entity = pole.surface.find_entity(pole.name .. "-orthogonal", pole.position)
  if not (simple_entity or is_big(pole)) then  -- if we didn't find it and it has a diagonal version
    simple_entity = pole.surface.find_entity(pole.name .. "-diagonal", pole.position)
  end
  -- if we don't have a simple_entity, make it facing the first rail clockwise (or north if no rails exist)
  if not simple_entity then
    local _, direction = get_adjacent_rail(pole)
    if not direction then
      direction = defines.direction.north
    end
    simple_entity = create_simple_entity_for_pole(pole, pole.name, direction)
  end
  return simple_entity
end


-- returns the 8-way direction of the catenary pole
---@param pole LuaEntity
---@return defines.direction
local function get_direction(pole)
  local simple_entity = get_simple_entity(pole)
  local direction = simple_entity.direction
  if simple_entity.name == pole.name .. "-diagonal" then
    direction = (direction + 1) % 8
  end
  return direction
end


-- when a (non-ghost) entity is placed that's a catenary pole
---@param pole LuaEntity
---@return boolean valid false if the placement should be canceled
function catenary_utils.on_pole_placed(pole)
  -- figure out what direction we're facing

  local direction = get_direction(pole)

  -- get the adjacent rail for searching for neighbors

  local rail = get_adjacent_rail(pole, direction)
  if not rail then
    game.print("no adjacent rail found")
    -- TODO: something better than this
    get_simple_entity(pole).destroy()
    return false
  end
  local poles = rail_march.find_all_poles(rail, defines.rail_direction.front)

  if not poles then
    game.print("no poles found")
    return true
  end

  for i, other_pole in pairs(poles) do
    game.print("found #" .. i .. ": " .. other_pole.name)
    highlight(other_pole, i)
  end

  local _, other_pole = next(poles)
  if other_pole then
    game.print("connecting poles")
    connect_poles(pole, other_pole)
  end

  return true
end


-- when any (non-ghost) rail is placed. checks updating status of nearby catenary poles
---@param rail LuaEntity
function catenary_utils.on_rail_placed(rail)

end


-- handles cleanup of graphical entities & whatnot
---@param pole LuaEntity
function catenary_utils.on_pole_removed(pole)
  get_simple_entity(pole).destroy()
end


-- disconnects catenary poles that are connected above this rail
---@param rail LuaEntity
function catenary_utils.on_removed_placed(rail)

end



-- handle converting the catenary pole placers to their corresponding real entity
---@param entity LuaEntity      the placer entity
---@param placer_target string  the name of the real entity to be placed
---@return LuaEntity -          the real entity that got placed
function catenary_utils.handle_placer(entity, placer_target)
  -- place the s-e-w-o for the direction
  if placer_target == "oe-catenary-pole" then
    create_simple_entity_for_pole(entity, placer_target, entity.direction)
  elseif placer_target == "oe-transformer" then
    create_simple_entity_for_pole(entity, placer_target, (entity.direction + 4) % 8)
  end

  local new_entity = entity.surface.create_entity{
    name = placer_target,
    position = entity.position,
    direction = entity.direction,
    force = entity.force,
    player = entity.last_user,
  }
  entity.destroy()
  if not new_entity or not new_entity.valid then error("creating catenary entity " .. placer_target .. " failed unexpectedly") end
  return new_entity
end

return catenary_utils
