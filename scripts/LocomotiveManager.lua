--[[ LocomotiveManager.lua © Penguin_Spy 2023
  Manages state electric locomotives
]]
local const = require 'constants'
local LocomotiveManager = {}

-- Global table storage for locomotive data
---@class locomotive_data
---@field locomotive LuaEntity The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil if not connected
---@field network_id uint?     The id of the catenary network this locomotive is attached to, or nil if not connected
---@field power_state number   0 = stopped, 1 = moving, 2 = braking, 3 = manual (varies)
---@field is_burning boolean   Is this locomotive currently powered (burner has fuel)


-- Constants to minimize table derefrences during update_locomotive
-- not quite sure how necessary this is but i don't think it can hurt
-- factorio uses lua 5.2, so no <const> attribute :/

local FRONT = defines.rail_direction.front
local BACK = defines.rail_direction.back

local TRAIN_STATE_ON_THE_PATH = defines.train_state.on_the_path
local TRAIN_STATE_PATH_LOST = defines.train_state.path_lost
local TRAIN_STATE_NO_SCHEDULE = defines.train_state.no_schedule
local TRAIN_STATE_NO_PATH = defines.train_state.no_path
local TRAIN_STATE_ARRIVE_SIGNAL = defines.train_state.arrive_signal
local TRAIN_STATE_WAIT_SIGNAL = defines.train_state.wait_signal
local TRAIN_STATE_ARRIVE_STATION = defines.train_state.arrive_station
local TRAIN_STATE_WAIT_STATION = defines.train_state.wait_station
local TRAIN_STATE_MANUAL_CONTROL_STOP = defines.train_state.manual_control_stop
local TRAIN_STATE_MANUAL_CONTROL = defines.train_state.manual_control
local TRAIN_STATE_DESTINATION_FULL = defines.train_state.destination_full

local POWER_STATE_STOPPED = 0
local POWER_STATE_MOVING = 1
local POWER_STATE_BRAKING = 2
local POWER_STATE_MANUAL = 3

local BUFFER_CAPACITY = const.LOCOMOTIVE_POWER * 1000
local POWER_USAGE = const.LOCOMOTIVE_POWER * 1000 / 60
local YOTTAJOULE = 10 ^ 24  -- 1000000000000000000000000


local STATE_COLORS = {
  [defines.train_state.on_the_path]         = {0, 1, 0, 0.5},      -- green       1 accelerating/maintaining speed
  [defines.train_state.path_lost]           = {1, 1, 0, 0.5},      -- yellow?     2 unknown, documentation suggests braking
  [defines.train_state.no_schedule]         = {1, 1, 1, 0.5},      -- white       0 stopped  -- overrides manual_control_stop
  [defines.train_state.no_path]             = {1, 0, 0, 0.5},      -- red         0 stopped
  [defines.train_state.arrive_signal]       = {0, 1, 1, 0.5},      -- cyan        2 braking
  [defines.train_state.wait_signal]         = {0, 0, 1, 0.5},      -- blue        0 stopped
  [defines.train_state.arrive_station]      = {0, 1, 1, 0.5},      -- cyan        2 braking
  [defines.train_state.wait_station]        = {0, 0, 1, 0.5},      -- blue        0 stopped
  [defines.train_state.manual_control_stop] = {0, 1, 1, 0.5},      -- cyan        2 braking
  [defines.train_state.manual_control]      = {0, 0.5, 0, 0.5},    -- dark green  3 <varies> -- have to check current speed i guess (>0 = consume power)
  [defines.train_state.destination_full]    = {0.5, 0, 0.5, 0.5},  -- purple      0 stopped
}

---@param locomotive LuaEntity
function LocomotiveManager.on_locomotive_placed(locomotive)
  global.locomotives[locomotive.unit_number] = {
    locomotive = locomotive,
    is_powered = false,
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


---@param data locomotive_data
function LocomotiveManager.update_locomotive(data)
  local locomotive = data.locomotive
  local interface = data.interface
  local rails = locomotive.train.get_rails()
  -- TODO: this needs to search if there's any power anywhere in between the front & back of train + a few rails out on each end!
  -- adjust function to search from rail A to rail B, returning network_id if there's exactly 1
  -- or something basically just don't do from whatever the first rail in the list is
  local front_network = RailMarcher.get_network_in_direction(rails[1], FRONT)
  local back_network = RailMarcher.get_network_in_direction(rails[1], BACK)
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

  -- can't be powered, remove fuel & stop processing
  if not interface then  -- we don't really care what state the loco is in, it's not powered
    locomotive.burner.currently_burning = nil
    if data.is_burning then
      data.is_burning = false
    end
    return
  end

  -- debug: color based on state
  locomotive.color = STATE_COLORS[locomotive.train.state]

  -- update power_state
  local state = locomotive.train.state
  local power_state
  if state == TRAIN_STATE_ON_THE_PATH then  -- checks are roughly ordered by how common they are (so short-circuit evaluation finds the right state faster)
    power_state = POWER_STATE_MOVING
  elseif state == TRAIN_STATE_WAIT_STATION or state == TRAIN_STATE_WAIT_SIGNAL
      or state == TRAIN_STATE_DESTINATION_FULL
      or state == TRAIN_STATE_NO_PATH or state == TRAIN_STATE_NO_SCHEDULE then
    power_state = POWER_STATE_STOPPED
  elseif state == TRAIN_STATE_ARRIVE_SIGNAL or state == TRAIN_STATE_ARRIVE_STATION
      or state == TRAIN_STATE_MANUAL_CONTROL_STOP or state == TRAIN_STATE_PATH_LOST then
    power_state = POWER_STATE_BRAKING
  else  -- TRAIN_STATE_MANUAL_CONTROL
    power_state = POWER_STATE_MANUAL
  end

  -- update consumption/production of interface
  if power_state ~= data.power_state then
    game.print("switching to " .. power_state .. " (was " .. data.power_state .. ")")
    if power_state == POWER_STATE_MOVING then
      interface.power_usage = POWER_USAGE
      interface.power_production = 0
    elseif power_state == POWER_STATE_STOPPED then
      interface.power_usage = 0
    elseif power_state == POWER_STATE_BRAKING then
      interface.power_usage = 0
      -- check if force has regen braking researched (what level if multiple levels?)
    else  -- POWER_STATE_MANUAL
      interface.power_usage = 0
    end
    data.power_state = power_state
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
