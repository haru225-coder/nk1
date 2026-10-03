extends SceneTree
## lane-w53-2 海战 / 接舷专项探针（headless）：真起 WorldMap 海战场（pending_battle），直调接舷 / 号令 / 收战那几支，
## 对账「题签上写的」与「船队 / 敌船身上真记的」。逐节：
##   一、白刃两边伤亡入账（本队先钩、白刃失利）：MeleeResolve 给的守方阵亡 def_dead 要从敌船水手里扣掉——
##       修复前只扣本队 att_dead，敌船人数一个不少，跳帮再败几回对面照样满员（回退即红：敌船水手 ≠ 开打前 − def_dead）。
## 用法：godot --headless --path . -s res://tools/qa_w53_2_combat_probe.gd
## 判词：QA_W53_2_COMBAT_PROBE PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。只改内存里的 Fleet / GameState / pending_battle，跑完还原。

const TAG := "QA_W53_2_COMBAT_PROBE"

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
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true), "martial": gs.get("martial"), "money": gs.get("money")}

	print("== 一、白刃两边伤亡入账（本队先钩、白刃失利）")
	await _sec_melee_casualties(fleet)

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	gs.set("money", saved["money"])
	await process_frame
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


## 开一场海战：一艘本队船（type / crew 由调用方定）对 enemy 条目；敌炮冻住（布景不自己结算）。返回 WorldMap
func _battle(fleet: Node, ship_type: String, crew: int, enemy: Dictionary) -> Node:
	var d: Dictionary = fleet.call("ship_def", ship_type)
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": ship_type, "name": "试船", "crew": crew, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [enemy], "sea_name": "泉州外海", "source": {"scene": "qa_w53_2"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in _foes(wm):
		f.set("fire_timer", INF)
	return wm


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm: Node) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)  # 拆布景不收战（不发 battle_finished）
		wm.queue_free()
	await process_frame


# ══ 一、白刃两边伤亡入账 ══════════════════════════════════════════

## 本队 80 人钩一艘 400 人的快船（敌披满甲）：白刃必不利（击退 / 脱钩），敌船留在场上。逐回对账：
## 敌船水手 = 开打前 − def_dead；本队水手 = 开打前 − att_dead。最多打 8 回，须至少一回 def_dead > 0（不然判不了，照红）
func _sec_melee_casualties(fleet: Node) -> void:
	var wm := await _battle(fleet, "canton_ship", 80, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	_check(foes.size() == 1, "海战刷出一艘快船（得 %d 艘）" % foes.size())
	if foes.is_empty():
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	var bad: Array = []
	var bled := 0
	var lost_rounds := 0
	for i in 8:
		if not is_instance_valid(foe) or bool(wm.get("resolved")):
			break
		foe.set("crew", 400)
		foe.set("melee_armor", 0.9)
		(fleet.get("ships") as Array)[0]["crew"] = 80
		var foe_before := int(foe.get("crew"))
		var ours_before := int(fleet.call("total_crew"))
		wm.call("_board_enemy", foe)
		var r: Dictionary = wm.get("_last_melee")
		if r.is_empty() or str(r.get("legacy", "")) == "win" or not is_instance_valid(foe):
			bad.append("第 %d 回没打成白刃失利（%s）" % [i + 1, str(r.get("outcome", "无结果"))])
			continue
		lost_rounds += 1
		var dd := int(r.get("def_dead", 0))
		var ad := int(r.get("att_dead", 0))
		if dd > 0:
			bled += 1
		if int(foe.get("crew")) != foe_before - dd:
			bad.append("第 %d 回 %s：敌船水手 %d → %d，守方阵亡 def_dead=%d 应扣到 %d" % [
				i + 1, str(r.get("outcome", "")), foe_before, int(foe.get("crew")), dd, foe_before - dd])
		if int(fleet.call("total_crew")) != ours_before - ad:
			bad.append("第 %d 回：本队水手 %d → %d，攻方阵亡 att_dead=%d 应扣到 %d" % [
				i + 1, ours_before, int(fleet.call("total_crew")), ad, ours_before - ad])
	_check(lost_rounds > 0 and bad.is_empty(), "白刃失利 %d 回：敌船水手逐回扣守方阵亡、本队逐回扣攻方阵亡%s" % [
		lost_rounds, "" if bad.is_empty() else "——" + "；".join(bad)])
	_check(bled > 0, "其中 %d 回守方确有阵亡（def_dead > 0），上一格才判得出「没扣」" % bled)
	await _close(wm)


class _ScriptErrLog extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
