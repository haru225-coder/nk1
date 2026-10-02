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
	# 2D 正角是顺时针；3D 绕 Y 正角从上方看是逆时针。抵消后船首仍朝节点的 -Y。
	_yaw.rotation.y = -_host.rotation
	var heel := float(_host.get_meta(&"nk1_heel", 0.0))
	_sprite.rotation = -_host.rotation + heel + _shudder
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
