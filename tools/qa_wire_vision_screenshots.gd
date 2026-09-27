extends SceneTree
## Lane L：VisionStage / CombatLetterbox 主流程薄接入巡检。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/wire/（至少 2 张：裱框、入战墨边）。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_wire_vision_screenshots.gd
## 默认严格：须出 2 张；headless / 空视口 / 一色空图 / 张数不足一律非零退出（shot_gate.gd）。
## 压帧自检（lane gd11）：NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path . -s res://tools/qa_wire_vision_screenshots.gd
## 契约模式（显式）：godot --headless --path . -s res://tools/qa_wire_vision_screenshots.gd -- --contract
##   只验接线符号与题签静态契约，不截图。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("wire")
const STAGE := "res://scenes/vision/VisionStage.tscn"
const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const TAG := "QA_WIRE_VISION"
const EXPECTED_SHOTS := 2
const ShotGate := preload("res://tools/shot_gate.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")

var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	CombatStage.watch_captures()  # 收尾断言 lambda 没捕获到已释放的节点（lane gd17）
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_WIRE_VISION_BEGIN")
	_check_wiring()
	if _contract:
		# headless：Letterbox 静态入口应返回 null；接线符号已验。
		if Kit.is_headless():
			_expect(Letterbox.enter(root, Letterbox.sea_title("泉州外海", "遇敌"), "咸淳三年　海鹘二艘") == null,
				"headless 下 Letterbox.enter 应返回 null")
		_report()
		return

	CombatStage.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（lane gd11）；未设不挂
	# 1) VisionStage 裱框（与岸上「市舶纪事」/ F8 叠层同场景）
	if not ResourceLoader.exists(STAGE):
		_fails.append("缺 VisionStage 场景")
		_report()
		return
	var packed := load(STAGE) as PackedScene
	var stage: Control = packed.instantiate()
	var ready_flag: Array = [false]
	if stage.has_signal("stage_ready"):
		stage.stage_ready.connect(func(): ready_flag[0] = true)
	root.add_child(stage)
	var frames := 0
	while frames < 90 and not ready_flag[0]:
		await process_frame
		frames += 1
	# 按帧不改（lane gd11）：VisionStage._run_intro 本身逐帧推进（题签擦出 20 帧），帧数就是它的时钟
	for _i in 40:
		await process_frame
	await _shot("wire_01_vision_frame")
	stage.queue_free()
	for _i in 8:
		await process_frame

	# 2) 真海战场面入战墨边（SeaChart→WorldMap 同路径：pending_battle + sea_name）
	var gm := root.get_node("GameManager")
	gm.pending_battle = {
		"battle": true,
		"power": 300.0,
		"player_power": 400.0,
		"enemy": [{"type": "sea_falcon", "count": 2}],
		"sea_name": "泉州外海",
		"source": {"scene": "wire_probe", "event": "pirate"},
	}
	var fleet: Node = root.get_node_or_null("Fleet")
	if fleet != null:
		fleet.set("ships", [{
			"type": "fuchuan", "name": "福船", "crew": 80,
			"sail_level": 1, "armor_level": 1, "cargo": {},
			"durability": 200, "max_durability": 200,
		}])
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# 布景不自己结算（lane gd10 helper）：只冻敌炮，理由见 combat_probe_stage.gd
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮已冻住（2 艘）")
	# 入战题签合拢期再截一帧：按演出信号截（lane gd11），不数帧。原 36+24 帧快机截在墨边合拢前、
	# 慢帧（每帧 160 ms）下 60 帧 ≈ 9.6 s，墨边（约 3.2 s）早收了，截的是空海面、照样 OK。
	# WorldMap._try_letterbox_enter 那副挂在 wm 下：题签擦出（caption_shown）后停拍 1.3 s 内截
	var lb := CombatStage.letterbox_under(self, wm)
	_expect(lb != null, "WorldMap 入战墨边应上场（挂在 wm 下）")
	if lb != null:
		var shown := [false]
		lb.caption_shown.connect(func() -> void: shown[0] = true, CONNECT_ONE_SHOT)
		var path := "%s/wire_02_letterbox_enter.png" % OUT_DIR
		# 条件只捕获弱引用：墨边在等待中演完自删 / 随布景释放后再调，直接捕获 lb 就报 Lambda capture freed（lane gd17）
		var lb_ref: WeakRef = weakref(lb)
		await CombatStage.shot_when(self, path.get_file(), _fails,
				func() -> void: ShotGate.shot(root, path, _saved, _fails),
				func() -> bool: return shown[0] and _live(lb_ref),
				func() -> bool: return not _live(lb_ref))
		if is_instance_valid(lb) and shown[0]:
			_expect(str(lb.get("title")) == "泉州外海・遇敌", "入战题名「%s」" % lb.get("title"))
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "布景海战在探针演示中未自行结算")
	if is_instance_valid(wm):
		wm.queue_free()
	gm.pending_battle = {}

	_report()


func _check_wiring() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_expect("KEY_F8" in main_src and "_open_vision_stage" in main_src, "Main F8 / _open_vision_stage")
	_expect("市舶纪事" in main_src and "_VISION_STAGE" in main_src, "Main 岸带「市舶纪事」")
	var sc := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_expect("_battle_sea_name" in sc and "sea_name" in sc, "SeaChart sea_name 写入 pending_battle")
	var wm := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_expect('pb.get("sea_name"' in wm or "sea_name" in wm, "WorldMap letterbox 读 sea_name")
	_expect("CombatLetterbox" in wm or "_LETTERBOX_PATH" in wm, "WorldMap 已接 CombatLetterbox")
	# 论文纪实：题签不含营销词
	var vs := FileAccess.get_file_as_string("res://scripts/ui/VisionStage.gd")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴"]:
		_expect(bad not in vs, "VisionStage 无「%s」" % bad)
	var title := Letterbox.sea_title("泉州外海", "遇敌")
	_expect(title == "泉州外海・遇敌", "sea_title 纪实格式（得 %s）" % title)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  ✓ ", label)
	else:
		print("  ✗ ", label)
		_fails.append(label)


func _shot(stem: String) -> void:
	await process_frame
	await process_frame
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)


## 弱引用的节点还在且没排队释放
func _live(ref: WeakRef) -> bool:
	var n: Node = ref.get_ref()
	return n != null and not n.is_queued_for_deletion()


func _report() -> void:
	var freed := CombatStage.captures_freed()
	_expect(freed == 0, "探针 lambda 没碰到已释放的捕获（Lambda capture … was freed %d 次，须 0；改捕获 weakref，见 combat_probe_stage 头注释「六」）" % freed)
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
