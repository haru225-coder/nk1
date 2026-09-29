extends SceneTree
## 福船出海观感 + 命中手感截图探针（combat-ship-vfx）。
## Run: NK1_SHOT_DIR=/tmp/nk1-combat-wave3 DISPLAY=:2 godot --path . -s res://tools/ship_vfx_probe.gd
##      godot --headless --path . -s res://tools/ship_vfx_probe.gd -- --contract
## 截图：${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/ship-opus/

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("ship-opus")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const TAG := "SHIP_VFX_PROBE"
const EXPECTED_SHOTS := 5

var _fails: Array = []
var _saved: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	CombatStage.watch_captures()
	root.size = VIEW
	var no_render := ShotGate.no_render_reason()
	if not ShotGate.contract_mode() and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	_check_contract()
	if ShotGate.contract_mode():
		_report()
		return

	ShotGate.frame_pressure(self)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var gm := root.get_node("GameManager")
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 2}],
		"source": {"scene": "ship_vfx_probe"},
		"sea_name": "刺桐外海",
	}
	var fleet: Node = root.get_node_or_null("Fleet")
	_expect(fleet != null, "Fleet autoload")
	if fleet != null:
		fleet.set("ships", [{"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 2, "armor_level": 1, "cargo": {}, "durability": 200, "max_durability": 200}])
		fleet.set("morale", 70)

	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var wm_ref: WeakRef = weakref(wm)
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "敌船开炮已冻")

	# 等入战墨边收场
	if not await _shot_when("01_dressed_sea",
			func() -> bool: return CombatStage.letterbox_under(self, wm_ref.get_ref()) == null,
			func() -> bool: return CombatStage.standing_fail(wm_ref.get_ref()) != ""):
		_finish(wm)
		return

	var ship: Node2D = wm.get("ship") as Node2D
	_expect(ship != null, "旗舰在场")
	if ship != null:
		_expect(ship.get_node_or_null("FxHullShadow") != null, "接触阴影已挂")
		var spr := ship.get_node_or_null("Sprite2D") as Sprite2D
		_expect(spr != null and spr.material is ShaderMaterial, "福船 shader 已着装")
		# 推船速显尾迹
		ship.set("velocity", Vector2.UP.rotated(ship.rotation) * 220.0)
		ship.set("sail_gear", 2)
	# 海面着色器新参数
	var ocean := wm.get_node_or_null("Ocean") as CanvasItem
	if ocean != null and ocean.material is ShaderMaterial:
		var mat := ocean.material as ShaderMaterial
		_expect(mat.get_shader_parameter("swell_scale") != null, "海面 swell_scale 参数在")

	if ship != null:
		var wake: CPUParticles2D = ship.get_node_or_null("WakeParticles")
		if wake != null:
			wake.emitting = true
			wake.amount = maxi(wake.amount, 120)
			wake.initial_velocity_min = 40.0
			wake.initial_velocity_max = 90.0
			wake.scale_amount_min = 0.2
			wake.scale_amount_max = 0.45
		var bl: CPUParticles2D = ship.get_node_or_null("BowWaveLeft")
		var br: CPUParticles2D = ship.get_node_or_null("BowWaveRight")
		if bl: bl.emitting = true
		if br: br.emitting = true
	await _frames(28)
	await _shot_now("02_wake_underway")

	# 右舷齐射 → 炮口焰
	if ship != null and ship.has_method("_fire_broadside"):
		ship.call("_fire_broadside", 1)
	await _frames(2)
	await _shot_now("03_muzzle_starboard")

	# 本船中弹手感
	if ship != null:
		CombatFx.on_missile_hit(wm, ship.position + Vector2(20, -10), "stone", true)
		if ship.has_method("take_hit"):
			ship.call("take_hit", {"amount": 18.0, "kind": "stone"})
	await _frames(2)
	await _shot_now("04_hit_shudder")

	# 霹雳炮命中观感
	if ship != null:
		CombatFx.on_missile_hit(wm, ship.position + Vector2(-30, 40), "bomb", true)
	await _frames(4)
	await _shot_now("05_bomb_impact")

	_finish(wm)


func _check_contract() -> void:
	var fx := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	for need in ["dress_ship", "muzzle_flash", "hull_shudder", "SHIP_SHADER"]:
		_expect(fx.find(need) >= 0, "CombatFx 含 " + need)
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗", "premium", "pipeline"]:
		_expect(fx.find(bad) < 0, "CombatFx 无营销词：" + bad)
	var ocean := FileAccess.get_file_as_string("res://assets/ocean_shader.gdshader")
	_expect(ocean.find("fbm") >= 0, "海面 shader 用 fbm 涌浪")
	_expect(ocean.find("deep_color") >= 0, "海面 shader 分层色")
	_expect(FileAccess.file_exists("res://assets/shaders/ship_seagoing.gdshader"), "福船 shader 在库")
	var ship_src := FileAccess.get_file_as_string("res://scripts/Ship.gd")
	_expect(ship_src.find("muzzle_flash") >= 0, "Ship 接线炮口焰")
	_expect(ship_src.find("dress_ship") >= 0, "Ship 接线着装")
	var pir := FileAccess.get_file_as_string("res://scripts/PirateShip.gd")
	_expect(pir.find("muzzle_flash") >= 0, "PirateShip 接线炮口焰")
	_expect(pir.find("hull_shudder") >= 0, "PirateShip 接线甲板颤")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot_now(name: String) -> void:
	var path := "%s/%s.png" % [OUT_DIR, name]
	ShotGate.shot(root, path, _saved, _fails)


func _shot_when(name: String, want: Callable, gone: Callable) -> bool:
	var path := "%s/%s.png" % [OUT_DIR, name]
	return await CombatStage.shot_when(self, path.get_file(), _fails,
			func() -> void: ShotGate.shot(root, path, _saved, _fails), want, gone)


func _finish(wm) -> void:
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "布景未自行结算")
	_report()


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  OK ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)


func _report() -> void:
	var freed := CombatStage.captures_freed()
	_expect(freed == 0, "lambda 捕获未释放（%d）" % freed)
	if ShotGate.contract_mode():
		quit(ShotGate.finish_contract(TAG, _fails))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
