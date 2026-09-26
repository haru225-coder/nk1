extends SceneTree
## Lane U：海图 HUD 信息密度巡检（港名密区 / 航行中 HUD / 告警朱字）。
## 截图落 /workspace/nk1-qa-shots/chart/
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_chart_hud_screenshots.gd
## 注意：本脚本勿在顶层类型标注 MapView（-s SceneTree 编译期尚无 autoload，会连带 MapView 编不过）。

const VIEW := Vector2i(1280, 720)
const CHART_SCENE := "res://scenes/SeaChart.tscn"
const WM_SCENE := "res://scenes/WorldMap.tscn"

var _out_dir := "/workspace/nk1-qa-shots/chart"
var _chart: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if str(a).begins_with("--out="):
			_out_dir = str(a).substr(6)
	root.size = VIEW
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("QA_CHART_HUD_BEGIN")
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
		if tw is Tween:
			await (tw as Tween).finished
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
	_expect("_px(26.0)" in mv, "船标避让放大")
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


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fails.append("截屏失败 %s" % name)
		return
	var path := "%s/%s.png" % [_out_dir, name]
	if img.save_png(path) != OK:
		_fails.append("save_png %s" % path)
		return
	_saved.append(path)
	print("SHOT ", path)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _report() -> void:
	print("QA_CHART_HUD_SHOTS %d" % _saved.size())
	if not _fails.is_empty():
		print("QA_CHART_HUD_FAIL")
		for f in _fails:
			print("  fail ", f)
		quit(1)
		return
	if _saved.size() < 3:
		print("QA_CHART_HUD_FAIL need ≥3 shots")
		quit(1)
		return
	print("QA_CHART_HUD_OK")
	quit(0)
