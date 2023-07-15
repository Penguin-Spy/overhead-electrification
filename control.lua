--[[ control.lua © Penguin_Spy 2023
  Event handlers & updating/tracking of locomotive power
]]
---@class locomotive_data
---@field locomotive LuaEntity    The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil

---@class catenary_network_data
---@field transformer LuaEntity   The transformer powering this catenary network

util = require 'util'

if script.active_mods["gvv"] then require("__gvv__.gvv")() end

---@param event EventData.on_built_entity|EventData.on_entity_cloned|EventData.script_raised_built
local function on_built(event)
  ---@type LuaEntity
  local entity = event.created_entity or event.entity or event.destination

  local match = string.match(entity.name, "^(oe%-.-)%-placer$")
  --game.print("on_built:" .. event.name .. " built:" .. entity.name .. " match: " .. (match or "nil"))

  if match then  -- note that this only runs when the player places the item. bots building ghosts immediatley places the real entity
    game.print("converting " .. entity.name .. " to " .. match)
    entity.surface.create_entity{
      name = match,
      position = entity.position,
      direction = entity.direction,
      force = entity.force,
      player = entity.last_user,
      raise_built = true  -- runs this handler again with the actual entity being placed
    }
    entity.destroy()
    return
  end

  -- transformer: create catenary network
  if entity.name == "oe-transformer" then
    global.catenary_networks[entity.unit_number] = {
      transformer = entity
    }
  end

  -- locomotive: create locomotives table entry
  if entity.name == "oe-electric-locomotive" then
    global.locomotives[entity.unit_number] = {
      locomotive = entity
    }
  end
end

-- todo: generate filter to only our entities, use it for events in the proper filter format
script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_entity_cloned,
  defines.events.script_raised_built,
  defines.events.script_raised_revive
}, on_built)


---@param event EventData.on_entity_died
local function on_destroyed(event)
  local entity = event.entity

  --game.print("on_destroyed:" .. event.name .. " destroyed:" .. entity.name)

  -- transformer: remove catenary network
  -- TODO: remove locomotive interfaces (could we just delete them? locomotive updating will do a valid check)
  if entity.name == "oe-transformer" then
    global.catenary_networks[entity.unit_number] = nil
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
}, on_destroyed)


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
  ---@type catenary_network_data[] A mapping of network_id to catenary network data
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


commands.add_command("oe-debug", {"mod-name.overhead-electrification"}, function(command)
  local player = game.players[command.player_index]

  local options
  if command.parameter then
    options = util.split(command.parameter, " ")
  else
    game.print("commands: step, find")
    return
  end

  -- consider LuaEntity.get_rail_segment_rails
  if options[1] == "step" then
    local rail = player.selected.get_connected_rail{rail_direction = defines.rail_direction.front, rail_connection_direction = defines.rail_connection_direction.straight}

    -- /c for _, r in pairs((game.player.selected.get_rail_segment_rails(0))) do pcall(r.destroy()) end

    -- (game.player.selected.get_connected_rail{rail_direction=1,rail_connection_direction=1}).destroy()
  elseif options[1] == "find" then
    local target = player.selected or player.character

    local entities = target.surface.find_entities_filtered{position = target.position, radius = tonumber(options[2]) or 10, name = "oe-catenary-pole"}
    for i, pole in ipairs(entities) do
      rendering.draw_circle{color = {1, 0.7, 0, 0.5}, radius = 0.5, width = i, filled = false, target = pole, surface = pole.surface, time_to_live = 240}
    end

    -- need to filter to closest 2 that are on the same rail network
    --  can't do much better without stepping along rails one by one and checking entities (that would be very bad & laggy)
  elseif options[1] == "all" then

  end
end)
