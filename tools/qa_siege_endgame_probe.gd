extends SceneTree
## 守城页 / 终局港口页巡检：截 01..N 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/siege/。
## 摆场仿 ShotTour._site_siege / _site_ended_port：先进泉州港页，再立守城（1276-11 兴化）或落定结局回泉州。
## 触发：首次进守城 / 终局岸带各演一次纪实题签（「兴化军・围城」印「城」、「港名・结局」印「终」）；
## -s 工具脚本下 play_transition 当帧直通，这里直接调 UiTransition 助手截墨幕那一帧。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_siege_endgame_probe.gd   # 截图门禁（须出 8 张）
##       godot --headless --path . -s res://tools/qa_siege_endgame_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截、墨幕按停拍相位截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_siege_endgame_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("siege")
const TAG := "QA_SIEGE"
const EXPECTED_SHOTS := 8
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
	print("QA_SIEGE_BEGIN")

	_expect(str(_UT.siege_title()) == "兴化军・围城", "守城题签「%s」" % _UT.siege_title())
	_expect(str(_UT.endgame_title("泉州", ENDING)) == "泉州・" + ENDING, "终局题签「%s」" % _UT.endgame_title("泉州", ENDING))
	_expect(str(_UT.endgame_title("", ENDING)) == ENDING, "无港名时终局题签只写结局名")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	ShotGate.frame_pressure(self)
	# 被测树自检（lane w24-b5 接 wave23-a9 共用面）：Main 挂不出 / 挂空壳秒级判红；字段在过帧后点名
	_main = ShotGate.start_tree_probe("res://scenes/Main.tscn", _fails, "SiegeEndgame Main")
	if _main == null:
		quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
		return
	root.add_child(_main)
	await _settle(10)
	if not ShotGate.check_fields(_main, {"current_scene_id": "Main.gd Parse Error / load_scene 断"}, _fails, "SiegeEndgame Main"):
		quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
		return

	# —— 守城：先进泉州港页，再照 ShotTour._site_siege 立守城进兴化
	gs.from_dict({})
	cal.from_dict({"year": 1276, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	await _settle(6)
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	gs.siege_begin()
	gs.chapter = 4
	gs.last_port = "xinghua"
	_main.load_scene("xinghua")
	await _settle(8)
	_expect(str(_main.port_title.text) == "兴化军・围城", "守城匾「%s」" % _main.port_title.text)
	_expect(_seen().has("siege"), "首次进守城岸带记下题签已演")
	_expect(_band_count("SiegeStat") == 1, "城防账一方（%d）" % _band_count("SiegeStat"))
	_expect(_slip_has_head("SiegeStat"), "城防账有泥金题抬头与分隔线")
	await _shot("01_siege_shore")

	var node: CanvasLayer = _UT.siege_open(_main, str(cal.call("get_date_string")), Callable())
	await _hold_shot(node, "02_transition_siege")

	_main.call("_on_facility_pressed", {"id": "siege_grain", "title": "市场"})
	await _settle(6)
	_main.load_scene("xinghua")
	await _settle(8)
	_expect(_band_count("SiegeStat") == 1, "进出市场后城防账仍一方（%d）" % _band_count("SiegeStat"))
	_expect(_seen().size() == 1, "进出设施不重复记题签")
	await _shot("03_siege_back")

	gs.call("siege_set", "grain", int(gs.get("SIEGE_GRAIN_PER_ROUND")) - 1)
	_main.call("_build_shore")
	await _settle(6)
	await _shot("04_siege_grain_warn")

	# —— 终局：回泉州，落定一个结局（ShotTour._site_ended_port 同摆）
	gs.from_dict({})
	cal.from_dict({"year": 1279, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	await _settle(6)
	gs.set_flag("sided_pu")
	gs.finish(ENDING, "市舶司的册子换了封面。（巡检摆场）")
	_main.load_scene("quanzhou")
	await _settle(8)
	var want := "泉州・" + ENDING
	_expect(str(_main.port_title.text) == want, "终局匾「%s」" % _main.port_title.text)
	_expect(_seen().has("ended"), "首次进终局岸带记下题签已演")
	_expect(_band_count("EpilogueSlip") == 1, "航海札记一方（%d）" % _band_count("EpilogueSlip"))
	_expect(_slip_has_head("EpilogueSlip"), "航海札记有泥金题抬头与分隔线")
	await _shot("05_ended_port")

	node = _UT.endgame_open(_main, "泉州", ENDING, str(gs.get("ended_at")), Callable())
	await _hold_shot(node, "06_transition_endgame")

	_main.call("_on_reread_ending")
	await _settle(6)
	await _shot("07_ended_reread_sheet")
	_main.call("_confirm_chapter_sheet")
	await _settle(8)
	_expect(str(_main.port_title.text) == want, "重读后终局匾不累加「%s」" % _main.port_title.text)
	_expect(_band_count("EpilogueSlip") == 1, "重读后札记仍一方（%d）" % _band_count("EpilogueSlip"))
	await _shot("08_ended_port_back")

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("QA_SIEGE_CHECK ok ", what)
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
	return band.find_children(n, "", true, false).size() + (1 if band.name == n else 0)


func _slip_has_head(n: String) -> bool:
	var band := _band()
	if band == null:
		return false
	var hits := band.find_children(n, "", true, false)
	if hits.is_empty():
		return false
	var slip: Node = hits[0]
	return slip.find_child("BandHead", true, false) != null \
		and not slip.find_children("*", "HSeparator", true, false).is_empty()


func _hold_shot(node: CanvasLayer, stem: String) -> void:
	if node == null:
		print("QA_SIEGE_SKIP_TRANSITION %s (headless)" % stem)
		return
	# 截题签停拍那一拍：按墨幕相位等，不数帧（原 36 帧：快机上只合 153 ms 还在淡入，满载慢帧下已整幕收场，lane gd14）
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
