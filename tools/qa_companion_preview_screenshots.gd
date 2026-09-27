extends SceneTree
## Lane Z3：伙伴草案预览浮页巡检。F7 开关；截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/companions/。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_companion_preview_screenshots.gd   # 截图门禁（须出 4 张）
##       godot --headless --path . -s res://tools/qa_companion_preview_screenshots.gd -- --contract
## 截图缺张 / 空视口 / 一色空图 / headless 未开 --contract 一律非零退出（shot_gate.gd）；浮页断言仍只记 warn。
## -s 勿用 autoload 标识符（Calendar/Voyage 等）；Main 用 load 实例化。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_companion_preview_screenshots.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("companions")
const TAG := "QA_COMPANION"
const EXPECTED_SHOTS := 4
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _main: Node
var _saved: Array = []
var _fails: Array = []
var _shot_fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_COMPANION_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	Clock.frame_pressure(self)
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

	if not _fails.is_empty():
		print("QA_COMPANION_WARN")
		for f in _fails:
			print("  warn ", f)
	if _contract:
		quit(ShotGate.finish_contract(TAG, _shot_fails))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _shot_fails))


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(name: String) -> void:
	await _settle(2)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _shot_fails)


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
