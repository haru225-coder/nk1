extends SceneTree
## lane w54-tutorial 船屋「补给」那一行探针（headless，经门锁跑）：
##   godot --headless --path . -s res://tools/qa_w54_tutorial_supply_line_probe.gd
## 船屋「补给」题签旁那一行原写「水 1　粮 9　每日耗 3」——两个数是单价，字面读作存量（顶匾同时写「水粮 26 日」，新手当是舱里只剩
## 一份水、九份粮）。真起 Main、进泉州船屋（开局光景）：
##   一、那一行写明单价与日耗的单位：「水每份 1 钱　粮每份 <牙行米价> 钱　每日各耗 <全队日耗> 份」，数与取数处同（水 1、粮按本港米粮买价、
##       日耗 Fleet.daily_supply_use）；一行放得下（不比补给卡宽）。
##   二、同一张卡上的钮与买后记事对得上这一行：「水粮各 30　付 N」N = 30 ×（水价 + 粮价），按下记事写「补入水 30 份、粮 30 份，付 N 钱」，
##       钱照扣、水粮各加 30。
## 判词：末行 QA_W54_TUTORIAL_SUPPLY_LINE PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_TUTORIAL_SUPPLY_LINE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _find(n: Node, pred: Callable) -> Node:
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _run() -> void:
	await process_frame
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	cine.set("auto_opening", false)
	cine.set("opening_seen", true)
	var gs := root.get_node("GameState")
	var gm := root.get_node("GameManager")
	var fleet := root.get_node("Fleet")
	var eco := root.get_node("Economy")
	gs.call("from_dict", {})
	gs.set("chapter", 1)
	gs.set("money", 940)
	gs.set("last_port", "quanzhou")
	gs.set("visited_ports", ["quanzhou"])
	gs.set("loaded_with_beats", true)
	for b in gm.get("port_beats_data").get("beats", []):
		gs.call("beat_mark", str((b as Dictionary).get("entry", "")))
	root.get_node("Calendar").call("from_dict", {"year": 1255, "month": 3, "day": 1})
	fleet.call("from_dict", {"ships": [{"type": "sampan", "name": "无名小艍", "durability": 120.0, "max_durability": 120.0,
		"crew": 6, "sail_level": 1, "armor_level": 1, "cargo": {}}], "water": 80, "food": 80, "morale": 70})
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for _i in 3:
		await process_frame
	main.call("load_scene", "quanzhou_shipyard")
	for _i in 3:
		await process_frame

	print("== 一、「补给」那一行写明单价与日耗的单位")
	var grain := int(eco.call("buy_price", "quanzhou", "grain"))
	var use := int(fleet.call("daily_supply_use"))
	var want := "水每份 1 钱　粮每份 %d 钱　每日各耗 %d 份" % [grain, use]
	var title: Label = _find(main, func(n): return n is Label and (n as Label).text == "补给" and (n as Label).is_visible_in_tree()) as Label
	_check(title != null, "船屋页上有「补给」那张卡")
	var line: Label = null
	if title != null:
		var body := title.get_parent()
		var at := title.get_index()
		if at + 1 < body.get_child_count() and body.get_child(at + 1) is Label:
			line = body.get_child(at + 1) as Label
	var got := line.text if line != null else ""
	_check(got == want, "题签旁那一行：「%s」（应「%s」）" % [got, want])
	_check(line != null and line.get_line_count() == 1, "一行放得下，不折行（%d 行）" % (line.get_line_count() if line != null else -1))

	print("== 二、钮与买后记事对得上这一行")
	var cost := 30 * (1 + grain)
	var chip: Button = _find(main, func(n): return n is Button and (n as Button).text == "水粮各 30　付 %d" % cost) as Button
	_check(chip != null, "钮「水粮各 30　付 %d」= 30 ×（水 1 + 粮 %d）" % [cost, grain])
	if chip != null:
		var money0 := int(gs.get("money"))
		var water0 := int(fleet.get("water"))
		var food0 := int(fleet.get("food"))
		chip.pressed.emit()
		for _i in 3:
			await process_frame
		var logs: PackedStringArray = main.get("_log_lines")
		var top := logs[0] if not logs.is_empty() else ""
		_check(top.begins_with("补入水 30 份、粮 30 份，付 %d 钱。" % cost), "按下记事：「%s」" % top)
		_check(int(gs.get("money")) == money0 - cost and int(fleet.get("water")) == water0 + 30 and int(fleet.get("food")) == food0 + 30,
			"钱 %d → %d、水 %d → %d、粮 %d → %d" % [money0, int(gs.get("money")), water0, int(fleet.get("water")), food0, int(fleet.get("food"))])
	main.queue_free()
	current_scene = null
	for _i in 2:
		await process_frame
	_report()
