--[[ prototypes/core.lua © Penguin_Spy 2023
  defines prototypes for the locomotive, catenary poles, and transformer
  also defines prototypes for the hidden fuel items & interface entity used to make the locomotive appear to consume electricity
]]

local data_util = require "prototypes.data_util"
local graphics = data_util.graphics
local sounds = require("__base__.prototypes.entity.sounds")

---@param base_picture data.SpriteParameters
---@param rotation integer
---@return data.Sprite
local function get_picture_for_rotation(base_picture, rotation)
  local picture = table.deepcopy(base_picture)  --[[@as data.Sprite]]
  picture.y = picture.height * rotation
  picture.hr_version.y = picture.hr_version.height * rotation
  return picture
end


--[[ === Rail power transformer ===

oe-transformer-electric-pole-[0..3]   -- hidden entity that does the electric network stuff (including showing wires)
                                      -- 4 copies of it, one for each direction
oe-transformer                        -- simple entity that shows graphics and is blueprintable
]]

---@type data.SpriteParameters
local transformer_picture = {
  filename = graphics .. "catenary-pole/transformer.png",
  priority = "extra-high",
  width = 96,
  height = 135,
  shift = {x = 0, y = -1},
  hr_version = {
    filename = graphics .. "catenary-pole/hr-transformer.png",
    priority = "extra-high",
    width = 192,
    height = 270,
    shift = {x = 0, y = -1},
    scale = 0.5,
  }
}
---@type data.SpriteParameters
local transformer_rail_part = {
  filename = graphics .. "catenary-pole/transformer-rail-part.png",
  priority = "high",
  width = 194,
  height = 189,
  hr_version = {
    filename = graphics .. "catenary-pole/hr-transformer-rail-part.png",
    priority = "high",
    width = 386,
    height = 377,
    scale = 0.5,
  },
}

local transformer_icons = {{icon = "__base__/graphics/icons/accumulator.png", icon_size = 64, icon_mipmaps = 4, tint = {r = 1, g = 1, b = 0.7, a = 1}}}
local transformer_wire_connection_points = {
  {x = 1,  y = -3},  -- 0, north,     right
  {x = 0,  y = -2},  -- 2, east,      down
  {x = -1, y = -3},  -- 4, south,     left
  {x = 0,  y = -4},  -- 6, west,      up
}

-- 4 hidden electric poles, 1 for each of the transformer's 4 orientations
for i = 0, 3 do
  data:extend{{
    type = "electric-pole",
    name = "oe-transformer-electric-pole-" .. i,
    tile_width = 2, tile_height = 2,
    build_grid_size = 2,
    collision_mask = {},
    subgroup = "oe-other",

    maximum_wire_distance = 9,  -- allow the transformer to connect to other normal electric poles
    supply_area_distance = 0,
    connection_points = {{
      wire = {
        copper = transformer_wire_connection_points[i + 1]
      },
      shadow = {
        copper = {x = 0, y = 0}  -- TODO: add to list above
      }
    }},
    pictures = {
      direction_count = 1,
      filename = "__core__/graphics/empty.png",
      priority = "extra-high",
      width = 1,
      height = 1
    },
    resistances = {{type = "fire", percent = 100}}
  }  --[[@as data.ElectricPolePrototype]]}
end

-- simple entity to exist in the world (visible, minable, blueprintable, has health & gets destroyed)
local transformer_graphics = {
  type = "simple-entity-with-owner",
  name = "oe-transformer",
  collision_box = {{-0.7, -0.7}, {0.7, 0.7}},
  selection_box = {{-1, -1}, {1, 1}},
  build_grid_size = 2,
  flags = {"placeable-neutral", "player-creation"},
  placeable_by = {item = "oe-transformer", count = 1},
  minable = {mining_time = 0.1, result = "oe-transformer"},
  max_health = 200,
  resistances = {{type = "fire", percent = 90}},
  localised_name = {"entity-name.oe-transformer"},
  localised_description = {"entity-description.oe-transformer"},
  icons = transformer_icons,
  subgroup = "train-transport",

  integration_patch = {
    north = get_picture_for_rotation(transformer_rail_part, 0),
    east = get_picture_for_rotation(transformer_rail_part, 1),
    south = get_picture_for_rotation(transformer_rail_part, 2),
    west = get_picture_for_rotation(transformer_rail_part, 3)
  },
  picture = {
    north = get_picture_for_rotation(transformer_picture, 0),
    east = get_picture_for_rotation(transformer_picture, 1),
    south = get_picture_for_rotation(transformer_picture, 2),
    west = get_picture_for_rotation(transformer_picture, 3)
  },
  water_reflection = data.raw["electric-pole"]["substation"].water_reflection,
  damaged_trigger_effect = data.raw["electric-pole"]["substation"].damaged_trigger_effect,
  dying_explosion = "substation-explosion",
  corpse = "substation-remnants",
  working_sound = data.raw["electric-pole"]["substation"].working_sound,
  vehicle_impact_sound = sounds.generic_impact
}  --[[@as data.SimpleEntityWithOwnerPrototype]]

-- dummy placement entity for placement restrictions for the player, immediately replaced by the real one in control.lua
local transformer_placer = {
  type = "train-stop",
  name = "oe-transformer-placer",
  collision_box = {{-0.7, -0.7}, {0.7, 0.7}},
  selection_box = {{-1, -1}, {1, 1}},
  build_grid_size = 2,
  flags = {"placeable-neutral", "player-creation", "filter-directions"},
  placeable_by = {item = "oe-transformer", count = 1},
  icons = transformer_icons,
  localised_name = {"entity-name.oe-transformer"},
  localised_description = {"entity-description.oe-transformer"},
  subgroup = "oe-other",

  animation_ticks_per_frame = 1,
  chart_name = false,
  rail_overlay_animations = {
    north = get_picture_for_rotation(transformer_rail_part, 2),  -- train stop directions are opposite rail signals.
    east = get_picture_for_rotation(transformer_rail_part, 3),
    south = get_picture_for_rotation(transformer_rail_part, 0),
    west = get_picture_for_rotation(transformer_rail_part, 1)
  },
  animations = {
    north = get_picture_for_rotation(transformer_picture, 2),
    east = get_picture_for_rotation(transformer_picture, 3),
    south = get_picture_for_rotation(transformer_picture, 0),
    west = get_picture_for_rotation(transformer_picture, 1)
  }
}

local transformer_item = {
  type = "item",
  name = "oe-transformer",
  icons = transformer_icons,
  subgroup = "train-transport",
  order = "a[train-system]-z[ovehead-electrification]-b",
  place_result = transformer_placer.name,
  stack_size = 50
}
local transformer_recipe = {
  type = "recipe",
  name = "oe-transformer",
  energy_required = 10,
  enabled = false,
  ingredients = {
    {type = "item", name = "copper-cable",     amount = 20},
    {type = "item", name = "steel-plate",      amount = 10},
    {type = "item", name = "advanced-circuit", amount = 5}
  },
  result = "oe-transformer"
}

data:extend{transformer_graphics, transformer_placer, transformer_item, transformer_recipe}


--[[ === Overhead power line pylons ===

oe-catenary-electric-pole-[0..7]      -- hidden entity that does the electric network stuff (including showing wires)
                                      -- 8 copies of it, one for each direction

oe-normal-catenary-pole-orthogonal    -- simple entities that show graphics and are blueprintable
oe-normal-catenary-pole-diagonal

oe-signal-catenary-pole               -- rail signal, does graphics for all 8 directions, selectable, circuit wireable, blueprintable
oe-chain-catenary-pole                -- chain signal, does graphics for all 8 directions, selectable, circuit wireable, blueprintable
]]

---@type data.SpriteParameters
local catenary_pole_picture = {
  filename = graphics .. "catenary-pole/normal-catenary-pole.png",
  priority = "extra-high",
  width = 96,
  height = 128,
  shift = {x = 0, y = -1.5},
  hr_version = {
    filename = graphics .. "catenary-pole/hr-normal-catenary-pole.png",
    priority = "extra-high",
    width = 192,
    height = 256,
    shift = {x = 0, y = -1.5},
    scale = 0.5,
  }
}

local catenary_pole_icons = {{icon = "__base__/graphics/icons/medium-electric-pole.png", icon_size = 64, icon_mipmaps = 4, tint = {r = 1, g = 1, b = 0.7, a = 1}}}
local catenary_wire_connection_points = {
  {x = 1,  y = -3},  -- 0, north,     right
  {x = 1,  y = -2},  -- 1, northeast, down right
  {x = 0,  y = -2},  -- 2, east,      down
  {x = -1, y = -2},  -- 3, southeast, down left
  {x = -1, y = -3},  -- 4, south,     left
  {x = -1, y = -4},  -- 5, southwest, up left
  {x = 0,  y = -4},  -- 6, west,      up
  {x = 1,  y = -4},  -- 7, northwest, up right
}

-- 8 hidden electric poles, 1 for each of the catenary poles' 8 orientations
for i = 0, 7 do
  data:extend{{
    type = "electric-pole",
    name = "oe-catenary-electric-pole-" .. i,
    tile_width = 1, tile_height = 1,  -- required so entity doesn't snap to tile grid edges
    collision_mask = {},
    subgroup = "oe-other",

    maximum_wire_distance = 0.71,  -- minimum distance to be able to connect catenary and tranformer electric poles via teleporting
    supply_area_distance = 0,
    connection_points = {{
      wire = {
        copper = catenary_wire_connection_points[i + 1]
      },
      shadow = {
        copper = {x = 0, y = 0}  -- TODO: add to list above
      }
    }},
    pictures = {
      direction_count = 1,
      filename = "__core__/graphics/empty.png",
      priority = "extra-high",
      width = 1,
      height = 1
    },
    resistances = {{type = "fire", percent = 100}}
  }  --[[@as data.ElectricPolePrototype]]}
end

-- simple entities to exist in the world (visible, minable, blueprintable, have health & get destroyed)
data:extend{
  {
    type = "simple-entity-with-owner",
    name = "oe-normal-catenary-pole-orthogonal",
    collision_box = {{-0.15, -0.15}, {0.15, 0.15}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    flags = {"placeable-neutral", "player-creation"},
    placeable_by = {item = "oe-catenary-pole", count = 1},
    minable = {mining_time = 0.1, result = "oe-catenary-pole"},
    max_health = 100,
    resistances = {{type = "fire", percent = 100}},
    localised_name = {"entity-name.oe-catenary-pole"},
    localised_description = {"entity-description.oe-catenary-pole"},
    icons = catenary_pole_icons,
    subgroup = "train-transport",

    picture = {
      north = get_picture_for_rotation(catenary_pole_picture, 0),
      east = get_picture_for_rotation(catenary_pole_picture, 2),
      south = get_picture_for_rotation(catenary_pole_picture, 4),
      west = get_picture_for_rotation(catenary_pole_picture, 6)
    },
    water_reflection = data.raw["electric-pole"]["medium-electric-pole"].water_reflection,
    damaged_trigger_effect = data.raw["electric-pole"]["medium-electric-pole"].damaged_trigger_effect,
    dying_explosion = "medium-electric-pole-explosion",
    corpse = "medium-electric-pole-remnants",
    vehicle_impact_sound = sounds.generic_impact
  }  --[[@as data.SimpleEntityWithOwnerPrototype]],
  {
    type = "simple-entity-with-owner",
    name = "oe-normal-catenary-pole-diagonal",
    collision_box = {{-0.15, -0.15}, {0.15, 0.15}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    flags = {"placeable-neutral", "player-creation"},
    placeable_by = {item = "oe-catenary-pole", count = 1},
    minable = {mining_time = 0.1, result = "oe-catenary-pole"},
    max_health = 100,
    resistances = {{type = "fire", percent = 100}},
    localised_name = {"entity-name.oe-catenary-pole"},
    localised_description = {"entity-description.oe-catenary-pole"},
    icons = catenary_pole_icons,
    subgroup = "train-transport",

    picture = {
      north = get_picture_for_rotation(catenary_pole_picture, 1),
      east = get_picture_for_rotation(catenary_pole_picture, 3),
      south = get_picture_for_rotation(catenary_pole_picture, 5),
      west = get_picture_for_rotation(catenary_pole_picture, 7)
    },
    water_reflection = data.raw["electric-pole"]["medium-electric-pole"].water_reflection,
    damaged_trigger_effect = data.raw["electric-pole"]["medium-electric-pole"].damaged_trigger_effect,
    dying_explosion = "medium-electric-pole-explosion",
    corpse = "medium-electric-pole-remnants",
    vehicle_impact_sound = sounds.generic_impact
  }  --[[@as data.SimpleEntityWithOwnerPrototype]]
}

local catenary_pole_placer_animation = table.deepcopy(catenary_pole_picture)  --[[@as data.RotatedAnimation]]
catenary_pole_placer_animation.direction_count = 8
catenary_pole_placer_animation.hr_version.direction_count = 8

-- dummy placement entity for placement restrictions, immediately replaced by the real one in control.lua
local catenary_pole_placer = {
  type = "rail-signal",
  name = "oe-catenary-pole-placer",
  collision_box = {{-0.15, -0.15}, {0.15, 0.15}},
  selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
  flags = {"placeable-neutral", "player-creation", "building-direction-8-way", "filter-directions"},
  placeable_by = {item = "oe-catenary-pole", count = 1},
  localised_name = {"entity-name.oe-catenary-pole"},
  localised_description = {"entity-description.oe-catenary-pole"},
  icons = catenary_pole_icons,
  subgroup = "oe-other",

  animation = catenary_pole_placer_animation,
}  --[[@as data.RailSignalPrototype]]

local catenary_pole_item = {
  type = "item",
  name = "oe-catenary-pole",
  icons = catenary_pole_icons,
  subgroup = "train-transport",
  order = "a[train-system]-z[ovehead-electrification]-a",
  place_result = catenary_pole_placer.name,
  stack_size = 50
}
local catenary_pole_recipe = {
  type = "recipe",
  name = "oe-catenary-pole",
  enabled = false,
  ingredients = {
    {type = "item", name = "copper-cable", amount = 10},
    {type = "item", name = "steel-plate",  amount = 4},
    {type = "item", name = "iron-stick",   amount = 4}
  },
  result = "oe-catenary-pole"
}

data:extend{catenary_pole_placer, catenary_pole_item, catenary_pole_recipe}


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
    },
    prerequisites = {"railway", "electric-engine", "electric-energy-distribution-1"},
    ---@type data.TechnologyUnit
    unit = {
      count = 75,
      ingredients =
      {
        {type = "item", name = "automation-science-pack", amount = 1},
        {type = "item", name = "logistic-science-pack",   amount = 1},
        {type = "item", name = "chemical-science-pack",   amount = 1}
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
        {type = "item", name = "automation-science-pack", amount = 1},
        {type = "item", name = "logistic-science-pack",   amount = 1},
        {type = "item", name = "chemical-science-pack",   amount = 1}
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
