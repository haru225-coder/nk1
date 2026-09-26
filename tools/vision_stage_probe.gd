## 展示台截屏探针。用法：
##   DISPLAY=:2 godot --path . -s res://tools/vision_stage_probe.gd
## 帧写入 /workspace/nk1-qa-shots/vision/（不擦 polish/）。
extends SceneTree

const OUT_DIR := "/workspace/nk1-qa-shots/vision"
const STAGE := "res://scenes/vision/VisionStage.tscn"


func _init() -> void:
	call_deferred("_run")


var _saved: Array = []
var _fails: Array = []


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if not ResourceLoader.exists(STAGE):
		push_error("VisionStage missing: %s" % STAGE)
		quit(1)
		return
	var packed := load(STAGE) as PackedScene
	var stage: Control = packed.instantiate()
	# GDScript 闭包对 bool 是拷贝赋值；用数组作可变旗标。
	var flag: Array = [false]
	if stage.has_signal("stage_ready"):
		stage.stage_ready.connect(func(): flag[0] = true)
	root.add_child(stage)
	var frames := 0
	while frames < 90 and not flag[0]:
		await process_frame
		frames += 1
	for _i in 50:
		await process_frame
	_shot("01_vision_stage_open.png")
	for _i in 30:
		await process_frame
	_shot("02_vision_stage_hold.png")
	# 截图探针：空视口/零截图必须失败（与 headless 契约探针区分）。
	if _saved.size() < 2:
		_fails.append("期望 2 张截图，实得 %d（headless 空视口？请用 DISPLAY 跑）" % _saved.size())
	if _fails.is_empty():
		print("vision_stage_probe OK frames=%d ready=%s shots=%d -> %s" % [frames, flag[0], _saved.size(), OUT_DIR])
		quit(0)
	else:
		for f in _fails:
			print("  ✗ ", f)
		print("vision_stage_probe FAIL %d" % _fails.size())
		quit(1)


func _shot(name: String) -> void:
	var tex = root.get_texture()
	if tex == null:
		_fails.append("no viewport texture for %s" % name)
		push_error("no viewport texture for %s" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		_fails.append("no viewport image for %s" % name)
		push_error("no viewport image for %s" % name)
		return
	var path := "%s/%s" % [OUT_DIR, name]
	var err := img.save_png(path)
	print("shot %s err=%d" % [path, err])
	if err != OK:
		_fails.append("save failed %s (%d)" % [path, err])
	else:
		_saved.append(path)
