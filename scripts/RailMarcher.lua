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

-- shallow copies an array. returns the new array
---@generic T: table
---@param t T
---@return T
local function copy(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = v
  end
  return c
end


-- determines if a `straight-rail` is orthogonal or diagonal <br>
-- result is not valid for `curved-rail`!
---@param direction defines.direction
---@return boolean
---@nodiscard
local function is_orthogonal(direction)
  return direction == HORIZONTAL or direction == VERTICAL
end


-- gets the next rail in the given direction (`FRONT`/`BACK`) & connection direction (`STRAIGHT`/`LEFT`/`RIGHT`) <br>
-- handles diagonal/curved rails (diagonal "front" is always upwards)
---@param rail LuaEntity
---@param direction defines.rail_direction
---@param connection defines.rail_connection_direction
---@return LuaEntity?
---@nodiscard
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


-- finds poles next to a single rail <br>
-- returns entities if `rail` is a curved-rail, `back_pole` is the pole on the diagonal end
---@param rail LuaEntity
---@param color Color
---@param skip_front boolean?  debug
---@param skip_back boolean?   debug
---@return LuaEntity pole
---@return LuaEntity back_pole
---@nodiscard
local function find_adjacent_poles(rail, color, skip_front, skip_back)
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
    return rail.surface.find_entities_filtered{position = position, radius = radius, name = pole_names, limit = 1}[1], nil

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

    if not skip_front then
      rendering.draw_circle{color = color, width = 2, filled = false, target = front_position, radius = 1.5, surface = rail.surface, only_in_alt_mode = true}
    end
    local front_pole = rail.surface.find_entities_filtered{position = front_position, radius = 1.5, name = pole_names, limit = 1}[1]

    if not skip_back then
      rendering.draw_circle{color = color, width = 2, filled = false, target = back_position, radius = 1.425, surface = rail.surface, only_in_alt_mode = true}
    end
    local back_pole = rail.surface.find_entities_filtered{position = back_position, radius = 1.425, name = pole_names, limit = 1}[1]

    return front_pole, back_pole
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
---@nodiscard
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
    local next_left_left_rail = get_next_rail(left_rail, direction, LEFT)  -- left turn into diagonal after left turn out of diagonal
    if next_left_left_rail then
      -- only save the 'front' (orthogonal) poles, the back poles are too far around the curve
      join(far_poles, (find_adjacent_poles(next_left_left_rail, {1, 1, 1})))
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
    local next_right_right_rail = get_next_rail(right_rail, direction, RIGHT)  -- right turn into diagonal after right turn out of diagonal
    if next_right_right_rail then
      -- only save the 'front' (orthogonal) poles, the back poles are too far around the curve
      join(far_poles, (find_adjacent_poles(next_right_right_rail, {1, 1, 1})))
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
---@nodiscard
local function find_poles_on_straight_rails(next_rail, direction, nearby_poles)
  for _ = 1, 7 do
    local straight_next_rail = get_next_rail(next_rail, direction, STRAIGHT)
    if straight_next_rail then
      join(nearby_poles, find_adjacent_poles(straight_next_rail, {0, 1, 0}))  -- green
      next_rail = straight_next_rail
    else
      local is_rail_orthogonal = is_orthogonal(next_rail.direction)
      local left_next_rail = get_next_rail(next_rail, direction, LEFT)
      if (left_next_rail) then
        local f, b = find_adjacent_poles(left_next_rail, {1, 0.5, 1})  -- magenta
        if is_rail_orthogonal then
          join(nearby_poles, f)
        else
          join(nearby_poles, b)
        end
      end
      local right_next_rail = get_next_rail(next_rail, direction, RIGHT)
      if (right_next_rail) then
        local f, b = find_adjacent_poles(right_next_rail, {1, 0.5, 1})  -- magenta
        if is_rail_orthogonal then
          join(nearby_poles, f)
        else
          join(nearby_poles, b)
        end
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
      -- find close poles on the curved rails in the orthogonal direction
      join(nearby_poles, (find_poles_on_curved_rails(rail, FRONT)))
    end

    -- if there's another pole other than this one, it's too close
    if #too_close_poles > 0 then
      for i, other_pole in pairs(too_close_poles) do highlight(other_pole, i, {0, 1, 0.5}) end  -- "SpringGreen"
      return false
    end
    return nearby_poles
  end
end



-- finds all rails attached to the curved rails (and one rail past) that are after `rail` in the specified `direction` that match the `network_id` <br>
---@param rail LuaEntity
---@param direction defines.rail_direction
---@param network_id catenary_network_id the catenary network to compare to
---@param rails LuaEntity[] the table to store found rails in
---@param potential_rails LuaEntity[] rails that should be saved if this function finds anything
local function find_rails_on_curved_rails(rail, direction, network_id, rails, potential_rails)
  local rail_number_lookup = global.rail_number_lookup
  local potential_rails_left, potential_rails_right = {}, {}
  local old_rails_length = #rails

  local left_rail = get_next_rail(rail, direction, LEFT)
  if left_rail then
    table.insert(potential_rails_left, left_rail)
    if rail_number_lookup[left_rail.unit_number] == network_id then
      join(rails, potential_rails_left)
      potential_rails_left = {}
    end
  end

  local right_rail = get_next_rail(rail, direction, RIGHT)
  if right_rail then
    table.insert(potential_rails_right, right_rail)
    if rail_number_lookup[right_rail.unit_number] == network_id then
      join(rails, potential_rails_right)
      potential_rails_right = {}
    end
  end

  local rail_into_curve_is_straight
  if rail.type == "straight-rail" then
    rail_into_curve_is_straight = is_orthogonal(rail.direction)
  else  -- rail.type == "curved-rail"
    rail_into_curve_is_straight = direction == FRONT
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
      table.insert(potential_rails_left, next_left_rail)
      if rail_number_lookup[next_left_rail.unit_number] == network_id then
        join(rails, potential_rails_left)
        potential_rails_left = {}
      end
    end
    local next_left_right_rail = get_next_rail(left_rail, direction, RIGHT)  -- left turn out of diagonal after right turn into diagonal
    if next_left_right_rail then
      table.insert(potential_rails_left, next_left_right_rail)
      if rail_number_lookup[next_left_right_rail.unit_number] == network_id then
        join(rails, potential_rails_left)
        potential_rails_left = {}
      end
    end
    local next_left_left_rail = get_next_rail(left_rail, direction, LEFT)  -- left turn into diagonal after left turn out of diagonal
    if next_left_left_rail then
      table.insert(potential_rails_left, next_left_left_rail)
      if rail_number_lookup[next_left_left_rail.unit_number] == network_id then
        join(rails, potential_rails_left)
        potential_rails_left = {}
      end
    end
  end
  if right_rail then
    local next_right_rail = get_next_rail(right_rail, direction, STRAIGHT)  -- straight/diagonal
    if next_right_rail then
      table.insert(potential_rails_right, next_right_rail)
      if rail_number_lookup[next_right_rail.unit_number] == network_id then
        join(rails, potential_rails_right)
        potential_rails_right = {}
      end
    end
    local next_right_left_rail = get_next_rail(right_rail, direction, LEFT)  -- right turn out of diagonal after left turn into diagonal
    if next_right_left_rail then
      table.insert(potential_rails_right, next_right_left_rail)
      if rail_number_lookup[next_right_left_rail.unit_number] == network_id then
        join(rails, potential_rails_right)
        potential_rails_right = {}
      end
    end
    local next_right_right_rail = get_next_rail(right_rail, direction, RIGHT)  -- right turn into diagonal after right turn out of diagonal
    if next_right_right_rail then
      table.insert(potential_rails_right, next_right_right_rail)
      if rail_number_lookup[next_right_right_rail.unit_number] == network_id then
        join(rails, potential_rails_right)
        potential_rails_right = {}
      end
    end
  end

  if #rails ~= old_rails_length then
    join(rails, potential_rails)
  end
end


-- marches along the straight rails after `rail` in the given `direction` and finds all rails that should be in the network <br>
-- also finds curved rails on the end <br>
-- found rails are moved from `potential_rails` to `rails
---@param next_rail LuaEntity
---@param direction defines.rail_direction
---@param network_id catenary_network_id the catenary network to compare to
---@param rails LuaEntity[] the table to store found rails in
---@param potential_rails LuaEntity[] any rails that should be saved if this function finds anything
local function find_rails_on_straight_rails(next_rail, direction, network_id, rails, potential_rails)
  local rail_number_lookup = global.rail_number_lookup

  for _ = 1, 7 do
    local straight_next_rail = get_next_rail(next_rail, direction, STRAIGHT)
    if straight_next_rail then
      table.insert(potential_rails, straight_next_rail)
      if rail_number_lookup[straight_next_rail.unit_number] == network_id then
        join(rails, potential_rails)
        potential_rails = {}
      end
      next_rail = straight_next_rail
    else
      local left_next_rail = get_next_rail(next_rail, direction, LEFT)
      if left_next_rail then
        table.insert(potential_rails, left_next_rail)
        if rail_number_lookup[left_next_rail.unit_number] == network_id then
          join(rails, potential_rails)
          potential_rails = {}
        end
      end
      local right_next_rail = get_next_rail(next_rail, direction, RIGHT)
      if right_next_rail then
        table.insert(potential_rails, right_next_rail)
        if rail_number_lookup[right_next_rail.unit_number] == network_id then
          join(rails, potential_rails)
          potential_rails = {}
        end
      end
      break
    end
  end
end



-- returns a table containing all rail entities that are between this rail and other rails in its network <br>
-- searches in both directions
---@param rail LuaEntity the rail to search from
---@param initial_pole LuaEntity the initial pole (used for knowing which end of a curved rail to march from)
---@return LuaEntity[] rails
function RailMarcher.find_all_rails(rail, initial_pole)
  local rail_number_lookup = global.rail_number_lookup
  local network_id = rail_number_lookup[rail.unit_number]

  local rails = {}
  local potential_rails_front, potential_rails_back = {}, {}

  rendering.draw_circle{color = {0, 0, 0}, width = 2, filled = false, target = rail.position, radius = 0.5, surface = rail.surface, only_in_alt_mode = true}

  if rail.type == "straight-rail" then
    -- find adjacent straight rails
    local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
    if front_rail then
      table.insert(potential_rails_front, front_rail)
      if rail_number_lookup[front_rail.unit_number] == network_id then
        join(rails, potential_rails_front)
        potential_rails_front = {}
      end
    end
    local back_rail = get_next_rail(rail, BACK, STRAIGHT)
    if back_rail then
      table.insert(potential_rails_back, back_rail)
      if rail_number_lookup[back_rail.unit_number] == network_id then
        join(rails, potential_rails_back)
        potential_rails_back = {}
      end
    end

    -- find adjacent curved rails
    find_rails_on_curved_rails(rail, FRONT, network_id, rails, potential_rails_front)
    find_rails_on_curved_rails(rail, BACK, network_id, rails, potential_rails_back)

    -- search along straight rails in both directions
    if front_rail then
      find_rails_on_straight_rails(rail, FRONT, network_id, rails, potential_rails_front)
    end
    if back_rail then
      find_rails_on_straight_rails(rail, BACK, network_id, rails, potential_rails_back)
    end

    return rails

    --
  else  -- rail.type == curved-rail
    local front_poles = find_adjacent_poles(rail, {0, 1, 0})

    -- figure out what end this pole is on (if it's in the poles list it gets removed)
    local on_orthogonal_end = util.remove_from_list(front_poles, initial_pole)

    if on_orthogonal_end then  -- the front of a curved rail is the orthogonal end
      -- find poles on the adjacent straight rail on the orthogonal direction
      local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
      if front_rail then
        table.insert(potential_rails_front, front_rail)
        if rail_number_lookup[front_rail.unit_number] == network_id then
          join(rails, potential_rails_front)
          potential_rails_front = {}
        end

        if rail.direction <= 3 then  --  0-3 are BACK, 4-7 are FRONT
          find_rails_on_straight_rails(front_rail, BACK, network_id, rails, potential_rails_front)
        else
          find_rails_on_straight_rails(front_rail, FRONT, network_id, rails, potential_rails_front)
        end
      end

      -- find poles along adjacent curved rails on the orthogonal direction (only poles on close end block placement, poles on far end count for attaching)
      find_rails_on_curved_rails(rail, FRONT, network_id, rails, potential_rails_front)

      -- find poles on the straight rail in the diagonal direction
      local back_rail = get_next_rail(rail, BACK, STRAIGHT)
      if back_rail then
        table.insert(potential_rails_back, back_rail)
        if rail_number_lookup[back_rail.unit_number] == network_id then
          join(rails, potential_rails_back)
          potential_rails_back = {}
        end
      end
      -- find poles along the curved rails in the orthogonal direction
      find_rails_on_curved_rails(rail, BACK, network_id, rails, potential_rails_back)

      --
    else  -- is back (diagonal) end
      -- find poles on the adjacent straight rail on the diagonal direction
      local back_rail = get_next_rail(rail, BACK, STRAIGHT)
      if back_rail then
        table.insert(potential_rails_back, back_rail)
        if rail_number_lookup[back_rail.unit_number] == network_id then
          join(rails, potential_rails_back)
          potential_rails_back = {}
        end

        if rail.direction <= 2 or rail.direction == 7 then  -- 0,1,2,7 are FRONT, 3,4,5,6 are BACK
          find_rails_on_straight_rails(back_rail, FRONT, network_id, rails, potential_rails_back)
        else
          find_rails_on_straight_rails(back_rail, BACK, network_id, rails, potential_rails_back)
        end
      end

      -- find poles along the adjacent curved rails on the diagonal direction
      find_rails_on_curved_rails(rail, BACK, network_id, rails, potential_rails_back)

      -- find poles on the straight rail in the orthogonal direction
      local front_rail = get_next_rail(rail, FRONT, STRAIGHT)
      if front_rail then
        table.insert(potential_rails_front, front_rail)
        if rail_number_lookup[front_rail.unit_number] == network_id then
          join(rails, potential_rails_front)
          potential_rails_front = {}
        end
      end
      -- find close poles on the curved rails in the orthogonal direction
      find_rails_on_curved_rails(rail, FRONT, network_id, rails, potential_rails_front)
    end

    return rails
  end
end


local insert = table.insert

---@param rail LuaEntity                      the rail to march from
---@param direction defines.rail_direction    the direction to march in
---@param path integer[]                      the unit_numbers of the rails leading up to this rail
---@param distance integer                    the remaining distance to travel
---@param on_pole function?                   the callback to run when a pole is found: `on_pole(pole, path, distance)`
---@param on_end  function?                   the callback to run when the end is found: `on_end(path)`
---@param filter_network catenary_network_id?  if given, ignore rails that aren't powered by this network
local function march_rail(rail, direction, path, distance, on_pole, on_end, filter_network)
  game.print(serpent.line{rail, direction, path, distance, on_pole and "on_pole", on_end and "on_end", filter_network})
  local rail_lut = global.rail_number_lookup

  -- check LEFT, STRAIGHT, and RIGHT rails for poles
  --  when a pole is found (don't march past that rail)
  --  call the on_pole callback (if it exists)

  local rail_into_curve_is_orthogonal
  if rail.type == "straight-rail" then
    rail_into_curve_is_orthogonal = is_orthogonal(rail.direction)
  else  -- rail.type == "curved-rail"
    rail_into_curve_is_orthogonal = direction == FRONT
  end

  -- LEFT & RIGHT are curves
  --  check close point for poles
  --  if enough distance left, check far point for poles
  local left_rail = get_next_rail(rail, direction, LEFT)  --[[@as LuaEntity|nil|false]]
  local left_path, left_direction  --[[@type nil, nil]]
  if left_rail then
    local rail_id = left_rail.unit_number
    left_path = copy(path)
    insert(left_path, rail_id)

    -- adjust direction for curved/diagonal shenanigans
    if direction == FRONT and rail_into_curve_is_orthogonal then
      left_direction = BACK
    elseif direction == BACK and not rail_into_curve_is_orthogonal then
      left_direction = FRONT
    else
      left_direction = direction
    end

    if not filter_network or filter_network == rail_lut[rail_id] then
      -- check for poles if no filter or filter matches
      local f, b = find_adjacent_poles(left_rail, {0, 1, 1}, not rail_into_curve_is_orthogonal and distance <= 3, rail_into_curve_is_orthogonal and distance <= 3)
      if not rail_into_curve_is_orthogonal then
        f, b = b, f  -- swap front & back if coming from diagonal rail
      end
      if f then
        left_rail = false  -- don't march past this rail
        if on_pole then on_pole(f, left_path, distance) end
      end
      if b and distance > 3 then
        left_rail = false  -- don't march past this rail
        if on_pole then on_pole(b, left_path, distance) end
      end
    elseif filter_network ~= rail_lut[rail_id] then
      -- ignore this rail for on_end checks if filter doesn't match
      left_rail = nil
    end
  end

  local right_rail = get_next_rail(rail, direction, RIGHT)  --[[@as LuaEntity|nil|false]]
  local right_path, right_direction  --[[@type nil, nil]]
  if right_rail then
    local rail_id = right_rail.unit_number
    right_path = copy(path)
    insert(right_path, rail_id)

    -- adjust direction for curved/diagonal shenanigans
    if direction == FRONT and rail_into_curve_is_orthogonal then
      right_direction = BACK
    elseif direction == BACK and not rail_into_curve_is_orthogonal then
      right_direction = FRONT
    else
      right_direction = direction
    end

    if not filter_network or filter_network == rail_lut[rail_id] then
      -- check for poles if no filter or filter matches
      local f, b = find_adjacent_poles(right_rail, {1, 1, 0}, not rail_into_curve_is_orthogonal and distance <= 3, rail_into_curve_is_orthogonal and distance <= 3)
      if not rail_into_curve_is_orthogonal then
        f, b = b, f  -- swap front & back if coming from diagonal rail
      end
      if f then
        right_rail = false  -- don't march past this rail
        if on_pole then on_pole(f, right_path, distance) end
      end
      if b and distance > 3 then
        right_rail = false  -- don't march past this rail
        if on_pole then on_pole(b, right_path, distance) end
      end
    elseif filter_network ~= rail_lut[rail_id] then
      -- ignore this rail for on_end checks if filter doesn't match
      right_rail = nil
    end
  end

  -- STRAIGHT is a straight rail
  local straight_rail = get_next_rail(rail, direction, STRAIGHT)  --[[@as LuaEntity|nil|false]]
  if straight_rail then
    local rail_id = straight_rail.unit_number
    insert(path, rail_id)

    if rail.type == "curved-rail" then
      --TODO: need to swap direction depending on the rotation of `rail` (the curved rail we're coming from)
      if direction == FRONT and rail.direction <= 3 then
        direction = BACK
      elseif rail.direction <= 2 or rail.direction == 7 then  -- direction == BACK
        direction = FRONT
      end
    end

    if not filter_network or filter_network == rail_lut[rail_id] then
      -- check for poles if no filter or filter matches
      local p = find_adjacent_poles(straight_rail, {0, 1, 0})
      if p then
        straight_rail = false  -- don't march past this rail
        if on_pole then on_pole(p, path, distance) end
      end
    elseif filter_network ~= rail_lut[rail_id] then
      -- ignore this rail for on_end checks if filter doesn't match
      straight_rail = nil
    end
  end

  -- call march_rail recursively on the found LEFT, STRAIGHT, and RIGHT rails (if enough distance & it didn't have a pole)
  --  pass a reduced distance (-1 for STRAIGHT, -4 for curved rails (from cost of placing them))
  --  flip direction param if necessary (entering/leaving curve, ~~diagonal shenanegans?~~)
  --  pass a copy of the path array to the LEFT/RIGHT marches, straight gets the one we got (works as long as we run straight last i think -- MAKE SURE TO TEST THIS)
  --  pass the on_pole & on_end callbacks unchanged

  if straight_rail and distance > 1 then
    game.print("  marching straight")
    march_rail(straight_rail, direction, path, distance - 1, on_pole, on_end, filter_network)
  end

  if left_rail and distance > 4 then  -- if a rail was found, the dir and path will not be nil
    game.print("  marching left")
    march_rail(left_rail, left_direction  --[[@as(integer)]], left_path  --[[@as(integer[])]], distance - 4, on_pole, on_end, filter_network)
  end
  if right_rail and distance > 4 then
    game.print("  marching right")
    march_rail(right_rail, right_direction  --[[@as(integer)]], right_path  --[[@as(integer[])]], distance - 4, on_pole, on_end, filter_network)
  end

  -- if no rail is found in any direction, run the on_end callback (if it exists)
  if straight_rail == nil and right_rail == nil and right_rail == nil and on_end then
    on_end(path)
  end
end
RailMarcher.march_rail = march_rail


return RailMarcher
