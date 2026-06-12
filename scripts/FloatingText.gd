extends Label

var float_speed: float = 50.0
var lifetime: float = 1.5

func _ready() -> void:
	# Add some jitter to position
	position += Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	var tween = create_tween()
	# Float up
	tween.tween_property(self, "position:y", position.y - float_speed * lifetime, lifetime)
	tween.parallel().tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_callback(func(): queue_free())
