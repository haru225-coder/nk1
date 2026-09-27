extends SceneTree
## Lane AD：CombatLetterbox / VisionStage 题签文案论文纪实巡检。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/letterbox/（裱框 + 入战墨边题签 + 出战题签）。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_letterbox_copy_probe.gd
## 默认严格：须出 4 张；headless / 空视口 / 一色空图 / 张数不足一律非零退出（shot_gate.gd）。
## 契约模式（显式）：godot --headless --path /workspace/nk1 -s res://tools/qa_letterbox_copy_probe.gd -- --contract
##   只验静态题签契约与禁词，不截图。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("letterbox")
const STAGE := "res://scenes/vision/VisionStage.tscn"
const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const TAG := "QA_LETTERBOX_COPY"
const EXPECTED_SHOTS := 4
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")

## 玩家可见禁词（营销腔 + 残留现代 UI）
const BAD := ["惊艳", "沉浸", "打造", "视觉盛宴", "离开展示", "立绘裱框"]

var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_LETTERBOX_COPY_BEGIN")
	_check_copy_contracts()
	if _contract:
		if Kit.is_headless():
			_expect(Letterbox.enter(root, Letterbox.sea_title("刺桐外海", "遇敌"), "咸淳三年六月十二　海鹘二艘") == null,
				"headless 下 Letterbox.enter 应返回 null")
		_report()
		return

	# 1) VisionStage 裱框题签
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
	for _i in 40:
		await process_frame
	await _shot("01_vision_slip")
	# 核对屏上 hint / 旁注
	_expect_label_has(stage, "Hint", "合上纪事")
	_expect_no_label(stage, "离开展示")
	_expect_no_label(stage, "立绘裱框")
	stage.queue_free()
	for _i in 8:
		await process_frame

	# 2) 入战墨边题签
	var gm := root.get_node("GameManager")
	var enemy := [{"type": "sea_falcon", "count": 2}]
	gm.pending_battle = {
		"battle": true, "power": 300.0, "player_power": 400.0,
		"enemy": enemy, "sea_name": "刺桐外海",
		"source": {"scene": "letterbox_probe"},
	}
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# 布景不自己结算（lane gd6 立、gd10 改冻开炮）：WorldMap 是真海战，照常开炮结算。
	# 探针不开船，约 3.5 s 首轮齐射、8–10 s 旗舰被击沉 → Ship._sink_ship → WorldMap._battle_exit("lose")
	# → queue_free()；下面再调 wm.queue_free() 就报「previously freed instance」，_run 协程中断、
	# quit() 没人调，DISPLAY 下挂到 timeout。add_child 当帧只冻敌炮，理由见 combat_probe_stage.gd。
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮已冻住（2 艘）")
	for _i in 30:
		await process_frame
	var sub := "咸淳三年六月十二　%s" % Letterbox.enemy_note(enemy)
	var lb := Letterbox.enter(root, Letterbox.sea_title("刺桐外海", "遇敌"), sub)
	_expect(lb != null, "有窗口时入战墨边未上场")
	# 裸 await caption_shown 在墨边被顶掉 / 随布景释放时永不返回（lane gd10）：一律带帧数上界，没等到就判红收尾
	if lb != null and not await CombatStage.wait_signal(self, lb, &"caption_shown"):
		_bail("入战题签没擦出（caption_shown 未发：墨边被顶掉或随布景释放）", wm, gm)
		return
	if lb != null:
		await _shot("02_enter_caption")
		_expect(str(lb.get("title")) == "刺桐外海・遇敌", "入战题名「%s」" % lb.get("title"))
		_expect("海鹘二艘" in str(lb.get("subtitle")), "入战副题含中文船数")
		var enter_done := [false]
		lb.finished.connect(func() -> void: enter_done[0] = true)
		if not await CombatStage.wait_until(self, func() -> bool: return enter_done[0] or not is_instance_valid(lb)) \
				or not enter_done[0]:
			_bail("入战墨边没演完（finished 未发）", wm, gm)
			return
	for _i in 4:
		await process_frame

	# 3) 出战题签（夺船）
	var ex := Letterbox.exit(root, Letterbox.outcome_title("board", "刺桐外海"),
		"咸淳三年六月十二　夺得海鹘一艘")
	_expect(ex != null, "出战墨边未上场")
	if ex != null and not await CombatStage.wait_signal(self, ex, &"caption_shown"):
		_bail("出战题签没擦出（caption_shown 未发：墨边被顶掉或随布景释放）", wm, gm)
		return
	if ex != null:
		await _shot("03_exit_caption")
		_expect(str(ex.get("title")) == "刺桐外海・夺船", "出战题名「%s」" % ex.get("title"))
		var exit_done := [false]
		ex.finished.connect(func() -> void: exit_done[0] = true)
		if not await CombatStage.wait_until(self, func() -> bool: return exit_done[0] or not is_instance_valid(ex)) \
				or not exit_done[0]:
			_bail("出战墨边没演完（finished 未发）", wm, gm)
			return
	# 墨边退场后、海战场面拆掉前截：旧写法先 queue_free 再截，得的是一色空视口（lane sg2）
	await _shot("04_after_exit")
	# 冻住后布景不该自己结算；万一又被释放（去掉冻结 / WorldMap 改了结算时序），报红收尾，不挂死
	var why := CombatStage.standing_fail(wm)
	_expect(why == "", why if why != "" else "布景海战在探针演示中未自行结算")
	if is_instance_valid(wm):
		wm.queue_free()
	gm.pending_battle = {}
	_report()


func _check_copy_contracts() -> void:
	var vs := FileAccess.get_file_as_string("res://scripts/ui/VisionStage.gd")
	var lb := FileAccess.get_file_as_string("res://scripts/ui/CombatLetterbox.gd")
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	for bad in BAD:
		_expect(bad not in vs, "VisionStage 无「%s」" % bad)
		_expect(bad not in lb, "CombatLetterbox 无「%s」" % bad)
	_expect('HINT_ESC := "B　合上纪事"' in vs, "Hint 为「B　合上纪事」")
	_expect('NOTE_PORTRAIT := "绢本立像　名册可核"' in vs, "旁注为「绢本立像　名册可核」")
	_expect('SLIP_TITLE := "市舶纪事"' in vs, "题签主名「市舶纪事」")
	_expect("市舶纪事" in main_src and "_open_vision_stage" in main_src, "Main 岸带「市舶纪事」")
	_expect(Letterbox.sea_title("刺桐外海", "遇敌") == "刺桐外海・遇敌", "sea_title 纪实格式")
	_expect(Letterbox.outcome_title("win", "刺桐外海") == "刺桐外海・战罢", "outcome win")
	_expect(Letterbox.outcome_title("board", "刺桐外海") == "刺桐外海・夺船", "outcome board")
	_expect(Letterbox.outcome_title("flee", "刺桐外海") == "刺桐外海・脱战", "outcome flee")
	_expect(Letterbox.outcome_title("lose", "刺桐外海") == "刺桐外海・败退", "outcome lose")
	_expect(Letterbox.enemy_note([{"type": "sea_falcon", "count": 2}]) == "海鹘二艘", "enemy_note 中文船数")


func _expect_label_has(root_n: Node, name: String, needle: String) -> void:
	var n := root_n.find_child(name, true, false)
	if n == null or not (n is Label):
		_fails.append("缺 Label「%s」" % name)
		print("  ✗ 缺 Label「%s」" % name)
		return
	var txt := (n as Label).text
	_expect(needle in txt, "Label「%s」含「%s」（得「%s」）" % [name, needle, txt])


func _expect_no_label(root_n: Node, needle: String) -> void:
	for l in root_n.find_children("*", "Label", true, false):
		if needle in (l as Label).text:
			_fails.append("屏上仍见「%s」" % needle)
			print("  ✗ 屏上仍见「%s」" % needle)
			return
	print("  ✓ 屏上无「%s」" % needle)


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


## 等不到信号时判红收尾：拆掉还在的布景与墨边，照常出报告（不挂死）
func _bail(msg: String, wm: Node, gm: Node) -> void:
	_expect(false, msg)
	for n in root.get_tree().get_nodes_in_group(Letterbox.GROUP):
		n.call("_abort")
	if is_instance_valid(wm):
		wm.queue_free()
	gm.pending_battle = {}
	_report()


func _report() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
