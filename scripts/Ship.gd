extends CharacterBody2D

## 玩家旗舰场景节点 — 委托 ShipSystem 航行/同步，ShipVisual 绘制船体。

signal hud_stats_changed

@export var wind_vector: Vector2 = Vector2(0, 1).normalized()
@export var wind_strength: float = 80.0

var sail_gear: int = 0
var max_gear: int = 2
var base_turn_speed: float = 1.8
var max_speed: float = 300.0
var hull_hp: float = 100.0
var max_hp: float = 100.0

@onready var _visual: Node2D = $ShipVisual
@onready var _effects: Node = $ShipEffects

var crate_scene = preload(ResourcePaths.SCENE_CRATE)
var _last_reported_hp: int = -1
var _sinking: bool = false


func _ready() -> void:
	if not is_in_group("player_ship"):
		add_to_group("player_ship")
	_remove_legacy_ship_sprite()
	_sync_from_flagship()


func _remove_legacy_ship_sprite() -> void:
	# 旧版 Ship.tscn 的 PNG 精灵与 ShipVisual 叠绘会形成「十字双船」
	var legacy := get_node_or_null("Sprite2D")
	if legacy is Sprite2D:
		legacy.queue_free()


func _flagship() -> ShipState:
	return GameState.fleet.get_flagship()


func _sync_from_flagship() -> void:
	var flagship := _flagship()
	if flagship == null:
		return
	ShipSystem.sync_runtime_from_state(self, flagship)
	if _visual.has_method("set_hull"):
		_visual.set_hull(flagship.hull_id, flagship.sail_type)
		_sync_particle_layout()
	_sync_collision_radius()
	if _visual.has_method("set_hp_ratio") and max_hp > 0.0:
		_visual.set_hp_ratio(hull_hp / max_hp)
	_last_reported_hp = int(hull_hp)


func _sync_collision_radius() -> void:
	if not _visual.has_method("get_collision_radius"):
		return
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not (shape_node.shape is CircleShape2D):
		return
	(shape_node.shape as CircleShape2D).radius = _visual.get_collision_radius()


func _sync_particle_layout() -> void:
	if not _visual.has_method("get_wake_offset"):
		return
	var wake: Node = get_node_or_null("WakeParticles")
	if wake:
		wake.position = _visual.get_wake_offset()
	var bows: Array = _visual.get_bow_wave_offsets()
	if bows.size() < 2:
		return
	var bow_l: Node = get_node_or_null("BowWaveLeft")
	var bow_r: Node = get_node_or_null("BowWaveRight")
	if bow_l:
		bow_l.position = bows[0]
	if bow_r:
		bow_r.position = bows[1]


func _input(event: InputEvent) -> void:
	var new_gear := ShipSystem.handle_sail_input(event, sail_gear, max_gear)
	if new_gear != sail_gear:
		sail_gear = new_gear
		hud_stats_changed.emit()


func _physics_process(delta: float) -> void:
	if _sinking or hull_hp <= 0:
		return

	var sail_result := ShipSystem.step_sailing(
		self,
		delta,
		GameState.crew_count,
		GameState.sail_type,
		func(): GameState.apply_effects({"crew_count": -1})
	)
	if sail_result.stats_changed:
		hud_stats_changed.emit()

	move_and_slide()
	_update_visuals(delta, sail_result)
	_process_storm_damage(delta)


func _update_visuals(delta: float, sail_result: Dictionary) -> void:
	var turn_input := Input.get_axis("ui_left", "ui_right")
	if _visual.has_method("update_motion"):
		_visual.update_motion(
			sail_gear,
			sail_result.speed,
			max_speed,
			rotation,
			wind_vector,
			wind_strength,
			turn_input,
			delta,
			float(sail_result.get("efficiency", 1.0))
		)
	if _visual.has_method("set_hp_ratio") and max_hp > 0.0:
		_visual.set_hp_ratio(hull_hp / max_hp)
	if _effects.has_method("update_motion"):
		_effects.update_motion(sail_result.speed, max_speed, wind_strength, delta)


func take_damage(amount: float) -> void:
	if _effects.has_method("flash_splinters"):
		_effects.flash_splinters()
	ShipSystem.apply_damage(self, _flagship(), amount)
	_last_reported_hp = int(hull_hp)
	hud_stats_changed.emit()
	_drop_cargo_if_hit()


func _drop_cargo_if_hit() -> void:
	var dropped := CargoSystem.remove_random_item()
	if dropped == "":
		return
	var side_dir := Vector2.RIGHT.rotated(rotation) if randf() > 0.5 else Vector2.LEFT.rotated(rotation)
	var crate := crate_scene.instantiate()
	crate.global_position = global_position + side_dir * 20.0
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.add_child(crate)


func _process_storm_damage(delta: float) -> void:
	if not ShipSystem.should_storm_damage(wind_strength, sail_gear):
		if _effects.has_method("set_splinters"):
			_effects.set_splinters(false)
		return
	if _effects.has_method("set_splinters"):
		_effects.set_splinters(true)
	var flagship := _flagship()
	if flagship == null:
		return
	ShipSystem.apply_damage(self, flagship, ShipSystem.storm_damage_amount(delta))
	var hp_int := int(hull_hp)
	if hp_int != _last_reported_hp:
		_last_reported_hp = hp_int
		hud_stats_changed.emit()
	if hull_hp <= 0.0:
		_sink_ship()


func _sink_ship() -> void:
	if _sinking:
		return
	_sinking = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	set_process_input(false)
	GameManager.set_input_locked(true)
	GameState.game_log.warning(GameLog.Category.VOYAGE, "旗舰沉没，货物尽失。")
	if _effects.has_method("play_sink"):
		_effects.play_sink(_visual, _finish_sink)
	else:
		_finish_sink()


func _finish_sink() -> void:
	GameState.clear_world_map_ship_pose()
	CargoSystem.clear_all()
	GameManager.set_input_locked(false)
	get_tree().change_scene_to_file(ResourcePaths.SCENE_MAIN)