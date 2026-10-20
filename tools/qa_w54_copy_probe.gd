extends SceneTree
## lane w54-copy 文案一致性探针（headless，不截图；一段钉一条、回退即红）。
##   一、门牌悬停提示里的地名与门牌同字：守城那天（1276-11-03）进兴化，岸带上「囊山」门的悬停提示写囊山
##       （曾误作「南山下设伏。」——门牌、战报题「囊山・第N阵」、元军行事「前锋到囊山」都写囊山）；
##       岸带上门牌是专名的门（城中通名的九门与守城借用的衙门 / 市场除外），提示都原字写出门牌（「・」不计）。
## 静态一侧见 tools/check_w53_copy.py 钉 R；本探针看的是岸带上真建出来的门。
## 用法：godot --headless --path . -s res://tools/qa_w54_copy_probe.gd（经门锁跑）
## 判词：逐条「  ✓ / ✗ 判词」，末行 QA_W54_COPY_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W54_COPY_PROBE"
const VIEW := Vector2i(1280, 720)
## 守城借用的城中通名门：与九门一样，提示不必复述门牌（同 check_w53_copy 钉 R 的 TIP_COMMON_TITLES）
const COMMON_TITLES := ["衙门", "市场"]

var _fails: Array = []
var _main: Node
var gs: Node
var cal: Node
var fleet: Node
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时不会走到 _report——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	print("%s_BEGIN" % TAG)
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	cal = root.get_node("/root/Calendar")
	fleet = root.get_node("/root/Fleet")
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	_main = packed.instantiate() if packed != null else null
	if _main == null or _main.get_script() == null:
		_check(false, "Main.tscn 挂得出（根脚本无 Parse Error）")
		_report()
		return
	root.size = VIEW
	root.add_child(_main)
	for i in 6:
		await process_frame

	print("== 一、门牌悬停提示里的地名与门牌同字（守城那天的兴化岸带）")
	await _sec_door_tips()
	_report()


func _sec_door_tips() -> void:
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	await process_frame
	var common: Array = COMMON_TITLES.duplicate()
	for fac in _main.get("GENERIC_FACILITIES"):
		common.append(str((fac as Dictionary).get("title", "")))
	var doors := _doors()
	var titles := []
	var nangshan := ""
	for d in doors:
		var title := str(d[0])
		var tip := str(d[1])
		titles.append(title)
		if title == "囊山":
			nangshan = tip
		if title in common:
			continue
		_check(tip.replace("・", "").find(title.replace("・", "")) >= 0,
			"「%s」门的悬停提示写出门牌（「%s」）" % [title, tip])
	_check(nangshan != "", "守城那天兴化岸带上有「囊山」门（岸带上的门 %s）" % [titles])
	_check(nangshan.find("囊山") >= 0 and nangshan.find("南山") < 0,
		"「囊山」门的悬停提示写囊山、不写南山（「%s」）" % nangshan)


## 岸带上的门：[门牌, 悬停提示]，按树序
func _doors() -> Array:
	var out := []
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	var doors: Node = band.get_node_or_null("ShoreDoors") if band != null else null
	if doors == null:
		return out
	for d in doors.get_children():
		if (d as Node).is_queued_for_deletion():
			continue
		if d is Button:  # 关着的门（_make_shore_shut）：钮字即门牌
			out.append([(d as Button).text, (d as Button).tooltip_text])
			continue
		var cols := (d as Node).find_children("*", "VBoxContainer", true, false)
		var head: Node = (cols[0] as Node).get_child(0) if not cols.is_empty() and (cols[0] as Node).get_child_count() > 0 else null
		var btns := (d as Node).find_children("*", "Button", true, false)
		var tip: String = (btns[0] as Button).tooltip_text if not btns.is_empty() else ""
		out.append([(head as Label).text if head is Label else "", tip])
	return out


## 守城那天：士人线改名文龙、在兴化、一条小艍（同 qa_w53_p5_siege_probe 的布景）
func _stage_siege(y: int, m: int, d: int) -> void:
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	gs.money = 20000
	gs.fame = 30
	gs.last_port = "xinghua"
	cal.from_dict({"year": y, "month": m, "day": d})
	root.get_node("/root/Crew").from_dict({})
	fleet.ships = []
	fleet.add_ship("sampan", "无名小艍")
	fleet.water = 60
	fleet.food = 60
	fleet.morale = 70


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)
