local NAME = "heavy-tower-crane"
local function blueprint()
  local surface = game.surfaces[1]
  for _, pos in ipairs({{14.5,-6.5},{14.5,1.5},{-14.5,1.5},{-14.5,-6.5},{-8.5,-13.5},{8.5,-13.5}}) do
    if surface.can_place_entity{name="assembling-machine-1",position=pos,force="player"} then
      surface.create_entity{name="entity-ghost",inner_name="assembling-machine-1",position=pos,force="player"}
    end
  end
end
local function panel(player)
  if player.gui.top.tower_test_site then return end
  local frame = player.gui.top.add{type="flow",name="tower_test_site",direction="horizontal"}
  frame.add{type="button",name="tower_test_blueprint",caption={"tower-test-site.blueprint"}}
  frame.add{type="button",name="tower_test_pause",caption={"tower-test-site.pause"}}
end
local function player_setup(player)
  player.teleport({-10,11})
  player.cheat_mode=true
  player.insert{name=NAME,count=2}
  player.insert{name="assembling-machine-1",count=50}
  player.insert{name="stone-furnace",count=50}
  player.insert{name="substation",count=20}
  player.zoom=1.25
  panel(player)
  player.print({"tower-test-site.help"})
end
script.on_init(function()
  local surface=game.surfaces[1]
  surface.request_to_generate_chunks({0,0},4);surface.force_generate_chunk_requests()
  for _, entity in pairs(surface.find_entities_filtered{area={{-65,-55},{65,45}},type={"tree","simple-entity","cliff","unit-spawner","unit","resource"}}) do entity.destroy() end
  local tiles={}
  for x=-65,65 do for y=-55,45 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
  surface.set_tiles(tiles)
  surface.daytime=0;surface.freeze_daytime=true
  game.forces.enemy.ai_controllable=false
  game.forces.player.technologies[NAME].researched=true
  local crane=surface.create_entity{name=NAME,position={0,0},force="player",raise_built=true}
  assert(crane,"test-site crane")
  crane.insert{name="assembling-machine-1",count=50}
  crane.insert{name="stone-furnace",count=50}
  crane.insert{name="transport-belt",count=100}
  storage.crane=crane
  surface.create_entity{name="substation",position={8,-2},force="player"}
  local generator=surface.create_entity{name="electric-energy-interface",position={11,1},force="player"}
  generator.electric_buffer_size=1000000000;generator.power_production=1000000000;generator.energy=1000000000
  for x=-34,46,2 do surface.create_entity{name="straight-rail",position={x,8},direction=defines.direction.east,force="player"} end
  for _,row in ipairs({{"locomotive",-10.5,.25},{"cargo-wagon",-3.5,.25},{"cargo-wagon",3.5,.25},{"locomotive",10.5,.75}}) do
    local stock=surface.create_entity{name=row[1],position={row[2],8},orientation=row[3],force="player"}
    if stock then
      if stock.type=="locomotive" then stock.color={r=.5,g=.07,b=.04};stock.insert{name="coal",count=10}
      else stock.insert{name="assembling-machine-1",count=100} end
      stock.train.manual_mode=true;stock.train.speed=0
    end
  end
  for x=-6.5,6.5 do
    local chest=surface.create_entity{name="steel-chest",position={x,10.5},force="player"}
    if chest then chest.insert{name="assembling-machine-1",count=5} end
  end
  storage.start=game.tick
  for _,player in pairs(game.players) do player_setup(player) end
end)
script.on_event(defines.events.on_player_created,function(event) player_setup(game.get_player(event.player_index)) end)
script.on_event(defines.events.on_gui_click,function(event)
  if not event.element.valid then return end
  if event.element.name=="tower_test_blueprint" then blueprint()
  elseif event.element.name=="tower_test_pause" and storage.crane and storage.crane.valid then
    local state=remote.call(NAME,"diagnostics")[storage.crane.unit_number]
    remote.call(NAME,"set_enabled",storage.crane.unit_number,state.paused)
  end
end)
script.on_event(defines.events.on_tick,function()
  if game.tick-storage.start==60 then blueprint() end
end)
