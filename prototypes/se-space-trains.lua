--[[ data.lua © Penguin_Spy 2023
  modifies se-space-trains's recipes & locomotive to be electric
]]

local data_util = require "prototypes.data_util"

if settings.startup["oe-se-space-train-compat"].value then
  -- modify fuel category of locomotive
  data.raw["locomotive"]["space-locomotive"].burner.fuel_category = nil
  data.raw["locomotive"]["space-locomotive"].burner.fuel_categories = {"oe-internal-fuel"}

  -- modify locomotive recipe
  data_util.remove_recipe_ingredient("recipe-space-locomotive", "locomotive")
  data_util.add_recipe_ingredient("recipe-space-locomotive", {
    type = "item", name = "oe-electric-locomotive", amount = 1
  })

  -- and change the dependency to electric railway
  local tech_name = mods["space-exploration"] and "se-space-rail" or "tech-space-trains"
  data_util.remove_technology_prerequisite(tech_name, "railway")
  data_util.add_technology_prerequisite(tech_name, "oe-electric-railway")

  -- remove/hide battery pack items, batter charger, and "electric" fuel category
  if settings.startup["oe-se-space-train-remove-batteries"].value then
    data.raw.item["space-train-battery-charging-station"] = nil
    data.raw.item["space-train-battery-pack"] = nil  -- charged form
    data.raw.item["space-train-destroyed-battery-pack"] = nil
    data.raw.item["space-train-discharged-battery-pack"] = nil

    data.raw.recipe["space-train-battery-charging-station"] = nil
    data.raw.recipe["space-train-battery-pack"] = nil
    data.raw.recipe["space-train-battery-pack-recharge"] = nil
    data.raw.recipe["space-train-battery-pack-refurbish"] = nil

    data.raw["assembling-machine"]["space-train-battery-charging-station"] = nil
    data.raw["recipe-category"]["electrical"] = nil  -- this might cause issues since this is a generic name. it removing it even necessary?
  else
    data.raw.recipe["space-train-battery-charging-station"].hidden = true
    data.raw.recipe["space-train-battery-pack"].hidden = true
    data.raw.recipe["space-train-battery-pack-recharge"].hidden = true
    data.raw.recipe["space-train-battery-pack-refurbish"].hidden = true
  end

  -- remove recipe unlocks from tech either way
  data_util.remove_technology_recipe_unlock(tech_name, "space-train-battery-charging-station")
  data_util.remove_technology_recipe_unlock(tech_name, "space-train-battery-pack")
  data_util.remove_technology_recipe_unlock(tech_name, "space-train-battery-pack-recharge")
  data_util.remove_technology_recipe_unlock(tech_name, "space-train-battery-pack-refurbish")
end
