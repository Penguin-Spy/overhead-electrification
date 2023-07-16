--[[ control.lua © Penguin_Spy 2023
  Event handlers & updating/tracking of locomotive power
]]
---@class locomotive_data
---@field locomotive LuaEntity The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil
---@field network_id uint      the id of the catenary network this locomotive is attached to
---@field is_powered boolean   is this locomotive currently powered

---@class catenary_network_data
---@field transformer LuaEntity   The transformer powering this catenary network
---@field electric_network_id uint

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


---@param event EventData.on_built_entity|EventData.script_raised_built
local function on_entity_created(event)
  local entity = event.created_entity or event.entity

  -- name of the entity this placer is placing, or nil if not a placer
  local placer_target = string.match(entity.name, "^(oe%-.-)%-placer$")

  if placer_target then  -- all placers are for catenary poles
    game.print("catenary_utils converting " .. entity.name .. " to " .. placer_target)
    entity = catenary_utils.handle_placer(entity, placer_target)
  end

  -- the real entity actually got built, run on_build code for them

  -- catenary poles: check if valid space, check if can create pole connections
  if catenary_utils.is_pole(entity) then
    local reason = catenary_utils.on_pole_placed(entity)
    if reason then
      cancel_entity_creation(entity, event, {"cant-build-reason." .. reason})
      return
    end

    -- any rails: check catenary pole connections.  checking type makes this work with other mods' rails
  elseif entity.type == "straight-rail" or entity.type == "curved-rail" then
    catenary_utils.on_rail_placed(entity)

    -- locomotive: create locomotives table entry
  elseif entity.name == "oe-electric-locomotive" then
    global.locomotives[entity.unit_number] = {
      locomotive = entity,
      is_powered = false
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

local FRONT = defines.rail_direction.front
local BACK = defines.rail_direction.back

local STATE_COLORS = {
  [defines.train_state.on_the_path]         = {0, 1, 0, 0.5},      -- green       accelerating/maintaining speed
  [defines.train_state.path_lost]           = {1, 1, 0, 0.5},      -- yellow?     unknown
  [defines.train_state.no_schedule]         = {1, 1, 1, 0.5},      -- white       stopped  -- overrides manual_control_stop
  [defines.train_state.no_path]             = {1, 0, 0, 0.5},      -- red         stopped
  [defines.train_state.arrive_signal]       = {0, 1, 1, 0.5},      -- cyan        braking
  [defines.train_state.wait_signal]         = {0, 0, 1, 0.5},      -- blue        stopped
  [defines.train_state.arrive_station]      = {0, 1, 1, 0.5},      -- cyan        braking
  [defines.train_state.wait_station]        = {0, 0, 1, 0.5},      -- blue        stopped
  [defines.train_state.manual_control_stop] = {0, 1, 1, 0.5},      -- cyan        braking
  [defines.train_state.manual_control]      = {0, 0.5, 0, 0.5},    -- dark green  <varies> -- have to check current speed i guess (>0 = consume power)
  [defines.train_state.destination_full]    = {0.5, 0, 0.5, 0.5},  -- purple      stopped
}


---@param data locomotive_data
local function update_locomotive(data)
  local locomotive = data.locomotive
  local interface = data.interface
  local rails = locomotive.train.get_rails()
  -- TODO: this needs to search if there's any power anywhere in between the front & back of train + a few rails out on each end!
  -- adjust function to search from rail A to rail B, returning network_id if there's exactly 1
  -- or something basically just don't do from whatever the first rail in the list is
  local front_network = rail_march.get_network_in_direction(rails[1], FRONT)
  local back_network = rail_march.get_network_in_direction(rails[1], BACK)
  local cached_network = data.network_id

  --game.print("front: " .. (front_network or "nil") .. " back: " .. (back_network or "nil") .. " cached: " .. (cached_network or "nil"))

  -- check network
  if front_network and front_network == back_network then
    -- if we were in a different network
    if cached_network and cached_network ~= front_network then
      game.print("joining new network " .. front_network)
      local network = global.catenary_networks[front_network]
      -- join this one instead
      ---@diagnostic disable-next-line: need-check-nil if we have a cached network this will always be not nil
      interface.teleport(network.transformer.position)
      data.network_id = front_network

      -- if we don't have a network we join the new one
    elseif not cached_network then
      game.print("joining network")
      local network = global.catenary_networks[front_network]
      data.network_id = front_network

      interface = locomotive.surface.create_entity{
        name = "oe-locomotive-interface",
        position = network.transformer.position,
        force = locomotive.force
      }
      data.interface = interface
    end
  elseif cached_network then  -- make sure we're not in a network
    game.print("leaving network")
    if interface then interface.destroy() end
    interface = nil
    data.interface = nil
    data.network_id = nil
    locomotive.burner.currently_burning = nil
  end

  -- update fuel

  -- if we have an interface that's full
  if interface and interface.energy >= interface.electric_buffer_size then
    if not data.is_powered then  -- , and we aren't powered,
      -- become powered
      local burner = locomotive.burner
      game.print("has enough energy")
      ---@diagnostic disable-next-line: assign-type-mismatch this is literally just wrong, this does work
      burner.currently_burning = "oe-internal-fuel"
      burner.remaining_burning_fuel = 10 ^ 24
      data.is_powered = true
    end

    -- if we are powered but we shouldn't be
  elseif data.is_powered then
    -- become unpowered
    local burner = locomotive.burner
    game.print("not enough energy")
    burner.currently_burning = nil
    data.is_powered = false
  end

  -- debug: color based on state
  locomotive.color = STATE_COLORS[locomotive.train.state]
end


-- [[ Catenary network updating ]]

-- this sucks but it's 1am i'll figure out something better later
---@param catenary_network_data catenary_network_data
local function update_catenary_network(catenary_id, catenary_network_data)
  local transformer = catenary_network_data.transformer
  local cached_electric_id = catenary_network_data.electric_network_id
  local current_electric_id = transformer.electric_network_id

  -- network changed
  if current_electric_id and current_electric_id ~= cached_electric_id then
    game.print("network changed from " .. cached_electric_id .. " to " .. current_electric_id)
    global.electric_network_lookup[cached_electric_id] = nil
    global.electric_network_lookup[current_electric_id] = catenary_id
    catenary_network_data.electric_network_id = current_electric_id
  end
end



-- todo: use event.tick, modulo, and a limit number to only update n locomotives per tick
---      make the limit a map setting
---@param event EventData.on_tick
local function on_tick(event)
  -- ew, really need to find a set of suitable event handlers for this if possible
  for id, catenary_network_data in pairs(global.catenary_networks) do
    update_catenary_network(id, catenary_network_data)
  end

  for _, locomotive_data in pairs(global.locomotives) do
    update_locomotive(locomotive_data)
  end

  for i, pole in pairs(global.queued_network_changes) do
    if pole.valid then
      game.print("queued recursive update of " .. pole.unit_number)
      catenary_utils.recursively_update_network(pole, global.electric_network_lookup[pole.electric_network_id])
    else
      game.print("queued recursive update of not valid pole.")
    end
    global.queued_network_changes[i] = nil
  end
end

script.on_event(defines.events.on_tick, on_tick)



-- [[ Initalization ]] --

-- called when added to a save, game start, or on_configuration_changed
local function initalize()
  ---@type locomotive_data[] A mapping of unit_number to locomotive data
  global.locomotives = global.locomotives or {}
  ---@type catenary_network_data[] A mapping of network_id to catenary network data
  global.catenary_networks = global.catenary_networks or {}

  -- map of electric_network_id to catenary network_id <br>
  -- used for determining what network a pole is in
  -- updated when electric network of transformer changes
  global.electric_network_lookup = global.electric_network_lookup or {}

  -- map of rail LuaEntity.unit_number to catenary network_id
  -- used for determining locomotive power
  -- updated when poles are placed/removed
  global.rail_number_lookup = global.rail_number_lookup or {}

  -- list of poles who's electric network may have changed and needs checking
  -- used to update pole catenary networks after one is destroyed
  global.queued_network_changes = global.queued_network_changes or {}
end

-- called every time the game loads. cannot access the game object or global table
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
---@param text string|number
---@param color table?
---@diagnostic disable-next-line: lowercase-global
function highlight(entity, text, color)
  ---@diagnostic disable-next-line: assign-type-mismatch
  rendering.draw_circle{color = color or {1, 0.7, 0, 1}, radius = 0.5, width = 2, filled = false, target = entity, surface = entity.surface, only_in_alt_mode = true}
  rendering.draw_text{color = color or {1, 0.7, 0, 1}, text = text, target = entity, surface = entity.surface, only_in_alt_mode = true}
end

commands.add_command("oe-debug", {"mod-name.overhead-electrification"}, function(command)
  ---@type LuaPlayer
  local player = game.players[command.player_index]

  local options
  if command.parameter then
    options = util.split(command.parameter, " ")
  else
    game.print("commands: all, find, update_loco, show_rails, clear, initalize")
    return
  end

  local subcommand = options[1]
  if subcommand == "clear" then
    rendering.clear(script.mod_name)
    return
  elseif subcommand == "initalize" then
    initalize()
    return
  end

  if subcommand == "update_loco" then
    update_locomotive(global.locomotives[game.player.selected.unit_number])
    return
  end

  if subcommand == "show_rails" then
    rendering.clear(script.mod_name)
    local all_rails = player.surface.find_entities_filtered{
      type = {"straight-rail", "curved-rail"}
    }
    for _, rail in pairs(all_rails) do
      local id = global.rail_number_lookup[rail.unit_number]
      if id then
        highlight(rail, id, {0, 1, 1})
      end
    end
    return
  end

  local rail = player.selected
  if not (rail and rail.valid and (rail.type == "straight-rail" or rail.type == "curved-rail")) then
    player.print("hover over a rail to use this command")
    return
  end

  if subcommand == "all" then
    local nearby_poles, far_poles = rail_march.find_all_poles(rail)

    for i, pole in pairs(nearby_poles) do
      game.print("found #" .. i .. ": " .. pole.name)
      highlight(pole, i, {0, 1, 0})
    end
    for i, pole in pairs(far_poles) do
      game.print("found #" .. i .. ": " .. pole.name)
      highlight(pole, i, {1, 0, 0})
    end
  elseif subcommand == "find" then
    ---@diagnostic disable-next-line: param-type-mismatch
    local network_id = rail_march.get_network_in_direction(rail, tonumber(options[2]))
    game.print("found: " .. (network_id or "no network"))
  else
    game.print("unknown command")
  end
end)
