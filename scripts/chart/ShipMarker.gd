class_name ShipMarker
extends Node2D
## 海图上的己船：宋式海舶俯视剪影，墨线 + 纸色帆，随航向旋转（图上正北 = 0）。
## 用矢量画而不用贴图：assets/ship_topdown.png 是烤死了棋盘格的假透明图，放到绢本上是一块白方。
## 局部坐标：船首朝 -y，全长 BASE_LEN，MapView 按屏幕像素反缩放。

const BASE_LEN := 40.0
const INK := Color(0.169, 0.141, 0.094)
const SAIL := Color(0.93, 0.885, 0.77)
const HULL := Color(0.36, 0.27, 0.16)
const CINNABAR := Color(0.722, 0.196, 0.122)

var _sway_t: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_sway_t += delta
	queue_redraw()


func _draw() -> void:
	var L := BASE_LEN
	var half := L * 0.5
	var beam := L * 0.19
	# 船体：尖艏方艉的福船轮廓
	var hull := PackedVector2Array([
		Vector2(0, -half),
		Vector2(beam * 0.55, -half * 0.62),
		Vector2(beam, -half * 0.10),
		Vector2(beam * 0.92, half * 0.78),
		Vector2(beam * 0.55, half),
		Vector2(-beam * 0.55, half),
		Vector2(-beam * 0.92, half * 0.78),
		Vector2(-beam, -half * 0.10),
		Vector2(-beam * 0.55, -half * 0.62),
	])
	# 纸白衬底，深海上也立得住
	draw_colored_polygon(_grow(hull, 2.2), Color(SAIL, 0.85))
	draw_colored_polygon(hull, HULL)
	var outline := PackedVector2Array(hull)
	outline.append(hull[0])
	draw_polyline(outline, INK, 1.4, true)
	# 三面硬帆：随微浪轻摆
	var sway := sin(_sway_t * 1.7) * 0.06
	var sails := [
		[Vector2(0, -half * 0.42), L * 0.30, L * 0.16],
		[Vector2(0, half * 0.02), L * 0.40, L * 0.20],
		[Vector2(0, half * 0.50), L * 0.28, L * 0.14],
	]
	for s in sails:
		var c: Vector2 = s[0]
		var w: float = s[1]
		var h: float = s[2]
		draw_set_transform(c, sway, Vector2.ONE)
		var r := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
		draw_rect(r, SAIL, true)
		draw_rect(r, INK, false, 1.0)
		# 帆骨
		var n := 3
		for i in range(1, n):
			var y := r.position.y + r.size.y * float(i) / float(n)
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(INK, 0.55), 0.8)
		draw_line(Vector2(0, r.position.y - 1.0), Vector2(0, r.end.y + 1.0), INK, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 艉部朱旗
	draw_line(Vector2(0, half * 0.86), Vector2(0, half * 0.86 - L * 0.16), INK, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, half * 0.86 - L * 0.16), Vector2(L * 0.09, half * 0.86 - L * 0.13), Vector2(0, half * 0.86 - L * 0.09),
	]), CINNABAR)


static func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	for p in poly:
		out.append(c + (p - c) * (1.0 + by / maxf(1.0, (p - c).length())))
	return out
