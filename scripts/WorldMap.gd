extends Node2D

@onready var ship: CharacterBody2D = $Ship
@onready var label: RichTextLabel = $CanvasLayer/HUD/LeftPanel/Margin/Label
@onready var fleet_status: Label = $CanvasLayer/HUD/RightPanel/Margin/FleetStatus
@onready var weather_status: Label = $CanvasLayer/HUD/RightPanel/Margin/WeatherStatus
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $CanvasLayer/LightningFlash

var crate_scene = preload("res://scenes/Crate.tscn")
var pirate_scene = preload("res://scenes/PirateShip.tscn")
var seagull_tex = preload("res://assets/seagull.png")
var whale_tex = preload("res://assets/whale_shadow.png")

@onready var ports_node: Node2D = $Ports
var port_scene = preload("res://scenes/PortZone.tscn")
var ports_data: Array = []
var port_nodes: Dictionary = {}

var time_of_day: float = 12.0
var is_storm: bool = false
var storm_timer: float = 0.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 80.0

var crate_spawn_timer: float = 5.0
var navigation_locked: bool = false
var distance_since_last_event: float = 0.0
var event_cooldown_distance: float = 3000.0
var last_ship_pos: Vector2 = Vector2.ZERO

var active_fleet_nodes: Dictionary = {}

func _ready() -> void:
	randomize()
	_load_ports()
	
	if port_nodes.has(GameState.current_voyage_origin):
		ship.position = port_nodes[GameState.current_voyage_origin].position + Vector2(0, 100)

func _process(delta: float) -> void:
	if not ship: return
	
	if navigation_locked:
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		return
	else:
		if ship.process_mode == Node.PROCESS_MODE_DISABLED:
			ship.process_mode = Node.PROCESS_MODE_INHERIT
	
	_process_weather_and_time(delta)
	_process_ai_fleets(delta)
	
	rain_particles.global_position = ship.global_position
	
	if last_ship_pos != Vector2.ZERO:
		var dist = ship.position.distance_to(last_ship_pos)
		distance_since_last_event += dist
	last_ship_pos = ship.position
	
	if distance_since_last_event > event_cooldown_distance:
		var prob = 0.005 + (distance_since_last_event - event_cooldown_distance) / 50000.0
		if randf() < prob:
			_try_trigger_event()
	
	# Update HUDs
	var wind_desc = "无风"
	if ship.wind_vector.y > 0: wind_desc = "北风 (自北向南吹)"
	elif ship.wind_vector.y < 0: wind_desc = "南风 (自南向北吹)"
	elif ship.wind_vector.x > 0: wind_desc = "西风 (自西向东吹)"
	elif ship.wind_vector.x < 0: wind_desc = "东风 (自东向西吹)"
	
	var hp_color = "green"
	if ship.hull_hp < 50: hp_color = "red"
	
	var text = "当前季风: %s\n风力强度: %d\nW/S: 升降帆 (当前档位: %d)\nA/D: 操舵\nJ/K: 左/右舷齐射开炮\n船体耐久: [color=%s]%d/100[/color]\nB/Esc: 返回港口" % [wind_desc, int(ship.wind_strength), ship.sail_gear, hp_color, int(ship.hull_hp)]
	label.text = text
	
	var cargo_str = ""
	if GameState.cargo.is_empty():
		cargo_str = "空"
	else:
		for k in GameState.cargo.keys():
			cargo_str += k + " x" + str(GameState.cargo[k]) + " "
	if cargo_str == "": cargo_str = "无"
	fleet_status.text = "【船队状态】\n铜钱: %d\n水手: %d/%d\n淡水: %d/%d\n食物: %d/%d\n货物: %s" % [LedgerSystem.get_balance(), GameState.crew_count, GameState.max_crew, int(GameState.water), int(GameState.max_water), int(GameState.food), int(GameState.max_food), cargo_str]
	
	if GameState.food <= 0 or GameState.water <= 0:
		# 豁免：动态效果，无法在.tres中预先定义
		fleet_status.modulate = Color(1, 0.3, 0.3)
		fleet_status.text += "\n【警告】水尽粮绝！"
	else:
		fleet_status.modulate = Color(1, 1, 1)

func _process_weather_and_time(delta: float) -> void:
	time_of_day += delta * 0.2
	if time_of_day >= 24.0: 
		time_of_day -= 24.0
		var old_crew = GameState.crew_count
		GameState.process_daily_consumption()
		WorldEventTracker.process_day()
		if GameState.crew_count < old_crew:
			var ft = preload("res://scenes/FloatingText.tscn").instantiate()
			ft.text = "【警告】水尽粮绝！水手减少！"
			# 豁免：动态效果，无法在.tres中预先定义
			ft.modulate = Color.RED
			ft.position = ship.position + Vector2(-100, -100)
			add_child(ft)
	
	var light_color = Color(1, 1, 1, 1)
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
			# 豁免：动态效果，无法在.tres中预先定义
			weather_status.modulate = Color(1, 0.3, 0.3)
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "当前天气: 晴朗"
			# 豁免：动态效果，无法在.tres中预先定义
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
	var tween = create_tween()
	tween.tween_property(lightning_flash, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): lightning_flash.visible = false)

func _process_ai_fleets(delta: float) -> void:
	var radius = 3000.0
	var nearby_fleets = FleetSystem.get_nearby_fleets(ship.position, radius)
	
	var current_visible_ids = []
	for f in nearby_fleets:
		var f_id = f["id"]
		current_visible_ids.append(f_id)
		
		if not active_fleet_nodes.has(f_id):
			var f_node = load("res://scripts/AIFleet.gd").new()
			f_node.fleet_id = f_id
			f_node.fleet_name = f["name"]
			f_node.player_encountered.connect(_on_fleet_encountered)
			add_child(f_node)
			active_fleet_nodes[f_id] = f_node
			
		active_fleet_nodes[f_id].update_logic_position(f["world_position"], delta)
		
	var to_remove = []
	for f_id in active_fleet_nodes.keys():
		if not f_id in current_visible_ids:
			active_fleet_nodes[f_id].queue_free()
			to_remove.append(f_id)
			
	for r in to_remove:
		active_fleet_nodes.erase(r)

func _on_fleet_encountered(fleet_id: String) -> void:
	if navigation_locked: return
	
	var encounter_data = EncounterSystem.resolve_encounter(fleet_id)
	if not encounter_data.is_empty():
		navigation_locked = true
		distance_since_last_event = 0.0
		
		var controller = SeaEventController.trigger_event($CanvasLayer, encounter_data)
		controller.event_finished.connect(func():
			navigation_locked = false
		)

func _process_spawns(delta: float) -> void:
	crate_spawn_timer -= delta
	if crate_spawn_timer <= 0:
		crate_spawn_timer = randf_range(10.0, 20.0)
		var crate = crate_scene.instantiate()
		var offset = Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		crate.position = ship.position + ship.velocity.normalized() * 500.0 + offset
		add_child(crate)
		
	animal_spawn_timer -= delta
	if animal_spawn_timer <= 0:
		animal_spawn_timer = randf_range(15.0, 30.0)
		_spawn_animal()

func _spawn_animal() -> void:
	var sprite = Sprite2D.new()
	var is_whale = randf() > 0.5
	if is_whale:
		sprite.texture = whale_tex
		sprite.scale = Vector2(0.5, 0.5)
		sprite.modulate.a = 0.5
		sprite.z_index = -1
	else:
		sprite.texture = seagull_tex
		sprite.scale = Vector2(0.2, 0.2)
		sprite.z_index = 10
		
	var offset = Vector2(randf_range(-1000, 1000), randf_range(-1000, 1000))
	sprite.position = ship.position + offset
	
	var move_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	sprite.rotation = move_dir.angle() + PI/2.0
	
	add_child(sprite)
	
	var tween = create_tween()
	var target_pos = sprite.position + move_dir * 3000.0
	tween.tween_property(sprite, "position", target_pos, 20.0)
	tween.tween_callback(func(): sprite.queue_free())

func _load_ports() -> void:
	var file = FileAccess.open("res://data/ports.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var res = json.parse(file.get_as_text())
		if res == OK:
			var data = json.get_data()
			ports_data = data.get("ports", [])
			for p in ports_data:
				_spawn_port(p)
			queue_redraw()
		file.close()

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
		if not port_nodes.has(p_id): continue
		var p_node = port_nodes[p_id]
		
		for conn_id in p.get("connections", []):
			if port_nodes.has(conn_id):
				var target_node = port_nodes[conn_id]
				if p_id < conn_id:
					draw_line(p_node.position, target_node.position, Color(1, 1, 1, 0.3), 10.0)
					var dist = int(p_node.position.distance_to(target_node.position) / 10.0)
					var mid_pos = (p_node.position + target_node.position) / 2.0
					draw_string(ThemeDB.fallback_font, mid_pos, str(dist) + " 海里", HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.8, 0.8, 0.8, 0.8))

func _try_trigger_event() -> void:
	var evt = EventSystem.get_random_event()
	if not evt.is_empty():
		distance_since_last_event = 0.0
		navigation_locked = true
		
		# 呼出控制器
		var controller = SeaEventController.trigger_event($CanvasLayer, evt)
		controller.event_finished.connect(func():
			navigation_locked = false
		)
