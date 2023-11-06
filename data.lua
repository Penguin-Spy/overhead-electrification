--[[ data.lua © Penguin_Spy 2023
  defines prototypes for the locomotive, catenary poles, and transformer
  also defines prototypes for the hidden fuel items & interface entity used to make the locomotive appear to consume electricity
]]

-- [[ Constants ]] --
local base_path = "__overhead-electrification__/"
local graphics = base_path .. "graphics/"
local const = require 'constants'

-- [[ Util functions ]] --

-- generates a dummy "placer entity" to use it's placement restrictions to a different entity type
-- ex: transformer has a placer that's a train-stop to force it to be placed next to rails
local function generate_placer(entity_to_place, placer_prototype, additional_properties)
  local placer = table.deepcopy(entity_to_place)

  placer.type = placer_prototype
  placer.name = entity_to_place.name .. "-placer"
  placer.localised_name = {"entity-name." .. entity_to_place.name}
  placer.localised_description = {"entity-description." .. entity_to_place.name}

  for k, v in pairs(additional_properties) do
    placer[k] = v
  end

  -- makes Q and blueprints work. place_result must still be set on the item
  entity_to_place.placeable_by = {item = entity_to_place.name, count = 1}

  return placer
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
    --collision_box = {{0, 0}, {0, 0}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},  -- remove for not debugging
    selectable_in_game = true,                   -- false for not debugging
    collision_mask = {},                         -- collide with nothing (anything can be placed overtop it)
    flags = {}
  }

  for k, v in pairs(properties) do
    mimic_prototype[k] = v
  end

  table.insert(mimic_prototype.flags, "hidden")
  table.insert(mimic_prototype.flags, "not-flammable")

  return mimic_prototype
end


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
locomotive.max_power = const.LOCOMOTIVE_POWER .. "kW"
locomotive.max_speed = 2  -- vanilla is 1.2
locomotive.weight = 1200  -- vanilla is 2000 for loco, 1000 for wagons

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
    {"advanced-circuit",     10},
    {"steel-plate",          30},
    {"iron-stick",           4}
  },
  result = "oe-electric-locomotive"
}

data:extend{locomotive, locomotive_item, locomotive_recipe}


-- [[ Rail power transformer ]] --

local transformer = table.deepcopy(data.raw["electric-pole"]["substation"])
transformer.name = "oe-transformer"
transformer.minable.result = "oe-transformer"
transformer.icons = {{icon = "__base__/graphics/icons/accumulator.png", tint = {r = 1, g = 1, b = 0.7, a = 1}}}
transformer.icon_size = 64
transformer.icon_mipmaps = 4
transformer.maximum_wire_distance = 9   -- medium-electric-pole
transformer.supply_area_distance = 0.5  -- only inside of it since it's 2x2
transformer.build_grid_size = 2         -- ensure ghosts also follow the rail grid

-- simple-entity for graphics
local transformer_graphics = mimic(transformer, {
  type = "simple-entity-with-owner",
  name = "oe-transformer-graphics",
  flags = {"not-rotatable"},
  build_grid_size = 2,
  picture = {
    sheet = {
      filename = graphics .. "catenary-pole/direction-4.png",
      priority = "extra-high",
      size = 76,
      shift = util.by_pixel(-0.5, -0.5),
      scale = 0.5
    }
  }
})

-- dummy placement entity for placement restrictions, immediatley replaced by the real one in control.lua
local transformer_placer = generate_placer(transformer, "train-stop", {
  animation_ticks_per_frame = 1,
  chart_name = false,
  flags = data.raw["train-stop"]["train-stop"].flags,  -- add "filter-directions"
  rail_overlay_animations = data.raw["train-stop"]["train-stop"].rail_overlay_animations,
  animations = {north = transformer.pictures}
})

local transformer_item = {
  type = "item",
  name = "oe-transformer",
  icons = transformer.icons,
  icon_size = transformer.icon_size,
  icon_mipmaps = transformer.icon_mipmaps,
  subgroup = "train-transport",
  order = "a[train-system]-j[oe-transformer]",
  place_result = transformer_placer.name,
  stack_size = 50
}

local transformer_recipe = {
  type = "recipe",
  name = "oe-transformer",
  energy_required = 10,
  enabled = false,
  ingredients = {
    {"copper-cable",     20},
    {"steel-plate",      10},
    {"advanced-circuit", 5}
  },
  result = "oe-transformer"
}

data:extend{transformer, transformer_graphics, transformer_placer, transformer_item, transformer_recipe}


-- [[ Overhead power line pylons ]] --

-- power pole
local catenary_pole = table.deepcopy(data.raw["electric-pole"]["medium-electric-pole"])
catenary_pole.name = "oe-catenary-pole"
catenary_pole.icons = {{icon = "__base__/graphics/icons/medium-electric-pole.png", tint = {r = 1, g = 1, b = 0.7, a = 1}}}
catenary_pole.icon_size = 64
catenary_pole.icon_mipmaps = 4
catenary_pole.minable.result = "oe-catenary-pole"
catenary_pole.maximum_wire_distance = 0.75  -- allow connecting to 2x2 poles inside of it, but not anything outside of it so player can't change connections)
catenary_pole.supply_area_distance = 0
catenary_pole.flags = {"player-creation", "placeable-player", "building-direction-8-way", "filter-directions"}
catenary_pole.fast_replaceable_group = ""  -- don't fast replace with power poles

-- simple-entity for graphics
local catenary_pole_graphics = mimic(catenary_pole, {
  type = "simple-entity-with-owner",
  name = "oe-catenary-pole-graphics",
  flags = {"not-rotatable"},
  collision_box = {{-0.35, -0.35}, {0.35, 0.35}},
  --selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
  random_variation_on_create = false,
  pictures = {
    sheet = {
      variation_count = 8,
      filename = graphics .. "catenary-pole/direction-8.png",
      priority = "extra-high",
      size = 76,
      shift = util.by_pixel(-0.5, -0.5),
      scale = 0.5
    }
  }
})

-- dummy placement entity for placement restrictions, immediatley replaced by the real one in control.lua
local catenary_pole_placer = generate_placer(catenary_pole, "rail-signal", {
  flags = data.raw["rail-signal"]["rail-signal"].flags,
  animation = data.raw["rail-signal"]["rail-signal"].animation,
})

local catenary_pole_item = {
  type = "item",
  name = "oe-catenary-pole",
  icons = catenary_pole.icons,
  icon_size = catenary_pole.icon_size,
  icon_mipmaps = catenary_pole.icon_mipmaps,
  subgroup = "train-transport",
  order = "a[train-system]-k[oe-catenary-pole]",
  place_result = catenary_pole_placer.name,
  stack_size = 50
}

local catenary_pole_recipe = {
  type = "recipe",
  name = "oe-catenary-pole",
  enabled = false,
  ingredients = {
    {"copper-cable", 10},
    {"steel-plate",  4},
    {"iron-stick",   4}
  },
  result = "oe-catenary-pole"
}

data:extend{catenary_pole, catenary_pole_graphics, catenary_pole_placer, catenary_pole_item, catenary_pole_recipe}


-- [[ electric locomotive interface ]] --
-- this is the hidden entity that consumes power from the electric network for the locomotive
--  teleported around by the script to be under the correct overhead network's transformer
-- no associated item or recipe

local locomotive_interface = mimic(locomotive, {
  type = "electric-energy-interface",
  name = "oe-locomotive-interface",
  flags = {"placeable-off-grid"},
  energy_source = {
    type = "electric",
    usage_priority = "secondary-input",                     -- can only input, setting energy_production does nothing
    buffer_capacity = const.LOCOMOTIVE_POWER .. "kJ",       -- 1 second of operation
    input_flow_limit = 2 * const.LOCOMOTIVE_POWER .. "kW",  -- recharges in 1 second (each second: consumes LOCOMOTIVE_POWER kJ, recharges LOCOMOTIVE_POWER kJ into buffer)
    --render_no_network_icon = false,                         -- when teleported out of the range of the transformer, should not blink the unplugged symbol
    --render_no_power_icon = false                            -- same with low power symbol
  },
  energy_usage = locomotive.max_power,
  picture = {
    filename = "__core__/graphics/empty.png",
    priority = "extra-high",
    width = 1,
    height = 1
  }
})

data:extend{locomotive_interface}


-- [[ internal fuel ]] --
-- this is the hidden fuel item & category used to power the locomotive
--  the fuel category is named & textured such that it's tooltips look identical to things that actually consume electricity

local internal_fuel_category = {
  type = "fuel-category",
  name = "oe-internal-fuel",
  localised_name = {"tooltip-category.electricity"}  -- makes the tooltip say "Consumes electricity" like other electrical devices
}
local internal_fuel_item = {
  type = "item",
  name = "oe-internal-fuel",
  icon = "__core__/graphics/icons/tooltips/tooltip-category-electricity.png",
  icon_size = 36,
  icon_mipmaps = 2,  -- close enough, especially for an icon that shouldn't appear
  subgroup = "other",
  order = "oe-internal",
  stack_size = 1,
  flags = {"hidden", "not-stackable"},
  fuel_category = "oe-internal-fuel",
  fuel_value = "1YJ"  -- effectively infinite
}

-- generate percentage fuels (slow down the loco by x percent using fuel speed & accel modifiers)
for _, percent in ipairs{75, 50, 25, 5} do
  local fuel = table.deepcopy(internal_fuel_item)
  fuel.name = fuel.name .. "-" .. percent
  --table.insert(fuel.flags, "hide-from-fuel-tooltip")   -- only the main one should show up in the tooltip
  --fuel.localised_name = {"item-name.oe-internal-fuel"} -- better name
  -- this fuel slows down the loco by i percent
  local multiplier = percent / 100
  fuel.fuel_top_speed_multiplier = multiplier * 0.8               -- reduce top speed more harshly
  fuel.fuel_acceleration_multiplier = math.max(multiplier, 0.15)  -- prevent 5% from being too slow (would be 0.05)
  -- and makes the burner.remaining_burning_fuel bar show it's percentage as how much is left by increasing the total burn time
  fuel.fuel_value = (100 / percent) .. "YJ"

  log("generating internal fuel " .. percent .. "% with data: " .. serpent.block(fuel))
  data:extend{fuel}
end

-- the prototype name must be "tooltip-category-" followed by the name of the fuel category for the "Consumes x" tooltip to show the icon
local internal_fuel_category_tooltip = table.deepcopy(data.raw["sprite"]["tooltip-category-electricity"])
internal_fuel_category_tooltip.name = "tooltip-category-" .. internal_fuel_category.name

data:extend{internal_fuel_category, internal_fuel_item, internal_fuel_category_tooltip}


-- [[ Technologies & misc ]] --

data:extend{
  {  -- Electric railway technology
    type = "technology",
    name = "oe-electric-railway",
    icon_size = 256,
    icon_mipmaps = 4,
    icon = graphics .. "electric-railway.png",
    effects = {
      {type = "unlock-recipe", recipe = "oe-electric-locomotive"},
      {type = "unlock-recipe", recipe = "oe-transformer"},
      {type = "unlock-recipe", recipe = "oe-catenary-pole"}
      -- double sided pole, combo catenary & big power pole
    },
    prerequisites = {"railway", "electric-engine", "electric-energy-distribution-1"},
    unit = {
      count = 75,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
        {"chemical-science-pack",   1}
      },
      time = 30
    },  -- after railway (c-g-a), before fluid-wagon (c-g-a-b)
    order = "c-g-a-a"
  },
  {  -- Electric railway signals technology
    type = "technology",
    name = "oe-electric-railway-signals",
    icon_size = 256,
    icon_mipmaps = 4,
    icon = graphics .. "electric-railway-signals.png",
    effects = {
      -- power poles with built-in signals
    },
    prerequisites = {"oe-electric-railway", "rail-signals"},
    unit = {
      count = 50,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
        {"chemical-science-pack",   1}
      },
      time = 30
    },  -- after electric-railway (c-g-a-a)
    order = "c-g-a-a-a"
  },
  {  -- order our internal entites on their own row
    type = "item-subgroup",
    name = "oe-other",
    group = "other",
    order = "zz"
  },
  {
    type = "shortcut",
    name = "oe-toggle-powered-rail-view",
    action = "lua",
    toggleable = true,
    technology_to_unlock = "oe-electric-railway",
    ---@type data.Sprite
    icon = {
      filename = "__core__/graphics/icons/tooltips/tooltip-category-electricity.png",
      size = 36,
      mipmap_count = 2
    }
  }
}


-- [[ Catenary wire sprites ]] --

local wire_sprite = {
  type = "sprite",
  name = "oe-catenary-wire",
  filename = graphics .. "catenary-wire.png",
  priority = "extra-high-no-scale",
  flags = {"no-crop"},
  width = 224,
  height = 46,
  hr_version = {
    filename = graphics .. "hr-catenary-wire.png",
    priority = "extra-high-no-scale",
    flags = {"no-crop"},
    width = 448,
    height = 92,
    scale = 0.5
  }
}

local wire_shadow_sprite = table.deepcopy(wire_sprite)
wire_shadow_sprite.name = "oe-catenary-wire-shadow"
wire_shadow_sprite.filename = graphics .. "catenary-wire-shadow.png"
wire_shadow_sprite.hr_version.filename = graphics .. "hr-catenary-wire-shadow.png"

local wire_debug_sprite = table.deepcopy(wire_sprite)
wire_debug_sprite.name = "oe-debug-wire"
wire_debug_sprite.filename = graphics .. "debug-wire.png"
wire_debug_sprite.hr_version.filename = graphics .. "hr-debug-wire.png"

data:extend{wire_sprite, wire_shadow_sprite, wire_debug_sprite}


-- TEMP TESTING STUFF BELOW HERE


-- testing placement restrictions
--[[local test_train_stop = table.deepcopy(data.raw["train-stop"]["train-stop"])
test_train_stop.name = "oe-test-train-stop"
test_train_stop.minable.result = "oe-test-train-stop"
test_train_stop.chart_name = false

local test_train_stop_item = table.deepcopy(data.raw["item"]["train-stop"])
test_train_stop_item.name = "oe-test-train-stop"
test_train_stop_item.place_result = "oe-test-train-stop"

data:extend{test_train_stop, test_train_stop_item}]]


--[[local test_catenary_pole = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
test_catenary_pole.name = "oe-test-catenary-pole"
test_catenary_pole.minable.result = "oe-test-catenary-pole"
test_catenary_pole.item_slot_count = 0
test_catenary_pole.circuit_wire_max_distance = 30 -- connection distance of caternary wires (same as big power poles)

local test_catenary_pole_item = table.deepcopy(data.raw["item"]["constant-combinator"])
test_catenary_pole_item.name = "oe-test-catenary-pole"
test_catenary_pole_item.place_result = "oe-test-catenary-pole"

data:extend{test_catenary_pole, test_catenary_pole_item}]]
