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


return update_locomotive
