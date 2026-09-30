extends SceneTree
## 人物呈现巡检：打开 scenes/chars/CharsDemo.tscn，逐档截帧到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/chars/。
## 用法：NK1_CHARS_SYNC=1 DISPLAY=:2 godot --path . -s res://tools/qa_chars_screenshots.gd
##       godot --headless --path . -s res://tools/qa_chars_screenshots.gd -- --contract   # 只验非渲染断言
## 截图缺张 / 空视口 / 一色空图 / headless 未开 --contract 一律非零退出（shot_gate.gd）；面板断言仍只记 warn。
## 本脚本不写任何游戏状态，只在末了 quit。
## lane w19-g6：每张截图前查演示页不裁——页身各栏与页头按钮整框在视口内、页身最小宽放得下（判红，进 _shot_fails）；
##   1280×720 下三栏放不下，演示页改两栏（右栏面板 / 站台二选一），站台两张前由切档 / 转台换到站台，面板几张前换回面板。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_chars_screenshots.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("chars")
const TAG := "QA_CHARS_SHOTS"
const EXPECTED_SHOTS := 10
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const SHOT_ORDER := ["chen_wenlong", "chen_zan", "merchant_lin", "monk_jinghai"]

var _demo: Node
var _saved: Array = []
var _fails: Array = []
var _shot_fails: Array = []
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
	print("QA_CHARS_BEGIN")
	_demo = (load("res://scenes/chars/CharsDemo.tscn") as PackedScene).instantiate()
	ShotGate.frame_pressure(self)
	root.add_child(_demo)
	await _settle(12)

	await _pick("chen_wenlong")
	await _shot("01_demo_protagonist")

	await _pick("chen_zan")
	await _shot("02_panel_placeholder")

	_demo.call("_toggle_mode")
	await _settle(6)
	await _shot("03_stage_volume")
	_demo.call("_toggle_mode")
	await _settle(4)
	if str(_demo.get("_stage_mode")) != "screen":
		_fails.append("站台档未切回画屏")

	_demo.call("_turn")
	await _settle(4)
	await _shot("04_stage_turned")

	if _demo.has_method("_show_view"):
		_demo.call("_show_view", "panel")
		await _settle(2)
	else:
		_shot_fails.append("演示页缺 _show_view，窄屏两栏换不回面板")
	var idx := 5
	for id in SHOT_ORDER:
		await _pick(str(id))
		await _shot("%02d_panel_%s" % [idx, str(id)])
		idx += 1

	for spec in [["职事", "roster_crew", 9], ["史实", "roster_historical", 10]]:
		_tab(str(spec[0]))
		await _settle(4)
		await _shot("%02d_%s" % [int(spec[2]), str(spec[1])])

	if not _fails.is_empty():
		print("QA_CHARS_SHOTS_WARN")
		for f in _fails:
			print("  warn ", f)
	quit(ShotGate.finish_contract(TAG, _shot_fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _shot_fails))


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	# 记进判红的 _shot_fails（lane gd24 普查）：原先进 _fails，那一份只打 warn、不判红——超上界照样绿，是碰运气
	if not await Clock.settle(self, n):
		var why := "演出 %d ms 内没静下来（%s）" % [Clock.WAIT_MS, Clock.overrun()]
		_shot_fails.append(why)
		print("  ✗ ", why)


func _pick(id: String) -> void:
	_demo.call("_pick", id)
	await _settle(5)
	if str(_demo.call("current")) != id:
		_fails.append("选人失败 %s（现为 %s）" % [id, str(_demo.call("current"))])


func _tab(tab_name: String) -> void:
	var roster: Node = _find(_demo, "CharRoster")
	if roster == null:
		_fails.append("未找到名册节点 CharRoster")
		return
	roster.call("_on_tab", tab_name)


func _shot(name: String) -> void:
	await _settle(2)
	if not _contract:
		await RenderingServer.frame_post_draw
		ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _shot_fails)
	_assert_scene()
	_assert_fits(name)


## lane w19-g6：演示页不出视口（原先名册钉死 404 + 面板 632 + 站台 352，1280 宽里站台与页头「退出」钮切在屏外）
func _assert_fits(where: String) -> void:
	var body := _find(_demo, "Body") as Control
	if body == null:
		_shot_fails.append("%s：演示页缺页身 Body" % where)
		print("  ✗ ", _shot_fails[-1])
		return
	var vr := root.get_visible_rect()
	if body.get_combined_minimum_size().x > body.size.x + 0.5:
		_shot_fails.append("%s：页身最小宽 %.0f 超出可用 %.0f" % [where, body.get_combined_minimum_size().x, body.size.x])
		print("  ✗ ", _shot_fails[-1])
	var boxes: Array = [body]
	for c in body.get_children():
		if (c as Control).is_visible_in_tree():
			boxes.append(c)
	for b in _demo.find_children("*", "Button", true, false):
		if (b as Control).is_visible_in_tree():
			boxes.append(b)
	for c in boxes:
		var r := (c as Control).get_global_rect()
		if r.position.x < vr.position.x - 0.5 or r.end.x > vr.end.x + 0.5 or r.end.y > vr.end.y + 0.5:
			_shot_fails.append("%s：%s %s 出视口 %s" % [where, str((c as Node).name), str(r), str(vr)])
			print("  ✗ ", _shot_fails[-1])
	var want := "CharStage3D" if where.contains("stage") else "CharPortraitPanel"
	var shown := _find(_demo, want) as Control
	if shown == null or not shown.is_visible_in_tree():
		_shot_fails.append("%s：该截的 %s 不在屏上" % [where, want])
		print("  ✗ ", _shot_fails[-1])


func _assert_scene() -> void:
	var panel: Node = _find(_demo, "CharPortraitPanel")
	if panel == null:
		panel = _find(_demo, "Panel")
	if panel == null:
		_fails.append("未找到人物面板 CharPortraitPanel")
		return
	if _find(panel, "Name") == null:
		_fails.append("面板缺题名 Name")
	var stage: Node = _find(_demo, "CharStage3D")
	if stage == null:
		_fails.append("未找到站台 CharStage3D")
		return
	var mat = stage.get("_screen_mat")
	if mat != null and mat.albedo_texture == null and str(_demo.call("current")) != "":
		_fails.append("站台画心无立绘（%s）" % str(_demo.call("current")))
	var roster: Node = _find(_demo, "CharRoster")
	if roster != null:
		var rows: Dictionary = roster.get("_rows")
		if rows.is_empty():
			_fails.append("名册当前档为空")


func _find(n: Node, node_name: String) -> Node:
	if n.name == node_name:
		return n
	for c in n.get_children():
		var hit := _find(c, node_name)
		if hit != null:
			return hit
	return null
