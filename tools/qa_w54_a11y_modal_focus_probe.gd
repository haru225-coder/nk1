extends SceneTree
## lane w54-a11y 浮层开着焦点不走到底下探针（headless，经门锁跑；真起 Main、真按键）。
##   godot --headless --path . -s res://tools/qa_w54_a11y_modal_focus_probe.gd
## 病：人物志 / 名册 / 市舶纪事 / 船籍簿 / 册页盖在页上时，Tab / 方向键照样走到暗幕底下的工席门、动作钮、选项上（Godot 的焦点
## 轮转不看谁被盖住），回车就在浮层底下开门、接委办、翻剧情页——人物志开着按两下 Tab 一下回车，底下的行会页就开了；
## 船籍簿不吞按键，开着时按回车，Main 照「按本页头一扇门」把底下剧情页的选项按了。
## 断言（泉州，景定三年五月初一，一艘客舟、钱三万）：
##   一、港页 Tab 到「人物志」回车开浮页：一路 Tab 焦点不出浮页（不落到岸门 / 动作钮）；回车不开底下的门；Esc 合上后焦点回到「人物志」。
##   二、牙行页 Tab 到「船籍簿」回车开：一路 Tab 焦点只在船籍簿里（不落到「细则」「接下委办」货单钮）；放掉焦点按回车不接委办、
##       钱不动、页不换；Tab 到「合上」回车合上，焦点回到「船籍簿」。
##   三、剧情页（city_tavern 只一条「离开」）：没开船籍簿时回车照旧按「离开」（对照）；开着船籍簿按回车不按底下的「离开」。
##   四、港页开市舶纪事、名册：一路 Tab 焦点不落到岸门 / 动作钮上。
##   五、册页盖在港页上：焦点原在岸门上，册页一开焦点放掉、一路 Tab 不落到岸门；回车落定册页、不开门。
## 判词：末行 QA_W54_A11Y_MODAL_FOCUS PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。
## 回退即红：去掉 Main._ready 行尾的 _a11y_mount()（或 KeyNav._sync 不改 focus_behavior_recursive）→ 一、二、四、五红；
## KeyNav._unhandled_input 不收回车 → 三红。航海日志册页自有焦点环（lane w53-5），qa_w53_5_save_sheet_probe 钉着，这里不另摆。

const TAG := "QA_W54_A11Y_MODAL_FOCUS"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const PORT := "quanzhou"

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
	print("== 一、港页开人物志")
	await _sec_codex()
	print("== 二、牙行页开船籍簿")
	await _sec_ledger_market()
	print("== 三、剧情页开船籍簿按回车")
	await _sec_ledger_story()
	print("== 四、港页开市舶纪事、名册")
	await _sec_vision_and_roster()
	print("== 五、册页盖在港页上")
	await _sec_chapter_sheet()
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


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _inside(host: Node, c: Node) -> bool:
	return host != null and c != null and (c == host or host.is_ancestor_of(c))


func _label(c: Control) -> String:
	if c == null:
		return "（无）"
	if c is Button and (c as Button).text != "":
		return "「%s」" % (c as Button).text
	# 岸门：覆盖钮没有字，门牌在同一张卡上（绢本卡上头一个 Label 是淡墨水印单字，跳过）
	var titles := PackedStringArray()
	if c.get_parent() != null:
		for l in c.get_parent().find_children("*", "Label", true, false):
			if (l as Label).text.length() >= 2:
				titles.append((l as Label).text)
	return "门%s" % ("「%s」" % titles[0] if not titles.is_empty() else "")


func _button(host: Node, text: String) -> Button:
	for b in host.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Control).is_visible_in_tree():
			return b
	return null


## 岸上那几扇开着的门（ShoreDoors 底下各卡的覆盖钮）
func _doors() -> Array:
	var out: Array = []
	var row: Node = _main.find_child("ShoreDoors", true, false)
	if row == null:
		return out
	for b in row.find_children("*", "Button", true, false):
		out.append(b)
	return out


func _door(title: String) -> Button:
	for b in _doors():
		for l in (b as Node).get_parent().find_children("*", "Label", true, false):
			if (l as Label).text == title:
				return b
	return null


## 一路按 Tab 直到焦点落在 want 上（至多 limit 下；牙行页四十几颗钮，顶匾的「船籍簿」排在一圈最后）
func _tab_to(want: Control, limit := 80) -> bool:
	for _i in limit:
		if _focus() == want:
			return true
		await _tap(KEY_TAB)
	return _focus() == want


## 按 n 下 Tab，记下焦点落过的、不在 host 里的控件
func _tab_strays(host: Node, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for _i in n:
		await _tap(KEY_TAB)
		var f := _focus()
		if f != null and not _inside(host, f):
			out.append(_label(f))
	return out


func _port_page() -> void:
	_main.load_scene(PORT)
	await _settle(4)
	root.gui_release_focus()


# ── 一、人物志 ─────────────────────────────────────────

func _sec_codex() -> void:
	await _port_page()
	var opener := _button(_main, "人物志")
	if opener == null:
		_check(false, "港页有「人物志」钮")
		return
	var on: bool = await _tab_to(opener)
	_check(on, "Tab 到「人物志」（焦点 %s）" % _label(_focus()))
	await _tap(KEY_ENTER)
	await _settle(4)
	var codex: Node = _main.get("_codex")
	_check(is_instance_valid(codex), "回车开人物志浮页")
	if not is_instance_valid(codex):
		return
	_check(_focus() == null or _inside(codex, _focus()), "浮页一开，焦点不在浮页外（焦点 %s）" % _label(_focus()))
	var strays := await _tab_strays(codex, 5)
	_check(strays.is_empty(), "浮页开着一路 Tab，焦点不出浮页（落到 %s）" % ("无" if strays.is_empty() else "、".join(strays)))
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(str(_main.get("current_scene_id")) == PORT, "浮页开着按回车不开底下的门（页 %s）" % str(_main.get("current_scene_id")))
	if str(_main.get("current_scene_id")) != PORT:
		return
	await _tap(KEY_ESCAPE)
	await _settle(12)
	_check(not is_instance_valid(_main.get("_codex")), "Esc 合上人物志")
	_check(_focus() == opener, "合上后焦点回到「人物志」（焦点 %s）" % _label(_focus()))


# ── 二、船籍簿（牙行页） ───────────────────────────────

func _sec_ledger_market() -> void:
	await _port_page()
	var door := _door("牙行")
	if door == null:
		_check(false, "岸上有「牙行」门")
		return
	door.pressed.emit()
	await _settle(4)
	_check(str(_main.get("current_scene_id")) == PORT + "_market", "进了牙行（页 %s）" % str(_main.get("current_scene_id")))
	root.gui_release_focus()
	var book := _button(_main, "船籍簿")
	var on: bool = await _tab_to(book)
	_check(on, "Tab 到「船籍簿」（焦点 %s）" % _label(_focus()))
	await _tap(KEY_ENTER)
	await _settle(3)
	var layer: Control = _main.get("_ledger_layer")
	_check(layer.visible, "回车开船籍簿")
	var strays := await _tab_strays(layer, 5)
	_check(strays.is_empty(), "船籍簿开着一路 Tab，焦点只在船籍簿里（落到 %s）" % ("无" if strays.is_empty() else "、".join(strays)))
	root.gui_release_focus()
	var money0: int = gs.money
	var contract0 := str(gs.get("contract"))
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(gs.money == money0 and str(gs.get("contract")) == contract0 and str(_main.get("current_scene_id")) == PORT + "_market",
		"放掉焦点按回车：没接委办、钱不动、页不换")
	var close := _button(layer, "合上")
	var on_close: bool = await _tab_to(close, 6)
	_check(on_close, "Tab 到船籍簿的「合上」（焦点 %s）" % _label(_focus()))
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(not layer.visible, "回车合上船籍簿")
	_check(_focus() == book, "合上后焦点回到「船籍簿」（焦点 %s）" % _label(_focus()))


# ── 三、船籍簿（剧情页） ───────────────────────────────

func _sec_ledger_story() -> void:
	_main.load_scene("city_tavern")
	await _settle(4)
	root.gui_release_focus()
	var leave := _button(_main.get("choices_container"), "离开")
	_check(leave != null and str(_main.get("current_scene_id")) == "city_tavern", "剧情页 city_tavern 上有「离开」")
	await _tap(KEY_ENTER)
	await _settle(3)
	var moved := str(_main.get("current_scene_id"))
	_check(moved != "city_tavern", "对照：没开船籍簿时回车照旧按「离开」（city_tavern → %s）" % moved)
	_main.load_scene("city_tavern")
	await _settle(4)
	root.gui_release_focus()
	_main.call("_toggle_ledger")
	await _settle(3)
	var layer: Control = _main.get("_ledger_layer")
	_check(layer.visible, "剧情页上开船籍簿")
	await _tap(KEY_ENTER)
	await _settle(3)
	_check(str(_main.get("current_scene_id")) == "city_tavern", "开着船籍簿按回车，不按底下的「离开」（页 %s）" % str(_main.get("current_scene_id")))
	_main.call("_close_ledger")
	await _settle(2)


# ── 四、市舶纪事、名册 ─────────────────────────────────

func _sec_vision_and_roster() -> void:
	await _port_page()
	_main.call("_open_vision_stage")
	await _settle(4)
	var vs: Node = _main.get("_vision_stage")
	_check(is_instance_valid(vs), "开市舶纪事")
	if is_instance_valid(vs):
		var strays := await _tab_strays(vs, 4)
		_check(strays.is_empty(), "市舶纪事开着一路 Tab，焦点不落到岸门 / 动作钮（落到 %s）" % ("无" if strays.is_empty() else "、".join(strays)))
		_main.call("_close_vision_stage")
		await _settle(4)
	await _port_page()
	_main.call("_open_chars_wire", "")
	await _settle(4)
	var ov: Node = _main.get("_chars_wire")
	_check(is_instance_valid(ov), "开名册")
	if is_instance_valid(ov):
		var strays2 := await _tab_strays(ov, 4)
		_check(strays2.is_empty(), "名册开着一路 Tab，焦点不落到岸门 / 动作钮（落到 %s）" % ("无" if strays2.is_empty() else "、".join(strays2)))
		_main.call("_close_chars_wire")
		await _settle(12)


# ── 五、册页 ───────────────────────────────────────────

func _sec_chapter_sheet() -> void:
	await _port_page()
	var door := _door("牙行")
	if door == null:
		_check(false, "岸上有「牙行」门（册页一节）")
		return
	door.grab_focus()
	await _settle(1)
	_main.call("_show_notice_dialog", "", "探针", "这一页只是盖在港页上的册页。")
	await _settle(4)
	var host: Node = _main.get("_chapter_host")
	_check(is_instance_valid(host), "册页盖在港页上")
	if not is_instance_valid(host):
		return
	_check(_focus() == null or _inside(host, _focus()), "册页一开，岸门上的焦点放掉（焦点 %s）" % _label(_focus()))
	var strays := await _tab_strays(host, 4)
	_check(strays.is_empty(), "册页开着一路 Tab，焦点不落到岸门（落到 %s）" % ("无" if strays.is_empty() else "、".join(strays)))
	root.gui_release_focus()
	await _tap(KEY_ENTER)
	await _settle(4)
	_check(not is_instance_valid(_main.get("_chapter_host")) and str(_main.get("current_scene_id")) == PORT,
		"回车落定册页、不开门（页 %s）" % str(_main.get("current_scene_id")))
