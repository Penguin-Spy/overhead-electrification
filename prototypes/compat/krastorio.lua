local data_util = require "prototypes.data_util"

local locomotive = data.raw["locomotive"]["oe-electric-locomotive"]

locomotive.equipment_grid = "kr-locomotive-grid"
locomotive.weight = 6000        -- krastorio multiplies vanilla's by a factor of 5, so we do the same here
locomotive.max_power = "2.6MW"  -- factor of 3.33
locomotive.max_speed = 1.6975   -- factor of 0.84875
locomotive.braking_force = 30   -- factor of 3

data_util.remove_recipe_ingredient("oe-electric-locomotive", "steel-plate")
data_util.add_recipe_ingredient("oe-electric-locomotive", {name = "steel-plate", amount = 80})
data.raw.recipe["oe-electric-locomotive"].energy_required = 60

data_util.remove_recipe_ingredient("oe-catenary-pole", "steel-plate")
data_util.add_recipe_ingredient("oe-catenary-pole", {name = "steel-beam", amount = 2})

data_util.remove_recipe_ingredient("oe-transformer", "steel-plate")
data_util.add_recipe_ingredient("oe-transformer", {name = "steel-beam", amount = 8})
