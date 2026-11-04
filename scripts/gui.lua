local config = require("config")
local M = {}
local PANEL = "heavy_tower_crane_panel"

function M.close(player)
  local frame = player.gui.relative[PANEL]
  if frame then frame.destroy() end
  if storage.opened_cranes then storage.opened_cranes[player.index] = nil end
end

function M.open(player, state)
  M.close(player)
  local frame = player.gui.relative.add{
    type = "frame", name = PANEL, direction = "vertical", caption = {"tower-crane.panel-title"},
    anchor = {gui = defines.relative_gui_type.container_gui, position = defines.relative_gui_position.right}
  }
  frame.style.minimal_width = 300
  frame.add{type = "label", name = "status", caption = {"tower-crane.state-idle"}}
  local progress = frame.add{type = "progressbar", name = "progress", value = 0}
  progress.style.horizontally_stretchable = true
  frame.add{type = "label", caption = {"tower-crane.range", config.radius}}
  frame.add{type = "label", caption = {"tower-crane.inventory", config.inventory_size}}
  frame.add{type = "label", name = "power", caption = {"tower-crane.power", 24}}
  frame.add{type = "label", name = "built", caption = {"tower-crane.built", 0}}
  frame.add{type = "label", name = "energy", caption = {"tower-crane.energy", 0}}
  frame.add{type = "checkbox", name = "heavy_tower_enabled", state = not state.paused,
    caption = {"tower-crane.enabled"}, tooltip = {"tower-crane.enabled-tooltip"}, tags = {crane = state.unit_number}}
  local help = frame.add{type = "label", caption = {"tower-crane.panel-help"}}
  help.style.single_line = false
  help.style.maximal_width = 300
  storage.opened_cranes[player.index] = state.unit_number
end

function M.update(player, state, powered)
  local frame = player.gui.relative[PANEL]
  if not state or not state.entity.valid then M.close(player); return end
  if not frame then return end
  local status = state.paused and "paused" or (not powered and "no-power" or state.state)
  frame.status.caption = {"tower-crane.state-" .. status}
  frame.progress.value = state.state == "building" and math.min(1, state.build_progress / config.build_ticks) or 0
  frame.built.caption = {"tower-crane.built", state.total_built}
  frame.energy.caption = {"tower-crane.energy", string.format("%.1f", state.total_energy_consumed / 1000000)}
  frame.heavy_tower_enabled.state = not state.paused
end

return M
