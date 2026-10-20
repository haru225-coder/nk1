extends SceneTree
## lane w54-tutorial 没发舶就回港货引还在手探针（headless，经门锁跑）：
##   godot --headless --path . -s res://tools/qa_w54_tutorial_unsailed_permit_probe.gd
## 「看风」放行那一下 Main 就 consume_permit（一引一航次）；海图上没发舶就「回港」，这一趟没走，原先引也没了——新手请了引、点「看风」
## 先看看去向、回港再去添货，得再请领一回。真起 Main、真按「看风」、真按海图上的「回港」：
##   一、凭引出港、没发舶就回港：回到港页引还在手；再按「看风」凭这张引放行（札记写出示货引），不另请领、钱不再少；
##       发了舶以后「回港」按不动、引照旧销着（真走了这一趟才算用掉）。
##   二、无引塞钱出港、没发舶就回港：没有引可还，引照旧没有；塞给小吏的钱与蒲家留意不退（照原样，交主控拍）。
##   三、请领后又添货、出港补过抽解、没发舶回港：引还回来、报过的舱货是补到的那一数；再按「看风」不再补、钱不再少。
## 判词：末行 QA_W54_TUTORIAL_UNSAILED_PERMIT PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_TUTORIAL_UNSAILED_PERMIT"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CHART_PATH := "res://scenes/SeaChart.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const GOOD := "qingbai_porcelain"

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
	print("== 一、凭引出港、没发舶就回港")
	await _sec_permit()
	print("== 二、无引塞钱出港、没发舶就回港")
	await _sec_bribe()
	print("== 三、补过抽解的引，回港照旧")
	await _sec_topup()
	_report()


# ── 布景 ──────────────────────────────────────────────

## 泉州、宝祐三年三月初一、小艍一条六人、无货引、蒲家留意 0；港口节拍全记过（港页不演戏）
func _opening(money: int) -> void:
	_gs.call("from_dict", {})
	_gs.set("chapter", 1)
	_gs.set("money", money)
	_gs.set("last_port", "quanzhou")
	_gs.set("visited_ports", ["quanzhou"])
	_gs.set("loaded_with_beats", true)
	for b in _gm.get("port_beats_data").get("beats", []):
		_gs.call("beat_mark", str((b as Dictionary).get("entry", "")))
	_cal.call("from_dict", {"year": 1255, "month": 3, "day": 1})
	_fleet.call("from_dict", {"ships": [{"type": "sampan", "name": "无名小艍", "durability": 120.0, "max_durability": 120.0,
		"crew": 6, "sail_level": 1, "armor_level": 1, "cargo": {}}], "water": 80, "food": 80, "morale": 70})
	_gm.set("depart_note", "")
	_gm.set("depart_permit", false)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _new_main() -> Node:
	var main: Node = (load(MAIN_PATH) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	main.call("load_scene", "quanzhou")
	await _frames(2)
	return main


## 等 change_scene_to_file 换上 path 那一场（一百帧换不上回 null）
func _await_scene(path: String) -> Node:
	for _i in 100:
		await process_frame
		var cs := current_scene
		if cs != null and is_instance_valid(cs) and cs.scene_file_path == path and cs.is_node_ready():
			await _frames(2)
			return cs
	return null


func _drop(n: Node) -> void:
	if n != null and is_instance_valid(n):
		if current_scene == n:
			current_scene = null
		n.queue_free()
	await _frames(2)


## 港页按「看风」→ 海图（换不上回 null）
func _sail_from(main: Node) -> Node:
	main.call("_on_set_sail")
	return await _await_scene(CHART_PATH)


## 海图上没发舶点「回港」→ 港页（Main.start_game 见 return_to_port 回 last_port）
func _back_from(chart: Node) -> Node:
	chart.call("_on_back_to_port")
	return await _await_scene(MAIN_PATH)


func _chart_log(chart: Node) -> String:
	return "｜".join(chart.get("_log_lines") as PackedStringArray)


# ── 一、凭引出港、没发舶就回港 ─────────────────────────

func _sec_permit() -> void:
	_opening(940)
	var res: Dictionary = _gs.call("apply_for_permit")
	var money0 := int(_gs.get("money"))
	_check(bool(res.get("ok", false)) and bool(_gs.get("has_customs_permit")), "请领货引（%s，钱 940 → %d）" % [str(res.get("msg", "")), money0])
	var main := await _new_main()
	var chart := await _sail_from(main)
	_check(chart != null and not bool(_gs.get("has_customs_permit")), "按「看风」凭引放行、换上海图：引照「一引一航次」先销了")
	if chart == null:
		await _drop(main)
		return
	main = await _back_from(chart)
	_check(main != null and str(main.get("current_scene_id")) == "quanzhou", "海图上没发舶就点「回港」：回到泉州港页")
	_check(bool(_gs.get("has_customs_permit")), "这一趟没走：货引还在手")
	_check(int(_gs.get("money")) == money0 and int(_gs.get("pu_attention")) == 0, "钱 %d、蒲家留意 %d 都没动" % [int(_gs.get("money")), int(_gs.get("pu_attention"))])
	if main == null:
		return
	chart = await _sail_from(main)
	_check(chart != null and _chart_log(chart).contains("出示了泉州货引") and int(_gs.get("money")) == money0,
		"再按「看风」：凭这张引放行、不另请领，钱照旧 %d（札记 %s）" % [int(_gs.get("money")), _chart_log(chart) if chart != null else ""])
	if chart == null:
		return
	var far := ""
	var vy: Node = root.get_node("Voyage")
	for pid in chart.get("_hand"):
		if far == "" or float(vy.call("distance_li", "quanzhou", pid)) > float(vy.call("distance_li", "quanzhou", far)):
			far = str(pid)
	chart.call("_select_heading", far)
	chart.call("_on_sail_pressed")
	await _frames(2)
	chart.call("_on_back_to_port")
	await _frames(4)
	_check(current_scene == chart and bool(chart.get("voyage_started")) and not bool(_gs.get("has_customs_permit")),
		"发了舶：「回港」按不动，引照旧销着（真走了这一趟才算用掉）")
	chart.set("sailing", false)
	await _drop(chart)


# ── 二、无引塞钱出港、没发舶就回港 ─────────────────────

func _sec_bribe() -> void:
	_opening(940)
	var main := await _new_main()
	var chart := await _sail_from(main)
	_check(chart != null and _chart_log(chart).contains("塞了 50 钱给小吏"), "无引按「看风」：塞钱强行出港")
	if chart == null:
		await _drop(main)
		return
	main = await _back_from(chart)
	_check(main != null and not bool(_gs.get("has_customs_permit")), "没发舶就回港：本没有引，引照旧没有")
	_check(int(_gs.get("money")) == 890 and int(_gs.get("pu_attention")) == 20,
		"塞给小吏的钱与蒲家留意不退（钱 %d、留意 %d，照原样）" % [int(_gs.get("money")), int(_gs.get("pu_attention"))])
	await _drop(main)


# ── 三、补过抽解的引，回港照旧 ─────────────────────────

func _sec_topup() -> void:
	_opening(5000)
	var res: Dictionary = _gs.call("apply_for_permit")
	_check(bool(res.get("ok", false)), "空舱请领货引（%s）" % str(res.get("msg", "")))
	_check(bool(_fleet.call("add_cargo", GOOD, 20, 60.0, 0)), "请领后添青白瓷 20 件")
	var owed := int(_gs.call("permit_topup"))
	var money1 := int(_gs.get("money"))
	var main := await _new_main()
	var chart := await _sail_from(main)
	_check(chart != null and owed > 0 and _chart_log(chart).contains("补抽解 %d 钱" % owed) and int(_gs.get("money")) == money1 - owed,
		"按「看风」补抽解 %d 钱放行（钱 %d → %d）" % [owed, money1, int(_gs.get("money"))])
	if chart == null:
		await _drop(main)
		return
	var base := int(_gs.get("permit_base"))
	main = await _back_from(chart)
	_check(main != null and bool(_gs.get("has_customs_permit")) and int(_gs.get("permit_base")) == base and base == int(_gs.call("duty_base")),
		"没发舶就回港：引还在手，报过的舱货是补到的那一数（%d）" % base)
	if main == null:
		return
	var money2 := int(_gs.get("money"))
	chart = await _sail_from(main)
	_check(chart != null and not _chart_log(chart).contains("补抽解") and int(_gs.get("money")) == money2,
		"再按「看风」：舱货没再添，不再补、钱照旧 %d" % int(_gs.get("money")))
	await _drop(chart if chart != null else current_scene)
