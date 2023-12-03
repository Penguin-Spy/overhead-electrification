--[[ prototypes/generate.lua © Penguin_Spy 2023
  ran in data-final-fixes
  automatically generates an interface for each locomotive with the internal fuel category
]]

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

-- [[ electric locomotive interface ]] --
-- this is the hidden entity that consumes power from the electric network for the locomotive
--  teleported around by the script to be under the correct overhead network's transformer
-- no associated item or recipe

for _, locomotive in pairs(data.raw["locomotive"]) do
  if locomotive.burner then
    -- i think fuel_category (singular) is auto-converted to fuel_categories (plural) by the game between stages, but just in case
    local fuel_categories = util.list_to_map(locomotive.burner.fuel_categories or {locomotive.burner.fuel_category})

    if fuel_categories["oe-internal-fuel"] then
      if #fuel_categories > 1 then
        error("[overhead-electrification] an electric locomotive cannot have multiple fuel categories!\n" ..
          "locomotive " .. tostring(locomotive.name) .. " has burner.fuel_categories: " .. serpent.line(locomotive.burner.fuel_categories))
      end

      local locomotive_power = util.parse_energy(locomotive.max_power) * 60  -- Watts -> Joules (undoes a conversion that util does)

      local locomotive_interface = mimic(locomotive, {
        type = "electric-energy-interface",
        name = locomotive.name .. "-oe-interface",
        flags = {"placeable-off-grid"},
        energy_source = {
          type = "electric",
          usage_priority = "secondary-input",              -- can only input, setting energy_production does nothing
          buffer_capacity = locomotive_power .. "J",       -- 1 second of operation
          input_flow_limit = 2 * locomotive_power .. "W",  -- recharges in 1 second (each second: consumes locomotive_power kJ, recharges locomotive_power kJ into buffer)
          --render_no_network_icon = true,                   -- (default), will show up on the transformer
          --render_no_power_icon = true                      -- (default), will show up on the transformer
        },
        energy_usage = locomotive_power .. "W",  -- set by script to match the locomotive anyways, this is just the default
        picture = {
          filename = "__core__/graphics/empty.png",
          priority = "extra-high",
          width = 1,
          height = 1
        }
      })

      data:extend{locomotive_interface}
    end
  end
end
