--[[ CatenaryManager.lua © Penguin_Spy 2023
  Manages state of overhead catenary line networks
]]
local CatenaryManager = {}

-- Global table storage for catenary network data
---@class catenary_network_data
---@field transformers LuaEntity[]  The transformers powering this catenary network
---@field electric_network_id uint  The electric network this catenary network is connected to

---@alias catenary_network_id uint

--[[
  catenary pole directions: (this is how rail signals do it)
  0 (defines.direction.north) = rail on the right, vertical
  1 (defines.direction.northeast) = rail on the right, diagonal up-left
  basically clockwise with the pole on the inside, 0 = 3-o-clock
]]


-- checks if an entity is a catenary pole
---@param entity LuaEntity
---@return boolean
local function is_pole(entity)
  local name = entity.name
  return name == "oe-catenary-pole" or name == "oe-transformer"  -- or name == "oe-catenary-double-pole" or name == "oe-catenary-pole-rail-signal", etc
end
CatenaryManager.is_pole = is_pole

-- checks if this entity is a 2x2 pole (only 4 rotations)
---@param entity LuaEntity
local function is_big(entity)
  return entity.prototype.building_grid_bit_shift == 2
end


-- gets the rails that a catenary pole is next to
---@param pole LuaEntity
---@param direction? defines.direction
---@return LuaEntity[]? rails the rails, or nil if the pole is not next to a rail
---@return defines.direction? direction the direction the rail is in, or nil if no rail was found
local function get_adjacent_rails(pole, direction)
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
      local rails, found_dir = get_adjacent_rails(pole, iter_dir)
      if rails then return rails, found_dir end
    end
    if not is_big(pole) then  -- if no orthogonal dir found (and not a big pole), try diagonal
      for iter_dir = 1, 7, 2 do
        local rails, found_dir = get_adjacent_rails(pole, iter_dir)
        if rails then return rails, found_dir end
      end
    end
    game.print("no direction given, all 8 searched and no found")
    return nil, nil  -- no rail found
  end

  rendering.draw_circle{color = {0, 0.7, 1, 1}, radius = 0.5, width = 2, filled = false, target = pos, surface = pole.surface, only_in_alt_mode = true}

  -- todo: handle ghosts
  return pole.surface.find_entities_filtered{position = pos, type = {"straight-rail", "curved-rail"}}, direction
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

-- finds the graphics entity for the pole that's used for graphics
---@param pole LuaEntity
---@return LuaEntity?
local function get_pole_graphics(pole)
  return pole.surface.find_entity(pole.name .. "-graphics", pole.position)
end

-- finds the graphics entity for the pole that's used for graphics, or creates it if it's missing
---@param pole LuaEntity
---@return LuaEntity
local function ensure_pole_graphics(pole)
  local graphics_entity = get_pole_graphics(pole)
  -- if we don't have a graphics_entity, make it facing the first rail clockwise (or north if no rails exist)
  if not graphics_entity then
    local _, direction = get_adjacent_rails(pole)
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
  if not graphics_entity then return defines.direction.north end
  -- 8-way directions are done with variations, 4 way is done with direction.
  return is_big(pole) and ((graphics_entity.direction) % 8)
      or (graphics_entity.graphics_variation - 1)
end


--- creates a new catenary network for the transformer. returns the new network id
---@param transformer LuaEntity
---@return catenary_network_id catenary_id
local function create_catenary_network(transformer)
  local catenary_id = global.next_catenary_network_id
  global.next_catenary_network_id = global.next_catenary_network_id + 1
  global.catenary_networks[catenary_id] = {
    transformers = {transformer},
    electric_network_id = transformer.electric_network_id
  }
  global.electric_network_lookup[transformer.electric_network_id] = catenary_id
  game.print("created catenary network " .. tostring(catenary_id))
  return catenary_id
end


-- 2? versions of this needed:
--   find first pole, connect arg pole to it, stop marching entirely
--   find all poles that match arg pole's network, connect to them & mark rails along path as powered
-- probably could add a check for if arg pole has a network & switch from first to 2nd mode
-- only need 1 version:
--  if arg pole doesn't have a network, don't check if found pole matches
--  otherwise do check
--  if not arg_pole.electric_network_id or found_pole.electric_network_id == arg_pole.electric_network_id then
--   connect the poles via teleport
--   mark all rails on the path as powered by the catenary network for arg_pole.electric_network_id
---@param other_pole LuaEntity
---@param path integer[]
---@param distance integer
---@param this_pole LuaEntity
---@return boolean? quit
local function on_pole(other_pole, path, distance, this_pole)
  if distance == 7 then
    game.print("pole too close")
    remove_pole_graphics(this_pole)
    return true  -- quit marching early
  end

  local catenary_lut = global.electric_network_lookup
  local our_network_id = catenary_lut[ this_pole.electric_network_id  --[[@as integer]] ]
  local other_network_id = catenary_lut[ other_pole.electric_network_id  --[[@as integer]] ]

  -- can't connect to a pole without a network
  -- TODO: it'd be more user-friendly if this connected, but that'd be very tricky to implement
  -- would have to create a catenary network without a transformer for the poles
  -- and also handle merging catenary networks (though i think i'll have to do that anyways)
  if not other_network_id then return end

  if not our_network_id then
    game.print("connecting to other network: " .. tostring(our_network_id))
    our_network_id = other_network_id
  end

  if our_network_id == other_network_id then
    game.print("connecting to pole: " .. tostring(other_pole.unit_number))
    -- connect poles
    local pos = this_pole.position
    this_pole.teleport(other_pole.position)
    this_pole.connect_neighbour(other_pole)
    this_pole.teleport(pos)

    -- power path
    for _, rail_id in pairs(path) do
      global.rail_number_lookup[rail_id] = our_network_id
    end
  end
end


-- when a (non-ghost) entity is placed that's a catenary pole
---@param this_pole LuaEntity
---@return string|nil removal_reason string if the placement should be canceled, or nil if success
function CatenaryManager.on_pole_placed(this_pole)
  game.print("placed pole id: " .. this_pole.unit_number)

  -- figure out what direction we're facing
  ensure_pole_graphics(this_pole)
  local direction = get_direction(this_pole)

  -- get the adjacent rail for searching for neighbors
  -- TODO: do this smarter
  local rails = get_adjacent_rails(this_pole, direction)
  if not rails then
    game.print("no adjacent rail found")
    remove_pole_graphics(this_pole)
    return "oe-invalid-pole-position"
  end

  -- from adjacent rails:
  -- on straight-rails:
  --  find_adjacent_poles, return "oe-pole-too-close" if other poles
  --  march_rail(rail, FRONT) and march_rail(rail, BACK), returning "oe-pole-too-close" if either return quit=true
  -- on curved-rails: f, b = find_adjacent poles
  --  check which end we're on, return "oe-pole-too-close" if other poles on the end we're on
  --
  -- should only be one of each type of rail
  -- if no straight-rail, just check curved-rail, and vice versa


  local poles = RailMarcher.find_adjacent_poles(rails[1], {1, 0, 0}, false)
  util.remove_from_list(poles, this_pole)
  if #poles > 0 then
    game.print("pole too close")
    remove_pole_graphics(this_pole)
    return "oe-pole-too-close"
  end

  local quit = RailMarcher.march_rail(rails[1], defines.rail_direction.front, {}, 7, on_pole, nil, this_pole)
  if quit then
    game.print("pole too close during marching")
    remove_pole_graphics(this_pole)
    return "oe-pole-too-close"
  end

  -- if placement succeded, mark all adjacent rails as powered by our catenary network
  -- TODO: do this smarter as noted above
  global.rail_number_lookup[rails[1].unit_number] = global.electric_network_lookup[this_pole.electric_network_id]


  -- placement is valid, if this is a transformer, create catenary network
  -- TODO: if a 'headless' catenary network can be created when connecting poles, make sure to properly handle merging that here
  --        this_pole could already have a catenary network (and we cant do this b4 because we may need to cancel placement)
  if this_pole.name == "oe-transformer" then
    game.print("network create pole id: " .. this_pole.unit_number)
    local catenary_id = global.electric_network_lookup[this_pole.electric_network_id]
    if not catenary_id then
      create_catenary_network(this_pole)
    else
      table.insert(global.catenary_networks[catenary_id].transformers, this_pole)
      game.print("pole added to catenary network " .. tostring(catenary_id))
    end
  end

  return nil
end


-- when any (non-ghost) rail is placed. checks updating status of nearby catenary poles
---@param rail LuaEntity
function CatenaryManager.on_rail_placed(rail)

end


-- handles cleanup of graphical entities & whatnot
---@param pole LuaEntity
function CatenaryManager.on_pole_removed(pole)
  game.print("on pole removed")

  -- if a transformer was removed, remove the global data for it
  -- TODO: remove locomotive interfaces (could we just delete them? locomotive updating will do a valid check)
  --  when leaving a network a locomotive will remove it's interface anyways
  if pole.name == "oe-transformer" then
    local catenary_id = global.electric_network_lookup[pole.electric_network_id]
    if catenary_id then
      local transformers = global.catenary_networks[catenary_id].transformers
      util.remove_from_list(transformers, pole)
      if table_size(transformers) == 0 then
        game.print("removed catenary network " .. tostring(catenary_id))
        global.catenary_networks[catenary_id] = nil
        global.electric_network_lookup[pole.electric_network_id] = nil
        -- remove all powered rails in this network
        for unit_number, value in pairs(global.rail_number_lookup) do
          if value == catenary_id then
            global.rail_number_lookup[unit_number] = nil
          end
        end
      end
    end
  end

  -- update neighbors
  local neighbors = pole.neighbours.copper
  for _, other_pole in pairs(neighbors) do
    if is_pole(other_pole) then
      -- TODO: unpower this rail, disconnect this pole from other pole, march from other to unpower dead ends, then march from other to connect
    end
  end

  -- do this after we call get_direction
  remove_pole_graphics(pole)
end


-- TODO: disconnect catenary poles that are connected above this rail
---@param rail LuaEntity
function CatenaryManager.on_rail_removed(rail)
  global.rail_number_lookup[rail.unit_number] = nil
end


-- handle converting the catenary pole placers to their corresponding real entity
---@param entity LuaEntity      the placer entity
---@param placer_target string  the name of the real entity to be placed
---@return LuaEntity -          the real entity that got placed
function CatenaryManager.handle_placer(entity, placer_target)
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


-- this sucks but it's 1am i'll figure out something better later
---@param catenary_network_data catenary_network_data
function CatenaryManager.update_catenary_network(existing_catenary_id, catenary_network_data)
  local cached_electric_id = catenary_network_data.electric_network_id

  for _, transformer in pairs(catenary_network_data.transformers) do
    local current_electric_id = transformer.electric_network_id

    -- network changed
    if current_electric_id and current_electric_id ~= cached_electric_id then
      game.print("network changed from " .. tostring(cached_electric_id) .. " to " .. current_electric_id)
      util.remove_from_list(catenary_network_data.transformers, transformer)

      local catenary_id = global.electric_network_lookup[transformer.electric_network_id]
      if not catenary_id then
        catenary_id = create_catenary_network(transformer)
      else
        table.insert(global.catenary_networks[catenary_id].transformers, transformer)
        game.print("pole added to catenary network " .. tostring(catenary_id))
      end

      -- update network
      CatenaryManager.recursively_update_network(catenary_id)
    end
  end

  if #catenary_network_data.transformers == 0 then
    game.print("removing catenary network " .. tostring(existing_catenary_id))
    global.electric_network_lookup[cached_electric_id] = nil
    global.catenary_networks[existing_catenary_id] = nil
  end
end




return CatenaryManager
