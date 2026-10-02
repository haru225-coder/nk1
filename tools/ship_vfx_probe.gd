extends SceneTree
## 出海船观感 + 命中手感截图探针（lane ship-vfx；polish 起改真弹、按相位截）。
## Run: NK1_SHOT_DIR=/tmp/nk1-combat-wave3 DISPLAY=:2 godot --path . -s res://tools/ship_vfx_probe.gd
##      godot --headless --path . -s res://tools/ship_vfx_probe.gd -- --contract
## 截图：${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/ship-vfx/
##   01_wide        远景（探针镜头 zoom 0.45）：三船剪影、敌船朱边、投影、航迹白练
##   02_close       旗舰近景（旗舰镜头）
##   03_muzzle      右舷齐射出手那一帧：星芒暖闪 + 火星拖线 + 火药烟团（画出第一记星芒的那一帧截）
##   04_hit_impact  敌船一发砲石落在本船舷上：星芒、木屑、舷边溅水、船身一闪一颤、镜头顺来力推 + 屏幕错位（落弹后第一帧截）
## 软渲染（llvmpipe）一帧可达数百 ms，截出手 / 落弹那几拍时游戏钟放到 0.05 倍（弹道、粒子跟着慢）。星芒的补间走真实时间，
## 帧太慢时 03 可能截到的是命中那几记星芒而不是出手那一记——看图时留意；60 fps 下出手星芒约亮 6 帧。
##   05_volley      齐射打到敌船：敌船船身一闪一颤、焦痕，出手烟团鼓开（敌船挨打后约 0.08 s 截）
##   06_founder     另一条敌船中砲石沉没：船身残影歪倒、压暗、没入海面，白沫漂木（沉后约 0.6 s 截）
## 布景同 combat_probe_stage：冻敌炮（探针自己放那一发砲石）、敌船关物理、逐帧钉在旗舰旁，构图每次一样。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("ship-vfx")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const Ballistics := preload("res://scripts/combat/Ballistics.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const TAG := "SHIP_VFX_PROBE"
const EXPECTED_SHOTS := 6
## 敌船摆位（旗舰局部坐标，船首 -y）与相对航向
const FOE_AT := [Vector2(235, -20), Vector2(-360, 300)]
var FOE_AT_LIVE := FOE_AT.duplicate()
const FOE_ROT := [0.12, -0.4]

var _fails: Array = []
var _saved: Array = []
var _ship: Node2D = null
## 截命中 / 出手那几拍时放慢游戏钟（软渲染一帧近 100 ms，0.09 s 的星芒一帧都画不上）；_shot_drawn 每帧重设（顿帧收尾会把它复成 1）
var _slowmo := 1.0
var _foes: Array = []


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
		fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 400, "max_durability": 400}])
		fleet.set("morale", 70)

	# 被测树自检（lane w26-k6 接 wave23-a9 共用面）：WorldMap 挂不出 / 挂空壳秒级判红；字段在过帧后点名
	var wm: Node = ShotGate.start_tree_probe("res://scenes/WorldMap.tscn", _fails, "ShipVfx WorldMap")
	if wm == null:
		_report()
		return
	root.add_child(wm)
	for _i in 6:
		await process_frame
	if not ShotGate.check_fields(wm, {"combat_mode": "WorldMap.gd Parse Error / 海战布景断", "resolved": "WorldMap.gd Parse Error / 海战布景断"}, _fails, "ShipVfx WorldMap"):
		_finish(wm)
		return
	var wm_ref: WeakRef = weakref(wm)
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "敌船开炮已冻")
	_ship = wm.get("ship") as Node2D
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set_physics_process(false)
			_foes.append(c)
	# 头船要挨一轮齐射再回一发砲石：船体加厚，别被这一轮打沉
	if not _foes.is_empty():
		_foes[0].set("hull_hp", 5000.0)
		_foes[0].set("hull_max", 5000.0)
	_expect(_ship != null, "旗舰在场")
	if _ship == null:
		_finish(wm)
		return
	_expect(_ship.get_node_or_null("HullWater") != null, "船下投影 / 贴舷白浪层在（ShipLook）")
	_expect(_ship.get_node_or_null(CombatFx.LOOK_NODE) != null, "船身反应节点 FxLook 已挂")
	var spr := _ship.get_node_or_null("Sprite2D") as Sprite2D
	_expect(spr != null and spr.material is ShaderMaterial, "船身 shader 已着装")
	var ocean := wm.get_node_or_null("Ocean") as CanvasItem
	_expect(ocean != null and ocean.z_index < -1, "海面压在投影 / 航迹之下（Ocean z < -1）")

	# 入战墨边收场，旗舰半帆走起来（航迹要走出几秒才开叉）
	if not await CombatStage.wait_until(self,
			func() -> bool: return CombatStage.letterbox_under(self, wm_ref.get_ref()) == null):
		_fails.append("入战墨边没收场")
		_finish(wm)
		return
	# 横风（正横受风）走：顶风走不起来，航迹出不来
	var wv = _ship.get("wind_vector")
	if wv is Vector2 and (wv as Vector2).length() > 0.01:
		_ship.rotation = (wv as Vector2).orthogonal().angle() + PI * 0.5
	_ship.set("sail_gear", 1)
	await _pinned(2.6)

	# 01 远景
	var cam := Camera2D.new()
	cam.zoom = Vector2(0.45, 0.45)
	wm.add_child(cam)
	cam.global_position = _ship.global_position + Vector2(0, 60)
	cam.make_current()
	await _pinned(0.1)
	cam.global_position = _ship.global_position + Vector2(0, 60)
	await _shot_drawn("01_wide", func() -> bool: return true)

	# 02 近景
	var own_cam := _ship.get("camera") as Camera2D
	if own_cam != null:
		own_cam.make_current()
	cam.queue_free()
	await _pinned(0.9)
	await _shot_drawn("02_close", func() -> bool: return true)

	# 03 齐射出手：画出第一记星芒的那一帧
	var foe: Node2D = _foes[0] if not _foes.is_empty() else null
	var foe_hp := float(foe.get("hull_hp")) if foe != null else 0.0
	_ship.set("fire_cooldown", 0.0)
	_slowmo = 0.05
	Engine.time_scale = _slowmo
	_ship.call("_fire_broadside", 1)
	_expect(await _shot_drawn("03_muzzle", _flash_up), "03 截到齐射星芒")

	# 05 齐射打到敌船：敌船掉血后约 0.08 s
	if foe != null:
		var hit_foe := await _pinned_until(func() -> bool:
			return not is_instance_valid(foe) or float(foe.get("hull_hp")) < foe_hp, 3.0)
		_expect(hit_foe, "齐射打中敌船")
		await _pinned(0.08)
		await _shot_drawn("05_volley", func() -> bool: return true)
	_slowmo = 1.0
	Engine.time_scale = 1.0
	await _pinned(1.6)

	# 04 本船挨一发砲石：落弹后画出的第一帧
	var hp := float(_ship.get("hull_hp"))
	if foe != null:
		# 落点带提前量：旗舰在走，砲石飞 ~0.8 s
		var aim := _ship.global_position + Vector2(-26, -36).rotated(_ship.global_rotation)
		var ft := Ballistics.flight_time("pao", foe.global_position.distance_to(aim))
		aim += (_ship as CharacterBody2D).velocity * ft
		_lob_at(wm, foe, aim, "pao")
	# 落弹前就放慢（顿帧收尾会把钟复成 1，_pinned_until 每帧重设）
	_slowmo = 0.05
	var hit_own := await _pinned_until(func() -> bool: return float(_ship.get("hull_hp")) < hp, 6.0)
	_expect(hit_own, "敌船砲石落在本船上")
	await _shot_drawn("04_hit_impact", func() -> bool: return true)
	var look = _ship.get_node_or_null(CombatFx.LOOK_NODE)
	_expect(look != null and int((look.get("scars") as PackedVector4Array).size()) >= 1, "本船中砲石留下焦痕")

	_slowmo = 1.0
	Engine.time_scale = 1.0
	await _pinned(1.2)

	# 06 另一条敌船沉没：拉近到旗舰左后，船体压到 1，一发砲石
	if _foes.size() >= 2 and is_instance_valid(_foes[1]):
		var f2: Node2D = _foes[1]
		FOE_AT_LIVE[1] = Vector2(-250, 60)
		f2.set("hull_hp", 1.0)
		await _pinned(0.2)
		_lob_at(wm, _ship, f2.global_position, "pao")
		var f2_ref: WeakRef = weakref(f2)
		var sunk := await _pinned_until(func() -> bool: return f2_ref.get_ref() == null, 6.0)
		_expect(sunk, "敌船中砲石沉没")
		await _pinned(0.6)
		await _shot_drawn("06_founder", func() -> bool: return true)
	await _pinned(0.3)
	_finish(wm)


## 场上有一记齐射星芒亮着（CombatFx._flash_sprite：flash_star 加色 Sprite2D）
func _flash_up() -> bool:
	for n in get_nodes_in_group(CombatFx.GROUP):
		var s := n as Sprite2D
		if s != null and s.has_meta(&"nk1_flash") and s.modulate.a > 0.35:
			return true
	return false


## 一发砲石（Ballistics.plan_shot 真弹）从 from 船心抛向 at
func _lob_at(wm: Node, from: Node2D, at: Vector2, weapon: String) -> void:
	var s := Ballistics.plan_shot(weapon, from.global_position, at, {"spread_mult": 0.1})
	s["landing"] = at
	var cb = (load("res://scenes/Cannonball.tscn") as PackedScene).instantiate()
	cb.shooter = from
	cb.configure(s)
	wm.add_child(cb)


func _place_foes() -> void:
	if _ship == null or not is_instance_valid(_ship):
		return
	for i in _foes.size():
		var f = _foes[i]
		if not is_instance_valid(f):
			continue
		f.global_position = _ship.global_position + (FOE_AT_LIVE[i] as Vector2).rotated(_ship.global_rotation)
		f.global_rotation = _ship.global_rotation + float(FOE_ROT[i])


func _pinned(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	while t < sec and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		t += root.get_process_delta_time()
		_place_foes()


func _pinned_until(cond: Callable, max_game_s: float) -> bool:
	var t := 0.0
	var t0 := Time.get_ticks_msec()
	while t < max_game_s and Time.get_ticks_msec() - t0 < 60000:
		if cond.call():
			return true
		Engine.time_scale = _slowmo
		await process_frame
		t += root.get_process_delta_time()
		_place_foes()
	return cond.call()


## 等到画出来的那一帧 want 成立就截（最多 3 s 墙钟）；截到返回 true
func _shot_drawn(name: String, want: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		Engine.time_scale = _slowmo
		await process_frame
		_place_foes()
		await RenderingServer.frame_post_draw
		if want.call():
			ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)
			await process_frame
			await process_frame
			return true
	_fails.append("%s 没截到该相位" % name)
	return false


func _check_contract() -> void:
	var fx := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	for need in ["dress_ship", "muzzle_flash", "hull_shudder", "hull_impact", "screen_kick", "founder", "SHIP_SHADER"]:
		_expect(fx.find(need) >= 0, "CombatFx 含 " + need)
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗", "premium", "pipeline"]:
		_expect(fx.find(bad) < 0, "CombatFx 无营销词：" + bad)
	# 命中 / 出手的一闪不再用软白晕贴图（glow_warm / mist_puff 放大当焰、当烟即一团白）
	var body := fx.substr(fx.find("static func muzzle_flash"), fx.find("static func founder") - fx.find("static func muzzle_flash"))
	_expect(body.find("glow_warm") < 0 and body.find("mist_puff") < 0 and body.find("soft_dot") < 0, "齐射出手不用软白晕贴图")
	for scn in ["res://scenes/ImpactExplosion.tscn", "res://scenes/WaterSplash.tscn"]:
		var src := FileAccess.get_file_as_string(scn)
		_expect(src.find("soft_dot") < 0 and src.find("glow_warm") < 0, "%s 不用软白晕贴图" % scn.get_file())
	for tex in ["smoke_puff", "flash_star", "spark_streak", "splinter", "water_drop", "foam_ring"]:
		_expect(ResourceLoader.exists("res://assets/fx/%s.png" % tex), "命中贴图在库：%s.png" % tex)
	for sh in ["ship_seagoing", "screen_kick"]:
		_expect(FileAccess.file_exists("res://assets/shaders/%s.gdshader" % sh), "shader 在库：%s" % sh)
	var ship_src := FileAccess.get_file_as_string("res://scripts/Ship.gd")
	_expect(ship_src.find("muzzle_flash") >= 0, "Ship 接线炮口焰")
	_expect(ship_src.find("dress_ship") >= 0, "Ship 接线着装")
	_expect(ship_src.find("camera.offset = -side_dir * 30.0") < 0, "齐射后坐不再硬甩 30 px")
	var pir := FileAccess.get_file_as_string("res://scripts/PirateShip.gd")
	_expect(pir.find("muzzle_flash") >= 0, "PirateShip 接线炮口焰")
	_expect(pir.find("hull_shudder") >= 0, "PirateShip 接线甲板颤")
	_expect(pir.find("founder") >= 0, "PirateShip 沉没留残影")
	var cb := FileAccess.get_file_as_string("res://scripts/Cannonball.gd")
	_expect(cb.find("hull_impact") >= 0, "Cannonball 命中交船身反应")


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
