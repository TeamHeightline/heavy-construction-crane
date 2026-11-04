local config = require("config")
local art = require("graphics.sprite-definitions")
local M = {}
local TAU = math.pi * 2
local SCALE = art.tiles_per_m

local function destroy(object)
  if object and object.valid then object.destroy() end
end

function M.clear(state)
  for key, object in pairs(state.visuals or {}) do
    if key == "ropes" or key == "lights" then
      for _, child in pairs(object) do destroy(child) end
    else destroy(object) end
  end
  state.visuals = nil
  state.last_visual = nil
end

local function attach(entity, offset)
  return {entity = entity, offset = offset}
end

local function make_sprite(state, key, index, offset, correction, layer)
  local objects = state.visuals
  local object = objects[key]
  local sprite = config.name .. "-" .. key .. "-" .. (index - 1)
  if not object or not object.valid then
    object = rendering.draw_sprite{
      sprite = sprite, surface = state.entity.surface,
      target = attach(state.entity, offset), orientation = correction % 1,
      render_layer = layer, tall = key ~= "upper-shadow"
    }
    objects[key] = object
  else
    object.sprite = sprite
    object.target = attach(state.entity, offset)
    object.orientation = correction % 1
    object.render_layer = layer
  end
end

local function rotate(x, y, angle)
  local c, s = math.cos(angle), math.sin(angle)
  return x * c - y * s, x * s + y * c
end

local function line(state, index, from, to, visible)
  local object = state.visuals.ropes[index]
  if not object or not object.valid then
    object = rendering.draw_line{
      surface = state.entity.surface, from = attach(state.entity, from), to = attach(state.entity, to),
      color = {0.16, 0.15, 0.13, 1}, width = 1, tall = true, visible = visible
    }
    state.visuals.ropes[index] = object
  else
    object.from = attach(state.entity, from)
    object.to = attach(state.entity, to)
    object.visible = visible
  end
end

function M.update(state, powered)
  if not state.entity.valid then return end
  local previous = state.last_visual
  if previous and previous[1] == state.orientation and previous[2] == state.reach
    and previous[3] == state.hook_height and previous[4] == powered
    and state.visuals and state.visuals.upper and state.visuals.upper.valid
    and state.visuals.hook and state.visuals.hook.valid then return end
  state.visuals = state.visuals or {ropes = {}, lights = {}}
  local objects = state.visuals
  objects.ropes = objects.ropes or {}
  objects.lights = objects.lights or {}
  local index = math.floor(state.orientation * art.directions + 0.5) % art.directions + 1
  local correction = (state.orientation - (index - 1) / art.directions + 0.5) % 1 - 0.5
  local angle = correction * TAU
  local phi = state.orientation * TAU
  local ux, uy = math.sin(phi), -math.cos(phi)
  local vx, vy = -math.cos(phi), -math.sin(phi)
  local function center(key)
    local value = art.centers[key][index]
    local x, y = rotate(value[1] * SCALE, value[2] * SCALE, angle)
    return x, y
  end
  local x, y = center("upper")
  make_sprite(state, "upper", index, {x, y - art.pivot_height_m * SCALE}, correction, "higher-object-above")
  x, y = center("upper-shadow")
  make_sprite(state, "upper-shadow", index,
    {x + art.shadow_vector[1] * art.pivot_height_m * SCALE, y - art.shadow_vector[2] * art.pivot_height_m * SCALE},
    correction, "object-under")
  x, y = center("trolley")
  make_sprite(state, "trolley", index,
    {x + ux * state.reach, y + uy * state.reach - art.pivot_height_m * SCALE}, correction, "higher-object-under")
  x, y = center("hook")
  local hook_x, hook_y = ux * state.reach, uy * state.reach - state.hook_height * SCALE
  local behind = uy < 0 and math.abs(hook_x) < 1.8 and hook_y > -art.pivot_height_m * SCALE + .6
  make_sprite(state, "hook", index, {x + hook_x, y + hook_y}, correction,
    behind and "object-under" or "higher-object-above")
  local n = 0
  for _, along in ipairs({-0.235, 0.235}) do
    for _, across in ipairs({-0.075, 0.075}) do
      n = n + 1
      local ox = (ux * along + vx * across) * SCALE
      local oy = (uy * along + vy * across) * SCALE
      local from_y = uy * state.reach + oy - art.hoist_top_m * SCALE
      local to_y = uy * state.reach + oy - (state.hook_height + art.hook_height_m * art.hook_attachment_ratio) * SCALE
      local rope_x = ux * state.reach + ox
      if uy < 0 and math.abs(rope_x) < 1.8 then to_y = math.min(to_y, -art.pivot_height_m * SCALE + .6) end
      line(state, n, {rope_x, from_y}, {rope_x, to_y}, to_y > from_y)
    end
  end
  for _, side in ipairs({-0.12, 0.12}) do
    n = n + 1
    line(state, n,
      {(ux * .7 + vx * side) * SCALE, (uy * .7 + vy * side - art.pivot_height_m - .82) * SCALE},
      {ux * state.reach + vx * side * SCALE, uy * state.reach + (vy * side - art.hoist_top_m - .24) * SCALE}, true)
  end
  for index, offset in ipairs({{-4, -3}, {4, -3}, {-4, 3}, {4, 3}}) do
    local object = objects.lights[index]
    if not object or not object.valid then
      object = rendering.draw_light{
        sprite = "utility/light_medium", target = attach(state.entity, offset),
        surface = state.entity.surface, scale = 1.5, intensity = .55,
        color = {1, .82, .52}, minimum_darkness = .25
      }
      objects.lights[index] = object
    end
    object.visible = powered
  end
  if not objects.work_light or not objects.work_light.valid then
    objects.work_light = rendering.draw_light{
      sprite = "utility/light_medium", target = state.entity, surface = state.entity.surface,
      scale = 2, intensity = .65, color = {1, .87, .65}, minimum_darkness = .25
    }
  end
  objects.work_light.target = attach(state.entity, {ux * state.reach, uy * state.reach})
  objects.work_light.visible = powered
  if not objects.warning or not objects.warning.valid then
    objects.warning = rendering.draw_sprite{
      sprite = "utility/electricity_icon_unplugged", target = attach(state.entity, {0, -3}),
      surface = state.entity.surface, render_layer = "entity-info-icon", x_scale = 1, y_scale = 1
    }
  end
  objects.warning.visible = not powered
  state.last_visual = {state.orientation, state.reach, state.hook_height, powered}
end

return M
