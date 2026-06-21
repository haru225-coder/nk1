extends Area2D

signal encounter_triggered(data: Dictionary, node: Node2D)

const _SHIP_TEX: Texture2D = preload("res://assets/ship_topdown.png")

var encounter_data: Dictionary = {}
var move_dir: Vector2 = Vector2.ZERO
var move_speed: float = 50.0
var _triggered: bool = false

@onready var sprite: Sprite2D = $Sprite2D


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


func setup(data: Dictionary) -> void:
	encounter_data = data
	_apply_visuals(data.get("id", ""))


func _apply_visuals(archetype_id: String) -> void:
	if sprite == null:
		return
	sprite.texture = _SHIP_TEX
	match archetype_id:
		"pirate_wokou":
			sprite.modulate = Color(1.0, 0.45, 0.4)
			move_speed = 65.0
		"patrol_song":
			sprite.modulate = Color(0.55, 0.75, 1.0)
			move_speed = 45.0
		"merchant_arab":
			sprite.modulate = Color(0.95, 0.85, 0.5)
			move_speed = 40.0
		_:
			sprite.modulate = Color(0.85, 0.85, 0.9)


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player_ship"):
		return
	_triggered = true
	set_process(false)
	monitoring = false
	encounter_triggered.emit(encounter_data, self)