extends SceneTree
## lane w54-a11y 焦点看得见探针（headless，经门锁跑；真起 Main、真按 Tab）。
##   godot --headless --path . -s res://tools/qa_w54_a11y_focus_ring_probe.gd
## 病：Tab 落在岸上的门上屏上毫无痕迹——三扇开着的门，门上那颗覆盖钮的焦点样式是空框（StyleBoxEmpty）；「今日未开」那一排门、
## 牙行「今日不在柜上」那一排货名，焦点样式与平常同一个框（焦点框画在钮上面，同一个框叠一层等于没画）。港页 Tab 一圈前九站、
## 牙行页二十几站，键盘玩家看不出焦点停在哪。
## 断言（泉州，景定三年五月初一，一艘客舟、钱三万）：港页与九处设施页（牙行 / 市舶司 / 船屋 / 酒馆 / 旅店 / 行会 / 贡院 / 住处 /
## 寺观）各从无焦点起按 Tab 绕一整圈，每一站：焦点是画框的那份（has_focus(true)），且这颗钮的焦点样式不是空框、也不是它平常那个框。
## 另核岸门、未开的门、牙行不在柜上的货名三样的焦点样式各自不空、不同平常（覆盖一圈 Tab 之外摆着的同类钮）。
## 判词：末行 QA_W54_A11Y_FOCUS_RING PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。
## 回退即红：Main._make_shore_door 的 focus 换回空框 → 港页一圈、岸门两格红；_make_shore_shut / 牙行 BrokerShut 的 focus 换回
## shut_box → 港页 / 牙行页一圈与对应一格红。

const TAG := "QA_W54_A11Y_FOCUS_RING"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PORT := "quanzhou"
const PAGES := ["market", "yamen", "shipyard", "tavern", "inn", "guild", "exam", "residence", "temple"]

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
	_stage()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	print("== 港页 Tab 一圈")
	_main.load_scene(PORT)
	await _settle(4)
	await _ring("港页")
	_kinds_port()
	for suffix in PAGES:
		print("== %s Tab 一圈" % suffix)
		_main.load_scene(PORT)
		await _settle(3)
		_main.load_scene("%s_%s" % [PORT, suffix])
		await _settle(4)
		await _ring("%s_%s" % [PORT, suffix])
		if suffix == "market":
			_kinds_market()
	_report()


func _stage() -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.last_port = PORT


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await process_frame
	await process_frame


func _label(c: Control) -> String:
	if c == null:
		return "（无）"
	if c is Button and (c as Button).text != "":
		return "「%s」" % (c as Button).text
	var titles := PackedStringArray()
	if c.get_parent() != null:
		for l in c.get_parent().find_children("*", "Label", true, false):
			if (l as Label).text.length() >= 2:
				titles.append((l as Label).text)
	return "%s%s" % [c.get_class(), "「%s」门" % titles[0] if not titles.is_empty() else ""]


## 焦点框看得见：画在钮上面的那层焦点样式不是空框，也不是它平常那个框（同一个框再叠一层等于没画）
func _ring_shows(c: Control) -> bool:
	var focus := c.get_theme_stylebox("focus")
	if focus == null or focus is StyleBoxEmpty:
		return false
	var normal := c.get_theme_stylebox("normal") if c is Button else null
	return focus != normal


## 从无焦点起按 Tab 绕一整圈（回到第一站为止，至多 120 下），每站都要画框且看得见
func _ring(page: String) -> void:
	root.gui_release_focus()
	var first: Control = null
	var stops := 0
	var dim := PackedStringArray()
	var hidden := 0
	for _i in 120:
		await _tap(KEY_TAB)
		var f := root.gui_get_focus_owner()
		if f == null:
			break
		if first == null:
			first = f
		elif f == first:
			break
		stops += 1
		if not f.has_focus(true):
			hidden += 1
		if not _ring_shows(f):
			if dim.size() < 8:
				dim.append(_label(f))
			else:
				dim.append("…")
	_check(stops > 0, "%s Tab 一圈有站（%d 站）" % [page, stops])
	_check(hidden == 0, "%s 一圈每站都是画框的焦点（不画框 %d 站）" % [page, hidden])
	_check(dim.is_empty(), "%s 一圈每站焦点框看得见（看不见：%s）" % [page, "无" if dim.is_empty() else "、".join(dim)])


func _kinds_port() -> void:
	var doors: Array = []
	var row: Node = _main.find_child("ShoreDoors", true, false)
	if row != null:
		doors = row.find_children("*", "Button", true, false)
	var shut: Array = []
	var srow: Node = _main.find_child("ShoreShut", true, false)
	if srow != null:
		shut = srow.find_children("*", "Button", true, false)
	_check(doors.size() == 3 and doors.all(func(b): return _ring_shows(b)), "岸上三扇开着的门焦点框看得见（%d 扇）" % doors.size())
	_check(not shut.is_empty() and shut.all(func(b): return _ring_shows(b)), "「今日未开」那一排门焦点框看得见（%d 扇）" % shut.size())


func _kinds_market() -> void:
	var shut: Array = []
	var srow: Node = _main.find_child("BrokerShut", true, false)
	if srow != null:
		shut = srow.find_children("*", "Button", true, false)
	_check(not shut.is_empty() and shut.all(func(b): return _ring_shows(b)), "牙行「今日不在柜上」那一排货名焦点框看得见（%d 样）" % shut.size())
