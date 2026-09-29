extends Node2D
## 桅顶长旒（lane atmos）：一条顺风飘的燕尾旗。敌船黑旒朱边，我船素旒——两船一眼分得开，也顺带标出风往哪吹。
## 挂在船节点下（跟船走），自己按世界风向把旗身转到下风，逐帧画；不碰船的精灵与材质。

## 旗身长 / 根部宽（像素）
var length := 60.0
var root_w := 10.0
var fill := Color(0.07, 0.06, 0.06, 0.95)
var trim := Color(0.72, 0.25, 0.17, 0.9)
## 世界风向（往哪吹，单位向量）与风力 0–1：SeaAtmosphere 每帧写
var wind := Vector2(0, 1)
var force := 0.6

var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta * (1.6 + force * 2.4)
	queue_redraw()


func _draw() -> void:
	# 旗向：世界风向转进船局部（船转，旗仍朝下风）
	var host := get_parent() as Node2D
	var rot := host.global_rotation if host != null else 0.0
	var dir := wind.normalized().rotated(-rot) if wind.length() > 0.01 else Vector2.DOWN
	var nrm := dir.orthogonal()
	var segs := 10
	var amp := 2.2 + 3.0 * (1.0 - force)
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var len_k := 0.75 + 0.35 * force
	for i in segs + 1:
		var s := float(i) / float(segs)
		var along := dir * length * len_k * s
		var wave := nrm * sin(_t * 2.0 - s * 5.5) * amp * s
		var half := root_w * 0.5 * (1.0 - 0.55 * s)
		top.append(along + wave + nrm * half)
		bot.append(along + wave - nrm * half)
	# 燕尾：尾端中间收一刀
	var tip_mid := dir * length * len_k * 0.86 + nrm * sin(_t * 2.0 - 0.86 * 5.5) * amp * 0.86
	var poly := PackedVector2Array()
	poly.append_array(top)
	poly.append(tip_mid)
	var rb := bot.duplicate()
	rb.reverse()
	poly.append_array(rb)
	draw_colored_polygon(poly, fill)
	var edge := PackedVector2Array(top)
	edge.append(tip_mid)
	edge.append_array(rb)
	edge.append(top[0])
	draw_polyline(edge, trim, 1.2, true)
	# 旗杆头一点
	draw_circle(Vector2.ZERO, 2.2, trim.darkened(0.3))
