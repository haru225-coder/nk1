extends SceneTree
## Lane C 接舷/海战 VFX 探针：开战 → 入战墨边（若有）→ 接舷题签 → 截屏。每张按演出相位截（lane gd11），不数帧。
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/combat_vfx_probe.gd            # 截图门禁（默认严格，须出 4 张）
##      godot --headless --path /workspace/nk1 -s res://tools/combat_vfx_probe.gd -- --contract   # 只验文案契约，不截图
##      NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/combat_vfx_probe.gd   # 压帧自检（lane gd11）
## 截图：${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/combat/。headless 下不加 --contract 必红（shot_gate.gd）。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("combat")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const TAG := "COMBAT_VFX_PROBE"
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
	_check_copy()

	_expect(CombatFx.board_win_note("海鹘").find("并入本队") >= 0, "夺船注记")
	_expect(CombatFx.board_lose_note(3).find("减员") >= 0, "脱钩注记")
	_expect(CombatFx.board_win_note("海鹘").find("！") < 0, "夺船注记无叹号")

	if ShotGate.contract_mode():
		if Kit.is_headless():
			_expect(BoardingStage.begin(root, null, null) == null, "headless 下接舷层应返回 null")
		_report()
		return

	CombatStage.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（lane gd11）；未设不挂
	var gm := root.get_node("GameManager")
	var enemy := [{"type": "sea_falcon", "count": 2}]
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": enemy, "source": {"scene": "combat_probe"}
	}
	# 水手充足，便于接舷演示（经 /root/Fleet，避免 -s 主脚本对 autoload 标识符的解析差异）
	var fleet: Node = root.get_node_or_null("Fleet")
	_expect(fleet != null, "Fleet autoload 应在 root")
	if fleet != null:
		fleet.set("ships", [{"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": 200, "max_durability": 200}])
		fleet.set("morale", 70)

	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# 布景不自己结算（lane gd10）：只冻敌船开炮，接舷演出照常跑；理由见 combat_probe_stage.gd 头注释
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮已冻住（2 艘）")
	# 按演出相位截图，不数帧（lane gd11）：原 40 / 20 / 45 帧只在某一帧率下对得上，快机截到墨边、慢帧截到空海面
	# 01：WorldMap 自己那副入战墨边（约 3.2 s，挂在 wm 下）收场后才是海战 HUD
	if not await _shot_when("01_naval_hud",
			func() -> bool: return CombatStage.letterbox_under(self, wm) == null,
			func() -> bool: return CombatStage.standing_fail(wm) != ""):
		_finish(wm)
		return

	# 强制接舷最近敌船
	if is_instance_valid(wm) and wm.has_method("_nearest_enemy") and wm.has_method("_board_enemy"):
		var ne: Array = wm._nearest_enemy()
		_expect(ne.size() == 2, "应有存活敌船可接舷")
		if ne.size() == 2:
			# 拉近到接舷距离内
			var enemy_node: Node2D = ne[0]
			var ship: Node2D = wm.get("ship")
			if ship != null and enemy_node != null:
				enemy_node.global_position = ship.global_position + Vector2(80, 0)
			wm._board_enemy(enemy_node)
			# 02：「接舷」题签显满（淡入 0.22 s）、白刃判定（0.42 s 后）还没出
			if not await _shot_when("02_boarding_stage",
					func() -> bool: return _board_is(wm, ["接舷"]),
					func() -> bool: return CombatStage.board_caption(self, wm)[0] != "接舷"):
				_finish(wm)
				return
			# 03：结算题签（夺船 / 脱钩）显满、还在停拍（0.55 s）没淡出
			if not await _shot_when("03_boarding_resolve",
					func() -> bool: return _board_is(wm, RESOLVE_TITLES),
					func() -> bool:
						var cap: Array = CombatStage.board_caption(self, wm)
						return cap[0] == "" or (cap[0] in RESOLVE_TITLES and cap[1] < 0.99)):
				_finish(wm)
				return

	# 04：接舷题签层演完收场（finished → queue_free）、布景仍在
	await _shot_when("04_post_board",
			func() -> bool: return CombatStage.boarding_stage(self, wm) == null,
			func() -> bool: return CombatStage.standing_fail(wm) != "")
	_finish(wm)


const RESOLVE_TITLES := ["夺船", "脱钩"]


## wm 下接舷题签此刻显满且题名在 titles 里
func _board_is(wm, titles: Array) -> bool:
	var cap: Array = CombatStage.board_caption(self, wm)
	return cap[0] in titles and cap[1] >= 0.99


func _shot_when(name: String, want: Callable, gone: Callable) -> bool:
	var path := "%s/%s.png" % [OUT_DIR, name]
	return await CombatStage.shot_when(self, path.get_file(), _fails,
			func() -> void: ShotGate.shot(root, path, _saved, _fails), want, gone)


func _finish(wm) -> void:
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "布景海战在探针演示中未自行结算")
	_report()


func _check_copy() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_expect(src.find("接舷白刃，夺下敌船") < 0, "旧夺船叹号文案应已替换")
	_expect(src.find("死了 %d 名水手") < 0, "旧失利文案应已替换")
	_expect(src.find("_CombatFx") >= 0, "WorldMap 应接入 CombatFx")
	_expect(src.find("_BoardingStage") >= 0, "WorldMap 应接入 BoardingStage")
	var fx := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗", "premium", "pipeline"]:
		_expect(fx.find(bad) < 0, "CombatFx 不得含营销词：" + bad)
	var bs := FileAccess.get_file_as_string("res://scripts/combat/BoardingStage.gd")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗"]:
		_expect(bs.find(bad) < 0, "BoardingStage 不得含营销词：" + bad)


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
