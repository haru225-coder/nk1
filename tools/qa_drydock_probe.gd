extends SceneTree
## 船屋坞位工席巡检：截 01..N 到 /workspace/nk1-qa-shots/drydock/。
## 摆场：泉州船屋坞位 → 伤船体修船题签 → 购入客舟 → 换坞题签 → 升帆题签。
## -s 工具脚本下 play_transition 当帧直通，题签帧直接调 UiTransition.drydock_open。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_drydock_probe.gd

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/drydock"
const _UT := preload("res://scripts/ui/UiTransition.gd")

var _main: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
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

	print("QA_DRYDOCK_SHOTS_SAVED %d" % _saved.size())
	for p in _saved:
		print("  ", p)
	if _fails.is_empty():
		print("QA_DRYDOCK_OK")
	else:
		print("QA_DRYDOCK_FAIL")
		for f in _fails:
			print("  fail ", f)
	quit(0 if _fails.is_empty() else 1)


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
	await _settle(36)
	await _shot(stem)
	if is_instance_valid(node):
		node.call("_abort")
	await _settle(4)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(stem: String) -> void:
	await _settle(2)
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		_fails.append("空帧 %s" % stem)
		return
	var path := "%s/%s.png" % [OUT_DIR, stem]
	var err := img.save_png(path)
	if err != OK:
		_fails.append("写失败 %s (%s)" % [stem, str(err)])
		return
	_saved.append(path)
	print("QA_DRYDOCK_SHOT ", path)
