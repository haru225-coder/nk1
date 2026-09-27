extends SceneTree
## 进出海战墨边（scripts/ui/CombatLetterbox.gd）的有窗口探针：在真海战场面（WorldMap + pending_battle）上
## 演一次入战、一次带 on_black 的出战，按节拍截屏，并量排版与信号。
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/vision_letterbox_probe.gd
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/vision/（绝对路径，不进仓库）。默认严格：须出 7 张，headless / 空视口 / 张数不足必红。
## 压帧自检（lane gd11）：NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/vision_letterbox_probe.gd
## 契约模式（显式）：godot --headless --path . -s res://tools/vision_letterbox_probe.gd -- --contract
##   只验静态题签与 headless 下入口返回 null，收尾打 VISION_LETTERBOX_PROBE_CONTRACT_OK，不报张数。

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("vision")
const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const ShotGate := preload("res://tools/shot_gate.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const TAG := "VISION_LETTERBOX_PROBE"
const EXPECTED_SHOTS := 7

var _contract := false

var _fails: Array = []
var _saved: Array = []
var _covered_hits := 0
var _on_black_hits := 0
## covered 当帧的墨边高与布景海战是否已结算：covered 先于 on_black 发，须在信号回调里当场记
var _shut_at_cover := -1.0
var _resolved_at_cover := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	_check_titles()
	_check_await_src()
	if _contract:
		if Kit.is_headless():
			_expect(Letterbox.enter(root, "刺桐外海・接舷") == null, "headless 下静态入口应返回 null")
		_end(null)
		return
	var no_render := ShotGate.no_render_reason()
	if no_render != "":
		for f in _fails:
			print("  ✗ ", f)
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	CombatStage.frame_pressure(self)  # NK1_PROBE_SLOW_MS 压帧自检（lane gd11）；未设不挂
	var gm := root.get_node("GameManager")
	var enemy := [{"type": "sea_falcon", "count": 2}]
	gm.pending_battle = {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": enemy, "source": {"scene": "probe"}}
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# 布景不自己结算（lane pg 立、gd10 改冻开炮）：WorldMap 是真海战，照常开炮结算。约 8–10 s 旗舰被击沉 →
	# _battle_exit("lose") 自己起一副出战墨边，把探针这副在停拍时顶掉（_abort 提前补调 on_black，揭开是拆了场的灰底）
	# → 05 中线 v=0.302 偶发红，10 次红 5。不是渲染时序，不能靠重试/多等帧遮掉。add_child 当帧就冻（原先等 30 帧再
	# 整棵 DISABLED，慢帧下 30 帧可能已过 3.5 s 首轮齐射）；只冻敌炮、布景照常动，理由见 combat_probe_stage.gd。
	_expect(CombatStage.freeze_enemy_fire(wm) == 2, "布景敌船开炮没冻住（应 2 艘）")
	# 00 / 01 按演出相位截，不数帧（lane gd11）：原 30 帧在快机上 WorldMap 自己那副入战墨边（挂在 wm 下，约 3.2 s）
	# 还没收，「combat_plain」截的是「外海・遇敌」墨边；原 6 帧在慢帧（每帧 160 ms）下墨边早合满、题签已在擦出，不是「合拢中」
	if not await _shot_when("00_combat_plain",
			func() -> bool: return CombatStage.letterbox_under(self, wm) == null,
			func() -> bool: return CombatStage.standing_fail(wm) != ""):
		_bail("布景入战墨边没收场，截不到海战素面", wm)
		return

	# 入战
	var sub := "咸淳三年六月十二　%s" % Letterbox.enemy_note(enemy)
	_expect(sub.ends_with("二艘"), "敌船副题未按船种表写数：%s" % sub)
	var lb := Letterbox.enter(root, Letterbox.sea_title("刺桐外海", "接舷"), sub)
	_expect(lb != null, "有窗口时入战墨边未上场")
	if lb == null:
		_end(wm)
		return
	var enter_done := [false]
	lb.finished.connect(func() -> void: enter_done[0] = true)
	# 01：墨边合到三成以上、还没合满（合拢 0.46 s）
	if not await _shot_when("01_enter_closing",
			func() -> bool: return _bar_frac(lb) >= 0.3 and _bar_frac(lb) < 1.0,
			func() -> bool: return _bar_frac(lb) >= 1.0):
		_bail("入战墨边合拢中一帧也没画到", wm)
		return
	# 裸 await caption_shown 在墨边被顶掉 / 随布景释放时永不返回（lane gd10）：一律带上界（gd11 起按墙钟），没等到就判红收尾
	if not await CombatStage.wait_signal(self, lb, &"caption_shown"):
		_bail("入战题签没擦出（caption_shown 未发：墨边被顶掉或随布景释放）", wm)
		return
	await _shot("02_enter_caption")
	_check_layout(lb, "入战")
	if not await CombatStage.wait_until(self, func() -> bool: return enter_done[0] or not is_instance_valid(lb)) \
			or not enter_done[0]:
		_bail("入战墨边没演完（finished 未发）", wm)
		return
	for _i in 3:
		await process_frame
	_expect(not is_instance_valid(lb) or lb.is_queued_for_deletion(), "入战演完节点未自删")
	await _shot("03_enter_done")

	# 出战（带 on_black：全黑时把战场换成空场）
	var ex := Letterbox.exit(root, Letterbox.outcome_title("board", "刺桐外海"),
		"咸淳三年六月十二　夺得海鹘一艘", func() -> void:
			_on_black_hits += 1
			wm.queue_free())
	_expect(ex != null, "出战墨边未上场")
	if ex == null:
		_end(wm)
		return
	ex.covered.connect(func() -> void:
		_covered_hits += 1
		_shut_at_cover = (ex.get("_top") as Control).size.y
		_resolved_at_cover = is_instance_valid(wm) and bool(wm.get("resolved")))
	var exit_done := [false]
	ex.finished.connect(func() -> void: exit_done[0] = true)
	if not await CombatStage.wait_signal(self, ex, &"caption_shown"):
		_bail("出战题签没擦出（caption_shown 未发：墨边被顶掉或随布景释放）", wm)
		return
	await _shot("04_exit_caption")
	_check_layout(ex, "出战")
	# 已被顶掉时 covered 早发过了，裸 await 会挂死；按计数等、带上界
	if not await CombatStage.wait_until(self, func() -> bool: return _covered_hits > 0 or not is_instance_valid(ex)) \
			or _covered_hits == 0:
		_bail("出战墨边没合到全黑（covered 未发）", wm)
		return
	_expect(not _resolved_at_cover,
		"布景海战在墨边演示中自行结算，WorldMap 自己的出战墨边顶掉了探针这副（探针布景没冻住，不是墨边回归）")
	_expect(_shut_at_cover >= VIEW.y * 0.5,
		"出战 covered 时墨边未合到中线（上边高 %.1f < %d）：被新墨边顶掉提前补调了 on_black" % [_shut_at_cover, VIEW.y / 2])
	var img: Image = await _shot("05_exit_black", true)
	if img != null:
		var mid := img.get_pixel(VIEW.x / 2, VIEW.y / 2)
		_expect(mid.v < 0.08, "出战合拢时画面中线未全黑（v=%.3f）" % mid.v)
	if not await CombatStage.wait_until(self, func() -> bool: return exit_done[0] or not is_instance_valid(ex)) \
			or not exit_done[0]:
		_bail("出战墨边没演完（finished 未发）", wm)
		return
	await _shot("06_exit_done", true)  # on_black 已换成空场，本就一色
	_expect(_on_black_hits == 1 and _covered_hits == 1,
		"出战 on_black / covered 应各调一次（%d / %d）" % [_on_black_hits, _covered_hits])

	# 同时只留一副：新的顶掉旧的，旧的若带 on_black 须补调
	var hits := [0]
	Letterbox.exit(root, "外洋・脱战", "", func() -> void: hits[0] += 1)
	await process_frame
	Letterbox.enter(root, "外洋・遇敌")
	await process_frame
	_expect(hits[0] == 1, "被顶掉的出战未补调 on_black")
	_expect(root.get_tree().get_nodes_in_group(Letterbox.GROUP).size() == 1, "同时留了不止一副墨边")
	_end(wm)


func _check_titles() -> void:
	_expect(Letterbox.sea_title("刺桐外海", "接舷") == "刺桐外海・接舷", "sea_title 拼法不对")
	_expect(Letterbox.sea_title("", "接舷") == "接舷", "海名空时不应补地名")
	_expect(Letterbox.outcome_title("win", "耽罗海") == "耽罗海・战罢", "win 事由不对")
	_expect(Letterbox.outcome_title("flee") == "脱战", "flee 事由不对")
	_expect(Letterbox.outcome_title("lose", "外洋") == "外洋・败退", "lose 事由不对")
	for w in ["惊艳", "沉浸", "打造"]:
		var src := FileAccess.get_file_as_string("res://scripts/ui/CombatLetterbox.gd")
		_expect(not src.contains(w), "墨边脚本里出现了禁词「%s」" % w)


## 墨边协程只许挂在可取消的挂起点上（lane gd15）：代码行里的 await 只能等 _woken，或等本文件自己的协程函数。
## 直接 await tween.finished / process_frame / 计时器，被 kill、随父释放或退出时协程永不醒 → ObjectDB 泄漏。
func _check_await_src() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/CombatLetterbox.gd")
	var own := {}
	for m in RegEx.create_from_string("(?m)^func (_\\w+)\\(").search_all(src):
		own[m.get_string(1)] = true
	var parked := 0
	var ln := 0
	for line in src.split("\n"):
		ln += 1
		var code := line.get_slice("#", 0)
		var at := code.find("await ")
		while at >= 0:
			var expr := code.substr(at + 6).strip_edges()
			var callee := expr.get_slice("(", 0)
			if expr == "_woken":
				parked += 1
			elif not (expr.contains("(") and own.has(callee)):
				_fails.append("CombatLetterbox.gd:%d 直接 await「%s」：须走 _await_tween / _await_frame（kill 或随父释放后协程永不醒）" % [ln, expr])
			at = code.find("await ", at + 6)
	_expect(parked == 2, "CombatLetterbox 的挂起点应恰好 2 处 await _woken（_await_tween / _await_frame），实为 %d" % parked)


func _check_layout(lb: CanvasLayer, tag: String) -> void:
	var h: float = lb.call("bar_height")
	var r: Rect2 = lb.call("caption_rect")
	_expect(is_equal_approx(h, 90.0), "%s墨边高应为 90（%.1f）" % [tag, h])
	_expect(r.position.y >= VIEW.y - h - 1.0 and r.end.y <= VIEW.y + 1.0,
		"%s题签没落在下墨边里：%s" % [tag, r])
	_expect(r.position.x >= 0.0 and r.end.x <= VIEW.x, "%s题签冲出画布：%s" % [tag, r])
	print("  %s 墨边 %.0f  题签 %s" % [tag, h, r])


## 截满足 want 的那一帧（combat_probe_stage.shot_when）；等不到红因已记进 _fails
func _shot_when(name: String, want: Callable, gone: Callable) -> bool:
	var path := "%s/letterbox_%s.png" % [OUT_DIR, name]
	return await CombatStage.shot_when(self, path.get_file(), _fails,
			func() -> void: ShotGate.shot(root, path, _saved, _fails), want, gone)


## 墨边上边此刻合到几成（0 = 未合、1 = 合满）；墨边已释放按合满算
func _bar_frac(lb) -> float:
	if lb == null or not is_instance_valid(lb):
		return 1.0
	return (lb.get("_top") as Control).size.y / maxf(1.0, float(lb.call("bar_height")))


## allow_blank：05_exit_black 本该全黑、06_exit_done 是 on_black 换上的空场，都不按「一色空图」判红；
## 其余 5 张仍防空视口。
func _shot(name: String, allow_blank := false) -> Image:
	await RenderingServer.frame_post_draw
	return ShotGate.shot(root, "%s/letterbox_%s.png" % [OUT_DIR, name], _saved, _fails, allow_blank)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


## 等不到信号时判红收尾：与正常收尾同走 _end，另带 error=no_signal 进 --json（不挂死）
func _bail(msg: String, wm) -> void:
	_fails.append(msg)
	_end(wm, CombatStage.NO_SIGNAL)


## 唯一收尾：场上墨边 _abort（挂着的等待方都收到 finished）、放掉布景，再出报告（lane gd12）。
## wm 不写类型：已被 on_black 放掉的实例传进带类型形参会 SCRIPT ERROR。
func _end(wm, error := "") -> void:
	CombatStage.teardown(self, wm)
	# teardown 已把场上墨边全 _abort：挂着的协程当场醒来自退，一个都不许剩（剩了就是退出时的 ObjectDB 泄漏，lane gd15）
	_expect(Letterbox.waiters == 0, "墨边收尾后仍有 %d 个协程挂在等待上（没被唤醒，退出会报 ObjectDB 泄漏）" % Letterbox.waiters)
	if _contract:
		quit(ShotGate.finish_contract(TAG, _fails, error))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails, error))
