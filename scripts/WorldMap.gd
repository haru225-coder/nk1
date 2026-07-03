extends Node2D

@onready var ship: CharacterBody2D = $Ship
@onready var label: RichTextLabel = $CanvasLayer/HUD/LeftPanel/Margin/Label
@onready var fleet_status: Label = $CanvasLayer/HUD/RightPanel/Margin/FleetStatus
@onready var weather_status: Label = $CanvasLayer/HUD/RightPanel/Margin/WeatherStatus
@onready var _left_panel: PanelContainer = $CanvasLayer/HUD/LeftPanel
@onready var _right_panel: PanelContainer = $CanvasLayer/HUD/RightPanel
@onready var _minimap_panel: MarginContainer = $CanvasLayer/HUD/MinimapPanel
@onready var _strategic_overlay: StrategicMapOverlay = $CanvasLayer/HUD/StrategicMapOverlay
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $CanvasLayer/LightningFlash

var crate_scene = preload(ResourcePaths.SCENE_CRATE)
var seagull_tex = preload(ResourcePaths.TEX_SEAGULL)
var whale_tex = preload(ResourcePaths.TEX_WHALE_SHADOW)

@onready var ports_node: Node2D = $Ports
@onready var _route_layer: RouteLayer = $RouteLayer
@onready var _strategic_map: Sprite2D = $StrategicMapRoot/StrategicMap
@onready var _ocean_overlay: Sprite2D = $StrategicMapRoot/OceanOverlay
@onready var _ocean_material: ShaderMaterial = $StrategicMapRoot/OceanOverlay.material as ShaderMaterial

const _OCEAN_TEX := preload(ResourcePaths.TEX_OCEAN_WATER)
var port_scene = preload(ResourcePaths.SCENE_PORT_ZONE)
var ports_data: Array = []
var port_nodes: Dictionary = {}

const FLEET_NODE_SCENE := preload(ResourcePaths.SCENE_MAP_FLEET)
var active_fleets: Array[Node2D] = []
const MAX_FLEETS_ON_MAP: int = 5
const FLEET_SPAWN_RADIUS: float = 1200.0
const FLEET_DESPAWN_RADIUS: float = 3000.0

var time_of_day: float = 12.0
var is_storm: bool = false
var storm_timer: float = 0.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 80.0

var crate_spawn_timer: float = 5.0
var animal_spawn_timer: float = 15.0
var navigation_locked: bool = false
var _overlay_open: bool = false

var _hud_update_timer: float = 0.0
var _voyage_log_timer: float = 25.0  ## NK1-P6: 航海日志周期
var _economy_log_timer: float = 15.0  ## NK1-P6: 经济动态检查周期
var _near_port_id: String = ""       ## NK1-P6: 当前最近港口（用于进港提示）

## NK1-P6: 航海风景描述池（NK1-P6-POLISH-004: 已迁移到 FloatingTextConfig.VOYAGE_SCENERY）

func _ready() -> void:
	randomize()
	_setup_strategic_map()
	_load_ports()

	if GameState.has_world_map_ship_pose():
		_restore_ship_pose()
	elif port_nodes.has(GameState.current_voyage_origin):
		_place_ship_at_port(GameState.current_voyage_origin)

	if not ship.is_in_group("player_ship"):
		ship.add_to_group("player_ship")

	_strategic_overlay.closed.connect(_on_strategic_overlay_closed)
	_strategic_overlay.destination_set.connect(_on_voyage_destination_set)
	_update_hud_labels()
	await get_tree().process_frame
	_animate_hud_entrance()

func _input(event: InputEvent) -> void:
	if _strategic_overlay.is_open():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_M or event.keycode == KEY_ESCAPE:
				_strategic_overlay.close()
				get_viewport().set_input_as_handled()
		return

	if navigation_locked:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M:
			_open_strategic_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B or event.keycode == KEY_ESCAPE:
			var nearest_port := _get_nearest_port_id()
			if nearest_port != "":
				GameState.last_port = nearest_port
			_save_ship_pose()
			GameState.set_navigation_flag("return_to_port")
			get_tree().change_scene_to_file(ResourcePaths.SCENE_MAIN)

func _get_nearest_port_id() -> String:
	if not ship or port_nodes.is_empty():
		return GameState.last_port
	var best_id := ""
	var best_dist := INF
	for port_id in port_nodes:
		var node: Node2D = port_nodes[port_id]
		var dist := ship.position.distance_to(node.position)
		if dist < best_dist:
			best_dist = dist
			best_id = port_id
	return best_id

func _process(delta: float) -> void:
	if not ship:
		return

	if navigation_locked or _overlay_open:
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		return
	else:
		if ship.process_mode == Node.PROCESS_MODE_DISABLED:
			ship.process_mode = Node.PROCESS_MODE_INHERIT

	_process_weather_and_time(delta)
	rain_particles.global_position = ship.global_position

	_process_spawns(delta)
	_maintain_fleet_spawns()

	_hud_update_timer -= delta
	if _hud_update_timer <= 0.0:
		_update_hud_labels()
		_hud_update_timer = 0.2

	# NK1-P6: 航海风景日志 — 长航时定期弹出风景描述
	_voyage_log_timer -= delta
	if _voyage_log_timer <= 0.0:
		_voyage_log_timer = randf_range(25.0, 45.0)
		_show_voyage_scenery()

	# NK1-P6: 经济动态检查 — 航行中发现经济变化
	_economy_log_timer -= delta
	if _economy_log_timer <= 0.0:
		_economy_log_timer = 20.0
		_check_economy_updates()

	# NK1-P6: 港口接近提示
	_check_port_proximity()

func _update_hud_labels() -> void:
	if not ship:
		return

	var wind_desc := "无风"
	if ship.wind_vector.y > 0:
		wind_desc = "北风 (自北向南吹)"
	elif ship.wind_vector.y < 0:
		wind_desc = "南风 (自南向北吹)"
	elif ship.wind_vector.x > 0:
		wind_desc = "西风 (自西向东吹)"
	elif ship.wind_vector.x < 0:
		wind_desc = "东风 (自东向西吹)"

	var hp_color := "green"
	if ship.hull_hp < 50:
		hp_color = "red"

	# NK1-P6: 显示航速和风向角度
	var current_speed := int(ship.velocity.length())
	var wind_angle := rad_to_deg(ship.wind_vector.angle_to(Vector2.UP.rotated(ship.rotation)))
	var wind_dir_label := "顺风" if abs(wind_angle) < 45 else ("逆风" if abs(wind_angle) > 135 else "侧风")

	var flagship := GameState.fleet.get_flagship()
	var ship_name := flagship.name if flagship else "旗舰"
	var sail_label := "纵帆" if GameState.sail_type == "lateen" else "横帆"
	var dest_line := ""
	if GameState.voyage_destination_id != "":
		dest_line = "\n航行目标: %s" % _port_display_name(GameState.voyage_destination_id)
	label.text = "旗舰: %s (%s)\n当前季风: %s\n风力强度: %d (%s)\n航速: %d\nW/S: 升降帆 (当前档位: %d)\nA/D: 操舵\nM: 战略地图\n船体耐久: [color=%s]%d/%d[/color]%s\nB/Esc: 返回港口" % [
		ship_name, sail_label, wind_desc, int(ship.wind_strength), wind_dir_label, current_speed, ship.sail_gear, hp_color, int(ship.hull_hp), int(ship.max_hp), dest_line
	]

	var cargo_str := CargoSystem.to_display_string(" ")
	if cargo_str == "":
		cargo_str = "无"
	var starving := GameState.food <= 0 or GameState.water <= 0

	fleet_status.text = "【船队状态】\n铜钱: %d\n水手: %d/%d\n淡水: %d/%d\n食物: %d/%d\n货物: %s" % [
		LedgerSystem.get_balance(),
		GameState.crew_count, GameState.max_crew,
		int(GameState.water), int(GameState.max_water),
		int(GameState.food), int(GameState.max_food),
		cargo_str,
	]

	if starving:
		fleet_status.modulate = GameColors.WARNING
		fleet_status.text += "\n【警告】水尽粮绝！"
	else:
		fleet_status.modulate = Color(1, 1, 1)

func _process_weather_and_time(delta: float) -> void:
	time_of_day += delta * 0.2

	while time_of_day >= 24.0:
		time_of_day -= 24.0
		var old_crew = GameState.crew_count
		var advance_result: Dictionary = GameState.advance_world_day()
		GameState.process_daily_consumption()
		WorldEventTracker.process_day()
		TradeEventGenerator.try_generate()
		TradeEventGenerator.process_day()
		# NK1-P5-ECON-002: 每日经济处理（繁荣度回归+贸易历史衰减）
		GameState.market.process_daily_economy()
		var tick_ctx := {
			"world_day": GameState.navigation.world_day,
			"world_month": GameState.navigation.world_month,
		}
		StoryEventChainEngine.check_triggers("day_advance", tick_ctx)
		if advance_result.get("month_advance", false):
			StoryEventChainEngine.check_triggers("month_advance", tick_ctx)
		if GameState.crew_count < old_crew:
			var ft = ResourceManager.FloatingText.instantiate()
			ft.text = "【警告】水尽粮绝！水手减少！"
			ft.modulate = GameColors.FLOATING_CREW_LOSS
			ft.global_position = ship.global_position + FloatingTextConfig.OFFSET_CREW_LOSS
			add_child(ft)
			get_tree().create_timer(FloatingTextConfig.LIFETIME_CREW_LOSS, false).timeout.connect(func():
				if is_instance_valid(ft):
					ft.queue_free()
			)
			# NK1-P6-POLISH: 分类日志
			GameState.game_log.warning(GameLog.Category.VOYAGE, "水尽粮绝，水手减少 %d 人" % (old_crew - GameState.crew_count))

	var light_color := GameColors.LIGHT_NOON
	if time_of_day < 5.0 or time_of_day > 19.0:
		light_color = GameColors.LIGHT_NIGHT
	elif time_of_day >= 5.0 and time_of_day < 7.0:
		light_color = GameColors.LIGHT_DAWN
	elif time_of_day > 17.0 and time_of_day <= 19.0:
		light_color = GameColors.LIGHT_DUSK

	storm_timer -= delta
	if storm_timer <= 0:
		is_storm = not is_storm
		if is_storm:
			storm_timer = randf_range(20.0, 40.0)
			weather_status.text = "当前天气: 狂风骤雨 (极其危险!)"
			weather_status.modulate = GameColors.WARNING
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
			GameState.game_log.warning(GameLog.Category.VOYAGE, "风暴来袭！风力 %.0f" % ship.wind_strength)
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "当前天气: 晴朗"
			weather_status.modulate = GameColors.INFO
			rain_particles.emitting = false
			ship.wind_strength = base_wind_strength
			ship.wind_vector = Vector2(0, 1)

	if is_storm:
		light_color = light_color.lerp(GameColors.LIGHT_STORM, 0.8)
		lightning_timer -= delta
		if lightning_timer <= 0:
			_strike_lightning()
			lightning_timer = randf_range(2.0, 8.0)

	canvas_modulate.color = canvas_modulate.color.lerp(light_color, 2.0 * delta)

func _strike_lightning() -> void:
	lightning_flash.visible = true
	lightning_flash.color.a = 0.8
	var tween := create_tween()
	tween.tween_property(lightning_flash, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): lightning_flash.visible = false)

func _maintain_fleet_spawns() -> void:
	for i in range(active_fleets.size() - 1, -1, -1):
		var f: Node2D = active_fleets[i]
		if is_instance_valid(f):
			if f.global_position.distance_to(ship.global_position) > FLEET_DESPAWN_RADIUS:
				f.queue_free()
				active_fleets.remove_at(i)
		else:
			active_fleets.remove_at(i)

	while active_fleets.size() < MAX_FLEETS_ON_MAP:
		_spawn_fleet()

func _spawn_fleet() -> void:
	var fleet_node: Node2D = FLEET_NODE_SCENE.instantiate()
	var angle := randf() * TAU
	var spawn_pos := ship.global_position + Vector2(cos(angle), sin(angle)) * FLEET_SPAWN_RADIUS
	fleet_node.global_position = spawn_pos

	var encounter_data := FleetArchetypes.get_random_encounter()
	fleet_node.setup(encounter_data)
	fleet_node.encounter_triggered.connect(_on_fleet_encountered)

	add_child(fleet_node)
	active_fleets.append(fleet_node)

func _resolve_patrol_encounter(encounter_data: Dictionary) -> Dictionary:
	var context := {
		"aggressor_id": encounter_data.get("id", "patrol_song"),
		"faction_id": "song_maritime_office",
		"behaviors": ["inspect"],
		"violation": EncounterSystem.calculate_cargo_violation(),
	}
	var resolved := EncounterResolver.get_encounter_data(context)
	if not resolved.is_empty():
		return resolved
	return FleetArchetypes.to_event_data(encounter_data)

func _on_fleet_encountered(encounter_data: Dictionary, fleet_node: Node2D) -> void:
	if navigation_locked:
		return

	navigation_locked = true
	GameState.set_navigation_locked(true)

	var event_data: Dictionary
	if encounter_data.get("id", "") == "patrol_song":
		event_data = _resolve_patrol_encounter(encounter_data)
	else:
		event_data = FleetArchetypes.to_event_data(encounter_data)
	var controller := SeaEventController.trigger_event($CanvasLayer, event_data)

	controller.event_finished.connect(func():
		if is_instance_valid(fleet_node):
			active_fleets.erase(fleet_node)
			fleet_node.queue_free()
		navigation_locked = false
		GameState.set_navigation_locked(false)
	)

func _process_spawns(delta: float) -> void:
	crate_spawn_timer -= delta
	if crate_spawn_timer <= 0:
		crate_spawn_timer = randf_range(10.0, 20.0)
		var crate = crate_scene.instantiate()
		var offset := Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		var forward_dir := Vector2.UP.rotated(ship.rotation)
		crate.global_position = ship.global_position + forward_dir * 500.0 + offset
		add_child(crate)

	animal_spawn_timer -= delta
	if animal_spawn_timer <= 0:
		animal_spawn_timer = randf_range(15.0, 30.0)
		_spawn_animal()

func _spawn_animal() -> void:
	var sprite := Sprite2D.new()
	var is_whale := randf() > 0.5
	if is_whale:
		sprite.texture = whale_tex
		sprite.scale = Vector2(0.5, 0.5)
		sprite.modulate.a = 0.5
		sprite.z_index = -1
	else:
		sprite.texture = seagull_tex
		sprite.scale = Vector2(0.2, 0.2)
		sprite.z_index = 10

	var offset := Vector2(randf_range(-1000, 1000), randf_range(-1000, 1000))
	sprite.global_position = ship.global_position + offset

	var move_dir := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	sprite.rotation = move_dir.angle() + PI / 2.0

	add_child(sprite)

	var tween := create_tween()
	var target_pos := sprite.position + move_dir * 3000.0
	tween.tween_property(sprite, "position", target_pos, 20.0)
	tween.tween_callback(func(): sprite.queue_free())

func _place_ship_at_port(port_id: String) -> void:
	if not ship or not port_nodes.has(port_id):
		return
	var flagship := GameState.fleet.get_flagship()
	var hull_id := flagship.hull_id if flagship else ShipSystem.DEFAULT_HULL_ID
	ship.position = port_nodes[port_id].position + ShipModelLibrary.get_port_spawn_offset(hull_id)
	ship.rotation = 0.0
	if ship.has_method("_sync_from_flagship"):
		ship._sync_from_flagship()


func _save_ship_pose() -> void:
	if not ship:
		return
	GameState.save_world_map_ship_pose(ship.position, ship.rotation)


func _restore_ship_pose() -> void:
	if not ship:
		return
	ship.position = GameState.navigation.world_map_position
	ship.rotation = GameState.navigation.world_map_rotation
	if ship.has_method("_sync_from_flagship"):
		ship._sync_from_flagship()


func _setup_strategic_map() -> void:
	if not MapLayout.apply_strategic_map_sprite(_strategic_map):
		push_warning("WorldMap: strategic map texture missing (%s)" % MapLayout.get_map_texture_path())
		_strategic_map.visible = false
		_ocean_overlay.visible = false
		return
	_strategic_map.visible = true
	if MapLayout.apply_ocean_overlay(_ocean_overlay, _OCEAN_TEX, _ocean_material):
		_ocean_overlay.visible = true
	else:
		push_warning("WorldMap: sea mask missing (%s)" % MapLayout.get_sea_mask_path())
		_ocean_overlay.visible = false


func _load_ports() -> void:
	ports_data = GameManager.ports_data.get("ports", [])
	for p in ports_data:
		_spawn_port(p)
	_route_layer.set_port_nodes(port_nodes)

func _spawn_port(p_data: Dictionary) -> void:
	var p = port_scene.instantiate()
	if p.has_method("setup"):
		p.setup(p_data)
	else:
		p.port_id = p_data.get("id", "")
		p.port_name = p_data.get("name", "")
	p.position = MapLayout.port_world_position(p_data)
	ports_node.add_child(p)
	port_nodes[p.port_id] = p

func _animate_hud_entrance() -> void:
	var panels := [_left_panel, _right_panel, _minimap_panel]
	for panel in panels:
		panel.scale = Vector2(0.88, 0.88)
		panel.modulate.a = 0.0
		panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for panel in panels:
		tw.tween_property(panel, "scale", Vector2.ONE, 0.6)
		tw.tween_property(panel, "modulate:a", 1.0, 0.5)

## ── NK1-P6: 航海反馈增强 ────────────────────────────────

## 航海风景日志：长航时弹出风景描述浮文
func _show_voyage_scenery() -> void:
	if navigation_locked or _overlay_open:
		return
	var idx: int = randi() % FloatingTextConfig.VOYAGE_SCENERY.size()
	var scenery: String = FloatingTextConfig.VOYAGE_SCENERY[idx]
	var ft = ResourceManager.FloatingText.instantiate()
	ft.text = scenery
	ft.modulate = GameColors.SCENERY
	ft.global_position = ship.global_position + FloatingTextConfig.OFFSET_SCENERY
	add_child(ft)
	get_tree().create_timer(FloatingTextConfig.LIFETIME_SCENERY, false).timeout.connect(func():
		if is_instance_valid(ft):
			ft.queue_free()
	)

## 经济动态检查：航行中检测经济事件变化并提示
func _check_economy_updates() -> void:
	if GameState.economy_log == null:
		return
	var latest: String = GameState.economy_log.get_latest()
	if latest.is_empty():
		return
	var ft = ResourceManager.FloatingText.instantiate()
	ft.text = latest
	ft.modulate = GameColors.FLOATING_ECONOMY
	ft.global_position = ship.global_position + FloatingTextConfig.OFFSET_ECONOMY
	add_child(ft)
	get_tree().create_timer(FloatingTextConfig.LIFETIME_ECONOMY, false).timeout.connect(func():
		if is_instance_valid(ft):
			ft.queue_free()
	)

## 港口接近提示：靠近港口时显示港口名
func _check_port_proximity() -> void:
	var nearest_id := _get_nearest_port_id()
	if nearest_id.is_empty() or not port_nodes.has(nearest_id):
		_near_port_id = ""
		return
	var dist: float = ship.position.distance_to(port_nodes[nearest_id].position)
	if dist < 300.0 and _near_port_id != nearest_id:
		_near_port_id = nearest_id
		var port_name: String = port_nodes[nearest_id].port_name
		var ft = ResourceManager.FloatingText.instantiate()
		ft.text = "【抵达】%s — 按 B/Esc 入港" % port_name
		ft.modulate = GameColors.FLOATING_PORT_NEAR
		ft.global_position = ship.global_position + FloatingTextConfig.OFFSET_PORT_NEAR
		add_child(ft)
		get_tree().create_timer(FloatingTextConfig.LIFETIME_PORT_NEAR, false).timeout.connect(func():
			if is_instance_valid(ft):
				ft.queue_free()
	)
	elif dist > 500.0:
		_near_port_id = ""


func _open_strategic_overlay() -> void:
	if not ship:
		return
	_overlay_open = true
	ports_node.process_mode = Node.PROCESS_MODE_DISABLED
	_strategic_overlay.open(
		ship,
		time_of_day,
		weather_status.text,
		int(ship.hull_hp),
		int(ship.max_hp)
	)


func _on_strategic_overlay_closed() -> void:
	_overlay_open = false
	ports_node.process_mode = Node.PROCESS_MODE_INHERIT


func _on_voyage_destination_set(_port_id: String) -> void:
	_update_hud_labels()
	if not ship or not _strategic_overlay.is_open():
		return
	_strategic_overlay.refresh_destination(
		time_of_day,
		weather_status.text,
		int(ship.hull_hp),
		int(ship.max_hp)
	)


func _port_display_name(port_id: String) -> String:
	for port_data in ports_data:
		if port_data.get("id", "") == port_id:
			return port_data.get("name", port_id)
	return port_id
