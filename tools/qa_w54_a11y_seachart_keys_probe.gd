extends SceneTree
## lane w54-a11y 海图只用键盘探针（headless，经门锁跑；真起 SeaChart、真按键、真点鼠标）。
##   godot --headless --path . -s res://tools/qa_w54_a11y_seachart_keys_probe.gd
## 病：海图发舶前的航法三策、三张航向牌、「就这一向 / 候风再发 / 回港」同顶上「舆图 / 全图 / 船况」一起全是 FOCUS_NONE
## （验收 CR-5：航行中按住空格加速，拿着焦点的钮会被空格按下），Tab / 方向键 / 回车 / Esc 一样都按不到——只用键盘
## 出了港就卡在海图上：选不了向、发不了船、也回不了港。
## 断言（泉州，景定三年五月初一，一艘客舟；draft_salt 0）：
##   一、刚进海图一路按 Tab：焦点走遍航法三策、三张牌、「候风再发」「回港」，不停在顶上三颗、不停在灰着的「就这一向」；
##       牌上的焦点框不是空框（StyleBoxEmpty）。
##   二、Tab 到第二张牌按回车：选中第二张那一向，整排重发后焦点还在（新排）第二张上；再 Tab 到「就这一向」（这时不灰）
##       按回车即起锚；起锚后九颗全不拿焦点、焦点放掉；航行中按空格不按到任何钮（CR-5）；Esc 不回港。
##   三、鼠标点「候风再发」：过三日、换一手牌，点完不留焦点——再按空格不再过三日（CR-5 对鼠标照旧）。
##   四、C 开合船况；船况开着按 Esc 先合上、人还在海图上；没发舶再按 Esc 即回港（换回 Main、落在泉州港页）。
## 判词：末行 QA_W54_A11Y_SEACHART_KEYS PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。
## 回退即红：去掉 SeaChart._ready 行尾 _a11y_mount() → 一、二红；_lock_hand 行尾 _a11y_sync() 去掉 → 二（起锚后放焦点）红；
## _a11y_drop_click_focus 不连 → 三红；去掉 _shortcut_input → 四红。

const TAG := "QA_W54_A11Y_SEACHART_KEYS"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

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
var _fired: Array = []


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
	# 先走不发舶的一回（三、四：末了 Esc 回港换回 Main），再起一回海图走一、二（发了舶就停在海上收尾，不再换场）
	print("== 三、鼠标点「候风再发」不留焦点")
	var sc := await _open_chart()
	if sc == null:
		_check(false, "海图起来了")
		_report()
		return
	await _sec_mouse_redraw(sc)
	print("== 四、C 开合船况、Esc 先合船况再回港")
	await _sec_escape(sc)
	print("== 一、刚进海图一路按 Tab")
	sc = await _open_chart()
	if sc == null:
		_check(false, "第二回海图起来了")
		_report()
		return
	await _sec_tab_walk(sc)
	print("== 二、只用键盘选第二张牌、发舶；起锚后不拿焦点")
	await _sec_keyboard_sail(sc)
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
	gs.last_port = "quanzhou"
	gs.draft_salt = 0


func _open_chart() -> Node:
	_stage()
	change_scene_to_file("res://scenes/SeaChart.tscn")
	for _i in 12:
		await process_frame
	var sc := current_scene
	if sc == null or str(sc.scene_file_path) != "res://scenes/SeaChart.tscn":
		return null
	return sc


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		Input.parse_input_event(k)
		await process_frame
	await process_frame


## 鼠标左键点控件正中（headless 根窗口有缩放，画布坐标经 get_final_transform 换成窗口坐标）
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


func _hud_buttons(sc: Node) -> Array:
	var out: Array = []
	for b in [sc.get("mode_button")]:
		if b != null:
			out.append(b)
	# 「全图」「船况」与「舆图」同在顶匾那一排
	var row: Node = (sc.get("mode_button") as Node).get_parent()
	for c in row.get_children():
		if c is Button and c not in out:
			out.append(c)
	return out


func _orders(sc: Node) -> Array:
	var out: Array = []
	for c in (sc.get("order_row") as Node).get_children():
		if c is Button:
			out.append(c)
	return out


func _hits(sc: Node) -> Array:
	var out: Array = []
	for w in (sc.get("heading_row") as Node).get_children():
		if w.is_queued_for_deletion():
			continue
		for c in w.get_children():
			if c is Button:
				out.append(c)
	return out


func _nine(sc: Node) -> Array:
	return _orders(sc) + _hits(sc) + [sc.get("sail_button"), sc.get("redraw_button"), sc.get("back_button")]


func _name_of(sc: Node, c: Control) -> String:
	if c == null:
		return "（无）"
	var hs := _hits(sc)
	if c in hs:
		return "第 %d 张牌" % (hs.find(c) + 1)
	if c is Button:
		return "「%s」" % (c as Button).text
	return c.get_class()


## 一路按 Tab 直到焦点落在 want 上（至多 limit 下），返回是否落上
func _tab_to(want: Control, limit := 16) -> bool:
	for _i in limit:
		if _focus() == want:
			return true
		await _tap(KEY_TAB)
	return _focus() == want


func _wire(sc: Node) -> void:
	_fired.clear()
	for c in sc.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		var label: String = (b as Button).text if b is Button else str(b.name)
		if not b.pressed.is_connected(_on_any_pressed):
			b.pressed.connect(_on_any_pressed.bind(label))


func _on_any_pressed(label: String) -> void:
	_fired.append(label)


# ── 一、Tab 一路走 ─────────────────────────────────────

func _sec_tab_walk(sc: Node) -> void:
	root.gui_release_focus()
	var seen: Array = []
	for _i in 16:
		await _tap(KEY_TAB)
		var f := _focus()
		if f != null and f not in seen:
			seen.append(f)
	var names := PackedStringArray()
	for c in seen:
		names.append(_name_of(sc, c))
	print("    Tab 走过：%s" % "、".join(names))
	var want: Array = _orders(sc) + _hits(sc) + [sc.get("redraw_button"), sc.get("back_button")]
	var missing := PackedStringArray()
	for c in want:
		if c not in seen:
			missing.append(_name_of(sc, c))
	_check(missing.is_empty(), "Tab 走遍航法三策、三张牌、「候风再发」「回港」（漏 %s）" % ("无" if missing.is_empty() else "、".join(missing)))
	var stray := PackedStringArray()
	for c in _hud_buttons(sc) + [sc.get("sail_button")]:
		if c in seen:
			stray.append(_name_of(sc, c))
	_check(stray.is_empty(), "Tab 不停在顶上「舆图 / 全图 / 船况」、不停在灰着的「就这一向」（停了 %s）" % ("无" if stray.is_empty() else "、".join(stray)))
	var empty_box := PackedStringArray()
	for h in _hits(sc):
		if (h as Control).get_theme_stylebox("focus") is StyleBoxEmpty:
			empty_box.append(_name_of(sc, h))
	_check(_hits(sc).size() == 3 and empty_box.is_empty(), "三张牌的焦点框不是空框（空框 %s）" % ("无" if empty_box.is_empty() else "、".join(empty_box)))


# ── 二、键盘选牌发舶 ───────────────────────────────────

func _sec_keyboard_sail(sc: Node) -> void:
	root.gui_release_focus()
	var hand: Array = sc.get("_hand")
	var hits := _hits(sc)
	if hand.size() < 3 or hits.size() < 3:
		_check(false, "三张牌都在（手牌 %d、牌 %d）" % [hand.size(), hits.size()])
		return
	var on_second: bool = await _tab_to(hits[1])
	_check(on_second, "Tab 到第二张牌（焦点 %s）" % _name_of(sc, _focus()))
	var old_second := (hits[1] as Object).get_instance_id()
	await _tap(KEY_ENTER)
	for _i in 3:
		await process_frame
	_check(str(sc.get("selected_port")) == str(hand[1]), "回车选中第二张那一向（%s → %s）" % [str(hand[1]), str(sc.get("selected_port"))])
	var now := _hits(sc)
	var f := _focus()
	_check(now.size() == 3 and f != null and f == now[1] and f.get_instance_id() != old_second,
		"整排重发后焦点还在新排第二张上（焦点 %s）" % _name_of(sc, f))
	var sail: Button = sc.get("sail_button")
	_check(not sail.disabled and sail.focus_mode != Control.FOCUS_NONE, "选了向，「就这一向」不灰、收焦点")
	var on_sail: bool = await _tab_to(sail)
	_check(on_sail, "Tab 到「就这一向」（焦点 %s）" % _name_of(sc, _focus()))
	var day0: int = cal.absolute_day()
	await _tap(KEY_ENTER)
	await process_frame
	_check(bool(sc.get("sailing")) and bool(sc.get("voyage_started")), "回车起锚（sailing=%s）" % str(sc.get("sailing")))
	var held := PackedStringArray()
	for c in _nine(sc):
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			held.append(_name_of(sc, c))
	_check(held.is_empty(), "起锚后九颗全不拿焦点（还收焦点的 %s）" % ("无" if held.is_empty() else "、".join(held)))
	_check(_focus() == null, "起锚后焦点放掉（焦点 %s）" % _name_of(sc, _focus()))
	var hud_ok := true
	for c in _hud_buttons(sc):
		hud_ok = hud_ok and (c as Control).focus_mode == Control.FOCUS_NONE
	_check(hud_ok, "顶上「舆图 / 全图 / 船况」照旧不拿焦点")
	_wire(sc)
	await _tap(KEY_SPACE)
	await _tap(KEY_SPACE)
	_check(_fired.is_empty(), "航行中按空格不按到任何钮（按到 %s）" % str(_fired))
	await _tap(KEY_ESCAPE)
	for _i in 3:
		await process_frame
	_check(current_scene == sc and bool(sc.get("sailing")) and not gs.has_flag("return_to_port"),
		"起锚之后 Esc 不回港（还在海图上，日子 %d → %d）" % [day0, cal.absolute_day()])


# ── 三、鼠标点「候风再发」 ─────────────────────────────

func _sec_mouse_redraw(sc: Node) -> void:
	if sc == null:
		_check(false, "第二回海图起来了")
		return
	root.gui_release_focus()
	var redraw: Button = sc.get("redraw_button")
	var day0: int = cal.absolute_day()
	var salt0: int = gs.draft_salt
	await _click(redraw)
	for _i in 3:
		await process_frame
	_check(cal.absolute_day() == day0 + 3 and gs.draft_salt == salt0 + 1, "鼠标点「候风再发」：过三日、换一手（日子 +%d、盐位 +%d）" % [cal.absolute_day() - day0, gs.draft_salt - salt0])
	_check(_focus() != redraw, "点完不留焦点（焦点 %s）" % _name_of(sc, _focus()))
	var day1: int = cal.absolute_day()
	await _tap(KEY_SPACE)
	for _i in 2:
		await process_frame
	_check(cal.absolute_day() == day1, "再按空格不再候三日（日子 %d → %d）" % [day1, cal.absolute_day()])


# ── 四、C / Esc ───────────────────────────────────────

func _sec_escape(sc: Node) -> void:
	if sc == null:
		return
	var layer: Control = sc.get("_condition_layer")
	await _tap(KEY_C)
	_check(layer.visible, "按 C 开船况")
	await _tap(KEY_C)
	_check(not layer.visible, "再按 C 合上")
	await _tap(KEY_C)
	await _tap(KEY_ESCAPE)
	for _i in 2:
		await process_frame
	_check(not layer.visible and current_scene == sc, "船况开着按 Esc：先合上船况，人还在海图上")
	_check(not gs.has_flag("return_to_port"), "合船况那一下没回港")
	await _tap(KEY_ESCAPE)
	for _i in 8:
		await process_frame
	# return_to_port 旗 Main.start_game 一进场就消了，这里看换回的是 Main、落在泉州港页、船不在海上
	var back_main := current_scene != null and str(current_scene.scene_file_path) == "res://scenes/Main.tscn"
	var at := str(current_scene.get("current_scene_id")) if back_main else ""
	_check(back_main and at == "quanzhou" and not bool(fleet.get("at_sea")),
		"没发舶按 Esc 即回港（换回 Main、落在泉州港页；现场 %s・%s）" % [str(current_scene.scene_file_path) if current_scene != null else "无", at])
