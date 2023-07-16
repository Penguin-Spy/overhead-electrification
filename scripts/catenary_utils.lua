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


-- gets the rail that a catenary pole is next to
---@param pole LuaEntity
---@param direction? defines.direction
---@return LuaEntity? rail the rail, or nil if the pole is not next to a rail
---@return defines.direction? direction the direction the rail is in, or nil if no rail was found
local function get_adjacent_rail(pole, direction)
  local pos = pole.position
  local offset = is_big(pole) and 1.5 or 1

  -- yup. i tried using the util.moveposition function, but the directions are different and there were a bunch of type annotation errors
  -- and the position vectors are as arrays instead of tables; it was more trouble than it's worth
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
    game.print("no direction given, all 8 searched and no found")
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


-- places the appropriate graphics entity for that direction at the position of the pole
---@param pole LuaEntity doesn't actually need to be a pole, just used for surface & position & whatnot
---@param name string the name of the pole
---@param direction defines.direction directions for graphics to face
local function create_graphics_for_pole(pole, name, direction)
  local graphics_entity = pole.surface.create_entity{
    name = name .. "-graphics",
    position = pole.position,
    direction = direction,  -- factorio rounds down for 4-direciton entities apparently, cool!
    force = pole.force,
    player = pole.last_user
  }
  graphics_entity.graphics_variation = direction + 1  -- does nothing for 4-way graphics entities (intended)
  return graphics_entity
end


-- removes the graphics entity if it exists
---@param pole LuaEntity
local function remove_pole_graphics(pole)
  local graphics_entity = pole.surface.find_entity(pole.name .. "-graphics", pole.position)
  if graphics_entity then
    graphics_entity.destroy()
  end
end


-- finds the graphics entity for the pole that's used for graphics, or creates it if it's missing
---@param pole LuaEntity
---@return LuaEntity
local function get_pole_graphics(pole)
  local graphics_entity = pole.surface.find_entity(pole.name .. "-graphics", pole.position)
  -- if we don't have a graphics_entity, make it facing the first rail clockwise (or north if no rails exist)
  if not graphics_entity then
    local _, direction = get_adjacent_rail(pole)
    if not direction then
      direction = defines.direction.north
    end
    graphics_entity = create_graphics_for_pole(pole, pole.name, direction)
  end
  return graphics_entity
end


-- returns the 8-way direction of the catenary pole
---@param pole LuaEntity
---@return defines.direction
local function get_direction(pole)
  local graphics_entity = get_pole_graphics(pole)
  -- 8-way directions are done with variations, 4 way is done with direction.
  return is_big(pole) and ((graphics_entity.direction) % 8)
      or (graphics_entity.graphics_variation - 1)
end


-- attempts to connect two poles, failing if they're not in the same network <br>
-- if this_pole doesn't have a network, it's added to the other_pole's network
---@param this_pole LuaEntity
---@param other_pole LuaEntity
---@return boolean success were the poles connected
local function connect_poles(this_pole, other_pole)
  -- if we have a network and it's different
  local we_have_network = global.electric_network_lookup[this_pole.electric_network_id]
  local they_have_network = global.electric_network_lookup[other_pole.electric_network_id]
  local networks_are_different = this_pole.electric_network_id ~= other_pole.electric_network_id

  game.print("we_have_network: " .. (we_have_network or "no") .. " they_have_network: " .. (they_have_network or "no") .. " networks_are_different: " .. tostring(networks_are_different))

  if we_have_network and they_have_network and networks_are_different then
    return false  -- don't connect
  else            -- otherwise, they're the same network or we should connect to theirs
    game.print("actually connecting to pole")
    -- teleport to the other pole to connect, then teleport back
    local pos = this_pole.position
    this_pole.teleport(other_pole.position)
    local success = this_pole.connect_neighbour(other_pole)
    this_pole.teleport(pos)
    --return success  -- we assume teleportation always succeeds bc they're electric poles

    if success then
      local rail = get_adjacent_rail(this_pole, get_direction(this_pole))
      if rail then
        local catenary_id = global.electric_network_lookup[this_pole.electric_network_id]
        global.rail_number_lookup[rail.unit_number] = catenary_id
      end
    end

    return success
  end
end


-- when a (non-ghost) entity is placed that's a catenary pole
---@param this_pole LuaEntity
---@return string|nil removal_reason string if the placement should be canceled, or nil if success
function catenary_utils.on_pole_placed(this_pole)
  -- figure out what direction we're facing
  local direction = get_direction(this_pole)

  -- get the adjacent rail for searching for neighbors
  local rail = get_adjacent_rail(this_pole, direction)
  if not rail then
    game.print("no adjacent rail found")
    return "oe-invalid-pole-position"
  end
  local nearby_poles, far_poles = rail_march.find_all_poles(rail)

  for i, other_pole in pairs(nearby_poles) do
    game.print("found nearby #" .. i .. ": " .. other_pole.name)
    highlight(other_pole, i, {0, 1, 0})
    if other_pole ~= this_pole then
      return "oe-pole-too-close"
    end
  end

  for i, other_pole in pairs(far_poles) do
    game.print("found far #" .. i .. ": " .. other_pole.name)
    highlight(other_pole, i, {1, 0, 0})
    game.print("connecting poles")
    connect_poles(this_pole, other_pole)
  end

  return nil
end


-- when any (non-ghost) rail is placed. checks updating status of nearby catenary poles
---@param rail LuaEntity
function catenary_utils.on_rail_placed(rail)

end


-- handles cleanup of graphical entities & whatnot
---@param pole LuaEntity
function catenary_utils.on_pole_removed(pole)
  game.print("on pole removed")

  -- mark rail as no longer powered
  -- TODO: do this for every pole in the electrical network that no longer has a catenary network (in the lookup table)
  local rail = get_adjacent_rail(pole, get_direction(pole))
  if rail then
    global.rail_number_lookup[rail.unit_number] = nil
  end

  -- do this after we call get_direction
  remove_pole_graphics(pole)
end


-- disconnects catenary poles that are connected above this rail
---@param rail LuaEntity
function catenary_utils.on_rail_removed(rail)

end



-- handle converting the catenary pole placers to their corresponding real entity
---@param entity LuaEntity      the placer entity
---@param placer_target string  the name of the real entity to be placed
---@return LuaEntity -          the real entity that got placed
function catenary_utils.handle_placer(entity, placer_target)
  -- place the s-e-w-o for the direction
  if placer_target == "oe-catenary-pole" then
    create_graphics_for_pole(entity, placer_target, entity.direction)
  elseif placer_target == "oe-transformer" then
    create_graphics_for_pole(entity, placer_target, (entity.direction + 4) % 8)  -- train stop directions are opposite rail signals.
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
