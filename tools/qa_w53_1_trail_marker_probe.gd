extends SceneTree
## lane w53-1：海图上「走过的那段航线描深」（MapView._draw_route 按 ship_progress 描）末端落在船标上，不前不后。
## 船标按 Voyage.point_along_track 的经纬投到画出的航线折线上（_arc_of_point）；描深原先按里程比例 frac 走折线——
## 里程按大圆量、折线按投影画布 px 量，南北跨得远的航线两者对不上：占城→博多走到五成五，描深末端落在船标后
## 33 画布 px，放大到 1.5 倍时隔开 50 屏幕 px，船尾后一截航线看着像没走过（1280×720 实跑截图）。
## 断言（真走海图逐日推船标：SeaChart._advance_ship_marker，按住空格一日 0.05 s，每帧取样）：
##   T1 三条远程（占城→博多、博多→占城、占城→耽罗）与一条近程（泉州→兴化）：补间每一帧，描深末端
##      （折线上 ship_progress 处）离船标 ≤ 0.5 画布 px；
##   T2 到港那一日描深走满（ship_progress = 1）、船标在目的港上。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_trail_marker_probe.gd
## 末行 TRAIL_MARKER cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const ROUTES := [["champa", "hakata"], ["hakata", "champa"], ["champa", "jeju"], ["quanzhou", "xinghua"]]
const DAYS := 30
const TOL := 0.5

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _voy: Node
var _chart: Node
var _map: Node


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
	var cal: Node = root.get_node_or_null("Calendar")
	_voy = root.get_node_or_null("Voyage")
	if gs == null or cal == null or _voy == null:
		_expect(false, "autoload 不全")
		_report()
		return
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	gs.chapter = 4
	gs.last_port = "quanzhou"
	cal.from_dict({"year": 1260, "month": 3, "day": 1})
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(12)
	_map = _chart.get("map")
	if _map == null or not _chart.has_method("_advance_ship_marker"):
		_expect(false, "SeaChart 挂上了但 map 为空 / 没有 _advance_ship_marker（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	for r in ROUTES:
		await _sail(str(r[0]), str(r[1]))
	space.pressed = false
	Input.parse_input_event(space)
	_report()


## a→b 分 DAYS 日走完：每日照 SeaChart._sail_next_day 扣余程后推船标，补间每帧量描深末端与船标
func _sail(a: String, b: String) -> void:
	var total: float = _voy.distance_li(a, b)
	_chart.set("origin_port", a)
	_chart.set("selected_port", b)
	_chart.set("total_li", total)
	_chart.set("remaining_li", total)
	_chart.set("sailing", true)
	_chart.call("_sync_map")
	_map.call("show_ship_at_port", a)
	var worst := 0.0
	var worst_at := ""
	var frames := 0
	for d in range(1, DAYS + 1):
		_chart.set("remaining_li", total * (1.0 - float(d) / float(DAYS)))
		var done := [false]
		var step := func() -> void:
			await _chart.call("_advance_ship_marker")
			done[0] = true
		step.call()
		while true:
			var gap := _gap()
			frames += 1
			if gap > worst:
				worst = gap
				worst_at = "第 %d 日" % d
			if done[0]:
				break
			await process_frame
	_expect(frames > DAYS and worst <= TOL, "T1 %s→%s 逐日 %d 帧：描深末端离船标至多 %.2f 画布 px（%s；限 %.1f）" % [
		a, b, frames, worst, worst_at if worst_at != "" else "—", TOL])
	var ship: Node2D = _map.get("ship")
	var dest_px: Vector2 = (_map.get("port_px") as Dictionary)[b]
	var prog: float = _map.get("ship_progress")
	_expect(is_equal_approx(prog, 1.0) and ship.position.distance_to(dest_px) <= TOL,
		"T2 %s→%s 到港：描深走满（ship_progress %.4f）、船标离港位 %.2f 画布 px" % [a, b, prog, ship.position.distance_to(dest_px)])
	_chart.set("sailing", false)


## 这一帧描深末端（_draw_route：折线上 ship_progress × 全长处）离船标多远（画布 px）
func _gap() -> float:
	var ship: Node2D = _map.get("ship")
	var end: Vector2 = (_map.call("route_pose", float(_map.get("ship_progress"))) as Array)[0]
	return end.distance_to(ship.position)


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
	print("TRAIL_MARKER cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
