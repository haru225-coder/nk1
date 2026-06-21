extends Area2D

@export var speed: float = 800.0
@export var damage: float = 25.0
@export var lifetime: float = 2.0
var direction: Vector2 = Vector2.ZERO
var shooter: Node2D = null

var water_splash = preload("res://scenes/WaterSplash.tscn")
var impact_explosion = preload("res://scenes/ImpactExplosion.tscn")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime, false).timeout.connect(func():
		if is_instance_valid(self):
			_splash_and_die()
	)

func _process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == shooter: return
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
		_explode_and_die()
		_spawn_floating_text("-" + str(int(damage)), Color.RED)
	else:
		_splash_and_die()

func _splash_and_die() -> void:
	var splash = water_splash.instantiate()
	splash.global_position = global_position
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.call_deferred("add_child", splash)
		splash.emitting = true
	queue_free()

func _explode_and_die() -> void:
	var expl = impact_explosion.instantiate()
	expl.global_position = global_position
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.call_deferred("add_child", expl)
		expl.emitting = true
	queue_free()

func _spawn_floating_text(text: String, color: Color) -> void:
	var ft = ResourceManager.FloatingText.instantiate()
	ft.global_position = global_position
	ft.text = text
	# 使用 modulate 避免破坏主题缓存
	ft.modulate = color
	var parent := get_parent()
	if is_instance_valid(parent):
		parent.call_deferred("add_child", ft)
