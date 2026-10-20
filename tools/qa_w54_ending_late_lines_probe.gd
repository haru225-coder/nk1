extends SceneTree
## lane-w54-ending：章节过渡页写到的人此刻已不在世，就不再写他在场。
## 林阿舶 1274 病故（characters.json died；人物志小传 1274 起写「咸淳十年前后病故」，泉州酒馆此后不再摆他——CharacterArt.deceased）。
## 第一章开第二章的册页正文写「林阿舶把一只油布包推过案来」，第二章开第三章的晋升过场幕写「林阿舶在廊下等你」：
## 开章晚到 1274 以后（士人线不跑船，或前两章耽久了；跳年封顶 1275 也落在这几年），原先照样这么写。
##   A 第二章开第三章晚了（1272 开章跳三年到 1275、1275 开章封顶不跳）：真进泉州开章、按「承此一路」进晋升过场幕，
##     幕正文不写林阿舶在廊下等你、写他已经不在了；此刻人物志判他已不在世（同一判法）。
##   B 第一章开第二章跨过卒年（1272 开章跳两年到 1274）：册页正文跳年后现判——不写林阿舶推油布包、写他已经不在了；
##     1275 开章封顶不跳，按当年判同。
##   R 反向基：1262 开第三章、1257 开第二章、1271 开第二章跳到 1273（卒年前一年），照旧写林阿舶本人，一字不改。
## 用法：godot --headless --path . -s res://tools/qa_w54_ending_late_lines_probe.gd（经门锁跑）
## 末行 W54_ENDING_LATE_LINES cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PARCEL := "林阿舶把一只油布包推过案来，没有解绳。"
const PORCH := "林阿舶在廊下等你，没有道喜，只说广州那边有人问过你的船。"
const GONE := "林阿舶已经不在了。"
const CH1_PORTS := ["quanzhou", "xinghua", "fuzhou", "penghu", "ryukyu"]
const CH2_PORTS := ["quanzhou", "xinghua", "fuzhou", "zhangzhou", "wenzhou", "penghu", "ryukyu", "mingzhou", "hakata"]

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _gm: Node
var _tally: ScriptErrTally
var _reported := false
## 人物志的判法件：它直读 autoload，-s 工具里 preload 编不过，_boot 里再 load
var _char_art: GDScript = null


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
	_char_art = load("res://scripts/ui/CharacterArt.gd") as GDScript
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_chapter3()
	await _b_chapter2()
	await _r_controls()
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ENDING_LATE_LINES cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame
	await process_frame


## 够开下一章的一局：本章号、开章那一年、所在港、走过的港、本钱
func _ready_to_advance(chapter: int, year: int, port: String, ports: Array, peak: int) -> void:
	await _drop_sheet()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	for e in _main._beats_book().entries():
		_gs.beat_mark(e)
	_cal.from_dict({"year": year, "month": 6, "day": 2})
	_gs.identity = "merchant"
	_gs.chapter = chapter
	_gs.peak_money = peak
	_gs.money = peak
	_gs.visited_ports = ports.duplicate()
	_gs.last_port = port
	_fleet.water = 200
	_fleet.food = 200
	_main.load_scene(port)
	await process_frame


func _sheet_text() -> String:
	var host = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return ""
	var body: Node = host.find_child("SheetScroll", true, false)
	var labels := body.find_children("*", "Label", true, false) if body != null else []
	return str((labels[0] as Label).text) if not labels.is_empty() else ""


func _lin_gone() -> bool:
	return bool(_char_art.call("deceased", _gm.get_character("merchant_lin")))


## 开第三章：册页弹出、按「承此一路」进晋升过场幕，返回幕正文
func _chapter3_scene_body(year: int) -> String:
	await _ready_to_advance(2, year, "quanzhou", CH2_PORTS, 30000)
	_expect(int(_gs.chapter) == 3 and _sheet_text() != "", "%d 年泉州开第三章：册页弹出（第%d章）" % [year, int(_gs.chapter)])
	await _drop_sheet()
	_expect(str(_main.current_scene_id) == "chapter3_gangshou", "%d 年开章：「承此一路」进晋升过场幕（%s，%d 年）" % [year, _main.current_scene_id, int(_cal.year)])
	return str(_main.body_text.text)


# ── A 第二章开第三章晚了 ─────────────────────────────────

func _a_chapter3() -> void:
	print("── A 第二章开第三章晚到林阿舶卒年以后：晋升过场幕不写他在廊下等你")
	for y in [1272, 1275]:
		var body := await _chapter3_scene_body(y)
		_expect(_lin_gone(), "%d 年开章落在 %d 年：人物志判林阿舶已不在世" % [y, int(_cal.year)])
		_expect(body.find(PORCH) < 0 and body.find(GONE) >= 0 and body.find("林家账房的人在廊下等你") >= 0,
			"%d 年开章：幕正文不写「%s」，写他已经不在了、林家账房的人在廊下等你" % [y, PORCH])
		_expect(body.find("「纲首」二字") >= 0, "%d 年开章：幕正文其余照旧（「纲首」二字那句在）" % y)


# ── B 第一章开第二章跨过卒年 ─────────────────────────────

func _b_chapter2() -> void:
	print("── B 第一章开第二章跳年跨过林阿舶卒年：册页正文跳年后现判")
	await _ready_to_advance(1, 1272, "ryukyu", CH1_PORTS, 6000)
	var text := _sheet_text()
	_expect(int(_gs.chapter) == 2 and int(_cal.year) == 1274, "1272 年开第二章跳两年落在 %d 年（第%d章）" % [int(_cal.year), int(_gs.chapter)])
	_expect(text.find(PARCEL) < 0 and text.find(GONE) >= 0 and text.find("林家账房的人把一只油布包推过案来") >= 0,
		"跳年落在卒年：册页不写「%s」，写他已经不在了、林家账房的人推过油布包" % PARCEL)
	_expect(text.find("「唐房那边的旧账，总要有人去对。」") >= 0 and text.find("【两年后・") >= 0,
		"册页其余照旧（唐房旧账那句、「两年后」那一截都在）")
	# 德祐元年开章：跳年封顶不跳，册页正文按当年判
	await _ready_to_advance(1, 1275, "ryukyu", CH1_PORTS, 6000)
	text = _sheet_text()
	_expect(int(_gs.chapter) == 2 and int(_cal.year) == 1275 and text.find("年后・") < 0, "1275 年开第二章：跳年封顶不跳（%d 年）" % int(_cal.year))
	_expect(text.find(PARCEL) < 0 and text.find(GONE) >= 0, "不跳年也按当年判：册页不写「%s」、写他已经不在了" % PARCEL)


# ── R 反向基 ─────────────────────────────────────────────

func _r_controls() -> void:
	print("── R 反向基：林阿舶在世的年份照旧写他本人")
	var body := await _chapter3_scene_body(1262)
	_expect(not _lin_gone() and body.find(PORCH) >= 0 and body.find(GONE) < 0, "1262 年开第三章：幕正文照旧「%s」" % PORCH)
	for y in [1257, 1271]:
		await _ready_to_advance(1, y, "ryukyu", CH1_PORTS, 6000)
		var text := _sheet_text()
		_expect(int(_gs.chapter) == 2 and not _lin_gone() and text.find(PARCEL) >= 0 and text.find(GONE) < 0,
			"%d 年开第二章（跳到 %d 年）：册页照旧「%s」" % [y, int(_cal.year), PARCEL])
