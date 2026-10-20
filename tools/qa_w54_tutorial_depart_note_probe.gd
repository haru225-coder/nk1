extends SceneTree
## lane w54-tutorial 出港验引那句探针（headless，经门锁跑）：
##   godot --headless --path . -s res://tools/qa_w54_tutorial_depart_note_probe.gd
## 港页「看风」过了验引当帧就换海图（Main._on_set_sail → change_scene_to_file），验引那一句原先只记在港页记事栏、随港页一起换掉：
## 新开一局头一日市舶司不在三扇门里，头一回出海多半无引塞钱，钱少五十、蒲家留意涨二十，屏上一个字也没有。真起 Main、真按出港、
## 等真换上海图：
##   一、无引塞钱：开局光景（泉州、宝祐三年三月初一、钱 940、无货引、蒲家留意 0）按「看风」→ 换上海图；船况札记里有塞钱那句，
##       起锚那句排在它上面（札记新的在上），顶匾第二行报的是塞钱那句；钱 890、蒲家留意 20（账照旧，只是看得见了）。
##   二、凭引放行：先请领货引再出港，札记与顶匾写「出示了泉州货引…安全放行」。
##   三、传话读完即清：换上海图后 GameManager.depart_note 已空；不经港页直接开一张海图，札记只有起锚那一句、顶匾也是它。
##   四、没放行的照旧留在港里（钱不够塞的遣返）：不换海图、港页记事栏写遣返那句、depart_note 不留话。
## 判词：末行 QA_W54_TUTORIAL_DEPART_NOTE PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_TUTORIAL_DEPART_NOTE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CHART_PATH := "res://scenes/SeaChart.tscn"
const BRIBE := "塞了 50 钱给小吏，强行出港"
const PERMIT_OK := "出示了泉州货引，缴过抽解，安全放行"
const TURNED_BACK := "小吏毫不客气地把你轰回港内"
const ANCHOR := "自 泉州 起锚。"

var _gs: Node = null
var _gm: Node = null
var _fleet: Node = null
var _cal: Node = null
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
	await process_frame
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	cine.set("auto_opening", false)
	cine.set("opening_seen", true)
	_gs = root.get_node("GameState")
	_gm = root.get_node("GameManager")
	_fleet = root.get_node("Fleet")
	_cal = root.get_node("Calendar")
	print("== 一、无引塞钱：按「看风」换上海图，塞钱那句在札记与顶匾上")
	await _sec_bribe()
	print("== 二、凭引放行")
	await _sec_permit()
	print("== 三、读完即清：不经港页开的海图只有起锚那一句")
	await _sec_fresh_chart()
	print("== 四、没放行的照旧留在港里")
	await _sec_turned_back()
	_report()


# ── 布景 ──────────────────────────────────────────────

## 开局光景：序章走完、头一回踏上泉州（同新开一局一路点下来的账：小艍一条六人、钱 940、无货引、蒲家留意 0）
func _opening_state(money: int) -> void:
	_gs.call("from_dict", {})
	_gs.set("money", money)
	_gs.set("last_port", "quanzhou")
	_gs.set("visited_ports", ["quanzhou"])
	_gs.set("has_customs_permit", false)
	_gs.set("pu_attention", 0)
	_cal.call("from_dict", {"year": 1255, "month": 3, "day": 1})
	_fleet.call("from_dict", {"ships": [{"type": "sampan", "name": "无名小艍", "durability": 120.0, "max_durability": 120.0,
		"crew": 6, "sail_level": 1, "armor_level": 1, "cargo": {}}], "water": 80, "food": 80, "morale": 70})
	_gm.set("depart_note", "")


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _new_main() -> Node:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.call("load_scene", "quanzhou")
	await _frames(2)
	return main


## 等「看风」换上海图（change_scene_to_file 在帧尾换场）；一百帧换不上回 null
func _await_chart() -> Node:
	for _i in 100:
		await process_frame
		var cs := current_scene
		if cs != null and is_instance_valid(cs) and cs.scene_file_path == CHART_PATH and cs.is_node_ready():
			await process_frame
			return cs
	return null


func _drop(n: Node) -> void:
	if n != null and is_instance_valid(n):
		if current_scene == n:
			current_scene = null
		n.queue_free()
	await _frames(2)


func _lines(chart: Node) -> PackedStringArray:
	return chart.get("_log_lines") as PackedStringArray


func _index_of(lines: PackedStringArray, needle: String) -> int:
	for i in lines.size():
		if lines[i].contains(needle):
			return i
	return -1


# ── 一、无引塞钱 ────────────────────────────────────────

func _sec_bribe() -> void:
	_opening_state(940)
	var main := await _new_main()
	main.call("_on_set_sail")
	var chart := await _await_chart()
	_check(chart != null, "无引出港：过了验引、换上海图")
	if chart == null:
		await _drop(main)
		return
	var lines := _lines(chart)
	var i_bribe := _index_of(lines, BRIBE)
	var i_anchor := _index_of(lines, ANCHOR)
	_check(i_bribe >= 0, "船况札记里有塞钱那句「%s」（札记 %s）" % [BRIBE, lines])
	_check(i_anchor >= 0 and i_anchor < i_bribe, "起锚那句仍在、排在塞钱那句上面（新的在上：起锚 %d、塞钱 %d）" % [i_anchor, i_bribe])
	var strip := str(chart.get("_latest_note"))
	_check(strip.contains(BRIBE), "顶匾第二行报塞钱那句（「%s」）" % strip)
	var shown := (chart.get("_strip_line") as RichTextLabel).get_parsed_text()
	_check(shown.contains("强行出港"), "顶匾上画出来的字里有「强行出港」（%s）" % shown.replace("\n", "｜"))
	_check(int(_gs.get("money")) == 890 and int(_gs.get("pu_attention")) == 20,
		"账照旧：钱 940 → %d（塞 50）、蒲家留意 0 → %d" % [int(_gs.get("money")), int(_gs.get("pu_attention"))])
	_check(str(_gm.get("depart_note")) == "", "传话读完即清（depart_note「%s」）" % str(_gm.get("depart_note")))
	await _drop(chart)


# ── 二、凭引放行 ────────────────────────────────────────

func _sec_permit() -> void:
	_opening_state(940)
	var res: Dictionary = _gs.call("apply_for_permit")
	_check(bool(res.get("ok", false)) and bool(_gs.get("has_customs_permit")), "先请领货引（%s）" % str(res.get("msg", "")))
	var main := await _new_main()
	main.call("_on_set_sail")
	var chart := await _await_chart()
	_check(chart != null, "凭引出港：换上海图")
	if chart == null:
		await _drop(main)
		return
	var lines := _lines(chart)
	_check(_index_of(lines, PERMIT_OK) >= 0 and _index_of(lines, BRIBE) < 0, "札记写凭引放行那句、不写塞钱（%s）" % [lines])
	_check(str(chart.get("_latest_note")).contains(PERMIT_OK), "顶匾第二行报凭引放行（「%s」）" % str(chart.get("_latest_note")))
	_check(not bool(_gs.get("has_customs_permit")), "货引一引一航次，出港即销")
	await _drop(chart)


# ── 三、读完即清 ────────────────────────────────────────

func _sec_fresh_chart() -> void:
	_opening_state(940)
	var chart: Node = (load(CHART_PATH) as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(2)
	var lines := _lines(chart)
	_check(lines.size() == 1 and lines[0].begins_with(ANCHOR), "不经港页开的海图：札记只有起锚那一句（%s）" % [lines])
	_check(str(chart.get("_latest_note")).begins_with(ANCHOR), "顶匾也是起锚那句（「%s」）" % str(chart.get("_latest_note")))
	await _drop(chart)


# ── 四、没放行的照旧留在港里 ────────────────────────────

func _sec_turned_back() -> void:
	_opening_state(30)
	var main := await _new_main()
	main.call("_on_set_sail")
	await _frames(4)
	var cs := current_scene
	_check(cs == main and is_instance_valid(main), "钱不够塞（30 < 50）：不换海图，仍在港页")
	var logs: PackedStringArray = main.get("_log_lines")
	_check(_index_of(logs, TURNED_BACK) >= 0, "港页记事栏写遣返那句（%s）" % [logs])
	_check(str(_gm.get("depart_note")) == "", "没放行不留话给海图（depart_note「%s」）" % str(_gm.get("depart_note")))
	await _drop(main)
