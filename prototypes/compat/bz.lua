--[[ prototypes/bz.lua © Penguin_Spy 2023
  modifies the locomotive & catenary pole recipes to match changes made by various brevvens mods
]]

local data_util = require "prototypes.data_util"

if mods["bzaluminum"] then
  data_util.replace_some_ingredient(data.raw["recipe"]["oe-electric-locomotive"].ingredients,
    "steel-plate", 10,
    "aluminum-6061", 20
  )
  data_util.replace_some_ingredient(data.raw["recipe"]["oe-transformer"].ingredients,
    "copper-cable", 20,  -- should be all of it
    "acsr-cable", 10
  )
  data_util.add_recipe_ingredient("oe-transformer",
    {type = "item", name = "aluminum-plate", amount = 4}
  )
  data_util.replace_some_ingredient(data.raw["recipe"]["oe-catenary-pole"].ingredients,
    "copper-cable", 10,  -- should be all of it
    "acsr-cable", 5
  )
end

if mods["bzlead"] then
  data_util.add_recipe_ingredient("oe-transformer",
    {type = "item", name = "lead-plate", amount = 2}
  )
end

if mods["bztin"] then
  data_util.add_recipe_ingredient("oe-transformer",
    {type = "item", name = "solder", amount = 4}
  )
end
