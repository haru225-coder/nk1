extends SceneTree
## 标题页 / 序章题签巡检：截 title_*.png 到 /workspace/nk1-qa-shots/title/。
## 触发：开机进 cg_title；点「开卷」见「序章・卷首」；四方沙盘末页「翻页」见「序章・兴化海口」。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_title_probe.gd

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/title"
const _UT := preload("res://scripts/ui/UiTransition.gd")

var _main: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_TITLE_BEGIN")

	var open_t := str(_UT.prologue_open_title())
	var shore_t := str(_UT.prologue_shore_title())
	if open_t != "序章・卷首" or shore_t != "序章・兴化海口":
		_fails.append("题签文案漂移 open=%s shore=%s" % [open_t, shore_t])
	else:
		print("QA_TITLE_COPY_OK ", open_t, " / ", shore_t)

	# 关自动开场：写会话开关（Cinematics 静态变量），避免 84s 过场
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	if str(_main.get("current_scene_id")) != "cg_title":
		_main.load_scene("cg_title")
		await _settle(8)
	_finish_title_stage()
	await _settle(4)
	await _shot("01_title_start")

	_main.load_scene("cg_world_north")
	await _settle(6)
	_finish_title_stage()
	await _settle(4)
	await _shot("02_sand_north")

	var sub := _date_sub()
	var node: CanvasLayer = _UT.prologue_open(_main, sub, Callable())
	if node != null:
		await _settle(36)
		await _shot("03_transition_prologue_open")
		if is_instance_valid(node):
			node.call("_abort")
		await _settle(4)
	else:
		print("QA_TITLE_SKIP_TRANSITION_OPEN (headless/no live)")

	node = _UT.prologue_shore(_main, sub, Callable())
	if node != null:
		await _settle(36)
		await _shot("04_transition_prologue_shore")
		if is_instance_valid(node):
			node.call("_abort")
		await _settle(4)
	else:
		print("QA_TITLE_SKIP_TRANSITION_SHORE (headless/no live)")

	_main.load_scene("cg_narrate_table")
	await _settle(8)
	await _shot("05_wine_shed")

	print("QA_TITLE_SHOTS_SAVED %d" % _saved.size())
	for p in _saved:
		print("  ", p)
	if _fails.is_empty():
		print("QA_TITLE_OK")
	else:
		print("QA_TITLE_FAIL")
		for f in _fails:
			print("  fail ", f)
	quit(0 if _fails.is_empty() else 1)


func _finish_title_stage() -> void:
	var stage: Node = _main.find_child("TitleStage", true, false)
	if stage != null and stage.has_method("_complete"):
		stage.call("_complete")


func _date_sub() -> String:
	var n := root.get_node_or_null("/root/Calendar")
	if n != null and n.has_method("get_date_string"):
		return str(n.call("get_date_string"))
	return "宝祐三年　三月初一"


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(stem: String) -> void:
	await _settle(2)
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		_fails.append("空帧 %s" % stem)
		return
	var path := "%s/%s.png" % [OUT_DIR, stem]
	var err := img.save_png(path)
	if err != OK:
		_fails.append("写失败 %s (%s)" % [stem, str(err)])
		return
	_saved.append(path)
	print("QA_TITLE_SHOT ", path)
