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

var time_of_day: float = 12.0
var is_storm: bool = false
var storm_timer: float = 0.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 80.0

var crate_spawn_timer: float = 5.0
var animal_spawn_timer: float = 10.0
var pirate_spawn_timer: float = 20.0

func _ready() -> void:
	randomize()

func _process(delta: float) -> void:
	if not ship: return
	
	_process_weather_and_time(delta)
	_process_spawns(delta)
	
	rain_particles.global_position = ship.global_position
	
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
	
	fleet_status.text = "【舰队资产】\n金钱: %d\n货舱: %s" % [GameState.money, cargo_str]

func _process_weather_and_time(delta: float) -> void:
	time_of_day += delta * 0.2
	if time_of_day >= 24.0: time_of_day -= 24.0
	
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
			weather_status.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "当前天气: 晴朗"
			weather_status.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
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
		
	pirate_spawn_timer -= delta
	if pirate_spawn_timer <= 0:
		pirate_spawn_timer = randf_range(30.0, 60.0)
		var pirate = pirate_scene.instantiate()
		var angle = randf() * TAU
		var dist = randf_range(1500, 2500)
		pirate.position = ship.position + Vector2(cos(angle), sin(angle)) * dist
		pirate.target = ship
		add_child(pirate)

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
