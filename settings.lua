data:extend{
  {
    type = "int-setting",
    name = "oe-train-update-rate",
    setting_type = "runtime-global",
    minimum_value = 1,
    maximum_value = 60,
    default_value = 6  -- 6 ticks between each train getting updated
  }
}
