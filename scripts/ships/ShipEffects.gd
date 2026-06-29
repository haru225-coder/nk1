extends Node

## 船体周边特效与镜头 — 尾迹、船首浪、震屏、变焦。

const WAKE_SPEED_THRESHOLD := 20.0
const BOW_WAVE_THRESHOLD := 100.0
const ZOOM_BASE := 1.5
const ZOOM_REDUCTION := 0.5
const ZOOM_LERP_SPEED := 1.0
const SHAKE_SPEED_THRESHOLD := 250.0
const SHAKE_WIND_THRESHOLD := 150.0
const SHAKE_MAX_INTENSITY := 2.0

@onready var wake_particles: CPUParticles2D = $"../WakeParticles"
@onready var bow_wave_left: CPUParticles2D = $"../BowWaveLeft"
@onready var bow_wave_right: CPUParticles2D = $"../BowWaveRight"
@onready var splinter_particles: CPUParticles2D = $"../SplinterParticles"
@onready var camera: Camera2D = $"../Camera2D"


func update_motion(current_speed: float, max_speed: float, wind_strength: float, delta: float) -> void:
	_update_wake(current_speed, max_speed)
	_update_camera(current_speed, max_speed, wind_strength, delta)


func set_splinters(active: bool) -> void:
	if is_instance_valid(splinter_particles):
		splinter_particles.emitting = active


func flash_splinters(duration: float = 0.5) -> void:
	set_splinters(true)
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(splinter_particles):
			splinter_particles.emitting = false
	)


func _update_wake(current_speed: float, max_speed: float) -> void:
	var speed_ratio := current_speed / maxf(max_speed * ZOOM_BASE, 1.0)
	if current_speed > WAKE_SPEED_THRESHOLD:
		wake_particles.emitting = true
		wake_particles.initial_velocity_min = 20.0 + speed_ratio * 80.0
		wake_particles.initial_velocity_max = 40.0 + speed_ratio * 120.0
		wake_particles.scale_amount_max = 4.0 + speed_ratio * 6.0
		var bow_emit := current_speed > BOW_WAVE_THRESHOLD
		bow_wave_left.emitting = bow_emit
		bow_wave_right.emitting = bow_emit
		if bow_emit:
			bow_wave_left.scale_amount_max = 2.0 + speed_ratio * 4.0
			bow_wave_right.scale_amount_max = 2.0 + speed_ratio * 4.0
	else:
		wake_particles.emitting = false
		bow_wave_left.emitting = false
		bow_wave_right.emitting = false


func _update_camera(current_speed: float, max_speed: float, wind_strength: float, delta: float) -> void:
	var speed_ratio := current_speed / maxf(max_speed * ZOOM_BASE, 1.0)
	var zoom_val := clampf(ZOOM_BASE - speed_ratio * ZOOM_REDUCTION, 0.5, ZOOM_BASE)
	camera.zoom = camera.zoom.lerp(Vector2(zoom_val, zoom_val), ZOOM_LERP_SPEED * delta)
	if current_speed > SHAKE_SPEED_THRESHOLD or wind_strength > SHAKE_WIND_THRESHOLD:
		var shake := clampf(current_speed / 400.0, 0.0, 1.0) * SHAKE_MAX_INTENSITY
		camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		camera.offset = Vector2.ZERO