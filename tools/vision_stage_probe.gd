## 展示台截屏探针。用法：
##   DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd            # 截图门禁（默认严格，须出 2 张）
##   godot --headless --path . -s res://tools/vision_stage_probe.gd -- --contract   # 只验契约（场景可载、stage_ready 发出）
## 帧写入 /workspace/nk1-qa-shots/vision/（不擦 polish/）。headless 下不加 --contract 必红。
extends SceneTree

const OUT_DIR := "/workspace/nk1-qa-shots/vision"
const STAGE := "res://scenes/vision/VisionStage.tscn"
const TAG := "VISION_STAGE_PROBE"
const EXPECTED_SHOTS := 2
const ShotGate := preload("res://tools/shot_gate.gd")


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
	# GDScript 闭包对 bool 是拷贝赋值；用数组作可变旗标。
	var flag: Array = [false]
	if stage.has_signal("stage_ready"):
		stage.stage_ready.connect(func(): flag[0] = true)
	else:
		_fails.append("VisionStage 缺 stage_ready 信号")
	root.add_child(stage)
	var frames := 0
	while frames < 90 and not flag[0]:
		await process_frame
		frames += 1
	if not flag[0]:
		_fails.append("90 帧内未收到 stage_ready")
	if contract:
		print("  contract frames=%d ready=%s" % [frames, flag[0]])
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
	print("  frames=%d ready=%s" % [frames, flag[0]])
	quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
