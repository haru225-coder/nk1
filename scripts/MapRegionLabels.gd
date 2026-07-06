class_name MapRegionLabels
extends Node2D

const LABEL_COLOR := Color(0.15, 0.12, 0.08, 0.12) # 极低透明度的深褐色墨迹
const FONT_SIZE := 300

# 定义地理大字的位置 (使用相对于地图中心的世界坐标)
var regions = [
	{"text": "大  宋", "pos": Vector2(-1200, -800), "rot": 0.0},
	{"text": "东  海", "pos": Vector2(800, -1000), "rot": 0.0},
	{"text": "流  求", "pos": Vector2(1500, 200), "rot": deg_to_rad(15)},
	{"text": "黑 水 沟", "pos": Vector2(1200, 800), "rot": deg_to_rad(45)},
	{"text": "南  海", "pos": Vector2(-500, 2500), "rot": 0.0},
]

var _font: Font

func _ready() -> void:
	z_index = 2 # 显示在网格之上，路线和港口之下
	# 获取系统默认字体或任何已加载字体
	var lbl = Label.new()
	_font = lbl.get_theme_font("font")
	lbl.free()
	queue_redraw()

func _draw() -> void:
	if not _font:
		return

	for region in regions:
		var text: String = region["text"]
		var pos: Vector2 = region["pos"]
		var rot: float = region["rot"]

		# 使用 draw_set_transform 旋转文本
		draw_set_transform(pos, rot, Vector2.ONE)
		# 居中绘制文本
		var text_size = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var offset = -text_size / 2.0
		# 这里通过 draw_string 绘制墨迹大字
		draw_string(_font, offset + Vector2(0, _font.get_ascent(FONT_SIZE)), text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, LABEL_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
