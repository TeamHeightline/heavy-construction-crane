local config = require("config")
local graphics = require("graphics.sprite-definitions")
local NAME = config.name
local POWER = NAME .. "-power"
local LEGACY = NAME .. "-legacy"
local TAU = math.pi * 2
local ENERGY_PER_UPDATE = config.working_power * config.update_ticks / 60

local function destroy_render(object)
  if object and object.valid then object.destroy() end
end

local function valid_crane(entity)
  return entity and entity.valid and entity.name == NAME
end

local function distance_squared(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return dx * dx + dy * dy
end

local function sprite_name(direction, extension)
  return NAME .. "-frame-" .. direction .. "-" .. extension
end

local function update_art(state)
  local direction = math.floor(state.orientation * graphics.directions + 0.5) % graphics.directions
  local extension = math.floor(state.extension * (graphics.extensions - 1) + 0.5)
  local frame = extension * graphics.directions + direction
  if not state.art or not state.art.valid then
    state.art = rendering.draw_sprite{
      sprite = sprite_name(direction, extension), surface = state.entity.surface,
      target = state.entity, render_layer = "higher-object-above"
    }
  elseif frame ~= state.frame then
    state.art.sprite = sprite_name(direction, extension)
  end
  state.frame = frame
end

local function make_power(entity)
  local power = entity.surface.create_entity{name = POWER, position = entity.position, force = entity.force}
  if power then power.destructible = false; power.energy = 0 end
  return power
end

local function register(entity)
  if not valid_crane(entity) or storage.cranes[entity.unit_number] then return end
  local state = {
    entity = entity, unit_number = entity.unit_number, power = make_power(entity), state = "idle", orientation = 0,
    extension = 0, build_progress = 0, next_scan = game.tick,
    blocked = {}, total_built = 0, total_energy_consumed = 0
  }
  storage.cranes[entity.unit_number] = state
  update_art(state)
end

local function release_target(state)
  if state.target_id and storage.reservations[state.target_id] == state.unit_number then
    storage.reservations[state.target_id] = nil
  end
  state.target, state.target_id, state.cost = nil, nil, nil
  state.build_progress = 0
  state.power_lost_since = nil
end

local function cleanup(state)
  release_target(state)
  destroy_render(state.art)
  if state.power and state.power.valid then state.power.destroy() end
end

local function range_for(player)
  destroy_render(storage.ranges[player.index])
  storage.ranges[player.index] = nil
  local entity = player.selected
  if not entity or not entity.valid then return end
  if entity.name ~= NAME and not (entity.type == "entity-ghost" and entity.ghost_name == NAME) then return end
  storage.ranges[player.index] = rendering.draw_circle{
    color = {r = 0.95, g = 0.66, b = 0.12, a = 0.8}, radius = config.radius,
    width = 2, filled = false, target = entity, surface = entity.surface,
    players = {player.index}, draw_on_ground = true, only_in_alt_mode = false
  }
end

local function spill_stack(surface, position, force, stack)
  if not stack.valid_for_read then return end
  surface.spill_item_stack{position = position, stack = stack, force = force, enable_looted = false, allow_belts = false}
  stack.clear()
end

local function return_reserved(buffer, entity, surface, position, force)
  local inventory = valid_crane(entity) and entity.get_inventory(defines.inventory.chest) or nil
  for i = 1, #buffer do
    local stack = buffer[i]
    if stack.valid_for_read then
      local inserted = inventory and inventory.valid and inventory.insert(stack) or 0
      if inserted > 0 then stack.count = stack.count - inserted end
      if stack.valid_for_read then spill_stack(surface, position, force, stack) end
    end
  end
  buffer.destroy()
end

local function migrate_legacy(surface)
  for _, old in pairs(surface.find_entities_filtered{name = LEGACY}) do
    local position, force, quality = old.position, old.force, old.quality
    local health_ratio = old.health / old.max_health
    local last_user = old.last_user
    local source = old.get_inventory(defines.inventory.chest)
    local buffer = game.create_inventory(#source)
    for i = 1, #source do buffer[i].transfer_stack(source[i]) end
    old.destroy()
    local entity = surface.create_entity{name = NAME, position = position, force = force, quality = quality}
    if entity then
      entity.health = entity.max_health * health_ratio
      if last_user and last_user.valid then entity.last_user = last_user end
      return_reserved(buffer, entity, surface, position, force)
    else
      -- Preserve inventory and refund the crane even if another mod prevents replacement.
      return_reserved(buffer, nil, surface, position, force)
      surface.spill_item_stack{position = position, stack = {name = NAME, count = 1, quality = quality}, force = force, enable_looted = false, allow_belts = false}
    end
  end
end

local function rebuild()
  for _, state in pairs(storage.cranes or {}) do
    destroy_render(state.art)
    if state.power and state.power.valid then state.power.destroy() end
  end
  for _, object in pairs(storage.ranges or {}) do destroy_render(object) end
  storage.cranes, storage.reservations, storage.ranges = {}, {}, {}
  for _, surface in pairs(game.surfaces) do
    for _, power in pairs(surface.find_entities_filtered{name = POWER}) do power.destroy() end
    migrate_legacy(surface)
    for _, entity in pairs(surface.find_entities_filtered{name = NAME}) do register(entity) end
  end
  -- The 0.2 draft enabled its recipe unconditionally; existing forces retain
  -- recipe enablement across prototype changes unless explicitly synchronized.
  for _, force in pairs(game.forces) do
    local recipe, technology = force.recipes[NAME], force.technologies[NAME]
    if recipe and technology then recipe.enabled = technology.researched end
  end
  for _, player in pairs(game.connected_players) do range_for(player) end
end

local function choose_cost(ghost, inventory)
  local quality = ghost.quality.name
  for _, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
    local cost = {name = item.name, count = item.count, quality = quality}
    if cost.count > 0 and inventory.get_item_count(cost) >= cost.count then return cost end
  end
end

local function target_valid(state)
  local ghost, entity = state.target, state.entity
  return ghost and ghost.valid and ghost.type == "entity-ghost" and ghost.force == entity.force
    and ghost.surface == entity.surface and distance_squared(ghost.position, entity.position) <= config.radius ^ 2
end

local function acquire_target(state, tick)
  local entity = state.entity
  local inventory = entity.get_inventory(defines.inventory.chest)
  if inventory.is_empty() then return end
  local candidates = {}
  for _, ghost in pairs(entity.surface.find_entities_filtered{
    position = entity.position, radius = config.radius, type = "entity-ghost", force = entity.force
  }) do
    local id = ghost.unit_number
    local distance = distance_squared(ghost.position, entity.position)
    if id and distance <= config.radius ^ 2 and not storage.reservations[id]
      and (not state.blocked[id] or state.blocked[id] <= tick) then
      local cost = choose_cost(ghost, inventory)
      if cost then candidates[#candidates + 1] = {ghost = ghost, id = id, cost = cost, distance = distance} end
    end
  end
  table.sort(candidates, function(a, b)
    if a.distance == b.distance then return a.id < b.id end
    return a.distance < b.distance
  end)
  local candidate = candidates[1]
  if candidate then
    state.target, state.target_id, state.cost = candidate.ghost, candidate.id, candidate.cost
    storage.reservations[candidate.id] = entity.unit_number
    state.target_orientation = (math.atan2(candidate.ghost.position.x - entity.position.x,
      entity.position.y - candidate.ghost.position.y) / TAU) % 1
    state.target_extension = math.min(1, math.sqrt(candidate.distance) / config.radius)
    state.state = "rotating"
  end
end

local function reserve_items(inventory, cost)
  -- Keep full stack metadata so a failed revival returns the exact items.
  local buffer = game.create_inventory(#inventory)
  local remaining = cost.count
  local slot = 1
  for i = 1, #inventory do
    local stack = inventory[i]
    if stack.valid_for_read and stack.name == cost.name and stack.quality.name == cost.quality then
      local taken = math.min(remaining, stack.count)
      buffer[slot].set_stack(stack)
      buffer[slot].count = taken
      stack.count = stack.count - taken
      remaining = remaining - taken
      slot = slot + 1
      if remaining == 0 then return buffer end
    end
  end
  return buffer, remaining
end

local function construct(state, tick)
  if not target_valid(state) then return false end
  local entity = state.entity
  local inventory = entity.get_inventory(defines.inventory.chest)
  local cost = choose_cost(state.target, inventory)
  if not cost then return false end
  local surface, position, force = entity.surface, entity.position, entity.force
  local buffer, missing = reserve_items(inventory, cost)
  if missing then
    return_reserved(buffer, entity, surface, position, force)
    return false
  end
  local _, built = state.target.revive{raise_revive = true, overflow = inventory}
  if built then
    buffer.destroy()
    state.total_built = state.total_built + 1
    return true
  end
  return_reserved(buffer, entity, surface, position, force)
  state.blocked[state.target_id] = tick + config.blocked_retry_ticks
  return false
end

local function power_ready(state)
  local power = state.power
  if not power or not power.valid then state.power = make_power(state.entity); return false end
  if power.surface ~= state.entity.surface then
    power.destroy(); state.power = make_power(state.entity); return false
  end
  if distance_squared(power.position, state.entity.position) > 0.0001 then power.teleport(state.entity.position) end
  if power.force ~= state.entity.force then power.force = state.entity.force end
  if not power.electric_network_id or power.energy + 0.001 < ENERGY_PER_UPDATE then return false end
  return true
end

local function take_power(state)
  if not power_ready(state) then return false end
  local power = state.power
  power.energy = math.max(0, power.energy - ENERGY_PER_UPDATE)
  state.total_energy_consumed = state.total_energy_consumed + ENERGY_PER_UPDATE
  return true
end

local function update(state, tick)
  local entity = state.entity
  if state.state ~= "idle" and state.state ~= "retracting" then
    local inventory = entity.get_inventory(defines.inventory.chest)
    if not target_valid(state) or not choose_cost(state.target, inventory) then
      release_target(state)
      state.state = "retracting"
    end
  end
  if state.state == "idle" then
    if tick >= state.next_scan then
      state.next_scan = tick + config.scan_ticks
      for id, retry in pairs(state.blocked) do if retry <= tick then state.blocked[id] = nil end end
      -- An unpowered crane must not reserve a ghost from a powered neighbor.
      if power_ready(state) then acquire_target(state, tick) end
    end
    if state.state == "idle" then return end
  end
  if state.state == "retracting" and state.extension <= 0 then
    state.state, state.next_scan = "idle", tick
    return
  end
  if not take_power(state) then
    if state.state ~= "retracting" then
      state.power_lost_since = state.power_lost_since or tick
      if tick - state.power_lost_since >= config.reservation_power_grace_ticks then
        release_target(state)
        state.state = "retracting"
      end
    end
    return
  end
  state.power_lost_since = nil
  if state.state == "rotating" then
    local difference = (state.target_orientation - state.orientation + 0.5) % 1 - 0.5
    local step = config.rotation_per_tick * config.update_ticks
    if math.abs(difference) <= step then
      state.orientation = state.target_orientation
      state.state = "extending"
    else
      state.orientation = (state.orientation + (difference > 0 and step or -step)) % 1
    end
  elseif state.state == "extending" then
    state.extension = math.min(state.target_extension, state.extension + config.extension_per_tick * config.update_ticks)
    if state.extension >= state.target_extension then state.state = "building" end
  elseif state.state == "building" then
    state.build_progress = state.build_progress + config.update_ticks
    if state.build_progress >= config.build_ticks then
      construct(state, tick)
      release_target(state)
      state.state = "retracting"
    end
  elseif state.state == "retracting" then
    state.extension = math.max(0, state.extension - config.extension_per_tick * config.update_ticks)
    if state.extension == 0 then state.state, state.next_scan = "idle", tick end
  end
  if entity.valid then update_art(state) end
end

script.on_init(rebuild)
script.on_configuration_changed(rebuild)

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.script_raised_built, defines.events.script_raised_revive}, function(event)
  register(event.entity)
end)

script.on_event(defines.events.on_entity_cloned, function(event)
  local entity = event.destination
  -- Area cloning can include hidden helpers; the cloned crane creates its own.
  if entity and entity.valid and entity.name == POWER then entity.destroy()
  else register(entity) end
end)

script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined,
  defines.events.on_entity_died, defines.events.script_raised_destroy}, function(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == NAME then
    local state = storage.cranes[entity.unit_number]
    if state then cleanup(state); storage.cranes[entity.unit_number] = nil end
  end
end)

script.on_event(defines.events.on_selected_entity_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then range_for(player) end
end)

script.on_event(defines.events.on_player_left_game, function(event)
  destroy_render(storage.ranges[event.player_index])
  storage.ranges[event.player_index] = nil
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local player = game.get_player(event.player_index)
  if player then range_for(player) end
end)

script.on_nth_tick(config.update_ticks, function(event)
  for id, state in pairs(storage.cranes) do
    if not valid_crane(state.entity) then
      -- The cached unit number remains usable after the entity itself is invalid.
      if state.target_id and storage.reservations[state.target_id] == id then storage.reservations[state.target_id] = nil end
      destroy_render(state.art)
      if state.power and state.power.valid then state.power.destroy() end
      storage.cranes[id] = nil
    else
      update(state, event.tick)
    end
  end
end)

-- Read-only snapshots help diagnose a user's save without exposing mutable state.
remote.add_interface(NAME, {
  constants = function() return table.deepcopy(config) end,
  diagnostics = function()
    local result = {}
    for id, state in pairs(storage.cranes) do
      result[id] = {
        unit_number = id, state = state.state, orientation = state.orientation,
        extension = state.extension, build_progress = state.build_progress,
        total_built = state.total_built, total_energy_consumed = state.total_energy_consumed,
        position = state.entity.valid and state.entity.position or nil,
        target_position = state.target and state.target.valid and state.target.position or nil
      }
    end
    return result
  end
})
