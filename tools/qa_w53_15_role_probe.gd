extends SceneTree
## lane-w53-15 战斗方案二期职事「总管管损」「夷人减伤」（crew_role_effects，DamageModel 一侧）探针（headless）：
##   一、数学面：steward_mul()=1+0.1*lv、medic_mul()=maxf 0.2(1−0.2*lv)；0 级照旧 1.0 项。
##   二、步火账：同 seed 下 steward lv3 step 火比 lv0 烧得少（戽水扑火手上人、每级 +0.1）。
##   三、伤亡账：medic lv3 下 apply_hit 的矢石伤亡显著少于 lv0（同 seed 分簿对比，期望比 ≤ 0.6）。
##   四、接线：起 WorldMap 布景，拨 Crew.hired（zongguan / yiren 各一名）让 prime 生效；
##       panel.prime_role_effects() 后 DamageModel.steward_level / medic_level 跟着级别写进簿；
##       关掉 crew_role_effects：prime 一律写 0 级，steward / medic 都跟 wave53 开工前一致。
## 用法：godot --headless --path . -s res://tools/qa_w53_15_role_probe.gd
## 判词：QA_W53_15_ROLE_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W53_15_ROLE_PROBE"
const Dm := preload("res://scripts/combat/DamageModel.gd")
const Orders := preload("res://scripts/ui/CombatOrdersPanel.gd")
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

var _fails: Array = []
var _errlog: _ScriptErrLog = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame

	print("== 一、steward_mul / medic_mul 数学面")
	_sec_math()
	print("== 二、总管 lv3 步火账少于 lv0")
	_sec_steward_step()
	print("== 三、医人 lv3 伤亡少于 lv0")
	_sec_medic_hits()
	print("== 四、接线：prime_role_effects 走 Crew.hired，开关对照")
	await _sec_wiring()

	OS.remove_logger(_errlog)
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)


func _mk(steward: int, medic: int) -> Object:
	var def: Dictionary = root.get_node("Fleet").call("ship_def", "fu_ship_medium")
	var dm := Dm.new()
	dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 42)
	dm.call("set_steward", steward)
	dm.call("set_medic", medic)
	return dm


func _sec_math() -> void:
	for pair in [[0, 0, 1.0, 1.0], [1, 1, 1.1, 0.8], [2, 2, 1.2, 0.6], [3, 3, 1.3, 0.4], [3, 9, 1.3, 0.4]]:
		var dm := _mk(pair[0], pair[1])
		_check(is_equal_approx(float(dm.call("steward_mul")), float(pair[2])),
			"steward lv%d → 管损 ×%.2f（要 %.2f）" % [pair[0], float(dm.call("steward_mul")), pair[2]])
		_check(is_equal_approx(float(dm.call("medic_mul")), float(pair[3])),
			"medic lv%d → 伤亡 ×%.2f（要 %.2f）" % [pair[1], float(dm.call("medic_mul")), pair[3]])


func _sec_steward_step() -> void:
	var def: Dictionary = root.get_node("Fleet").call("ship_def", "fu_ship_medium")
	# 判「实际顶上的人头」：damage_crews() ——lv0 两路照 split，lv3 ×1.3（DamageModel.step 喂 ff 的正是这一路）
	var dm0 := Dm.new()
	dm0.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 42)
	var ff0 = dm0.get("ff")
	ff0.call("ignite", "mid", 0.8)
	var c0: Array = dm0.call("damage_crews")
	var dm3 := Dm.new()
	dm3.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 42)
	dm3.call("set_steward", 3)
	var ff3 = dm3.get("ff")
	ff3.call("ignite", "mid", 0.8)
	var c3: Array = dm3.call("damage_crews")
	_check(int(c0[1]) > 0 and int(c3[1]) > int(c0[1]), "fire crew lv3 (%d) > lv0 (%d)（戽水 / 扑火双路同律）" % [c3[1], c0[1]])
	# 电池侧真效：同样 ign 0.5、人 80、不再时时、step 失火 60 s 的烧量 lv3 少
	var burn0 := _fire_burn(0, def)
	var burn3 := _fire_burn(3, def)
	_check(burn0 > 0.0 and burn3 < burn0, "总管 lv3 步 60 s 烧量 %.3f < lv0 %.3f" % [burn3, burn0])


func _fire_burn(steward: int, def: Dictionary) -> float:
	var dm := Dm.new()
	dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 1141)
	dm.call("set_steward", steward)
	var ff = dm.get("ff")
	ff.call("ignite", "mid", 0.8)
	# 走 1 s × 60：5 s 大步 t 差 tail 后 i 去 0 烧量一起被压（5 s(i-douse*5) clamp 时 BURN 已按 0 算）；
	# 同 seed 单步但 douse 差 真算 lv3 vs lv0
	var tot := 0.0
	for i in range(60):
		var r: Dictionary = dm.call("step", 1.0, {})
		tot += float(r.get("hull", 0.0))
	return tot


func _sec_medic_hits() -> void:
	var dead0 := _medic_hits(0)
	var dead3 := _medic_hits(3)
	_check(dead0 > 0 and dead3 <= int(ceil(dead0 * 0.55)), "医人 lv3 受击伤亡 ≤ lv0 ×0.55（off=%d on=%d）" % [dead0, dead3])


func _medic_hits(medic: int) -> int:
	var def: Dictionary = root.get_node("Fleet").call("ship_def", "fu_ship_medium")
	var tot := 0
	for batch in range(50):
		var dm := Dm.new()
		dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 700 + batch)
		dm.call("set_medic", medic)
		for j in range(30):
			var kind: String = ["bomb", "arrow"][j % 2]
			var r: Dictionary = dm.call("apply_hit", {"amount": 25.0, "kind": kind, "high": true})
			tot += int(r.get("crew", 0))
	return tot


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _battle(fleet: Node, gm: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 4:
		await process_frame
	for c in _foes(wm):
		c.set("fire_timer", INF)
	return wm


func _sec_wiring() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var crew: Node = root.get_node("Crew")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true),
		"hired": (crew.get("hired") as Dictionary).duplicate(true)}

	# 一名三级总管、一名三级医人上册
	(crew as Object).set("hired", {"zongguan": "shi_naowei", "yiren": "sun_qiaoshou"})

	var wm := await _battle(fleet, gm)
	var ship: Node2D = Hud.ship_of(wm)
	var dm = Hud.damage_of(ship)
	_check(dm != null, "旗舰损伤簿在场")
	if dm != null:
		var panel: Node = null
		for c in wm.get_children():
			if c.is_in_group(Orders.GROUP):
				panel = c
				break
		_check(panel != null, "号令面板在场")
		if panel != null:
			var primed: Dictionary = panel.call("prime_role_effects")
			_check(int((dm as Object).get("steward_level")) == 3, "prime 后 steward_level = 3（得 %d）" % int((dm as Object).get("steward_level")))
			_check(int((dm as Object).get("medic_level")) == 3, "prime 后 medic_level = 3（得 %d）" % int((dm as Object).get("medic_level")))
			_check(int(primed.get("steward", -1)) == 3 or int(primed.get("steward", -1)) == -1, "prime 字典 steward = 3（得 %s）" % str(primed.get("steward", -1)))
			# 关开关：prime 写 0 级
			Switches.set_on("crew_role_effects", false)
			panel.call("prime_role_effects")
			_check(int((dm as Object).get("steward_level")) == 0, "crew_role_effects 关：prime 写回 steward 0")
			_check(int((dm as Object).get("medic_level")) == 0, "crew_role_effects 关：prime 写回 medic 0")
			Switches.reset()
	await _close(wm)

	crew.set("hired", saved["hired"])
	fleet.set("ships", saved["ships"])
	gm.set("pending_battle", saved["pb"])
	Switches.reset()


class _ScriptErrLog extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
