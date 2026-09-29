extends Node2D
## 海战氛围（lane atmos）：海面着色器的驱动 + 航迹 + 敌我旗旒与敌船轮廓 + 落水涟漪 + 接舷镜头。
## WorldMap._setup_combat 末尾 attach(world, ship) 挂一次（节点名 SeaAtmosphere，排在 Ocean 之后、船之前）；
## _board_enemy 钩上敌船时调 boarding_drama(world, ship, enemy)。其余全自动：
##   · 每帧把 SeaState 的风向 / 风力 / 阵风、各船位置航向航速、涟漪写进 sea_surface.gdshader
##   · 场上每条船（旗舰 + PirateShip*）挂一条 SeaWake 白练；敌船加黑旒朱边 + FoeRim 轮廓，旗舰加素旒
##   · 听 node_added：WaterSplash（矢石落水）一出生就在海面上记一圈涟漪，砲石另加一圈白冠
##   · 敌船沉没离树：原地一圈大涟漪
## 不改 Ship / PirateShip / CombatFx / Cannonball 的任何代码与场景；只加子节点、只读属性。
## headless（探针 / 门禁）照挂照跑，只跳过换镜头。

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const SeaWake := preload("res://scripts/combat/SeaWake.gd")
const SeaPennant := preload("res://scripts/combat/SeaPennant.gd")
const SURFACE_SHADER := "res://assets/shaders/sea_surface.gdshader"
const RIM_SHADER := "res://assets/shaders/hull_rim.gdshader"
const HAZE_SHADER := "res://assets/shaders/sea_haze.gdshader"
const FIBER_TEX := "res://assets/fx/noise_fiber.png"
const SPLASH_SCENE := "res://scenes/WaterSplash.tscn"
const NODE_NAME := "SeaAtmosphere"
const GROUP := "nk1_sea_atmos"
const MAX_HULLS := 8
const MAX_RIPPLES := 12
## 海面压到船影之下：ShipSeakeeping 的 HullShadow（z −1）、ship-vfx 的接触影（z −2）原先被 z 0 的海面盖住
const OCEAN_Z := -10
const WAKE_Z := -5
## 风力归一：SeaState.WIND_CAP
const WIND_CAP := 130.0
## 船体尺寸（Sprite2D scale 0.62 时，世界像素）：半宽 / 半长
const HULL_HALF := Vector2(44.0, 128.0)
## 桅顶旗旒挂点（船局部）。HullRig 每帧按三维主桅投影改写；这只是首帧落点。
const PENNANT_AT := Vector2(0.0, -70.0)
## 接舷镜头：拉近倍数、推进 / 停 / 回的秒数
const DRAMA_ZOOM := 1.4
const DRAMA_IN := 0.35
const DRAMA_HOLD := 1.35
const DRAMA_OUT := 0.45

var world: Node2D = null
var ship: Node2D = null
var _mat: ShaderMaterial = null
var _hulls: Array = []  # 跟踪中的船
var _ripples: Array = []  # [{p, age, s}]
var _scan_t := 0.0
var _haze: ColorRect = null
var _haze_focus := 0.0
var _drama_cam: Camera2D = null
var _drama_t := -1.0
var _drama_from_zoom := Vector2.ONE
var _drama_mid := Vector2.ZERO
var _ropes: Array = []
var _last_pos := {}  # instance_id → [Vector2, 是否敌船]
var _boardable := {}  # instance_id → 此刻够得着接舷
var _clock := 0.0


## 挂到 world（WorldMap）下；已挂过返回原节点
static func attach(w: Node2D, flagship: Node2D) -> Node2D:
	if w == null or not is_instance_valid(w):
		return null
	var have := w.get_node_or_null(NODE_NAME) as Node2D
	if have != null:
		return have
	var a: Node2D = (load("res://scripts/combat/SeaAtmosphere.gd") as GDScript).new()
	a.name = NODE_NAME
	a.world = w
	a.ship = flagship
	w.add_child(a)
	var ocean := w.get_node_or_null("Ocean")
	if ocean != null:
		w.move_child(a, ocean.get_index() + 1)
	return a


static func of(w: Node) -> Node2D:
	if w == null or not is_instance_valid(w):
		return null
	return w.get_node_or_null(NODE_NAME) as Node2D


## 接舷：拉近镜头、抛钩缆、两船之间翻白、一闪暖光（BoardingStage 的题签照旧在上层）
static func boarding_drama(w: Node2D, flagship: Node2D, enemy: Node2D) -> void:
	var a := of(w)
	if a == null:
		a = attach(w, flagship)
	if a != null:
		a.call("_boarding", flagship, enemy)


## 在海面上记一圈涟漪：strength 0.3 一排矢、1 砲石、2 沉船
static func ripple_at(w: Node, at: Vector2, strength := 1.0) -> void:
	var a := of(w)
	if a != null:
		a.call("_add_ripple", at, strength)


func _ready() -> void:
	add_to_group(GROUP)
	z_index = WAKE_Z
	_setup_ocean()
	_setup_haze()
	_scan_hulls()
	get_tree().node_added.connect(_on_node_added)
	# ShipLook（combat12）逐帧写 Sprite2D.offset 摇船，出图前也再写一遍：轮廓在同一时刻抄它
	RenderingServer.frame_pre_draw.connect(_sync_rims)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if RenderingServer.frame_pre_draw.is_connected(_sync_rims):
		RenderingServer.frame_pre_draw.disconnect(_sync_rims)


## 轮廓是船图的子节点，吃得到船图的变换，吃不到 offset：逐帧抄过来
func _sync_rims() -> void:
	for h in _hulls:
		if not _hull_ok(h):
			continue
		var spr := (h as Node).get_node_or_null("Sprite2D") as Sprite2D
		if spr == null:
			continue
		var rim := spr.get_node_or_null("FoeRim") as Sprite2D
		if rim != null:
			rim.offset = spr.offset
			rim.flip_h = spr.flip_h
			rim.flip_v = spr.flip_v


# ── 海面 ────────────────────────────────────────────────────────────

func _setup_ocean() -> void:
	var ocean := world.get_node_or_null("Ocean") as CanvasItem
	if ocean == null:
		return
	ocean.z_index = OCEAN_Z
	var mat := ocean.material as ShaderMaterial
	if mat == null or mat.shader == null or mat.shader.resource_path != SURFACE_SHADER:
		var sh := load(SURFACE_SHADER) as Shader
		if sh == null:
			return
		mat = ShaderMaterial.new()
		mat.shader = sh
		ocean.material = mat
	if mat.get_shader_parameter("fiber_tex") == null and ResourceLoader.exists(FIBER_TEX):
		mat.set_shader_parameter("fiber_tex", load(FIBER_TEX))
	_mat = mat


func _sea():
	if world != null and world.has_method("sea_state"):
		return world.call("sea_state")
	return null


func _process(delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	_clock += delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_scan_hulls()
		_scan_boardable()
	var wind := Vector2(0, 1)
	var force := 0.6
	var gust := 0.0
	var sea = _sea()
	if sea != null:
		var wt = sea.get("wind_to")
		if wt is Vector2 and (wt as Vector2).length() > 0.01:
			wind = (wt as Vector2).normalized()
		var spd := float(sea.get("wind_speed"))
		var mean := maxf(float(sea.get("wind_mean")), 1.0)
		force = clampf(spd / WIND_CAP, 0.0, 1.0)
		gust = clampf((spd - mean) / (mean * 0.14), -1.0, 1.0)
	_feed_surface(delta, wind, force, gust)
	_feed_pennants(wind, force)
	_tick_drama(delta)
	if _haze != null and is_instance_valid(_haze):
		var hm := _haze.material as ShaderMaterial
		if hm != null:
			hm.set_shader_parameter("focus", _haze_focus)


func _feed_surface(delta: float, wind: Vector2, force: float, gust: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("wind_angle", wind.angle())
	_mat.set_shader_parameter("wind_strength", force)
	_mat.set_shader_parameter("gust", gust)
	var hv: Array = []
	var hb: Array = []
	for h in _hulls:
		if hv.size() >= MAX_HULLS:
			break
		if not _hull_ok(h):
			continue
		var n2 := h as Node2D
		var v = n2.get("velocity")
		var spd := minf((v as Vector2).length(), 420.0) if v is Vector2 else 0.0
		var k := _hull_scale(n2)
		hv.append(Vector4(n2.position.x, n2.position.y, n2.rotation, spd))
		hb.append(Vector4(HULL_HALF.x * k, HULL_HALF.y * k, 0.0 if n2 == ship else 1.0, 0.0))
	while hv.size() < MAX_HULLS:
		hv.append(Vector4.ZERO)
		hb.append(Vector4.ZERO)
	_mat.set_shader_parameter("hulls", hv)
	_mat.set_shader_parameter("hulls_b", hb)
	_mat.set_shader_parameter("hull_count", mini(_hulls.size(), MAX_HULLS))
	# 涟漪
	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples = _ripples.filter(func(r): return float(r["age"]) < 1.6 + float(r["s"]) * 0.9)
	var rv: Array = []
	for r in _ripples:
		if rv.size() >= MAX_RIPPLES:
			break
		var p: Vector2 = r["p"]
		rv.append(Vector4(p.x, p.y, float(r["age"]), float(r["s"])))
	var nr := rv.size()
	while rv.size() < MAX_RIPPLES:
		rv.append(Vector4(0, 0, -1, 0))
	_mat.set_shader_parameter("ripples", rv)
	_mat.set_shader_parameter("ripple_count", nr)


func _add_ripple(at: Vector2, strength: float) -> void:
	_ripples.append({"p": at, "age": 0.0, "s": clampf(strength, 0.1, 2.5)})
	# 满了挤掉最老的
	while _ripples.size() > MAX_RIPPLES:
		_ripples.pop_front()


# ── 船：航迹、旗旒、轮廓 ───────────────────────────────────────────

func _hull_ok(h) -> bool:
	return h != null and is_instance_valid(h) and h is Node2D and not (h as Node).is_queued_for_deletion()


func _is_foe(n: Node) -> bool:
	return String(n.name).begins_with("PirateShip")


func _hull_scale(n: Node2D) -> float:
	var s := n.get_node_or_null("Sprite2D") as Sprite2D
	if s == null:
		return 1.0
	var base = n.get_meta(&"nk1_sprite_base_scale") if n.has_meta(&"nk1_sprite_base_scale") else s.scale
	return absf((base as Vector2).x) / 0.62


func _scan_hulls() -> void:
	# 离场的船：沉的（血量归零）原地一圈大涟漪
	var keep: Array = []
	for h in _hulls:
		if _hull_ok(h) and h.is_inside_tree():
			keep.append(h)
			_last_pos[h.get_instance_id()] = [(h as Node2D).position, _is_foe(h)]
	_hulls = keep
	if world == null:
		return
	for c in world.get_children():
		if not (c is Node2D):
			continue
		var is_ship: bool = c == ship
		if not is_ship and not _is_foe(c):
			continue
		if c in _hulls or c.is_queued_for_deletion():
			continue
		_hulls.append(c)
		_dress(c as Node2D, not is_ship)
		c.tree_exiting.connect(_on_hull_exit.bind(c.get_instance_id()), CONNECT_ONE_SHOT)


## 敌船够不够得着接舷：同顶匾「舷边可接」（WorldMap.boarding_approach_of）
func _scan_boardable() -> void:
	_boardable.clear()
	if world == null or not world.has_method("boarding_approach_of") or not _hull_ok(ship):
		return
	if bool(world.get("boarding")) or bool(world.get("resolved")):
		return
	for h in _hulls:
		if h == ship or not _hull_ok(h):
			continue
		var r = world.call("boarding_approach_of", ship, h)
		if r is Dictionary and bool((r as Dictionary).get("ok", false)):
			_boardable[h.get_instance_id()] = true


func _on_hull_exit(id: int) -> void:
	var o := instance_from_id(id) as Node2D
	if o == null:
		return
	# 夺船清血量后 queue_free，也是 hull_hp 0：夺来的船不算沉，看 grappled（被钩住的是夺走的）
	var hp := float(o.get("hull_hp")) if o.get("hull_hp") != null else 1.0
	var taken := bool(o.get("grappled")) if o.get("grappled") != null else false
	if hp <= 0.0 and not taken and is_inside_tree():
		_add_ripple(o.position, 2.0)


func _dress(h: Node2D, foe: bool) -> void:
	var k := _hull_scale(h)
	var wake: Node2D = SeaWake.new()
	wake.name = "Wake_%s" % h.name
	wake.hull = h
	wake.half_beam = HULL_HALF.x * k
	wake.half_len = HULL_HALF.y * k
	add_child(wake)
	if h.get_node_or_null("FoePennant") == null and h.get_node_or_null("OwnPennant") == null:
		var pen: Node2D = SeaPennant.new()
		pen.name = "FoePennant" if foe else "OwnPennant"
		pen.position = PENNANT_AT * k
		pen.z_index = 3
		if not foe:
			pen.fill = Color(0.90, 0.88, 0.80, 0.95)
			pen.trim = Color(0.24, 0.42, 0.40, 0.9)
			pen.length = 46.0
			pen.root_w = 8.0
		h.add_child(pen)
	if foe:
		_add_rim(h)


func _add_rim(h: Node2D) -> void:
	var spr := h.get_node_or_null("Sprite2D") as Sprite2D
	if spr == null or spr.get_node_or_null("FoeRim") != null:
		return
	var sh := load(RIM_SHADER) as Shader
	if sh == null:
		return
	var rim := Sprite2D.new()
	rim.name = "FoeRim"
	rim.texture = spr.texture
	rim.centered = spr.centered
	rim.offset = spr.offset
	rim.region_enabled = spr.region_enabled
	rim.region_rect = spr.region_rect
	rim.show_behind_parent = true
	var m := ShaderMaterial.new()
	m.shader = sh
	rim.material = m
	spr.add_child(rim)


func _feed_pennants(wind: Vector2, force: float) -> void:
	for h in _hulls:
		if not _hull_ok(h):
			continue
		for nm in ["FoePennant", "OwnPennant"]:
			var p := (h as Node).get_node_or_null(nm)
			if p != null:
				p.set("wind", wind)
				p.set("force", force)
		# 敌船换过精灵（apply_sprite）：轮廓跟着换；进了接舷够距，朱边一明一暗
		var spr := (h as Node).get_node_or_null("Sprite2D") as Sprite2D
		if spr != null:
			var rim := spr.get_node_or_null("FoeRim") as Sprite2D
			if rim != null:
				if rim.texture != spr.texture:
					rim.texture = spr.texture
				var pm := rim.material as ShaderMaterial
				if pm != null:
					var near := bool(_boardable.get(h.get_instance_id(), false))
					pm.set_shader_parameter("pulse", (0.5 + 0.5 * sin(_clock * 6.0)) if near else 0.0)


# ── 落水 ─────────────────────────────────────────────────────────

func _on_node_added(n: Node) -> void:
	if not (n is Node2D) or n.scene_file_path != SPLASH_SCENE:
		return
	if world == null or n.get_parent() != world:
		return
	var s := 1.0
	if n is CPUParticles2D:
		# 一排矢只溅小花（Cannonball.LIGHT_SPLASH_AMOUNT）：按粒子数定强弱
		s = clampf(float((n as CPUParticles2D).amount) / 30.0, 0.3, 1.2)
	var at := (n as Node2D).position
	_add_ripple(at, s)
	if s >= 0.8:
		_crown(at, s)


## 砲石落水的一圈白冠：水花往四面低低地炸开再落回
func _crown(at: Vector2, s: float) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 6
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = int(18 * s)
	p.lifetime = 0.55
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	p.emission_ring_radius = 6.0
	p.emission_ring_inner_radius = 2.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.radial_accel_min = -60.0
	p.radial_accel_max = -30.0
	p.initial_velocity_min = 60.0 * s
	p.initial_velocity_max = 120.0 * s
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	if ResourceLoader.exists("res://assets/fx/spray_drop.png"):
		p.texture = load("res://assets/fx/spray_drop.png")
	p.color = Color(0.9, 0.95, 0.97, 0.85)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = g
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ── 水气暗角 ─────────────────────────────────────────────────────

func _setup_haze() -> void:
	var sh := load(HAZE_SHADER) as Shader
	if sh == null or world == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "SeaHaze"
	layer.layer = 1
	_haze = ColorRect.new()
	_haze.name = "Haze"
	_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = sh
	_haze.material = m
	layer.add_child(_haze)
	# 与 HUD 同层（1），排在 HUD 那层之前 → 画在 HUD 之下
	world.add_child(layer)
	var hud_layer := world.get_node_or_null("CanvasLayer")
	if hud_layer != null:
		world.move_child(layer, hud_layer.get_index())


# ── 接舷 ─────────────────────────────────────────────────────────

func _boarding(flagship: Node2D, enemy: Node2D) -> void:
	if not (_hull_ok(flagship) and _hull_ok(enemy)):
		return
	var mid := (flagship.position + enemy.position) * 0.5
	_add_ripple(mid, 1.6)
	_add_ripple(mid + (enemy.position - flagship.position).orthogonal().normalized() * 60.0, 0.8)
	_throw_ropes(flagship, enemy)
	_flash(mid)
	_haze_focus = 1.0
	var tw := create_tween()
	tw.tween_interval(DRAMA_HOLD + DRAMA_IN)
	tw.tween_property(self, "_haze_focus", 0.0, DRAMA_OUT)
	if Kit.is_headless():
		return
	var cam := flagship.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if _drama_cam == null or not is_instance_valid(_drama_cam):
		_drama_cam = Camera2D.new()
		_drama_cam.name = "BoardingCam"
		world.add_child(_drama_cam)
	_drama_from_zoom = cam.zoom
	_drama_mid = mid
	_drama_cam.global_position = cam.get_screen_center_position()
	_drama_cam.zoom = cam.zoom
	_drama_cam.make_current()
	_drama_t = 0.0


func _tick_drama(delta: float) -> void:
	if _drama_t < 0.0 or _drama_cam == null or not is_instance_valid(_drama_cam):
		return
	_drama_t += delta
	var cam: Camera2D = ship.get_node_or_null("Camera2D") as Camera2D if _hull_ok(ship) else null
	var home := cam.get_screen_center_position() if cam != null else _drama_mid
	var k := 0.0
	if _drama_t < DRAMA_IN:
		k = _ease(_drama_t / DRAMA_IN)
	elif _drama_t < DRAMA_IN + DRAMA_HOLD:
		k = 1.0
	elif _drama_t < DRAMA_IN + DRAMA_HOLD + DRAMA_OUT:
		k = 1.0 - _ease((_drama_t - DRAMA_IN - DRAMA_HOLD) / DRAMA_OUT)
	else:
		_drama_t = -1.0
		if cam != null:
			cam.make_current()
		_drama_cam.queue_free()
		_drama_cam = null
		return
	var z := cam.zoom if cam != null else _drama_from_zoom
	_drama_cam.global_position = home.lerp(_drama_mid, k)
	_drama_cam.zoom = z * lerpf(1.0, DRAMA_ZOOM, k)
	# 震镜头（CombatFx.punch_camera 打在旗舰镜头 offset 上）照样传过来
	if cam != null:
		_drama_cam.offset = cam.offset


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## 钩缆：三根从本船舷边抛到敌船舷边，先飞出、再绷直，约两秒后收
func _throw_ropes(a: Node2D, b: Node2D) -> void:
	for r in _ropes:
		if is_instance_valid(r):
			r.queue_free()
	_ropes.clear()
	var ab := b.position - a.position
	var along := Vector2.UP.rotated(a.rotation)
	for i in 3:
		var off := (float(i) - 1.0) * 46.0
		var from := a.position + along * off + ab.normalized() * 30.0
		var to := b.position + along * off * 0.8 - ab.normalized() * 26.0
		var line := Line2D.new()
		line.width = 2.4
		line.default_color = Color(0.66, 0.53, 0.33, 0.95)
		line.antialiased = true
		line.z_index = 8
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		world.add_child(line)
		_ropes.append(line)
		var sag := ab.orthogonal().normalized() * (10.0 + 6.0 * float(i))
		var tw := line.create_tween()
		tw.tween_method(func(k: float) -> void: _rope_pts(line, from, to, sag, k), 0.0, 1.0, 0.22 + 0.06 * float(i))
		tw.tween_interval(1.9)
		tw.tween_property(line, "modulate:a", 0.0, 0.4)
		tw.tween_callback(line.queue_free)


static func _rope_pts(line: Line2D, from: Vector2, to: Vector2, sag: Vector2, k: float) -> void:
	if not is_instance_valid(line):
		return
	var pts := PackedVector2Array()
	var n := 10
	# 飞出段 k<1 时绳头在半路；绳越绷直垂度越小
	var head := from.lerp(to, k)
	for i in n + 1:
		var s := float(i) / float(n)
		var p := from.lerp(head, s)
		p += sag * sin(s * PI) * (1.0 - 0.6 * k)
		pts.append(p)
	line.points = pts


## 两船之间一闪暖光（加色）
func _flash(at: Vector2) -> void:
	if not ResourceLoader.exists("res://assets/fx/glow_warm.png"):
		return
	var s := Sprite2D.new()
	s.texture = load("res://assets/fx/glow_warm.png")
	s.position = at
	s.z_index = 9
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.modulate = Color(1.0, 0.86, 0.6, 0.0)
	s.scale = Vector2.ONE * 0.6
	world.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.75, 0.06)
	tw.parallel().tween_property(s, "scale", Vector2.ONE * 1.1, 0.3)
	tw.tween_property(s, "modulate:a", 0.0, 0.45)
	tw.tween_callback(s.queue_free)
