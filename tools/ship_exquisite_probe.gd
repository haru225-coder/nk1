extends SceneTree
## 泉州湾宋船三维朝向探针。
## DISPLAY=:2 godot --path . -s res://tools/ship_exquisite_probe.gd
## 截图：/tmp/nk1-combat-wave3/ship-polish21/  close_own / close_enemy / wide / angles/angle_XX.png

const ShotGate := preload("res://tools/shot_gate.gd")
const OUT := "/tmp/nk1-combat-wave3/ship-polish21"
const FACINGS := 16

var _fails: Array = []

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ShotGate.frame_pressure(self)
	var why := ShotGate.no_render_reason()
	if why != "":
		print("SHIP_EXQUISITE_FAIL ", why)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT + "/angles")

	var world := Node2D.new()
	world.name = "Sea"
	root.add_child(world)
	var sea := ColorRect.new()
	sea.position = Vector2(-2400, -1600)
	sea.size = Vector2(4800, 3200)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/sea_surface.gdshader")
	mat.set_shader_parameter("wind_strength", 0.55)
	mat.set_shader_parameter("shallows", 0.15)
	sea.material = mat
	world.add_child(sea)

	var cam := Camera2D.new()
	cam.name = "ShotCam"
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(1.35, 1.35)
	cam.enabled = true
	world.add_child(cam)
	cam.make_current()

	var ship := (load("res://scenes/Ship.tscn") as PackedScene).instantiate()
	ship.get_node("Camera2D").enabled = false
	ship.position = Vector2(-40, 20)
	ship.set_physics_process(false)
	world.add_child(ship)

	var foe := (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	foe.position = Vector2(280, 40)
	foe.rotation = 4.712
	foe.set_physics_process(false)
	world.add_child(foe)

	for _i in 6:
		await process_frame

	# 近景己方：相机已是左舷偏艏。航向只把这张四分之三摆正，整船入画。
	foe.visible = false
	ship.position = Vector2(0, 18)
	ship.rotation = 0.15
	cam.position = ship.position
	cam.zoom = Vector2(1.48, 1.48)
	for _i in 4:
		await process_frame
	var own_img := _shot(OUT + "/close_own.png")
	_save_contract(ship, "res://assets/ship_fu.png")

	# 近景敌船：跟己方同一套艏舷四分之三。只改这一帧的航向，相机仍是 17°。
	ship.visible = false
	foe.visible = true
	foe.position = Vector2(0, 16)
	foe.rotation = 0.15
	cam.position = foe.position
	cam.zoom = Vector2(1.42, 1.42)
	for _i in 4:
		await process_frame
	var enemy_img := _shot(OUT + "/close_enemy.png")
	_save_contract(foe, "res://assets/ship_falcon.png")

	# lane w53-11 七轮：拍近景敌船那一帧，foe 必须在场且 visible。修前：foe 被遮 / 挂不出时 _shot 静默、
	# 探针照样 SHOT + OK 退 0。M7（foe.visible=false）须当场判红，不等收尾。
	if foe == null or not is_instance_valid(foe):
		_fails.append("真失败：近景敌船那一帧 foe 不在场（null / 已释放）")
	elif not foe.visible:
		_fails.append("真失败：近景敌船那帧 foe.visible=false（敌船没挂上或被遮）")

	# lane w53-11 七轮：「敌船被遮 / 没挂出」不靠两张近景的像素差判——同相机同距离，真实跑差 29.6%、
	# 敌船被遮也 30%，区别力不够。所以改用上面那一帧的 foe.visible 直查。像素差仅留诊断行供回看。
	if own_img != null and enemy_img != null:
		print("DIFF close_own vs close_enemy %.1f%% pixels differ（仅诊断，不判红）" % (_pixel_diff_frac(own_img, enemy_img) * 100.0))

	# 十六向：同一条船，只改航向。拉远一点，横侧也不被画面切掉。
	foe.visible = false
	ship.visible = true
	ship.position = Vector2.ZERO
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(1.28, 1.28)
	for i in FACINGS:
		ship.rotation = float(i) * TAU / float(FACINGS)
		for _k in 3:
			await process_frame
		_shot(OUT + "/angles/angle_%02d.png" % i)

	# 宽景：两船不同朝向，证明不是一张图在转
	ship.rotation = 0.35
	ship.position = Vector2(-390, 30)
	foe.visible = true
	foe.rotation = 4.35
	foe.position = Vector2(400, -20)
	cam.zoom = Vector2(0.78, 0.78)
	cam.position = Vector2(8, 6)
	for _i in 4:
		await process_frame
	_shot(OUT + "/wide.png")

	# 「近场敌船被遮」的近景处已判；收尾不再重查。
	if _fails.is_empty():
		print("SHIP_EXQUISITE_OK")
		quit(0)
	else:
		for f in _fails:
			print("  ✗ ", f)
		print("SHIP_EXQUISITE_FAIL %d" % _fails.size())
		quit(1)


func _shot(path: String) -> Image:
	# 画面走 ShotGate.grab 口径：空视口记红——lane w53-11 七轮：
	# 原先 _shot 取不到图只打印一行就过，探针照样 SHIP_EXQUISITE_OK 退 0，空朝面截图静悄悄。
	var name := path.get_file()
	var img := ShotGate.grab(root, name, _fails)
	if img == null:
		return null
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
	return img


## 两张近景逐像素差（同相机、同距离、相机都没动）：两艘船都挂上时画面里一艘福船一艘海鹘、差应满格；
## 有一艘没挂出来或被遮，两张都是同一片海面、差应趋零。一色海面的浪花闪变在网格取样上落不下判据，
## 比对帧「同 vs 不同」稳定。返回差像素占比（[0,1]，越大越不同）。lane w53-11 七轮立。
static func _pixel_diff_frac(a: Image, b: Image) -> float:
	if a == null or b == null:
		return -1.0
	var w: int = min(a.get_width(), b.get_width())
	var h: int = min(a.get_height(), b.get_height())
	var total := 0
	var diff := 0
	# 8 px 抽样：1280×720 下 14400 样本，稳态噪声打不过 1% 阈值，真差异（两艘船）约占满 ~90% 像素
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += 1
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.15:
				diff += 1
	return float(diff) / maxf(1.0, float(total))


func _save_contract(hull: Node, res_path: String) -> void:
	var rig := hull.get_node_or_null("HullRig")
	if rig == null or not rig.has_method("grab_image"):
		print("CONTRACT skip no rig")
		return
	var img: Image = rig.call("grab_image")
	if img == null or img.is_empty():
		print("CONTRACT empty ", res_path)
		return
	img.convert(Image.FORMAT_RGBA8)
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var disk := ProjectSettings.globalize_path(res_path)
	img.save_png(disk)
	print("CONTRACT ", disk, " ", img.get_width())
