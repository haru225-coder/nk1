extends SceneTree
## lane-w54-ending：升章册页「这一路」那句主航线写成纪实句，不夹箭头。
## 跳年摘要（ChapterSheet.era_summary_lines）原写「这两年，你的船跑了四趟，走得最多的是泉州→流求。」——主航线照账里的键
## （GameState.era_routes「泉州→流求」）原样上屏，纪实短句里夹一枚界面箭头。账里的键不动（存档同形），上屏写「泉州到流求那一程」。
##   A 真记四趟航行（GameState.record_trip，同海图抵港那一处）、真开第二章：册页「这一路」写「走得最多的是泉州到<港>那一程」，
##     整页正文不出「→」；账里的键照旧是「泉州→<港>」。
##   R 反向基：只跑过、没记起讫港的一章，照旧只写「你的船跑了几趟」。
## 用法：godot --headless --path . -s res://tools/qa_w54_ending_era_line_probe.gd（经门锁跑）
## 末行 W54_ENDING_ERA_LINE cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CH1_PORTS := ["quanzhou", "xinghua", "fuzhou", "penghu", "ryukyu"]

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _gm: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	_gm = root.get_node_or_null("GameManager")
	if _gs == null or _cal == null or _fleet == null or _gm == null:
		_expect(false, "autoload GameState / Calendar / Fleet / GameManager 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_route()
	await _r_no_route()
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ENDING_ERA_LINE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame
	await process_frame


## 第一章够开第二章的一局（宝祐四年六月、流求）：本钱、走过的港齐了，还没进港
func _fresh() -> void:
	await _drop_sheet()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	for e in _main._beats_book().entries():
		_gs.beat_mark(e)
	_cal.from_dict({"year": 1256, "month": 6, "day": 2})
	_gs.identity = "merchant"
	_gs.chapter = 1
	_gs.peak_money = 6000
	_gs.money = 6000
	_gs.visited_ports = CH1_PORTS.duplicate()
	_gs.last_port = "ryukyu"
	_fleet.water = 200
	_fleet.food = 200


func _sheet_text() -> String:
	var host = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return ""
	var body: Node = host.find_child("SheetScroll", true, false)
	var labels := body.find_children("*", "Label", true, false) if body != null else []
	return str((labels[0] as Label).text) if not labels.is_empty() else ""


# ── A 记了起讫港的四趟 ───────────────────────────────────

func _a_route() -> void:
	print("── A 真记四趟、真开第二章：主航线写「泉州到<港>那一程」、正文不夹箭头")
	await _fresh()
	for i in 3:
		_gs.record_trip("quanzhou", "ryukyu")
	_gs.record_trip("ryukyu", "quanzhou")
	var qz: String = _gm.get_port_name("quanzhou")
	var ry: String = _gm.get_port_name("ryukyu")
	_expect(_gs.era_routes.has("%s→%s" % [qz, ry]), "账里的键照旧是「%s→%s」（存档同形）" % [qz, ry])
	_main.load_scene("ryukyu")
	await process_frame
	var text := _sheet_text()
	_expect(int(_gs.chapter) == 2 and text.find("这一路") >= 0, "开第二章：册页有「这一路」一截（第%d章）" % int(_gs.chapter))
	var want := "这两年，你的船跑了四趟，走得最多的是%s到%s那一程。" % [qz, ry]
	_expect(text.find(want) >= 0, "「这一路」写「%s」" % want)
	_expect(text.find("→") < 0, "整页正文不出「→」")


# ── R 没记起讫港 ─────────────────────────────────────────

func _r_no_route() -> void:
	print("── R 反向基：只记趟数、没记起讫港，照旧只写跑了几趟")
	await _fresh()
	_gs.record_trip("", "")
	_gs.record_trip("", "")
	_main.load_scene("ryukyu")
	await process_frame
	var text := _sheet_text()
	_expect(text.find("这两年，你的船跑了两趟。") >= 0 and text.find("走得最多") < 0, "「这一路」只写「这两年，你的船跑了两趟。」")
