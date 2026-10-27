extends SceneTree
## lane tut2 玩家引导（札记）探针（headless，经门锁跑）。
## 断言：四条札记 id/文案/开关；触发后读旗。
## 判词：末行 QA_W57_TUT PASS|FAIL cases=N fails=K。

const TAG := "QA_W57_TUT"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var Book
var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _ids := ["districts", "invest_shop", "flag_chain", "seasonal_price"]


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


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	Book = load("res://scripts/core/Districts.gd")
	if Book == null:
		_check(false, "城区账本没载入")
		_report()
		return
	_stage_boot()
	print("== 一、札记表")
	_sec_table()
	print("== 二、触发与读旗")
	await _sec_triggers()
	_report()


func _stage_boot() -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.last_port = "quanzhou"
	Book.wipe()


func _fresh() -> void:
	Book.wipe()
	gs.money = 30000
	gs.contract = {}
	gs.siege = {}
	gs.flags = {}
	gs.identity = "undecided"
	gs.player_name = "陈子龙"
	gs.pu_attention = 0
	gs.merchant_credit = 0
	gs.scholar_tendency = 0
	gs.hometown_tendency = 0
	gs.network = 0
	gs.fame = 0
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _settle(n: int) -> void:
	for _i in n:
		await process_frame

func _drop_notes() -> void:
	var layer = _main.get_node_or_null("CombatNotes")
	if layer != null:
		layer.queue_free()
	await _settle(3)


func _sec_table() -> void:
	var txt := FileAccess.get_file_as_string("res://data/combat_notes.json")
	var parsed = JSON.parse_string(txt)
	_check(typeof(parsed) == TYPE_DICTIONARY, "表是字典")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var notes: Array = parsed.get("notes", [])
	var by_id := {}
	for n in notes:
		if typeof(n) == TYPE_DICTIONARY:
			by_id[str(n.get("id", ""))] = n
	for id in _ids:
		var e = by_id.get(id, null)
		_check(e != null, "有札记 %s" % id)
		if e == null:
			continue
		_check(str(e.get("text", "")) != "" and str(e.get("text", "")).ends_with("。"), "文案 %s 非空句号收尾" % id)
		_check(str(e.get("switch", "x")) == "", "开关 %s 为空（只认总开关）" % id)
	var CN := load("res://scripts/ui/CombatNotes.gd")
	_check(CN != null, "CombatNotes 可载")
	if CN != null:
		for id in _ids:
			_check(CN.entry(id).has("id"), "entry 可取 %s" % id)


func _sec_triggers() -> void:
	# instantiate Main for host
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.money = 30000
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	_fresh()
	gs.loaded_with_beats = true
	for b2 in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b2 as Dictionary).get("entry", "")))
	gs.money = 30000
	_main.load_scene("quanzhou")
	await _settle(6)

	# districts
	gs.flags = {}
	await _drop_notes()
	_main._open_districts()
	await _settle(12)
	_check(gs.has_flag("combat_note_districts"), "districts 触发读旗")

	# invest_shop
	_fresh()
	gs.loaded_with_beats = true
	for b3 in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b3 as Dictionary).get("entry", "")))
	gs.money = 30000
	_main.load_scene("quanzhou")
	await _settle(6)
	var stall := _ix("qz_citong_stall")
	await _drop_notes()
	var r1: Dictionary = Book.apply("qz_citong_stall")
	_check(bool(r1.get("ok", false)), "invest 触发前置成功")
	await _settle(12)
	_check(gs.has_flag("combat_note_invest_shop"), "invest_shop 触发读旗")

	# flag_chain
	_fresh()
	gs.loaded_with_beats = true
	for b4 in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b4 as Dictionary).get("entry", "")))
	gs.money = 30000
	_main.load_scene("quanzhou")
	await _settle(6)
	await _drop_notes()
	var r2: Dictionary = Book.apply("qz_houzhu_pilot")
	_check(bool(r2.get("ok", false)), "flag 触发前置成功")
	await _settle(12)
	_check(gs.has_flag("combat_note_flag_chain"), "flag_chain 触发读旗")

	# seasonal_price
	gs.flags = {}
	_check(not is_equal_approx(eco.seasonal_mul("grain", 3), 1.0), "grain 节令倍数非 1")
	await _drop_notes()
	_main._offer_season_note("grain")  # 成交后挂（_on_buy / _on_sell 同一行调用）
	await _settle(12)
	_check(gs.has_flag("combat_note_seasonal_price"), "seasonal_price 触发读旗")
	gs.flags = {}
	await _drop_notes()
	_main._offer_season_note("pepper")
	await _settle(12)
	_check(is_equal_approx(eco.seasonal_mul("pepper", 3), 1.0) and not gs.has_flag("combat_note_seasonal_price"), "不随节令的货（胡椒）不出节令旁注")


func _ix(id: String) -> Dictionary:
	return Book.interaction(id)
