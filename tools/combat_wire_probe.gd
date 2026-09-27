extends SceneTree
## Lane N：接舷/海战真实钩子探针 + wire_*.png
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/combat_wire_probe.gd            # 截图门禁（默认严格，须出 4 张）
##      godot --headless --path /workspace/nk1 -s res://tools/combat_wire_probe.gd -- --contract   # 只验文案与接线符号
## headless 下不加 --contract 必红（shot_gate.gd）。

const VIEW := Vector2i(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/combat"
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const CombatShoreHook := preload("res://scripts/combat/CombatShoreHook.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const TAG := "COMBAT_WIRE_PROBE"
const EXPECTED_SHOTS := 4

var _fails: Array = []
var _saved: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	var no_render := ShotGate.no_render_reason()
	if not ShotGate.contract_mode() and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	_check_wiring()

	if ShotGate.contract_mode():
		_report()
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

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
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  OK ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)


func _report() -> void:
	if ShotGate.contract_mode():
		quit(ShotGate.finish_contract(TAG, _fails))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
