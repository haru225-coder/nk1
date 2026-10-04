extends SceneTree
## lane w53-1：海图上点港名也算点了那个港（选向）；悬停在港名上那港亮圈。
## 原先只认港位 14 屏幕 px 以内：港名摆在港框右侧（或上下左）、离港位十几到五六十 px，玩家照字点「泉州」没有反应，
## 要点到字旁那个小方框才算。
## 走真输入：鼠标事件从根视口推进去（root.push_input → 海图页 SeaChart 的 GUI → SubViewportContainer → 海图子视口 →
## MapView._unhandled_input），与玩家点图同一条路，收 MapView.port_clicked。MapView 按事件自己的位置判港（_event_world）；
## headless 下读不到系统鼠标，判港若改回读 get_global_mouse_position，P1 也会红。
## 取景：全图；泉州 / 明州 / 广州 / 博多起锚的选向取景；每港放大 0.8 / 1.6 / 2.6。每个镜头里画出来的每个港：
##   P1 点港框（港位）照旧点得中（不因改动丢了原来的点法）；
##   P2 点港名（港名字框中点）点得中那港，不点到别的港；
##   P3 悬停港名，那港算悬停（MapView._hover_port）；
##   P4 点开阔海面（离所有港框、港名都远）不出 port_clicked。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_port_name_click_probe.gd
## 末行 PORT_NAME_CLICK cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const ORIGINS := ["quanzhou", "mingzhou", "guangzhou", "hakata"]
const ZOOMS := [0.8, 1.6, 2.6]

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _map: Node
var _cam: Camera2D
var _vp: SubViewport
var _chart: Control
var _clicked: Array = []


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	var gs: Node = root.get_node_or_null("GameState")
	var gm: Node = root.get_node_or_null("GameManager")
	var cal: Node = root.get_node_or_null("Calendar")
	if gs == null or gm == null or cal == null:
		_expect(false, "autoload 不全")
		_report()
		return
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	gs.chapter = 4
	gs.last_port = "quanzhou"
	cal.from_dict({"year": 1260, "month": 3, "day": 1})
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(12)
	_map = chart.get("map")
	if _map == null:
		_expect(false, "SeaChart 挂上了但 map 为空（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	_cam = _map.get("camera")
	_vp = _map.get_viewport() as SubViewport
	_chart = chart as Control
	_map.connect("port_clicked", func(pid: String) -> void: _clicked.append(pid))
	# 海图页照航行中处置点港（不改去向、不重新取景），镜头才停在这一镜头上逐港点；MapView 照样判港、发 port_clicked
	chart.set("sailing", true)
	var ids: Array = []
	for p in gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	var specs: Array = [["全图"]]
	for a in ORIGINS:
		for b in ids:
			if b != a:
				specs.append(["选向", a, b])
	for a in ids:
		for z in ZOOMS:
			specs.append(["放大", a, z])
	var views := 0
	var n_ports := 0
	var box_miss: Array = []
	var name_miss: Array = []
	var hover_miss: Array = []
	var sea_hits: Array = []
	for sp in specs:
		_map.call("clear_route")
		_map.call("show_ship_at_port", "quanzhou")
		if sp[0] == "全图":
			chart.call("_frame_home", 0.0)
		elif sp[0] == "选向":
			_map.call("show_ship_at_port", sp[1])
			_map.call("set_route", sp[1], sp[2], Color(0.66, 0.2, 0.16), true)
			_map.call("frame_ports", [sp[1], sp[2]], 0.30, 0.0)
		else:
			_map.call("show_ship_at_port", sp[1])
			_cam.zoom = Vector2(sp[2], sp[2])
			_cam.position = (_map.get("port_px") as Dictionary)[sp[1]]
			_map.call("_clamp_camera")
		_map.call("_on_camera_moved")
		_map.set("_layout_key", "")
		_map.call("_ensure_layout")
		views += 1
		var tag := " ".join(sp.map(func(x): return str(x)))
		var band: Rect2 = _map.call("_band_world_rect")
		var lay: Dictionary = (_map.get("_port_layout") as Dictionary).duplicate(true)
		for pid: String in lay.keys():
			var L: Dictionary = lay[pid]
			var nm: Rect2 = L["rect"]
			var at_name := nm.get_center()
			if not band.has_point(L["v"]) or not band.has_point(at_name):
				continue
			n_ports += 1
			var got_box := await _click(L["v"])
			if got_box != pid:
				box_miss.append("%s 点%s港框得「%s」" % [tag, pid, got_box])
			var got_name := await _click(at_name)
			if got_name != pid:
				name_miss.append("%s 点%s港名得「%s」" % [tag, pid, got_name])
			await _move(at_name)
			if str(_map.get("_hover_port")) != pid:
				hover_miss.append("%s 悬停%s港名得「%s」" % [tag, pid, _map.get("_hover_port")])
		var sea := _open_sea(band, lay)
		if is_finite(sea.x):
			var got_sea := await _click(sea)
			if got_sea != "":
				sea_hits.append("%s 点海面得「%s」" % [tag, got_sea])
	_expect(views >= 50 and n_ports >= 200, "P0 镜头 %d 个、点过的港 %d 个" % [views, n_ports])
	_expect(box_miss.is_empty(), "P1 点港框照旧点得中（不中 %d 处：%s）" % [box_miss.size(), "; ".join(box_miss.slice(0, 4))])
	_expect(name_miss.is_empty(), "P2 点港名点得中那港（不中 %d 处：%s）" % [name_miss.size(), "; ".join(name_miss.slice(0, 4))])
	_expect(hover_miss.is_empty(), "P3 悬停港名那港亮圈（不中 %d 处：%s）" % [hover_miss.size(), "; ".join(hover_miss.slice(0, 4))])
	_expect(sea_hits.is_empty(), "P4 点开阔海面不出 port_clicked（误中 %d 处：%s）" % [sea_hits.size(), "; ".join(sea_hits.slice(0, 4))])
	_report()


## 世界坐标 → 根视口里的屏幕坐标（海图子视口铺满海图页，海图页铺满根视口）
func _screen(world: Vector2) -> Vector2:
	return _chart.get_global_rect().position + (world - _cam.position) * _cam.zoom.x + _vp.get_visible_rect().size * 0.5


## 鼠标挪到 world 处（从根视口推一条 MouseMotion）
func _move(world: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = _screen(world)
	mm.global_position = mm.position
	root.push_input(mm)
	await process_frame


## 在 world 处原地按下松开左键，返回这一下发出的 port_clicked（没有为 ""）
func _click(world: Vector2) -> String:
	await _move(world)
	_clicked.clear()
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = _screen(world)
		mb.global_position = mb.position
		root.push_input(mb)
	await process_frame
	return str(_clicked[0]) if not _clicked.is_empty() else ""


## 图带里离所有港框、港名都远（≥ 80 屏幕 px）的一点；找不到返回 INF
func _open_sea(band: Rect2, lay: Dictionary) -> Vector2:
	var keep := 80.0 / _cam.zoom.x
	for fy in [0.5, 0.3, 0.7]:
		for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var p := band.position + band.size * Vector2(fx, fy)
			var ok := true
			for pid in lay.keys():
				if (lay[pid]["rect"] as Rect2).grow(keep).has_point(p) or (lay[pid]["v"] as Vector2).distance_to(p) < keep:
					ok = false
					break
			if ok:
				return p
	return Vector2(INF, INF)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("PORT_NAME_CLICK cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
