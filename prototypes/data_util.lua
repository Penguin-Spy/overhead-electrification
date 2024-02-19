--[[ prototypes/data_util.lua © Penguin_Spy 2023
  util functions for modifying prototypes
]]

-- removes the `unlock-recipe` effect for the recipe from the technology
---@param technology_name string
---@param recipe string
local function remove_technology_recipe_unlock(technology_name, recipe)
  local technology = data.raw.technology[technology_name]
  if not technology then error("[overhead-electrification.data_util] unknown technology: '" .. tostring(technology_name) .. "', cannot remove recipe unlock '" .. tostring(recipe) .. "' from it!") end
  local effects = technology.effects
  if effects then
    for i, effect in pairs(effects) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe then
        effects[i] = nil
      end
    end
  else
    for i, effect in pairs(technology.normal.effects) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe then
        effects[i] = nil
      end
    end
    for i, effect in pairs(technology.expensive.effects) do
      if effect.type == "unlock-recipe" and effect.recipe == recipe then
        effects[i] = nil
      end
    end
  end
end

-- removes a prerequesite from a technology if it was present
---@param technology_name string
---@param prerequisite_name string
local function remove_technology_prerequisite(technology_name, prerequisite_name)
  local technology = data.raw.technology[technology_name]
  if not technology then error("[overhead-electrification.data_util] unknown technology: '" .. tostring(technology_name) .. "', cannot remove prerequisite '" .. tostring(prerequisite_name) .. "' from it!") end
  local prerequisites = technology.prerequisites
  if prerequisites then
    util.remove_from_list(prerequisites, prerequisite_name)
  else
    util.remove_from_list(technology.normal.prerequisites, prerequisite_name)
    util.remove_from_list(technology.expensive.prerequisites, prerequisite_name)
  end
end

-- adds a prerequesite to a technology
---@param technology_name string
---@param prerequisite_name string
local function add_technology_prerequisite(technology_name, prerequisite_name)
  local technology = data.raw.technology[technology_name]
  if not technology then error("[overhead-electrification.data_util] unknown technology: '" .. tostring(technology_name) .. "', cannot add prerequisite '" .. tostring(prerequisite_name) .. "' to it!") end
  local prerequisites = technology.prerequisites
  if prerequisites then
    table.insert(prerequisites, prerequisite_name)
  else
    table.insert(technology.normal.prerequisites, prerequisite_name)
    table.insert(technology.expensive.prerequisites, prerequisite_name)
  end
end


---@param ingredients data.IngredientPrototype[]
---@param from string
---@param from_amount integer
---@param to string
---@param to_amount integer
local function replace_some_ingredient(ingredients, from, from_amount, to, to_amount)
  for i, ingredient in pairs(ingredients) do
    if ingredient[1] and ingredient[1] == from then
      local amount = ingredient[2] - from_amount
      if amount > 0 then
        ingredient[2] = amount
      else
        ingredients[i] = nil
      end
    elseif ingredient.name == from then
      local amount = ingredient.amount - from_amount
      if amount > 0 then
        ingredient.amount = amount
      else
        ingredients[i] = nil
      end
    end
  end

  table.insert(ingredients, {type = "item", name = to, amount = to_amount})
end


-- internal function to handle the ingredients shorthand
---@param array data.IngredientPrototype[]
---@param name string
---@param ingredient_type string?
local function remove_from_ingredients_array(array, name, ingredient_type)
  for i, ingredient in pairs(array) do
    if ingredient[1] and ingredient[1] == name then  -- shorthand formt 👎
      array[i] = nil
    else
      if ingredient.name == name and  -- full format + optional type check
          (not ingredient_type or ingredient.type == ingredient_type) then
        array[i] = nil
      end
    end
  end
end

-- removes an ingredient from a recipe
---@param recipe_name string
---@param ingredient_name string
---@param ingredient_type string? if not specified, removes both `item` and `fluid` ingredients with matching names
local function remove_recipe_ingredient(recipe_name, ingredient_name, ingredient_type)
  local recipe = data.raw.recipe[recipe_name]
  if not recipe then error("[overhead-electrification.data_util] unknown recipe: '" .. tostring(recipe) .. "', cannot remove ingredient '" .. tostring(ingredient_name) .. "' from it!") end
  local ingredients = recipe.ingredients
  if ingredients then
    remove_from_ingredients_array(ingredients, ingredient_name, ingredient_type)
  else
    remove_from_ingredients_array(recipe.normal.ingredients, ingredient_name, ingredient_type)
    remove_from_ingredients_array(recipe.expensive.ingredients, ingredient_name, ingredient_type)
  end
end

-- adds an ingredient to a recipe
---@param recipe_name string
---@param ingredient data.IngredientPrototype
local function add_recipe_ingredient(recipe_name, ingredient)
  local recipe = data.raw.recipe[recipe_name]
  if not recipe then
    local name, type, amount = ingredient.name, ingredient.type, ingredient.amount
    error("[overhead-electrification.data_util] unknown recipe: '" .. tostring(recipe) .. "', cannot add ingredient '"
      .. tostring(name) .. "' ('" .. tostring(type) .. "') x" .. tostring(amount) .. " to it!")
  end
  local ingredients = recipe.ingredients
  if ingredients then
    table.insert(ingredients, ingredient)
  else
    table.insert(recipe.normal.ingredients, ingredient)
    table.insert(recipe.expensive.ingredients, ingredient)
  end
end


-- creates an entity prototype that mimics another entity
local function mimic(entity_prototype, properties)
  local mimic_prototype = {
    localised_name = {"entity-name." .. entity_prototype.name},
    localised_description = {"entity-description." .. entity_prototype.name},
    icon = entity_prototype.icon,  -- whichever isn't defined will just be nil
    icons = entity_prototype.icons,
    icon_size = entity_prototype.icon_size,
    icon_mipmaps = entity_prototype.icon_mipmaps,
    subgroup = "oe-other",
    order = "oe-internal",
    collision_mask = {},  -- collide with nothing (anything can be placed overtop it)
    flags = {}
  }

  for k, v in pairs(properties) do
    mimic_prototype[k] = v
  end

  table.insert(mimic_prototype.flags, "hidden")
  table.insert(mimic_prototype.flags, "not-flammable")

  return mimic_prototype
end

return {
  graphics = "__overhead-electrification__/graphics/",
  remove_technology_recipe_unlock = remove_technology_recipe_unlock,
  remove_technology_prerequisite = remove_technology_prerequisite,
  add_technology_prerequisite = add_technology_prerequisite,
  replace_some_ingredient = replace_some_ingredient,
  remove_recipe_ingredient = remove_recipe_ingredient,
  add_recipe_ingredient = add_recipe_ingredient,
  mimic = mimic
}
