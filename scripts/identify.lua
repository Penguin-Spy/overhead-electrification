--[[ identify.lua © Penguin_Spy 2023
  Common functions for identifying entities that we need to process
]]
local identify = {}

-- checks if an entity is a catenary pole
---@param entity LuaEntity
---@return boolean
function identify.is_pole(entity)
  local name = entity.name
  return name == "oe-catenary-pole" or name == "oe-transformer"  -- or name == "oe-catenary-double-pole" or name == "oe-catenary-pole-rail-signal", etc
end

-- is the given locomotive an electric locomotive?
---@param entity LuaEntity
---@return boolean
function identify.is_locomotive(entity)
  -- locomotives can have a void energy source (and so entity.burner is nil)
  return entity.burner and entity.burner.fuel_categories["oe-internal-fuel"] or false
end

-- is the given entity any type of rolling stock?
---@param entity LuaEntity
---@return boolean
function identify.is_rolling_stock(entity)
  local type = entity.type
  return type == "locomotive" or type == "cargo-wagon" or type == "fluid-wagon" or type == "artillery-wagon"
end

return identify
