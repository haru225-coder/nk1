extends SceneTree
## lane w54-a11y 页面重排后焦点不丢探针（headless，经门锁跑；真起 Main、真按键、真点鼠标）。
##   godot --headless --path . -s res://tools/qa_w54_a11y_focus_keep_probe.gd
## 病：牙行「买 1 / 卖 1」、港页「再候一日」、旅店「歇 N 日」按完整页重排（load_scene 本页 / _build_shore），焦点随旧钮一起
## 离树——键盘玩家每买一件货都得从页首重新 Tab（牙行页四十几颗钮），连按回车第二下什么也不按。
## 断言（泉州，景定三年五月初一，一艘客舟、钱三万）：
##   一、牙行 Tab 到第三张货单的「买 1」回车：买进第三样 1 件，焦点还在第三张货单的「买 1」（重排后的新钮）上；再回车又买 1 件。
##   二、接着 Tab 到第三张货单「卖 1」回车：卖出 1 件，焦点还在那颗「卖 1」上。
##   三、港页 Tab 到「再候一日」回车：过一日，焦点还在「再候一日」上；再回车又过一日。
##   四、旅店 Tab 到「歇 1 日」回车：过一日，焦点还在「歇 1 日」上。
##   五、换了页不替人落焦点：Tab 到岸上牙行门回车进牙行，焦点空着（不自作主张落到页上的钮）。
##   六、鼠标点「买 1」：照买，重排后不还焦点（鼠标点出来的不画框，空格 / 回车不去重按刚点过的钮）。
##   七、焦点在页上的钮时整页离场（换场景 / 退出：Main 整个摘下释放）：不报脚本错（找回焦点那一路不在树上就作罢）。
## 判词：末行 QA_W54_A11Y_FOCUS_KEEP PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。
## 回退即红：KeyNav 不连 gui_focus_changed（或 _regain 不还焦点）→ 一、二、三、四红；_on_focus_changed 不看 has_focus(true) → 六红；
## _regain 不先认树（照旧 await get_tree().process_frame）→ 七红（SCRIPT ERROR：在 null 上取 process_frame）。

const TAG := "QA_W54_A11Y_FOCUS_KEEP"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PORT := "quanzhou"

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
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
	_rates0 = eco.rates.duplicate(true)
	_stage()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	print("== 一、牙行第三张货单「买 1」连按回车")
	await _sec_buy()
	print("== 二、第三张货单「卖 1」")
	await _sec_sell()
	print("== 三、港页「再候一日」连按回车")
	await _sec_shore_wait()
	print("== 四、旅店「歇 1 日」")
	await _sec_inn()
	print("== 五、换了页不替人落焦点")
	await _sec_new_page()
	print("== 六、鼠标点「买 1」不还焦点")
	await _sec_mouse()
	print("== 七、焦点在页上时整页离场")
	await _sec_leave_tree()
	eco.rates = _rates0.duplicate(true)
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
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.broker_salt = 0
	gs.shore_salt = 0
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


func _click(c: Control) -> void:
	var pos: Vector2 = root.get_final_transform() * c.get_global_rect().get_center()
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		root.push_input(mb)
		await process_frame
		await process_frame
	await process_frame


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _label(c: Control) -> String:
	if c == null:
		return "（无）"
	if c is Button and (c as Button).text != "":
		return "「%s」" % (c as Button).text
	return c.get_class()


func _tab_to(want: Control, limit := 80) -> bool:
	for _i in limit:
		if _focus() == want:
			return true
		await _tap(KEY_TAB)
	return _focus() == want


## 柜上第 i 张货单（BrokerSlips 底下第 i 张卡）
func _card(i: int) -> Node:
	var slips: Node = (_main.get("choices_container") as Node).get_node_or_null("BrokerSlips")
	if slips == null:
		return null
	var live: Array = []
	for c in slips.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	return live[i] if i < live.size() else null


func _card_button(i: int, text: String) -> Button:
	var card := _card(i)
	if card == null:
		return null
	for b in card.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _qty(good_id: String) -> int:
	return int(fleet.cargo_qty(good_id))


func _hand_good(i: int) -> String:
	var hand := PackedStringArray(_main.get("broker_hand"))
	return hand[i] if i < hand.size() else ""


func _enter_market() -> void:
	_main.load_scene(PORT)
	await _settle(3)
	_main.load_scene(PORT + "_market")
	await _settle(4)
	root.gui_release_focus()


func _button(text: String) -> Button:
	for b in _main.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Control).is_visible_in_tree():
			return b
	return null


# ── 一、买 1 ───────────────────────────────────────────

func _sec_buy() -> void:
	await _enter_market()
	var good := _hand_good(2)
	var buy := _card_button(2, "买 1")
	if good == "" or buy == null:
		_check(false, "牙行有第三张货单与它的「买 1」（%s）" % good)
		return
	var on: bool = await _tab_to(buy)
	_check(on, "Tab 到第三张货单「买 1」（焦点 %s）" % _label(_focus()))
	var q0 := _qty(good)
	var old_id := buy.get_instance_id()
	await _tap(KEY_ENTER)
	await _settle(3)
	var now := _card_button(2, "买 1")
	_check(_qty(good) == q0 + 1, "回车买进第三样 1 件（%s %d → %d）" % [good, q0, _qty(good)])
	_check(now != null and _focus() == now and now.get_instance_id() != old_id,
		"整页重排后焦点还在第三张货单的「买 1」上（焦点 %s）" % _label(_focus()))
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(_qty(good) == q0 + 2, "再回车又买进 1 件（%s %d → %d）" % [good, q0, _qty(good)])


# ── 二、卖 1 ───────────────────────────────────────────

func _sec_sell() -> void:
	var good := _hand_good(2)
	var sell := _card_button(2, "卖 1")
	if good == "" or sell == null or sell.disabled:
		_check(false, "第三张货单的「卖 1」按得动")
		return
	var on: bool = await _tab_to(sell)
	_check(on, "Tab 到第三张货单「卖 1」（焦点 %s）" % _label(_focus()))
	var q0 := _qty(good)
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(_qty(good) == q0 - 1, "回车卖出 1 件（%s %d → %d）" % [good, q0, _qty(good)])
	var now := _card_button(2, "卖 1")
	_check(now != null and _focus() == now, "重排后焦点还在那颗「卖 1」上（焦点 %s）" % _label(_focus()))


# ── 三、再候一日 ───────────────────────────────────────

func _sec_shore_wait() -> void:
	_main.load_scene(PORT)
	await _settle(4)
	root.gui_release_focus()
	var wait := _button("再候一日")
	var on: bool = await _tab_to(wait)
	_check(on, "Tab 到「再候一日」（焦点 %s）" % _label(_focus()))
	var d0: int = cal.absolute_day()
	await _tap(KEY_ENTER)
	await _settle(3)
	var now := _button("再候一日")
	_check(cal.absolute_day() == d0 + 1, "回车过一日（日子 %d → %d）" % [d0, cal.absolute_day()])
	_check(now != null and _focus() == now, "岸带重排后焦点还在「再候一日」上（焦点 %s）" % _label(_focus()))
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(cal.absolute_day() == d0 + 2, "再回车又过一日（日子 %d → %d）" % [d0, cal.absolute_day()])


# ── 四、旅店 ───────────────────────────────────────────

func _sec_inn() -> void:
	_main.load_scene(PORT)
	await _settle(3)
	_main.load_scene(PORT + "_inn")
	await _settle(4)
	root.gui_release_focus()
	var rest: Button = null
	for b in _main.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("歇 1 日") and (b as Control).is_visible_in_tree():
			rest = b
	if rest == null:
		_check(false, "旅店有「歇 1 日」")
		return
	var label := rest.text
	var on: bool = await _tab_to(rest)
	_check(on, "Tab 到「%s」（焦点 %s）" % [label, _label(_focus())])
	var d0: int = cal.absolute_day()
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(cal.absolute_day() == d0 + 1, "回车歇一日（日子 %d → %d）" % [d0, cal.absolute_day()])
	var f := _focus()
	_check(f is Button and (f as Button).text == label and str(_main.get("current_scene_id")) == PORT + "_inn",
		"旅店页重排后焦点还在「%s」上（焦点 %s）" % [label, _label(f)])


# ── 五、换了页 ─────────────────────────────────────────

func _sec_new_page() -> void:
	_main.load_scene(PORT)
	await _settle(4)
	root.gui_release_focus()
	var door: Button = null
	var row: Node = _main.find_child("ShoreDoors", true, false)
	if row != null:
		for b in row.find_children("*", "Button", true, false):
			for l in (b as Node).get_parent().find_children("*", "Label", true, false):
				if (l as Label).text == "牙行":
					door = b
	if door == null:
		_check(false, "岸上有牙行门")
		return
	var on: bool = await _tab_to(door)
	_check(on, "Tab 到岸上牙行门")
	await _tap(KEY_ENTER)
	await _settle(4)
	_check(str(_main.get("current_scene_id")) == PORT + "_market", "回车进牙行（页 %s）" % str(_main.get("current_scene_id")))
	_check(_focus() == null, "换了页，焦点空着、不自作主张落到页上的钮（焦点 %s）" % _label(_focus()))


# ── 六、鼠标 ───────────────────────────────────────────

func _sec_mouse() -> void:
	await _enter_market()
	var good := _hand_good(0)
	var buy := _card_button(0, "买 1")
	if good == "" or buy == null:
		_check(false, "牙行第一张货单有「买 1」")
		return
	var q0 := _qty(good)
	await _click(buy)
	await _settle(3)
	_check(_qty(good) == q0 + 1, "鼠标点「买 1」照买（%s %d → %d）" % [good, q0, _qty(good)])
	_check(_focus() == null, "重排后不还焦点（焦点 %s）" % _label(_focus()))


# ── 七、整页离场 ───────────────────────────────────────

func _sec_leave_tree() -> void:
	_main.load_scene(PORT)
	await _settle(4)
	root.gui_release_focus()
	var wait := _button("再候一日")
	var on: bool = await _tab_to(wait)
	_check(on, "Tab 到「再候一日」（焦点 %s）" % _label(_focus()))
	var errs0: int = _tally.lines.size()
	root.remove_child(_main)
	_main.queue_free()
	_main = null
	await _settle(6)
	_check(_tally.lines.size() == errs0, "焦点在页上时整页摘下释放：不报脚本错（新增 %d 条%s）" % [
		_tally.lines.size() - errs0, "：" + str(_tally.lines[errs0]) if _tally.lines.size() > errs0 else ""])
