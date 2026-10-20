extends SceneTree
## lane-w54-story：结局落款（GameState.ended_at，「终局时地」）写结局所在的地方。
## GameState.finish 照 last_port 落款。崖山这一局是从广州港页点崖山卡、走了五日（「把粮与硫黄交上去」）或打完突围那一仗
## （「上船同去」）才在崖山外海收的——册页大题「崖山・祥兴二年二月」、结局过场题签同写崖山，航海札记却记「终局：海上宋鬼
## （祥兴二年　二月初七・广州）」，终局港页札记抬头、「重读结局」眉题也都写广州。涵江出海早已照「落款改写成到岸的地方」
## 改成旧避风澳（Main._on_hanjiang_escape），崖山漏了。
##   A 交粮那条路：落款写崖山、不写广州，札记「终局」一行同。
##   B 上船同去那条路（突围打完，冲出 / 没冲出两式）：落款同写崖山。
##   反向基：人在哪里收局就写哪里的照旧——福州听到兴化城破落「未归」写福州；涵江出海照旧写旧避风澳。
## 用法：godot --headless --path . -s res://tools/qa_w54_story_signoff_probe.gd（经门锁跑）
## 末行 W54_STORY_SIGNOFF cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _cal: Node
var _fleet: Node
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
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload GameState / Calendar / Fleet 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_yashan_join()
	await _b_yashan_breakout()
	await _r_controls()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_STORY_SIGNOFF cases=%d fails=%d" % [cases, fails])
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


func _epilogue_end_line() -> String:
	for line in _gs.epilogue_lines():
		if str(line).begins_with("终局："):
			return str(line)
	return ""


# ── A 交粮那条路 ─────────────────────────────────────────

func _a_yashan_join() -> void:
	print("── A 崖山「把粮与硫黄交上去」：落款写崖山")
	await _fresh(1279, 2, "guangzhou", "merchant")
	_main.load_scene("guangzhou")
	await process_frame
	_main._on_facility_pressed({"id": "special_yashan"})
	await process_frame
	var join: Button = null
	for c in _main.choices_container.get_children():
		if c is Button and str((c as Button).text).begins_with("把粮与硫黄交上去"):
			join = c
	_expect(join != null, "崖山页有「把粮与硫黄交上去」")
	if join != null:
		join.pressed.emit()
		await process_frame
	var line := _epilogue_end_line()
	_expect(_gs.ended == "海上宋鬼" and _gs.ended_at.ends_with("・崖山") and _gs.ended_at.find("广州") < 0
			and _gs.ended_at.begins_with(_cal.get_date_string()),
		"交粮落「海上宋鬼」：落款写当日・崖山、不写广州（「%s」）" % _gs.ended_at)
	_expect(line.ends_with("・崖山）") and line.find("广州") < 0, "航海札记终局一行同写崖山（「%s」）" % line)


# ── B 上船同去那条路 ─────────────────────────────────────

func _b_yashan_breakout() -> void:
	print("── B 崖山「上船同去」突围打完：落款写崖山")
	for outcome in ["win", "lose"]:
		await _fresh(1279, 2, "guangzhou", "merchant")
		_main.load_scene("guangzhou")
		await process_frame
		_main._on_facility_pressed({"id": "special_yashan"})
		await process_frame
		# 突围那一仗由 WorldMap 打；这里直接收战（outcome 照 WorldMap 发的那一族），走的是同一支 _on_yashan_battle
		_main._on_yashan_battle(outcome, {"player_damage": 0.0})
		await process_frame
		_expect(_gs.ended == "海上宋鬼" and _gs.ended_at.ends_with("・崖山") and _gs.ended_at.find("广州") < 0,
			"突围收战（%s）落「海上宋鬼」：落款写崖山、不写广州（「%s」）" % [outcome, _gs.ended_at])


# ── 反向基 ───────────────────────────────────────────────

func _r_controls() -> void:
	print("── 反向基：人在哪里收局就写哪里")
	await _fresh(1276, 12, "fuzhou", "scholar")
	_gs.player_name = "陈文龙"
	_gs.set_flag("renamed_wenlong")
	_main.load_scene("fuzhou")
	await process_frame
	_expect(_gs.ended == "未归" and _gs.ended_at.ends_with("・福州"),
		"景炎元年腊月士人在福州：落「未归」、落款写福州（「%s」）" % _gs.ended_at)
	await _fresh(1277, 9, "xinghua", "hometown")
	_gs.discoveries_found = ["nameless_shelter_bay"]
	_main.load_scene("xinghua")
	await process_frame
	_main._on_facility_pressed({"id": "special_hanjiang_escape"})
	await process_frame
	_expect(_gs.ended == "岸上的根" and _gs.ended_at.ends_with("・旧避风澳"),
		"涵江出海落「岸上的根」：落款照旧写旧避风澳（「%s」）" % _gs.ended_at)
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
