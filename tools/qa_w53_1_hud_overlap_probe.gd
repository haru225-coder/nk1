extends SceneTree
## lane w53-1：海图上的港名、地名、出带箭头不钻到盖在图带上的 HUD 块底下（罗盘盘面与盘下针名、题记框、比例尺）。
## 原先港名只避港框、船标：选向框兴化—泉州等，「南島海道北口」的字落在罗盘盘面底下，盘下针名「丑针」压进港名里；
## 广州、漳州的港名压在比例尺「一百里」上——全图与全港对选向 183 个镜头里 33 个有港框或港名压在这几块下（1280×720 实跑）。
## HUD 块按海图页上那几个 Control 的实际位置自算（罗盘按盘面圆与盘下针名一行算，不按 MapView 收到的矩形）：
##   U1 画出来的港名不压 HUD 块；
##   U2 画出来的小字地名、地区名不压 HUD 块；
##   U3 出带箭头的朱箭与名字不压 HUD 块；
##   U4 港位本身落在 HUD 块里（港位是真经纬，挪不开）的才不写港名，不为让 HUD 多藏名字；
##   U0 镜头够多、量过的港名与地名够多（不然测不到）。
## HUD 块的样子：罗盘按盘面圆与盘下针名一行（U1–U3 量压没压），U4 按罗盘框连下沿 8 px（MapView 收的是框）；
## 比例尺只算墨线与里数那一块（框里其余透明）；题记框整块。
## 取景：全图；第四章已解锁港两两成对的选向取景（SeaChart._refresh_hand 那一框，pad 0.30）；收牌（H）后再全图一次。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_hud_overlap_probe.gd
## 末行 HUD_OVERLAP cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SMALL_KINDS := ["island", "cape", "strait", "mountain", "river", "note"]

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _chart: Control
var _map: Node
var _cam: Camera2D


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
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(12)
	_map = _chart.get("map")
	if _map == null:
		_expect(false, "SeaChart 挂上了但 map 为空（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	_cam = _map.get("camera")
	var ids: Array = []
	for p in gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	var specs: Array = [["全图"]]
	for a in ids:
		for b in ids:
			if a != b:
				specs.append(["选向", a, b])
	specs.append(["收牌全图"])
	var views := 0
	var n_names := 0
	var n_labels := 0
	var n_hints := 0
	var name_hits: Array = []
	var label_hits: Array = []
	var hint_hits: Array = []
	var boxes_under := 0
	var hidden_n := 0
	var hidden_bad: Array = []
	for sp in specs:
		_map.call("clear_route")
		_map.call("show_ship_at_port", "quanzhou")
		if sp[0] == "收牌全图":
			_chart.call("_toggle_deck")
			await _frames(3)
			_chart.call("_frame_home", 0.0)
		elif sp[0] == "全图":
			_chart.call("_frame_home", 0.0)
		else:
			_map.call("show_ship_at_port", sp[1])
			_map.call("set_route", sp[1], sp[2], Color(0.66, 0.2, 0.16), true)
			_map.call("frame_ports", [sp[1], sp[2]], 0.30, 0.0)
		_map.set("_layout_key", "")
		_map.call("_ensure_layout")
		views += 1
		var tag := " ".join(sp.map(func(x): return str(x)))
		var hud := _hud()
		var lay: Dictionary = _map.get("_port_layout")
		for pid in lay.keys():
			var L: Dictionary = lay[pid]
			var at := _screen_pt(L["v"])
			if _under(hud, _screen_rect((L["box"] as Rect2).grow(3.0 / _cam.zoom.x))) != "":
				boxes_under += 1
			if bool(L.get("name_hidden", false)):
				hidden_n += 1
				if not _in_frames(hud, at):
					hidden_bad.append("%s %s 港位 %s 不在 HUD 块里却没写港名" % [tag, pid, str(at.round())])
				continue
			n_names += 1
			var under := _under(hud, _screen_rect(L["rect"]))
			if under != "":
				name_hits.append("%s %s港名压%s" % [tag, pid, under])
		if _map.has_method("label_layout"):
			for it: Dictionary in _map.call("label_layout"):
				var kind := str(it["kind"])
				if kind == "sea":
					continue
				n_labels += 1
				var r := _label_rect(it)
				var under2 := _under(hud, _screen_rect(r))
				if under2 != "":
					label_hits.append("%s %s「%s」压%s" % [tag, kind, it["text"], under2])
		var h: Dictionary = _map.call("dest_hint_layout") if _map.has_method("dest_hint_layout") else {}
		if not h.is_empty():
			n_hints += 1
			for part in [["朱箭", h["tri_rect"]], ["名字", h["label_rect"]]]:
				var under3 := _under(hud, _screen_rect(part[1]))
				if under3 != "":
					hint_hits.append("%s 出带箭头%s压%s" % [tag, part[0], under3])
	_expect(views >= 150 and n_names >= 1000 and n_labels >= 500, "U0 镜头 %d 个、量过港名 %d 处、地名 %d 处、出带箭头 %d 处（港框压在 HUD 下 %d 处、不写港名 %d 处）" % [
		views, n_names, n_labels, n_hints, boxes_under, hidden_n])
	_expect(name_hits.is_empty(), "U1 港名不压罗盘 / 题记框 / 比例尺（压 %d 处：%s）" % [name_hits.size(), "; ".join(name_hits.slice(0, 5))])
	_expect(label_hits.is_empty(), "U2 小字地名、地区名不压 HUD 块（压 %d 处：%s）" % [label_hits.size(), "; ".join(label_hits.slice(0, 5))])
	_expect(hint_hits.is_empty(), "U3 出带箭头不压 HUD 块（压 %d 处：%s）" % [hint_hits.size(), "; ".join(hint_hits.slice(0, 5))])
	_expect(hidden_bad.is_empty(), "U4 只在港位落进 HUD 块时才不写港名（多藏 %d 处：%s）" % [hidden_bad.size(), "; ".join(hidden_bad.slice(0, 5))])
	_report()


## 这一刻海图页上的 HUD 块（海图屏幕坐标）：罗盘盘面（圆）与盘下针名一行、题记框、比例尺——按 Control 实际位置自算
func _hud() -> Dictionary:
	var compass: Control = _chart.get("compass")
	var scale_bar: Control = _chart.get("scale_bar")
	var origin := _chart.get_global_rect().position
	var out := {"circles": [], "rects": [], "frames": []}
	if compass != null and compass.is_visible_in_tree():
		var cr := Rect2(compass.global_position - origin, compass.size)
		var c := cr.get_center()
		var rad := minf(cr.size.x, cr.size.y) * 0.5 - 1.0
		(out["circles"] as Array).append(["罗盘盘面", c, rad])
		# 盘下针名：盘心下 r + 16 处基线、12 px 字，取宽 64 高 16
		(out["rects"] as Array).append(["罗盘针名", Rect2(c + Vector2(-32.0, rad + 4.0), Vector2(64.0, 16.0))])
		(out["frames"] as Array).append(cr.grow_individual(0.0, 0.0, 0.0, 8.0))
	if scale_bar != null and scale_bar.is_visible_in_tree():
		# 墨线（至多 190 px）连上方里数那一块；框里其余透明
		var ink := Rect2(scale_bar.global_position - origin + Vector2(4.0, 3.0), Vector2(196.0, 28.0))
		(out["rects"] as Array).append(["比例尺", ink])
		(out["frames"] as Array).append(ink)
	# 题记框：罗盘、比例尺之外挂在图带占位上的那块竖长条
	var holder := compass.get_parent() if compass != null else null
	if holder != null:
		for c2 in holder.get_children():
			if c2 is Control and c2 != compass and c2 != scale_bar and (c2 as Control).is_visible_in_tree() \
					and (c2 as Control).size.y > (c2 as Control).size.x * 2.0 and (c2 as Control).size.x > 40.0:
				var cart := Rect2((c2 as Control).global_position - origin, (c2 as Control).size)
				(out["rects"] as Array).append(["题记框", cart])
				(out["frames"] as Array).append(cart)
	return out


## 屏幕矩形 r 压在哪块 HUD 下（压到的面积 > 0），没有返回 ""
func _under(hud: Dictionary, r: Rect2) -> String:
	for c in hud["circles"]:
		var q := Vector2(clampf(c[1].x, r.position.x, r.end.x), clampf(c[1].y, r.position.y, r.end.y))
		if q.distance_to(c[1]) < float(c[2]):
			return str(c[0])
	for h in hud["rects"]:
		if (h[1] as Rect2).intersects(r) and (h[1] as Rect2).intersection(r).get_area() > 0.0:
			return str(h[0])
	return ""


## 屏幕点落没落在哪块 HUD 的框里（罗盘按框连下沿 8 px，与 MapView 收到的一致）
func _in_frames(hud: Dictionary, p: Vector2) -> bool:
	for f: Rect2 in hud["frames"]:
		if f.has_point(p):
			return true
	return false


func _screen_pt(w: Vector2) -> Vector2:
	var half: Vector2 = (_map.get_viewport() as SubViewport).get_visible_rect().size * 0.5
	return (w - _cam.position) * _cam.zoom.x + half


## 世界矩形 → 海图屏幕坐标
func _screen_rect(w: Rect2) -> Rect2:
	var half: Vector2 = (_map.get_viewport() as SubViewport).get_visible_rect().size * 0.5
	return Rect2((w.position - _cam.position) * _cam.zoom.x + half, w.size * _cam.zoom.x)


## 地名字框（世界坐标）：小字文楷数据字号、山名写在三峰下 字号 + 4 处；地区名仿宋 字号 + 1
func _label_rect(it: Dictionary) -> Rect2:
	var lb: Dictionary = it["lb"]
	var text := str(it["text"])
	var kind := str(it["kind"])
	var fnt: Font = _map.get("font")
	var sz := int(lb.get("size", 12))
	var off_y := 0.0
	if kind == "region":
		fnt = _map.get("font_title")
		sz = int(lb.get("size", 16)) + 1
	elif kind == "mountain":
		off_y = (sz + 4) / _cam.zoom.x
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / _cam.zoom.x
	var th := sz * 1.15 / _cam.zoom.x
	return Rect2((it["pos"] as Vector2) + Vector2(-w * 0.5, off_y - th * 0.8), Vector2(w, th))


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
	print("HUD_OVERLAP cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
