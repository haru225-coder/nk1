extends SceneTree
## 大食缝合船：游戏海面上的低斜视角。不进编辑器默认视口，不改宋船。
## 视线在水平面以上约 18°，接近正舷看低干舷；甲板可露一点，但不能是俯视甲板。
## DISPLAY=:2 godot --path . -s res://tools/ship_dashi_probe.gd
## 截图：/tmp/nk1-combat-wave3/ship-dashi17/

const ShotGate := preload("res://tools/shot_gate.gd")
const OUT := "/tmp/nk1-combat-wave3/ship-dashi17"
const MERCHANT := "res://assets/ships/dashi_sewn_merchant.glb"
const ARMED := "res://assets/ships/dashi_sewn_armed.glb"
const FACINGS := 16

var _vp: SubViewport
var _yaw: Node3D
var _cam: Camera3D
var _hull: Node3D
var _sprite: Sprite2D
var _cam2: Camera2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ShotGate.frame_pressure(self)
	var why := ShotGate.no_render_reason()
	if why != "":
		print("DASHI_SHIP_FAIL ", why)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT + "/angles")

	var world := Node2D.new()
	world.name = "Sea"
	root.add_child(world)
	var sea := ColorRect.new()
	sea.position = Vector2(-2800, -1800)
	sea.size = Vector2(5600, 3600)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/sea_surface.gdshader")
	mat.set_shader_parameter("wind_strength", 0.55)
	mat.set_shader_parameter("wind_angle", 0.7)
	mat.set_shader_parameter("wave_speed", 0.0)
	mat.set_shader_parameter("shallows", 0.18)
	mat.set_shader_parameter("foam_amount", 0.42)
	mat.set_shader_parameter("stroke_amount", 0.62)
	mat.set_shader_parameter("glint_amount", 0.20)
	sea.material = mat
	world.add_child(sea)

	_cam2 = Camera2D.new()
	_cam2.name = "ShotCam"
	_cam2.position = Vector2.ZERO
	_cam2.zoom = Vector2(1.0, 1.0)
	_cam2.enabled = true
	world.add_child(_cam2)
	_cam2.make_current()

	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.size = Vector2i(1280, 1280)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = SubViewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.handle_input_locally = false
	world.add_child(_vp)

	var world3 := Node3D.new()
	_vp.add_child(world3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.72, 0.80)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -32, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	world3.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 150, 0)
	fill.light_color = Color(0.62, 0.74, 0.86)
	fill.light_energy = 0.55
	world3.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(12, 28, 0)
	rim.light_color = Color(1.0, 0.86, 0.70)
	rim.light_energy = 0.38
	world3.add_child(rim)

	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	world3.add_child(_yaw)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	world3.add_child(_cam)
	_cam.current = true
	_cam.near = 1.0
	_cam.far = 90.0

	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.texture = _vp.get_texture()
	_sprite.position = Vector2(0, 8)
	world.add_child(_sprite)

	for _i in 4:
		await process_frame

	# 近景商船：接近正舷的斜向。视线 18°，瞄准水线上方干舷，侧看低干舷，不是俯视甲板。
	_sprite.scale = Vector2(0.62, 0.62)
	_clear_ships()
	_spawn(MERCHANT, Vector3.ZERO, 0.0)
	_frame_elev(18.5, 98.0, 18.0, 0.12, Vector3(0.05, 0.28, 0.10), 34.0)
	for _i in 8:
		await process_frame
	_shot(OUT + "/close_merchant.png")

	# 近景护舶：左舷接近正舷，齐胸栏杆、圆盾、矛尖与尾侧舵桨朝镜头。同一俯角。
	_clear_ships()
	_spawn(ARMED, Vector3.ZERO, 0.0)
	_frame_elev(18.5, 262.0, 18.0, -0.10, Vector3(-0.05, 0.32, 0.05), 34.0)
	for _i in 8:
		await process_frame
	_shot(OUT + "/close_war.png")

	# 远景：商船和护舶都是整船，同一低俯角，中间留出海面。
	_clear_ships()
	_spawn(MERCHANT, Vector3(-9.0, 0.0, 1.6), 0.35)
	_spawn(ARMED, Vector3(9.2, 0.0, -1.8), 0.85)
	_sprite.scale = Vector2(0.72, 0.72)
	_frame_elev(48.0, 108.0, 18.0, 0.0, Vector3(0.0, 0.35, 0.0), 30.0)
	for _i in 8:
		await process_frame
	_shot(OUT + "/wide.png")

	# 十六向：相机固定，只转商船。哈希取三维视口（没有海面），证明是船在转。
	_clear_ships()
	_spawn(MERCHANT, Vector3.ZERO, 0.0)
	_sprite.scale = Vector2(0.56, 0.56)
	_frame_elev(20.0, 102.0, 18.0, 0.0, Vector3(0.0, 0.30, 0.0), 32.0)
	var seen := {}
	for i in FACINGS:
		_yaw.rotation.y = float(i) * TAU / float(FACINGS)
		for _k in 3:
			await process_frame
		var mesh_img := _vp.get_texture().get_image()
		var tiny := mesh_img.duplicate()
		tiny.resize(48, 48, Image.INTERPOLATE_BILINEAR)
		var key: String = tiny.get_data().hex_encode()
		seen[key] = true
		_shot(OUT + "/angles/angle_%02d.png" % i)
		print("YAW_HASH ", i, " ", key.md5_text())

	print("YAW_DISTINCT ", seen.size(), "/16")
	if seen.size() != FACINGS:
		print("DASHI_SHIP_FAIL yaw hashes not distinct")
		quit(1)
		return
	print("DASHI_SHIP_OK")
	quit(0)


func _clear_ships() -> void:
	for n in _yaw.get_children():
		n.free()
	_hull = null


func _spawn(path: String, pos: Vector3, yaw: float) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("DASHI_SHIP_FAIL missing ", path)
		return
	var hull := packed.instantiate()
	hull.name = "Hull"
	hull.position = pos
	hull.rotation.y = yaw
	_paint(hull)
	_yaw.add_child(hull)
	_hull = hull


func _paint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, depth_draw_opaque;
varying vec4 vcol;
varying vec3 wpos;
void vertex() {
	vcol = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y < -0.02 && vcol.a > 0.85) {
		discard;
	}
	ALBEDO = vcol.rgb;
	ALPHA = vcol.a;
	ROUGHNESS = 0.86;
	METALLIC = 0.0;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = sh
		# 椰索贴在板面上。关深度，否则细绳被壳吃掉。
		# 不打光：三像素宽的圆管一打光就只剩一条暗棱，拧花的两色读不出来。
		if str(mi.name).contains("Stitch"):
			mat.render_priority = 100
			sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec4 vcol;
varying vec3 wpos;
void vertex() {
	vcol = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y < -0.02 && vcol.a > 0.85) {
		discard;
	}
	ALBEDO = vcol.rgb;
	ALPHA = vcol.a;
}
"""
			mat.shader = sh
		elif str(mi.name).contains("Sail"):
			# 帆只留顶点色上的一块肚子。Burley 加三盏灯会把这块色冲成白板。
			sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec4 vcol;
varying vec3 wpos;
void vertex() {
	vcol = COLOR;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y < -0.02 && vcol.a > 0.85) {
		discard;
	}
	ALBEDO = vcol.rgb;
	ALPHA = vcol.a;
}
"""
			mat.shader = sh
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		_paint(c)


func _frame(dist: float, dir: Vector3, yaw: float, look := Vector3(0.0, 1.25, 0.0), fov := 30.0) -> void:
	_yaw.rotation.y = yaw
	_cam.fov = fov
	_cam.look_at_from_position(look + dir.normalized() * dist, look, Vector3.UP)


func _frame_elev(dist: float, azimuth_deg: float, elev_deg: float, yaw: float, look: Vector3, fov: float) -> void:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elev_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	var cam_pos := look + dir.normalized() * dist
	var elev := rad_to_deg(atan2(dir.y, Vector2(dir.x, dir.z).length()))
	var to_wl := cam_pos - Vector3(look.x, 0.0, look.z)
	var wl := rad_to_deg(atan2(to_wl.y, Vector2(to_wl.x, to_wl.z).length()))
	print("CAM elev_deg=", snapped(elev, 0.1), " waterline_elev=", snapped(wl, 0.1), " az=", azimuth_deg, " dist=", dist, " fov=", fov, " look_y=", look.y)
	_frame(dist, dir, yaw, look, fov)


func _shot(path: String) -> void:
	var mesh := _vp.get_texture().get_image()
	if mesh != null:
		var w := mesh.get_width()
		var h := mesh.get_height()
		var minx := w
		var miny := h
		var maxx := 0
		var maxy := 0
		var step := 3
		for y in range(0, h, step):
			for x in range(0, w, step):
				if mesh.get_pixel(x, y).a > 0.2:
					if x < minx:
						minx = x
					if y < miny:
						miny = y
					if x > maxx:
						maxx = x
					if y > maxy:
						maxy = y
		print("MESH_BOUNDS ", path.get_file(), " ", minx, ",", miny, " ", maxx, ",", maxy, " / ", w, "x", h)
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT FAIL empty ", path)
		return
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
