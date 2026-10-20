extends SceneTree
## lane w54-hunt 回车误按探针（headless，经 glock 跑；真起 Main、真按键）。
##   godot --headless --path . -s res://tools/qa_w54_hunt_stray_enter_probe.gd
## Main._unhandled_input 把回车 / 空格（ui_accept）当「按本页头一扇门」（_activate_first_choice）。页面被别的东西盖住时，
## 底下那几扇门还在、只是看不见——回车不该按到它们。
##   一、崖山页「上船同去」开打：海战一层铺在港页上（港页收起），打仗当中按回车 / 空格，不许按到收起的
##       「把粮与硫黄交上去」——那一扇当场落结局「海上宋鬼」、加名声、过五日、弹结局册页，仗还在底下打。
##       收战后结局照常只落一回、册页只弹一张。
##   二、看得见的页照旧按得动：卷首 cg_title「…………」页按回车翻到下一页；开着一局、title_mode 收起之后，
##       回车不许按到收起的「开始旅程」再开一局（前一局没了）。
## 判词：末行 QA_W54_HUNT_STRAY_ENTER PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_HUNT_STRAY_ENTER"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const VIEW := Vector2i(1280, 720)

var _main: Node = null
var _gs: Node = null
var _cal: Node = null
var _fleet: Node = null
var _gm: Node = null
var _rec: Array = []
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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	root.size = VIEW
	print("== 一、崖山「上船同去」开打当中按回车 / 空格")
	await _sec_yashan()
	print("== 二、看得见的页照旧按得动、收起的卷首页按不到")
	await _sec_visible_page()
	_Switches.reset()
	_report()


# ── 按键 ───────────────────────────────────────────────

## 真按一下（按下 + 松开）：键盘回车、空格各走一遍 Input 管线
func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await process_frame
	await process_frame


# ── 一、崖山 ───────────────────────────────────────────

func _open_yashan_page() -> void:
	_gs.set("identity", "merchant")
	_gs.set("ended", "")
	_gs.set("fame", 40)
	_cal.from_dict({"year": 1279, "month": 2, "day": 1})
	_gs.set("last_port", "guangzhou")
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "旗舰", "durability": 300.0, "max_durability": 300.0,
		"crew": 60, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	_fleet.set("morale", 60)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for _i in 3:
		await process_frame
	_main.call("load_scene", "guangzhou")
	await process_frame
	_main.call("_on_yashan")
	await process_frame


func _battle() -> Node:
	for c in _main.get_children():
		if c.has_signal("battle_finished") and not c.is_queued_for_deletion():
			return c
	return null


func _date() -> String:
	return "%d-%d-%d" % [int(_cal.get("year")), int(_cal.get("month")), int(_cal.get("day"))]


func _sec_yashan() -> void:
	await _open_yashan_page()
	_main.call("_yashan_breakout", false)
	for _i in 4:
		await process_frame
	var wm := _battle()
	_check(wm != null, "「上船同去」开打：海战一层挂在港页上")
	if wm == null:
		return
	wm.battle_finished.connect(func(o: String, _d: Dictionary) -> void: _rec.append(o))
	var fame0 := int(_gs.get("fame"))
	var date0 := _date()
	await _tap(KEY_ENTER)
	await _tap(KEY_SPACE)
	_check(_rec.is_empty() and is_instance_valid(wm) and not wm.get("resolved"), "按完回车 / 空格，仗还在打（没收战）")
	_check(str(_gs.get("ended")) == "", "打仗当中按回车 / 空格：没有落结局（ended=「%s」）" % str(_gs.get("ended")))
	_check(int(_gs.get("fame")) == fame0 and _date() == date0,
		"没按到收起的「把粮与硫黄交上去」：名声 %d → %d、日子 %s → %s 都不动" % [fame0, int(_gs.get("fame")), date0, _date()])
	_check(not is_instance_valid(_main.get("_chapter_host")), "没弹结局册页（仗还在底下打）")
	# 收战：照崖山流程回页、落结局、弹一张结局册页
	if is_instance_valid(wm):
		wm.call("_battle_exit", "flee", {"flee_ok": true})
	for _i in 3:
		await process_frame
	_check(str(_gs.get("ended")) == "海上宋鬼", "收战后结局照常落「海上宋鬼」（%s）" % str(_gs.get("ended")))
	_check(is_instance_valid(_main.get("_chapter_host")), "收战后弹结局册页")
	_check(int(_gs.get("fame")) == fame0, "收战落结局不另加名声（%d → %d）" % [fame0, int(_gs.get("fame"))])
	_main.queue_free()
	_main = null
	await process_frame


# ── 二、看得见的页照旧按得动 ───────────────────────────

func _new_main() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await process_frame
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for _i in 3:
		await process_frame


func _sec_visible_page() -> void:
	await _new_main()
	_gs.set("ended", "")
	_gs.set("visited_ports", [])
	_gs.set("flags", {})
	_main.call("load_scene", "cg_title")
	await process_frame
	_check(str(_main.get("current_scene_id")) == "cg_title", "卷首翻页页在屏上（current_scene_id=%s）" % str(_main.get("current_scene_id")))
	await _tap(KEY_ENTER)
	await process_frame
	var now := str(_main.get("current_scene_id"))
	_check(now != "cg_title", "看得见的翻页钮：回车照旧翻过去（%s → %s）" % ["cg_title", now])
	# 开着一局、卷首页收起：回车不许按到收起的「开始旅程」重开一局（钱、日子、旗都不动，页面不换）
	_gs.set("money", 4321)
	_gs.set("flags", {})
	_main.call("load_scene", "xinghua_harbor")
	for _i in 2:
		await process_frame
	var before := str(_main.get("current_scene_id"))
	var title_shown := bool((_main.get("title_mode") as CanvasItem).visible)
	var date_before := _date()
	await _tap(KEY_ENTER)
	await process_frame
	_check(not title_shown and str(_main.get("current_scene_id")) == before and _date() == date_before \
			and not bool(_gs.get("flags").has("return_to_port")),
		"卷首页收起后按回车：没重开一局（卷首 %s、仍在 %s、日子 %s，钱 %d）" % [
			"收着" if not title_shown else "还开着", str(_main.get("current_scene_id")), _date(), int(_gs.get("money"))])
	_main.queue_free()
	_main = null
	await process_frame
