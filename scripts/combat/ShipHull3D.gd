extends Node
## 海战船身是一条三维泉州湾宋船（assets/ships/song_quanzhou.glb），不是一张贴图在转。
## 低斜俯相机固定在视口里，船体绕 Y 跟 CharacterBody2D.rotation 走，所以每一向看到的是
## 同一条船的另一面（舷弧、干舷、硬篷、甲板），不是把一张船图旋过去。
## Sprite2D 只负责把这张视口贴到海面上，并抵消船体航向，让透视跟相机一致。
## 敌我同一船壳，帆色由 Sail 材质区分。

const MESH_PATH := "res://assets/ships/song_quanzhou.glb"
const VIEW := 832
## 视口像素 → 世界像素。船在画面里约占 0.62 高时，832×0.40 ≈ 旧船图 512×0.62 的船长。
const VIS_SCALE := 0.78

@export var sail_crimson := false

var _vp: SubViewport
var _yaw: Node3D
var _cam: Camera3D
var _mast: Node3D
var _host: Node2D
var _sprite: Sprite2D
var _shudder := 0.0
var _ready_visual := false


func _ready() -> void:
	_host = get_parent() as Node2D
	process_priority = 20
	_build_view()
	call_deferred("_bind_sprite")


func _build_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.size = Vector2i(VIEW, VIEW)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.mesh_lod_threshold = 0.0
	_vp.msaa_3d = SubViewport.MSAA_DISABLED
	_vp.handle_input_locally = false
	add_child(_vp)

	var world := Node3D.new()
	world.name = "World"
	_vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.78)
	env.ambient_light_energy = 0.62
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.45
	sun.shadow_enabled = false
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_blend_splits = true
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 150, 0)
	fill.light_color = Color(0.62, 0.74, 0.86)
	fill.light_energy = 0.42
	world.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(12, 20, 0)
	rim.light_color = Color(1.0, 0.86, 0.7)
	rim.light_energy = 0.28
	world.add_child(rim)

	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	world.add_child(_yaw)

	var packed := load(MESH_PATH) as PackedScene
	if packed == null:
		push_error("ShipHull3D: 缺船模 %s" % MESH_PATH)
		return
	var rig := packed.instantiate()
	rig.name = "Hull"
	_yaw.add_child(rig)
	_paint_sails(rig)

	# 主桅顶近似（生成器：t=0.56，桅高 5.35，甲板约 0.4）
	_mast = Node3D.new()
	_mast.name = "MastTip"
	_mast.position = Vector3(0.0, 5.55, _z_of(0.56))
	_yaw.add_child(_mast)

	_cam = Camera3D.new()
	# 贴近海面的艏舷四分之三。28° 在这条低干舷船上仍是看甲板，所以用 17°。
	# 注视点抬到帆腹中部，船在方视口里居中。俯角见 SHIP_CAM。
	var look := Vector3(0.0, 2.35, 0.05)
	var elev := deg_to_rad(17.0)
	var az := deg_to_rad(-55.0)
	var dist := 22.5
	var dir := Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))
	_cam.fov = 40.0
	_cam.position = look + dir * dist
	world.add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(_cam.position, look, Vector3.UP)
	var fwd := -_cam.global_transform.basis.z
	var got := rad_to_deg(asin(clampf(-fwd.y, -1.0, 1.0)))
	print("SHIP_CAM elev_deg=%.1f dist=%.1f fov=%.1f az_deg=%.1f pos=%s" % [got, dist, _cam.fov, rad_to_deg(az), _cam.global_position])
	_ready_visual = true


func _z_of(t: float) -> float:
	var half := 4.8
	return half - t * 9.6


func _paint_sails(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat == null:
				continue
			var named := str(mat.resource_name)
			var sail := named == "Sail" or node.name == "Sails"
			if not sail:
				continue
			var sh := load("res://assets/shaders/song_sail.gdshader") as Shader
			if sh == null:
				push_warning("缺 song_sail.gdshader")
				continue
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("sail_color", Color(0.62, 0.08, 0.07, 1) if sail_crimson else Color(0.95, 0.89, 0.74, 1))
			mi.set_surface_override_material(i, sm)
	for c in node.get_children():
		_paint_sails(c)


func _bind_sprite() -> void:
	if _host == null or _vp == null:
		return
	_sprite = _host.get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	var tex := _vp.get_texture()
	_sprite.texture = tex
	_sprite.scale = Vector2(VIS_SCALE, VIS_SCALE)
	_host.set_meta(&"nk1_sprite_base_scale", _sprite.scale)
	for nm in ["HullWater", "HullLight"]:
		var layer := _host.get_node_or_null(nm) as Sprite2D
		if layer != null:
			layer.texture = tex
			layer.scale = _sprite.scale
	var _cam := _host.get_node_or_null("Camera2D") as Camera2D
	# 相机仍由旗舰用；这里不动


func _process(_delta: float) -> void:
	if not _ready_visual or _host == null or not is_instance_valid(_host):
		return
	if _sprite == null or not is_instance_valid(_sprite):
		_sprite = _host.get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		return
	var tex := _vp.get_texture()
	if _sprite.texture != tex:
		_sprite.texture = tex
	var lod := CombatSwitches.on(LOD_KEY)
	if lod != _lod_on:
		_lod_switch(lod)
	if not lod:
		# 2D 正角是顺时针；3D 绕 Y 正角从上方看是逆时针。抵消后船首仍朝节点的 -Y。
		_yaw.rotation.y = -_host.rotation
	var heel := float(_host.get_meta(&"nk1_heel", 0.0))
	_sprite.rotation = -_host.rotation + heel + _shudder
	if lod:
		_lod_frame()
	_aim_pennant()


func shudder(roll: float) -> void:
	_shudder = roll
	if has_meta(&"nk1_shudder_tw"):
		var old = get_meta(&"nk1_shudder_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := create_tween()
	set_meta(&"nk1_shudder_tw", tw)
	tw.tween_method(_set_shudder, roll, 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_shudder(v: float) -> void:
	_shudder = v


func grab_image() -> Image:
	if _vp == null:
		return null
	return _vp.get_texture().get_image()


func _aim_pennant() -> void:
	if _cam == null or _mast == null:
		return
	var world_pt: Vector3 = _mast.global_position
	if _cam.is_position_behind(world_pt):
		return
	var px := _cam.unproject_position(world_pt)
	var local_px := px - Vector2(VIEW, VIEW) * 0.5
	var heel := _host.rotation + _sprite.rotation
	var screen_off := Vector2(local_px.x * _sprite.scale.x, local_px.y * _sprite.scale.y)
	screen_off = screen_off.rotated(heel)
	var ship_local := screen_off.rotated(-_host.rotation)
	for nm in ["OwnPennant", "FoePennant"]:
		var pen := _host.get_node_or_null(nm) as Node2D
		if pen != null:
			pen.position = ship_local


# ── lane w54-perf：船身视口省着画（开关 hull_view_lod；关 = 上面那条每帧满幅重画的老路，逐字回旧）──────
## 这张三维图只随航向一个量变：相机、三盏灯、帆色都在 _build_view 里钉死，船模没有动画，
## 侧倾 / 中弹一震 / 损伤压扁都在 Sprite2D 上（二维），不进视口。所以：
##   · 航向比上回画的那张转过不到 _yaw_eps（船首在屏上挪不出 YAW_EPS_PX 个窗口像素的角）就不重画，沿用上一张；
##   · 船图连 CULL_MARGIN 边距出了画（或藏着）也不画，回到画里那一帧之前补上；
##   · 该画的那帧才把航向摆进视口、请视口只画这一回（UPDATE_ONCE），旗旒挂点跟着画出来的那张走；
##   · 开着时视口里换上去重顶点的船模（_welded_of）：船模导进来是一个三角形三个顶点各占一份，位置 / 法线 / UV / 顶点色
##     全同的合成一个、索引改指它，每个三角形三个角逐位不变、三角形次序不变，画出来逐像素一样，顶点着色少四成。
## 开关只在 _process 里逐帧读：开战时读到什么就是什么，探针半路拨也当帧生效（拨回关换回原船模、回每帧都画）。
const LOD_KEY := "hull_view_lod"
## 船首 / 船尾离转轴最远多少视口像素：半个船长 4.8 m，视口里约 50.8 px/m 是 244 px，
## 近相机那头透视再放大约 1.27 倍，取 320 偏大（阈角宁小勿大）
const HULL_REACH_PX := 320.0
## 船首在屏上挪不过这么多窗口像素就不重画（不到半个像素，看不出）
const YAW_EPS_PX := 0.4
## 阈角封顶（弧度，1°）：镜头再远、窗口再小，画面也不落后航向超过这么多
const YAW_EPS_MAX := 0.01745
## 出画判定的边距（画布像素）：船与镜头一帧挪不了这么远，回到画里之前就已画好
const CULL_MARGIN := 96.0

var _lod_on := false
var _lod_drawn := false
var _lod_yaw := 0.0
var _lod_eps := YAW_EPS_MAX
var _lod_renders := 0
## [MeshInstance3D, 原网格]：拨回关时换回去
var _lod_meshes: Array = []
## 原网格 → 去重顶点的网格；同一进程所有船共用一份（头一条船开画时现做，约百来毫秒）
static var _welded := {}


## 开关拨了（开战时读到、或探针半路拨）：开 = 视口停画、等下一张该画的、换上去重顶点的船模；关 = 回每帧都画、换回原船模
func _lod_switch(on: bool) -> void:
	_lod_on = on
	_lod_drawn = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if on else SubViewport.UPDATE_ALWAYS
	if _lod_meshes.is_empty() and _yaw != null:
		for mi in _yaw.find_children("*", "MeshInstance3D", true, false):
			_lod_meshes.append([mi, (mi as MeshInstance3D).mesh])
	for pair in _lod_meshes:
		var mi := pair[0] as MeshInstance3D
		var orig := pair[1] as Mesh
		if is_instance_valid(mi) and orig != null:
			mi.mesh = _welded_of(orig) if on else orig


## 开关开：这一帧要不要重画三维船身；要画就把这一刻的航向摆上、请视口画一回
func _lod_frame() -> void:
	var xf := _sprite.get_global_transform_with_canvas()
	var port := _sprite.get_viewport()
	if port == null or not _sprite.is_visible_in_tree() or not _in_view(xf, port):
		return
	var yaw := -_host.rotation
	_lod_eps = _yaw_eps(xf, port)
	if _lod_drawn and absf(angle_difference(_lod_yaw, yaw)) < _lod_eps:
		return
	_yaw.rotation.y = yaw
	_lod_yaw = yaw
	_lod_drawn = true
	_lod_renders += 1
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## 船图（整张视口贴图那么大，连边距）落不落在画里
func _in_view(xf: Transform2D, port: Viewport) -> bool:
	var h := Vector2(VIEW, VIEW) * 0.5
	var box := Rect2(xf * -h, Vector2.ZERO).expand(xf * h).expand(xf * Vector2(h.x, -h.y)).expand(xf * Vector2(-h.x, h.y))
	return port.get_visible_rect().grow(CULL_MARGIN).intersects(box)


## 阈角：屏上一个视口像素合几个窗口像素（船图缩放 × 镜头 × 窗口拉伸），折成船首挪 YAW_EPS_PX 的转角
func _yaw_eps(xf: Transform2D, port: Viewport) -> float:
	var k := maxf(xf.x.length(), xf.y.length()) * port.get_final_transform().x.length()
	return minf(YAW_EPS_MAX, YAW_EPS_PX / maxf(0.001, HULL_REACH_PX * k))


## 探针 / 验收读：省着画开没开、请视口画过几回、画出来那张是哪个航向、上回在画里时算的阈角
func lod_state() -> Dictionary:
	return {"on": _lod_on, "renders": _lod_renders, "drawn": _lod_drawn, "yaw": _lod_yaw, "eps": _lod_eps}


## 去重顶点的船模（按原网格缓存）。只认三角形、没有混合形状的面；有别的样子就原样还回去，不冒险
static func _welded_of(m: Mesh) -> Mesh:
	if _welded.has(m):
		return _welded[m]
	var out: Mesh = _weld(m)
	_welded[m] = out
	return out


static func _weld(m: Mesh) -> Mesh:
	if m == null or m.get_blend_shape_count() > 0:
		return m
	for si in m.get_surface_count():
		if m.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			return m
		var probe := m.surface_get_arrays(si)
		for t in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			if probe[t] != null:
				return m
	var out := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# 判等的几样：喂进着色的位置、法线、两套 UV、顶点色（切线不进：这几样材质都没有法线贴图）
		var keys: Array = []
		for t in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			var a = arr[t]
			if a != null and a.size() == pos.size():
				keys.append(a)
		var seen := {}
		var remap := PackedInt32Array()
		remap.resize(pos.size())
		var keep := PackedInt32Array()
		for vi in pos.size():
			var k: Array = [pos[vi]]
			for a in keys:
				k.append(a[vi])
			var h = seen.get(k)
			if h == null:
				h = keep.size()
				seen[k] = h
				keep.append(vi)
			remap[vi] = int(h)
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		for t in Mesh.ARRAY_MAX:
			if t == Mesh.ARRAY_INDEX or arr[t] == null:
				continue
			na[t] = _pick(arr[t], keep, pos.size())
		var nidx := PackedInt32Array()
		nidx.resize(idx.size() if idx.size() > 0 else pos.size())
		for q in nidx.size():
			nidx[q] = remap[idx[q] if idx.size() > 0 else q]
		na[Mesh.ARRAY_INDEX] = nidx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		out.surface_set_material(si, m.surface_get_material(si))
	if m is ArrayMesh:
		out.shadow_mesh = (m as ArrayMesh).shadow_mesh
	return out


## 顶点数组按 keep 里的顶点号抽一份（每顶点多格的——切线 4 格、骨骼 4 格——成组抽）
static func _pick(src: Variant, keep: PackedInt32Array, n: int) -> Variant:
	var per: int = maxi(1, src.size() / maxi(1, n))
	var out: Variant = src.duplicate()
	out.resize(keep.size() * per)
	for i in keep.size():
		for c in per:
			out[i * per + c] = src[keep[i] * per + c]
	return out
