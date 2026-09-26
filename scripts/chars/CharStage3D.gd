extends SubViewportContainer
## 人物展台（chars 线）：一方 SubViewport 里的小 3D 场——漆木圆台 + 立轴画屏（贴立绘）+ 宋尺标杆，
## 另有「体量」一档：以胶囊体块示人形高矮与站位，供日后换真模型时对位。
## 只作展示：不读写 GameState，不接玩法。立绘经 CharacterArt.portrait() 取（只读）。
##
## 工程备注（不上屏）：
## - 画屏是 stand-in。真模型落地后放 res://assets/chars3d/<人物 id>.glb（或 .tscn），本台自动改挂模型、
##   隐去画屏与体块；约定：原点在两脚之间、+Y 向上、面朝 +Z、身高按米（成人约 1.60–1.75）。
## - 画屏后面是阵营籍贯的港口油画，压暗作远景；取不到就只留墨色底。
## - headless（假渲染器）下照常建树，不出画，门禁只核节点。

signal turned(yaw_deg: float)

const Art := preload("res://scripts/ui/CharacterArt.gd")

const VIEW_PX := Vector2i(352, 520)
const MODEL_DIR := "res://assets/chars3d/"
## 宋尺约 31.2 厘米（太府尺）；标杆刻到六尺
const SONG_CHI_M := 0.312
const PLATFORM_TOP := 0.18
## 画屏画心：立绘 4:5，高 1.5 米
const SCREEN_SIZE := Vector2(1.2, 1.5)
const SWAY_DEG := 9.0
const SWAY_PERIOD := 7.0

## 阵营 → 远景油画（按籍贯大致归港）
const FACTION_BG := {
	"yuhu_chen": "res://assets/bg_xinghua_harbor.jpg",
	"song_court": "res://assets/bg_linan.jpg",
	"quanxing": "res://assets/bg_linan.jpg",
	"mongol_yuan": "res://assets/bg_end_siege.jpg",
	"fanfang": "res://assets/bg_arab_mosque.jpg",
	"quanzhou_merchants": "res://assets/bg_quanzhou_harbor.jpg",
	"seafarers": "res://assets/bg_sea_route.jpg",
	"temple": "res://assets/bg_temple_gate.jpg",
	"local_officials": "res://assets/bg_quanzhou_office.jpg",
	"townsfolk": "res://assets/bg_xinghua_wine_shed.jpg",
	"foreign": "res://assets/bg_hakata.jpg",
}

var viewport: SubViewport
var turntable: Node3D
var screen_rig: Node3D
var volume_rig: Node3D
var model_slot: Node3D
var mode := "screen"
var current_id := ""

var _world: Node3D
var _screen_mat: StandardMaterial3D
var _backdrop_mat: StandardMaterial3D
var _volume_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _yaw := 0.0
var _user_yaw := 0.0
var _t := 0.0
var _dragging := false
var _swap_tween: Tween
var _live := true


func _init() -> void:
	name = "CharStage3D"
	stretch = true
	custom_minimum_size = Vector2(VIEW_PX)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_live = DisplayServer.get_name() != "headless"


func _ready() -> void:
	if viewport == null:
		_build()


# ── 建场 ─────────────────────────────────────────────

func _build() -> void:
	viewport = SubViewport.new()
	viewport.name = "StageViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED  # QA/巡检稳：4X 在多 Godot 并存时易卡死截屏
	viewport.size = VIEW_PX
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_world = Node3D.new()
	_world.name = "StageWorld"
	viewport.add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.051, 0.043, 0.035)     # 焦墨
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.45, 0.33)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false  # 截屏稳：关掉辉光，观感仍靠暖光与绢色
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.08, 0.06)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	_world.add_child(we)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 36.0
	cam.position = Vector3(0.0, 1.35, 4.3)
	_world.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.98, 0.0), Vector3.UP)
	cam.current = true

	# 主光：左前上方暖烛光；轮廓光：右后月白；补光：低处暖墨
	var key := SpotLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(1.0, 0.82, 0.58)
	key.light_energy = 5.0
	key.spot_range = 9.0
	key.spot_angle = 34.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = true
	_world.add_child(key)
	key.look_at_from_position(Vector3(-1.9, 3.2, 2.6), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_color = Color(0.84, 0.89, 0.91)             # 月白
	rim.light_energy = 0.55
	_world.add_child(rim)
	rim.look_at_from_position(Vector3(2.0, 2.4, -2.5), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color(0.93, 0.66, 0.38)
	fill.light_energy = 0.45
	fill.omni_range = 4.0
	fill.position = Vector3(1.4, 0.5, 2.0)
	_world.add_child(fill)

	_build_backdrop()
	_build_floor()

	turntable = Node3D.new()
	turntable.name = "Turntable"
	_world.add_child(turntable)
	_build_platform()
	screen_rig = _build_screen()
	turntable.add_child(screen_rig)
	volume_rig = _build_volume()
	turntable.add_child(volume_rig)
	model_slot = Node3D.new()
	model_slot.name = "ModelSlot"
	model_slot.position.y = PLATFORM_TOP
	turntable.add_child(model_slot)
	_world.add_child(_build_gauge())
	set_mode(mode)


func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if node_name != "":
		mi.name = node_name
	return mi


func _build_backdrop() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(9.6, 5.4)
	_backdrop_mat = StandardMaterial3D.new()
	_backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_backdrop_mat.albedo_color = Color(0.30, 0.25, 0.20)
	_backdrop_mat.disable_fog = false
	var bd := _mesh(q, _backdrop_mat, Vector3(0.0, 1.9, -3.6), "Backdrop")
	bd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(bd)


func _build_floor() -> void:
	var p := PlaneMesh.new()
	p.size = Vector2(14.0, 10.0)
	var fl := _mesh(p, _mat(Color(0.075, 0.062, 0.050), 0.95), Vector3.ZERO, "Floor")
	_world.add_child(fl)


## 两层漆木圆台，上层口沿一道泥金。
func _build_platform() -> void:
	var lacquer := _mat(Color(0.16, 0.075, 0.05), 0.45)      # 朱漆压暗
	var base := CylinderMesh.new()
	base.top_radius = 1.08
	base.bottom_radius = 1.14
	base.height = 0.07
	turntable.add_child(_mesh(base, _mat(Color(0.07, 0.055, 0.045), 0.7), Vector3(0, 0.035, 0), "PlatformBase"))
	var top := CylinderMesh.new()
	top.top_radius = 0.92
	top.bottom_radius = 0.98
	top.height = 0.11
	turntable.add_child(_mesh(top, lacquer, Vector3(0, 0.07 + 0.055, 0), "PlatformTop"))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.905
	ring.outer_radius = 0.935
	_rim_mat = _mat(Color(0.788, 0.631, 0.290), 0.35, 0.8)  # 泥金
	_rim_mat.emission_enabled = true
	_rim_mat.emission = Color(0.788, 0.631, 0.290)
	_rim_mat.emission_energy_multiplier = 0.12
	turntable.add_child(_mesh(ring, _rim_mat, Vector3(0, PLATFORM_TOP, 0), "GoldRim"))


## 立轴画屏：画心贴立绘，背面旧绢；上下轴杆、两根立柱、一对抱鼓墩。
func _build_screen() -> Node3D:
	var rig := Node3D.new()
	rig.name = "ScreenRig"
	var wood := _mat(Color(0.12, 0.07, 0.045), 0.55)
	var gold := _mat(Color(0.788, 0.631, 0.290), 0.4, 0.7)
	var cy := PLATFORM_TOP + 0.16 + SCREEN_SIZE.y * 0.5

	var face := QuadMesh.new()
	face.size = SCREEN_SIZE
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.roughness = 1.0
	_screen_mat.albedo_color = Color(1, 1, 1)
	# 画心带一点自发光：主光偏在一侧时，暗半边的立绘仍看得清
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0, 0, 0)
	_screen_mat.emission_energy_multiplier = 0.35
	_screen_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	rig.add_child(_mesh(face, _screen_mat, Vector3(0, cy, 0.012), "PortraitFace"))
	var back := QuadMesh.new()
	back.size = SCREEN_SIZE + Vector2(0.08, 0.08)
	var silk := _mat(Color(0.804, 0.722, 0.561), 0.95)       # 旧绢
	var bk := _mesh(back, silk, Vector3(0, cy, -0.012), "SilkBack")
	bk.rotation.y = PI
	rig.add_child(bk)
	# 裱边（前面一圈窄绫，墨褐）
	var mount := _mat(Color(0.22, 0.16, 0.10), 0.9)
	var bw := 0.045
	for spec in [
		[Vector3(SCREEN_SIZE.x + bw * 2, bw, 0.02), Vector3(0, cy + SCREEN_SIZE.y * 0.5 + bw * 0.5, 0.0)],
		[Vector3(SCREEN_SIZE.x + bw * 2, bw, 0.02), Vector3(0, cy - SCREEN_SIZE.y * 0.5 - bw * 0.5, 0.0)],
		[Vector3(bw, SCREEN_SIZE.y, 0.02), Vector3(-SCREEN_SIZE.x * 0.5 - bw * 0.5, cy, 0.0)],
		[Vector3(bw, SCREEN_SIZE.y, 0.02), Vector3(SCREEN_SIZE.x * 0.5 + bw * 0.5, cy, 0.0)],
	]:
		var b := BoxMesh.new()
		b.size = spec[0]
		rig.add_child(_mesh(b, mount, spec[1]))
	# 天杆、地杆（轴头泥金）
	var rod_w := SCREEN_SIZE.x + 0.34
	for y in [cy + SCREEN_SIZE.y * 0.5 + bw + 0.03, cy - SCREEN_SIZE.y * 0.5 - bw - 0.03]:
		var rod := CylinderMesh.new()
		rod.top_radius = 0.028
		rod.bottom_radius = 0.028
		rod.height = rod_w
		var r := _mesh(rod, wood, Vector3(0, y, 0.0))
		r.rotation.z = PI * 0.5
		rig.add_child(r)
		for sx in [-1.0, 1.0]:
			var cap := CylinderMesh.new()
			cap.top_radius = 0.038
			cap.bottom_radius = 0.038
			cap.height = 0.06
			var c := _mesh(cap, gold, Vector3(sx * rod_w * 0.5, y, 0.0))
			c.rotation.z = PI * 0.5
			rig.add_child(c)
	# 立柱与墩
	var post_h := cy + SCREEN_SIZE.y * 0.5 + 0.16 - PLATFORM_TOP
	for sx in [-1.0, 1.0]:
		var x: float = sx * (rod_w * 0.5 - 0.09)
		var post := BoxMesh.new()
		post.size = Vector3(0.05, post_h, 0.05)
		rig.add_child(_mesh(post, wood, Vector3(x, PLATFORM_TOP + post_h * 0.5, -0.05)))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.12, 0.08, 0.46)
		rig.add_child(_mesh(foot, wood, Vector3(x, PLATFORM_TOP + 0.04, -0.05)))
		var knob := SphereMesh.new()
		knob.radius = 0.04
		knob.height = 0.08
		rig.add_child(_mesh(knob, gold, Vector3(x, PLATFORM_TOP + post_h + 0.03, -0.05)))
	return rig


## 体量：胶囊示身高 1.68 米、肩宽约 0.46 米的站姿，外缘阵营色轮廓光。
func _build_volume() -> Node3D:
	var rig := Node3D.new()
	rig.name = "VolumeRig"
	_volume_mat = StandardMaterial3D.new()
	_volume_mat.albedo_color = Color(0.13, 0.11, 0.09)
	_volume_mat.roughness = 0.85
	_volume_mat.rim_enabled = true
	_volume_mat.rim = 0.9
	_volume_mat.rim_tint = 0.8
	var body := CapsuleMesh.new()
	body.radius = 0.23
	body.height = 1.42
	rig.add_child(_mesh(body, _volume_mat, Vector3(0, PLATFORM_TOP + 0.71, 0), "BodyProxy"))
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.25
	rig.add_child(_mesh(head, _volume_mat, Vector3(0, PLATFORM_TOP + 1.55, 0), "HeadProxy"))
	# 朝向小楔：示「面朝 +Z」
	var nose := PrismMesh.new()
	nose.size = Vector3(0.10, 0.08, 0.06)
	var n := _mesh(nose, _rim_mat, Vector3(0, PLATFORM_TOP + 1.55, 0.13), "FacingMark")
	n.rotation.x = PI * 0.5
	rig.add_child(n)
	return rig


## 宋尺标杆：立在台右后，一尺一刻，逢尺题字。不随转台转。
func _build_gauge() -> Node3D:
	var g := Node3D.new()
	g.name = "ChiGauge"
	g.position = Vector3(1.28, 0.0, -0.35)
	var ink := _mat(Color(0.10, 0.08, 0.06), 0.8)
	var gold := _mat(Color(0.788, 0.631, 0.290), 0.4, 0.6)
	var top_h := SONG_CHI_M * 6.0
	var pole := BoxMesh.new()
	pole.size = Vector3(0.025, top_h, 0.025)
	g.add_child(_mesh(pole, ink, Vector3(0, PLATFORM_TOP * 0.0 + top_h * 0.5, 0)))
	var digits := ["一", "二", "三", "四", "五", "六"]
	for i in 6:
		var y := SONG_CHI_M * float(i + 1)
		var tick := BoxMesh.new()
		tick.size = Vector3(0.09, 0.008, 0.02)
		g.add_child(_mesh(tick, gold, Vector3(-0.03, y, 0)))
		var l := Label3D.new()
		l.text = "%s尺" % digits[i]
		l.font = UiTheme.font()
		l.font_size = 40
		l.outline_size = 6
		l.modulate = Color(0.804, 0.722, 0.561, 0.85)
		l.outline_modulate = Color(0.051, 0.043, 0.035, 0.8)
		l.pixel_size = 0.0022
		l.position = Vector3(0.12, y, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = false
		g.add_child(l)
	return g


# ── 对外 ─────────────────────────────────────────────

## 换人：画屏先转出去，换上新画再转回来（headless 下直接换）。
func show_character(ch: Dictionary) -> void:
	if viewport == null:
		_build()
	var id := str(ch.get("id", ""))
	if id == current_id:
		return
	current_id = id
	# 巡检/无显示或 NK1_CHARS_SYNC=1：同步换画，避开 tween 与截屏竞态
	if not _live or not is_inside_tree() or OS.get_environment("NK1_CHARS_SYNC") == "1":
		_apply(ch)
		return
	if _swap_tween != null and _swap_tween.is_valid():
		_swap_tween.kill()
	_swap_tween = create_tween()
	_swap_tween.tween_property(turntable, "rotation:y", turntable.rotation.y + deg_to_rad(90.0), 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_swap_tween.tween_callback(_apply.bind(ch))
	_swap_tween.tween_callback(func() -> void: turntable.rotation.y = deg_to_rad(_yaw - 90.0))
	_swap_tween.tween_property(turntable, "rotation:y", deg_to_rad(_yaw), 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply(ch: Dictionary) -> void:
	var tex: Texture2D = Art.portrait(ch)
	_screen_mat.albedo_texture = tex
	_screen_mat.emission_texture = tex
	_screen_mat.emission = Color(1, 1, 1) if tex != null else Color(0, 0, 0)
	_screen_mat.albedo_color = Color(1, 1, 1) if tex != null else Color(0.09, 0.08, 0.07)
	var fd := Art.faction_def(str(ch.get("faction", "")))
	var fc := Color.from_string(str(fd.get("color", "#54585c")), Color(0.33, 0.35, 0.36))
	_volume_mat.rim_tint = 0.8
	_volume_mat.albedo_color = Color(0.13, 0.11, 0.09).lerp(fc, 0.18)
	var bg_path := str(FACTION_BG.get(str(ch.get("faction", "")), ""))
	_backdrop_mat.albedo_texture = load(bg_path) as Texture2D if bg_path != "" and ResourceLoader.exists(bg_path) else null
	_mount_model(str(ch.get("id", "")))
	set_mode(mode)


## 有真模型就挂上（见文件头约定），并返回 true。
func _mount_model(id: String) -> bool:
	for c in model_slot.get_children():
		c.queue_free()
	for ext: String in [".glb", ".tscn", ".gltf"]:
		var p: String = MODEL_DIR + id + ext
		if ResourceLoader.exists(p):
			var ps := load(p) as PackedScene
			if ps != null:
				model_slot.add_child(ps.instantiate())
				return true
	return false


func has_model() -> bool:
	return model_slot != null and model_slot.get_child_count() > 0 \
		and not model_slot.get_child(0).is_queued_for_deletion()


## "screen" 画屏 / "volume" 体量。有真模型时两档都让位给模型。
func set_mode(m: String) -> void:
	mode = m if m in ["screen", "volume"] else "screen"
	if screen_rig == null:
		return
	var model := has_model()
	screen_rig.visible = mode == "screen" and not model
	volume_rig.visible = mode == "volume" and not model


func yaw_deg() -> float:
	return _yaw


func set_yaw(deg: float) -> void:
	_user_yaw = clampf(deg, -180.0, 180.0)
	_yaw = _user_yaw
	if turntable != null:
		turntable.rotation.y = deg_to_rad(_yaw)


# ── 转台 ─────────────────────────────────────────────

func _process(delta: float) -> void:
	if turntable == null or not _live:
		return
	if _swap_tween != null and _swap_tween.is_running():
		return
	_t += delta
	if not _dragging:
		# 松手后缓缓回到用户转定的角度附近，微微摆动
		var target := _user_yaw + sin(_t * TAU / SWAY_PERIOD) * SWAY_DEG
		_yaw = lerpf(_yaw, target, clampf(delta * 2.0, 0.0, 1.0))
	turntable.rotation.y = deg_to_rad(_yaw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_user_yaw = wrapf(_user_yaw + (event as InputEventMouseMotion).relative.x * 0.6, -180.0, 180.0)
		_yaw = _user_yaw
		turned.emit(_yaw)
		accept_event()
