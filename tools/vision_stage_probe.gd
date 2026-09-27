## 展示台截屏探针。用法：
##   DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd            # 截图门禁（默认严格，须出 2 张）
##   godot --headless --path . -s res://tools/vision_stage_probe.gd -- --contract   # 只验契约（场景可载、stage_ready 发出）
## 帧写入 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/vision/（不擦 polish/）。headless 下不加 --contract 必红。
## 推进口径（lane gd14）：stage_ready 按墙钟上界等；开场（VisionStage._run_intro）本身按 process_frame 逐帧演
##   （题签擦出 20 + 飘字上浮 18 + 淡去 12 = 50 帧），所以 50 / 30 帧照旧按帧、与帧率无关；台上唯一按 delta 走的是
##   自动齐射（首轮 0.6 s、每 2.8 s），关掉（auto_volley=false，VisionStage 留给截屏探针定时刻用的开关），
##   否则同样 50 帧在快机上截不到炮焰、慢帧下截到第二轮——两张图随帧率变。
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd
extends SceneTree

var OUT_DIR := ShotGate.out_dir("vision")
const STAGE := "res://scenes/vision/VisionStage.tscn"
const TAG := "VISION_STAGE_PROBE"
const EXPECTED_SHOTS := 2
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")


func _init() -> void:
	call_deferred("_run")


var _saved: Array = []
var _fails: Array = []


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var contract := ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not ResourceLoader.exists(STAGE):
		_fails.append("VisionStage 场景缺失：%s" % STAGE)
		quit(ShotGate.finish_contract(TAG, _fails) if contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
		return
	var packed := load(STAGE) as PackedScene
	var stage: Control = packed.instantiate()
	stage.set("auto_volley", false)
	ShotGate.frame_pressure(self)
	# GDScript 闭包对 bool 是拷贝赋值；用数组作可变旗标。
	var flag: Array = [false]
	if stage.has_signal("stage_ready"):
		stage.stage_ready.connect(func(): flag[0] = true)
	else:
		_fails.append("VisionStage 缺 stage_ready 信号")
	root.add_child(stage)
	var t0 := Time.get_ticks_msec()
	if not await Clock.until(self, func() -> bool: return flag[0]):
		_fails.append("%d ms 内未收到 stage_ready" % Clock.WAIT_MS)
	var ready_ms := Time.get_ticks_msec() - t0
	if contract:
		print("  contract ready_ms=%d ready=%s" % [ready_ms, flag[0]])
		quit(ShotGate.finish_contract(TAG, _fails))
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for _i in 50:
		await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/01_vision_stage_open.png" % OUT_DIR, _saved, _fails)
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/02_vision_stage_hold.png" % OUT_DIR, _saved, _fails)
	_expect_no_volley(stage)
	print("  ready_ms=%d ready=%s" % [ready_ms, flag[0]])
	quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


## 两张图都该是开场演完的静帧：自动齐射已关，台上不该放过炮（放过就是有人又按 delta 起了演出）
func _expect_no_volley(stage: Node) -> void:
	var n := int(stage.get("volley_count")) if is_instance_valid(stage) else -1
	if n != 0:
		_fails.append("截图期间放了 %d 轮齐射（auto_volley 应关）" % n)
