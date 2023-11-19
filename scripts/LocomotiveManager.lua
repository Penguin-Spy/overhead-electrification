--[[ LocomotiveManager.lua © Penguin_Spy 2023
  Manages state electric locomotives
]]
local const = require 'constants'
local LocomotiveManager = {}

-- Global table storage for locomotive data
---@class locomotive_data
---@field locomotive LuaEntity The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil if not connected
---@field electric_network_id uint?     The id of the electric network this locomotive is attached to, or nil if not connected
---@field power_state number   0 = stopped, 1 = moving, 2 = braking, 3 = manual (varies)
---@field is_burning boolean   Is this locomotive currently powered (burner has fuel)


-- Constants to minimize table derefrences during update_locomotive
-- not quite sure how necessary this is but i don't think it can hurt
-- factorio uses lua 5.2, so no <const> attribute :/

local FRONT = defines.rail_direction.front
local BACK  = defines.rail_direction.back


local TRAIN_STATE_MANUAL_CONTROL = defines.train_state.manual_control
local RIDING_STATE_ACCELERATING  = defines.riding.acceleration.accelerating
local RIDING_STATE_BRAKING       = defines.riding.acceleration.braking
local RIDING_STATE_REVERSING     = defines.riding.acceleration.reversing
local RIDING_STATE_NOTHING       = defines.riding.acceleration.nothing


---@alias PowerState
---| 0 POWER_STATE_STOPPED
---| 1 POWER_STATE_MOVING
---| 2 POWER_STATE_BRAKING
---| 3 POWER_STATE_MANUAL
local POWER_STATE_STOPPED = 0
local POWER_STATE_MOVING  = 1
local POWER_STATE_BRAKING = 2
local POWER_STATE_MANUAL  = 3


local BUFFER_CAPACITY          = const.LOCOMOTIVE_POWER * 1000
local POWER_USAGE              = const.LOCOMOTIVE_POWER * 1000 / 60
local REGEN_BRAKING_PRODUCTION = POWER_USAGE
local YOTTAJOULE               = 10 ^ 24  -- 1000000000000000000000000


local STATE_COLORS = {
  [POWER_STATE_STOPPED] = {0, 0, 1, 0.5},    -- blue        0 stopped
  [POWER_STATE_MOVING]  = {0, 1, 0, 0.5},    -- green       1 accelerating/maintaining speed
  [POWER_STATE_BRAKING] = {0, 1, 1, 0.5},    -- cyan        2 braking
  [POWER_STATE_MANUAL]  = {0, 0.5, 0, 0.5},  -- dark green  3 <varies> -- have to check current speed i guess (>0 = consume power)
}

---@param locomotive LuaEntity
function LocomotiveManager.on_locomotive_placed(locomotive)
  global.locomotives[locomotive.unit_number] = {
    locomotive = locomotive,
    is_burning = false,
    power_state = POWER_STATE_MANUAL  -- always in manual when first placed
  }
end

---@param locomotive LuaEntity
function LocomotiveManager.on_locomotive_removed(locomotive)
  local locomotive_data = global.locomotives[locomotive.unit_number]
  local interface = locomotive_data.interface
  if interface and interface.valid then  -- may be nil if loco wasn't in a network (or invalid if deleted somelsehow)
    interface.destroy()
  end
  global.locomotives[locomotive.unit_number] = nil
end


-- sets the `power_usage` and `power_production` of the interface to the appropriate value for the power_state <br>
---@param interface LuaEntity
---@param power_state PowerState
local function set_interface_power(interface, power_state)
  if power_state == POWER_STATE_MOVING then
    interface.power_usage = POWER_USAGE
    interface.power_production = 0
  elseif power_state == POWER_STATE_STOPPED then  -- also used by locomotives facing backwards that aren't helping the train accelerate
    interface.power_usage = 0
    interface.power_production = 0
  elseif power_state == POWER_STATE_BRAKING then
    interface.power_usage = 0
    -- TODO: check if force has regen braking researched (what level if multiple levels?)
    -- use the force of the interface entity
    -- also can't use this interface bc it's usage priority is "secondary-input"
    --interface.power_production = REGEN_BRAKING_PRODUCTION
  else  -- POWER_STATE_MANUAL
    interface.power_usage = 0
    interface.power_production = 0
    -- TODO: if speed > 0 consume power (or speed > speed last update?)
    -- would need to run this part in update_locomotive
    -- wait i could probably use the train.riding_state (.acceleration) to know what the player is doing (still in update_locomotive)
  end
end

---@param locomotive LuaEntity
---@param power_state PowerState
local function set_locomotive_power_state(locomotive, power_state)
  if locomotive.name == "oe-electric-locomotive" then
    local data = global.locomotives[locomotive.unit_number]
    local interface = data.interface

    -- debug: color based on state
    locomotive.color = STATE_COLORS[power_state]

    -- update consumption/production of interface
    if interface and interface.valid and power_state ~= data.power_state then
      --game.print("switching to " .. power_state .. " (was " .. data.power_state .. ")")
      set_interface_power(interface, power_state)
      data.power_state = power_state
    end
  end
end

-- updates the power_state & interface power fields of each locomotive in the train
---@param train LuaTrain
function LocomotiveManager.on_train_changed_state(train)
  local acceleration = train.riding_state.acceleration
  local front_state, back_state
  if train.state == TRAIN_STATE_MANUAL_CONTROL then
    front_state = POWER_STATE_MANUAL
    back_state = POWER_STATE_MANUAL
  elseif acceleration == RIDING_STATE_ACCELERATING then
    front_state = POWER_STATE_MOVING
    back_state = POWER_STATE_STOPPED
  elseif acceleration == RIDING_STATE_REVERSING then
    front_state = POWER_STATE_STOPPED
    back_state = POWER_STATE_MOVING
  elseif acceleration == RIDING_STATE_BRAKING then
    front_state = POWER_STATE_BRAKING
    back_state = POWER_STATE_BRAKING
  elseif acceleration == RIDING_STATE_NOTHING then
    front_state = POWER_STATE_STOPPED
    back_state = POWER_STATE_STOPPED
  end

  --game.print("riding state: " .. acceleration .. "  front_state: " .. front_state .. "  back_state: " .. back_state)

  for _, locomotive in pairs(train.locomotives.front_movers) do
    set_locomotive_power_state(locomotive, front_state)
  end
  for _, locomotive in pairs(train.locomotives.back_movers) do
    set_locomotive_power_state(locomotive, back_state)
  end
end


-- handles updating the network/burning state of an individual locomotive
---@param data locomotive_data
function LocomotiveManager.update_locomotive(data)
  local locomotive = data.locomotive
  local interface = data.interface
  local surface = locomotive.surface

  -- get the closest rail of all the rails under this train
  local rail_under_locomotive = surface.get_closest(locomotive.position, locomotive.train.get_rails())
  if not rail_under_locomotive then
    error("no rail under locomotive?")
  end
  local pole = global.pole_powering_rail[rail_under_locomotive.unit_number]
  local current_network_id = pole and pole.valid and pole.electric_network_id or nil
  local cached_network_id = data.electric_network_id

  -- check network
  if current_network_id then
    -- if we were in a different network (or no network)
    if not cached_network_id or cached_network_id ~= current_network_id then
      game.print("joining network " .. current_network_id)
      local network = global.catenary_networks[current_network_id]
      data.electric_network_id = current_network_id

      if interface and interface.valid then  -- if we have an interface
        if not network then                  -- and new network is headless, destroy it
          interface.destroy(); interface = nil
        else                                 -- and new network is headfull, teleport it
          interface.teleport(network.transformers[surface.index][1].position)
        end
      else               -- if we don't have an interface
        if network then  -- and new network is headfull, create one
          interface = locomotive.surface.create_entity{
            name = "oe-locomotive-interface",
            position = network.transformers[surface.index][1].position,
            force = locomotive.force
          }
          if not (interface and interface.valid) then error("creating locomotive interface failed unexpectedly") end
          data.interface = interface
          set_interface_power(interface, data.power_state)
        end
      end
    end
  elseif cached_network_id then  -- make sure we're not in a network
    game.print("leaving network")
    if interface then interface.destroy() end
    interface = nil
    data.interface = nil
    data.electric_network_id = nil
  end

  -- can't be powered, remove fuel & stop processing
  if not interface then  -- we don't really care what state the loco is in, it's not powered
    locomotive.burner.currently_burning = nil
    data.is_burning = false
    return
  end


  -- update fuel

  -- if we have an interface that's full
  if interface.energy >= interface.electric_buffer_size then
    if not data.is_burning then  -- and we aren't powered,
      -- become powered
      local burner = locomotive.burner
      game.print("has enough energy")
      ---@diagnostic disable-next-line: assign-type-mismatch this is literally just wrong, this does work
      burner.currently_burning = "oe-internal-fuel"
      burner.remaining_burning_fuel = YOTTAJOULE
      data.is_burning = true
    end

    -- if we are powered but we shouldn't be
  elseif data.is_burning then
    -- become unpowered
    local burner = locomotive.burner
    game.print("not enough energy")
    burner.currently_burning = nil
    data.is_burning = false
  end
end


return LocomotiveManager
