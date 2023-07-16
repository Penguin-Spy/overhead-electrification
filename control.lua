--[[ control.lua © Penguin_Spy 2023
  Event handlers & updating/tracking of locomotive power
]]
---@class locomotive_data
---@field locomotive LuaEntity    The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil

---@class catenary_network_data
---@field transformer LuaEntity   The transformer powering this catenary network

util = require 'util'
local catenary_utils = require 'scripts.catenary_utils'
---@diagnostic disable-next-line: lowercase-global
rail_march = require 'scripts.rail_march'

if script.active_mods["gvv"] then require("__gvv__.gvv")() end

---@param entity LuaEntity
---@param event EventData.on_built_entity|EventData.on_robot_built_entity|EventData.script_raised_built
---@param reason LocalisedString
local function cancel_entity_creation(entity, event, reason)
  local player = event.player_index and game.players[event.player_index]

  entity.surface.create_entity{name = "flying-text", text = reason, position = entity.position, render_player_index = event.player_index}

  -- if it's a ghost, just delete it
  if entity.type == "entity-ghost" then
    entity.destroy()
    return
  end

  -- if it's already placed, Put That Thing Back Where It Came From Or So Help Me!
  local item = entity.prototype.items_to_place_this and entity.prototype.items_to_place_this[1]
  local picked_up = false
  if player then  -- put it back in the player
    local mine = player.mine_entity(entity, false)
    if mine then
      picked_up = true
    elseif item then
      picked_up = player.insert(item) > 0
    end
  end  -- or put it back in the robot
  if not picked_up and item and event.robot then
    local inventory = event.robot.get_inventory(defines.inventory.robot_cargo)
    ---@diagnostic disable-next-line need-check-nil
    picked_up = inventory.insert(item) > 0
  end  -- or just spill it
  if not picked_up and item then
    entity.surface.spill_item_stack(
      entity.position, item,
      true,          -- to_be_looted (picked up when walked over)
      ---@diagnostic disable-next-line: param-type-mismatch
      entity.force,  -- mark for deconstruction by this force
      false)         -- don't go on belts
  end
  if entity and entity.valid then
    entity.destroy()
  end
end



---@param effective_name string the actual name of the entity
---@param entity LuaEntity may be "entity-ghost"
---@return string?- nil if not canceling, or localised string key
local function check_placement(effective_name, entity)
  if effective_name == "oe-transformer" or effective_name == "oe-catenary-pole" then
    --local nearby_rails = entity.surface.find_entities_filtered{position = entity.position, radius = 2, name = "straight-rail"}
  end

  return "cant-build-reason.entity-must-be-built-next-to-rail"
end


---@param event EventData.on_built_entity|EventData.script_raised_built
local function on_entity_created(event)
  local entity = event.created_entity or event.entity

  -- name of the entity this placer is placing, or nil if not a placer
  local placer_target = string.match(entity.name, "^(oe%-.-)%-placer$")
  -- name of the entity this entity will eventually be
  --[[local effective_name = placer_target                                                                                     -- real placer
      or (entity.name == "entity-ghost" and (string.match(entity.ghost_name, "^(oe%-.-)%-placer$") or entity.ghost_name))  -- ghost placer or ghost entity
      or entity.name                                                                                                       -- real entity
  ]]

  --game.print("placer_name: " .. (placer_target or "nil") .. " effective_name: " .. effective_name)

  -- if it's an entity we have placement restrictions for, check them
  --[[if effective_name == "oe-transformer" then
    local cancel_reason = check_placement(effective_name, entity)
    if cancel_reason then
      cancel_entity_creation(entity, event, {cancel_reason, {"entity-name." .. effective_name}})
      return
    end
  end]]


  -- if an actual placer got placed, convert it to it's target
  --[[if placer_target == "oe-transformer" then  -- note that this only runs when the player places the item. bots building ghosts immediatley places the real entity
    game.print("converting " .. entity.name .. " to " .. placer_target)
    local new_entity = entity.surface.create_entity{
      name = placer_target,
      position = entity.position,
      direction = entity.direction,
      force = entity.force,
      player = entity.last_user,
    }
    entity.destroy()
    if not new_entity or not new_entity.valid then error("creating entity " .. placer_target .. " failed unexpectedly") end
    -- run the rest of this handler with the real entity
    entity = new_entity
  else]]
  if placer_target then  -- any other placers are for catenary poles
    game.print("catenary_utils converting " .. entity.name .. " to " .. placer_target)
    entity = catenary_utils.handle_placer(entity, placer_target)
  end

  -- the real entity actually got built, run on_build code for them

  -- catenary poles: check if valid space, check if can create pole connections
  if catenary_utils.is_pole(entity) then
    if not catenary_utils.on_pole_placed(entity) then
      cancel_entity_creation(entity, event, {"cant-build-reason.oe-pole-too-close"})
      return
    end

    -- any rails: check catenary pole connections.  checking type makes this work with other mods' rails
  elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
    catenary_utils.on_rail_placed(entity)
  end

  -- transformer: create catenary network.
  if entity.name == "oe-transformer" then
    global.catenary_networks[entity.electric_network_id] = {
      transformer = entity
    }

    -- locomotive: create locomotives table entry
  elseif entity.name == "oe-electric-locomotive" then
    global.locomotives[entity.unit_number] = {
      locomotive = entity
    }
  end
end

-- todo: generate filter to only our entities, use it for events in the proper filter format
script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, on_entity_created)


---@param event EventData.on_entity_died
local function on_entity_destroyed(event)
  local entity = event.entity

  --game.print("on_destroyed:" .. event.name .. " destroyed:" .. entity.name)

  if catenary_utils.is_pole(entity) then
    catenary_utils.on_pole_removed(entity)
  elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
    catenary_utils.on_rail_removed(entity)
  end

  -- transformer: remove catenary network
  -- TODO: remove locomotive interfaces (could we just delete them? locomotive updating will do a valid check)
  if entity.name == "oe-transformer" then
    global.catenary_networks[entity.electric_network_id] = nil
  end

  if entity.name == "oe-electric-locomotive" then
    local locomotive_data = global.locomotives[entity.unit_number]
    local interface = locomotive_data.interface
    if interface and interface.valid then  -- may be nil if loco wasn't in a network (or invalid if deleted somelsehow)
      interface.destroy()
    end
    global.locomotives[entity.unit_number] = nil
  end
end

-- todo: filter
script.on_event({
  defines.events.on_entity_died,
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy
}, on_entity_destroyed)


-- [[ Locomotive updating ]]

---@param locomotive LuaEntity
local function update_locomotive(locomotive)

end

-- todo: use event.tick, modulo, and a limit number to only update n locomotives per tick
---      make the limit a map setting
---@param event EventData.on_tick
local function on_tick(event)
  for _, locomotive_data in ipairs(global.locomotives) do
    update_locomotive(locomotive_data.locomotive)
  end
end

script.on_event(defines.events.on_tick, on_tick)




-- [[ Initalization ]] --

-- called when added to a save, game start, or on_configuration_changed
local function initalize()
  ---@type locomotive_data[] A mapping of unit_number to locomotive data
  global.locomotives = global.locomotives or {}
  ---@type catenary_network_data[] A mapping of electric_network_id to catenary network data
  global.catenary_networks = global.catenary_networks or {}
end

-- called every time the game loads. cannot access the game object
local function loadalize()

end

script.on_init(function()
  initalize()
  loadalize()
end)
script.on_load(loadalize)
script.on_configuration_changed(initalize)






-- [[ testing stuff ]] --

---@param entity LuaEntity
---@param index number
function highlight(entity, index)
  ---@diagnostic disable-next-line: assign-type-mismatch
  rendering.draw_circle{color = {1, 0.7, 0, 1}, radius = 0.5, width = 2, filled = false, target = entity, surface = entity.surface, only_in_alt_mode = true}
  rendering.draw_text{color = {1, 0.7, 0, 1}, text = index, target = entity, surface = entity.surface, only_in_alt_mode = true}
end

commands.add_command("oe-debug", {"mod-name.overhead-electrification"}, function(command)
  local player = game.players[command.player_index]

  local options
  if command.parameter then
    options = util.split(command.parameter, " ")
  else
    game.print("commands: step, find, all, clear")
    return
  end

  local subcommand = options[1]

  -- consider LuaEntity.get_rail_segment_rails
  if subcommand == "step" then
    --local rail = player.selected.get_connected_rail{rail_direction = options[2] or defines.rail_direction.front, rail_connection_direction = defines.rail_connection_direction.straight}

    local poles = rail_march.find_all_poles(player.selected, tonumber(options[2]) or defines.rail_direction.front)

    if not poles then return end

    for i, pole in pairs(poles) do
      game.print("found #" .. i .. ": " .. pole.name)
      highlight(pole, i)
    end

    -- /c for _, r in pairs((game.player.selected.get_rail_segment_rails(0))) do pcall(r.destroy()) end

    -- (game.player.selected.get_connected_rail{rail_direction=1,rail_connection_direction=1}).destroy()
  elseif subcommand == "find" then
    local target = player.selected or player.character

    local entities = target.surface.find_entities_filtered{position = target.position, radius = tonumber(options[2]) or 2, name = "oe-catenary-pole"}
    --/c game.print(serpent.line(game.player.surface.find_entities_filtered{position=a,radius=1.5,name="oe-catenary-pole"}))
    for i, pole in pairs(entities) do
      game.print("found #" .. i .. ": " .. pole.name)
      highlight(pole, i)
    end



    -- need to filter to closest 2 that are on the same rail network
    --  can't do much better without stepping along rails one by one and checking entities (that would be very bad & laggy)
  elseif subcommand == "all" then

  elseif subcommand == "clear" then
    rendering.clear(script.mod_name)
  end
end)
