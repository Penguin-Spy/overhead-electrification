--[[ data.lua © Penguin_Spy 2023
  requires the mods' core prototypes, as well as prototype scripts for mod compatability

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

require 'prototypes.core'

if mods["aai-industry"] then
  require 'prototypes.aai-industry'
end

if mods["space-exploration"] then
  require 'prototypes.space-exploration'
end
