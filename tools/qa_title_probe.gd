extends SceneTree
## 标题页 / 序章题签巡检：截 title_*.png 到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/title/。
## 触发：开机进 cg_title；点「开卷」见「序章・卷首」；四方沙盘末页「翻页」见「序章・兴化海口」。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd   # 截图门禁（须出 5 张）
##       godot --headless --path . -s res://tools/qa_title_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截、墨幕按停拍相位截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("title")
const TAG := "QA_TITLE"
const EXPECTED_SHOTS := 5
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")
const _UT := preload("res://scripts/ui/UiTransition.gd")

var _main: Node
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
	Clock.frame_pressure(self)
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
		await _hold_shot(node, "03_transition_prologue_open")
		if is_instance_valid(node):
			node.call("_abort")
		await _settle(4)
	else:
		print("QA_TITLE_SKIP_TRANSITION_OPEN (headless/no live)")

	node = _UT.prologue_shore(_main, sub, Callable())
	if node != null:
		await _hold_shot(node, "04_transition_prologue_shore")
		if is_instance_valid(node):
			node.call("_abort")
		await _settle(4)
	else:
		print("QA_TITLE_SKIP_TRANSITION_SHORE (headless/no live)")

	_main.load_scene("cg_narrate_table")
	await _settle(8)
	await _shot("05_wine_shed")

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _finish_title_stage() -> void:
	var stage: Node = _main.find_child("TitleStage", true, false)
	if stage != null and stage.has_method("_complete"):
		stage.call("_complete")


func _date_sub() -> String:
	var n := root.get_node_or_null("/root/Calendar")
	if n != null and n.has_method("get_date_string"):
		return str(n.call("get_date_string"))
	return "宝祐三年　三月初一"


## 截题签停拍那一拍：按墨幕相位等，不数帧（原 36 帧：快机上只合 153 ms 还在淡入，满载慢帧下已整幕收场，lane gd14）
func _hold_shot(node: CanvasLayer, stem: String) -> void:
	var why := await Clock.wait_hold(self, node)
	if why != "":
		_fails.append("%s 没截到墨幕停拍：%s" % [stem, why])
		print("  ✗ %s 没截到墨幕停拍：%s" % [stem, why])
		return
	await _shot(stem)
	if not Clock.holding(node):
		_fails.append("%s 截图时墨幕已过停拍" % stem)
		print("  ✗ %s 截图时墨幕已过停拍" % stem)


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
