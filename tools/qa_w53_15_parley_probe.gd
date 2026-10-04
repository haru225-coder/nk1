extends SceneTree
## lane-w53-15 战斗方案一期「劝降钮挂敌船、三样凑齐才亮」探针（headless）：
## parley_on_ship 开时，喊话不再「走到 360 px 就成」，改由敌船形势三样定：被钩住・帆被打坏・已动摇。
## 逐条钉一项、回退即红：
##   一、parley_road 纯函数的判词（凑词列表）：缺一样愁一字，凑齐三样「可喊话」且 have 三格皆真。
##   二、真起战备 WorldMap + 号令面板：parley_on_ship 开时，orphan 敌船（钩未挂、船体满、士气簿稳）喊话「不成」
##       （parley_context.ok = false、why 含「未钩住」/「帆尚在」/「阵脚未乱」）；改成被钩住 + 船体伤半 + 士气簿「动摇」，
##       ok 返真、why 写在路，发 parley 实打（roll 定 0）得「敌竖降幡」。关总开关 off：同一场喊话不判三样、
##       近敌就能喊（照旧玩法）。
## 用法：godot --headless --path . -s res://tools/qa_w53_15_parley_probe.gd
## 判词：QA_W53_15_PARLEY_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W53_15_PARLEY_PROBE"
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

	print("== 一、parley_road 纯函数（钩住・帆残・动摇三样凑齐才亮）")
	_sec_road()
	print("== 二、parley_on_ship 开 / 关对照：喊话走敌船形势")
	await _sec_on_ship()

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


func _sec_road() -> void:
	var all := Orders.parley_road({"grappled": true, "hull_frac": 0.4, "enemy_state": "shaken"})
	_check(bool(all["lit"]) and str(all["road"]) == "可喊话", "钩子挂上・船伤过半・士气簿动摇 → 亮")
	var h: Dictionary = all["have"]
	_check(bool(h["grappled"]) and bool(h["sail_broken"]) and bool(h["shaken"]), "have 三格皆真（得 grap=%s sail=%s shaken=%s）" % [h["grappled"], h["sail_broken"], h["shaken"]])
	for s in ["wavering", "routing"]:
		var r := Orders.parley_road({"grappled": true, "hull_frac": 0.4, "enemy_state": s})
		_check(bool(r["lit"]), "士气簿 %s 也亮" % s)
	for t in [["未钩住", {"grappled": false, "hull_frac": 0.4, "enemy_state": "shaken"}],
			["帆尚在", {"grappled": true, "hull_frac": 0.95, "enemy_state": "shaken"}],
			["阵脚未乱", {"grappled": true, "hull_frac": 0.4, "enemy_state": "steady"}]]:
		var r := Orders.parley_road(t[1])
		_check(not bool(r["lit"]) and str(r["road"]).contains(t[0]), "只缺 %s → 不亮、why 拿这字（实得 %s）" % [t[0], str(r["road"])])
	var two := Orders.parley_road({"grappled": false, "hull_frac": 0.95, "enemy_state": "steady"})
	_check(str(two["road"]) == "未钩住、帆尚在、阵脚未乱", "三样都缺 → why 三缺逐字列：%s" % str(two["road"]))


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _battle(fleet: Node, morale: int) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 80, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in _foes(wm):
		f.set("fire_timer", INF)
	var panel: Node = null
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			panel = c
			break
	if panel != null:
		# 敌船士气簿走 Orders._hull_seen 计 hull_frac；一帧吃下开战 hull
		for _i in 2:
			panel.call("tick", 0.5)
	return wm


func _panel_of(wm: Node) -> Node:
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			return c
	return null


func _sec_on_ship() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	# 开：三样凑齐才亮（未钩住 / 帆好 / 簿稳 → 不喊；改齐 → 能喊）
	var wm := await _battle(fleet, 60)
	var panel: Node = _panel_of(wm)
	_check(panel != null, "号令面板在场")
	if panel == null:
		await _close(wm)
		Switches.reset()
		fleet.set("ships", saved["ships"])
		gm.set("pending_battle", saved["pb"])
		return
	var ship: Node2D = Hud.ship_of(wm)
	var foe: Node2D = _foes(wm)[0]
	if ship != null:
		foe.global_position = ship.global_position + Vector2(140, 0)
	var ctx0: Dictionary = panel.call("parley_context")
	_check(not bool(ctx0.get("ok", false)), "未钩住・帆好・簿稳 → 喊话不亮：%s" % str(ctx0.get("why", "")))
	var why0 := str(ctx0.get("why", ""))
	_check(why0.contains("未钩住") and why0.contains("帆尚在") and why0.contains("阵脚未乱"), "why 白从三样凑字：%s" % why0)
	# 凑齐三样：钩住（grappled）・伤过半（hull 打到三成）・士气簿动摇（CombatMorale meta 写得抢）
	foe.set("grappled", true)
	var hull0: float = Hud.prop_f(foe, "hull_hp", 0.0)
	foe.set("hull_hp", hull0 * 0.3)
	foe.set_meta(&"nk1_combat_morale", {"state": "shaken", "value": 35})
	panel.call("tick", 0.5)  # 仍记 hull_seen 的开战值：hull_frac 实打
	var ctx1: Dictionary = panel.call("parley_context")
	_check(bool(ctx1.get("ok", false)), "被钩住・船伤过半・簿动摇 → 喊话亮（%s）" % str(ctx1.get("why", "ok")))
	var road = ctx1.get("road", null)
	_check(road is Dictionary and bool((road as Dictionary).get("lit", false)), "parley_context 带 road.lit = true")
	# 发 parley 实打：roll 0 必降
	var pay: Dictionary = panel.call("issue", "parley", 0.0)
	_check(str(pay.get("order", "")) == "parley" and str(pay.get("result", "")) == "surrender", "实按 5 号出「敌竖降幡」：%s" % str(pay.get("result", "")))
	foe.set("grappled", false)
	foe.set("hull_hp", hull0)
	foe.remove_meta(&"nk1_combat_morale")
	await _close(wm)
	Switches.reset()

	# 关：near 就能喊（不判三样）
	Switches.set_on("parley_on_ship", false)
	var wm2 := await _battle(fleet, 60)
	var panel2 := _panel_of(wm2)
	if panel2 != null:
		var ship2: Node2D = Hud.ship_of(wm2)
		var foe2: Node2D = _foes(wm2)[0]
		if ship2 != null:
			foe2.global_position = ship2.global_position + Vector2(140, 0)
		var ctx_off: Dictionary = panel2.call("parley_context")
		_check(bool(ctx_off.get("ok", false)), "off：未钩住・帆好・簿稳 也能喊（距内即行），与 wave53 开工前一致")
	await _close(wm2)
	Switches.reset()

	fleet.set("ships", saved["ships"])
	gm.set("pending_battle", saved["pb"])


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
