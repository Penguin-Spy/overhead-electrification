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
---@return LuaEntity[] back_poles
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
    -- this is easier then trying to convince sumneko.lua that back_poles won't be nil for curved rails
    ---@diagnostic disable-next-line: return-type-mismatch
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


-- finds all poles next to the curved rails (and one rail past) that are after `rail` in the specified `direction` <br>
-- returns two tables, close_poles and far_poles. `direction` is used to know what poles are "close" <br>
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
    join(back_poles, b)
  end

  local right_rail = get_next_rail(rail, direction, RIGHT)
  if right_rail then
    local f, b = find_adjacent_poles(right_rail, {1, 1, 0})
    join(front_poles, f)
    join(back_poles, b)
  end

  local rail_into_curve_is_straight
  if rail.type == "straight-rail" then
    rail_into_curve_is_straight = is_orthogonal(rail.direction)
  else  -- rail.type == "curved-rail"
    rail_into_curve_is_straight = direction == FRONT
  end

  -- determine which poles are close/far
  if rail_into_curve_is_straight then
    -- straight rail, use `front_poles` for too-close check
    close_poles = front_poles
    far_poles = back_poles
  else  -- diagonal rail, use `back_poles` for too-close check
    close_poles = back_poles
    far_poles = front_poles
  end

  -- check the next rail after the curve too, adjusting direction for curved/diagonal shenanigans
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
      join(far_poles, b)  -- technically kinda diagonal rail, join `back_poles` first to preserve distance order
      join(far_poles, f)
    end
  end

  return close_poles, far_poles
end


-- marches along the straight rails after `rail` in the given `direction` and finds all adjacent poles <br>
-- also finds poles on the close end of `curved-rail`s <br>
-- found poles are added to `nearby_poles`
---@param next_rail LuaEntity
---@param direction defines.rail_direction
---@param nearby_poles LuaEntity[]
local function find_poles_on_straight_rails(next_rail, direction, nearby_poles)
  for _ = 1, 7 do
    local straight_next_rail = get_next_rail(next_rail, direction, STRAIGHT)
    if straight_next_rail then
      join(nearby_poles, find_adjacent_poles(straight_next_rail, {0, 1, 0}))  -- green
      next_rail = straight_next_rail
    else
      local left_next_rail = get_next_rail(next_rail, direction, LEFT)
      if (left_next_rail) then
        join(nearby_poles, (find_adjacent_poles(left_next_rail, {1, 0.5, 1})))  -- magenta
      end
      local right_next_rail = get_next_rail(next_rail, direction, RIGHT)
      if (right_next_rail) then
        join(nearby_poles, (find_adjacent_poles(right_next_rail, {1, 0.5, 1})))  -- magenta
      end
      break
    end
  end
end


-- returns a table containing all pole entities that could be connected to, or `false` if there's a pole too close to this rail <br>
-- searches in both directions <br>
-- used when finding poles for a pole to connect to
---@param rail LuaEntity the rail to search from
---@param initial_pole LuaEntity the pole being placed, ignored in the too-close checks
---@return LuaEntity[]|false nearby_poles
function RailMarcher.find_all_poles(rail, initial_pole)
  rendering.draw_circle{color = {0, 0, 0}, width = 2, filled = false, target = rail.position, radius = 0.5, surface = rail.surface, only_in_alt_mode = true}

  if rail.type == "straight-rail" then
    local nearby_poles = {}
    --if straight rail:
    -- [find all poles next to this rail & the two adjacent rails]
    -- [if any exist, cancel placement]
    -- [find all poles on curved rails next to this rail]
    -- [include poles one the rail one past the curved rail] (straight/diagonal/curved, doesn't matter they're all a call to find_adjacent_poles)
    -- [find all poles on straight rails past the two ajacent rails]

    -- check this rail for poles
    local too_close_poles = find_adjacent_poles(rail, {1, 0, 0})

    -- find adjacent straight rails and check for poles
    local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
    if front_rail then
      join(too_close_poles, find_adjacent_poles(front_rail, {1, 0, 0}))
    end
    local back_rail = get_next_rail(rail, BACK, STRAIGHT)
    if back_rail then
      join(too_close_poles, find_adjacent_poles(back_rail, {1, 0, 0}))
    end

    -- find poles on adjacent curved rails (only poles on close end block placement, poles on far end count for attaching)
    local close_poles, far_poles = find_poles_on_curved_rails(rail, FRONT)
    join(too_close_poles, close_poles)  -- count these close poles as being too close
    join(nearby_poles, far_poles)
    close_poles, far_poles = find_poles_on_curved_rails(rail, BACK)
    join(too_close_poles, close_poles)
    join(nearby_poles, far_poles)


    -- if there's another pole other than this one, it's too close
    util.remove_from_list(too_close_poles, initial_pole)
    if #too_close_poles > 0 then
      for i, other_pole in pairs(too_close_poles) do highlight(other_pole, i, {0, 1, 0.5}) end  -- "SpringGreen"
      return false
    end


    -- search along straight rails in both directions
    if front_rail then
      find_poles_on_straight_rails(rail, FRONT, nearby_poles)
    end
    if back_rail then
      find_poles_on_straight_rails(rail, BACK, nearby_poles)
    end


    return nearby_poles


    --
  else  -- rail.type == curved-rail
    -- if curved rail:
    -- [find all poles next to this end of the curved rail] & [the rail adjacent to the end this pole is on]
    -- [if any exist, cancel placement]
    -- [find all poles on the other end of this curved rail, one rail past the end]
    -- [find all poles on straight rails on this end of the curved rail]

    local front_poles, back_poles = find_adjacent_poles(rail, {0, 1, 0})
    local too_close_poles, nearby_poles

    -- figure out what end this pole is on (if it's in the poles list it gets removed)
    local on_orthogonal_end = util.remove_from_list(front_poles, initial_pole)

    if on_orthogonal_end then  -- the front of a curved rail is the orthogonal end
      game.print("on orthogonal end")
      too_close_poles = front_poles
      nearby_poles = back_poles

      -- find poles on the adjacent straight rail on the orthogonal direction
      local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
      if front_rail then
        join(too_close_poles, find_adjacent_poles(front_rail, {1, 0, 0}))

        if rail.direction <= 3 then  --  0-3 are BACK, 4-7 are FRONT
          find_poles_on_straight_rails(front_rail, BACK, nearby_poles)
        else
          find_poles_on_straight_rails(front_rail, FRONT, nearby_poles)
        end
      end

      -- find poles along adjacent curved rails on the orthogonal direction (only poles on close end block placement, poles on far end count for attaching)
      local close_poles, far_poles = find_poles_on_curved_rails(rail, FRONT)
      join(too_close_poles, close_poles)  -- count these close poles as being too close
      join(nearby_poles, far_poles)

      -- find poles on the straight rail in the diagonal direction
      local back_rail = get_next_rail(rail, BACK, STRAIGHT)
      if back_rail then
        join(nearby_poles, (find_adjacent_poles(back_rail, {1, 1, 1})))  -- white
      end
      -- find poles along the curved rails in the orthogonal direction
      close_poles, far_poles = find_poles_on_curved_rails(rail, BACK)
      join(too_close_poles, close_poles)  -- count these close poles as being too close
      join(nearby_poles, far_poles)

      --
    else  -- is back (diagonal) end
      game.print("on diagonal end")

      util.remove_from_list(back_poles, initial_pole)  -- remove the initial_pole from the back_poles list instead
      too_close_poles = back_poles
      nearby_poles = front_poles

      -- find poles on the adjacent straight rail on the diagonal direction
      local back_rail = get_next_rail(rail, BACK, STRAIGHT)
      if back_rail then
        join(too_close_poles, find_adjacent_poles(back_rail, {1, 0, 0}))

        if rail.direction <= 2 or rail.direction == 7 then  -- 0,1,2,7 are FRONT, 3,4,5,6 are BACK
          find_poles_on_straight_rails(back_rail, FRONT, nearby_poles)
        else
          find_poles_on_straight_rails(back_rail, BACK, nearby_poles)
        end
      end

      -- find poles along the adjacent curved rails on the diagonal direction
      local close_poles, far_poles = find_poles_on_curved_rails(rail, BACK)
      join(too_close_poles, close_poles)  -- count these close poles as being too close
      join(nearby_poles, far_poles)

      -- find poles on the straight rail in the orthogonal direction
      local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
      if front_rail then
        join(nearby_poles, (find_adjacent_poles(front_rail, {1, 1, 0})))
      end
      -- find poles along the curved rails in the orthogonal direction
      local f, b = find_poles_on_curved_rails(rail, FRONT)
      join(nearby_poles, f)
      join(nearby_poles, b)
    end

    -- if there's another pole other than this one, it's too close
    if #too_close_poles > 0 then
      for i, other_pole in pairs(too_close_poles) do highlight(other_pole, i, {0, 1, 0.5}) end  -- "SpringGreen"
      return false
    end
    return nearby_poles
  end
end

return RailMarcher
