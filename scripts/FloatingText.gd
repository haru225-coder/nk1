extends Label

## NK1-P6-POLISH-004: 默认值从 FloatingTextConfig 读取
var float_speed: float = FloatingTextConfig.DEFAULT_FLOAT_SPEED
var lifetime: float = FloatingTextConfig.DEFAULT_LIFETIME

func _ready() -> void:
	global_position += Vector2(
		randf_range(-FloatingTextConfig.RANDOM_JITTER, FloatingTextConfig.RANDOM_JITTER),
		randf_range(-FloatingTextConfig.RANDOM_JITTER, FloatingTextConfig.RANDOM_JITTER)
	)
	var target_y := global_position.y - float_speed * lifetime
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", target_y, lifetime)
	tween.parallel().tween_property(self, "modulate:a", 0.0, lifetime)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished() -> void:
	queue_free()