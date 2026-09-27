extends SceneTree
## chars 线薄接入巡检：打开 CharsShoreOverlay，截 wire_*.png 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/chars/。
## 用法：NK1_CHARS_SYNC=1 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_chars_wire_screenshots.gd   # 截图门禁（须出 4 张）
##       godot --headless --path /workspace/nk1 -s res://tools/qa_chars_wire_screenshots.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_chars_wire_screenshots.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("chars")
const TAG := "QA_CHARS_WIRE"
const EXPECTED_SHOTS := 4
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _ov: Control
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("NK1_CHARS_SYNC", "1")
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_CHARS_WIRE_BEGIN")
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.07, 0.055, 1.0)
	Clock.frame_pressure(self)
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

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)
