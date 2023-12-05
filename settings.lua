data:extend{
  {
    type = "int-setting",
    name = "oe-train-update-rate",
    setting_type = "runtime-global",
    minimum_value = 1,
    maximum_value = 60,
    default_value = 6  -- 6 ticks between each train getting updated
  },
  -- SE Space Trains
  {
    type = "bool-setting",
    name = "oe-se-space-train-compat",
    setting_type = "startup",
    default_value = true,
  },
  {
    type = "bool-setting",
    name = "oe-se-space-train-remove-batteries",
    setting_type = "startup",
    default_value = true,
  }
}

if not mods["se-space-trains"] then
  data.raw["bool-setting"]["oe-se-space-train-compat"].hidden = true
  data.raw["bool-setting"]["oe-se-space-train-remove-batteries"].hidden = true
end
