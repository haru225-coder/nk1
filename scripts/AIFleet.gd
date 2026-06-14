extends Area2D
class_name AIFleetNode

var fleet_id: String = ""
var fleet_name: String = ""
var sprite: Sprite2D
var label: Label

signal player_encountered(fleet_id: String)

func _ready() -> void:
	# Visual Sprite
	sprite = Sprite2D.new()
	var tex = load("res://assets/boat.png")
	if not tex: tex = load("res://icon.svg")
	sprite.texture = tex
	sprite.scale = Vector2(0.5, 0.5)
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
	label.add_theme_font_size_override("font_size", 14)
	add_child(label)
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Ship":
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
