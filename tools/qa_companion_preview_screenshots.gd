extends SceneTree
## Lane Z3：伙伴草案预览浮页巡检。F7 开关；截图落 /workspace/nk1-qa-shots/companions/。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_companion_preview_screenshots.gd
## -s 勿用 autoload 标识符（Calendar/Voyage 等）；Main 用 load 实例化。

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/companions"

var _main: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_COMPANION_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(12)

	if str(_main.get("current_scene_id")) != "cg_title":
		_main.load_scene("cg_title")
		await _settle(8)
	await _shot("01_title_before")

	_main.call("_toggle_companion_preview")
	await _settle(10)
	var ov: Node = _main.get("_companion_preview")
	if not is_instance_valid(ov):
		_fails.append("F7 打开后无 CompanionPreview")
		print("QA_COMPANION_FAIL open")
	else:
		print("QA_COMPANION_OPEN ok")
		var stamp := _find(ov, "DraftStamp")
		if stamp == null or not ("草案预览" in str(stamp.get("text"))):
			_fails.append("缺草案预览题签")
		var grid := _find(ov, "CardGrid")
		var n := 0 if grid == null else grid.get_child_count()
		if n != 6:
			_fails.append("剪影卡数=%d（期望 6）" % n)
		else:
			print("QA_COMPANION_CARDS 6")
	await _shot("02_preview_open")

	# 合上
	_main.call("_toggle_companion_preview")
	await _settle(8)
	if is_instance_valid(_main.get("_companion_preview")):
		_fails.append("再按 F7 未关闭浮页")
	else:
		print("QA_COMPANION_CLOSE ok")
	await _shot("03_preview_closed")

	# 港页再开一次
	_main.load_scene("quanzhou")
	await _settle(10)
	_main.call("_toggle_companion_preview")
	await _settle(10)
	await _shot("04_quanzhou_preview")
	_main.call("_toggle_companion_preview")
	await _settle(6)

	print("QA_COMPANION_SHOTS_SAVED %d" % _saved.size())
	for p in _saved:
		print("  ", p)
	if _fails.is_empty():
		print("QA_COMPANION_OK")
		quit(0)
	else:
		print("QA_COMPANION_WARN")
		for f in _fails:
			print("  warn ", f)
		quit(0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	await _settle(2)
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fails.append("截屏失败 %s" % name)
		print("QA_COMPANION_SHOT_FAIL ", name)
		return
	var path := "%s/%s.png" % [OUT_DIR, name]
	if img.save_png(path) != OK:
		_fails.append("save_png 失败 %s" % path)
		print("QA_COMPANION_SHOT_FAIL ", name)
		return
	_saved.append(path)
	print("QA_COMPANION_SHOT ", name)


func _find(node: Node, target: String) -> Node:
	if node == null:
		return null
	if str(node.name) == target:
		return node
	for c in node.get_children():
		var hit := _find(c, target)
		if hit != null:
			return hit
	return null
