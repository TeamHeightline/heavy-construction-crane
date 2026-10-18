local category = require("config").name .. "-assembly"
-- A dedicated category keeps this recipe out of character hand crafting, even
-- when other mods expand the character's usual crafting categories.
for _, machine in pairs(data.raw["assembling-machine"]) do
  machine.crafting_categories = machine.crafting_categories or {}
  local found, is_assembler = false, false
  for _, value in pairs(machine.crafting_categories) do
    if value == category then found = true; break end
    if value == "crafting" or value == "advanced-crafting" then is_assembler = true end
  end
  if is_assembler and not found then table.insert(machine.crafting_categories, category) end
end
