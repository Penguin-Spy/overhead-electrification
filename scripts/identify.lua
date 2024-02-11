--[[ identify.lua © Penguin_Spy 2023
  Common functions for identifying entities that we need to process
]]
local identify = {}

identify.electric_pole_names = {"oe-catenary-electric-pole-0", "oe-catenary-electric-pole-1", "oe-catenary-electric-pole-2", "oe-catenary-electric-pole-3",
  "oe-catenary-electric-pole-4", "oe-catenary-electric-pole-5", "oe-catenary-electric-pole-6", "oe-catenary-electric-pole-7"}

local electric_pole_map = util.list_to_map(identify.electric_pole_names)

-- checks if an entity is a catenary pole
---@param entity LuaEntity
---@return boolean
function identify.is_pole(entity)
  return electric_pole_map[entity.name]
end

-- checks if an entity is a catenary pole's graphics
---@param entity LuaEntity
---@return boolean
function identify.is_pole_graphics(entity)
  local name = entity.name
  return name == "oe-normal-catenary-pole-orthogonal"
      or name == "oe-normal-catenary-pole-diagonal"
      or name == "oe-signal-catenary-pole"
      or name == "oe-chain-catenary-pole"
      or name == "oe-transformer-graphics"
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
