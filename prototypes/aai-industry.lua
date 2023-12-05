--[[ prototypes/aai-industry.lua © Penguin_Spy 2023
  modifies the locomotive & catenary pole recipes to match AAI Industries' changes to vanilla items
]]

data.raw["recipe"]["oe-electric-locomotive"].ingredients = {
  {type = "item", name = "electric-engine-unit", amount = 15},
  {type = "item", name = "advanced-circuit",     amount = 10},
  {type = "item", name = "steel-plate",          amount = 30},
  {type = "item", name = "iron-stick",           amount = 4},
  {type = "item", name = "iron-gear-wheel",      amount = 10}
}

data.raw["recipe"]["oe-transformer"].ingredients = {
  {type = "item", name = "copper-cable",     amount = 20},
  {type = "item", name = "steel-plate",      amount = 10},
  {type = "item", name = "advanced-circuit", amount = 5},
  {type = "item", name = "concrete",         amount = 5}
}
