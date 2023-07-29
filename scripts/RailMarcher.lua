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

local pole_names = {"oe-catenary-pole", "oe-transformer"}

-- joins arrays. modifies `a` in place
---@param a table
---@param b table
local function join(a, b)
  for _, v in pairs(b) do
    a[#a+1] = v
  end
end

-- determines if a `straight-rail` is orthogonal or diagonal <br>
-- result is not valid for `curved-rail`!
---@param direction defines.direction
---@return boolean
local function is_orthogonal(direction)
  return direction == HORIZONTAL or direction == VERTICAL
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
-- debug
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

-- finds poles next to a single rail <br>
-- returns two tables if `rail` is a curved-rail, `back_poles` are the poles on the diagonal end
---@param rail LuaEntity
---@param color Color
---@return LuaEntity[] poles
---@return LuaEntity[]|nil back_poles
local function find_adjacent_poles(rail, color)
  if rail.type == "straight-rail" then
    local position = rail.position
    local direction = rail.direction

    -- adjust search radius to actual center of diagonal rails
    if direction == SOUTHWEST then
      position.x = position.x - 0.5
      position.y = position.y + 0.5
    elseif direction == NORTHWEST then
      position.x = position.x - 0.5
      position.y = position.y - 0.5
    elseif direction == SOUTHEAST then
      position.x = position.x + 0.5
      position.y = position.y + 0.5
    elseif direction == NORTHEAST then
      position.x = position.x + 0.5
      position.y = position.y - 0.5
    end

    local radius = is_orthogonal(direction) and 2 or 1.5

    rendering.draw_circle{color = color, width = 2, filled = false, target = position, surface = rail.surface, radius = radius, only_in_alt_mode = true}
    return rail.surface.find_entities_filtered{position = position, radius = radius, name = pole_names}, nil

    --
  elseif rail.type == "curved-rail" then
    local front_position, back_position = rail.position, rail.position
    local direction = rail.direction

    -- yup.
    if direction == defines.direction.north then
      front_position.x = front_position.x + 1
      front_position.y = front_position.y + 3.5
      back_position.x = back_position.x - 1.5
      back_position.y = back_position.y - 2.5
    elseif direction == defines.direction.northeast then
      front_position.x = front_position.x - 1
      front_position.y = front_position.y + 3.5
      back_position.x = back_position.x + 1.5
      back_position.y = back_position.y - 2.5
    elseif direction == defines.direction.east then
      front_position.x = front_position.x - 3.5
      front_position.y = front_position.y + 1
      back_position.x = back_position.x + 2.5
      back_position.y = back_position.y - 1.5
    elseif direction == defines.direction.southeast then
      front_position.x = front_position.x - 3.5
      front_position.y = front_position.y - 1
      back_position.x = back_position.x + 2.5
      back_position.y = back_position.y + 1.5
    elseif direction == defines.direction.south then
      front_position.x = front_position.x - 1
      front_position.y = front_position.y - 3.5
      back_position.x = back_position.x + 1.5
      back_position.y = back_position.y + 2.5
    elseif direction == defines.direction.southwest then
      front_position.x = front_position.x + 1
      front_position.y = front_position.y - 3.5
      back_position.x = back_position.x - 1.5
      back_position.y = back_position.y + 2.5
    elseif direction == defines.direction.west then
      front_position.x = front_position.x + 3.5
      front_position.y = front_position.y - 1
      back_position.x = back_position.x - 2.5
      back_position.y = back_position.y + 1.5
    elseif direction == defines.direction.northwest then
      front_position.x = front_position.x + 3.5
      front_position.y = front_position.y + 1
      back_position.x = back_position.x - 2.5
      back_position.y = back_position.y - 1.5
    else
      error("rail direction invalid " .. direction)
    end

    rendering.draw_circle{color = color, width = 2, filled = false, target = front_position, radius = 1.5, surface = rail.surface, only_in_alt_mode = true}
    local front_poles = rail.surface.find_entities_filtered{position = front_position, radius = 1.5, name = pole_names}

    rendering.draw_circle{color = color, width = 2, filled = false, target = back_position, radius = 1.425, surface = rail.surface, only_in_alt_mode = true}
    local back_poles = rail.surface.find_entities_filtered{position = back_position, radius = 1.425, name = pole_names}

    return front_poles, back_poles
  end
  error("cannot find ajacent poles: '" .. rail.name .. "' is not a straight-rail or curved-rail")
end
-- debug
RailMarcher.find_adjacent_poles = find_adjacent_poles


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


-- finds all poles next to the curved rails (and one rail past) that are after `rail` in the specified `direction` <br>
-- returns two tables, close_poles and far_poles. `direction` is used to know what poles are "close" <br>
-- this function only works for `straight-rail`s
---@param rail LuaEntity
---@param direction defines.rail_direction
---@return LuaEntity[] close_poles
---@return LuaEntity[] far_poles
local function find_poles_on_curved_rails(rail, direction)
  local close_poles, far_poles
  ---@type LuaEntity[], LuaEntity[]
  local front_poles, back_poles = {}, {}

  local left_rail = get_next_rail(rail, direction, LEFT)
  if left_rail then
    local f, b = find_adjacent_poles(left_rail, {1, 1, 0})
    join(front_poles, f)
    ---@diagnostic disable-next-line: param-type-mismatch -- will not be nil for curved-rail
    join(back_poles, b)
  end

  local right_rail = get_next_rail(rail, direction, RIGHT)
  if right_rail then
    local f, b = find_adjacent_poles(right_rail, {1, 1, 0})
    join(front_poles, f)
    ---@diagnostic disable-next-line: param-type-mismatch -- will not be nil for curved-rail
    join(back_poles, b)
  end

  -- determine which poles are close/far
  if is_orthogonal(rail.direction) then
    -- straight rail, use `front_poles` for too-close check
    close_poles = front_poles
    far_poles = back_poles
  else  -- diagonal rail, use `back_poles` for too-close check
    close_poles = back_poles
    far_poles = front_poles
  end

  -- check the next rail after the curve too, adjusting direction for curved/diagonal shenanigans
  local rail_into_curve_is_straight = is_orthogonal(rail.direction)
  if direction == FRONT and rail_into_curve_is_straight then
    direction = BACK
  elseif direction == BACK and not rail_into_curve_is_straight then
    direction = FRONT
  end

  -- find poles on the rail after the curved rails (always in far_poles)
  if left_rail then
    local next_left_rail = get_next_rail(left_rail, direction, STRAIGHT)  -- straight/diagonal
    if next_left_rail then
      local f, b = find_adjacent_poles(next_left_rail, {1, 1, 1})
      join(far_poles, f)
      if b then join(far_poles, b) end                                       -- back rails only exists for curved rails, might be diagonal
    end
    local next_left_right_rail = get_next_rail(left_rail, direction, RIGHT)  -- left turn out of diagonal after right turn into diagonal
    if next_left_right_rail then
      local f, b = find_adjacent_poles(next_left_right_rail, {1, 1, 1})
      ---@diagnostic disable-next-line: param-type-mismatch -- will not be nil for curved-rail
      join(far_poles, b)  -- technically kinda diagonal rail, join `back_poles` first to preserve distance order
      join(far_poles, f)
    end
  end
  if right_rail then
    local next_right_rail = get_next_rail(right_rail, direction, STRAIGHT)  -- straight/diagonal
    if next_right_rail then
      local f, b = find_adjacent_poles(next_right_rail, {1, 1, 1})
      join(far_poles, f)
      if b then join(far_poles, b) end                                       -- back rails only exists for curved rails, might be diagonal
    end
    local next_right_left_rail = get_next_rail(right_rail, direction, LEFT)  -- right turn out of diagonal after left turn into diagonal
    if next_right_left_rail then
      local f, b = find_adjacent_poles(next_right_left_rail, {1, 1, 1})
      ---@diagnostic disable-next-line: param-type-mismatch -- will not be nil for curved-rail
      join(far_poles, b)  -- technically kinda diagonal rail, join `back_poles` first to preserve distance order
      join(far_poles, f)
    end
  end

  return close_poles, far_poles
end


-- returns a table containing all pole entities that could be connected to, or `false` if there's a pole too close to this rail <br>
-- searches in both directions <br>
-- used when finding poles for a pole to connect to
---@param rail LuaEntity the rail to search from
---@param pole LuaEntity the pole being placed, ignored in the too-close checks
---@return LuaEntity[]|false nearby_poles
function RailMarcher.find_all_poles(rail, pole)
  local poles, back_poles

  if rail.type == "straight-rail" then
    --if straight rail:
    -- (find all poles next to this rail & the two adjacent rails)
    -- (if any exist, cancel placement)
    -- (find all poles on curved rails next to this rail) and on curved rails next to the two adjacent rails
    --  include poles one the rail one past the curved rail (straight/diagonal/curved, doesn't matter they're all a call to find_adjacent_poles)
    -- find all poles on straight rails past the two ajacent rails


    -- check this rail
    poles = find_adjacent_poles(rail, {1, 0, 0})

    -- find adjacent rails and check for poles
    local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
    if front_rail then
      join(poles, find_adjacent_poles(front_rail, {1, 0, 0}))
    end
    local back_rail = get_next_rail(rail, BACK, STRAIGHT)
    if back_rail then
      join(poles, find_adjacent_poles(back_rail, {1, 0, 0}))
    end

    -- find poles on close end of adjacent curved rails (only poles on close end block placement)
    local close_poles, far_poles = find_poles_on_curved_rails(rail, FRONT)
    for i, pole in pairs(close_poles) do
      highlight(pole, i, {1, 1, 0})  -- yellow
    end
    for i, pole in pairs(far_poles) do
      highlight(pole, i, {1, 0, 1})  -- magenta
    end
    join(poles, close_poles)         -- count these close poles as being too close
    local close_poles, far_poles = find_poles_on_curved_rails(rail, BACK)
    for i, pole in pairs(close_poles) do
      highlight(pole, i, {1, 1, 0})  -- yellow
    end
    for i, pole in pairs(far_poles) do
      highlight(pole, i, {1, 0, 1})  -- magenta
    end
    join(poles, close_poles)


    -- if there's another pole other than this one, it's too close
    util.remove_from_list(poles, pole)
    if #poles > 0 then  -- there can only be one on this rail
      for i, other_pole in pairs(poles) do highlight(other_pole, i, {0, 1, 0.5}) end
      return false
    end

    --   use straight/diagonal to know which end we're on
    -- poles on far end count for attaching

    -- todo: search along straight rails in both directions
    --   also search for all poles on curved rails that are one rail away

    -- rail.type == curved-rail
  else
    -- if curved rail:
    -- (find all poles next to this end of the curved rail) & the rail adjacent to the end this pole is on
    -- (if any exist, cancel placement)
    -- find all poles on the other end of this curved rail, one rail past the end
    -- find all poles on straight rails on this end of the curved rail

    poles, back_poles = find_adjacent_poles(rail, {0, 1, 0})

    -- figure out what end this pole is on (if it's in the poles list it gets removed)
    local straight_end = util.remove_from_list(poles, pole)

    if straight_end then
      if #poles > 0 then
        for i, other_pole in pairs(poles) do highlight(other_pole, i, {0, 1, 0.25}) end
        return false
      end
      -- todo: find next rail in BACK rail_direction and check it for poles

      --
    else  -- is diagonal end
      util.remove_from_list(back_poles, pole)
      if #back_poles > 0 then
        for i, other_pole in pairs(poles) do highlight(other_pole, i, {0, 1, 0.75}) end
        return false
      end
      -- todo: find next rail in FRONT rail_direction and check it for poles
    end

    -- todo: search along straight rails connected to whichever end of the curved rail this pole is on
  end




  if back_poles then
    join(poles, back_poles)
  end
  return poles




  --[[
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

  ]]

  --[[
  local surface = rail.surface

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
