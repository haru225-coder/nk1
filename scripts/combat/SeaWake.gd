extends Node2D
## 一条船的航迹白练（lane atmos）：按船尾走过的点画一条渐宽渐淡的带子，转弯留弯痕。
## 挂在 SeaAtmosphere 下（世界坐标＝WorldMap 局部），海面之上、船影之下。近处的艏波与开尔文斜浪归海面着色器画。
## hull 释放或沉了：不再添点，余迹照常淡完再自删。

const SHADER_PATH := "res://assets/shaders/sea_wake.gdshader"
## 每隔多少秒 / 多少像素记一个点
const STEP_S := 0.06
const STEP_PX := 7.0
## 一点活多久（秒）：航速越高迹越长，这里是上限
const LIFE_S := 3.4
const MAX_PTS := 64
## 相邻两点超过这么远就当是被挪了位，断开重记
const JUMP_PX := 90.0

var hull: Node2D = null
## 船半宽 / 半长（世界像素），SeaAtmosphere 按精灵尺寸给
var half_beam := 46.0
var half_len := 132.0

var _pts: Array = []  # [{p: Vector2, age: float, w: float}]
var _acc := 0.0
var _last := Vector2.INF


func _ready() -> void:
	var sh := load(SHADER_PATH) as Shader
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		material = m


func _process(delta: float) -> void:
	for pt in _pts:
		pt["age"] = float(pt["age"]) + delta
	while not _pts.is_empty() and float(_pts[0]["age"]) > LIFE_S:
		_pts.pop_front()
	var alive := hull != null and is_instance_valid(hull) and float(_prop(hull, "hull_hp", 1.0)) > 0.0
	if alive:
		_acc += delta
		var stern := hull.position + Vector2(0.0, half_len * 0.86).rotated(hull.rotation)
		var spd := _speed()
		# 船被整段挪走（摆拍 / 夺船移位）：旧迹不连过去，免得拉出一片直边大三角
		if _last != Vector2.INF and stern.distance_to(_last) > JUMP_PX:
			_pts.clear()
			_last = Vector2.INF
		if _acc >= STEP_S and (_last == Vector2.INF or stern.distance_to(_last) >= STEP_PX):
			_acc = 0.0
			_last = stern
			# 慢船迹窄淡：w 记下时航速（0–1）
			_pts.append({"p": stern, "age": 0.0, "w": clampf(spd / 260.0, 0.0, 1.0)})
			if _pts.size() > MAX_PTS:
				_pts.pop_front()
	elif _pts.is_empty():
		queue_free()
		return
	queue_redraw()


func _speed() -> float:
	var v = hull.get("velocity")
	if v is Vector2:
		return minf((v as Vector2).length(), 420.0)
	return 0.0


func _draw() -> void:
	var n := _pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var cl := PackedColorArray()
	var ul := PackedVector2Array()
	var ur := PackedVector2Array()
	for i in n:
		var pt: Dictionary = _pts[i]
		var p: Vector2 = pt["p"]
		var a := float(pt["age"]) / LIFE_S
		var w := float(pt["w"])
		var dir: Vector2
		if i < n - 1:
			dir = (_pts[i + 1]["p"] as Vector2) - p
		else:
			dir = p - (_pts[i - 1]["p"] as Vector2)
		if dir.length_squared() < 0.001:
			dir = Vector2.UP
		var nrm := dir.normalized().orthogonal()
		# 出船尾时约船宽六成，越老越散越宽
		var half := half_beam * (0.45 + 1.5 * a) * (0.6 + 0.4 * w)
		left.append(p + nrm * half)
		right.append(p - nrm * half)
		var alpha := (1.0 - a) * (1.0 - a) * (0.25 + 0.75 * w)
		# 最新一段在船身下，渐显免得船尾切出硬边
		if i == n - 1:
			alpha *= 0.0
		elif i == n - 2:
			alpha *= 0.5
		cl.append(Color(1, 1, 1, alpha))
		ul.append(Vector2(0.0, a))
		ur.append(Vector2(1.0, a))
	# 逐段两片三角：急转弯时四边形会拧成麻花，draw_polygon 三角化失败；draw_primitive 不做三角化
	for i in n - 1:
		draw_primitive(PackedVector2Array([left[i], left[i + 1], right[i + 1]]),
			PackedColorArray([cl[i], cl[i + 1], cl[i + 1]]), PackedVector2Array([ul[i], ul[i + 1], ur[i + 1]]))
		draw_primitive(PackedVector2Array([left[i], right[i + 1], right[i]]),
			PackedColorArray([cl[i], cl[i + 1], cl[i]]), PackedVector2Array([ul[i], ur[i + 1], ur[i]]))


static func _prop(o: Object, k: String, fb: float) -> float:
	var v = o.get(k)
	return fb if v == null else float(v)
