extends CharacterBody2D

# 核心航海物理 v4.0 (火炮海战版)

@export var wind_vector: Vector2 = Vector2(0, 1).normalized()
@export var wind_strength: float = 80.0

var sail_gear: int = 0
var max_gear: int = 2

var base_turn_speed: float = 1.8
var max_speed: float = 300.0

var hull_hp: float = 100.0
var max_hp: float = 100.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var wake_particles: CPUParticles2D = $WakeParticles
@onready var bow_wave_left: CPUParticles2D = $BowWaveLeft
@onready var bow_wave_right: CPUParticles2D = $BowWaveRight
@onready var splinter_particles: CPUParticles2D = $SplinterParticles
@onready var camera: Camera2D = $Camera2D

var target_zoom = Vector2(1.5, 1.5)
var cannonball_scene = preload("res://scenes/Cannonball.tscn")
var fire_cooldown: float = 0.0

func _ready() -> void:
	# 战术场景反映旗舰状态；舰队数据以 Fleet 为准
	var fs: Dictionary = Fleet.flagship()
	max_hp = float(fs.get("max_durability", 100.0))
	hull_hp = float(fs.get("durability", max_hp))
	var sail_lv: int = int(fs.get("sail_level", 1))
	max_speed = 300.0 + (sail_lv - 1) * 50.0
	base_turn_speed = 1.8 + (sail_lv - 1) * 0.2

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		sail_gear = min(sail_gear + 1, max_gear)
	elif event.is_action_pressed("ui_down"):
		sail_gear = max(sail_gear - 1, 0)
	
	if fire_cooldown <= 0:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_J:
				_fire_broadside(-1) # Left
			elif event.keycode == KEY_K:
				_fire_broadside(1) # Right

func _fire_broadside(side: int) -> void:
	fire_cooldown = 2.0
	var ship_dir = Vector2.UP.rotated(rotation)
	var side_dir = Vector2.RIGHT.rotated(rotation) if side == 1 else Vector2.LEFT.rotated(rotation)
	
	for i in range(3):
		var cb = cannonball_scene.instantiate()
		cb.position = position + ship_dir * (i * 20 - 20) + side_dir * 30
		var spread = randf_range(-0.1, 0.1)
		cb.direction = side_dir.rotated(spread)
		cb.shooter = self
		get_parent().add_child(cb)
		
	# Recoil shake
	camera.offset = -side_dir * 30.0

func _physics_process(delta: float) -> void:
	if hull_hp <= 0: return
	if fire_cooldown > 0: fire_cooldown -= delta
	
	_apply_sailing_physics(delta)
	move_and_slide()
	_update_visuals(delta)
	_process_storm_damage(delta)

func _apply_sailing_physics(delta: float) -> void:
	var ship_dir = Vector2.UP.rotated(rotation)
	var turn_input = Input.get_axis("ui_left", "ui_right")
	
	var turn_efficiency = 1.0
	if sail_gear == 2: turn_efficiency = 0.4
	elif sail_gear == 0: turn_efficiency = 0.0
		
	rotation += turn_input * base_turn_speed * turn_efficiency * delta

	var wind_dot = ship_dir.dot(wind_vector)
	var drive_force = 0.0
	
	if sail_gear > 0:
		if wind_dot > 0:
			drive_force = (60.0 * sail_gear) + (wind_strength * wind_dot * sail_gear)
		else:
			var penalty = abs(wind_dot) * 30.0
			drive_force = max(10.0, (40.0 * sail_gear) - penalty)
	
	var target_velocity = (ship_dir * drive_force)
	
	if sail_gear > 0:
		var drift = wind_vector * wind_strength * 0.4
		target_velocity += drift
		
	velocity = velocity.lerp(target_velocity, 2.0 * delta)

func _update_visuals(delta: float) -> void:
	var current_speed = velocity.length()
	
	var cross_wind = Vector2.RIGHT.rotated(rotation).dot(wind_vector)
	var roll_angle = cross_wind * wind_strength * 0.002 * sail_gear
	
	var turn_input = Input.get_axis("ui_left", "ui_right")
	roll_angle -= turn_input * (current_speed / max_speed) * 0.3
	
	sprite.rotation = lerp_angle(sprite.rotation, roll_angle, 5.0 * delta)
	
	var speed_ratio = current_speed / (max_speed * 1.5)
	
	if current_speed > 20.0:
		wake_particles.emitting = true
		wake_particles.initial_velocity_min = 20.0 + speed_ratio * 80.0
		wake_particles.initial_velocity_max = 40.0 + speed_ratio * 120.0
		wake_particles.scale_amount_max = 4.0 + speed_ratio * 6.0
		
		var bow_emit = current_speed > 100.0
		bow_wave_left.emitting = bow_emit
		bow_wave_right.emitting = bow_emit
		if bow_emit:
			bow_wave_left.scale_amount_max = 2.0 + speed_ratio * 4.0
			bow_wave_right.scale_amount_max = 2.0 + speed_ratio * 4.0
	else:
		wake_particles.emitting = false
		bow_wave_left.emitting = false
		bow_wave_right.emitting = false

	var zoom_val = 1.5 - (speed_ratio * 0.5)
	target_zoom = Vector2(zoom_val, zoom_val)
	camera.zoom = camera.zoom.lerp(target_zoom, 1.0 * delta)
	
	if current_speed > 250.0 or wind_strength > 150.0:
		var shake_intensity = (current_speed / 400.0) * 2.0
		camera.offset = Vector2(randf_range(-shake_intensity, shake_intensity), randf_range(-shake_intensity, shake_intensity))
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 5.0 * delta)

func take_damage(amount: float) -> void:
	splinter_particles.emitting = true
	var tween = create_tween()
	tween.tween_callback(func(): splinter_particles.emitting = false).set_delay(0.5)
	
	hull_hp -= amount
	Fleet.damage_fleet(amount)
	# 中弹会颠掉舱面货
	if not Fleet.cargo.is_empty():
		var keys = Fleet.cargo.keys()
		var key = keys[randi() % keys.size()]
		Fleet.remove_cargo(key, 1)

	if hull_hp <= 0:
		hull_hp = 0
		_sink_ship()

func _process_storm_damage(delta: float) -> void:
	if wind_strength > 150.0 and sail_gear == 2:
		splinter_particles.emitting = true
		hull_hp -= 5.0 * delta
		Fleet.damage_fleet(5.0 * delta)
		if hull_hp <= 0:
			hull_hp = 0
			_sink_ship()
	elif wind_strength <= 150.0 or sail_gear < 2:
		if not fire_cooldown > 0: # Hacky way to not disable splinter if hit by cannon
			pass

func _sink_ship() -> void:
	Fleet.clear_cargo()
	GameState.set_flag("return_to_port")
	# 海战（P4-1）：旗舰在 WorldMap 战斗中沉没 → 由 WorldMap 结算败局，不切场景
	if GameManager.pending_battle.get("battle", false):
		get_parent()._battle_player_sunk()
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
