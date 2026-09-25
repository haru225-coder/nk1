## 过场粒子层：mist / embers / snow / rain / sea_spray / dust / lantern_glow。
## 全部 CPUParticles2D（不用 GPUParticles2D），贴图来自 assets/fx/（build_fx_textures.py 生成）。
## 预热（preprocess）后入镜即满屏，不会「从零长出来」。
extends RefCounted

const Kit := preload("res://scripts/cutscene/cs_kit.gd")

const KINDS := ["mist", "embers", "snow", "rain", "sea_spray", "dust", "lantern_glow"]


static func build(kinds: Array, canvas: Vector2, grade: String) -> Node2D:
	var root := Node2D.new()
	root.name = "Fx"
	for k in kinds:
		var kind := str(k)
		match kind:
			"mist":
				_mist(root, canvas, grade, 0.62, 0.3, 1.0)
			"embers":
				_embers(root, canvas)
			"snow":
				_snow(root, canvas)
			"rain":
				_rain(root, canvas)
			"sea_spray":
				_spray(root, canvas)
			"dust":
				_dust(root, canvas)
			"lantern_glow":
				_glow(root, canvas)
			_:
				push_warning("未知 fx：%s（可用：%s）" % [kind, ", ".join(KINDS)])
	return root


static func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


static func _ramp(points: Array) -> Gradient:
	# points: [[offset, Color], ...]
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for pt in points:
		offs.append(float(pt[0]))
		cols.append(pt[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	return g


static func _base(root: Node2D, tex_name: String, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Kit.fx_texture(tex_name)
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.local_coords = false
	p.emitting = true
	root.add_child(p)
	return p


static func _mist(root: Node2D, c: Vector2, grade: String, cy: float, ext: float, strength: float) -> void:
	var col := Kit.C_MOON
	match grade:
		"night":
			col = Color(0.5, 0.58, 0.68)
		"fire":
			col = Color(0.3, 0.25, 0.22)
		"dusk":
			col = Color(0.93, 0.8, 0.68)
		"cold":
			col = Color(0.78, 0.85, 0.9)
		"sepia":
			col = Color(0.85, 0.78, 0.66)
	var p := _base(root, "mist_puff.png", 12, 18.0)
	p.position = Vector2(c.x * 0.5, c.y * cy)
	p.emission_rect_extents = Vector2(c.x * 0.62, c.y * ext)
	p.direction = Vector2(1, -0.05)
	p.spread = 10.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 22.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -2.5
	p.angular_velocity_max = 2.5
	p.scale_amount_min = 2.4
	p.scale_amount_max = 3.8
	p.color = col
	var pk := 0.2 * strength
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.3, Color(1, 1, 1, pk)], [0.7, Color(1, 1, 1, pk)], [1.0, Color(1, 1, 1, 0)]])


static func _embers(root: Node2D, c: Vector2) -> void:
	var ramp := _ramp([
		[0.0, Color(1.0, 0.9, 0.62, 0.0)], [0.06, Color(1.0, 0.82, 0.45, 1.0)],
		[0.45, Color(1.0, 0.5, 0.16, 0.85)], [1.0, Color(0.6, 0.12, 0.04, 0.0)],
	])
	var p := _base(root, "ember.png", 110, 4.4)
	p.position = Vector2(c.x * 0.5, c.y + 12.0)
	p.emission_rect_extents = Vector2(c.x * 0.6, 14.0)
	p.direction = Vector2(0.18, -1)
	p.spread = 24.0
	p.gravity = Vector2(10, -14)
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 150.0
	p.damping_min = 2.0
	p.damping_max = 9.0
	p.tangential_accel_min = -18.0
	p.tangential_accel_max = 18.0
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.35
	p.color_ramp = ramp
	p.material = _add_mat()
	# 近景：少量大而虚的火星，拉出纵深
	var n := _base(root, "glow_warm.png", 12, 3.2)
	n.position = Vector2(c.x * 0.5, c.y + 30.0)
	n.emission_rect_extents = Vector2(c.x * 0.55, 10.0)
	n.direction = Vector2(0.1, -1)
	n.spread = 18.0
	n.gravity = Vector2(6, -20)
	n.initial_velocity_min = 140.0
	n.initial_velocity_max = 240.0
	n.scale_amount_min = 0.22
	n.scale_amount_max = 0.42
	n.color_ramp = _ramp([[0.0, Color(1.0, 0.7, 0.35, 0.0)], [0.15, Color(1.0, 0.66, 0.3, 0.75)], [1.0, Color(0.9, 0.3, 0.1, 0.0)]])
	n.material = _add_mat()


static func _snow(root: Node2D, c: Vector2) -> void:
	var ramp := _ramp([[0.0, Color(1, 1, 1, 0)], [0.06, Color(1, 1, 1, 1)], [0.88, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	var far := _base(root, "snow_flake.png", 300, 11.0)
	far.position = Vector2(c.x * 0.45, -24.0)
	far.emission_rect_extents = Vector2(c.x * 0.7, 10.0)
	far.direction = Vector2(0.12, 1)
	far.spread = 12.0
	far.gravity = Vector2(6, 5)
	far.initial_velocity_min = 30.0
	far.initial_velocity_max = 62.0
	far.angular_velocity_min = -40.0
	far.angular_velocity_max = 40.0
	far.scale_amount_min = 0.2
	far.scale_amount_max = 0.5
	far.color = Color(Kit.C_MOON, 0.85)
	far.color_ramp = ramp
	var near := _base(root, "soft_dot.png", 22, 6.0)
	near.position = Vector2(c.x * 0.4, -60.0)
	near.emission_rect_extents = Vector2(c.x * 0.7, 10.0)
	near.direction = Vector2(0.18, 1)
	near.spread = 8.0
	near.gravity = Vector2(10, 10)
	near.initial_velocity_min = 90.0
	near.initial_velocity_max = 130.0
	near.scale_amount_min = 0.3
	near.scale_amount_max = 0.5
	near.color = Color(Kit.C_MOON, 0.42)
	near.color_ramp = ramp


static func _rain(root: Node2D, c: Vector2) -> void:
	var p := _base(root, "rain_streak.png", 280, 0.8)
	p.position = Vector2(c.x * 0.4, -80.0)
	p.emission_rect_extents = Vector2(c.x * 0.75, 10.0)
	p.direction = Vector2(0.2, 1)
	p.spread = 2.0
	p.gravity = Vector2(0, 500)
	p.initial_velocity_min = 950.0
	p.initial_velocity_max = 1250.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.1
	p.color = Color(0.78, 0.84, 0.9, 0.3)
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0.6)], [0.2, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 1)]])
	_mist(root, c, "cold", 0.75, 0.25, 0.55)


static func _spray(root: Node2D, c: Vector2) -> void:
	var p := _base(root, "spray_drop.png", 110, 1.6)
	p.position = Vector2(c.x * 0.5, c.y + 10.0)
	p.emission_rect_extents = Vector2(c.x * 0.62, 8.0)
	p.direction = Vector2(0.28, -1)
	p.spread = 26.0
	p.gravity = Vector2(40, 430)
	p.initial_velocity_min = 170.0
	p.initial_velocity_max = 390.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.4
	p.color = Color(0.9, 0.95, 0.97, 0.7)
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.08, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]])
	var haze := _base(root, "mist_puff.png", 9, 5.0)
	haze.position = Vector2(c.x * 0.5, c.y * 0.96)
	haze.emission_rect_extents = Vector2(c.x * 0.6, c.y * 0.06)
	haze.direction = Vector2(0.4, -1)
	haze.spread = 20.0
	haze.initial_velocity_min = 16.0
	haze.initial_velocity_max = 40.0
	haze.gravity = Vector2(4, -4)
	haze.scale_amount_min = 1.6
	haze.scale_amount_max = 2.8
	haze.angle_max = 360.0
	haze.color = Color(0.88, 0.92, 0.95)
	haze.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.3, Color(1, 1, 1, 0.2)], [1.0, Color(1, 1, 1, 0)]])


static func _dust(root: Node2D, c: Vector2) -> void:
	var p := _base(root, "dust_mote.png", 70, 12.0)
	p.position = c * 0.5
	p.emission_rect_extents = c * 0.52
	p.direction = Vector2(0.3, -1)
	p.spread = 180.0
	p.gravity = Vector2(1.6, -1.2)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 11.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.95
	p.color = Color(1.0, 0.86, 0.62)
	p.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.25, Color(1, 1, 1, 0.55)], [0.75, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0)]])
	p.material = _add_mat()


static func _glow(root: Node2D, c: Vector2) -> void:
	var p := _base(root, "glow_warm.png", 7, 7.0)
	p.position = Vector2(c.x * 0.5, c.y * 0.56)
	p.emission_rect_extents = Vector2(c.x * 0.44, c.y * 0.3)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(1.0, 0.62, 0.28)
	# 多峰 alpha：一盏灯的明灭
	p.color_ramp = _ramp([
		[0.0, Color(1, 1, 1, 0)], [0.18, Color(1, 1, 1, 0.26)], [0.32, Color(1, 1, 1, 0.15)],
		[0.48, Color(1, 1, 1, 0.28)], [0.66, Color(1, 1, 1, 0.17)], [0.82, Color(1, 1, 1, 0.24)], [1.0, Color(1, 1, 1, 0)],
	])
	p.material = _add_mat()
