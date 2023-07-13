local base_path = "__overhead-electrification__/"
local graphics = base_path .. "graphics/"

-- [[ Constants ]] --
local locomotive_power = 600   -- same consumption as vanilla locomotive


-- [[ Electric Locomotive ]] --

---@diagnostic disable-next-line: undefined-field
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
locomotive.max_power = locomotive_power.."kW"
locomotive.max_speed = 2 -- vanilla is 1.2
locomotive.weight = 1200 -- vanilla is 2000 for loco, 1000 for wagons

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
    {"electric-engine-unit", 20},
    {"advanced-circuit", 10},
    {"steel-plate", 30},
    {"iron-stick", 4}
  },
  result = "oe-electric-locomotive"
}

data:extend{locomotive, locomotive_item, locomotive_recipe}


-- [[ Rail power transformer ]] --

local transformer = table.deepcopy(data.raw["electric-pole"]["substation"])
transformer.name = "oe-transformer"
transformer.minable.result = "oe-transformer"
transformer.icons = { {icon = "__base__/graphics/icons/accumulator.png", tint = {r=1, g=1, b=0.7, a=1}} }
transformer.icon_size = 64
transformer.icon_mipmaps = 4
transformer.maximum_wire_distance = 9 -- medium-electric-pole
transformer.supply_area_distance = 0.5  -- only inside of it since it's 2x2

local transformer_item = {
  type = "item",
  name = "oe-transformer",
  icons = transformer.icons,
  icon_size = transformer.icon_size, icon_mipmaps = transformer.icon_mipmaps,
  subgroup = "train-transport",
  order = "a[train-system]-j[oe-transformer]",
  place_result = "oe-transformer",
  stack_size = 50
}

local transformer_recipe = {
  type = "recipe",
  name = "oe-transformer",
  energy_required = 10,
  enabled = false,
  ingredients = {
    {"copper-cable", 20},
    {"steel-plate", 10},
    {"advanced-circuit", 5}
  },
  result = "oe-transformer"
}

data:extend{transformer, transformer_item, transformer_recipe}


-- [[ Overhead power line pylons ]] --

local overhead_pylon = table.deepcopy(data.raw["electric-pole"]["medium-electric-pole"])
overhead_pylon.name = "oe-overhead-pylon"
overhead_pylon.icons = { {icon = "__base__/graphics/icons/medium-electric-pole.png", tint = {r=1, g=1, b=0.7, a=1}} }
overhead_pylon.icon_size = 64
overhead_pylon.icon_mipmaps = 4
overhead_pylon.minable.result = "oe-overhead-pylon"
overhead_pylon.maximum_wire_distance = 0   -- doesn't work, will have to prevent automatic connections with script?
overhead_pylon.supply_area_distance = 0

local overhead_pylon_item = {
  type = "item",
  name = "oe-overhead-pylon",
  icons = overhead_pylon.icons,
  icon_size = overhead_pylon.icon_size, icon_mipmaps = overhead_pylon.icon_mipmaps,
  subgroup = "train-transport",
  order = "a[train-system]-k[oe-overhead-pylon]",
  place_result = "oe-overhead-pylon",
  stack_size = 50
}

local overhead_pylon_recipe = {
  type = "recipe",
  name = "oe-overhead-pylon",
  enabled = false,
  ingredients = {
    {"copper-cable", 10},
    {"steel-plate", 4},
    {"iron-stick", 4}
  },
  result = "oe-overhead-pylon"
}

data:extend{overhead_pylon, overhead_pylon_item, overhead_pylon_recipe}


-- [[ electric locomotive interface ]] --
-- this is the hidden entity that consumes power from the electric network for the locomotive
--  teleported around by the script to be under the correct overhead network's transformer
-- no associated item or recipe

local locomotive_interface = {
  type = "electric-energy-interface",
  name = "oe-locomotive-interface",
  localised_name = {"entity-name.oe-electric-locomotive"},               -- use the same name, description, and icon from the locomotive
  localised_description = {"entity-description.oe-electric-locomotive"}, --  so it looks right in the electric network stats screen
  icon = locomotive.icon, icon_size = locomotive.icon_size, icon_mipmaps = locomotive.icon_mipmaps,
  flags = { "placeable-player", "placeable-off-grid", "hidden", "not-flammable" },
  max_health = 150,
  -- collision_box = {{0, 0}, {0, 0}},
  selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
  selectable_in_game = true, -- false,
  collision_mask = {}, -- collide with nothing (anything can be placed overtop it)
  energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    buffer_capacity = locomotive_power.."kJ", -- 1 second of operation
    input_flow_limit = 2*locomotive_power.."kW", -- recharges in 1 second
    render_no_network_icon = false,  -- when teleported out of the range of the transformer, should not blink the unplugged symbol
    render_no_power_icon = false     -- same with low power symbol
  },
  energy_usage = locomotive.max_power,
  picture = {
    filename = "__core__/graphics/empty.png",
    priority = "extra-high",
    width = 1, height = 1
  }
}

data:extend{locomotive_interface}


-- [[ internal fuel ]] --
-- this is the hidden fuel item & category used to power the locomotive
--  the fuel category is named & textured such that it's tooltips look identical to things that actually consume electricity

local internal_fuel_category = {
  type = "fuel-category",
  name = "oe-internal-fuel",
  localised_name = {"tooltip-category.electricity"} -- makes the tooltip say "Consumes electricity" like other electrical devices
}
local internal_fuel_item = {
  type = "item",
  name = "oe-internal-fuel",
  icon = "__core__/graphics/icons/tooltips/tooltip-category-electricity.png",
  icon_size = 36, icon_mipmaps = 2, -- close enough, especially for an icon that shouldn't appear
  subgroup = "other",
  order = "oe-internal",
  stack_size = 1,
  flags = {"hidden", "not-stackable"},
  fuel_category = "oe-internal-fuel",
  fuel_value = "1YJ" -- effectively infinite
}

-- the prototype name must be "tooltip-category-" followed by the name of the fuel category for the "Consumes x" tooltip to show the icon
local internal_fuel_category_tooltip = table.deepcopy(data.raw["sprite"]["tooltip-category-electricity"])
internal_fuel_category_tooltip.name = "tooltip-category-" .. internal_fuel_category.name

data:extend{internal_fuel_category, internal_fuel_item, internal_fuel_category_tooltip}


-- [[ Misc ]] --

data:extend{
  { -- Electric railway technology
    type = "technology",
    name = "oe-electric-railway",
    icon_size = 256, icon_mipmaps = 4,
    icon = graphics .. "electric-railway.png",
    effects = {
      {
        type = "unlock-recipe",
        recipe = "oe-electric-locomotive"
      }, {
        type = "unlock-recipe",
        recipe = "oe-transformer"
      }, {
        type = "unlock-recipe",
        recipe = "oe-overhead-pylon"
      }
      -- power poles, etc.
    },
    prerequisites = {"railway", "electric-engine", "electric-energy-distribution-1"},
    unit = {
      count = 75,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    },
    order = "c-g-a-a" -- after railway, before fluid-wagon
  },
  { -- Electric railway signals technology
    type = "technology",
    name = "oe-electric-railway-signals",
    icon_size = 256, icon_mipmaps = 4,
    icon = graphics .. "electric-railway-signals.png",
    effects = {
        -- power poles with built-in signals
    },
    prerequisites = {"oe-electric-railway", "rail-signals"},
    unit = {
      count = 50,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    },
    order = "c-g-a-a-a" -- after electric-railway
  }
}

-- testing placement restrictions
--[[local test_train_stop = table.deepcopy(data.raw["train-stop"]["train-stop"])
test_train_stop.name = "oe-test-train-stop"
test_train_stop.minable.result = "oe-test-train-stop"
test_train_stop.chart_name = false

local test_train_stop_item = table.deepcopy(data.raw["item"]["train-stop"])
test_train_stop_item.name = "oe-test-train-stop"
test_train_stop_item.place_result = "oe-test-train-stop"

data:extend{test_train_stop, test_train_stop_item}]]