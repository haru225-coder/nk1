extends Area2D

signal encounter_triggered(data: Dictionary, node: Node2D)

var encounter_data: Dictionary = {}
var move_dir: Vector2 = Vector2.ZERO
var move_speed: float = 50.0
var _triggered: bool = false

@onready var _visual: Node2D = $ShipVisual


func _ready() -> void:
	add_to_group("map_fleet")
	body_entered.connect(_on_body_entered)
	var angle := randf() * TAU
	move_dir = Vector2(cos(angle), sin(angle))
	rotation = move_dir.angle() + PI / 2.0


func _process(delta: float) -> void:
	if _triggered:
		return
	position += move_dir * move_speed * delta
	if _visual != null and "sail_gear" in _visual:
		_visual.sail_gear = 1 if move_speed > 0.0 else 0
		_visual.queue_redraw()


func setup(data: Dictionary) -> void:
	encounter_data = data
	_apply_visuals(data.get("id", ""))


func _apply_visuals(archetype_id: String) -> void:
	if _visual == null:
		return
	var hull_id := "fujian_merchant"
	var tint := GameColors.FLEET_DEFAULT
	match archetype_id:
		"pirate_wokou":
			hull_id = "fujian_merchant"
			tint = GameColors.PIRATE_RED
			move_speed = 65.0
		"patrol_song":
			hull_id = "warship_patrol"
			tint = GameColors.PATROL_BLUE
			move_speed = 45.0
		"merchant_arab":
			hull_id = "guangzhou_trader"
			tint = GameColors.TEXT_GOLD
			move_speed = 40.0
		_:
			hull_id = "fujian_merchant"
			tint = GameColors.FLEET_DEFAULT
	if _visual.has_method("set_hull"):
		_visual.set_hull(hull_id)
	if "sail_gear" in _visual:
		_visual.sail_gear = 1
	_visual.modulate = tint
	_visual.queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player_ship"):
		return
	_triggered = true
	set_process(false)
	monitoring = false
	encounter_triggered.emit(encounter_data, self)