extends SceneTree
## P7 visual QA: open guild join + exam sit panels and save PNGs.
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_p7_screenshots.gd
## Shots land in ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/polish/ (absolute; 01–06 originals one level up are kept). Leaves tools script untracked.
## 默认严格：须出 8 张；headless / 空视口 / 一色空图 / 张数不足一律非零退出。
## 契约模式（显式）：godot --headless --path . -s res://tools/qa_p7_screenshots.gd -- --contract
##   只验按钮与 flag 写入，不截图，收尾打 QA_P7_SHOTS_CONTRACT_OK。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_p7_screenshots.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("polish")
const TAG := "QA_P7_SHOTS"
const EXPECTED_SHOTS := 8
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _main: Node
var _gs: Node
var _saved: Array = []
var _fails: Array = []
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
	Clock.frame_pressure(self)
	_gs = root.get_node("GameState")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)

	# Enough cash + credit to show join as available (fee 2000, credit 8).
	_gs.money = maxi(int(_gs.money), 5000)
	_gs.merchant_credit = maxi(int(_gs.merchant_credit), 8)
	_gs.network = maxi(int(_gs.network), 1)
	_gs.last_port = "quanzhou"
	_gs.chapter = 1
	# Clear per-chapter exam flag so 入场赴试 shows.
	if _gs.has_method("clear_flag"):
		_gs.clear_flag("exam_sat_ch1")
	elif "exam_sat_ch1" in _gs.flags:
		_gs.flags.erase("exam_sat_ch1")
	for port in ["quanzhou", "hakata", "guangzhou"]:
		var fk := "guild_%s" % port
		if fk in _gs.flags:
			_gs.flags.erase(fk)

	await _open_and_shot("quanzhou_guild", "01_quanzhou_guild_join", "交会费入行")
	await _open_and_shot("hakata_guild", "02_hakata_guild_join", "交会费入行")
	await _open_and_shot("guangzhou_guild", "03_guangzhou_guild_join", "交会费入行")
	await _open_and_shot("quanzhou_exam", "04_quanzhou_exam_sit", "入场赴试")

	# After-join: press 交会费入行 at 泉州, reshoot.
	await _goto("quanzhou_guild")
	var join_btn := _button_with_text(_main, "交会费入行")
	if join_btn == null:
		_fails.append("泉州入行按钮缺失，无法拍已入行态")
	else:
		join_btn.pressed.emit()
		await _settle(4)
		await _shot("05_quanzhou_guild_joined")
		if not _gs.has_flag("guild_quanzhou"):
			_fails.append("入行后未写 guild_quanzhou")

	# After-exam: press 入场赴试, reshoot.
	await _goto("quanzhou_exam")
	var sit_btn := _button_with_text(_main, "入场赴试")
	if sit_btn == null:
		_fails.append("贡院赴试按钮缺失，无法拍已赴试态")
	else:
		sit_btn.pressed.emit()
		await _settle(4)
		await _shot("06_quanzhou_exam_sat")
		if not _gs.has_flag("exam_sat_ch1"):
			_fails.append("赴试后未写 exam_sat_ch1")

	# Other ports: read-only 会籍 / 赴试 cards should still carry a disabled chip.
	await _open_and_shot("mingzhou_guild", "07_mingzhou_guild_nojoin", "本港无会籍")
	await _open_and_shot("mingzhou_exam", "08_mingzhou_exam_nosit", "本港无贡院科场")

	# 截图门禁：张数不足或逻辑失败都非零退出（headless 空视口不得假绿）。
	if _contract:
		quit(ShotGate.finish_contract(TAG, _fails))
	else:
		quit(ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _open_and_shot(scene_id: String, name: String, must_btn: String) -> void:
	await _goto(scene_id)
	var btn := _button_with_text(_main, must_btn)
	if btn == null:
		_fails.append("%s 缺少按钮「%s」" % [scene_id, must_btn])
	else:
		print("OK button 「%s」 on %s" % [must_btn, scene_id])
	await _shot(name)


func _goto(scene_id: String) -> void:
	_main.load_scene(scene_id)
	await _settle(5)
	# Force a draw so get_texture is not a prior frame.
	RenderingServer.force_draw()
	await process_frame


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	var img := ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)
	# Reject near-black frames (no draw) even if not perfectly uniform.
	if img != null:
		var sample := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		var corner := img.get_pixel(8, 8)
		if sample.get_luminance() < 0.02 and corner.get_luminance() < 0.02:
			_fails.append("真失败：%s 截屏过暗 lum=%.3f/%.3f" % [name, sample.get_luminance(), corner.get_luminance()])


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _button_with_text(root_node: Node, text: String) -> Button:
	var hits: Array = []
	_collect_buttons(root_node, text, hits)
	if hits.is_empty():
		return null
	return hits[0]


func _collect_buttons(n: Node, text: String, hits: Array) -> void:
	if n.is_queued_for_deletion():
		return
	if n is Button and (n as Button).text == text:
		hits.append(n)
	for c in n.get_children():
		_collect_buttons(c, text, hits)
