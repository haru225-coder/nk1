extends SceneTree
## 船屋坞位工席巡检：截 01..N 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/drydock/。
## 摆场：泉州船屋坞位 → 伤船体修船题签 → 购入客舟 → 换坞题签 → 升帆题签。
## -s 工具脚本下 play_transition 当帧直通，题签帧直接调 UiTransition.drydock_open。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_drydock_probe.gd   # 截图门禁（须出 9 张）
##       godot --headless --path /workspace/nk1 -s res://tools/qa_drydock_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截、墨幕按停拍相位截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_drydock_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("drydock")
const TAG := "QA_DRYDOCK"
const EXPECTED_SHOTS := 9
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const _UT := preload("res://scripts/ui/UiTransition.gd")

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
	print("QA_DRYDOCK_BEGIN")

	_expect(str(_UT.drydock_title("泉州", "修船")) == "泉州・修船", "修船题签")
	_expect(str(_UT.drydock_title("泉州", "购入")) == "泉州・购入", "购入题签")
	_expect(str(_UT.drydock_title("泉州", "换坞")) == "泉州・换坞", "换坞题签")
	_expect(str(_UT.drydock_title("泉州", "升帆")) == "泉州・升帆", "升帆题签")
	_expect(str(_UT.drydock_seal("修船")) == "修", "朱印修")
	_expect(str(_UT.drydock_seal("购入")) == "购", "朱印购")
	_expect(str(_UT.drydock_seal("换坞")) == "坞", "朱印坞")
	_expect(str(_UT.drydock_seal("升帆")) == "帆", "朱印帆")
	_expect(str(_UT.drydock_seal("升甲")) == "甲", "朱印甲")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var fleet: Node = root.get_node("/root/Fleet")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	Clock.frame_pressure(self)
	root.add_child(_main)
	await _settle(10)

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	gs.money = 8000
	_main.load_scene("quanzhou_shipyard")
	await _settle(10)
	_expect(str(_main.scene_title.text).contains("船屋"), "船屋匾「%s」" % _main.scene_title.text)
	_expect(str(_main.body_text.text).contains("坞上只搁一艘"), "坞位正文")
	await _shot("01_shipyard_berth")

	# 伤船体 → 修船 chip 出现；直接调修船题签截墨幕
	if fleet.ships.size() > 0:
		fleet.ships[0]["durability"] = maxf(1.0, float(fleet.ships[0].get("max_durability", 100)) * 0.4)
	_main.load_scene("quanzhou_shipyard")
	await _settle(8)
	await _shot("02_shipyard_damaged")

	var node: CanvasLayer = _UT.drydock_open(_main, "泉州", "修船", str(cal.call("get_date_string")), Callable())
	await _hold_shot(node, "03_transition_repair")

	# 购入客舟（若本章有）
	var added := false
	if fleet.has_method("add_ship"):
		added = bool(fleet.call("add_ship", "keel_boat"))
		if not added:
			added = bool(fleet.call("add_ship", "fu_ship_medium"))
	_main.load_scene("quanzhou_shipyard")
	await _settle(8)
	await _shot("04_shipyard_two_hulls" if fleet.ships.size() >= 2 else "04_shipyard_after_buy")

	node = _UT.drydock_open(_main, "泉州", "购入", str(cal.call("get_date_string")), Callable())
	await _hold_shot(node, "05_transition_buy")

	if fleet.ships.size() >= 2:
		gs.berth_index = 1
		_main.load_scene("quanzhou_shipyard")
		await _settle(8)
		await _shot("06_berth_switched")
		node = _UT.drydock_open(_main, "泉州", "换坞", str(cal.call("get_date_string")), Callable())
		await _hold_shot(node, "07_transition_swap")
	else:
		await _shot("06_berth_single")
		await _shot("07_transition_swap_skip")

	node = _UT.drydock_open(_main, "泉州", "升帆", str(cal.call("get_date_string")), Callable())
	await _hold_shot(node, "08_transition_sail")

	_main.load_scene("quanzhou_shipyard")
	await _settle(8)
	await _shot("09_shipyard_back")

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("QA_DRYDOCK_CHECK ok ", what)
	else:
		_fails.append(what)
		print("QA_DRYDOCK_CHECK fail ", what)


func _hold_shot(node: CanvasLayer, stem: String) -> void:
	if node == null:
		print("QA_DRYDOCK_SKIP_TRANSITION %s (headless)" % stem)
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
