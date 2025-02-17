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

  -- remove or hide the battery pack items and battery charger
  if settings.startup["oe-se-space-train-remove-batteries"].value then
    data.raw.item["space-train-battery-charging-station"] = nil
    data.raw.item["space-train-battery-pack"] = nil  -- charged form
    data.raw.item["space-train-destroyed-battery-pack"] = nil
    data.raw.item["space-train-discharged-battery-pack"] = nil

    data.raw.recipe["space-train-battery-charging-station"] = nil
    data.raw.recipe["space-train-battery-pack"] = nil
    data.raw.recipe["space-train-battery-pack-recharge"] = nil
    data.raw.recipe["space-train-battery-pack-refurbish"] = nil

    -- generated by krastorio during data-updates, but we can't remove se-space-trains' stuff until after data-updates
    if mods["Krastorio2"] then
      data.raw.recipe["kr-vc-space-train-battery-charging-station"] = nil
      data.raw.recipe["kr-vc-space-train-battery-pack"] = nil
      data.raw.recipe["kr-vc-space-train-destroyed-battery-pack"] = nil
      data.raw.recipe["kr-vc-space-train-discharged-battery-pack"] = nil
    end

    data.raw["assembling-machine"]["space-train-battery-charging-station"] = nil
    -- make sure to remove this reference if any mod has made it pastable to anything (attach notes, for example, makes everything copy-pastable to make notes pastable)
    log(serpent.block(defines.prototypes.entity))
    for t in pairs(defines.prototypes.entity) do
      for _, proto in pairs(data.raw[t]) do
        local pastable = proto.additional_pastable_entities
        if pastable and type(pastable) == "table" then
          util.remove_from_list(pastable, "space-train-battery-charging-station")
        end
      end
    end

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
