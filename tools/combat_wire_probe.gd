extends SceneTree
## Lane N：接舷/海战真实钩子探针 + wire_*.png
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/combat_wire_probe.gd
## headless：只验文案与接线符号。

const VIEW := Vector2i(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/combat"
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const CombatShoreHook := preload("res://scripts/combat/CombatShoreHook.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")

var _fails: Array = []
var _saved: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_check_wiring()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	if Kit.is_headless():
		_report()
		return

	var gm := root.get_node("GameManager")
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 2}],
		"source": {"scene": "combat_wire"}
	}
	var fleet: Node = root.get_node_or_null("Fleet")
	_expect(fleet != null, "Fleet autoload")
	if fleet != null:
		fleet.set("ships", [{"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 200, "max_durability": 200}])
		fleet.set("morale", 70)

	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 36:
		await process_frame
	await _shot("wire_01_naval")

	if wm.has_method("_nearest_enemy") and wm.has_method("_board_enemy"):
		var ne: Array = wm._nearest_enemy()
		_expect(ne.size() == 2, "应有敌船可接舷")
		if ne.size() == 2:
			var enemy_node: Node2D = ne[0]
			var ship: Node2D = wm.get("ship")
			if ship != null and enemy_node != null:
				enemy_node.global_position = ship.global_position + Vector2(80, 0)
			wm._board_enemy(enemy_node)
			for _i in 18:
				await process_frame
			await _shot("wire_02_board_begin")
			for _i in 50:
				await process_frame
			await _shot("wire_03_board_resolve")

	# 岸上薄钩子预览（不依赖 WorldMap）
	var host := Node.new()
	root.add_child(host)
	_expect(CombatShoreHook.preview_boarding(host, true), "岸上接舷预览应可触发")
	for _i in 20:
		await process_frame
	await _shot("wire_04_shore_hook")

	_report()


func _check_wiring() -> void:
	var wm := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_expect(wm.find("_await_boarding_fx") >= 0, "WorldMap 应等待接舷题签")
	_expect(wm.find('{"boarded": true}') >= 0 or wm.find('"boarded": true') >= 0, "WorldMap 应标记 boarded")
	_expect(wm.find("_CombatFx.board_begin_subtitle") >= 0, "WorldMap 开场副题走 CombatFx")
	var sc := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_expect(sc.find("_CombatFx") >= 0, "SeaChart 应接入 CombatFx")
	_expect(sc.find("sea_win_note") >= 0, "SeaChart 应用 sea_win_note")
	var fx := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	_expect(fx.find("sea_flee_ok_note") >= 0, "CombatFx 应有海图脱战注记")
	_expect(CombatFx.board_win_note("海鹘").find("并入本队") >= 0, "夺船注记")
	_expect(CombatFx.sea_win_note(100, 10, "").find("海盗已退") >= 0, "战果胜注记")
	_expect(CombatFx.board_win_note("海鹘").find("！") < 0, "无叹号")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗", "premium", "pipeline"]:
		_expect(fx.find(bad) < 0, "CombatFx 无营销词：" + bad)
	var main := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_expect(main.find("CombatShoreHook") >= 0 or main.find("scripts/combat/CombatShoreHook") >= 0,
		"Main 应薄接入 CombatShoreHook（F9）")


func _shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	_saved.append(path)
	print("SHOT ", path)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  OK ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)


func _report() -> void:
	print("SAVED ", _saved.size(), " shots")
	for p in _saved:
		print("  ", p)
	if _fails.is_empty():
		print("COMBAT_WIRE_PROBE_PASS")
		quit(0)
	else:
		print("COMBAT_WIRE_PROBE_FAIL ", _fails)
		quit(1)
