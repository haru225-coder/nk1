extends SceneTree
## 泉州湾宋船三维朝向探针。
## DISPLAY=:2 godot --path . -s res://tools/ship_exquisite_probe.gd
## 截图：/tmp/nk1-combat-wave3/ship-polish5/  close_own / close_enemy / wide / angles/angle_XX.png

const ShotGate := preload("res://tools/shot_gate.gd")
const OUT := "/tmp/nk1-combat-wave3/ship-polish5"
const FACINGS := 16

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
	foe.rotation = 2.15
	foe.set_physics_process(false)
	world.add_child(foe)

	for _i in 6:
		await process_frame

	# 近景己方：艏舷四分之三，整船在画面里，水线露出来。不是艉视正俯。
	foe.visible = false
	ship.position = Vector2(0, 10)
	ship.rotation = 1.35
	cam.position = ship.position
	cam.zoom = Vector2(2.05, 2.05)
	for _i in 4:
		await process_frame
	_shot(OUT + "/close_own.png")
	_save_contract(ship, "res://assets/ship_fu.png")

	# 近景敌船：另一舷的四分之三，同样整船入画
	ship.visible = false
	foe.visible = true
	foe.position = Vector2(0, 8)
	foe.rotation = 2.45
	cam.position = foe.position
	cam.zoom = Vector2(1.85, 1.85)
	for _i in 4:
		await process_frame
	_shot(OUT + "/close_enemy.png")
	_save_contract(foe, "res://assets/ship_falcon.png")

	# 十六向：同一条船，只改航向。拉远一点，横侧也不被画面切掉。
	foe.visible = false
	ship.visible = true
	ship.position = Vector2.ZERO
	cam.position = Vector2.ZERO
	cam.zoom = Vector2(1.72, 1.72)
	for i in FACINGS:
		ship.rotation = float(i) * TAU / float(FACINGS)
		for _k in 3:
			await process_frame
		_shot(OUT + "/angles/angle_%02d.png" % i)

	# 宽景：两船不同朝向，证明不是一张图在转
	ship.rotation = 1.35
	ship.position = Vector2(-340, 20)
	foe.visible = true
	foe.rotation = 2.55
	foe.position = Vector2(360, -16)
	cam.zoom = Vector2(0.95, 0.95)
	cam.position = Vector2(10, 4)
	for _i in 4:
		await process_frame
	_shot(OUT + "/wide.png")

	print("SHIP_EXQUISITE_OK")
	quit(0)


func _shot(path: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT FAIL empty ", path)
		return
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())


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
