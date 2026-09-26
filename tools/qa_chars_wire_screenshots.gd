extends SceneTree
## chars 线薄接入巡检：打开 CharsShoreOverlay，截 wire_*.png 到 /workspace/nk1-qa-shots/chars/。
## 用法：NK1_CHARS_SYNC=1 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_chars_wire_screenshots.gd

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/chars"

var _ov: Control
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("NK1_CHARS_SYNC", "1")
	root.size = Vector2i(VIEW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_CHARS_WIRE_BEGIN")
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.055, 1.0)
	root.add_child(bg)
	# 经场景实例化，等 autoload（GameManager）就绪后再解析脚本
	_ov = (load("res://scenes/chars/CharsShoreOverlay.tscn") as PackedScene).instantiate()
	root.add_child(_ov)
	_ov.call("begin", "chen_wenlong")
	await _settle(14)
	await _shot("wire_01_roster_panel")

	_ov.call("focus_id", "chen_zan")
	await _settle(8)
	await _shot("wire_02_placeholder")

	_ov.call("focus_id", "merchant_lin")
	await _settle(6)
	await _shot("wire_03_merchant_lin")

	var roster = _ov.get("_roster")
	if roster != null and roster.has_method("_on_tab"):
		roster.call("_on_tab", "职事")
		await _settle(6)
		await _shot("wire_04_roster_crew")

	print("QA_CHARS_WIRE_SHOTS_SAVED %d" % _saved.size())
	for p in _saved:
		print("  ", p)
	if _fails.is_empty():
		print("QA_CHARS_WIRE_OK")
	else:
		print("QA_CHARS_WIRE_WARN")
		for f in _fails:
			print("  warn ", f)
	quit(0 if _saved.size() >= 2 else 1)


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
	print("QA_CHARS_WIRE_SHOT ", path)
