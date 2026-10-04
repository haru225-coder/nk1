extends SceneTree
## 占城船朝向探针。海面用游戏 sea_surface（WorldMap/Ocean 那一套）。
## 镜头在水平面以上 18°，贴近右舷，能看见舷侧、舷弧、低干舷和直立的帆面。不是俯视图标。
## 网格绕 Y 转。精灵不跟着转：跟着转会把帆从甲板上方旋到船底外面。
## NK1_SHOT_DIR=/tmp/nk1-combat-wave3 DISPLAY=:2 godot --path . -s res://tools/shot_champa_ship.gd
## 图落 $NK1_SHOT_DIR/ship-champa15/

const ShotGate := preload("res://tools/shot_gate.gd")
const MESH := "res://assets/ships/champa.glb"
const SEA := "res://assets/shaders/sea_surface.gdshader"
const SAIL := "res://assets/shaders/champa_sail.gdshader"
const FIBER := "res://assets/fx/noise_fiber.png"
const FACINGS := 16
const VIEW := Vector2i(1280, 720)

var _fails: Array = []
## 仰角 18°。几乎正对右舷，只向船尾偏 14°，好看见舷侧、舷弧和直立的帆面。
## 再偏到船尾、再拉远，帆会被看成平铺在甲板上的一块横板。
const CAM_ELEV_DEG := 18.0
const CAM_AZ_DEG := 22.0


class Rig:
	var vp: SubViewport
	var yaw: Node3D
	var sprite: Sprite2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ShotGate.frame_pressure(self)
	var why := ShotGate.no_render_reason()
	if why != "":
		print("CHAMPA_SHOT_FAIL ", why)
		quit(1)
		return
	var out := ShotGate.out_dir("ship-champa15")
	DirAccess.make_dir_recursive_absolute(out + "/angles")
	root.size = Vector2i(1280, 720)

	var world := Node2D.new()
	world.name = "Sea"
	root.add_child(world)

	var sea := ColorRect.new()
	sea.position = Vector2(-6000, -4500)
	sea.size = Vector2(12000, 9000)
	sea.material = _sea_mat()
	world.add_child(sea)

	var cam := Camera2D.new()
	cam.name = "ShotCam"
	cam.enabled = true
	world.add_child(cam)
	cam.make_current()

	var cam_dir := _cam_dir()
	var elev := rad_to_deg(atan2(cam_dir.y, Vector2(cam_dir.x, cam_dir.z).length()))
	print("CAM_ELEV_DEG %.1f" % elev)
	# 近。窄焦距拉远会把 18° 拍成平面图。商船壳长，战舟再近一截，两艘都是整船入画。
	var merchant := _rig("Merchant", 15.2, Vector3(0.0, 0.90, 0.0), 32.0)
	var war := _rig("War", 11.2, Vector3(0.0, 0.55, 0.0), 32.0)
	world.add_child(merchant.vp)
	world.add_child(war.vp)
	world.add_child(merchant.sprite)
	world.add_child(war.sprite)
	merchant.sprite.texture = merchant.vp.get_texture()
	war.sprite.texture = war.vp.get_texture()

	await _settle(8)

	# 近景商船：18° 侧视，整船、两张直立帆、舷侧和舷弧一起入画
	_show_only(merchant, war)
	_place(merchant, 0.0, Vector2(0, 0), 1.0)
	cam.position = Vector2(0, 0)
	cam.zoom = Vector2(1.22, 1.22)
	await _settle(6)
	_save_root(out + "/close_merchant.png")

	# 近景战舟：短壳、一列桨、一面直立帆、侧舵。整船，不是俯视图标。
	_show_only(war, merchant)
	_place(war, 0.0, Vector2(0, 0), 1.0)
	cam.position = Vector2(0, 0)
	cam.zoom = Vector2(1.22, 1.22)
	await _settle(6)
	_save_root(out + "/close_war.png")

	# 十六向：只转三维船的 yaw，精灵不转，帆始终在甲板上方。哈希取视口里的网格，不取海面。
	# 机位、距离、仰角、2D 缩放都与近景商船相同。航向变了不许把相机拉远。
	_show_only(merchant, war)
	war.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	cam.zoom = Vector2(1.22, 1.22)
	cam.position = Vector2(0, 0)
	var hashes: PackedStringArray = PackedStringArray()
	for i in FACINGS:
		var heading := float(i) * TAU / float(FACINGS)
		_place(merchant, heading, Vector2(0, 0), 1.0)
		await _settle(4)
		var img := merchant.vp.get_texture().get_image()
		if img == null or img.is_empty():
			print("CHAMPA_SHOT_FAIL empty viewport ", i)
			quit(1)
			return
		var digest := _md5(img)
		# 视口若没跟上 yaw，再等几帧
		if i > 0 and digest == hashes[i - 1]:
			await _settle(8)
			img = merchant.vp.get_texture().get_image()
			digest = _md5(img)
		hashes.append(digest)
		_save_root(out + "/angles/angle_%02d.png" % i)
		print("YAW_HASH %02d %s" % [i, digest])
	var uniq := {}
	for h in hashes:
		uniq[h] = true
	print("YAW_DISTINCT ", uniq.size(), "/", FACINGS)
	if uniq.size() != FACINGS:
		_fails.append("真失败：YAW_DISTINCT %d/16 不足（十六向有重影）" % uniq.size())

	# 宽景：航向差开，帆面都朝着镜头，而且都在甲板上方。不把战舟旋到帆掉到船底下。
	war.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	merchant.sprite.visible = true
	war.sprite.visible = true
	_place(merchant, 0.08, Vector2(-280, 8), 0.42)
	_place(war, -0.15, Vector2(290, 4), 0.46)
	cam.zoom = Vector2(1.0, 1.0)
	cam.position = Vector2(0, 4)
	await _settle(6)
	_save_root(out + "/wide.png")

	# lane w53-11 八轮：收尾按 ship_exquisite 同款——空视口 / 挂不进船都记账进 _fails，不再静默绿
	if _fails.is_empty():
		print("CHAMPA_SHOT_OK ", out)
		quit(0)
	else:
		for f in _fails:
			print("  ✗ ", f)
		print("CHAMPA_SHOT_FAIL %d" % _fails.size())
		quit(1)


func _show_only(on: Rig, off: Rig) -> void:
	on.sprite.visible = true
	off.sprite.visible = false
	on.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	off.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _place(rig: Rig, heading: float, pos: Vector2, scl: float) -> void:
	# 航向只绕 Y 转网格。精灵保持正放：帆在视口上方就是画面上方。
	# 若再把精灵转 -heading，半圈以后帆会落到船壳下面，像一块脱离的布。
	rig.yaw.rotation = Vector3(0.0, -heading, 0.0)
	rig.sprite.rotation = 0.0
	rig.sprite.position = pos
	rig.sprite.scale = Vector2(scl, scl)


func _rig(which: String, dist: float, look: Vector3, fov_deg: float) -> Rig:
	var rig := Rig.new()
	var vp := SubViewport.new()
	vp.name = which + "Vp"
	vp.size = VIEW
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = SubViewport.MSAA_4X
	vp.mesh_lod_threshold = 0.0
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.handle_input_locally = false
	rig.vp = vp

	var world := Node3D.new()
	world.name = "World"
	vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.78)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.45
	sun.shadow_enabled = false
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 150, 0)
	fill.light_color = Color(0.62, 0.74, 0.86)
	fill.light_energy = 0.42
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(12, 20, 0)
	rim.light_color = Color(1.0, 0.86, 0.70)
	rim.light_energy = 0.28
	world.add_child(rim)

	var yaw := Node3D.new()
	yaw.name = "Yaw"
	world.add_child(yaw)
	rig.yaw = yaw

	var packed := load(MESH) as PackedScene
	if packed == null:
		# lane w53-11 八轮：挂不进船时不能只 push_error 就走——记账入 _fails，由收尾 FAIL k 判
		_fails.append("真失败：load %s 打包不出（缺占城船模）" % MESH)
		push_error("缺占城船模")
		return rig
	var hull := packed.instantiate()
	hull.name = "Hull"
	yaw.add_child(hull)
	_paint(hull)
	var keep := _find(hull, which)
	var drop_name := "War" if which == "Merchant" else "Merchant"
	var drop := _find(hull, drop_name)
	if keep != null:
		keep.visible = true
	if drop != null:
		drop.visible = false

	var cam := Camera3D.new()
	cam.fov = fov_deg
	var dir := _cam_dir()
	cam.position = look + dir * dist
	world.add_child(cam)
	cam.current = true
	cam.look_at_from_position(cam.position, look, Vector3.UP)

	var sprite := Sprite2D.new()
	sprite.name = which + "Sprite"
	sprite.centered = true
	rig.sprite = sprite
	return rig


func _cam_dir() -> Vector3:
	var elev := deg_to_rad(CAM_ELEV_DEG)
	var az := deg_to_rad(CAM_AZ_DEG)
	return Vector3(cos(elev) * cos(az), sin(elev), -cos(elev) * sin(az))


func _sea_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SEA)
	# 与 scenes/WorldMap.tscn 的 Ocean 一致
	mat.set_shader_parameter("wind_angle", 0.7)
	mat.set_shader_parameter("wind_strength", 0.6)
	mat.set_shader_parameter("gust", 0.0)
	mat.set_shader_parameter("wave_speed", 0.3)
	mat.set_shader_parameter("foam_amount", 0.45)
	mat.set_shader_parameter("glint_amount", 0.22)
	mat.set_shader_parameter("stroke_amount", 0.62)
	mat.set_shader_parameter("shallows", 0.35)
	mat.set_shader_parameter("cloud_amount", 0.5)
	mat.set_shader_parameter("swell_len", 330.0)
	mat.set_shader_parameter("swell_scale", 0.003)
	if ResourceLoader.exists(FIBER):
		mat.set_shader_parameter("fiber_tex", load(FIBER))
		mat.set_shader_parameter("fiber_amount", 0.5)
	return mat


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _save_root(path: String) -> void:
	# lane w53-11 八轮：走 ShotGate.grab 口径——空视口 / 空图记账进 _fails，不再静默绿（跟 ship_exquisite 同型）
	var img := ShotGate.grab(root, path.get_file(), _fails)
	if img == null:
		return
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())


func _md5(img: Image) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(img.get_data())
	return ctx.finish().hex_encode()


func _paint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var named := ""
			if mat != null:
				named = str(mat.resource_name)
			var is_sail := named == "Sail" or str(node.name) == "Sails"
			if is_sail:
				var sh := load(SAIL) as Shader
				if sh != null:
					var sm := ShaderMaterial.new()
					sm.shader = sh
					sm.set_shader_parameter("sail_color", Color(0.93, 0.78, 0.52, 1))
					# 货帆在这张 18° 近景里更小。战舟那档缝只有大约一个像素，会被看成平板。
					if _role_of(mi) == "Merchant":
						sm.set_shader_parameter("lobe_gain", 1.05)
						sm.set_shader_parameter("crease_width", 0.062)
						sm.set_shader_parameter("crease_dark", 0.55)
						sm.set_shader_parameter("stitch_width", 0.022)
						sm.set_shader_parameter("seam_scale", 1.45)
					mi.set_surface_override_material(i, sm)
			elif mat is StandardMaterial3D:
				var wood := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				wood.vertex_color_use_as_albedo = true
				wood.roughness = 0.74
				mi.set_surface_override_material(i, wood)
	for c in node.get_children():
		_paint(c)


func _role_of(node: Node) -> String:
	var n: Node = node
	while n != null:
		var nm := str(n.name)
		if nm == "Merchant" or nm == "War":
			return nm
		n = n.get_parent()
	return ""


func _find(node: Node, want: String) -> Node:
	if str(node.name) == want:
		return node
	for c in node.get_children():
		var hit := _find(c, want)
		if hit != null:
			return hit
	return null
