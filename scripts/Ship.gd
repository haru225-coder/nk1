extends CharacterBody2D

# 核心航海物理 v4.0 (火炮海战版 + 物理引擎版)

## ── 物理常量 ─────────────────────────────────────────────
const BASE_MAX_SPEED := 300.0
const SPEED_PER_SAIL := 50.0
const BASE_TURN_SPEED_DEFAULT := 1.8
const TURN_PER_SAIL := 0.2
const TURN_EFFICIENCY_FULL_SAIL := 0.4
const TURN_EFFICIENCY_NO_CREW := 0.2
const VELOCITY_LERP_SPEED := 2.0

## ── 火炮常量 ─────────────────────────────────────────────
const FIRE_COOLDOWN_TIME := 2.0
const CANNONBALL_COUNT := 3
const CANNONBALL_SPACING := 20
const SIDE_OFFSET := 30.0
const CANNON_SPREAD := 0.1
const RECOIL_OFFSET := 30.0

## ── 视觉常量 ─────────────────────────────────────────────
const ROLL_FACTOR := 0.002
const TURN_ROLL_FACTOR := 0.3
const SPRITE_LERP_SPEED := 5.0
const WAKE_SPEED_THRESHOLD := 20.0
const WAKE_VEL_MIN_BASE := 20.0
const WAKE_VEL_MIN_FACTOR := 80.0
const WAKE_VEL_MAX_BASE := 40.0
const WAKE_VEL_MAX_FACTOR := 120.0
const WAKE_SCALE_BASE := 4.0
const WAKE_SCALE_FACTOR := 6.0
const BOW_WAVE_THRESHOLD := 100.0
const BOW_SCALE_BASE := 2.0
const BOW_SCALE_FACTOR := 4.0
const ZOOM_BASE := 1.5
const ZOOM_REDUCTION := 0.5
const ZOOM_LERP_SPEED := 1.0
const SHAKE_SPEED_THRESHOLD := 250.0
const SHAKE_WIND_THRESHOLD := 150.0
const SHAKE_SPEED_DIVISOR := 400.0
const SHAKE_MAX_INTENSITY := 2.0
const CAMERA_LERP_SPEED := 5.0

## ── 风暴/损伤常量 ─────────────────────────────────────────
const STORM_WIND_THRESHOLD := 150.0
const STORM_DAMAGE_PER_SEC := 5.0
const SPLINTER_DURATION := 0.5

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

var cannonball_scene = preload("res://scenes/Cannonball.tscn")
var crate_scene = preload("res://scenes/Crate.tscn")
var fire_cooldown: float = 0.0
var _last_reported_hp: int = -1
var _recoil_offset: Vector2 = Vector2.ZERO

signal hud_stats_changed

func _ready() -> void:
	if not is_in_group("player_ship"):
		add_to_group("player_ship")
	max_hp = GameState.ship_max_hp
	hull_hp = GameState.ship_hp
	_last_reported_hp = int(hull_hp)
	max_speed = BASE_MAX_SPEED + (GameState.sail_level - 1) * SPEED_PER_SAIL
	base_turn_speed = BASE_TURN_SPEED_DEFAULT + (GameState.sail_level - 1) * TURN_PER_SAIL

func _notify_hud_stats() -> void:
	hud_stats_changed.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		sail_gear = min(sail_gear + 1, max_gear)
		_notify_hud_stats()
	elif event.is_action_pressed("ui_down"):
		sail_gear = max(sail_gear - 1, 0)
		_notify_hud_stats()
	
	if fire_cooldown <= 0:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_J:
				_fire_broadside(-1) # Left
			elif event.keycode == KEY_K:
				_fire_broadside(1) # Right

func _fire_broadside(side: int) -> void:
	fire_cooldown = FIRE_COOLDOWN_TIME
	var ship_dir = Vector2.UP.rotated(rotation)
	var side_dir = Vector2.RIGHT.rotated(rotation) if side == 1 else Vector2.LEFT.rotated(rotation)
	
	for i in range(CANNONBALL_COUNT):
		var cb = cannonball_scene.instantiate()
		cb.global_position = global_position + ship_dir * (i * CANNONBALL_SPACING - CANNONBALL_SPACING) + side_dir * SIDE_OFFSET
		var spread = randf_range(-CANNON_SPREAD, CANNON_SPREAD)
		cb.direction = side_dir.rotated(spread)
		cb.shooter = self
		var parent := get_parent()
		if is_instance_valid(parent):
			parent.add_child(cb)

	_recoil_offset = -side_dir * RECOIL_OFFSET

func _physics_process(delta: float) -> void:
	if hull_hp <= 0: return
	if fire_cooldown > 0: fire_cooldown -= delta
	
	_apply_sailing_physics(delta)
	move_and_slide()
	_update_visuals(delta)
	_process_storm_damage(delta)

func _apply_sailing_physics(delta: float) -> void:
	var turn_input = Input.get_axis("ui_left", "ui_right")
	
	var turn_efficiency = 1.0
	if sail_gear == 2: turn_efficiency = TURN_EFFICIENCY_FULL_SAIL
	elif sail_gear == 0: turn_efficiency = 0.0
	
	if GameState.crew_count <= 0:
		turn_efficiency *= TURN_EFFICIENCY_NO_CREW
		if sail_gear != 0:
			sail_gear = 0
			_notify_hud_stats()
			
	rotation += turn_input * base_turn_speed * turn_efficiency * delta

	# 刷新 ship_dir
	var ship_dir = Vector2.UP.rotated(rotation)

	var phys = SailPhysicsEngine.calculate(velocity, ship_dir, wind_vector, wind_strength, sail_gear, max_speed, GameState.sail_type, delta)
	velocity = phys.new_velocity
	
	# 阻断器惩罚：完全逆风却满帆强行航行，造成极度劳累扣减水手
	if phys.is_dead_wind and sail_gear > 0:
		if randf() < 0.2 * delta:
			GameState.apply_effects({"crew_count": -1})
			_notify_hud_stats()

func _update_visuals(delta: float) -> void:
	var current_speed = velocity.length()
	
	var cross_wind = Vector2.RIGHT.rotated(rotation).dot(wind_vector)
	var roll_angle = cross_wind * wind_strength * ROLL_FACTOR * sail_gear
	
	var turn_input = Input.get_axis("ui_left", "ui_right")
	roll_angle -= turn_input * (current_speed / max_speed) * TURN_ROLL_FACTOR
	
	sprite.rotation = lerp_angle(sprite.rotation, roll_angle, SPRITE_LERP_SPEED * delta)
	
	var speed_ratio = current_speed / (max_speed * ZOOM_BASE)
	
	if current_speed > WAKE_SPEED_THRESHOLD:
		wake_particles.emitting = true
		wake_particles.initial_velocity_min = WAKE_VEL_MIN_BASE + speed_ratio * WAKE_VEL_MIN_FACTOR
		wake_particles.initial_velocity_max = WAKE_VEL_MAX_BASE + speed_ratio * WAKE_VEL_MAX_FACTOR
		wake_particles.scale_amount_max = WAKE_SCALE_BASE + speed_ratio * WAKE_SCALE_FACTOR
		
		var bow_emit = current_speed > BOW_WAVE_THRESHOLD
		bow_wave_left.emitting = bow_emit
		bow_wave_right.emitting = bow_emit
		if bow_emit:
			bow_wave_left.scale_amount_max = BOW_SCALE_BASE + speed_ratio * BOW_SCALE_FACTOR
			bow_wave_right.scale_amount_max = BOW_SCALE_BASE + speed_ratio * BOW_SCALE_FACTOR
	else:
		wake_particles.emitting = false
		bow_wave_left.emitting = false
		bow_wave_right.emitting = false

	var zoom_val = ZOOM_BASE - (speed_ratio * ZOOM_REDUCTION)
	zoom_val = clampf(zoom_val, 0.5, ZOOM_BASE)
	var target_zoom = Vector2(zoom_val, zoom_val)
	camera.zoom = camera.zoom.lerp(target_zoom, ZOOM_LERP_SPEED * delta)

	_recoil_offset = _recoil_offset.lerp(Vector2.ZERO, CAMERA_LERP_SPEED * delta)

	if current_speed > SHAKE_SPEED_THRESHOLD or wind_strength > SHAKE_WIND_THRESHOLD:
		var shake_intensity = (current_speed / SHAKE_SPEED_DIVISOR) * SHAKE_MAX_INTENSITY
		var shake = Vector2(randf_range(-shake_intensity, shake_intensity), randf_range(-shake_intensity, shake_intensity))
		camera.offset = _recoil_offset + shake
	else:
		camera.offset = _recoil_offset

func take_damage(amount: float) -> void:
	splinter_particles.emitting = true
	get_tree().create_timer(SPLINTER_DURATION, false).timeout.connect(func():
		if is_instance_valid(splinter_particles):
			splinter_particles.emitting = false
	)

	hull_hp -= amount
	GameState.modify_hp(-amount)
	_last_reported_hp = int(hull_hp)
	_notify_hud_stats()
	var dropped = CargoSystem.remove_random_item()
	if dropped != "":
		var side_dir = Vector2.RIGHT.rotated(rotation) if randf() > 0.5 else Vector2.LEFT.rotated(rotation)
		var crate = crate_scene.instantiate()
		crate.global_position = global_position + side_dir * 20.0
		var parent := get_parent()
		if is_instance_valid(parent):
			parent.add_child(crate)
	
	if hull_hp <= 0:
		hull_hp = 0
		_sink_ship()

func _process_storm_damage(delta: float) -> void:
	if wind_strength > STORM_WIND_THRESHOLD and sail_gear == 2:
		splinter_particles.emitting = true
		var dmg = STORM_DAMAGE_PER_SEC * delta
		hull_hp -= dmg
		GameState.modify_hp(-dmg)
		var hp_int := int(hull_hp)
		if hp_int != _last_reported_hp:
			_last_reported_hp = hp_int
			_notify_hud_stats()
		if hull_hp <= 0:
			hull_hp = 0
			_sink_ship()
	else:
		if wind_strength <= STORM_WIND_THRESHOLD:
			splinter_particles.emitting = false

func _sink_ship() -> void:
	CargoSystem.clear_all()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
