extends SceneTree
## lane ui2 城中各处 UI 可用性探针（headless，经门锁跑）。
##   godot --headless --path . -s res://tools/qa_w57_districtui_probe.gd
## 断言：名单按类分组、事页按类分组、钮带花费/冷却/条件提示、悬停提示不空。
const TAG := "QA_W57_DISTRICTUI"
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
	await _sec_ui()
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


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n as Button
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _collect_nodes(n: Node, name: String, out: Array) -> void:
	if n.name == name:
		out.append(n)
	for c in n.get_children():
		_collect_nodes(c, name, out)


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_collect_labels(c, out)


func _sec_ui() -> void:
	_fresh()
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
	var door := _find_button(_main, "城中各处")
	_check(door != null, "UI：泉州港页有城中各处")
	if door == null:
		return
	door.pressed.emit()
	await _settle(4)
	_check(str(_main.scene_title.text) == "城中各处", "UI：名单题头是城中各处")
	var headers: Array = []
	_collect_nodes(_main, "DistrictGroupHeader", headers)
	_check(headers.size() >= 2, "UI：名单按类分组（%d 组）" % headers.size())
	var into := _find_button(_main, "进去")
	_check(into != null and str(into.tooltip_text) != "", "UI：进去钮带悬停提示")
	if into == null:
		return
	into.pressed.emit()
	await _settle(4)
	_check(str(_main.get("_bg_file")) == "bg_dist_qz_houzhu.jpg", "UI：进入后渚")
	var headers2: Array = []
	_collect_nodes(_main, "DistrictGroupHeader", headers2)
	_check(headers2.size() >= 1, "UI：事页按类分组（%d 组）" % headers2.size())
	var btns: Array = []
	_collect_buttons(_main, btns)
	var tip_ok := false
	for b in btns:
		if str((b as Button).tooltip_text) != "":
			tip_ok = true
			break
	_check(tip_ok, "UI：事钮带悬停提示")
	var labels: Array = []
	_collect_labels(_main, labels)
	var cd_ok := false
	for lb in labels:
		if str((lb as Label).text).contains("可再办"):
			cd_ok = true
			break
	_check(cd_ok, "UI：冷却提示落字")
	var cost_ok := false
	for b in btns:
		if str((b as Button).tooltip_text).contains("费"):
			cost_ok = true
			break
	_check(cost_ok, "UI：花费提示落字")
PYEOF
echo done