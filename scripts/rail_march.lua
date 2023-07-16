--[[ rail_march.lua © Penguin_Spy 2023
  Utilities for finding catenary poles alongside rails
]]

local rail_march = {}

-- store these to reduce table dereferences
local STRAIGHT = defines.rail_connection_direction.straight
local LEFT = defines.rail_connection_direction.left
local RIGHT = defines.rail_connection_direction.right
local FRONT = defines.rail_direction.front
local BACK = defines.rail_direction.back

-- directions the straight rails use
local VERTICAL = defines.direction.north   -- front is up, back is down
local HORIZONTAL = defines.direction.east  -- front is right, back is left

-- joins arrays. modifies `a` in place
---@param a table
---@param b table
local function join(a, b)
  for _, v in pairs(b) do
    a[#a+1] = v
  end
end


-- returns the first pole found whose network_id matches the argument <br>
-- used when updating electric locomotive, so no error checking for performance
---@param rail LuaEntity
---@param rail_dir defines.rail_direction
---@param network_id uint?
---@return uint?
function rail_march.get_network_in_direction(rail, rail_dir, network_id)
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
    game.print("curved rail not implemented")
    return {}
  end
  error("cannot find ajacent poles: '" .. rail.name .. "' is not a straight-rail or curved-rail")
end

-- returns 2 tables containing all pole entities found close by and all poles found further away, or nil on error <br>
-- searches in both directions <br>
-- used when finding poles for a pole to connect to
---@param rail LuaEntity
---@return LuaEntity[] nearby_poles, LuaEntity[] far_poles
function rail_march.find_all_poles(rail)
  local nearby_poles, far_poles = nil, {}
  local surface = rail.surface

  -- check this rail
  nearby_poles = find_adjacent_poles(rail, {0, 1, 0})


  -- check one rail in each direction
  local front_rail = rail.get_connected_rail{rail_direction = FRONT, rail_connection_direction = STRAIGHT}
  local back_rail = rail.get_connected_rail{rail_direction = BACK, rail_connection_direction = STRAIGHT}
  if front_rail then join(nearby_poles, find_adjacent_poles(front_rail, {0, 1, 0})) end
  if back_rail then join(nearby_poles, find_adjacent_poles(back_rail, {0, 1, 0})) end


  -- check further away rails
  -- {1, 0, 0}
  if front_rail then
    local next_rail = front_rail
    for i = 1, 7 do
      ---@diagnostic disable-next-line: cast-local-type -- holy shit leave me alone i'm going to fucking nil check it
      next_rail = next_rail.get_connected_rail{rail_direction = FRONT, rail_connection_direction = STRAIGHT}
      if next_rail then  -- see look i'm fucking checking it right here
        local poles = find_adjacent_poles(next_rail, {1, 0, 0})
        if #poles > 0 then
          join(far_poles, poles)
          break  -- stop once we've found a pole
        end
      else
        break
      end
    end
  end

  if back_rail then
    local next_rail = back_rail
    for i = 1, 7 do
      ---@diagnostic disable-next-line: cast-local-type -- holy shit leave me alone i'm going to fucking nil check it
      next_rail = next_rail.get_connected_rail{rail_direction = BACK, rail_connection_direction = STRAIGHT}
      if next_rail then  -- see look i'm fucking checking it right here
        local poles = find_adjacent_poles(next_rail, {1, 0, 0})
        if #poles > 0 then
          join(far_poles, poles)
          break  -- stop once we've found a pole
        end
      else
        break
      end
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

return rail_march
