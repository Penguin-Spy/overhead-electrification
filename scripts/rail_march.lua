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


-- returns the first pole found whose network_id matches the argument
---@param rail LuaEntity
---@param rail_dir defines.rail_direction
---@param network_id uint
---@return LuaEntity?
function rail_march.find_next_pole_in_network(rail, rail_dir, network_id)
  --local next_rail = rail.selected.get_connected_rail{rail_direction = rail_dir, rail_connection_direction = STRAIGHT}
end


-- returns a table containing all pole entities found (or nil if none were found, not an empty table)
-- does not perform error checking to save performance
---@param rail LuaEntity
---@param rail_dir defines.rail_direction
---@return LuaEntity[]|nil
function rail_march.find_all_poles(rail, rail_dir)
  local found_poles = {}
  local surface = rail.surface

  -- first, check next to this rail
  if rail.name == "straight-rail" then
    local position = rail.position
    if rail.direction == HORIZONTAL then
      if rail_dir == FRONT then
        position.x = position.x + 0.5
      else  -- must be back
        position.x = position.x - 0.5
      end
    else
      if rail_dir == FRONT then  -- up is -y
        position.y = position.y - 0.5
      else
        position.y = position.y + 0.5
      end
    end
    rendering.draw_circle{color = {0, 1, 0}, width = 2, filled = false, target = position, surface = surface, radius = 1.5, only_in_alt_mode = true}
    found_poles = surface.find_entities_filtered{position = position, radius = 1.5, name = "oe-catenary-pole"}  -- name can be an array
    ---
  elseif rail.name == "curved-rail" then
    game.print("curved rail")
  else
    game.print("cannot find poles next to " .. rail.name .. ", it's not a rail")
    return nil
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

  return found_poles
end

return rail_march
