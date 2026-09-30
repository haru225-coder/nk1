extends Label

const _CombatFx := preload("res://scripts/combat/CombatFx.gd")

var float_speed: float = 50.0
var lifetime: float = 1.5

func _ready() -> void:
	add_theme_font_override("font", UiTheme.font())
	add_theme_color_override("font_color", UiTheme.CINNABAR)
	add_theme_color_override("font_outline_color", Color(0.07, 0.04, 0.02, 1))
	# 海战镜头拉远（w19-g13）后世界坐标里的飘字按镜头反缩放，屏上字号、飘程与原 zoom 1.5 时一样（CombatFx.world_text_k）
	var tk := _CombatFx.world_text_k(self)
	scale = Vector2(tk, tk)
	float_speed *= tk
	position += Vector2(randf_range(-20, 20), randf_range(-20, 20)) * tk
	
	var tween = create_tween()
	# Float up
	tween.tween_property(self, "position:y", position.y - float_speed * lifetime, lifetime)
	tween.parallel().tween_property(self, "modulate:a", 0.0, lifetime)
	tween.tween_callback(func(): queue_free())
