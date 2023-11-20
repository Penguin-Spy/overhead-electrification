--[[ data.lua © Penguin_Spy 2023
  requires the mods' core prototypes, as well as prototype scripts for mod compatability
]]

require 'prototypes.core'

if mods["aai-industry"] then
  require 'prototypes.aai-industry'
end

if mods["space-exploration"] then
  require 'prototypes.space-exploration'
end
