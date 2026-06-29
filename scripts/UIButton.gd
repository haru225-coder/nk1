extends Button
class_name UIButton

## NK1-P6-POLISH-002: 可复用 UIButton 预制体
## 用法: var btn = UIButtonFactory.create("文本", UITheme.BTN_SET_SAIL, 60)
## 也可以直接 instantiate() scenes/UIButton.tscn

@export var theme_variation: String = "ActionButton"
@export var min_height: int = 52

func _ready() -> void:
	# 应用配置（如果通过代码设置了属性）
	theme_type_variation = theme_variation
	custom_minimum_size = Vector2(custom_minimum_size.x, min_height)
