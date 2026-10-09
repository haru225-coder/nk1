extends SceneTree
## lane-w53-p4-melee 白刃三决断「压上 / 收势」拍板拍 1280×720 截图（DISPLAY=:2 + glock）。
## 布景照 combat_wire_probe：真 WorldMap 海战（泉州外海，福船 80 人对海鹘 ×2），冻敌炮、
## 挪最近敌船贴舷、直接 _board_enemy → WorldMap 分段白刃挂起在首个决断段、决策层亮拍，
## 一拍真按键 Enter（收势）把场推进一格，截「层亮着」那一帧存 NK1_SHOT_DIR/wave53-p4/。
## 截图同步名 qa_w53_p4_melee_decision_panel.png；另留一条「真按键 InputEventKey Enter（收势）管路闯过」的账证：
## 收势一拍后决策层 waiting 关、set_battle_auto(true) 只活本场不回写 CombatSwitches（不另截图）。
## 用法：DISPLAY=:2 NK1_SHOT_DIR=<qa-shots 根> godot --path . --resolution 1280x720 \
##   -s res://tools/qa_w53_p4_melee_decision_shot.gd -- --shot-dir "<qa-shots 根>/wave53-p4"

const VIEW := Vector2i(1280, 720)
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const TAG := "QA_W53_P4_MELEE_DECISION_SHOT"

var _fails: Array = []
var _dir := ""


func _init() -> void:
	_dir = OS.get_environment("NK1_SHOT_DIR")
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_dir = args[i + 1]
	if _dir == "":
		_dir = "/tmp/nk1-qa-shots/wave53-p4"
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	CombatStage.watch_captures()
	root.size = VIEW
	var no_render := ShotGate.no_render_reason()
	if no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, 1))
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	ShotGate.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（同 shot_gate 一个口径；gates_md 门钉）

	# 布景照 combat_wire：真 WorldMap 海战、敌炮冻住、接舷演出照常
	var gm := root.get_node("GameManager")
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 2}],
		"source": {"scene": "qa_w53_p4_melee_decision_shot"}
	}
	var fleet: Node = root.get_node_or_null("Fleet")
	if fleet != null:
		fleet.set("ships", [{"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 200, "max_durability": 200}])
		fleet.set("morale", 70)
	var wm: Node = ShotGate.start_tree_probe("res://scenes/WorldMap.tscn", _fails, "P4Melee WorldMap")
	if wm == null:
		_report()
		return
	root.add_child(wm)
	for _i in 6:
		await process_frame
	if not ShotGate.check_fields(wm, {"combat_mode": "WorldMap 布景断", "boarding": "WorldMap 布景断"}, _fails, "P4Melee WorldMap"):
		_finish(wm)
		return
	_check(wm.has_method("_decision_offer"), "WorldMap 有 _decision_offer（本 lane 接线进了档）")
	var wm_ref: WeakRef = weakref(wm)
	_check(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮已冻住（2 艘）")
	_check(Switches.on("melee_decision"), "开关 melee_decision 开（默认）")
	_check(Switches.on("pursue_window"), "开关 pursue_window 开（默认）")

	# 入战墨边收场后才是真海战场面
	if not await CombatStage.wait_until(self, func() -> bool: return CombatStage.letterbox_under(self, wm_ref.get_ref()) == null):
		_check(false, CombatStage.why_not("入战墨边没收场", "finished 未发"))
		_finish(wm)
		return
	var wmv: Node = wm_ref.get_ref()
	if wmv == null:
		_check(false, "布景中途没了")
		_finish(wmv)
		return
	var ne: Array = wmv._nearest_enemy()
	_check(ne.size() == 2, "应有敌船可接舷")
	if ne.size() != 2:
		_finish(wmv)
		return
	var enemy_node: Node2D = ne[0]
	var ship: Node2D = wmv.get("ship")
	if ship != null and enemy_node != null:
		enemy_node.global_position = ship.global_position + Vector2(80, 0)
	wmv._board_enemy(enemy_node)

	# 等决策层真亮起（分段白刃跑到首个决断段挂起）：等 group 里出现一层 waiting
	var layer_found := false
	for i in 240:
		await process_frame
		var w: Node = wm_ref.get_ref()
		if w == null:
			break
		for n in w.get_tree().get_nodes_in_group("nk1_melee_decision"):
			if bool(n.call("waiting")):
				layer_found = true
				break
		if layer_found:
			break
	_check(layer_found, "决策层亮拍（分段白刃跑到首个决断段挂起）")
	if not layer_found:
		_finish(wm_ref.get_ref())
		return

	# 截这一帧（层亮着、题签「白刃·舷边 / 舷腰 / 桅下」、两钮可点）
	for i in 3:
		await process_frame
	var img: Image = root.get_texture().get_image()
	var png := "%s/qa_w53_p4_melee_decision_panel.png" % _dir
	var err := img.save_png(png)
	_check(err == OK, "截图落盘 %s（rc=%d）" % [png, err])

	# 账证：玩家真按键（推入 InputEventKey Enter = 收势）一拍，决策层 waiting 收掉；M 切自动只活本场
	var shot_layer: Node = null
	for n in root.get_tree().get_nodes_in_group("nk1_melee_decision"):
		shot_layer = n
	_check(shot_layer != null and bool(shot_layer.call("waiting")), "亮拍层 waiting 中（收势前）")
	if shot_layer != null:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.pressed = true
		Input.parse_input_event(ev)
		for i in 3:
			await process_frame
		_check(not bool(shot_layer.call("waiting")), "真按键 Enter（收势）一拍后 waiting 收掉（抉择拍走完）")
		# M 切自动后本场不再亮拍
		shot_layer.call("set_battle_auto", true)
		_check(bool(shot_layer.get("battle_auto")), "切本场自动（M 轴）：只活本场、不动开关")
	_check(Switches.on("melee_decision"), "拍板走过后开关照常在（battle_auto 不回写 CombatSwitches）")

	_finish(wm_ref.get_ref())


func _finish(wm) -> void:
	CombatStage.teardown(self, wm, root.get_node_or_null("GameManager"))
	_report()


func _report() -> void:
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)
