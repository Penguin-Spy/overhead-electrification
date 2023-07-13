local base_path = "__overhead-electrification__/"
local graphics = base_path .. "graphics/"

-- [[ Electric Locomotive ]] --

---@diagnostic disable-next-line: undefined-field
local locomotive = table.deepcopy(data.raw["locomotive"]["locomotive"])

locomotive.name = "oe-electric-locomotive"
locomotive.icon = graphics .. "electric-locomotive-icon.png"
locomotive.icon_size = 64
locomotive.icon_mipmaps = 4
locomotive.minable.result = "oe-electric-locomotive"
locomotive.burner = {
  fuel_inventory_size = 0,
  fuel_category = "oe-internal-fuel"
}
locomotive.max_power = "600kW" -- same as vanilla locomotive
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
  ingredients =
  {
    {"electric-engine-unit", 20},
    {"advanced-circuit", 10},
    {"steel-plate", 30},
    {"iron-stick", 4}
  },
  result = "oe-electric-locomotive"
}

data:extend{locomotive, locomotive_item, locomotive_recipe}


-- [[ Rail power transformer ]] --

--[[ (old transformer that was an electric interface)
local transformer = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
transformer.name = "oe-transformer"
transformer.icons = { {icon = "__base__/graphics/icons/accumulator.png", tint = {r=1, g=1, b=0.7, a=1}} }
transformer.minable = {mining_time = 0.1, result = "oe-transformer"}
transformer.energy_source =
  {
    type = "electric",
    buffer_capacity = "10GJ",
    usage_priority = "tertiary"
  }
transformer.energy_production = "500GW"
transformer.energy_usage = "0kW"
-- also 'pictures' for 4-way sprite is available, or 'animation' resp. 'animations'
transformer.picture = accumulator_picture( {r=1, g=1, b=0.7, a=1} )
]]

local transformer = table.deepcopy(data.raw["electric-pole"]["substation"])
transformer.name = "oe-transformer"
transformer.minable.result = "oe-transformer"
transformer.icons = { {icon = "__base__/graphics/icons/accumulator.png", tint = {r=1, g=1, b=0.7, a=1}} }
transformer.maximum_wire_distance = 9 -- medium-electric-pole
transformer.supply_area_distance = 0.5  -- only inside of it since it's 2x2

local transformer_item = {
  type = "item",
  name = "oe-transformer",
  icons = { {icon = "__base__/graphics/icons/accumulator.png", tint = {r=1, g=1, b=0.7, a=1}} },
  icon_size = 64, icon_mipmaps = 4,
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
  ingredients =
  {
    {"copper-cable", 20},
    {"steel-plate", 5},
    {"advanced-circuit", 5}
  },
  result = "oe-transformer"
}

data:extend{transformer, transformer_item, transformer_recipe}


-- [[ electric locomotive interface ]] --
-- this is the hidden entity that consumes power from the electric network for the locomotive
--  teleported around by the script to be under the correct overhead network's transformer
-- no associated item or recipe

local locomotive_interface = {
  type = "electric-energy-interface",
  name = "oe-locomotive-interface",
  localized_name = {"entity-name.oe-electric-locomotive"},               -- use the same name, description, and icon from the locomotive
  localized_description = {"entity-description.oe-electric-locomotive"}, --  so it looks right in the electric network stats screen
  icon = locomotive.icon, icon_size = locomotive.icon_size, icon_mipmaps = locomotive.icon_mipmaps,
  flags = { "placeable-player", "placeable-off-grid", "hidden", "not-flammable" },
  max_health = 150,
  --[[collision_box = {{0, 0}, {0, 0}},
  selection_box = {{-0, -0}, {0, 0}},]]
  selectable_in_game = false,
  energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    buffer_capacity = "600kJ" -- 1 second of operation. should be equal to the loco's "max_power" (acceleration)
  },
  energy_usage = locomotive.max_power,
  picture = {
    filename = "__core__/graphics/empty.png",
    priority = "extra-high",
    width = 1, height = 1
  }
}

data:extend{locomotive_interface}


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
      },
      {
        type = "unlock-recipe",
        recipe = "oe-transformer"
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
  },
  { -- fuel category for internal locomotive fuel
    type = "fuel-category",
    name = "oe-internal-fuel"
  },
  { -- internal locomotive fuel
    type = "item",
    name = "oe-internal-fuel",
    icon = "__core__/graphics/icons/tooltips/tooltip-category-electricity.png",
    icon_size = 36, icon_mipmaps = 2,
    subgroup = "other",
    order = "oe-internal",
    stack_size = 1,
    tags = {"hidden", "not-stackable"},
    fuel_category = "oe-internal-fuel",
    fuel_value = "1YJ" -- effectively infinite
  },
  { -- have the locomotive "consumes" tooltip use the electricity symbol
    type = "sprite",
    name = "tooltip-category-oe-internal-fuel",
    filename = "__core__/graphics/icons/tooltips/tooltip-category-electricity.png",
    priority = "extra-high-no-scale",
    width = 32,
    height = 40,
    flags = {"gui-icon"},
    mipmap_count = 2,
    scale = 0.5
  }
}

-- just copy the electricity tooltip and change the name
--table.deepcopy(data.raw["sprite"]["tooltip-category-electricity"])