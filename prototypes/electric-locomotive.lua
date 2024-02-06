local data_util = require "prototypes.data_util"
local graphics = data_util.graphics

-- [[ Electric Locomotive ]] --

local locomotive = table.deepcopy(data.raw["locomotive"]["locomotive"])

locomotive.name = "oe-electric-locomotive"
locomotive.icon = graphics .. "electric-locomotive-icon.png"
locomotive.icon_size = 64
locomotive.icon_mipmaps = 4
locomotive.minable.result = "oe-electric-locomotive"
locomotive.burner = {
  fuel_inventory_size = 0,  -- 0 is valid and means no slots appear
  fuel_category = "oe-internal-fuel"
}
locomotive.max_power = "800kW"  -- vanilla locomotive is 600
locomotive.max_speed = 2        -- vanilla is 1.2
locomotive.weight = 1200        -- vanilla is 2000 for loco, 1000 for wagons

local locomotive_item = table.deepcopy(data.raw["item-with-entity-data"]["locomotive"])
locomotive_item.name = "oe-electric-locomotive"
locomotive_item.icon = locomotive.icon
locomotive_item.icon_size = locomotive.icon_size
locomotive_item.icon_mipmaps = locomotive.icon_mipmaps
locomotive_item.order = "a[train-system]-f[oe-electric-locomotive]"
locomotive_item.place_result = "oe-electric-locomotive"

local locomotive_recipe = {
  type = "recipe",
  name = "oe-electric-locomotive",
  energy_required = 4,
  enabled = false,
  ingredients = {
    {type = "item", name = "electric-engine-unit", amount = 20},
    {type = "item", name = "advanced-circuit",     amount = 10},
    {type = "item", name = "steel-plate",          amount = 30},
    {type = "item", name = "iron-stick",           amount = 4}
  },
  result = "oe-electric-locomotive"
}

data:extend{locomotive, locomotive_item, locomotive_recipe}
