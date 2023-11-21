--[[ control.lua © Penguin_Spy 2023
  Event handlers & updating/tracking of locomotive power

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]


util = require 'util'
RailMarcher = require 'scripts.RailMarcher'
identify = require 'scripts.identify'  ---@diagnostic disable-line: lowercase-global

local CatenaryManager = require 'scripts.CatenaryManager'
local TrainManager = require 'scripts.TrainManager'

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
    local inventory = event.robot.get_inventory(defines.inventory.robot_cargo)  --[[@as LuaInventory]]
    picked_up = inventory.insert(item) > 0
  end  -- or just spill it
  if not picked_up and item then
    entity.surface.spill_item_stack(
      entity.position, item,
      true,                              -- to_be_looted (picked up when walked over)
      entity.force  --[[@as LuaForce]],  -- mark for deconstruction by this force
      false)                             -- don't go on belts
  end
  if entity and entity.valid then
    entity.destroy()
  end
end



-- [[ Event handlers ]] --

---@param event EventData.on_built_entity|EventData.script_raised_built
local function on_entity_created(event)
  local entity = event.created_entity or event.entity

  -- name of the entity this placer is placing, or nil if not a placer
  local placer_target = string.match(entity.name, "^(oe%-.-)%-placer$")
  if placer_target then  -- all placers are for catenary poles
    entity = CatenaryManager.handle_placer(entity, placer_target)
  end
  -- the real entity actually got built, run on_build code for them

  -- catenary poles: check if valid space, check if can create pole connections
  if identify.is_pole(entity) then
    local reason = CatenaryManager.on_pole_placed(entity)
    if reason then
      cancel_entity_creation(entity, event, {"cant-build-reason." .. reason})
    end

    -- any rails: check catenary pole connections.  checking type makes this work with other mods' rails
  elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
    CatenaryManager.on_rail_placed(entity)

    -- locomotive: create locomotives table entry
  elseif entity.name == "oe-electric-locomotive" then
    TrainManager.on_locomotive_placed(entity)
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

  if identify.is_pole(entity) then
    CatenaryManager.on_pole_removed(entity)
  elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
    CatenaryManager.on_rail_removed(entity)
  elseif identify.is_locomotive(entity) then
    TrainManager.on_locomotive_removed(entity)
  end

  if identify.is_rolling_stock(entity) then
    TrainManager.on_rolling_stock_removed(entity)
  end
end

-- todo: filter
script.on_event({
  defines.events.on_entity_died,
  defines.events.on_pre_player_mined_item,
  defines.events.on_robot_pre_mined,
  defines.events.script_raised_destroy
}, on_entity_destroyed)


script.on_event(defines.events.on_entity_cloned, function(event)
  local source = event.source
  if identify.is_locomotive(source) then
    local destination = event.destination
    local data = global.locomotives[source.unit_number]
    global.locomotives[source.unit_number] = {cloning = true}
    global.locomotives[destination.unit_number] = data

    local train_data = global.trains[source.train.id]
    if util.remove_from_list(train_data.electric_front_movers, source) then
      table.insert(train_data.electric_front_movers, destination)
    elseif util.remove_from_list(train_data.electric_back_movers, source) then
      table.insert(train_data.electric_back_movers, destination)
    end

    data.locomotive = destination
  elseif identify.is_pole(source) then
    CatenaryManager.on_pole_placed(event.destination)
  end
end)


-- this is OK as a non-global because it still initalizes to the same value for everyone, and I keep it up to date with the event handler
local TRAIN_UPDATE_RATE = settings.global["oe-train-update-rate"].value  --[[@as integer]]

script.on_event(defines.events.on_tick, function(event)
  -- ew, really need to find a set of suitable event handlers for this if possible
  -- pole created/destroyed + linked game control for "build" to detect copper wire usage
  --  what about power switches toggling?
  for id, catenary_network_data in pairs(global.catenary_networks) do
    CatenaryManager.update_catenary_network(id, catenary_network_data)
  end

  -- update each train every N ticks, spread multiple trains across those N ticks
  for _, train_id in pairs(global.train_buckets[event.tick % TRAIN_UPDATE_RATE + 1]) do
    TrainManager.update_train(global.trains[train_id])
  end

  -- handle train state changes every tick because it's infrequent & not performance intensive
  for _, train_data in pairs(global.next_tick_train_state_changes) do
    TrainManager.update_train_power_state(train_data)
  end
  global.next_tick_train_state_changes = global.second_next_tick_train_state_changes
  global.second_next_tick_train_state_changes = {}
end)

script.on_event(defines.events.on_train_changed_state, TrainManager.on_train_state_changed)
script.on_event(defines.events.on_train_created, TrainManager.on_train_created)


-- [[ Rail power visualization ]]

script.on_nth_tick(30, function(event)
  for _, player in pairs(game.connected_players) do
    if global.show_rail_power[player.index] then
      local all_rails = player.surface.find_entities_filtered{
        type = {"straight-rail", "curved-rail"},
        position = player.position,
        radius = 32
      }
      for _, rail in pairs(all_rails) do
        local pole = global.pole_powering_rail[rail.unit_number]
        if pole and pole.valid then
          rendering.draw_circle{
            color = {0, 1, 1}, radius = 0.5, width = 2, filled = false,
            target = rail, surface = rail.surface, players = {player},
            time_to_live = 31
          }
          rendering.draw_text{
            color = {0, 1, 1}, text = pole.electric_network_id,
            target = rail, surface = rail.surface, players = {player},
            time_to_live = 31
          }
        end
      end
    end
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "oe-toggle-powered-rail-view" then
    local player = game.get_player(event.player_index)
    if not player then return end
    global.show_rail_power[event.player_index] = not global.show_rail_power[event.player_index]
    player.set_shortcut_toggled("oe-toggle-powered-rail-view", global.show_rail_power[event.player_index])
  end
end)


-- delete old buckets and recreate them
local function rebucket_trains()
  ---@type (uint[])[] list of train ids to update on each tick
  global.train_buckets = {}
  for i = 1, TRAIN_UPDATE_RATE do
    global.train_buckets[i] = {}
  end
  global.train_next_bucket = 1

  -- re-add all trains to the buckets
  for train_id, train_data in pairs(global.trains) do
    table.insert(global.train_buckets[global.train_next_bucket], train_id)
    train_data.bucket = global.train_next_bucket
    global.train_next_bucket = global.train_next_bucket + 1
    if global.train_next_bucket > #global.train_buckets then
      global.train_next_bucket = 1
    end
  end
end

-- update the TRAIN_UPDATE_RATE value & recompute the buckets
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "oe-train-update-rate" then
    TRAIN_UPDATE_RATE = settings.global["oe-train-update-rate"].value  --[[@as integer]]
    rebucket_trains()
  end
end)

-- [[ Initalization ]] --

-- called when added to a save, game start, or on_configuration_changed
local function initalize()
  ---@type table<uint, locomotive_data> A mapping of unit_number to locomotive data
  global.locomotives = global.locomotives or {}

  ---@type table<uint, train_data> a list of trains that have at least one electric locomotive
  global.trains = {}
  -- recreates the global.trains list because removing locomotive prototypes creates trains but doesn't trigger on_train_created
  for _, surface in pairs(game.surfaces) do
    local trains = surface.get_trains()
    for _, train in pairs(trains) do
      TrainManager.on_train_created{train = train}
    end
  end

  -- initalizes global.train_buckets and global.train_next_bucket
  rebucket_trains()

  ---@type table<uint?, LuaEntity> a mapping of a rail's `unit_number` to the `LuaEntity` of the pole powering it
  global.pole_powering_rail = global.pole_powering_rail or {}

  ---@type table<uint?, catenary_network_data?> A mapping of `electric_network_id` to catenary network data <br>
  --- if an electric network doesn't have a transformer on any surface (i.e. it's headless), this will be nil
  global.catenary_networks = global.catenary_networks or {}
  --- note that the key is of type integer, it cannot be nil (the ? is just there because otherwise sumneko-lua doesn't properly infer the type from indexing)

  -- mapping of `unit_number` to 8-way direction
  ---@type table<uint, integer>
  global.pole_directions = global.pole_directions or {}

  -- riding_state needs 1 tick to update, or 2 if the train state changed to on_the_path
  ---@type train_data[]
  global.next_tick_train_state_changes = global.next_tick_train_state_changes or {}
  ---@type train_data[]
  global.second_next_tick_train_state_changes = global.second_next_tick_train_state_changes or {}

  -- mapping from player index to player's "show rail power visualization" toggle
  ---@type { [uint]: boolean? }
  global.show_rail_power = global.show_rail_power or {}

  -- Compatability with picker dollies
  if remote.interfaces["PickerDollies"] then
    remote.call("PickerDollies", "add_blacklist_name", "oe-catenary-pole")
    remote.call("PickerDollies", "add_blacklist_name", "oe-catenary-pole-graphics")
    remote.call("PickerDollies", "add_blacklist_name", "oe-transformer")
    remote.call("PickerDollies", "add_blacklist_name", "oe-transformer-graphics")
    remote.call("PickerDollies", "add_blacklist_name", "oe-locomotive-interface")
  end
end

script.on_init(initalize)
script.on_configuration_changed(initalize)



-- [[ testing stuff ]] --

---@param entity LuaEntity
---@param text string|number
---@param color table?
local function highlight(entity, text, color)
  ---@diagnostic disable-next-line: assign-type-mismatch
  rendering.draw_circle{color = color or {1, 0.7, 0, 1}, radius = 0.5, width = 2, filled = false, target = entity, surface = entity.surface, only_in_alt_mode = true}
  rendering.draw_text{color = color or {1, 0.7, 0, 1}, text = text, target = entity, surface = entity.surface, only_in_alt_mode = true}
end

---@param surface LuaSurface
local function show_rails(surface)
  rendering.clear(script.mod_name)
  local all_rails = surface.find_entities_filtered{
    type = {"straight-rail", "curved-rail"}
  }
  for _, rail in pairs(all_rails) do
    local pole = global.pole_powering_rail[rail.unit_number]
    if pole then
      highlight(rail, pole.electric_network_id, {0, 1, 1})
    end
  end
end

commands.add_command("oe-debug", {"mod-name.overhead-electrification"}, function(command)
  ---@type LuaPlayer
  local player = game.players[command.player_index]

  local options
  if command.parameter then
    options = util.split(command.parameter, " ")
  else
    player.print("commands: all, march, find_poles, next_rail, update_train, show_rails, clear, initalize, rebucket_trains")
    return
  end

  local subcommand = options[1]
  if subcommand == "clear" then
    rendering.clear(script.mod_name)
    return
  elseif subcommand == "initalize" then
    initalize()
    return
  elseif subcommand == "rebucket_trains" then
    rebucket_trains()
    return
  elseif subcommand == "update_train" then
    TrainManager.update_train(global.trains[player.selected.train.id])
    return
  end

  if subcommand == "show_rails" then
    local toggle = options[2]
    if toggle == "on" then
      global.show_rail_power[player.index] = true
    elseif toggle == "off" then
      global.show_rail_power[player.index] = false
    elseif toggle then
      player.print("invalid option: " .. tostring(toggle))
      player.print("usage: /oe-debug show_rails <toggle_constant>")
    else
      show_rails(player.surface)
    end
    return
  end

  if subcommand ~= "find_poles" and subcommand ~= "all" and subcommand ~= "next_rail" and subcommand ~= "march" then
    player.print("unknown command")
    return
  end

  local rail = player.selected
  if not (rail and rail.valid and (rail.type == "straight-rail" or rail.type == "curved-rail")) then
    player.print("hover over a rail to use this command")
    return
  end

  if subcommand == "march" then
    local direction = tonumber(options[2])
    local distance = tonumber(options[3])
    local network_id = tonumber(options[4])
    if not direction or not distance then
      player.print("invalid option: " .. tostring(direction) .. " " .. tostring(distance))
      player.print("usage: /oe-debug march_to_connect <direction> <distance> [network_id]")
      return
    end
    local path = {}
    local on_pole = function(pole, current_path, current_distance)
      game.print("  on_pole: pole=" .. pole.unit_number .. ", path=" .. serpent.line(current_path) .. ", distance=" .. current_distance)
    end
    local on_end = function(current_path)
      game.print("  on_end: path=" .. serpent.line(current_path))
    end
    RailMarcher.march_rail(rail, direction, path, distance, on_pole, on_end, network_id)

    --
  elseif subcommand == "find_poles" then
    local poles, other_poles = RailMarcher.find_adjacent_poles(rail, {1, 1, 0, 0.5}, false)  --[[@as(LuaEntity[])]]  -- in not single mode this always returns arrays

    for i, pole in pairs(poles) do
      player.print("found #" .. i .. ": " .. pole.name)
      highlight(pole, i, {0, 1, 0})
    end

    if other_poles then
      for i, pole in pairs(other_poles) do
        player.print("found other #" .. i .. ": " .. pole.name)
        highlight(pole, i, {0, 0, 1})
      end
    end

    --
  elseif subcommand == "all" then
    local poles = RailMarcher.find_all_poles(rail, player.surface.find_entities_filtered{name = "oe-catenary-pole", limit = 1, position = player.position, radius = 1}[0])

    if poles then
      for i, pole in pairs(poles) do
        player.print("found #" .. i .. ": " .. pole.name)
        highlight(pole, i, {0, 1, 0})
      end
    else
      player.print("other pole too close")
    end

    --
  elseif subcommand == "next_rail" then
    local direction = tonumber(options[2])
    local connection = tonumber(options[3])
    if not direction or not connection then
      player.print("invalid options: " .. tostring(direction) .. " " .. tostring(connection))
      player.print("usage: /oe-debug next_rail <direction> <connection>")
      return
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    local next_rail = RailMarcher.get_next_rail(rail, direction, connection)
    if next_rail then
      player.teleport(next_rail.position)
    else
      player.print("no rail found")
    end
  end
end)
