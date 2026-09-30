extends SceneTree
## chars 线薄接入巡检：打开 CharsShoreOverlay，截 wire_*.png 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/chars/。
## 用法：NK1_CHARS_SYNC=1 DISPLAY=:2 godot --path . -s res://tools/qa_chars_wire_screenshots.gd   # 截图门禁（须出 4 张）
##       godot --headless --path . -s res://tools/qa_chars_wire_screenshots.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## lane fx1：每张截图前、再逐页签（主 / 职事 / 市井 / 史实）查一遍——浮页整页最小宽不越视口、WireSheet 与「合上」钮整框在视口内
##   （名册行短注曾不截断，最长一行把浮页顶出 1280 右缘、「合上」钮切掉半截）；契约模式同样查。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_chars_wire_screenshots.gd

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
	ShotGate.frame_pressure(self)
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
		for spec in (load("res://scripts/chars/CharRoster.gd") as GDScript).TIERS:
			roster.call("_on_tab", str(spec[0]))
			await _settle(4)
			_expect_fits("页签「%s」" % str(spec[0]))

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	_expect_fits(stem)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)


## lane fx1：浮页在视口里放得下——WireSheet 最小宽 ≤ 视口宽减左右边距，整框与「合上」钮不出视口右缘 / 下缘
func _expect_fits(where: String) -> void:
	var sheet := _ov.get("_sheet") as Control
	var close := _ov.find_child("CloseButton", true, false) as Control
	if sheet == null or close == null:
		_fail("%s：浮页缺 WireSheet / CloseButton" % where)
		return
	var vp := root.get_visible_rect()
	var room := vp.size.x - sheet.offset_left + sheet.offset_right
	var min_w := sheet.get_combined_minimum_size().x
	if min_w > room + 0.5:
		_fail("%s：浮页最小宽 %.0f 超出视口可用宽 %.0f（名册行 / 立绘面板有字撑宽）" % [where, min_w, room])
	for pair in [["WireSheet", sheet.get_global_rect()], ["「合上」钮", close.get_global_rect()]]:
		var r: Rect2 = pair[1]
		if r.end.x > vp.end.x + 0.5 or r.end.y > vp.end.y + 0.5 or r.position.x < vp.position.x - 0.5:
			_fail("%s：%s %s 出视口 %s" % [where, str(pair[0]), str(r), str(vp)])


func _fail(msg: String) -> void:
	_fails.append(msg)
	print("  ✗ " + msg)
