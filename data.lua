local config = require("config")
local art = require("graphics.sprite-definitions")
local name = config.name
local root = "__" .. name .. "__/"
local empty = {filename = "__core__/graphics/empty.png", width = 1, height = 1}

local crane = table.deepcopy(data.raw.container["steel-chest"])
crane.name = name
crane.icon = root .. "graphics/icon.png"
crane.icon_size = 128
crane.minable = {mining_time = 6, result = name}
crane.max_health = 12000
crane.inventory_size = config.inventory_size
crane.quality_affects_inventory_size = false
crane.collision_box = {{-5.6, -5.1}, {5.6, 5.1}}
crane.selection_box = {{-6, -6}, {6, 6}}
crane.tile_width = config.footprint_width
crane.tile_height = config.footprint_height
crane.fast_replaceable_group = nil
crane.next_upgrade = nil
crane.drawing_box_vertical_extension = 40
crane.circuit_wire_max_distance = 64
crane.picture = {layers = {table.deepcopy(art.foundation_shadow), table.deepcopy(art.foundation)}}

-- The large electrical footprint allows a pole to supply the crane from its
-- perimeter. Collision masks stay empty: only the visible foundation collides.
local power = {
  type = "electric-energy-interface", name = name .. "-power",
  flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"},
  hidden = true, hidden_in_factoriopedia = true,
  max_health = 1, selectable_in_game = false,
  collision_box = table.deepcopy(crane.collision_box), collision_mask = {layers = {}},
  selection_box = {{0, 0}, {0, 0}},
  energy_source = {
    type = "electric", buffer_capacity = "4.8MJ", usage_priority = "secondary-input",
    input_flow_limit = "24MW", output_flow_limit = "0W", drain = "0W"
  },
  energy_production = "0W", energy_usage = "0W", picture = table.deepcopy(empty),
  allow_copy_paste = false
}

data:extend({
  crane, power,
  {type = "recipe-category", name = name .. "-assembly"},
  {
    type = "item", name = name, icon = crane.icon, icon_size = 128,
    subgroup = "production-machine", order = "z[heavy-tower-crane]",
    place_result = name, stack_size = 1,
    weight = 1000000
  },
  {
    type = "recipe", name = name, categories = {name .. "-assembly"}, enabled = false,
    energy_required = 120,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 300},
      {type = "item", name = "iron-gear-wheel", amount = 200},
      {type = "item", name = "electronic-circuit", amount = 100},
      {type = "item", name = "engine-unit", amount = 40},
      {type = "item", name = "stone-brick", amount = 400}
    },
    results = {{type = "item", name = name, amount = 1}},
    allow_as_intermediate = false
  },
  {
    type = "technology", name = name, icon = crane.icon, icon_size = 128,
    prerequisites = {"railway", "automation"},
    effects = {{type = "unlock-recipe", recipe = name}},
    unit = {count = 150, ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}, time = 30},
    order = "c-k-z[heavy-tower-crane]"
  },
  {
    type = "sound", name = name .. "-drive",
    variations = {{filename = "__base__/sound/inserter-long-handed.ogg", volume = 0.45}}
  }
})

for kind, frames in pairs(art.frames) do
  for index, definition in ipairs(frames) do
    local sprite = table.deepcopy(definition)
    sprite.type = "sprite"
    sprite.name = name .. "-" .. kind .. "-" .. (index - 1)
    data:extend({sprite})
  end
end
