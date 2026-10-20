extends SceneTree
## lane-w54-ending：终局抉择页与结局页里回指开局的「N 年前」，按开局那一年（Calendar 起点，宝祐三年 1255）算得上。
## 士人线辞呈页（德祐元年腊月，Main._on_resign_1275）原写「箧里是十三年前那本夹着货引的《论语》」——货引是序章兴化海口
## 酒棚里那一枚，到德祐元年是二十年；同页三条去向写「二十年前阿那教过你怎么看」「泉州。二十年。」。「十三年」是幕本
## 1268 那一幕（1255→1268）的数，搬进 1275 没改。
##   A 辞呈页（真开岸上「临安・辞呈批语」卡）：正文里每处「N年前」= 本年 − 开局年；正文点到货引那一句。
##     三条去向逐条真点，册页正文里每处「N年前」同算（不回头「二十年前阿那」、车转向南「二十年前你叔父那笔债」）。
##   B 涵江出海（景炎二年）：结局册页「二十二年前，一个舵手教过你」、结局过场同句，按本年 − 开局年算得上。
## 用法：godot --headless --path . -s res://tools/qa_w54_ending_years_probe.gd（经门锁跑）
## 末行 W54_ENDING_YEARS cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const DIGIT := {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _tally: ScriptErrTally
var _reported := false
var _start_year := 0
var _re := RegEx.new()


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
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		return
	_re.compile("([零一二两三四五六七八九十]+)年前")
	# 开局那一年：新开一局的历法起点
	_cal.from_dict({})
	_start_year = int(_cal.year)
	_expect(_start_year == 1255, "开局年取历法起点（%d）" % _start_year)
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_resign()
	await _b_hanjiang()
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ENDING_YEARS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame


func _fresh(y: int, m: int, port: String, identity: String) -> void:
	await _drop_sheet()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_cal.from_dict({"year": y, "month": m, "day": 2})
	_gs.identity = identity
	_gs.last_port = port
	_gs.money = 3000
	_fleet.water = 200
	_fleet.food = 200


## 中文小数目（零至九十九）→ 整数
func _cn(s: String) -> int:
	if s.find("十") < 0:
		return int(DIGIT.get(s, -1))
	var parts := s.split("十")
	var tens: int = 1 if parts[0] == "" else int(DIGIT.get(parts[0], -100))
	var ones: int = 0 if parts[1] == "" else int(DIGIT.get(parts[1], -100))
	return tens * 10 + ones


## 文中每处「N年前」的 N
func _spans(text: String) -> Array:
	var out := []
	for m in _re.search_all(text):
		out.append(_cn(m.get_string(1)))
	return out


func _all_eq(spans: Array, want: int) -> bool:
	for n in spans:
		if int(n) != want:
			return false
	return true


func _sheet_text() -> String:
	var host = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return ""
	var body: Node = host.find_child("SheetScroll", true, false)
	var labels := body.find_children("*", "Label", true, false) if body != null else []
	return str((labels[0] as Label).text) if not labels.is_empty() else ""


func _open_resign() -> void:
	await _fresh(1275, 12, "xinghua", "scholar")
	_gs.player_name = "陈文龙"
	_gs.set_flag("renamed_wenlong")
	_gs.set_flag("vice_councillor")
	_main.load_scene("xinghua")
	await process_frame
	_main._on_facility_pressed({"id": "special_resign_1275"})
	await process_frame


# ── A 辞呈页与三条去向 ───────────────────────────────────

func _a_resign() -> void:
	print("── A 辞呈页（德祐元年腊月）与三条去向：「N年前」按开局年算")
	await _open_resign()
	var want: int = int(_cal.year) - _start_year
	var body := str(_main.body_text.text)
	var spans := _spans(body)
	_expect(str(_main.scene_title.text) == "临安・嘉会门" and body.find("货引") >= 0, "辞呈页开着、正文点到货引（%s）" % _main.scene_title.text)
	_expect(not spans.is_empty() and _all_eq(spans, want),
		"辞呈页正文每处「N年前」= %d − %d = %d（文中 %s）" % [int(_cal.year), _start_year, want, str(spans)])
	for spec in [["回头", 0], ["不回头", 1], ["车转向南", 1]]:
		var pick: String = spec[0]
		await _open_resign()
		var btn: Button = null
		for c in _main.choices_container.get_children():
			if c is Button and str((c as Button).text).begins_with(pick):
				btn = c
		_expect(btn != null, "辞呈页有「%s」那一条" % pick)
		if btn == null:
			continue
		btn.pressed.emit()
		await process_frame
		var s := _spans(_sheet_text())
		_expect(s.size() >= int(spec[1]) and _all_eq(s, want),
			"「%s」册页正文每处「N年前」= %d（文中 %s）" % [pick, want, str(s)])


# ── B 涵江出海 ───────────────────────────────────────────

func _b_hanjiang() -> void:
	print("── B 涵江出海（景炎二年）：「二十二年前，一个舵手教过你」按开局年算")
	await _fresh(1277, 9, "xinghua", "hometown")
	_gs.discoveries_found = ["nameless_shelter_bay"]
	_main.load_scene("xinghua")
	await process_frame
	_main._on_facility_pressed({"id": "special_hanjiang_escape"})
	await process_frame
	var want: int = int(_cal.year) - _start_year
	var s := _spans(_sheet_text())
	_expect(str(_gs.ended) == "岸上的根" and not s.is_empty() and _all_eq(s, want),
		"「岸上的根」册页正文每处「N年前」= %d（文中 %s）" % [want, str(s)])
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes.json"))
	var cid := str(((data as Dictionary).get("endings", {}) as Dictionary).get("岸上的根", ""))
	var caps := ""
	for shot in ((data as Dictionary).get("cutscenes", {}) as Dictionary).get(cid, {}).get("shots", []):
		for c in (shot as Dictionary).get("captions", []):
			caps += str((c as Dictionary).get("text", "")) + "\n"
	var cs := _spans(caps)
	_expect(not cs.is_empty() and _all_eq(cs, want), "「岸上的根」结局过场（%s）每处「N年前」= %d（文中 %s）" % [cid, want, str(cs)])
