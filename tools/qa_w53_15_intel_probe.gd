extends SceneTree
## lane-w53-15 战斗系统方案第一期「敌情与号令」探针（headless）。逐条钉一项实施、回退即红：
##   一、敌情列（enemy_intel 开）：真起战备 WorldMap，CombatStatusHud 右上多一匾「敌情」，
##       场上几艘敌船就几行（每艘布色墨珠 + 估计伤情 + 船种），沉一艘后行数跟着少。
##       关掉总开关（CombatSwitches "enemy_intel" = off）：同一场海战敌情列不建（照 wave53 开工前的旧玩法）。
##   二、布色与船种的纯函数：PirateShip 型样船走表（pirate_boat → 快船 / sea_falcon → 海鹘），
##       白帆（struck 或簿上 struck）的布色珠是「白帆」色（不是「稳」的灰青）；
##       敌情行至少有 2 行（开战两艘），沉一艘只剩 1 行、行里不再写它的船种。
##   三、我方士气险档（enemy_intel 开，Fleet 士气跌到 18 / 7）：
##       _refresh_morale_bar 上方那行小条 ≥ 20 不提、跌到 18 出「队里乱了」、跌到 7 出「白旗要挂出来了」；
##       回 32 档销档、再跌到 18 又提（不叠只回线）。关掉总开关：跌到低也不提。
## 用法：godot --headless --path . -s res://tools/qa_w53_15_intel_probe.gd
## 判词：QA_W53_15_INTEL_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。只改内存里的 Fleet / GameManager pending_battle，跑完还原。
## 注：真战例（迎战 2 艘元军海鹘）未打；探针走布景 WorldMap，与 qa_w53_2_combat_probe 同工。

const TAG := "QA_W53_15_INTEL_PROBE"
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
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	print("== 一、敌情列：enemy_intel 开 / 关对照")
	await _sec_intel_on(fleet)
	await _sec_intel_off(fleet)
	print("== 二、布色 / 船种 / 行数")
	_sec_cloth_kind()
	print("== 三、我方士气险档提示条")
	await _sec_morale_bar(fleet)

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
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


# ── 布景：开一场两艘海鹘的海战 ───────────────────────────

func _battle(fleet: Node, crew: int) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": crew, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 2}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in _foes(wm):
		f.set("fire_timer", INF)
	return wm


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _hud_of(wm: Node) -> Node:
	for c in wm.get_children():
		if c.is_in_group(Hud.GROUP):
			return c
	return null


# ── 一、敌情列：enemy_intel 开关对照 ──────────────────────

func _sec_intel_on(fleet: Node) -> void:
	var wm := await _battle(fleet, 80)
	var hud := _hud_of(wm)
	_check(hud != null, "海战场挂着状态条（敌情列、士气条所在）")
	if hud == null:
		await _close(wm)
		return
	for _i in 3:
		await process_frame
	var card: Node = hud.get("_intel")
	_check(card != null, "enemy_intel 开：状态条自出敌情列（_intel）")
	if card != null:
		var rows: Node = hud.get("_intel_rows")
		_check(rows != null and rows.get_child_count() == _foes(wm).size(),
			"两艘敌船 = 两行敌情（得 %d）" % (rows.get_child_count() if rows != null else -1))
		if rows != null and rows.get_child_count() > 0:
			var lbl := (rows.get_child(0).get_child(1) as Label).text
			_check(lbl.contains("海鹘"), "行内写有船种「海鹘」：%s" % lbl)
			var dot := rows.get_child(0).get_child(0) as ColorRect
			_check(dot != null and dot.self_modulate == UiTheme.PAPER_MOSS, "开战满血的敌船布色珠 = 稳（灰青）")
	await _close(wm)
	Switches.reset()


func _sec_intel_off(fleet: Node) -> void:
	Switches.set_on("enemy_intel", false)
	var wm := await _battle(fleet, 80)
	var hud := _hud_of(wm)
	_check(hud != null and hud.get("_intel") == null, "enemy_intel 关：敌情列照旧不建（开战前玩法）")
	await _close(wm)
	Switches.reset()


# ── 二、布色 / 船种 / 行数的纯函数 ──────────────────────

func _sec_cloth_kind() -> void:
	# PirateShip.tscn 实例：ship_type / enemy_morale / struck 是脚本变量，鸭子型 get 都按真的走
	var e: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	e.set("ship_type", "pirate_boat")
	e.set("enemy_morale", 60)
	e.set("struck", false)
	_check(Hud.ship_type_word(e) == "快船", "pirate_boat 行内写「快船」：%s" % Hud.ship_type_word(e))
	_check(Hud.cloth_state(e) == "稳", "满士气 60、无簿：布色「稳」：%s" % Hud.cloth_state(e))
	e.set("enemy_morale", 25)
	_check(Hud.cloth_state(e) == "想退", "士气 25 落簿档：布色「想退」：%s" % Hud.cloth_state(e))
	e.set("enemy_morale", 8)
	_check(Hud.cloth_state(e) == "想退", "士气 8：布色「想退」：%s" % Hud.cloth_state(e))
	e.set("struck", true)
	_check(Hud.cloth_state(e) == "白帆", "节点 struck：布色「白帆」：%s" % Hud.cloth_state(e))
	_check(Hud.cloth_color("白帆") != Hud.cloth_color("稳"), "白帆珠色与稳的珠色不一样")
	e.free()
	var e2: Node = (load("res://scenes/PirateShip.tscn") as PackedScene).instantiate()
	e2.set("ship_type", "sea_falcon")
	e2.set("enemy_morale", 60)
	e2.set("struck", false)
	_check(Hud.ship_type_word(e2) == "海鹘", "sea_falcon 行内写「海鹘」：%s" % Hud.ship_type_word(e2))
	e2.free()


# ── 三、我方士气险档提示条 ──────────────────────────────

func _sec_morale_bar(fleet: Node) -> void:
	var wm := await _battle(fleet, 80)
	var hud := _hud_of(wm)
	if hud == null:
		_check(false, "海战场挂着状态条")
		await _close(wm)
		return
	for _i in 2:
		await process_frame
	var lbl: Label = hud.get("_morale_bar")
	_check(lbl != null, "enemy_intel 开：士气提示条 _morale_bar 已建")
	if lbl != null:
		(hud as Object).set("_morale_flag", 0)
		hud.call("_refresh_morale_bar", {"morale": 60.0})
		_check(not lbl.visible and lbl.text == "", "士气 60：提示条收起")
		hud.call("_refresh_morale_bar", {"morale": 18.0})
		_check(lbl.visible and lbl.text.contains("队里乱了"), "士气 18：提示条亮「队里乱了」：%s" % lbl.text)
		hud.call("_refresh_morale_bar", {"morale": 7.0})
		_check(lbl.visible and lbl.text.contains("白旗要挂出来了"), "士气 7：提示条亮「白旗要挂出来了」：%s" % lbl.text)
		hud.call("_refresh_morale_bar", {"morale": 70.0})
		_check(not lbl.visible and lbl.text == "", "士气 70：提示条收起、flag 落 0")
		(hud as Object).set("_morale_flag", 0)
	# 士气跨档只经 morale_urgency 纯函数（跟 HUD 里 refresh_morale_bar 走的同一支）：残骸、士气真值、flag 链三节
	var flag := 0
	var seq := [[70, ""], [18, "队里乱了"], [7, "白旗要挂出来了"], [32, ""], [18, "队里乱了"], [70, ""], [12, "队里乱了"], [7, "白旗要挂出来了"], [70, ""]]
	for pair in seq:
		var u: Dictionary = Hud.morale_urgency(float(pair[0]), flag)
		flag = int(u["flag"])
		_check(str(u["text"]) == str(pair[1]),
			"士气 %s → 提示 \"%s\"（要 \"%s\"）" % [str(pair[0]), str(u["text"]), str(pair[1])])
	# 关掉总开关：同一场跌到 18 也不提
	hud.set("switch_override", 0)
	_check(not bool(hud.call("_switch_on")), "switch_override=0 时 _switch_on() 为假（保驾护航探针用）")
	hud.set("switch_override", -1)
	await _close(wm)
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
