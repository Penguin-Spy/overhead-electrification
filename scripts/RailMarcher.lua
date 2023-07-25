--[[ RailMarcher.lua © Penguin_Spy 2023
  Utilities for finding catenary poles alongside rails
]]

local RailMarcher = {}

-- store these to reduce table dereferences
local STRAIGHT = defines.rail_connection_direction.straight
local LEFT = defines.rail_connection_direction.left
local RIGHT = defines.rail_connection_direction.right
local FRONT = defines.rail_direction.front
local BACK = defines.rail_direction.back

-- directions the straight rails use
local VERTICAL = defines.direction.north   -- front is up, back is down
local HORIZONTAL = defines.direction.east  -- front is right, back is left


-- diagonal rails
-- 1 & 3 go  up  when getting the "front" "straight" rail
local NORTHEAST = defines.direction.northeast
local SOUTHEAST = defines.direction.southeast
-- 5 & 7 go down when getting the "front" "straight" rail
local SOUTHWEST = defines.direction.southwest
local NORTHWEST = defines.direction.northwest


-- joins arrays. modifies `a` in place
---@param a table
---@param b table
local function join(a, b)
  for _, v in pairs(b) do
    a[#a+1] = v
  end
end


-- gets the next rail in the given direction (`FRONT`/`BACK`) & connection direction (`STRAIGHT`/`LEFT`/`RIGHT`) <br>
-- handles diagonal/curved rails (diagonal "front" is always upwards)
---@param rail LuaEntity
---@param direction defines.rail_direction
---@param connection defines.rail_connection_direction
---@return LuaEntity?
local function get_next_rail(rail, direction, connection)
  local entity_direction = rail.direction

  -- straight/diagonal rails
  if rail.type == "straight-rail" then
    if entity_direction == SOUTHWEST or entity_direction == NORTHWEST then
      -- inverts direction so diagonal rails are consistent
      return rail.get_connected_rail{rail_direction = direction == FRONT and BACK or FRONT, rail_connection_direction = connection}
    end
    -- vertical/horizontal or normal diagonal directions
    return rail.get_connected_rail{rail_direction = direction, rail_connection_direction = connection}

    -- curved rails
  else
    return rail.get_connected_rail{rail_direction = direction, rail_connection_direction = connection}
  end
end
RailMarcher.get_next_rail = get_next_rail


-- returns the first pole found whose network_id matches the argument <br>
-- used when updating electric locomotive, so no error checking for performance
---@param rail LuaEntity
---@param rail_dir defines.rail_direction
---@param network_id uint?
---@return uint?
function RailMarcher.get_network_in_direction(rail, rail_dir, network_id)
  -- TODO: implement this
  -- might also change this to use a lookup table indexed by rail unit_numbers for better performance
  -- needs pretty big table in memory, but 0 calls to surface.find_entities_filtered
  local found_network_id = global.rail_number_lookup[rail.unit_number]
  if found_network_id then return found_network_id end

  for i = 1, 7 do
    ---@type LuaEntity
    ---@diagnostic disable-next-line: assign-type-mismatch fuck off
    rail = rail.get_connected_rail{rail_direction = rail_dir, rail_connection_direction = STRAIGHT}
    if rail then  -- see look i'm fucking checking it right here
      found_network_id = global.rail_number_lookup[rail.unit_number]
      if found_network_id then return found_network_id end
    else  -- no more rails
      break
    end
  end
end


-- finds poles next to a single rail
---@param rail LuaEntity
---@return LuaEntity[]
local function find_adjacent_poles(rail, color)
  if rail.type == "straight-rail" then
    rendering.draw_circle{color = color, width = 2, filled = false, target = rail.position, surface = rail.surface, radius = 2, only_in_alt_mode = true}
    return rail.surface.find_entities_filtered{position = rail.position, radius = 2, name = {"oe-catenary-pole", "oe-transformer"}}
  elseif rail.type == "curved-rail" then
    rendering.draw_circle{color = color, width = 2, filled = false, target = rail.position, surface = rail.surface, radius = 1.5, only_in_alt_mode = true}
    game.print("curved rail not implemented")
    return {}
  end
  error("cannot find ajacent poles: '" .. rail.name .. "' is not a straight-rail or curved-rail")
end


-- returns a table of all poles that are next along the rail in the specified direction, as well as the next rail in the `STRAIGHT` direction if it exists
---@param rail LuaEntity
---@param direction defines.rail_direction
---@param straight_color Color
---@return LuaEntity[] poles
---@return LuaEntity? next_straight_rail
local function find_all_next_poles(rail, direction, straight_color)
  local poles = {}

  local next_straight_rail = get_next_rail(rail, direction, STRAIGHT)
  if next_straight_rail then
    join(poles, find_adjacent_poles(next_straight_rail, straight_color))  -- red
  end

  -- check curved rail directions
  local left_rail = get_next_rail(rail, direction, LEFT)
  if left_rail then
    join(poles, find_adjacent_poles(left_rail, {1, 0, 1}))  -- purple
    -- check the next rail after the curve too
    -- TODO: this FRONT might need to change depending on what shape we're coming from
    local direction_of_rail_into_curve = rail.direction
    local direction = direction  -- intentionally redeclaring local direction
    if direction == FRONT and (direction_of_rail_into_curve == HORIZONTAL or direction_of_rail_into_curve == VERTICAL) then
      direction = BACK
    elseif direction == BACK and not (direction_of_rail_into_curve == HORIZONTAL or direction_of_rail_into_curve == VERTICAL) then
      direction = FRONT
    end

    local next_left_rail = get_next_rail(left_rail, direction, STRAIGHT)  -- exiting a curve is always "STRAIGHT"
    if next_left_rail then
      join(poles, find_adjacent_poles(next_left_rail, {0, 1, 1}))         -- cyan
    end
  end

  local right_rail = get_next_rail(rail, direction, RIGHT)
  game.print("rails: " .. tostring(left_rail) .. " " .. tostring(right_rail))
  if right_rail then
    join(poles, find_adjacent_poles(right_rail, {1, 0, 1}))  -- purple
    -- check the next rail after the curve too
    -- TODO: this FRONT might need to change depending on what shape we're coming from
    local direction_of_rail_into_curve = rail.direction
    if direction == FRONT and (direction_of_rail_into_curve == HORIZONTAL or direction_of_rail_into_curve == VERTICAL) then
      direction = BACK
    elseif direction == BACK and not (direction_of_rail_into_curve == HORIZONTAL or direction_of_rail_into_curve == VERTICAL) then
      direction = FRONT
    end

    local next_right_rail = get_next_rail(right_rail, direction, STRAIGHT)  -- exiting a curve is always "STRAIGHT"
    if next_right_rail then
      join(poles, find_adjacent_poles(next_right_rail, {0, 1, 1}))          -- cyan
    end
  end

  return poles, next_straight_rail
end


-- returns 2 tables containing all pole entities found close by and all poles found further away, or nil on error <br>
-- searches in both directions <br>
-- used when finding poles for a pole to connect to
---@param rail LuaEntity
---@return LuaEntity[] nearby_poles, LuaEntity[] far_poles
function RailMarcher.find_all_poles(rail)
  local nearby_poles, far_poles = nil, {}
  local surface = rail.surface

  -- check this rail
  nearby_poles = find_adjacent_poles(rail, {0, 1, 0})

  local poles, front_rail, back_rail
  poles, front_rail = find_all_next_poles(rail, FRONT, {0, 1, 0})
  join(nearby_poles, poles)
  poles, back_rail = find_all_next_poles(rail, BACK, {0, 1, 0})
  join(nearby_poles, poles)


  -- check further away rails
  if front_rail then
    for _ = 1, 7 do
      -- get poles from all rail directions, if no straight rail then break
      poles, front_rail = find_all_next_poles(front_rail, FRONT, {1, 0, 0})
      join(far_poles, poles)
      if not front_rail then break end
    end
  end

  if back_rail then
    for _ = 1, 7 do
      -- get poles from all rail directions, if no straight rail then break
      poles, back_rail = find_all_next_poles(back_rail, BACK, {1, 0, 0})
      join(far_poles, poles)
      if not back_rail then break end
    end
  end


  return nearby_poles, far_poles

  --[[

  -- first, check next to this rail
  if rail.type == "straight-rail" then
    rendering.draw_circle{color = {0, 1, 0}, width = 2, filled = false, target = position, surface = surface, radius = 1.5, only_in_alt_mode = true}
    found_poles = surface.find_entities_filtered{position = position, radius = 1.5, name = "oe-catenary-pole"}  -- name can be an array
  elseif rail.type == "curved-rail" then
    game.print("curved rail not implemented")
    return
  else
    game.print("cannot find poles next to " .. rail.name .. ", it's not a rail")
    return
  end

  -- then, loop for a few rails to find poles next to them
  -- i is used to index into the found_poles table
  for i = 2, 7 do
    ---@diagnostic disable-next-line: cast-local-type
    rail = rail.get_connected_rail{rail_direction = rail_dir, rail_connection_direction = STRAIGHT}
    if rail then
      rendering.draw_circle{color = {1, 0, 0}, width = 2, filled = false, target = rail, surface = surface, radius = 2, only_in_alt_mode = true}
      local all_poles = surface.find_entities_filtered{position = rail.position, radius = 2, name = "oe-catenary-pole"}
      game.print(serpent.line(all_poles))
      found_poles[i] = all_poles[1]
    else  -- we're out of rails in the STRAIGHT direction
      break
    end
  end
  ]]
end

return RailMarcher
