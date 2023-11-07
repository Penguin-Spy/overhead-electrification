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
-- if `single` is true, return values are `LuaEntity`, else it's `LuaEntity[]`
-- if `rail` is a curved-rail, `back_poles` is the pole on the diagonal end, else it is nil
---@param rail LuaEntity
---@param color Color
---@param single boolean
---@param skip_front boolean?  debug
---@param skip_back boolean?   debug
---@return LuaEntity|LuaEntity[]|nil poles
---@return LuaEntity|LuaEntity[]|nil back_poles
---@nodiscard
local function find_adjacent_poles(rail, color, single, skip_front, skip_back)
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
    if single then
      return rail.surface.find_entities_filtered{position = position, radius = radius, name = pole_names, limit = 1}[1], nil
    else
      return rail.surface.find_entities_filtered{position = position, radius = radius, name = pole_names}, nil
    end

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
    if not skip_back then
      rendering.draw_circle{color = color, width = 2, filled = false, target = back_position, radius = 1.425, surface = rail.surface, only_in_alt_mode = true}
    end

    local front_pole, back_pole
    if single then
      front_pole = rail.surface.find_entities_filtered{position = front_position, radius = 1.5, name = pole_names, limit = 1}[1]
      back_pole = rail.surface.find_entities_filtered{position = back_position, radius = 1.425, name = pole_names, limit = 1}[1]
    else
      front_pole = rail.surface.find_entities_filtered{position = front_position, radius = 1.5, name = pole_names}
      back_pole = rail.surface.find_entities_filtered{position = back_position, radius = 1.425, name = pole_names}
    end

    return front_pole, back_pole
  end
  error("cannot find ajacent poles: '" .. rail.name .. "' is not a straight-rail or curved-rail")
end
RailMarcher.find_adjacent_poles = find_adjacent_poles


local insert = table.insert

---@generic T
---@param rail LuaEntity                      the rail to march from
---@param direction defines.rail_direction    the direction to march in
---@param path integer[]                      the unit_numbers of the rails leading up to this rail
---@param distance integer                    the remaining distance to travel
---@param on_pole (fun(other_pole: LuaEntity, path: integer[], distance: integer, cb_arg: T): quit: boolean?)? the callback to run when a pole is found
---@param on_end  (fun(path: integer[], cb_arg: T): quit: boolean?)? the callback to run when the end is found
---@param cb_arg T                          an arbitrary value to be passed to the callbacks
---@param filter_network catenary_network_id?  if given, ignore rails that aren't powered by this network
---@return boolean? quit
local function march_rail(rail, direction, path, distance, on_pole, on_end, cb_arg, filter_network)
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
      local f, b = find_adjacent_poles(left_rail, {0, 1, 1}, true, not rail_into_curve_is_orthogonal and distance <= 3, rail_into_curve_is_orthogonal and distance <= 3)
      if not rail_into_curve_is_orthogonal then
        f, b = b, f  -- swap front & back if coming from diagonal rail
      end
      if f then
        left_rail = false  -- don't march past this rail
        if on_pole then
          local quit = on_pole(f, left_path, distance, cb_arg)
          if quit then return quit end
        end
      end
      if b and distance > 3 then
        left_rail = false  -- don't march past this rail
        if on_pole then
          local quit = on_pole(b, left_path, distance, cb_arg)
          if quit then return quit end
        end
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
      local f, b = find_adjacent_poles(right_rail, {1, 1, 0}, true, not rail_into_curve_is_orthogonal and distance <= 3, rail_into_curve_is_orthogonal and distance <= 3)
      if not rail_into_curve_is_orthogonal then
        f, b = b, f  -- swap front & back if coming from diagonal rail
      end
      if f then
        right_rail = false  -- don't march past this rail
        if on_pole then
          local quit = on_pole(f, right_path, distance, cb_arg)
          if quit then return quit end
        end
      end
      if b and distance > 3 then
        right_rail = false  -- don't march past this rail
        if on_pole then
          local quit = on_pole(b, right_path, distance, cb_arg)
          if quit then return quit end
        end
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
      local p = find_adjacent_poles(straight_rail, {0, 1, 0}, true)
      if p then
        straight_rail = false  -- don't march past this rail
        if on_pole then
          local quit = on_pole(p, path, distance, cb_arg)
          if quit then return quit end
        end
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
    local quit = march_rail(straight_rail, direction, path, distance - 1, on_pole, on_end, cb_arg, filter_network)
    if quit then return quit end
  end

  if left_rail and distance > 4 then  -- if a rail was found, the dir and path will not be nil
    game.print("  marching left")
    local quit = march_rail(left_rail, left_direction  --[[@as(integer)]], left_path  --[[@as(integer[])]], distance - 4, on_pole, on_end, cb_arg, filter_network)
    if quit then return quit end
  end
  if right_rail and distance > 4 then
    game.print("  marching right")
    local quit = march_rail(right_rail, right_direction  --[[@as(integer)]], right_path  --[[@as(integer[])]], distance - 4, on_pole, on_end, cb_arg, filter_network)
    if quit then return quit end
  end

  -- if no rail is found in any direction, run the on_end callback (if it exists)
  if straight_rail == nil and right_rail == nil and right_rail == nil and on_end then
    local quit = on_end(path, cb_arg)
    if quit then return quit end
  end
end
RailMarcher.march_rail = march_rail


return RailMarcher
