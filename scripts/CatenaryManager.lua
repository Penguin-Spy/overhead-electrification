--[[ CatenaryManager.lua © Penguin_Spy 2023
  Manages state of overhead catenary line networks
]]
local CatenaryManager = {}

-- Global table storage for catenary network data
---@class catenary_network_data
---@field transformers        LuaEntity[] The transformers powering this catenary network.
---@field electric_network_id uint        The electric network this catenary network is connected to

---@alias catenary_network_id uint

--[[
  catenary pole directions: (this is how rail signals do it)
  0 (defines.direction.north) = rail on the right, rail oriented vertical
  1 (defines.direction.northeast) = rail on the right, rail oriented diagonal up-left
  basically clockwise with the pole on the inside, 0 = 3-o-clock
]]

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
      if #rails > 0 then
        return rails, found_dir
      end
    end
    if not is_big(pole) then  -- if no orthogonal dir found (and not a big pole), try diagonal
      for iter_dir = 1, 7, 2 do
        local rails, found_dir = get_adjacent_rails(pole, iter_dir)
        if #rails > 0 then
          return rails, found_dir
        end
      end
    end
    return nil, nil  -- no rail found
  end

  -- todo: handle ghosts
  return pole.surface.find_entities_filtered{position = pos, type = {"straight-rail", "curved-rail"}}, direction
end

--[[
-- places the appropriate graphics entity for that direction at the position of the pole
---@param pole LuaEntity              the pole to create graphics for
---@param direction defines.direction directions for graphics to face
local function create_pole_graphics(pole, direction)
  local graphics_entity = pole.surface.create_entity{
    name = pole.name .. "-graphics",
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

-- creates the graphics entity if its missing
---@param pole LuaEntity
---@param direction defines.direction
local function ensure_pole_graphics(pole, direction)
  local graphics_entity = pole.surface.find_entity(pole.name .. "-graphics", pole.position)
  if not graphics_entity then
    graphics_entity = create_pole_graphics(pole, direction)
  end
end
]]

--- gets the catenary network data for an electric_network_id, <br>
--- and creates the entry in the global table if one does not exist for the electric network
---@param electric_network_id uint
---@return catenary_network_data network
local function get_or_create_catenary_network(electric_network_id)
  local network = global.catenary_networks[electric_network_id]
  if not network then
    network = {
      transformers = {},
      electric_network_id = electric_network_id
    }
    global.catenary_networks[electric_network_id] = network
  end
  return network
end

--- adds a transformer to a catenary network
---@param network catenary_network_data
---@param transformer LuaEntity
local function add_transformer_to_network(network, transformer)
  table.insert(network.transformers, transformer)
end

--- removes a transformer from a catenary network <br>
--- does not remove the network data if it has no transformers, as update_catenary_network will do that
---@param network catenary_network_data
---@param transformer LuaEntity
local function remove_transformer_from_network(network, transformer)
  util.remove_from_list(network.transformers, transformer)
end



-- when a (non-ghost) entity is placed that's a catenary pole
---@param this_pole LuaEntity the electric pole
---@return string|nil removal_reason string if the placement should be canceled, or nil if success
local function on_electric_pole_placed(this_pole)
  -- figure out what direction we're facing and get the adjacent rail for searching for neighbors
  local rails, direction = get_adjacent_rails(this_pole, global.pole_directions[this_pole.unit_number])
  if not rails or #rails == 0 or not direction then  -- no adjacent rail found
    return "oe-invalid-pole-position"
  end

  -- if this is a transformer, create catenary network
  local network
  if this_pole.name == "oe-transformer" then
    network = get_or_create_catenary_network(this_pole.electric_network_id)
    add_transformer_to_network(network, this_pole)
  end

  -- returns true if the placement is invalid
  local quit = RailMarcher.march_to_connect(rails, this_pole)
  if quit then
    if this_pole.name == "oe-transformer" then
      -- remove the transformer from the network
      remove_transformer_from_network(network, this_pole)
    end
    return "oe-pole-too-close"
  end

  return nil
end


-- when any (non-ghost) rail is placed. checks updating status of nearby catenary poles
---@param rail LuaEntity
function CatenaryManager.on_rail_placed(rail)

end

-- reconnects `pole` to all its neighboring poles, ignoring `ignore_pole`
---@param pole LuaEntity
---@param ignore_pole LuaEntity
local function reconnect(pole, ignore_pole)
  -- unpower all rails powered by the other pole
  for rail_id, powering_pole in pairs(global.pole_powering_rail) do
    if powering_pole == pole then
      global.pole_powering_rail[rail_id] = nil
    end
  end

  -- march to connect from the other pole
  local rails, direction = get_adjacent_rails(pole, global.pole_directions[pole.unit_number])
  if not rails or #rails == 0 or not direction then
    --error("neighbor pole in invalid position unexpectedly")
    return  -- this can happen normally if the rail for that pole was removed
  end
  local quit = RailMarcher.march_to_connect(rails, pole, ignore_pole)
  if quit then
    error("neighbor pole in invalid connection position unexpectedly")
  end
end

-- handles cleanup of graphical entities & whatnot
---@param this_pole LuaEntity
local function on_electric_pole_removed(this_pole)
  -- if a transformer was removed, remove the global data for it
  -- TODO: remove locomotive interfaces (could we just delete them? locomotive updating will do a valid check)
  --  when leaving a network a locomotive will remove it's interface anyways
  if this_pole.name == "oe-transformer" then
    local network = get_or_create_catenary_network(this_pole.electric_network_id)
    remove_transformer_from_network(network, this_pole)
    -- the update_catenary_network function should remove the data if this was the last transformer
  end

  -- unpower all rails powered by this pole
  for rail_id, powering_pole in pairs(global.pole_powering_rail) do
    if powering_pole == this_pole then
      global.pole_powering_rail[rail_id] = nil
    end
  end

  -- update neighbors
  local neighbors = this_pole.neighbours.copper
  this_pole.disconnect_neighbour()  -- disconnect all poles first to properly split electric networks
  for _, other_pole in pairs(neighbors) do
    if identify.is_pole(other_pole) then
      reconnect(other_pole, this_pole)
    end
  end
end


-- TODO: disconnect catenary poles that are connected above this rail
---@param rail LuaEntity
function CatenaryManager.on_rail_removed(rail)
  global.pole_powering_rail[rail.unit_number] = nil
end


-- handle converting the catenary pole placers to their corresponding real entity \
-- also handles ghosts
---@param entity LuaEntity      the placer entity (or ghost of it)
---@return LuaEntity -          the real entity that got placed (may be a ghost)
function CatenaryManager.handle_placer(entity)
  local name, direction, new_entity
  local placer_name = entity.name ~= "entity-ghost" and entity.name or entity.ghost_name

  if placer_name == "oe-catenary-pole-placer" then
    direction = entity.direction
    name = "oe-normal-catenary-pole-" .. ((direction % 2 == 0) and "orthogonal" or "diagonal")
  elseif placer_name == "oe-transformer-placer" then
    name = "oe-transformer-graphics"
    direction = (entity.direction + 4) % 8  -- train stop directions are opposite rail signals.
  end

  if entity.name == "entity-ghost" then
    -- create ghost for the s-e-w-o
    new_entity = entity.surface.create_entity{
      name = "entity-ghost",
      inner_name = name,
      direction = direction,
      position = entity.position,
      force = entity.force,
      player = entity.last_user,
    }
    if not new_entity or not new_entity.valid then error("creating catenary entity (" .. serpent.line(data) .. ") failed unexpectedly") end

    -- remove the placer ghost
    entity.destroy()

    --
  else
    -- create the s-e-w-o
    new_entity = entity.surface.create_entity{
      name = name,
      direction = direction,
      position = entity.position,
      force = entity.force,
      player = entity.last_user,
    }
    if not new_entity or not new_entity.valid then error("creating catenary entity (" .. serpent.line(data) .. ") failed unexpectedly") end

    -- remove the placer entity
    entity.destroy()

    -- handle placing the electric pole
  end

  return new_entity
end

-- when the actual pole graphics entity is placed (not a ghost) \
-- creates the hidden electric pole for the rotation
---@param pole_graphics LuaEntity
---@return string|nil reason
function CatenaryManager.on_pole_graphics_placed(pole_graphics)
  -- mark the graphics entity as not rotatable (in the world, can't use the prototype flag because it needs to be rotatable in blueprints)
  pole_graphics.rotatable = false

  -- get the 8-way direction of the pole
  local direction
  if pole_graphics.name == "oe-normal-catenary-pole-orthogonal" then
    direction = pole_graphics.direction
  elseif pole_graphics.name == "oe-normal-catenary-pole-diagonal" then
    direction = pole_graphics.direction + 1  -- i think
  else
    direction = pole_graphics.direction      -- for transformer, idk
  end

  local electric_pole = pole_graphics.surface.create_entity{
    name = "oe-catenary-electric-pole-" .. direction,
    direction = direction,
    position = pole_graphics.position,
    force = pole_graphics.force,
    player = pole_graphics.last_user,
  }
  if not electric_pole or not electric_pole.valid then error("creating catenary entity (" .. tostring(direction) .. ") failed unexpectedly") end

  global.pole_directions[electric_pole.unit_number] = direction
  local reason = on_electric_pole_placed(electric_pole)

  if reason then  -- invalid pos for catenary pole
    global.pole_directions[electric_pole.unit_number] = nil
    electric_pole.destroy()
    return reason
  end
  return nil
end

-- when the actual pole graphics entity is removed (not a ghost) \
-- removes the hidden electric pole
---@param pole_graphics LuaEntity
function CatenaryManager.on_pole_graphics_removed(pole_graphics)
  -- find electric pole
  local electric_poles = pole_graphics.surface.find_entities_filtered{
    name = identify.electric_pole_names,
    position = pole_graphics.position
  }

  if #electric_poles == 0 then  -- pole may already have been removed if it's placement by a player was canceled
    return
  end

  local electric_pole = electric_poles[1]
  on_electric_pole_removed(electric_pole)
  global.pole_directions[electric_pole.unit_number] = nil
  electric_pole.destroy()
end


-- this sucks but it's 1am i'll figure out something better later
---@param existing_catenary_id uint
---@param catenary_network_data catenary_network_data
function CatenaryManager.update_catenary_network(existing_catenary_id, catenary_network_data)
  local cached_electric_id = catenary_network_data.electric_network_id

  local has_any_transformer = false
  for _, transformer in pairs(catenary_network_data.transformers) do
    if transformer.valid then
      has_any_transformer = true
      local current_electric_id = transformer.electric_network_id

      -- network changed
      if current_electric_id and current_electric_id ~= cached_electric_id then
        log("network changed from " .. tostring(cached_electric_id) .. " to " .. current_electric_id)
        -- remove from old network
        remove_transformer_from_network(catenary_network_data, transformer)

        -- add to new network
        local network = get_or_create_catenary_network(transformer.electric_network_id)
        add_transformer_to_network(network, transformer)
        log("pole added to catenary network " .. tostring(network.electric_network_id))
      end
    end
  end

  -- if all the transformers in this network moved to another one, remove this data
  if not has_any_transformer then
    log("network contains no transformers: " .. tostring(existing_catenary_id))
    global.catenary_networks[existing_catenary_id] = nil
  end
end




return CatenaryManager
