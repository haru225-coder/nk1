extends SceneTree
## 海面 / 尾迹 / 敌船轮廓 / 落水 / 接舷氛围截图探针（lane atmos）。真海战布景（WorldMap + pending_battle），冻敌炮，按墙钟推进。
## Run: DISPLAY=:4 godot --path . -s res://tools/atmos_water_probe.gd
##      NK1_ATMOS_OUT=/tmp/x NK1_ATMOS_PREFIX=00_before_ DISPLAY=:4 godot --path . -s res://tools/atmos_water_probe.gd
## 截图缺省写 /tmp/nk1-combat-wave3/opus-atmos/。headless 下无渲染，直接判红退出（不假绿）。
## 另验：WorldMap 海面换上 sea_surface 着色器、每条船挂上尾迹、敌船挂上轮廓（前缀 00_before_ 时跳过这些断言）。

const VIEW := Vector2i(1280, 720)
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const SPLASH := preload("res://scenes/WaterSplash.tscn")
const TAG := "ATMOS_WATER_PROBE"

var _out := ""
var _prefix := ""
var _fails: Array = []
var _saved: Array = []
var _cam: Camera2D = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_out = OS.get_environment("NK1_ATMOS_OUT")
	if _out == "":
		_out = "/tmp/nk1-combat-wave3/opus-atmos"
	_prefix = OS.get_environment("NK1_ATMOS_PREFIX")
	DirAccess.make_dir_recursive_absolute(_out)
	if DisplayServer.get_name() == "headless":
		print("%s FAIL headless：无渲染，截不了图" % TAG)
		quit(1)
		return
	var gm := root.get_node("GameManager")
	var fleet: Node = root.get_node_or_null("Fleet")
	if fleet != null:
		fleet.set("ships", [{"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 200, "max_durability": 200}])
		fleet.set("morale", 70)
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 2}], "sea_name": "泉州外洋",
		"sea_seed": 7, "wind_bearing": 60.0, "wind_strength": 96.0,
		"source": {"scene": "atmos_probe"},
	}
	var wm: Node2D = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var wm_ref: WeakRef = weakref(wm)
	CombatStage.freeze_enemy_fire(wm)
	var ship: Node2D = wm.get("ship")
	var foes: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			foes.append(c)
	_expect(foes.size() == 2, "布景刷出 2 艘敌船")
	_park(ship, foes)
	# 入战墨边收场
	await CombatStage.wait_until(self, func() -> bool: return CombatStage.letterbox_under(self, wm_ref.get_ref()) == null, 8000)
	await _secs(0.8)
	_park(ship, foes)
	await _secs(0.5)

	if _prefix == "":
		_check_dress(wm, ship, foes)

	# 01 宽：自带镜头拉远到海图尺度
	_take_cam(wm, ship.global_position + Vector2(0, -40), 0.42)
	await _secs(0.6)
	await _shot("01_after_water_wide" if _prefix == "" else "water_wide")
	# 02 近：战斗镜头
	_take_cam(wm, ship.global_position + Vector2(40, -30), 1.5)
	await _secs(0.5)
	await _shot("02_after_water_close" if _prefix == "" else "water_close")
	_drop_cam(ship)

	# 03 尾迹 / 风痕：满帆跑 4 秒，敌船挪开别挡
	for f in foes:
		if is_instance_valid(f):
			_place(f, ship.global_position + Vector2(900, 900))
	ship.set("sail_gear", 2)
	await _secs(4.0)
	_take_cam(wm, ship.global_position + Vector2.DOWN.rotated(ship.rotation) * 120.0, 1.05)
	await _secs(0.3)
	await _shot("03_wake_or_wind" if _prefix == "" else "wake")
	_drop_cam(ship)
	ship.set("sail_gear", 0)

	# 04 敌我轮廓：两船并列
	await _secs(0.6)
	if foes.size() > 0 and is_instance_valid(foes[0]):
		var f0: Node2D = foes[0]
		_place(f0, ship.global_position + Vector2(230, -20), ship.rotation + 0.35)
		if foes.size() > 1:
			_place(foes[1], ship.global_position + Vector2(-260, 60), ship.rotation - 0.6)
		_take_cam(wm, ship.global_position + Vector2(0, 10), 1.0)
		await _secs(0.35)
		await _shot("04_pirate_silhouette" if _prefix == "" else "pirate")
		_drop_cam(ship)

	# 05 落水：两发砲石、一排矢落在船边
	var at: Vector2 = ship.global_position + Vector2(150, -90)
	for p in [at, at + Vector2(-70, 60), at + Vector2(60, 110)]:
		var s: Node2D = SPLASH.instantiate()
		s.position = wm.to_local(p)
		wm.add_child(s)
		(s as CPUParticles2D).emitting = true
	_take_cam(wm, ship.global_position + Vector2(90, -20), 1.5)
	await _secs(0.22)
	await _shot("05_combatfx_water_hit" if _prefix == "" else "water_hit")
	await _secs(0.5)
	await _shot("05b_combatfx_water_ring" if _prefix == "" else "water_ring")
	_drop_cam(ship)

	# 06 接舷
	var ne: Array = wm._nearest_enemy()
	if ne.size() == 2:
		var e: Node2D = ne[0]
		_place(e, ship.global_position + Vector2(96, 10), ship.rotation + 0.12)
		wm._board_enemy(e)
		await _secs(0.34)
		await _shot("06_boarding_drama" if _prefix == "" else "boarding")
	await _secs(0.3)
	CombatStage.teardown(self, wm_ref.get_ref(), gm)
	await _secs(0.1)
	for f in _fails:
		print("%s FAIL %s" % [TAG, f])
	print("%s %s shots=%d fails=%d out=%s" % [TAG, "OK" if _fails.is_empty() else "FAIL", _saved.size(), _fails.size(), _out])
	quit(0 if _fails.is_empty() else 1)


func _check_dress(wm: Node, ship: Node2D, foes: Array) -> void:
	var ocean := wm.get_node_or_null("Ocean") as CanvasItem
	var mat := ocean.material as ShaderMaterial if ocean != null else null
	_expect(mat != null and mat.shader != null and mat.shader.resource_path.ends_with("sea_surface.gdshader"),
		"海面换上 sea_surface 着色器")
	_expect(wm.get_node_or_null("SeaAtmosphere") != null, "WorldMap 挂上 SeaAtmosphere")
	var wakes := 0
	var atm := wm.get_node_or_null("SeaAtmosphere")
	if atm != null:
		for c in atm.get_children():
			if String(c.name).begins_with("Wake_"):
				wakes += 1
	_expect(wakes >= 3, "旗舰 + 2 敌船各有尾迹带（%d）" % wakes)
	for f in foes:
		var spr := (f as Node).get_node_or_null("Sprite2D")
		_expect(spr != null and spr.get_node_or_null("FoeRim") != null, "敌船挂上轮廓 FoeRim")
		_expect((f as Node).get_node_or_null("FoePennant") != null, "敌船挂上黑旗 FoePennant")


## 摆拍挪船：清掉速度。PirateShip 挪位后下一物理帧 velocity 会记成整段位移 / delta（实测 4 万+），
## 尾迹粒子 scale 随 speed_ratio 放大成满屏大方块——那是摆拍假象，不是海面
func _place(n: Node2D, at: Vector2, rot := INF) -> void:
	if n == null or not is_instance_valid(n):
		return
	n.global_position = at
	if rot != INF:
		n.rotation = rot
	if n is CharacterBody2D:
		(n as CharacterBody2D).velocity = Vector2.ZERO
	var wp := n.get_node_or_null("WakeParticles") as CPUParticles2D
	if wp != null:
		wp.restart()
		wp.emitting = false


func _park(ship: Node2D, foes: Array) -> void:
	var offs := [Vector2(280, -160), Vector2(-320, 120)]
	for i in foes.size():
		if is_instance_valid(foes[i]):
			_place(foes[i], ship.global_position + offs[i % 2])


func _take_cam(wm: Node, at: Vector2, zoom: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera2D.new()
		_cam.name = "ProbeCam"
		wm.add_child(_cam)
	_cam.global_position = at
	_cam.zoom = Vector2(zoom, zoom)
	_cam.make_current()


func _drop_cam(ship: Node2D) -> void:
	var c := ship.get_node_or_null("Camera2D") as Camera2D
	if c != null:
		c.make_current()


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s%s.png" % [_out, _prefix, name]
	if img == null or img.is_empty():
		_fails.append("截图为空：" + name)
		return
	img.save_png(path)
	_saved.append(path)
	print("  SHOT ", path)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  OK ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)
