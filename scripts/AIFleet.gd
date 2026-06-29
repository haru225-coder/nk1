extends Area2D
class_name AIFleetNode

const _THEME_PATH := ResourcePaths.THEME_MAIN

var fleet_id: String = ""
var fleet_name: String = ""
var sprite: Node2D
var label: Label

signal player_encountered(fleet_id: String)

func _ready() -> void:
	var visual_script: Script = load("res://scripts/ships/ShipVisual.gd") as Script
	var visual := Node2D.new()
	visual.set_script(visual_script)
	visual.scale = Vector2(0.75, 0.75)
	if visual.has_method("set_hull"):
		visual.set_hull("fujian_merchant")
	if "sail_gear" in visual:
		visual.sail_gear = 1
	sprite = visual
	add_child(sprite)
	
	# Physical Collision
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	add_child(shape)
	
	# Label
	label = Label.new()
	label.text = fleet_name
	label.position = Vector2(-50, -60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.theme = load(_THEME_PATH) as Theme
	label.theme_type_variation = UITheme.LABEL_SEA_HUD_FLEET
	add_child(label)
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		player_encountered.emit(fleet_id)

# 纯视觉平滑追踪逻辑坐标
func update_logic_position(pos: Vector2, delta: float) -> void:
	if position == Vector2.ZERO:
		position = pos
	else:
		# 判断朝向
		var dir = (pos - position).normalized()
		if dir.length() > 0.1:
			sprite.rotation = dir.angle() + PI/2.0
		position = position.lerp(pos, 5.0 * delta)
