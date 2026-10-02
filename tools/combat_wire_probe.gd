extends SceneTree
## Lane N：接舷/海战真实钩子探针 + wire_*.png（每张按演出相位截，lane gd11，不数帧）
## Run: DISPLAY=:2 godot --path . -s res://tools/combat_wire_probe.gd            # 截图门禁（默认严格，须出 4 张）
##      godot --headless --path . -s res://tools/combat_wire_probe.gd -- --contract   # 只验文案与接线符号
##      NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path . -s res://tools/combat_wire_probe.gd   # 压帧自检（lane gd11）
## headless 下不加 --contract 必红（shot_gate.gd）。
## lane combat10：_check_wiring 另验剧情挂钩锚点（遇盗 → 开战 → 夺船 → 回写，字样表在 CombatDirector.STORY_ANCHORS）；
##   写实海战五块与这条挂钩的真跑冒烟在 tools/combat_realism_probe.gd（headless，见 docs/combat_realism_verify.md）。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("combat")
const CombatFx := preload("res://scripts/combat/CombatFx.gd")
const BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const SP := preload("res://tools/src_probe.gd")  # 按名认函数的源码探查（lane cs15：不按前缀认名）
const CombatShoreHook := preload("res://scripts/combat/CombatShoreHook.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const Director := preload("res://scripts/combat/CombatDirector.gd")  # 剧情挂钩锚点表（lane combat10）
const TAG := "COMBAT_WIRE_PROBE"
const EXPECTED_SHOTS := 4

var _fails: Array = []
var _saved: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	CombatStage.watch_captures()  # 收尾断言 lambda 没捕获到已释放的节点（lane gd17）
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
	ShotGate.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（lane gd11；gd18 收进 shot_gate）；未设不挂

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
	# 被测树自检（lane w24-b5 接 wave23-a9 共用面）：WorldMap 挂不出 / 挂空壳秒级判红；字段在过帧后点名
	wm = ShotGate.start_tree_probe("res://scenes/WorldMap.tscn", _fails, "CombatWire WorldMap")
	if wm == null:
		_report()
		return
	root.add_child(wm)
	for _i in 6:
		await process_frame
	if not ShotGate.check_fields(wm, {"combat_mode": "WorldMap.gd Parse Error / 海战布景断", "resolved": "WorldMap.gd Parse Error / 海战布景断"}, _fails, "CombatWire WorldMap"):
		_finish(wm)
		return
	# 下面等相位的 lambda 只捕获弱引用：布景万一自行结算释放后再调，直接捕获 wm 就报 Lambda capture freed（lane gd17）
	var wm_ref: WeakRef = weakref(wm)
	# 布景不自己结算（lane gd10）：只冻敌船开炮，接舷演出照常跑；理由见 combat_probe_stage.gd 头注释
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮已冻住（2 艘）")
	# 按演出相位截图，不数帧（lane gd11）：原 36 / 18 / 50 / 20 帧只在某一帧率下对得上，快机截到墨边、慢帧截到空海面
	# wire_01：WorldMap 自己那副入战墨边（约 3.2 s，挂在 wm 下）收场后才是海战场面
	if not await _shot_when("wire_01_naval",
			func() -> bool: return CombatStage.letterbox_under(self, wm_ref.get_ref()) == null,
			func() -> bool: return CombatStage.standing_fail(wm_ref.get_ref()) != ""):
		_finish(wm)
		return

	if is_instance_valid(wm) and wm.has_method("_nearest_enemy") and wm.has_method("_board_enemy"):
		var ne: Array = wm._nearest_enemy()
		_expect(ne.size() == 2, "应有敌船可接舷")
		if ne.size() == 2:
			var enemy_node: Node2D = ne[0]
			var ship: Node2D = wm.get("ship")
			if ship != null and enemy_node != null:
				enemy_node.global_position = ship.global_position + Vector2(80, 0)
			wm._board_enemy(enemy_node)
			# wire_02：「接舷」题签显满（淡入 0.22 s）、白刃判定（0.42 s 后）还没出
			if not await _shot_when("wire_02_board_begin",
					func() -> bool: return _board_is(wm_ref.get_ref(), ["接舷"]),
					func() -> bool: return CombatStage.board_caption(self, wm_ref.get_ref())[0] != "接舷"):
				_finish(wm)
				return
			# wire_03：结算题签（夺船 / 脱钩）显满、还在停拍（0.55 s）没淡出
			if not await _shot_when("wire_03_board_resolve",
					func() -> bool: return _board_is(wm_ref.get_ref(), RESOLVE_TITLES),
					func() -> bool:
						var cap: Array = CombatStage.board_caption(self, wm_ref.get_ref())
						return cap[0] == "" or (cap[0] in RESOLVE_TITLES and cap[1] < 0.99)):
				_finish(wm)
				return
			# 等海上这层接舷题签演完再起岸上预览：否则 BoardingStage.begin 按组顶掉它，顶在哪一拍随帧率变
			if not await CombatStage.wait_until(self, func() -> bool: return CombatStage.boarding_stage(self, wm_ref.get_ref()) == null):
				_expect(false, CombatStage.why_not("海上接舷题签没收场", "finished 未发"))
				_finish(wm)
				return

	# 岸上薄钩子预览（不依赖 WorldMap）：接舷 → 0.55 s → 夺船，截第二拍（两拍都演了才有它）
	var host := Node.new()
	root.add_child(host)
	_expect(CombatShoreHook.preview_boarding(host, true), "岸上接舷预览应可触发")
	await _shot_when("wire_04_shore_hook",
			func() -> bool: return _board_is(host, ["夺船"]),
			func() -> bool:
				var cap: Array = CombatStage.board_caption(self, host)
				return cap[0] == "" or (cap[0] == "夺船" and cap[1] < 0.99))
	_finish(wm)


const RESOLVE_TITLES := ["夺船", "脱钩"]


## parent 下接舷题签此刻显满且题名在 titles 里
func _board_is(parent, titles: Array) -> bool:
	var cap: Array = CombatStage.board_caption(self, parent)
	return cap[0] in titles and cap[1] >= 0.99


func _shot_when(name: String, want: Callable, gone: Callable) -> bool:
	var path := "%s/%s.png" % [OUT_DIR, name]
	return await CombatStage.shot_when(self, path.get_file(), _fails,
			func() -> void: ShotGate.shot(root, path, _saved, _fails), want, gone)


func _finish(wm) -> void:
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "布景海战在探针演示中未自行结算")
	_report()


func _check_wiring() -> void:
	var wm := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_expect(SP.has_tok(wm, "_await_boarding_fx", true), "WorldMap 应等待接舷题签")
	_expect(wm.find('{"boarded": true}') >= 0 or wm.find('"boarded": true') >= 0, "WorldMap 应标记 boarded")
	_expect(SP.calls(wm, "_CombatFx.board_begin_subtitle"), "WorldMap 开场副题走 CombatFx")
	var sc := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_expect(sc.find("_CombatFx") >= 0, "SeaChart 应接入 CombatFx")
	_expect(SP.has_tok(sc, "sea_win_note", true), "SeaChart 应用 sea_win_note")
	var fx := FileAccess.get_file_as_string("res://scripts/combat/CombatFx.gd")
	_expect(SP.has_func(fx, "sea_flee_ok_note"), "CombatFx 应有海图脱战注记")
	_expect(CombatFx.board_win_note("海鹘").find("并入本队") >= 0, "夺船注记")
	_expect(CombatFx.sea_win_note(100, 10, "").find("海盗已退") >= 0, "战果胜注记")
	_expect(CombatFx.board_win_note("海鹘").find("！") < 0, "无叹号")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "史诗", "premium", "pipeline"]:
		_expect(fx.find(bad) < 0, "CombatFx 无营销词：" + bad)
	# lane combat12：胜局按各船下场分账（先沉后遁照全赏，士气 verdict 只看在场的船）、限时两散出「两散」题签
	var chart_gd: GDScript = load("res://scripts/SeaChart.gd")
	var lb_gd: GDScript = load("res://scripts/ui/CombatLetterbox.gd")
	var mixed := {"morale_verdict": "enemy_fled", "enemy_fled": 1,
		"fates": [{"type": "pirate_boat", "fate": "sunk"}, {"type": "pirate_boat", "fate": "fled"}]}
	_expect(str(chart_gd.call("win_kind", {"morale_verdict": "enemy_fled", "enemy_fled": 1})) == "fled", "SeaChart 敌遁半赏（win_kind=fled）")
	_expect(str(chart_gd.call("win_kind", mixed)) == "", "SeaChart 先沉后遁照击沉全赏")
	_expect(str(chart_gd.call("win_kind", {"morale_verdict": "enemy_broken", "enemy_struck": 1, "enemy_fled": 1})) == "surrender",
		"SeaChart 降遁皆有走受降")
	_expect(str(lb_gd.call("outcome_key", "flee", {"flee_ok": true, "parted": true})) == "parted"
		and str(lb_gd.call("outcome_key", "disengaged", {})) == "parted", "题签两散 parted")
	_expect(SP.has_func(wm, "_battle_fates") and wm.find('"parted": true') >= 0, "WorldMap 收战带下场明细、限时两散")
	var main := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_expect(main.find("CombatShoreHook") >= 0 or main.find("scripts/combat/CombatShoreHook") >= 0,
		"Main 应薄接入 CombatShoreHook（F9）")
	# lane combat10：剧情挂钩锚点逐条验——剧情日后在「遇盗开打」「夺得敌船」上挂旗标 / 新闻就挂在这几支函数上，锚点动了先红
	var probs := Director.anchor_problems()
	for a in Director.STORY_ANCHORS:
		var mine := probs.filter(func(p): return str(p).begins_with(str(a["id"]) + "："))
		_expect(mine.is_empty(), "剧情锚点 %s：%s.%s（%s）%s" % [a["id"], str(a["file"]).get_file(), a["func"], a["what"],
			"" if mine.is_empty() else "——" + "; ".join(mine)])


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  OK ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)


func _report() -> void:
	var freed := CombatStage.captures_freed()
	_expect(freed == 0, "探针 lambda 没碰到已释放的捕获（Lambda capture … was freed %d 次，须 0；改捕获 weakref，见 combat_probe_stage 头注释「六」）" % freed)
	if ShotGate.contract_mode():
		quit(ShotGate.finish_contract(TAG, _fails))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
