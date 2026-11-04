local config = require("config")
local art = require("graphics.sprite-definitions")
local visuals = require("scripts.visuals")
local gui = require("scripts.gui")
local NAME, POWER = config.name, config.name .. "-power"
local TAU = math.pi * 2
local ENERGY_STEP = config.working_power * config.update_ticks / 60
local HOIST_STEP = (art.hook_raised_bottom_m - art.hook_lowered_bottom_m) * config.update_ticks / (60 * config.hoist_seconds)

local function valid(entity)
  return entity and entity.valid and entity.name == NAME
end

local function distance2(a, b)
  local x, y = a.x - b.x, a.y - b.y
  return x * x + y * y
end

local function destroy(object)
  if object and object.valid then object.destroy() end
end

local function make_power(entity)
  local helper = entity.surface.create_entity{name = POWER, position = entity.position, force = entity.force}
  if helper then helper.destructible = false; helper.operable = false; helper.energy = 0 end
  return helper
end

local function ensure_power(state)
  local power, entity = state.power, state.entity
  if not power or not power.valid then state.power = make_power(entity); return false end
  if power.surface ~= entity.surface then power.destroy(); state.power = make_power(entity); return false end
  if distance2(power.position, entity.position) > .0001 then power.teleport(entity.position) end
  if power.force ~= entity.force then power.force = entity.force end
  return power.electric_network_id ~= nil
end

local function power_ready(state)
  return ensure_power(state) and state.power.energy + .001 >= ENERGY_STEP
end

local function release_target(state)
  if state.target_id and storage.reservations[state.target_id] == state.unit_number then
    storage.reservations[state.target_id] = nil
  end
  state.target, state.target_id, state.cost = nil, nil, nil
  state.build_progress = 0
end

local function register(entity, previous)
  if not valid(entity) or storage.cranes[entity.unit_number] then return end
  local state = {
    entity = entity, unit_number = entity.unit_number, power = make_power(entity),
    state = "idle", orientation = previous and previous.orientation or 0,
    reach = math.min(config.radius, math.max(0, previous and previous.reach or config.rest_radius)),
    hook_height = previous and previous.hook_height or art.hook_raised_bottom_m,
    paused = previous and previous.paused or false,
    build_progress = 0, next_scan = game.tick, idle_since = game.tick, blocked = {},
    total_built = previous and previous.total_built or 0,
    total_energy_consumed = previous and previous.total_energy_consumed or 0
  }
  if state.hook_height < art.hook_raised_bottom_m then state.state = "raising" end
  storage.cranes[entity.unit_number] = state
  visuals.update(state, false)
end

local function cleanup(state)
  release_target(state)
  visuals.clear(state)
  destroy(state.power)
end

local function range_for(player)
  destroy(storage.ranges[player.index])
  storage.ranges[player.index] = nil
  local entity = player.selected
  if not entity or not entity.valid then return end
  if entity.name ~= NAME and not (entity.type == "entity-ghost" and entity.ghost_name == NAME) then return end
  storage.ranges[player.index] = rendering.draw_circle{
    color = {.95, .66, .12, .8}, radius = config.radius, width = 2, filled = false,
    target = entity, surface = entity.surface, players = {player.index}, draw_on_ground = true
  }
end

local function rebuild()
  local old = storage.cranes or {}
  for _, state in pairs(old) do visuals.clear(state); destroy(state.power) end
  for _, object in pairs(storage.ranges or {}) do destroy(object) end
  storage.cranes, storage.reservations, storage.ranges, storage.opened_cranes = {}, {}, {}, {}
  for _, surface in pairs(game.surfaces) do
    for _, helper in pairs(surface.find_entities_filtered{name = POWER}) do helper.destroy() end
    for _, entity in pairs(surface.find_entities_filtered{name = NAME}) do register(entity, old[entity.unit_number]) end
  end
  for _, force in pairs(game.forces) do
    if force.recipes[NAME] and force.technologies[NAME] then force.recipes[NAME].enabled = force.technologies[NAME].researched end
  end
  for _, player in pairs(game.connected_players) do gui.close(player); range_for(player) end
  storage.schema_version = 2
end

local function choose_cost(ghost, inventory, counts)
  local quality = ghost.quality.name
  for _, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
    local have = counts and (counts[item.name .. "@" .. quality] or 0) or inventory.get_item_count{name = item.name, quality = quality}
    if item.count > 0 and (have or 0) >= item.count then return {name = item.name, count = item.count, quality = quality} end
  end
end

local function target_valid(state)
  local ghost, entity = state.target, state.entity
  return ghost and ghost.valid and ghost.type == "entity-ghost" and ghost.force == entity.force
    and ghost.surface == entity.surface and distance2(ghost.position, entity.position) <= config.radius ^ 2
end

local function acquire_target(state)
  local entity = state.entity
  local inventory = entity.get_inventory(defines.inventory.chest)
  if inventory.is_empty() then return false end
  local counts = {}
  for _, stack in pairs(inventory.get_contents()) do counts[stack.name .. "@" .. stack.quality] = stack.count end
  local selected, best = nil, math.huge
  for _, ghost in pairs(entity.surface.find_entities_filtered{position = entity.position, radius = config.radius, type = "entity-ghost", force = entity.force}) do
    local id = ghost.unit_number
    local squared = distance2(ghost.position, entity.position)
    if id and squared >= 16 and squared <= config.radius ^ 2 and not storage.reservations[id]
      and (not state.blocked[id] or state.blocked[id] <= game.tick) then
      local cost = choose_cost(ghost, inventory, counts)
      if cost and (squared < best or (squared == best and id < selected.id)) then
        best, selected = squared, {ghost = ghost, id = id, cost = cost}
      end
    end
  end
  if not selected then return false end
  state.target, state.target_id, state.cost = selected.ghost, selected.id, selected.cost
  storage.reservations[selected.id] = state.unit_number
  state.target_orientation = (math.atan2(selected.ghost.position.x - entity.position.x, entity.position.y - selected.ghost.position.y) / TAU) % 1
  state.target_reach = math.sqrt(best)
  state.state = "rotating"
  entity.surface.play_sound{path = NAME .. "-drive", position = entity.position, volume_modifier = .65}
  return true
end

local function return_items(buffer, entity, surface, position, force)
  local inventory = valid(entity) and entity.get_inventory(defines.inventory.chest) or nil
  for i = 1, #buffer do
    local stack = buffer[i]
    if stack.valid_for_read then
      local inserted = inventory and inventory.valid and inventory.insert(stack) or 0
      if inserted > 0 then stack.count = stack.count - inserted end
      if stack.valid_for_read then
        surface.spill_item_stack{position = position, stack = stack, force = force, enable_looted = false, allow_belts = false}
        stack.clear()
      end
    end
  end
  buffer.destroy()
end

local function construct(state)
  if not target_valid(state) then return end
  local entity, ghost = state.entity, state.target
  local inventory = entity.get_inventory(defines.inventory.chest)
  local cost = choose_cost(ghost, inventory)
  if not cost then return end
  local surface, position, force = entity.surface, entity.position, entity.force
  local buffer, remaining, slot = game.create_inventory(#inventory), cost.count, 1
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == cost.name and stack.quality.name == cost.quality then
      local taken = math.min(remaining, stack.count)
      buffer[slot].set_stack(stack)
      buffer[slot].count = taken
      stack.count = stack.count - taken
      remaining, slot = remaining - taken, slot + 1
      if remaining == 0 then break end
    end
  end
  if remaining > 0 then return_items(buffer, entity, surface, position, force); return end
  local _, built = ghost.revive{raise_revive = true, overflow = inventory}
  if built then
    buffer.destroy()
    state.total_built = state.total_built + 1
  else
    return_items(buffer, entity, surface, position, force)
    state.blocked[state.target_id] = game.tick + config.blocked_retry_ticks
  end
end

local function set_enabled(state, enabled)
  state.paused = not enabled
  if state.paused then release_target(state); state.state = "raising" end
end

local function update(state, tick)
  local entity = state.entity
  local connected = ensure_power(state)
  if state.paused then visuals.update(state, connected); return end
  if entity.to_be_deconstructed(entity.force) then
    release_target(state); state.state = "raising"; visuals.update(state, connected); return
  end
  if state.target and (not target_valid(state) or not choose_cost(state.target, entity.get_inventory(defines.inventory.chest))) then
    release_target(state); state.state = "raising"
  end
  if state.state == "idle" then
    if tick >= state.next_scan then
      state.next_scan = tick + config.scan_ticks
      for id, retry in pairs(state.blocked) do if retry <= tick then state.blocked[id] = nil end end
      if power_ready(state) then acquire_target(state) end
    end
    if state.state == "idle" and tick - state.idle_since >= config.idle_park_ticks and math.abs(state.reach - config.rest_radius) > .001 then
      state.state = "parking"
    end
    if state.state == "idle" then visuals.update(state, connected); return end
  end
  if not power_ready(state) then
    if state.target then
      state.power_lost_since = state.power_lost_since or tick
      if tick - state.power_lost_since >= config.reservation_power_grace_ticks then
        release_target(state); state.state = "raising"
      end
    end
    visuals.update(state, connected)
    return
  end
  state.power_lost_since = nil
  state.power.energy = math.max(0, state.power.energy - ENERGY_STEP)
  state.total_energy_consumed = state.total_energy_consumed + ENERGY_STEP
  if state.state == "rotating" then
    local difference = (state.target_orientation - state.orientation + .5) % 1 - .5
    local step = config.rotation_per_tick * config.update_ticks
    if math.abs(difference) <= step then state.orientation = state.target_orientation; state.state = "travelling"
    else state.orientation = (state.orientation + (difference > 0 and step or -step)) % 1 end
  elseif state.state == "travelling" then
    local difference, step = state.target_reach - state.reach, config.trolley_speed * config.update_ticks
    if math.abs(difference) <= step then state.reach = state.target_reach; state.state = "lowering"
    else state.reach = state.reach + (difference > 0 and step or -step) end
  elseif state.state == "lowering" then
    state.hook_height = math.max(art.hook_lowered_bottom_m, state.hook_height - HOIST_STEP)
    if state.hook_height <= art.hook_lowered_bottom_m then state.state = "building" end
  elseif state.state == "building" then
    state.build_progress = state.build_progress + config.update_ticks
    if state.build_progress >= config.build_ticks then construct(state); release_target(state); state.state = "raising" end
  elseif state.state == "raising" then
    state.hook_height = math.min(art.hook_raised_bottom_m, state.hook_height + HOIST_STEP)
    if state.hook_height >= art.hook_raised_bottom_m then state.state = "idle"; state.idle_since = tick; state.next_scan = tick end
  elseif state.state == "parking" then
    local difference, step = config.rest_radius - state.reach, config.trolley_speed * config.update_ticks
    if math.abs(difference) <= step then state.reach = config.rest_radius; state.state = "idle"; state.idle_since = tick
    else state.reach = state.reach + (difference > 0 and step or -step) end
  end
  if entity.valid then visuals.update(state, connected) end
end

script.on_init(rebuild)
script.on_configuration_changed(rebuild)
script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity, defines.events.script_raised_built, defines.events.script_raised_revive}, function(event) register(event.entity) end)
script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  if entity and entity.valid and entity.name == POWER then entity.destroy() else register(entity) end
end)
script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died, defines.events.script_raised_destroy}, function(event)
  local entity = event.entity
  if valid(entity) then
    local state = storage.cranes[entity.unit_number]
    if state then cleanup(state); storage.cranes[entity.unit_number] = nil end
  end
end)
script.on_event(defines.events.on_selected_entity_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then range_for(player) end
end)
script.on_event(defines.events.on_gui_opened, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if valid(event.entity) then gui.open(player, storage.cranes[event.entity.unit_number]) else gui.close(player) end
end)
script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if player then gui.close(player) end
end)
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
  local element = event.element
  if element and element.valid and element.name == "heavy_tower_enabled" then
    local state = storage.cranes[element.tags.crane]
    local player = game.get_player(event.player_index)
    if state and player and state.entity.valid and state.entity.force == player.force then set_enabled(state, element.state) end
  end
end)
script.on_event(defines.events.on_player_left_game, function(event)
  destroy(storage.ranges[event.player_index]); storage.ranges[event.player_index] = nil
  storage.opened_cranes[event.player_index] = nil
end)
script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  if player then gui.close(player); range_for(player) end
end)

script.on_nth_tick(config.update_ticks, function(event)
  for id, state in pairs(storage.cranes) do
    if not valid(state.entity) then cleanup(state); storage.cranes[id] = nil else update(state, event.tick) end
  end
  if event.tick % 30 == 0 then
    for player_index, unit_number in pairs(storage.opened_cranes) do
      local player, state = game.get_player(player_index), storage.cranes[unit_number]
      if player and player.valid then gui.update(player, state, state and power_ready(state)) else storage.opened_cranes[player_index] = nil end
    end
  end
end)

remote.add_interface(NAME, {
  constants = function() local result = {}; for key, value in pairs(config) do result[key] = value end; return result end,
  set_enabled = function(unit_number, enabled)
    local state = storage.cranes[unit_number]
    if not state or not state.entity.valid then return false end
    set_enabled(state, enabled); return true
  end,
  diagnostics = function()
    local result = {}
    for id, state in pairs(storage.cranes) do
      result[id] = {
        unit_number = id, state = state.state, orientation = state.orientation,
        reach = state.reach, hook_height = state.hook_height, paused = state.paused,
        build_progress = state.build_progress, total_built = state.total_built,
        total_energy_consumed = state.total_energy_consumed,
        connected = state.power and state.power.valid and state.power.electric_network_id ~= nil,
        buffer_energy = state.power and state.power.valid and state.power.energy or 0,
        position = state.entity.valid and state.entity.position or nil,
        target_id = state.target_id,
        target_position = state.target and state.target.valid and state.target.position or nil
      }
    end
    return result
  end
})
