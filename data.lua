local config = require("config")
local art = require("graphics.sprite-definitions")
local name = config.name
local root = "__" .. name .. "__/"
local empty = {filename = "__core__/graphics/empty.png", width = 1, height = 1}

local crane = table.deepcopy(data.raw.container["steel-chest"])
crane.name = name
crane.icon = root .. "graphics/icon.png"
crane.icon_size = 128
crane.minable = {mining_time = 1.5, result = name}
crane.max_health = 1500
crane.inventory_size = config.inventory_size
crane.quality_affects_inventory_size = false
crane.collision_box = {{-1.8, -1.8}, {1.8, 1.8}}
crane.selection_box = {{-2, -2}, {2, 2}}
crane.tile_width = 4
crane.tile_height = 4
crane.fast_replaceable_group = nil
crane.next_upgrade = nil
crane.drawing_box_vertical_extension = 16
-- A fixed foundation remains visible for placement previews and entity ghosts;
-- runtime frames draw the moving upper assembly over this same foundation.
crane.picture = table.deepcopy(art.foundation)

-- JSON migration renames the old 80-slot containers before the new 10-slot
-- prototype is applied. Lua then transfers intact stacks and spills overflow.
local legacy = table.deepcopy(crane)
legacy.name = name .. "-legacy"
legacy.inventory_size = 80
legacy.quality_affects_inventory_size = true
legacy.max_health = 2500
legacy.hidden = true
legacy.hidden_in_factoriopedia = true
legacy.flags = {"placeable-player", "player-creation", "not-blueprintable", "not-deconstructable"}

local power = {
  type = "electric-energy-interface", name = name .. "-power",
  flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"},
  hidden = true, hidden_in_factoriopedia = true,
  max_health = 1, selectable_in_game = false,
  collision_box = {{0, 0}, {0, 0}}, collision_mask = {layers = {}},
  selection_box = {{0, 0}, {0, 0}},
  energy_source = {
    type = "electric", buffer_capacity = "360kJ", usage_priority = "secondary-input",
    input_flow_limit = "1.8MW", output_flow_limit = "0W", drain = "0W"
  },
  energy_production = "0W", energy_usage = "0W", picture = table.deepcopy(empty),
  allow_copy_paste = false
}

data:extend({
  crane, legacy, power,
  {type = "recipe-category", name = name .. "-assembly"},
  {
    type = "item", name = name, icon = crane.icon, icon_size = 128,
    subgroup = "production-machine", order = "z[heavy-construction-crane]",
    place_result = name, stack_size = 10
  },
  {
    type = "recipe", name = name, category = name .. "-assembly", enabled = false,
    energy_required = 20,
    ingredients = {
      {type = "item", name = "iron-plate", amount = 80},
      {type = "item", name = "iron-gear-wheel", amount = 40},
      {type = "item", name = "electronic-circuit", amount = 20},
      {type = "item", name = "copper-plate", amount = 40},
      {type = "item", name = "stone-brick", amount = 30}
    },
    results = {{type = "item", name = name, amount = 1}},
    allow_as_intermediate = false
  },
  {
    type = "technology", name = name, icon = crane.icon, icon_size = 128,
    prerequisites = {"automation"},
    effects = {{type = "unlock-recipe", recipe = name}},
    unit = {count = 100, ingredients = {{"automation-science-pack", 1}}, time = 30},
    order = "a-b-z[heavy-construction-crane]"
  }
})

for extension = 0, art.extensions - 1 do
  for direction = 0, art.directions - 1 do
    local sprite = table.deepcopy(art.frames[extension * art.directions + direction + 1])
    sprite.type = "sprite"
    sprite.name = name .. "-frame-" .. direction .. "-" .. extension
    data:extend({sprite})
  end
end
