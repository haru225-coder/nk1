extends SceneTree
## 终局港口「重读结局」入口巡检：截 01..06 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/ending/。
## 摆场仿 qa_siege_endgame_probe 终局段：先进泉州港页，落定一个结局再回泉州。
## 锁：札记抬头旁注终局时地、笺脚注文；「重读结局」是动作行主钮（有 tooltip）；点按只翻开既有册页，
## 不重播岸带题签（_shore_title_seen 仍只一条）；合上后港名匾不累加、札记仍一方、动作行钮数不变；册页已开时再点不叠。
## -s 工具脚本下 play_transition 当帧直通，02 帧直接调 UiTransition.endgame_open 截墨幕。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_ending_reread_probe.gd   # 截图门禁（须出 6 张）
##       godot --headless --path . -s res://tools/qa_ending_reread_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截、墨幕按停拍相位截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_ending_reread_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("ending")
const TAG := "QA_ENDING"
const EXPECTED_SHOTS := 6
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const _UT := preload("res://scripts/ui/UiTransition.gd")
const ENDING := "泉州蒲氏的船"

var _main: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_ENDING_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	ShotGate.frame_pressure(self)
	root.add_child(_main)
	await _settle(10)

	gs.from_dict({})
	cal.from_dict({"year": 1279, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	await _settle(6)
	gs.set_flag("sided_pu")
	gs.finish(ENDING, "市舶司的册子换了封面。蒲氏的船照旧进出后渚，舱单上写的是另一个年号。（巡检摆场）")
	_main.load_scene("quanzhou")
	await _settle(8)

	var want := "泉州・" + ENDING
	var ended_at := str(gs.get("ended_at"))
	_expect(str(_main.port_title.text) == want, "终局匾「%s」" % _main.port_title.text)
	_expect(_seen().has("ended") and _seen().size() == 1, "首次进终局岸带记下题签已演（%d）" % _seen().size())
	_expect(_band_count("EpilogueSlip") == 1, "航海札记一方（%d）" % _band_count("EpilogueSlip"))
	_expect(_head_has_aside(ended_at), "札记抬头旁注终局时地「%s」（淡字 16px）" % ended_at)
	_expect(_band_count("EpilogueFoot") == 1, "札记笺脚有「重读结局」注文")
	_expect(_min_font("EpilogueSlip") >= 16, "札记最小字号 ≥16（%d）" % _min_font("EpilogueSlip"))
	var btn := _reread_btn()
	_expect(btn != null and btn.visible, "动作行有「重读结局」")
	if btn != null:
		_expect(btn.get_parent().get_child(0) == btn, "「重读结局」是动作行首钮（主钮）")
		_expect(btn.custom_minimum_size.x >= 240 and btn.custom_minimum_size.y >= 52, "重读钮热区 ≥240×52")
		_expect(btn.tooltip_text != "", "重读钮有 tooltip「%s」" % btn.tooltip_text)
	var acts0 := _action_count()
	await _shot("01_ended_port_shore")

	var node: CanvasLayer = _UT.endgame_open(_main, "泉州", ENDING, ended_at, Callable())
	await _hold_shot(node, "02_endgame_title")

	_main.call("_on_reread_ending")
	await _settle(6)
	_expect(_sheet_count() == 1, "点重读后册页一张（%d）" % _sheet_count())
	_expect(_sheet_has_text("重读"), "册页眉题含「重读」")
	_expect(_sheet_has_text("合上册页"), "册页钮为「合上册页」")
	_expect(_seen().size() == 1, "重读不重播岸带题签")
	_expect(_transition_count() == 0, "重读不起墨幕题签（%d）" % _transition_count())
	_main.call("_on_reread_ending")
	await _settle(3)
	_expect(_sheet_count() == 1, "册页已开时再点不叠（%d）" % _sheet_count())
	await _shot("03_reread_sheet")

	_main.call("_confirm_chapter_sheet")
	await _settle(8)
	_check_back(want, acts0, "合上册页")
	await _shot("04_back_to_port")

	btn = _reread_btn()
	if btn != null:
		btn.emit_signal("pressed")
	await _settle(6)
	_expect(_sheet_count() == 1, "再点重读册页仍一张（%d）" % _sheet_count())
	_expect(_seen().size() == 1, "再点重读仍不重播题签")
	await _shot("05_reread_again")

	_main.call("_confirm_chapter_sheet")
	await _settle(8)
	_check_back(want, acts0, "再合上")
	await _shot("06_back_one_slip")

	_expect(str(gs.get("ended")) == ENDING and str(gs.get("ended_at")) == ended_at, "重读不改终局名 / 时地")

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _check_back(want: String, acts0: int, tag: String) -> void:
	_expect(_sheet_count() == 0, "%s后册页收起（%d）" % [tag, _sheet_count()])
	_expect(str(_main.port_title.text) == want, "%s后港名匾不累加「%s」" % [tag, _main.port_title.text])
	_expect(_band_count("EpilogueSlip") == 1, "%s后札记仍一方（%d）" % [tag, _band_count("EpilogueSlip")])
	_expect(_action_count() == acts0, "%s后动作行钮数不变（%d → %d）" % [tag, acts0, _action_count()])
	_expect(_seen().size() == 1, "%s后题签记录仍一条" % tag)



func _sheet_has_text(frag: String) -> bool:
	var host = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return false
	for n in host.find_children("*", "", true, false):
		if n is Label and frag in str(n.text):
			return true
		if n is Button and frag in str(n.text):
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("QA_ENDING_CHECK ok ", what)
	else:
		_fails.append(what)


func _seen() -> Dictionary:
	var d = _main.get("_shore_title_seen")
	return d if d is Dictionary else {}


func _band() -> Node:
	return _main.port_mode.get_node_or_null("ShoreBand")


func _band_count(n: String) -> int:
	var band := _band()
	if band == null:
		return -1
	var hits := 0
	for c in band.find_children(n, "", true, false):
		if not c.is_queued_for_deletion():
			hits += 1
	return hits


func _action_count() -> int:
	var band := _band()
	var acts: Node = band.get_node_or_null("ShoreActions") if band != null else null
	if acts == null:
		return -1
	var n := 0
	for c in acts.get_children():
		if c is Button and not c.is_queued_for_deletion():
			n += 1
	return n


func _reread_btn() -> Button:
	var band := _band()
	if band == null:
		return null
	var hit := band.find_child("RereadEnding", true, false)
	return hit as Button


func _head_has_aside(aside: String) -> bool:
	var band := _band()
	if band == null or aside == "":
		return false
	var slips := band.find_children("EpilogueSlip", "", true, false)
	if slips.is_empty():
		return false
	var head: Node = slips[0].find_child("BandHead", true, false)
	if head == null:
		return false
	for l in head.find_children("*", "Label", true, false):
		if (l as Label).text == aside and (l as Label).get_theme_font_size("font_size") == 16:
			return true
	return false


func _min_font(n: String) -> int:
	var band := _band()
	if band == null:
		return -1
	var slips := band.find_children(n, "", true, false)
	if slips.is_empty():
		return -1
	var lo := 999
	for l in slips[0].find_children("*", "Label", true, false):
		lo = mini(lo, (l as Label).get_theme_font_size("font_size"))
	return lo


func _sheet_count() -> int:
	var n := 0
	for c in _main.get_children():
		if str(c.name).begins_with("ChapterSheet") and not c.is_queued_for_deletion() and (c as Control).visible:
			n += 1
	return n


func _transition_count() -> int:
	return get_nodes_in_group(_UT.GROUP).size()


func _hold_shot(node: CanvasLayer, stem: String) -> void:
	if node == null:
		print("QA_ENDING_SKIP_TRANSITION %s (headless)" % stem)
		return
	# 截题签停拍那一拍：按墨幕相位等，不数帧（原 72 帧：快机上只合 306 ms 还在淡入，满载慢帧下已整幕收场，lane gd14）
	var why := await Clock.wait_hold(self, node)
	if why != "":
		_fails.append("%s 没截到墨幕停拍：%s" % [stem, why])
		print("  ✗ %s 没截到墨幕停拍：%s" % [stem, why])
	else:
		await _shot(stem)
		if not Clock.holding(node):
			_fails.append("%s 截图时墨幕已过停拍" % stem)
			print("  ✗ %s 截图时墨幕已过停拍" % stem)
	if is_instance_valid(node):
		node.call("_abort")
	await _settle(4)


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)
