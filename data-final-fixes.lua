-- se-space-trains expects its items to exist during data-updates
if mods["se-space-trains"] then
  require "prototypes.compat.se-space-trains"
end

-- must be absolutley last
require "prototypes.generate"
