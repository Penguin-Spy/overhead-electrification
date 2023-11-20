--[[ prototypes/aai-industry.lua © Penguin_Spy 2023
  modifies the locomotive & catenary pole recipes to match AAI Industries' changes to vanilla items
]]

data.raw["recipe"]["oe-electric-locomotive"].ingredients = {
  {"electric-engine-unit", 15},
  {"advanced-circuit",     10},
  {"steel-plate",          30},
  {"iron-stick",           4},
  {"iron-gear-wheel",      10}
}

data.raw["recipe"]["oe-transformer"].ingredients = {
  {"copper-cable",     20},
  {"steel-plate",      10},
  {"advanced-circuit", 5},
  {"concrete",         5}
}
