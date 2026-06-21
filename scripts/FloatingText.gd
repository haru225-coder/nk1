extends Label

var float_speed: float = 50.0
var lifetime: float = 1.5

func _ready() -> void:
	global_position += Vector2(randf_range(-20, 20), randf_range(-20, 20))
	var target_y := global_position.y - float_speed * lifetime
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", target_y, lifetime)
	tween.parallel().tween_property(self, "modulate:a", 0.0, lifetime)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	queue_free()