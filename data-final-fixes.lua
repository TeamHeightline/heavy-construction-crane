local category = require("config").name .. "-assembly"
for _, machine in pairs(data.raw["assembling-machine"]) do
  machine.crafting_categories = machine.crafting_categories or {}
  local found, compatible = false, false
  for _, value in pairs(machine.crafting_categories) do
    if value == category then found = true; break end
    if value == "crafting" or value == "advanced-crafting" then compatible = true end
  end
  if compatible and not found then table.insert(machine.crafting_categories, category) end
end
