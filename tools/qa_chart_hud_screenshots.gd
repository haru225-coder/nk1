extends SceneTree
## Lane U：海图 HUD 信息密度巡检（港名密区 / 航行中 HUD / 告警朱字）。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/chart/
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd   # 截图门禁（须出 5 张）
##       godot --headless --path . -s res://tools/qa_chart_hud_screenshots.gd -- --contract   # 只验非渲染断言，不截图
## 默认严格须出 5 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_chart_hud_screenshots.gd
## 注意：本脚本勿在顶层类型标注 MapView（-s SceneTree 编译期尚无 autoload，会连带 MapView 编不过）。

const VIEW := Vector2i(1280, 720)
const CHART_SCENE := "res://scenes/SeaChart.tscn"
const WM_SCENE := "res://scenes/WorldMap.tscn"
const SP := preload("res://tools/src_probe.gd")  # 按名认函数的源码探查（lane cs15：不按前缀认名）
const TAG := "QA_CHART_HUD"
const EXPECTED_SHOTS := 5
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _out_dir := ShotGate.out_dir("chart")
var _chart: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--out="):
			_out_dir = str(a).substr(6)
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(_out_dir)
	print("QA_CHART_HUD_BEGIN")
	ShotGate.frame_pressure(self)
	_check_wiring()

	# 先挂 Main，让 autoload / class_name 与游戏一致（与 patrol_shell 同路径）
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await _frames(6)

	var gs: Node = root.get_node("GameState")
	var fleet: Node = root.get_node("Fleet")
	var voyage: Node = root.get_node("Voyage")
	var cal: Node = root.get_node("Calendar")
	gs.chapter = 4
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou"]
	gs.money = maxi(int(gs.money), 800)

	# ── 01 港名密区 ──
	_chart = (load(CHART_SCENE) as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(8)
	var map: Node = _chart.get("map")
	_expect(map != null, "MapView 已挂上")
	if map:
		map.call("frame_ports", ["quanzhou", "xinghua", "xinghua_harbor", "fuzhou", "zhangzhou", "penghu"], 0.10, 0.0)
		await _frames(6)
	await _shot("01_port_dense")

	# ── 02 航行中 HUD ──
	var hand: PackedStringArray = _chart.get("_hand")
	var far := ""
	var far_d := -1.0
	for pid in hand:
		var d: float = voyage.distance_li("quanzhou", str(pid))
		if d > far_d:
			far_d = d
			far = str(pid)
	_expect(far != "", "手牌里有去处")
	if far != "" and map:
		_chart.call("_select_heading", far)
		await _frames(4)
		_chart.set("total_li", far_d)
		_chart.set("remaining_li", far_d * 0.42)
		_chart.set("course_bearing", voyage.bearing("quanzhou", far))
		_chart.set("days_elapsed", 6)
		_chart.set("sailing", true)
		_chart.call("_lock_hand")
		var traveled := far_d * 0.58
		var at: Dictionary = voyage.point_along_track("quanzhou", far, traveled)
		var tw = map.call("move_ship_lonlat", float(at["lon"]), float(at["lat"]), voyage.bearing_at("quanzhou", far, traveled), 0.58, 0.01)
		# 裸 await finished：补间被 kill（再调 move_ship_lonlat）就永不返回；改带墙钟上界
		if tw is Tween and not await Clock.until(self, func() -> bool: return not (tw as Tween).is_running()):
			_expect(false, "船标补间 %d ms 内没走完" % Clock.WAIT_MS)
		var ship: Node2D = map.get("ship")
		if ship:
			map.call("frame_rect", Rect2(ship.position, Vector2.ZERO), 0.0, 0.0)
		var cam: Camera2D = map.get("camera")
		if cam:
			cam.zoom = Vector2(1.4, 1.4)
		map.call("_clamp_camera")
		map.call("_on_camera_moved")
		_chart.call("_refresh_status")
		await _frames(4)
	await _shot("02_sailing_hud")

	# ── 03/04 告警朱字 ──
	_chart.set("sailing", false)
	_chart.set("days_elapsed", 0)
	fleet.water = 6
	fleet.food = 6
	gs.contract = {
		"good_id": "silk_fabric", "remaining": 30, "qty": 30,
		"dest": far if far != "" else "hakata", "from": "quanzhou",
		"due_day": cal.absolute_day() + 2, "purse": 900, "paid": 0,
	}
	_chart.call("_log", "[color=#A8322A]第 5 日・水粮已尽　舱中有人病倒[/color]")
	_chart.call("_refresh_hand")
	if far != "":
		_chart.call("_select_heading", far)
	await _frames(4)
	await _shot("03_alert_strip")
	_chart.call("_toggle_condition")
	await _frames(12)
	_expect(_condition_alpha() >= 1.0, "船况层已淡入满（a=%.2f）" % _condition_alpha())
	await _shot("04_alert_condition")

	# ── 05 小地图：卸海图、藏 Main，只留 WorldMap HUD 雷达 ──
	if ResourceLoader.exists(WM_SCENE):
		if is_instance_valid(_chart):
			root.remove_child(_chart)
			_chart.free()
			_chart = null
		await _frames(2)
		for c in main.get_children():
			if c is CanvasItem:
				(c as CanvasItem).visible = false
		main.visible = false
		var wm: Node = (load(WM_SCENE) as PackedScene).instantiate()
		root.add_child(wm)
		await _frames(12)
		await _shot("05_minimap_hud")
		if is_instance_valid(wm):
			root.remove_child(wm)
			wm.free()
		await _frames(1)

	_report()


func _check_wiring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	_expect("AUTOWRAP_OFF" in src, "顶匾 strip 不折行")
	_expect("委办剩" in src and "半途必尽" in src, "告警朱字短标签")
	var mini := FileAccess.get_file_as_string("res://scripts/Minimap.gd")
	_expect("子" in mini and "卯" in mini, "小地图子午卯酉短标")
	var mv := FileAccess.get_file_as_string("res://scripts/chart/MapView.gd")
	_expect("size_px := 16" in mv or "size_px := 16 if" in mv, "港名字号抬升")
	_expect(SP.has_tok(mv, "_px(26.0)"), "船标避让放大")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "placeholder", "玩家", "点击"]:
		_expect(bad not in _visible_strings(src), "SeaChart 可见文案无「%s」" % bad)


func _visible_strings(src: String) -> String:
	var rx := RegEx.new()
	rx.compile("\"([^\"\\\\]|\\\\.)*\"")
	var out := PackedStringArray()
	for line in src.split("\n"):
		var code := line.get_slice("#", 0)
		for m in rx.search_all(code):
			out.append(m.get_string())
	return "\n".join(out)


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完（进海图面纱 0.55 s、船况层淡入 0.16 s）；墙钟上界见 probe_clock.gd
func _frames(n: int) -> void:
	if not await Clock.settle(self, n):
		_expect(false, "演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


## 船况层不透明度（0 = 未开）
func _condition_alpha() -> float:
	var layer = _chart.get("_condition_layer") if is_instance_valid(_chart) else null
	return float(layer.modulate.a) if layer != null and bool(layer.visible) else 0.0


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [_out_dir, name], _saved, _fails)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _report() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, _out_dir, _fails))
