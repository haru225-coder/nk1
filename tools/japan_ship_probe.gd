extends SceneTree
## 日本准构造船朝向探针。同一条网格绕 Y，十六向各存一张。
## 镜头在水平面以上约 18°，斜侧三分，能看见舷弧、圆底和低干舷。
## 船贴在游戏海面着色器上。每张都把整条船（桅头、帆脚、壳、桨叶）收进画面。
## DISPLAY=:2 godot --path . -s res://tools/japan_ship_probe.gd

const ShotGate := preload("res://tools/shot_gate.gd")

var _fails: Array = []
const OUT := "/tmp/nk1-combat-wave3/ship-japan16"
const MERCHANT := "res://assets/ships/japan_quasi.glb"
const WAR := "res://assets/ships/japan_quasi_war.glb"
const VIEW := 960
const ELEV_DEG := 18.0
const AZ_DEG := 75.0
const FOV := 28.0

var _vp: SubViewport
var _yaw: Node3D
var _cam: Camera3D
var _merchant: Node3D
var _war: Node3D
var _sprite: Sprite2D
var _cam2d: Camera2D
var _crop_notes: PackedStringArray = PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ShotGate.frame_pressure(self)
	var why := ShotGate.no_render_reason()
	if why != "":
		print("JAPAN_SHIP_FAIL ", why)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT + "/angles/merchant")
	DirAccess.make_dir_recursive_absolute(OUT + "/angles/war")

	var world2 := Node2D.new()
	world2.name = "Sea"
	root.add_child(world2)
	var sea := ColorRect.new()
	sea.position = Vector2(-2400, -1600)
	sea.size = Vector2(4800, 3200)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/sea_surface.gdshader")
	mat.set_shader_parameter("wind_strength", 0.48)
	mat.set_shader_parameter("shallows", 0.18)
	sea.material = mat
	world2.add_child(sea)

	_cam2d = Camera2D.new()
	_cam2d.position = Vector2.ZERO
	_cam2d.zoom = Vector2(1.0, 1.0)
	_cam2d.enabled = true
	world2.add_child(_cam2d)
	_cam2d.make_current()

	_build_view(world2)
	_hide_shadow(_merchant)
	_hide_shadow(_war)
	# 视口是正方形。缩到窗口高度里面，避免窗口把桅头切掉。
	_sprite = Sprite2D.new()
	_sprite.texture = _vp.get_texture()
	_sprite.scale = Vector2(0.70, 0.70)
	_sprite.rotation = 0.0
	world2.add_child(_sprite)

	for _i in 8:
		await process_frame
	var _back := _eye()
	print("CAM_ELEV_DEG ", rad_to_deg(asin(_back.normalized().y)))

	_isolate()
	_show_merchant()
	_yaw.rotation.y = 0.40
	await _ensure_fit("close_merchant")
	_shot(OUT + "/close_merchant.png")
	_note_crop("close_merchant")

	_show_war()
	_yaw.rotation.y = 0.28
	await _ensure_fit("close_war")
	_shot(OUT + "/close_war.png")
	_note_crop("close_war")

	# 对侧：远舷小叶应仍挂在远舷缘外，不能飘在空槽上。
	_yaw.rotation.y = 0.28 + PI
	await _ensure_fit("far_war")
	_shot(OUT + "/far_war.png")
	_note_crop("far_war")

	var merchant_n := await _yaw_set("merchant", OUT + "/angles/merchant")
	var war_n := await _yaw_set("war", OUT + "/angles/war")
	print("YAW_DISTINCT merchant ", merchant_n, "/16")
	print("YAW_DISTINCT war ", war_n, "/16")
	if merchant_n < 16 or war_n < 16:
		_fails.append("真失败：YAW_DISTINCT merchant %d/16 / war %d/16 不足（yaw 重影）" % [merchant_n, war_n])

	_merchant.visible = true
	_war.visible = true
	_merchant.position = Vector3(-5.4, 0.0, 0.35)
	_merchant.rotation.y = 0.22
	_war.position = Vector3(5.1, 0.0, -0.45)
	_war.rotation.y = -0.08
	_yaw.rotation.y = 0.18
	await _ensure_fit("wide")
	_shot(OUT + "/wide.png")
	_note_crop("wide")

	for note in _crop_notes:
		print("CROP_NOTE ", note)

	# lane w53-11 八轮：收尾按 ship_exquisite 同款——空视口 / 空图 / 挂不进船都记账进 _fails，不再静默绿
	if _fails.is_empty():
		print("JAPAN_SHIP_OK")
		quit(0)
	else:
		for f in _fails:
			print("  ✗ ", f)
		print("JAPAN_SHIP_FAIL %d" % _fails.size())
		quit(1)


func _yaw_set(which: String, dir: String) -> int:
	if which == "merchant":
		_show_merchant()
	else:
		_show_war()
	var seen := {}
	for i in 16:
		_yaw.rotation.y = float(i) * TAU / 16.0
		var tag := "%s_%02d" % [which, i]
		await _ensure_fit(tag)
		var path := dir + "/angle_%02d.png" % i
		_shot(path)
		_note_crop(tag)
		var img := _vp.get_texture().get_image()
		var tiny := img.duplicate()
		tiny.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var key: String = tiny.get_data().hex_encode()
		if seen.has(key):
			print("YAW_DUP ", which, " ", i)
		seen[key] = true
	return seen.size()



func _eye() -> Vector3:
	var elev := deg_to_rad(ELEV_DEG)
	var az := deg_to_rad(AZ_DEG)
	return Vector3(sin(az) * cos(elev), sin(elev), cos(az) * cos(elev))


func _isolate() -> void:
	_merchant.position = Vector3.ZERO
	_war.position = Vector3.ZERO
	_merchant.rotation = Vector3.ZERO
	_war.rotation = Vector3.ZERO


func _build_view(host: Node) -> void:
	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.size = Vector2i(VIEW, VIEW)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = SubViewport.MSAA_2X
	_vp.handle_input_locally = false
	host.add_child(_vp)

	var world := Node3D.new()
	_vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.72, 0.80)
	env.ambient_light_energy = 0.70
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22, 48, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.4
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-8, 210, 0)
	fill.light_color = Color(0.70, 0.80, 0.90)
	fill.light_energy = 0.62
	world.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(8, 18, 0)
	rim.light_color = Color(1.0, 0.86, 0.70)
	rim.light_energy = 0.35
	world.add_child(rim)

	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	world.add_child(_yaw)

	var mp := load(MERCHANT) as PackedScene
	if mp == null:
		# lane w53-11 八轮：打包不出时不能只打印就走——记账入 _fails，由收尾 FAIL k 判
		_fails.append("真失败：load %s 打包不出" % MERCHANT)
	else:
		_merchant = mp.instantiate()
		_merchant.name = "Merchant"
		_yaw.add_child(_merchant)
		_paint(_merchant)

	var wp := load(WAR) as PackedScene
	if wp == null:
		_fails.append("真失败：load %s 打包不出" % WAR)
	else:
		_war = wp.instantiate()
		_war.name = "War"
		_yaw.add_child(_war)
		_paint(_war)
		_war.visible = false

	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true


func _paint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat == null:
				continue
			var named := str(mat.resource_name)
			if named == "Sail" or node.name == "Sails":
				var sh := load("res://assets/shaders/japan_mushiro.gdshader") as Shader
				var sm := ShaderMaterial.new()
				sm.shader = sh
				sm.set_shader_parameter("sail_color", Color(0.86, 0.70, 0.42, 1))
				mi.set_surface_override_material(i, sm)
			elif mat is StandardMaterial3D:
				var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.vertex_color_use_as_albedo = true
				mi.set_surface_override_material(i, sm)
	for c in node.get_children():
		_paint(c)


func _hide_shadow(node: Node) -> void:
	if str(node.name) == "Shadow":
		node.visible = false
	for c in node.get_children():
		_hide_shadow(c)


func _show_merchant() -> void:
	_isolate()
	_merchant.visible = true
	_war.visible = false


func _show_war() -> void:
	_isolate()
	_merchant.visible = false
	_war.visible = true


func _visible_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for ship in [_merchant, _war]:
		if ship == null or not (ship as Node3D).visible:
			continue
		_collect_points(ship, pts)
	return pts


func _collect_points(n: Node, pts: PackedVector3Array) -> void:
	if not n.visible:
		return
	if n is GeometryInstance3D and str(n.name) != "Shadow":
		var gi := n as GeometryInstance3D
		var xf := gi.global_transform
		var mesh: Mesh = gi.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					pts.append(xf * v)
	for c in n.get_children():
		_collect_points(c, pts)


func _frame_points(pts: PackedVector3Array, margin: float) -> void:
	var look := Vector3.ZERO
	for p in pts:
		look += p
	look /= float(maxi(pts.size(), 1))
	var back := _eye().normalized()
	var world_up := Vector3.UP
	var right := world_up.cross(back)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := back.cross(right).normalized()
	var half := deg_to_rad(FOV) * 0.5
	var tan_h := tan(half)
	var dist := 1.0
	for p in pts:
		var q := p - look
		var cx := q.dot(right)
		var cy := q.dot(up)
		var cz := q.dot(back)
		dist = max(dist, abs(cx) / tan_h + cz)
		dist = max(dist, abs(cy) / tan_h + cz)
	dist *= margin
	_cam.fov = FOV
	_cam.look_at_from_position(look + back * dist, look, Vector3.UP)


func _ensure_fit(tag: String) -> void:
	for attempt in 5:
		for _k in 2:
			await process_frame
		var pts := _visible_points()
		if pts.is_empty():
			print("FRAME_EMPTY ", tag)
			return
		_frame_points(pts, 1.10 + float(attempt) * 0.07)
		for _k in 3:
			await process_frame
		var img := _vp.get_texture().get_image()
		var r := img.get_used_rect()
		var pad := 16
		var ok := r.position.x >= pad and r.position.y >= pad and r.end.x <= VIEW - pad and r.end.y <= VIEW - pad
		print("FRAME ", tag, " attempt ", attempt, " ", r, " ok ", ok)
		if ok:
			return
	print("FRAME_CROP ", tag)


func _note_crop(tag: String) -> void:
	var img := _vp.get_texture().get_image()
	var r := img.get_used_rect()
	var pad := 16
	var cropped := r.position.x < pad or r.position.y < pad or r.end.x > VIEW - pad or r.end.y > VIEW - pad
	var note := "%s used=%s crop=%s" % [tag, r, cropped]
	_crop_notes.append(note)


func _shot(path: String) -> void:
	# lane w53-11 八轮：走 ShotGate.grab 口径——空视口 / 空图记账进 _fails，不再静默绿（跟 ship_exquisite 同型）
	var img := ShotGate.grab(root, path.get_file(), _fails)
	if img == null:
		return
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
