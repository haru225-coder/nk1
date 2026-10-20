extends SceneTree
## lane w54-a11y Esc 有出口探针（headless，经门锁跑；真起 Main、真按键）。
##   godot --headless --path . -s res://tools/qa_w54_a11y_escape_probe.gd
## 病：Main 不认 Esc——进了牙行、旅店、船屋……任何一处设施页，或见了人，按 Esc 都没有反应，只能摸到页脚「离开」去点；
## 船籍簿开着按 Esc 也合不上（人物志 / 名册 / 市舶纪事 / 航海日志各自认 Esc，只有船籍簿和设施页没有出口）。
## 断言（泉州，景定三年五月初一，一艘客舟、钱三万）：
##   一、九处设施页（牙行 / 市舶司 / 船屋 / 酒馆 / 旅店 / 行会 / 贡院 / 住处 / 寺观）逐一：按 Esc 回泉州港页，钱与日子不动。
##   二、牙行见林阿舶：见面页按 Esc 回牙行页（不是回港页），再按 Esc 回港页。
##   三、剧情页 city_tavern（只一条「离开」）：Esc 同点「离开」；岔路页 prologue_harbor（两条真路、挂 no_enter）：Esc 不替人选。
##   四、牙行页开着船籍簿：Esc 先合船籍簿、页不换；再按 Esc 才离开牙行。
##   五、港页按 Esc 不动（页、钱、日子都不变）；册页开着按 Esc 不替人落定（册页还在）。
##   六、牙行页开着人物志按 Esc：只合人物志，底下牙行页不离开。
## 判词：末行 QA_W54_A11Y_ESCAPE PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。
## 回退即红：KeyNav._unhandled_input 不认 ui_cancel（或去掉 Main._ready 行尾 _a11y_mount()）→ 一、二、三（city_tavern）、四红。

const TAG := "QA_W54_A11Y_ESCAPE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PORT := "quanzhou"
const PAGES := ["market", "yamen", "shipyard", "tavern", "inn", "guild", "exam", "residence", "temple"]

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	_stage()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	print("== 一、九处设施页按 Esc 回港页")
	await _sec_pages()
	print("== 二、见面页按 Esc 回设施页")
	await _sec_npc()
	print("== 三、剧情页与岔路页")
	await _sec_story()
	print("== 四、船籍簿开着先合船籍簿")
	await _sec_ledger()
	print("== 五、港页与册页上按 Esc")
	await _sec_hub_and_sheet()
	print("== 六、人物志开着只合人物志")
	await _sec_codex()
	_report()


# ── 摆场与按键 ─────────────────────────────────────────

func _stage() -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1262, "month": 5, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.last_port = PORT


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await process_frame
	await process_frame


func _scene() -> String:
	return str(_main.get("current_scene_id"))


func _at_port() -> bool:
	return _scene() == PORT and bool((_main.get("port_mode") as CanvasItem).visible)


func _open(scene_id: String) -> void:
	_main.load_scene(PORT)
	await _settle(3)
	_main.load_scene(scene_id)
	await _settle(4)
	root.gui_release_focus()


# ── 一、九处设施页 ─────────────────────────────────────

func _sec_pages() -> void:
	for suffix in PAGES:
		var page := "%s_%s" % [PORT, suffix]
		await _open(page)
		if _scene() != page:
			_check(false, "进了 %s（现页 %s）" % [page, _scene()])
			continue
		var money0: int = gs.money
		var day0: int = cal.absolute_day()
		await _tap(KEY_ESCAPE)
		await _settle(3)
		_check(_at_port() and gs.money == money0 and cal.absolute_day() == day0,
			"%s 按 Esc 回泉州港页（现页 %s，钱 %d → %d，日子 %d → %d）" % [page, _scene(), money0, gs.money, day0, cal.absolute_day()])


# ── 二、见面页 ─────────────────────────────────────────

func _sec_npc() -> void:
	await _open(PORT + "_market")
	_main.call("_show_npc_mode", "merchant_lin", "林阿舶")
	await _settle(3)
	var npc_mode: CanvasItem = _main.get("npc_mode")
	_check(npc_mode.visible, "牙行见林阿舶：见面页开着")
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(not npc_mode.visible and _scene() == PORT + "_market" and bool((_main.get("investigation_mode") as CanvasItem).visible),
		"见面页按 Esc 回牙行页（现页 %s）" % _scene())
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(_at_port(), "牙行页再按 Esc 回港页（现页 %s）" % _scene())


# ── 三、剧情页与岔路页 ─────────────────────────────────

func _sec_story() -> void:
	await _open("city_tavern")
	_check(_scene() == "city_tavern", "进了剧情页 city_tavern（只一条「离开」）")
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(_scene() != "city_tavern", "city_tavern 按 Esc 同点「离开」（→ %s）" % _scene())
	await _open("prologue_harbor")
	var forks := 0
	for b in (_main.get("choices_container") as Node).get_children():
		if b is Button and (b as Button).has_meta("no_enter"):
			forks += 1
	_check(_scene() == "prologue_harbor" and forks >= 2, "岔路页 prologue_harbor 两条真路都挂 no_enter（%d 条）" % forks)
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(_scene() == "prologue_harbor", "岔路页按 Esc 不替人选（现页 %s）" % _scene())


# ── 四、船籍簿 ─────────────────────────────────────────

func _sec_ledger() -> void:
	await _open(PORT + "_market")
	_main.call("_toggle_ledger")
	await _settle(3)
	var layer: Control = _main.get("_ledger_layer")
	_check(layer.visible, "牙行页开船籍簿")
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(not layer.visible and _scene() == PORT + "_market", "Esc 先合船籍簿、页不换（现页 %s）" % _scene())
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(_at_port(), "再按 Esc 才离开牙行（现页 %s）" % _scene())


# ── 五、港页与册页 ─────────────────────────────────────

func _sec_hub_and_sheet() -> void:
	_main.load_scene(PORT)
	await _settle(4)
	root.gui_release_focus()
	var money0: int = gs.money
	var day0: int = cal.absolute_day()
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(_at_port() and gs.money == money0 and cal.absolute_day() == day0, "港页按 Esc 不动（现页 %s）" % _scene())
	_main.call("_show_notice_dialog", "", "探针", "这一页只是盖在港页上的册页。")
	await _settle(4)
	await _tap(KEY_ESCAPE)
	await _settle(3)
	_check(is_instance_valid(_main.get("_chapter_host")), "册页开着按 Esc 不替人落定（册页还在）")
	_main.call("_confirm_chapter_sheet")
	await _settle(4)


# ── 六、人物志 ─────────────────────────────────────────

func _sec_codex() -> void:
	await _open(PORT + "_market")
	_main.call("_open_codex", "")
	await _settle(4)
	_check(is_instance_valid(_main.get("_codex")), "牙行页开人物志")
	await _tap(KEY_ESCAPE)
	await _settle(12)
	_check(not is_instance_valid(_main.get("_codex")) and _scene() == PORT + "_market",
		"Esc 只合人物志，底下牙行页不离开（现页 %s）" % _scene())
