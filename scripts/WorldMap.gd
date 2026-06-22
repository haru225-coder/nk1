extends Node2D

@onready var ship: CharacterBody2D = $Ship
@onready var label: RichTextLabel = $CanvasLayer/HUD/LeftPanel/Margin/Label
@onready var fleet_status: Label = $CanvasLayer/HUD/RightPanel/Margin/FleetStatus
@onready var weather_status: Label = $CanvasLayer/HUD/RightPanel/Margin/WeatherStatus
@onready var _left_panel: PanelContainer = $CanvasLayer/HUD/LeftPanel
@onready var _right_panel: PanelContainer = $CanvasLayer/HUD/RightPanel
@onready var _minimap_panel: PanelContainer = $CanvasLayer/HUD/MinimapPanel
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $CanvasLayer/LightningFlash

var crate_scene = preload("res://scenes/Crate.tscn")
var seagull_tex = preload("res://assets/seagull.png")
var whale_tex = preload("res://assets/whale_shadow.png")

@onready var ports_node: Node2D = $Ports
var port_scene = preload("res://scenes/PortZone.tscn")
var ports_data: Array = []
var port_nodes: Dictionary = {}

const FLEET_NODE_SCENE := preload("res://scenes/MapFleetNode.tscn")
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

var _hud_update_timer: float = 0.0

func _ready() -> void:
	randomize()
	_load_ports()

	if port_nodes.has(GameState.current_voyage_origin):
		ship.position = port_nodes[GameState.current_voyage_origin].position + Vector2(0, 100)

	if not ship.is_in_group("player_ship"):
		ship.add_to_group("player_ship")

	_update_hud_labels()
	await get_tree().process_frame
	_animate_hud_entrance()

func _input(event: InputEvent) -> void:
	if navigation_locked:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_B or event.keycode == KEY_ESCAPE:
			var nearest_port := _get_nearest_port_id()
			if nearest_port != "":
				GameState.last_port = nearest_port
			GameState.set_navigation_flag("return_to_port")
			get_tree().change_scene_to_file("res://scenes/Main.tscn")

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

	if navigation_locked:
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

	label.text = "当前季风: %s\n风力强度: %d\nW/S: 升降帆 (当前档位: %d)\nA/D: 操舵\nJ/K: 左/右舷齐射开炮\n船体耐久: [color=%s]%d/%d[/color]\nB/Esc: 返回港口" % [
		wind_desc, int(ship.wind_strength), ship.sail_gear, hp_color, int(ship.hull_hp), int(ship.max_hp)
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
		fleet_status.modulate = Color(1, 0.3, 0.3)
		fleet_status.text += "\n【警告】水尽粮绝！"
	else:
		fleet_status.modulate = Color(1, 1, 1)

func _process_weather_and_time(delta: float) -> void:
	time_of_day += delta * 0.2

	while time_of_day >= 24.0:
		time_of_day -= 24.0
		var old_crew = GameState.crew_count
		GameState.process_daily_consumption()
		WorldEventTracker.process_day()
		TradeEventGenerator.try_generate()
		TradeEventGenerator.process_day()
		if GameState.crew_count < old_crew:
			var ft = ResourceManager.FloatingText.instantiate()
			ft.text = "【警告】水尽粮绝！水手减少！"
			ft.modulate = Color.RED
			ft.global_position = ship.global_position + Vector2(-100, -100)
			add_child(ft)
			get_tree().create_timer(2.0, false).timeout.connect(func():
				if is_instance_valid(ft):
					ft.queue_free()
			)

	var light_color := Color(1, 1, 1, 1)
	if time_of_day < 5.0 or time_of_day > 19.0:
		light_color = Color(0.2, 0.2, 0.4, 1.0)
	elif time_of_day >= 5.0 and time_of_day < 7.0:
		light_color = Color(0.8, 0.5, 0.4, 1.0)
	elif time_of_day > 17.0 and time_of_day <= 19.0:
		light_color = Color(0.8, 0.4, 0.2, 1.0)

	storm_timer -= delta
	if storm_timer <= 0:
		is_storm = not is_storm
		if is_storm:
			storm_timer = randf_range(20.0, 40.0)
			weather_status.text = "当前天气: 狂风骤雨 (极其危险!)"
			weather_status.modulate = Color(1, 0.3, 0.3)
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "当前天气: 晴朗"
			weather_status.modulate = Color(0.5, 0.8, 1)
			rain_particles.emitting = false
			ship.wind_strength = base_wind_strength
			ship.wind_vector = Vector2(0, 1)

	if is_storm:
		light_color = light_color.lerp(Color(0.3, 0.3, 0.4, 1.0), 0.8)
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

func _load_ports() -> void:
	ports_data = GameManager.ports_data.get("ports", [])
	for p in ports_data:
		_spawn_port(p)
	queue_redraw()

func _spawn_port(p_data: Dictionary) -> void:
	var p = port_scene.instantiate()
	p.port_id = p_data.get("id", "")
	p.port_name = p_data.get("name", "")

	var pos_data = p_data.get("position", {"x": 0, "y": 0})
	p.position = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))

	ports_node.add_child(p)
	port_nodes[p.port_id] = p

func _draw() -> void:
	for p in ports_data:
		var p_id = p.get("id", "")
		if not port_nodes.has(p_id):
			continue
		var p_node: Node2D = port_nodes[p_id]

		for conn_id in p.get("connections", []):
			if port_nodes.has(conn_id):
				var target_node: Node2D = port_nodes[conn_id]
				if p_id < conn_id:
					draw_line(p_node.position, target_node.position, Color(1, 1, 1, 0.3), 10.0)
					var dist := int(p_node.position.distance_to(target_node.position) / 10.0)
					var mid_pos := (p_node.position + target_node.position) / 2.0
					draw_string(ThemeDB.fallback_font, mid_pos, str(dist) + " 海里", HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.8, 0.8, 0.8, 0.8))

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