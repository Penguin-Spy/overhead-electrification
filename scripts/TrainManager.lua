--[[ TrainManager.lua © Penguin_Spy 2023
  Keeps track of trains with electric locomotives and updates them
]]
local TrainManager               = {}
local const                      = require 'constants'

-- Global table storage for train data
---@class train_data
---@field train LuaTrain                    the LuaTrain for this data
---@field id    uint                        the LuaTrain's id
---@field electric_front_movers LuaEntity[] an array of just the electric locomotive front_movers
---@field electric_back_movers LuaEntity[]  an array of just the electric locomotive back_movers
---@field bucket integer which train bucket this train_data is in

-- Global table storage for individual locomotive data
---@class locomotive_data
---@field locomotive LuaEntity The locomotive this data is for
---@field interface LuaEntity? The `electric-energy-interface` this locomotive is using to connect to the electrical network, or nil if not connected
---@field electric_network_id uint?     The id of the electric network this locomotive is attached to, or nil if not connected
---@field power_state PowerState   0 = stopped, 1 = moving, 2 = braking
---@field is_burning boolean   Is this locomotive currently powered (burner has fuel)

-- Constants to minimize table derefrences during update_locomotive
-- not quite sure how necessary this is but i don't think it can hurt
-- factorio uses lua 5.2, so no <const> attribute :/

local TRAIN_STATE_MANUAL_CONTROL = defines.train_state.manual_control
local RIDING_STATE_ACCELERATING  = defines.riding.acceleration.accelerating
local RIDING_STATE_BRAKING       = defines.riding.acceleration.braking
local RIDING_STATE_REVERSING     = defines.riding.acceleration.reversing
local RIDING_STATE_NOTHING       = defines.riding.acceleration.nothing


---@alias PowerState
---| 0 POWER_STATE_NEUTRAL
---| 1 POWER_STATE_MOVING
---| 2 POWER_STATE_BRAKING
local POWER_STATE_NEUTRAL = 0  -- stopped or a mover in the opposite direction of current travel
local POWER_STATE_MOVING  = 1  -- a mover in the current direction of travel
local POWER_STATE_BRAKING = 2  -- all locomotives contribute to braking


--local POWER_USAGE              = const.LOCOMOTIVE_POWER * 1000 / 60
--local REGEN_BRAKING_PRODUCTION = POWER_USAGE
local YOTTAJOULE = 10 ^ 24  -- 1000000000000000000000000


local function remove_train(train_id)
  -- may have already been removed (if splitting a train)
  if not global.trains[train_id] then return end

  -- remove train from bucket
  local bucket = global.trains[train_id].bucket
  global.trains[train_id] = nil
  util.remove_from_list(global.train_buckets[bucket], train_id)

  -- remove train from state change queue
  for i, train_data in pairs(global.next_tick_train_state_changes) do
    if train_data.id == train_id then
      global.next_tick_train_state_changes[i] = nil
    end
  end
  for i, train_data in pairs(global.second_next_tick_train_state_changes) do
    if train_data.id == train_id then
      global.second_next_tick_train_state_changes[i] = nil
    end
  end
end

-- [[ Event handlers ]]

-- handles the `on_train_created` event
---@param event EventData.on_train_created
function TrainManager.on_train_created(event)
  -- remove entries for merged trains
  if event.old_train_id_1 then
    remove_train(event.old_train_id_1)
  end
  if event.old_train_id_2 then
    remove_train(event.old_train_id_2)
  end

  local train = event.train

  local electric_front_movers = {}
  local electric_back_movers = {}

  -- check if the current train has any electric locomotives, and add them to the lists
  local has_electric_locomotive = false
  for _, locomotive in pairs(train.locomotives.front_movers) do
    if identify.is_locomotive(locomotive) then
      has_electric_locomotive = true
      table.insert(electric_front_movers, locomotive)
    end
  end
  for _, locomotive in pairs(train.locomotives.back_movers) do
    if identify.is_locomotive(locomotive) then
      has_electric_locomotive = true
      table.insert(electric_back_movers, locomotive)
    end
  end

  -- if so, add this to our list of trains
  if has_electric_locomotive then
    global.trains[train.id] = {
      train = train,
      id = train.id,
      electric_front_movers = electric_front_movers,
      electric_back_movers = electric_back_movers,
      bucket = global.train_next_bucket
    }
    table.insert(global.train_buckets[global.train_next_bucket], train.id)
    global.train_next_bucket = global.train_next_bucket + 1
    if global.train_next_bucket > #global.train_buckets then
      global.train_next_bucket = 1
    end
  end
end

-- handles the `on_train_state_changed` event
---@param event EventData.on_train_changed_state
function TrainManager.on_train_state_changed(event)
  local train = event.train
  -- train.riding_state updates on the next tick, or after 2 ticks if the train state changed to on_the_path
  if train.state == defines.train_state.on_the_path then
    table.insert(global.second_next_tick_train_state_changes, global.trains[train.id])
  else
    table.insert(global.next_tick_train_state_changes, global.trains[train.id])
  end
end


-- creates the data for this individual locomotive
---@param locomotive LuaEntity
function TrainManager.on_locomotive_placed(locomotive)
  global.locomotives[locomotive.unit_number] = {
    locomotive = locomotive,
    is_burning = false,
    power_state = POWER_STATE_NEUTRAL  -- always in manual when first placed
  }
  -- on_train_created handles adding this locomotive to the global.trains entry
end

-- removes the data for this individual locomotive
---@param locomotive LuaEntity
function TrainManager.on_locomotive_removed(locomotive)
  -- remove global.locomotives table entry
  local interface = global.locomotives[locomotive.unit_number].interface
  if interface and interface.valid then  -- may be nil if loco wasn't in a network (or invalid if deleted somelsehow)
    interface.destroy()
  end
  global.locomotives[locomotive.unit_number] = nil

  -- remove self from global.trains entry
  local train_data = global.trains[locomotive.train.id]
  util.remove_from_list(train_data.electric_front_movers, locomotive)
  util.remove_from_list(train_data.electric_back_movers, locomotive)
end

-- removes the global train data entry if this was the last rolling stock in the train
---@param entity LuaEntity
function TrainManager.on_rolling_stock_removed(entity)
  if #entity.train.carriages == 1 then
    remove_train(entity.train.id)
  end
end


-- [[ updating methods ]]


-- sets the `power_usage` and `power_production` of the interface to the appropriate value for the power_state
---@param interface LuaEntity
---@param power_state PowerState
---@param power_usage integer
local function set_interface_power(interface, power_state, power_usage)
  if power_state == POWER_STATE_MOVING then
    interface.power_usage = power_usage
    --interface.power_production = 0
  elseif power_state == POWER_STATE_NEUTRAL then
    interface.power_usage = 0
    --interface.power_production = 0
  elseif power_state == POWER_STATE_BRAKING then
    interface.power_usage = 0
    -- TODO: check if force has regen braking researched (what level if multiple levels?)
    -- use the force of the interface entity
    -- also can't use this interface bc it's usage priority is "secondary-input"
    --interface.power_production = power_usage * 0.4
  end
end

---@param locomotive LuaEntity
---@param power_state PowerState
local function set_locomotive_power_state(locomotive, power_state)
  local data = global.locomotives[locomotive.unit_number]
  local interface = data.interface

  -- update consumption/production of interface
  if interface and interface.valid and power_state ~= data.power_state then
    set_interface_power(interface, power_state, locomotive.prototype.max_energy_usage)
    data.power_state = power_state
  end
end

-- runs after the train's state changes and once its riding_state has updated <br>
-- updates the power_state & interface power fields of each locomotive in the train
---@param train_data train_data
local function update_train_power_state(train_data)
  local acceleration = train_data.train.riding_state.acceleration
  local front_state, back_state
  if acceleration == RIDING_STATE_ACCELERATING then
    front_state, back_state = POWER_STATE_MOVING, POWER_STATE_NEUTRAL
  elseif acceleration == RIDING_STATE_REVERSING then
    front_state, back_state = POWER_STATE_NEUTRAL, POWER_STATE_MOVING
  elseif acceleration == RIDING_STATE_BRAKING then
    front_state, back_state = POWER_STATE_BRAKING, POWER_STATE_BRAKING
  else  -- acceleration == RIDING_STATE_NOTHING
    front_state, back_state = POWER_STATE_NEUTRAL, POWER_STATE_NEUTRAL
  end

  for i = 1, #train_data.electric_front_movers do
    set_locomotive_power_state(train_data.electric_front_movers[i], front_state)
  end
  for i = 1, #train_data.electric_back_movers do
    set_locomotive_power_state(train_data.electric_back_movers[i], back_state)
  end
end
TrainManager.update_train_power_state = update_train_power_state


-- handles updating the network/burning state of an individual locomotive
---@param data locomotive_data
---@param rails LuaEntity[]
local function update_locomotive(data, rails)
  local locomotive = data.locomotive
  local interface = data.interface
  local surface = locomotive.surface

  -- get the closest rail of all the rails under this train
  local rail_under_locomotive = surface.get_closest(locomotive.position, rails)
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
      local network = global.catenary_networks[current_network_id]
      data.electric_network_id = current_network_id

      if interface and interface.valid then  -- if we have an interface
        if not network then                  -- and new network is headless, destroy it
          interface.destroy()
          interface = nil
          data.interface = nil
        else  -- and new network is headfull, teleport it (to whichever the first transformer is)
          interface.teleport(network.transformers[1].position)
        end
      else               -- if we don't have an interface
        if network then  -- and new network is headfull, create one (at whichever the first transformer is)
          interface = locomotive.surface.create_entity{
            name = locomotive.name .. "-oe-interface",
            position = network.transformers[1].position,
            force = locomotive.force
          }
          if not (interface and interface.valid) then error("creating locomotive interface failed unexpectedly") end
          data.interface = interface
          set_interface_power(interface, data.power_state, locomotive.prototype.max_energy_usage)
        end
      end
    end
  elseif cached_network_id then  -- make sure we're not in a network
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

  -- if we have an interface that's full
  if interface.energy >= interface.electric_buffer_size then
    if not data.is_burning then  -- and we aren't powered, become powered
      local burner = locomotive.burner
      ---@diagnostic disable-next-line: assign-type-mismatch this is literally just wrong, this does work
      burner.currently_burning = "oe-internal-fuel"
      burner.remaining_burning_fuel = YOTTAJOULE
      data.is_burning = true
    end

    -- if we are powered but we shouldn't be
  elseif data.is_burning then
    -- become unpowered
    locomotive.burner.currently_burning = nil
    data.is_burning = false
  end
end


-- updates all electric locomotives in a train
---@param train_data train_data
function TrainManager.update_train(train_data)
  local train = train_data.train
  -- if in manual mode, convert power state to normal ones for locomotives
  if train.state == TRAIN_STATE_MANUAL_CONTROL then
    update_train_power_state(train_data)
  end

  local rails = train.get_rails()
  local front_movers = train_data.electric_front_movers
  local back_movers = train_data.electric_front_movers
  for i = 1, #front_movers do
    update_locomotive(global.locomotives[front_movers[i].unit_number], rails)
  end
  for i = 1, #train_data.electric_back_movers do
    update_locomotive(global.locomotives[back_movers[i].unit_number], rails)
  end
end


return TrainManager
