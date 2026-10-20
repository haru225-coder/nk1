extends SceneTree
## lane-w54-ending：「海上宋鬼」结局过场按这一局崖山实际走的那条路出字。
## 结局过场（data/cutscenes.json ending_sea_ghost）原先只有一套字幕：第 1 镜「你把粮与硫黄交上去，船留在外围。」、
## 第 2 镜「你砍断了自己的缆。」。w53-p6-yashan 加了「上船同去」那扇门（打一场雾里有火船的突围战），册页正文按
## 冲出 / 没冲出换了句，过场没跟——走「上船同去」的人粮没交、船没留在外围、也没有缆可砍，过场照样这么演，演完弹出的
## 册页写的却是「你在雾里把舵压到底」/「火船顺风来的时候你没躲开」。交粮那条路船慢砍缆砍晚了的，册页写「烧了半条船」，
## 过场只有「你砍断了自己的缆」。
##   A 交粮三路（泉州借过船船快 / 船快 / 船慢）：真按崖山页的钮。第 1 镜写交粮、第 2 镜写砍缆；船慢那一路另补
##     「砍晚了。火从上风头卷过来，烧了半条船。」，船快两路不补、三镜字幕逐句同原先那一套。
##   B 上船同去两路（冲出 / 没冲出）：真开突围那一仗（WorldMap 挂上港页），真走 WorldMap._battle_exit 收战（两枚旗由
##     _yashan_settle 立），第 1 镜写「没有把船留在外围，上船跟着冲」、第 2 镜写册页里那一句，不写交粮、不写砍缆。
##   C 每一路：第 1、2 镜换句那一格（同 t）各只出一句；第 2 镜那一句的字（去标点）在这一局的册页正文里。
## 字幕出不出照 CutscenePlayer._caption_on 判（真播放器那一支，不另抄判法）。
## 用法：godot --headless --path . -s res://tools/qa_w54_ending_yashan_cine_probe.gd（经门锁跑）
## 末行 W54_ENDING_YASHAN_CINE cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Player := preload("res://scripts/cutscene/CutscenePlayer.gd")
const VIEW := Vector2i(1280, 720)
const JOIN := "你把粮与硫黄交上去，船留在外围。"
const BOARD := "你没有把船留在外围，上船跟着冲。"
const CUT := "你砍断了自己的缆。"
const CUT_LATE := "砍晚了。火从上风头卷过来，烧了半条船。"
const OUT := "你在雾里把舵压到底。"
const BURNT := "火船顺风来的时候，你没躲开。"
## 船快交粮那一路三镜原先的字幕（不含台江那一镜），一句不许变
const OLD_FAST := [["崖山・祥兴二年二月", "张世杰的船连成一片，船与船之间，是铁索。", JOIN],
	["战到午后，铁索连着的船开始烧。", CUT],
	["阿那要是还活着，会告诉你这时候该往哪边走。", "你自己看了水色。", "往南"]]

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
var _tally: ScriptErrTally
var _reported := false
var _shots: Array = []
var _probe: Player


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
	root.size = VIEW
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	var cid := Player.ending_id("海上宋鬼")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes.json"))
	if typeof(data) == TYPE_DICTIONARY:
		_shots = ((data as Dictionary).get("cutscenes", {}) as Dictionary).get(cid, {}).get("shots", [])
	_expect(cid != "" and _shots.size() >= 3, "「海上宋鬼」有结局过场（%s，%d 镜）" % [cid, _shots.size()])
	_probe = Player.new()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_join()
	await _b_breakout()
	_probe.free()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ENDING_YASHAN_CINE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame


## 广州港页、祥兴二年二月、海商：一条船，船型与士气定快慢（崖山页的门槛：船速过 90，泉州借过船的过 70）
func _fresh(ship_type: String, morale: int, sided_zhang: bool) -> void:
	await _drop_sheet()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	_cal.from_dict({"year": 1279, "month": 2, "day": 2})
	_gs.identity = "merchant"
	_gs.last_port = "guangzhou"
	_gs.money = 3000
	if sided_zhang:
		_gs.set_flag("sided_zhang")
	_fleet.ships = [{"type": ship_type, "name": "旗舰", "durability": 300.0, "max_durability": 300.0,
		"crew": 40, "sail_level": 1, "armor_level": 1, "cargo": {}}]
	_fleet.morale = morale
	_fleet.water = 200
	_fleet.food = 200
	_main.load_scene("guangzhou")
	await process_frame
	_main._on_facility_pressed({"id": "special_yashan"})
	await process_frame


## 这一局过场每一镜实际出的字幕（照真播放器 _caption_on 判），只取字，镜内照数据次序
func _shown() -> Array:
	var out := []
	for shot in _shots:
		var caps := []
		for c in (shot as Dictionary).get("captions", []):
			if typeof(c) == TYPE_DICTIONARY and _probe._caption_on(c):
				caps.append(str((c as Dictionary).get("text", "")))
		out.append(caps)
	return out


## 某一镜里起笔时刻为 t 的那一格出了几句（同一格换句的几条旗标互斥，只该出一句）
func _slot_count(shot_i: int, t: float) -> int:
	var n := 0
	for c in (_shots[shot_i] as Dictionary).get("captions", []):
		if typeof(c) == TYPE_DICTIONARY and is_equal_approx(float(c.get("t", -1.0)), t) and _probe._caption_on(c):
			n += 1
	return n


func _flat(shown: Array) -> Array:
	var out := []
	for caps in shown:
		out.append_array(caps)
	return out


func _bare(s: String) -> String:
	var out := s
	for p in ["。", "，", "、", "；", "\n", " ", "　"]:
		out = out.replace(p, "")
	return out


## 过场那一句（去标点）落在这一局的册页正文里。「你砍断了自己的缆」是交粮三路共用的一句：册页写「你砍断自己的缆」
## （泉州借过船）/「你砍断了自己的缆」/「你砍缆砍晚了」都算——砍晚了也是砍了，那一路另补「砍晚了」一句
func _line_in_sheet(line: String) -> bool:
	var sheet := _bare(str(_gs.ended_text))
	if line == CUT:
		return sheet.find("砍断自己的缆") >= 0 or sheet.find("砍断了自己的缆") >= 0 or sheet.find("砍缆") >= 0
	return sheet.find(_bare(line)) >= 0


func _common(tag: String, shown: Array) -> void:
	_expect(_slot_count(0, 4.2) == 1 and _slot_count(1, 3.8) == 1,
		"%s：第 1 镜、第 2 镜换句那一格各只出一句（%d / %d）" % [tag, _slot_count(0, 4.2), _slot_count(1, 3.8)])
	var line := ""
	for c in (_shots[1] as Dictionary).get("captions", []):
		if typeof(c) == TYPE_DICTIONARY and is_equal_approx(float(c.get("t", -1.0)), 3.8) and _probe._caption_on(c):
			line = str(c.get("text", ""))
	_expect(line != "" and _line_in_sheet(line), "%s：第 2 镜「%s」在册页正文里" % [tag, line])


# ── A 交粮三路 ───────────────────────────────────────────

func _a_join() -> void:
	print("── A 崖山「把粮与硫黄交上去」：过场写交粮、砍缆，船慢另补砍晚了")
	for spec in [["泉州借过船・船快", "fu_ship_medium", 80, true], ["船快", "fu_ship_medium", 80, false],
			["船慢", "sampan", 20, false]]:
		var tag: String = spec[0]
		await _fresh(spec[1], spec[2], spec[3])
		var slow: bool = _fleet.fleet_speed() <= (70.0 if spec[3] else 90.0)
		_expect(slow == (tag == "船慢"), "%s：船速 %.1f 摆对了快慢" % [tag, _fleet.fleet_speed()])
		var join: Button = null
		for c in _main.choices_container.get_children():
			if c is Button and str((c as Button).text).begins_with("把粮与硫黄交上去"):
				join = c
		_expect(join != null, "%s：崖山页有「把粮与硫黄交上去」" % tag)
		if join == null:
			continue
		join.pressed.emit()
		await process_frame
		_expect(str(_gs.ended) == "海上宋鬼", "%s：落「海上宋鬼」" % tag)
		var shown := _shown()
		var flat := _flat(shown)
		_expect(flat.has(JOIN) and flat.has(CUT) and not flat.has(BOARD) and not flat.has(OUT) and not flat.has(BURNT),
			"%s：第 1 镜写交粮、第 2 镜写砍缆，不出上船同去那几句" % tag)
		if slow:
			_expect(flat.has(CUT_LATE) and _line_in_sheet(CUT_LATE), "%s：第 2 镜补「%s」（册页同写）" % [tag, CUT_LATE])
		else:
			_expect(not flat.has(CUT_LATE), "%s：船快不补「砍晚了」" % tag)
			_expect(shown.slice(0, 3) == OLD_FAST, "%s：前三镜字幕逐句同原先那一套（%s）" % [tag, str(shown.slice(0, 3))])
		_common(tag, shown)


# ── B 上船同去两路 ───────────────────────────────────────

func _battle() -> Node:
	for c in _main.get_children():
		if c.has_signal("battle_finished") and not c.is_queued_for_deletion():
			return c
	return null


func _b_breakout() -> void:
	print("── B 崖山「上船同去」真打突围那一仗：过场写上船跟着冲、写册页里那一句")
	for spec in [["冲出", "flee", {"flee_ok": true}, OUT, BURNT], ["没冲出", "lose", {}, BURNT, OUT]]:
		var tag: String = spec[0]
		await _fresh("fu_ship_medium", 80, false)
		_main._yashan_breakout(false)
		for i in 4:
			await process_frame
		var wm := _battle()
		_expect(wm != null, "%s：「上船同去」开打，海战一层挂在港页上" % tag)
		if wm == null:
			continue
		wm.call("_battle_exit", spec[1], spec[2])
		for i in 3:
			await process_frame
		_expect(str(_gs.ended) == "海上宋鬼" and _gs.has_flag("yashan_breakout_done") and _gs.has_flag("yashan_broke_out") == (tag == "冲出"),
			"%s：收战落「海上宋鬼」，两枚旗由收战立好（done=%s out=%s）" % [tag, _gs.has_flag("yashan_breakout_done"), _gs.has_flag("yashan_broke_out")])
		var flat := _flat(_shown())
		_expect(not flat.has(JOIN) and not flat.has(CUT) and not flat.has(CUT_LATE),
			"%s：不写「%s」「%s」" % [tag, JOIN, CUT])
		_expect(flat.has(BOARD) and flat.has(spec[3]) and not flat.has(spec[4]),
			"%s：第 1 镜「%s」、第 2 镜「%s」" % [tag, BOARD, spec[3]])
		_common(tag, _shown())
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
