extends SceneTree
## lane w53-1：远程航行镜头跟船。明州—占城、占城—萨摩这类远程缩到最小也装不下起讫两港，发舶取景保起点；
## 原先船标逐日往前走、镜头不动，明州往占城（冬月顺风二十余日）走到第十五日前后就钻到航法栏与航向牌底下，
## 后十几日连抵港都在牌底下看不见（1280×720 实跑截图）。
## 照真游戏逐日链式推进：SeaChart._sail_next_day 在上一日船标补间 finished 里同步起下一日，日与日之间不等镜头补间静下来
## （每日等静了再走会把「隔日才跟」藏住）。每段航程先照选向那一下框起讫两港、等静（玩家看牌），再照发舶那一下框一遍、立刻起第一日。
## 断言：
##   F1 每日日末船标都在露出的图带里（顶匾之下、航法栏之上），抵港时目的港也在图带里；
##   F2 跟船只平移不改缩放；
##   F3 玩家真拖开镜头（按下—拖—停稳—松手，走 MapView._unhandled_input）把船标拖出图带，下一日不把镜头拽回；
##      再拖回来、船标回到图带里，往后照跟到港；
##   F4 航行中走到半路按 H 收牌，跟到大图带底边时再走到半路按 H 展牌（跟船补间正走着），此后每日与抵港船标都还在图带里；
##   F5 一开跟就每日都跟：第四日起日末船标离图带边不少于 FOLLOW_MARGIN − MARGIN_TOL（上一日跟船补间还差一帧时被当
##      「镜头忙」让掉，会隔一日才跟一次，船标贴到离牌边 42 px）；
##   F6 按住空格快进（一日 0.05 s，发舶取景若是 0.9 s 空转补间，船在里头就走十几日）北上占城往萨摩：每日船标都在图带里，
##      抵港萨摩在图带里。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_chart_follow_ship_probe.gd
## 末行 CHART_FOLLOW cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const Clock := preload("res://tools/probe_clock.gd")
## F5 容差：量的是船标补间放完那一刻，同长的跟船补间还差一帧（缓出段，压帧到每帧 0.133 s 时约 5 px）
const MARGIN_TOL := 10.0

var gs: Node
var gm: Node
var cal: Node
var voyage: Node
var fleet: Node
var _chart: Node
var _map: Node
var cases := 0
var fails := 0
var _margin := 64.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	voyage = root.get_node_or_null("Voyage")
	fleet = root.get_node_or_null("Fleet")
	if gs == null or gm == null or cal == null or voyage == null or fleet == null:
		_expect(false, "autoload 不全")
		_report()
		return
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	gs.chapter = 4
	gs.last_port = "mingzhou"
	gs.visited_ports = ["quanzhou", "mingzhou", "guangzhou", "champa", "kagoshima"]
	gs.money = 5000
	gs.contract = {}
	cal.from_dict({"year": 1260, "month": 11, "day": 1})
	fleet.morale = 70
	fleet.water = 900
	fleet.food = 900
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(12)
	_map = _chart.get("map")
	if _map == null or _chart.get("heading_row") == null:
		_expect(false, "SeaChart 挂上了但字段为空（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	_margin = float((_map.get_script() as Script).get_script_constant_map().get("FOLLOW_MARGIN", 64.0))
	await _voyage_plain("mingzhou", "champa", 11)
	await _drag_away("mingzhou", "champa")
	await _voyage_deck("mingzhou", "champa", 11)
	await _voyage_fast("champa", "kagoshima", 6)
	_report()


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


func _cam() -> Camera2D:
	return _map.get("camera") as Camera2D


func _vp() -> Vector2:
	return _map.get_viewport().get_visible_rect().size


## 世界点在屏幕上的位置
func _screen(world: Vector2) -> Vector2:
	return (world - _cam().position) * _cam().zoom.x + _vp() * 0.5


## 露出的图带（顶匾之下、航法栏之上）上下沿的屏幕 y
func _band() -> Vector2:
	return Vector2(float(_map.get("inset_top")), _vp().y - float(_map.get("inset_bottom")))


## 世界点离图带四边最近的屏幕距离（负 = 出带）
func _edge_gap(world: Vector2) -> float:
	var p := _screen(world)
	var b := _band()
	return minf(minf(p.x, _vp().x - p.x), minf(p.y - b.x, b.y - p.y))


func _in_band(world: Vector2) -> bool:
	return _edge_gap(world) >= -1.0


func _ship_pos() -> Vector2:
	return (_map.get("ship") as Node2D).position


func _where(world: Vector2) -> String:
	var b := _band()
	return "屏上 %s，图带 %d–%d" % [str(_screen(world).round()), int(b.x), int(b.y)]


## 等船标补间与镜头补间都走完（补间被顶掉不发 finished，按在跑补间数等，墙钟上界）
func _wait_moves() -> bool:
	return await Clock.settle(self, 2)


## 照选向（SeaChart._refresh_hand 框起讫两港，玩家看牌——等静）与发舶（_on_sail_pressed 再框一遍，不等，立刻起第一日）的图上几步
func _depart(a: String, b: String, month: int) -> float:
	cal.from_dict({"year": 1260, "month": month, "day": 1})
	gs.last_port = a
	if bool(_chart.get("_deck_hidden")):
		_chart.call("_toggle_deck")
	var total: float = voyage.distance_li(a, b)
	_chart.set("sailing", false)
	_chart.set("origin_port", a)
	_chart.set("selected_port", b)
	_chart.set("course_order", 0)
	_chart.set("total_li", total)
	_chart.set("remaining_li", total)
	_chart.set("course_bearing", voyage.bearing(a, b))
	_chart.set("days_elapsed", 0)
	_chart.call("_sync_map")
	_map.call("show_ship_at_port", a)
	_map.call("frame_ports", [a, b], 0.30, 0.7)
	await _frames(3)
	await _wait_moves()
	_chart.set("sailing", true)
	fleet.at_sea = true
	_map.call("frame_ports", [a, b], 0.30, 0.9)
	return total


## 照 SeaChart._sail_next_day 的无事日走一日：过一日、取所在段罗经、扣里程，再由 SeaChart 推船标。
## 船标这一日走完（补间 finished 同步唤醒）即返回，与真游戏一样不等镜头补间——调用方接着就起下一日
func _day(a: String, b: String, total: float) -> float:
	gm.advance_days(1)
	_chart.set("days_elapsed", int(_chart.get("days_elapsed")) + 1)
	var rem: float = float(_chart.get("remaining_li"))
	_chart.set("course_bearing", voyage.bearing_at(a, b, maxf(0.0, total - rem)))
	rem -= float(_chart.call("_day_progress", {}))
	_chart.set("remaining_li", rem)
	_chart.call("_refresh_status")
	if not await _chart.call("_advance_ship_marker"):
		_expect(false, "第 %d 日船标补间被顶掉 / 作废" % int(_chart.get("days_elapsed")))
	return rem


func _end_voyage() -> void:
	fleet.at_sea = false
	_chart.set("sailing", false)
	await _wait_moves()


func _voyage_plain(a: String, b: String, month: int) -> void:
	print("── 明州→占城冬月：照真游戏逐日链式推船标")
	var total := await _depart(a, b, month)
	var port_px: Dictionary = _map.get("port_px")
	_expect(not _in_band(port_px[b]), "发舶取景装不下占城（不然本探针测不到跟船）：占城%s" % _where(port_px[b]))
	var zoom0: float = _cam().zoom.x
	var out_days: Array = []
	var tight_days: Array = []
	var rem := total
	var n := 0
	while rem > 0.0 and n < 120:
		rem = await _day(a, b, total)
		n += 1
		var gap := _edge_gap(_ship_pos())
		if gap < -1.0:
			out_days.append("第%d日%s" % [n, str(_screen(_ship_pos()).round())])
		elif n >= 4 and rem > 0.0 and gap < _margin - MARGIN_TOL:
			tight_days.append("第%d日 %d px" % [n, int(gap)])
	_expect(n > 10 and rem <= 0.0, "照无事日走到港：%d 日" % n)
	_expect(out_days.is_empty(), "F1 每日船标都在图带里（出带 %d 日：%s）" % [out_days.size(), ", ".join(out_days.slice(0, 6))])
	_expect(tight_days.is_empty(), "F5 第四日起日末船标离图带边都不少于 %d px（贴边 %d 日：%s）" % [
		int(_margin - MARGIN_TOL), tight_days.size(), ", ".join(tight_days.slice(0, 6))])
	await _wait_moves()
	_expect(_in_band(port_px[b]), "F1 抵港时占城在图带里（%s）" % _where(port_px[b]))
	_expect(is_equal_approx(_cam().zoom.x, zoom0), "F2 跟船只平移不改缩放（%.3f → %.3f）" % [zoom0, _cam().zoom.x])


## 照玩家拖图：按下、拖到、停稳 150 ms（MapView 松手时最后一次移动距今超 80 ms 就不甩）、松手
func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	_map.call("_unhandled_input", press)
	var move := InputEventMouseMotion.new()
	move.position = to
	move.relative = to - from
	_map.call("_unhandled_input", move)
	await create_timer(0.15).timeout
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	_map.call("_unhandled_input", release)
	await _frames(2)


func _drag_away(a: String, b: String) -> void:
	print("── 玩家拖开镜头后不拽回，拖回来接着跟")
	var total: float = float(_chart.get("total_li"))
	_chart.set("sailing", true)
	fleet.at_sea = true
	# 船标一日折回航段中点（镜头照跟），落定
	_chart.set("remaining_li", total * 0.5)
	await _chart.call("_advance_ship_marker")
	await _wait_moves()
	var cam := _cam()
	var before := cam.position
	var ship_in := _in_band(_ship_pos())
	# 往下拖 560 px：镜头往北挪，船标往下出带
	await _drag(Vector2(640, 140), Vector2(640, 700))
	var parked := cam.position
	var ship_out := not _in_band(_ship_pos())
	var rem: float = await _day(a, b, total)
	await _wait_moves()
	_expect(ship_in and ship_out and cam.position.is_equal_approx(parked), "F3 船标被拖出图带后下一日不拽回镜头（拖前在带=%s、拖后出带=%s，镜头 %s → %s）" % [
		str(ship_in), str(ship_out), str(parked.round()), str(cam.position.round())])
	# 拖回原处：船标回到图带里，往后照跟
	var back := (parked - before) * cam.zoom.x
	await _drag(Vector2(640, 600), Vector2(640, 600) + back)
	var ship_back := _in_band(_ship_pos())
	var out_days: Array = []
	var moved := 0
	var n := 0
	while rem > 0.0 and n < 120:
		var c0 := cam.position
		rem = await _day(a, b, total)
		n += 1
		if not cam.position.is_equal_approx(c0):
			moved += 1
		if not _in_band(_ship_pos()):
			out_days.append("拖回后第%d日%s" % [n, str(_screen(_ship_pos()).round())])
	await _wait_moves()
	var port_px: Dictionary = _map.get("port_px")
	_expect(ship_back and moved > 0 and out_days.is_empty() and _in_band(port_px[b]),
		"F3 拖回后船标在图带里（%s）、往后照跟（镜头动了 %d 日、出带 %d 日：%s），抵港占城在图带里（%s）" % [
		str(ship_back), moved, out_days.size(), ", ".join(out_days.slice(0, 4)), _where(port_px[b])])
	await _end_voyage()


func _voyage_deck(a: String, b: String, month: int) -> void:
	print("── 明州→占城冬月：第三日走到半路按 H 收牌，跟到大图带底边再走到半路按 H 展牌")
	var total := await _depart(a, b, month)
	var port_px: Dictionary = _map.get("port_px")
	var out_days: Array = []
	var rem := total
	var n := 0
	var expanded_on := 0
	var moved_last := false
	var gap_bottom := INF
	while rem > 0.0 and n < 120:
		var hidden: bool = bool(_chart.get("_deck_hidden"))
		var press := n + 1 == 3
		if not press and hidden and expanded_on == 0 and n >= 4 and moved_last and gap_bottom <= _margin + MARGIN_TOL:
			press = true
			expanded_on = n + 1
		# 这一日船标补间起了以后、同一帧里按下（真按 H 也落在两日之间的帧里，_toggle_deck 再延一拍推图带）
		if press:
			_chart.call_deferred("_toggle_deck")
		var c0 := _cam().position
		rem = await _day(a, b, total)
		n += 1
		moved_last = not _cam().position.is_equal_approx(c0)
		gap_bottom = _band().y - _screen(_ship_pos()).y
		if not _in_band(_ship_pos()):
			out_days.append("第%d日%s（图带 %d–%d）" % [n, str(_screen(_ship_pos()).round()), int(_band().x), int(_band().y)])
	_expect(expanded_on > 0, "F4 前置：收牌后跟到大图带底边，第 %d 日走到半路展牌" % expanded_on)
	_expect(out_days.is_empty(), "F4 收牌、展牌后每日船标都在图带里（出带 %d 日：%s）" % [out_days.size(), ", ".join(out_days.slice(0, 4))])
	await _wait_moves()
	_expect(_in_band(port_px[b]), "F4 抵港时占城在图带里（%s）" % _where(port_px[b]))
	await _end_voyage()


func _space(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _voyage_fast(a: String, b: String, month: int) -> void:
	print("── 占城→萨摩六月：按住空格快进北上")
	await _space(true)
	var total := await _depart(a, b, month)
	var port_px: Dictionary = _map.get("port_px")
	_expect(Input.is_key_pressed(KEY_SPACE) and not _in_band(port_px[b]), "F6 前置：空格按住=%s，发舶取景装不下萨摩（%s）" % [
		str(Input.is_key_pressed(KEY_SPACE)), _where(port_px[b])])
	var out_days: Array = []
	var rem := total
	var n := 0
	var t0 := Time.get_ticks_msec()
	while rem > 0.0 and n < 120:
		rem = await _day(a, b, total)
		n += 1
		if not _in_band(_ship_pos()):
			out_days.append("第%d日%s" % [n, str(_screen(_ship_pos()).round())])
	var ms := Time.get_ticks_msec() - t0
	await _space(false)
	_expect(out_days.is_empty(), "F6 快进 %d 日（墙钟 %d ms）每日船标都在图带里（出带 %d 日：%s）" % [
		n, ms, out_days.size(), ", ".join(out_days.slice(0, 6))])
	await _wait_moves()
	_expect(_in_band(port_px[b]), "F6 抵港时萨摩在图带里（%s）" % _where(port_px[b]))
	await _end_voyage()


func _report() -> void:
	print("CHART_FOLLOW cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
