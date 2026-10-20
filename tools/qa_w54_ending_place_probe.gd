extends SceneTree
## lane-w54-ending：终局港页的匾与首进那张题签写结局收在的地方。
## 结局落款（GameState.ended_at）改写到别处的两局：涵江出海收在旧避风澳（Main._on_hanjiang_escape）、崖山两条路收在崖山外海
## （Main._yashan_signoff）。终局港页的匾、首进终局港页那张题签却照点卡的那一港写——「广州・海上宋鬼」「兴化军・岸上的根」，
## 同一张题签副题是「祥兴二年　二月初七・崖山」「景炎二年　九月初九・旧避风澳」，上下两个地方；结算底图画的是崖山 / 旧避风澳。
##   A 崖山交粮、上船同去冲出 / 没冲出（真开突围那一仗、真走 WorldMap._battle_exit）：匾「崖山・海上宋鬼」，题签题与匾同、
##     副题即落款，札记抬头旁注即落款；重读结局合上后匾不累加；存档读回再进港，匾照旧写崖山。
##   B 涵江出海：匾与题签题「旧避风澳・岸上的根」，副题即落款。
##   R 反向基：落款照点卡那一港写的照旧用港名匾——福州听到兴化城破「福州・未归」、泉州纲首卡「泉州・纲首」、
##     守城候过城破时点结「援绝」（落款「景炎元年　腊月・兴化」）匾照旧「兴化军・忠肃」；落款空着的旧档照旧写港名。
## 题签的题与副题由内存里现编的 Main 子类覆写 play_transition 记下（headless 下题签不演，play_transition 照调）。
## 用法：godot --headless --path . -s res://tools/qa_w54_ending_place_probe.gd（经门锁跑）
## 末行 W54_ENDING_PLACE cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const VIEW := Vector2i(1280, 720)
const SPY_SRC := """extends "res://scripts/Main.gd"

var spy_titles: Array = []


func play_transition(title: String, subtitle := "", at_black := Callable(), seal := "") -> void:
	spy_titles.append([title, subtitle, seal])
	await super(title, subtitle, at_black, seal)
"""

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
	var spy := GDScript.new()
	spy.source_code = SPY_SRC
	var err := spy.reload()
	_expect(err == OK, "Main 探针子类编得过（err=%d）" % err)
	if err != OK:
		return
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	_main.set_script(spy)
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _a_yashan()
	await _b_hanjiang()
	await _r_controls()
	await _drop_sheet()
	_gs.from_dict({})
	_cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ENDING_PLACE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _drop_sheet() -> void:
	var host = _main.get("_chapter_host")
	if host != null and is_instance_valid(host):
		_main._confirm_chapter_sheet()
	await process_frame
	await process_frame


func _fresh(y: int, m: int, port: String, identity: String, d := 2) -> void:
	await _drop_sheet()
	_gs.from_dict({})
	_gs.loaded_with_beats = true
	_main.set("_beats", null)
	for e in _main._beats_book().entries():
		_gs.beat_mark(e)
	_cal.from_dict({"year": y, "month": m, "day": d})
	_gs.identity = identity
	_gs.last_port = port
	_gs.money = 3000
	_fleet.ships = [{"type": "fu_ship_medium", "name": "旗舰", "durability": 300.0, "max_durability": 300.0,
		"crew": 40, "sail_level": 1, "armor_level": 1, "cargo": {}}]
	_fleet.morale = 80
	_fleet.water = 200
	_fleet.food = 200
	# 每一局都是头一回进终局港页：题签记过的清掉，好看见那张题签
	(_main.get("_shore_title_seen") as Dictionary).clear()
	(_main.get("spy_titles") as Array).clear()


## 首进终局港页那张「终」字题签：[题, 副题]（没演过返回空）
func _ended_card() -> Array:
	for t in _main.get("spy_titles"):
		if str(t[2]) == "终":
			return [str(t[0]), str(t[1])]
	return []


## 终局港页航海札记抬头的旁注（淡字那一枚）
func _slip_aside() -> String:
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	var slip: Node = band.find_child("EpilogueSlip", true, false) if band != null else null
	var head: Node = slip.find_child("BandHead", true, false) if slip != null else null
	if head == null:
		return ""
	var labels := head.find_children("*", "Label", true, false)
	return str((labels[labels.size() - 1] as Label).text) if labels.size() >= 2 else ""


## 落定结局、合上结局册页回到终局港页之后：匾、题签、札记抬头三处
func _check_page(tag: String, want_title: String) -> void:
	await _drop_sheet()
	await process_frame
	var at := str(_gs.ended_at)
	_expect(str(_main.port_title.text) == want_title, "%s：终局匾「%s」（现「%s」）" % [tag, want_title, _main.port_title.text])
	var card := _ended_card()
	_expect(card.size() == 2 and card[0] == want_title and card[1] == at,
		"%s：首进终局港页的题签题「%s」、副题即落款「%s」（记下 %s）" % [tag, want_title, at, str(card)])
	_expect(_slip_aside() == at, "%s：航海札记抬头旁注即落款（「%s」）" % [tag, _slip_aside()])


# ── A 崖山三路 ───────────────────────────────────────────

func _battle() -> Node:
	for c in _main.get_children():
		if c.has_signal("battle_finished") and not c.is_queued_for_deletion():
			return c
	return null


func _a_yashan() -> void:
	print("── A 崖山：匾与题签写崖山")
	await _fresh(1279, 2, "guangzhou", "merchant")
	_main.load_scene("guangzhou")
	await process_frame
	_main._on_facility_pressed({"id": "special_yashan"})
	await process_frame
	for c in _main.choices_container.get_children():
		if c is Button and str((c as Button).text).begins_with("把粮与硫黄交上去"):
			(c as Button).pressed.emit()
	await process_frame
	_expect(str(_gs.ended) == "海上宋鬼" and str(_gs.ended_at).ends_with("・崖山"), "交粮落「海上宋鬼」、落款写崖山（「%s」）" % _gs.ended_at)
	await _check_page("交粮", "崖山・海上宋鬼")
	_main._on_reread_ending()
	await process_frame
	await _drop_sheet()
	_expect(str(_main.port_title.text) == "崖山・海上宋鬼", "交粮：重读结局合上后匾不累加（「%s」）" % _main.port_title.text)
	# 存档读回（同标题页「续卷」那条路的两份字典），再进港：匾照落款写崖山
	var gs_d: Dictionary = _gs.to_dict()
	var cal_d: Dictionary = _cal.to_dict()
	_gs.from_dict({})
	_gs.from_dict(gs_d)
	_cal.from_dict(cal_d)
	_main.load_scene(str(_gs.last_port))
	await process_frame
	_expect(str(_main.port_title.text) == "崖山・海上宋鬼", "交粮：存档读回再进港，匾照旧写崖山（「%s」）" % _main.port_title.text)

	for spec in [["上船同去冲出", "flee", {"flee_ok": true}], ["上船同去没冲出", "lose", {}]]:
		var tag: String = spec[0]
		await _fresh(1279, 2, "guangzhou", "merchant")
		_main.load_scene("guangzhou")
		await process_frame
		_main._on_facility_pressed({"id": "special_yashan"})
		await process_frame
		_main._yashan_breakout(false)
		for i in 4:
			await process_frame
		var wm := _battle()
		_expect(wm != null, "%s：突围那一仗开打" % tag)
		if wm == null:
			continue
		wm.call("_battle_exit", spec[1], spec[2])
		for i in 3:
			await process_frame
		_expect(str(_gs.ended) == "海上宋鬼", "%s：收战落「海上宋鬼」" % tag)
		await _check_page(tag, "崖山・海上宋鬼")


# ── B 涵江出海 ───────────────────────────────────────────

func _b_hanjiang() -> void:
	print("── B 涵江出海：匾与题签写旧避风澳")
	await _fresh(1277, 9, "xinghua", "hometown")
	_gs.discoveries_found = ["nameless_shelter_bay"]
	_main.load_scene("xinghua")
	await process_frame
	_main._on_facility_pressed({"id": "special_hanjiang_escape"})
	await process_frame
	_expect(str(_gs.ended) == "岸上的根" and str(_gs.ended_at).ends_with("・旧避风澳"), "落「岸上的根」、落款写旧避风澳（「%s」）" % _gs.ended_at)
	await _check_page("涵江出海", "旧避风澳・岸上的根")


# ── R 反向基 ─────────────────────────────────────────────

func _r_controls() -> void:
	print("── R 反向基：落款照点卡那一港写的，匾照旧写港名")
	await _fresh(1276, 12, "fuzhou", "scholar")
	_gs.player_name = "陈文龙"
	_gs.set_flag("renamed_wenlong")
	_main.load_scene("fuzhou")
	await process_frame
	_expect(str(_gs.ended) == "未归", "福州听到兴化城破落「未归」")
	await _check_page("福州未归", "福州・未归")

	await _fresh(1285, 4, "quanzhou", "merchant")
	_main.load_scene("quanzhou")
	await process_frame
	_main._on_facility_pressed({"id": "special_gangshou_end"})
	await process_frame
	_expect(str(_gs.ended) == "纲首", "泉州点纲首卡落「纲首」")
	await _check_page("泉州纲首", "泉州・纲首")

	# 守城：冬月进城开城防，候到腊月（过首守城破时点）再进港，按「援绝」结——落款「景炎元年　腊月・兴化」，匾仍是港名匾
	await _fresh(1276, 11, "xinghua", "scholar", 20)
	_gs.player_name = "陈文龙"
	_gs.set_flag("renamed_wenlong")
	_main.load_scene("xinghua")
	await process_frame
	_expect(_gs.siege_open(), "冬月进兴化开了城防")
	_cal.from_dict({"year": 1276, "month": 12, "day": 3})
	_main.load_scene("xinghua")
	await process_frame
	_expect(str(_gs.ended) == "忠肃" and str(_gs.ended_head).ends_with("援绝"), "候过城破时点按「援绝」落「忠肃」（落款「%s」）" % _gs.ended_at)
	await _check_page("守城援绝", "兴化军・忠肃")

	# 落款空着的旧档：匾照旧写港名
	await _fresh(1279, 3, "quanzhou", "merchant")
	_gs.finish("纲首", "旧档摆场")
	_gs.ended_at = ""
	_main.load_scene("quanzhou")
	await process_frame
	_expect(str(_main.port_title.text) == "泉州・纲首", "落款空着的旧档：匾照旧「泉州・纲首」（「%s」）" % _main.port_title.text)
