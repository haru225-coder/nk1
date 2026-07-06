class_name MapCompassRose
extends Control

const COMPASS_RADIUS := 120.0
const COLOR_INK := Color(0.15, 0.12, 0.08, 0.7)
const COLOR_RED := Color(0.65, 0.15, 0.15, 0.85)

var _font: Font
# 二十四山（顺时针：北 -> 东 -> 南 -> 西）
# 上北（子），右东（卯），下南（午），左西（酉）
var _labels = ["子", "癸", "丑", "艮", "寅", "甲", "卯", "乙", "辰", "巽", "巳", "丙", "午", "丁", "未", "坤", "申", "庚", "酉", "辛", "戌", "乾", "亥", "壬"]

func _ready() -> void:
	var lbl := Label.new()
	_font = lbl.get_theme_font("font")
	lbl.free()

	custom_minimum_size = Vector2(COMPASS_RADIUS * 2.5, COMPASS_RADIUS * 2.5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	if not _font:
		return

	var center := size / 2.0

	# 画罗盘外圈和内圈
	draw_arc(center, COMPASS_RADIUS, 0, TAU, 64, COLOR_INK, 3.0)
	draw_arc(center, COMPASS_RADIUS - 25.0, 0, TAU, 64, COLOR_INK, 1.5)

	# 绘制天干地支二十四山
	var angle_step := TAU / 24.0
	for i in range(24):
		var angle := i * angle_step - PI / 2.0 # -PI/2 是正上方 (子)
		var text: String = str(_labels[i])
		var dir := Vector2(cos(angle), sin(angle))

		# 刻度线
		var is_cardinal = (i % 6 == 0)
		var line_width = 3.0 if is_cardinal else 1.0
		var line_color = COLOR_RED if is_cardinal else COLOR_INK
		draw_line(center + dir * (COMPASS_RADIUS - 25.0), center + dir * COMPASS_RADIUS, line_color, line_width)

		var text_pos := center + dir * (COMPASS_RADIUS - 12.0)
		var string_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)

		# 旋转文字使其朝向圆心
		draw_set_transform(text_pos, angle + PI/2.0, Vector2.ONE)
		draw_string(_font, -string_size/2.0 + Vector2(0, _font.get_ascent(16) * 0.7), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, line_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 中心点与指南针指针
	draw_circle(center, 6.0, COLOR_RED)

	# 指南针指针 (古代指南鱼/磁针，南极为红)
	var p_north = center + Vector2(0, -COMPASS_RADIUS + 35) # 指向子
	var p_south = center + Vector2(0, COMPASS_RADIUS - 35)  # 指向午
	var p_east = center + Vector2(6, 0)
	var p_west = center + Vector2(-6, 0)

	# 北半段 (黑/墨色)
	draw_polygon(PackedVector2Array([p_north, p_east, center]), PackedColorArray([COLOR_INK, COLOR_INK, COLOR_INK]))
	draw_polygon(PackedVector2Array([p_north, center, p_west]), PackedColorArray([COLOR_INK, COLOR_INK, COLOR_INK]))

	# 南半段 (朱砂红，古法司南指南)
	draw_polygon(PackedVector2Array([center, p_east, p_south]), PackedColorArray([COLOR_RED, COLOR_RED, COLOR_RED]))
	draw_polygon(PackedVector2Array([p_west, center, p_south]), PackedColorArray([COLOR_RED, COLOR_RED, COLOR_RED]))
