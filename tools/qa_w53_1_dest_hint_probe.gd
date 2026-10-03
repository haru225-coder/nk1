extends SceneTree
## lane w53-1：目的地出带箭头（MapView._draw_dest_edge_hint）不压别的港框 / 港名 / 船标。
## 目的地被挤出图带时，图带边上画朱箭指向它并写港名；原先只让开船标，放大看海岸时常压在近岸港上——泉州往占城、在泉州一带
## 放大到 1.0，朱箭压住漳州港框，「占城」两字叠在「漳州」头上，像是那港的名字（1280×720 实跑截图）。
## 取三种镜头，第四章全部已解锁港两两成对：
##   选向——SeaChart._refresh_hand 框起讫两港（pad 0.30，即时）；
##   放大——玩家在起点港处滚轮放大到 1.0 看海岸；
##   航行——船标在航线 30% / 60% / 90% 处，镜头照跟船（MapView._keep_in_band 把船标收进图带，离边 FOLLOW_MARGIN）。
## 断言：
##   H1 出箭头的镜头够多（不然测不到）；
##   H2 朱箭三角与名字的外框不压港框 / 港名 / 船标（_port_obstacles；目的港自己的也算——落在图带边那圈里时
##      出带箭头的名字与它自己的港名同字，叠在一起更乱）；
##   H3 箭尖仍在图带边上（挪动只沿图带边、出不了图带），离原位不过 8 步 × 14 屏幕 px；三角尖朝目的地。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_dest_hint_probe.gd
## 末行 DEST_HINT cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

var _map: Node
var cases := 0
var fails := 0


func _init() -> void:
	call_deferred("_run")


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
	if not _map.has_method("dest_hint_layout"):
		print("  （MapView 无 dest_hint_layout：照原先只让船标的摆法复算）")
	var ids: Array = []
	for p in gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	var cam: Camera2D = _map.get("camera")
	var shown := {"选向": 0, "放大": 0, "航行": 0}
	var hits: Array = []
	var bad_tip: Array = []
	for a in ids:
		for b in ids:
			if a == b:
				continue
			_map.call("set_route", a, b, Color(0.66, 0.2, 0.16), true)
			for mode in ["选向", "放大", "航行"]:
				var fs: Array = [0.3, 0.6, 0.9] if mode == "航行" else [0.0]
				for f in fs:
					_map.call("show_ship_at_port", a)
					if mode == "选向":
						_map.call("frame_ports", [a, b], 0.30, 0.0)
					elif mode == "放大":
						cam.zoom = Vector2(1.0, 1.0)
						cam.position = (_map.get("port_px") as Dictionary)[a]
						_map.call("_clamp_camera")
					else:
						_map.call("frame_ports", [a, b], 0.30, 0.0)
						var ship: Node2D = _map.get("ship")
						ship.position = (_map.call("route_pose", f) as Array)[0]
						if _map.has_method("_keep_in_band"):
							_map.call("_keep_in_band", ship.position, 0.0)
							var ft = _map.get("_follow_tween")
							if ft != null and ft.is_valid():
								ft.custom_step(1.0)
					_map.set("_layout_key", "")
					_map.call("_ensure_layout")
					var h := _hint()
					if h.is_empty():
						continue
					shown[mode] = int(shown[mode]) + 1
					var tag := "%s %s→%s%s" % [mode, a, b, ("@%d%%" % int(f * 100)) if mode == "航行" else ""]
					var who := _overlaps(h)
					if not who.is_empty():
						hits.append("%s 压 %s" % [tag, ", ".join(who)])
					var why := _tip_check(h, b)
					if why != "":
						bad_tip.append("%s %s" % [tag, why])
	var total := int(shown["选向"]) + int(shown["放大"]) + int(shown["航行"])
	_expect(total >= 150, "H1 出箭头的镜头 %d 个（选向 %d / 放大 %d / 航行 %d）" % [total, shown["选向"], shown["放大"], shown["航行"]])
	_expect(hits.is_empty(), "H2 朱箭与名字不压港框 / 港名 / 船标（压 %d 处：%s）" % [hits.size(), "; ".join(hits.slice(0, 8))])
	_expect(bad_tip.is_empty(), "H3 箭尖在图带边上、挪不过 8 步、朝目的地（不合 %d 处：%s）" % [bad_tip.size(), "; ".join(bad_tip.slice(0, 6))])
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


func _px(screen_px: float) -> float:
	return screen_px / (_map.get("camera") as Camera2D).zoom.x


## 这一帧的出带箭头摆法：MapView.dest_hint_layout；没有它（回退）就照原先的摆法复算（只让船标）
func _hint() -> Dictionary:
	if _map.has_method("dest_hint_layout"):
		return _map.call("dest_hint_layout")
	var dest_id: String = _map.get("dest_id")
	var port_px: Dictionary = _map.get("port_px")
	if dest_id == "" or not port_px.has(dest_id):
		return {}
	var band: Rect2 = (_map.call("_band_world_rect") as Rect2).grow(-_px(20.0))
	var d: Vector2 = port_px[dest_id]
	if band.grow_individual(0.0, 0.0, 0.0, _px(52.0)).has_point(d):
		return {}
	var c := band.get_center()
	var dir := (d - c).normalized()
	var half := band.size * 0.5
	var tx := INF if absf(dir.x) < 1e-6 else half.x / absf(dir.x)
	var ty := INF if absf(dir.y) < 1e-6 else half.y / absf(dir.y)
	var e := c + dir * minf(tx, ty)
	var s := _px(9.0)
	var perp := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([e, e - dir * s * 1.7 + perp * s * 0.8, e - dir * s * 1.7 - perp * s * 0.8])
	var text := str((_map.call("_port_def", dest_id) as Dictionary).get("chart", {}).get("label", dest_id))
	var tp := e - dir * s * 3.2
	tp += Vector2(0, _px(5.0)) if dir.y < 0.0 else Vector2(0, -_px(4.0))
	var ship: Node2D = _map.get("ship")
	if bool(_map.get("ship_visible")) and ship.visible:
		var delta := tp - ship.position
		if delta.length() < _px(28.0) and delta.length() > 0.01:
			tp = ship.position + delta.normalized() * _px(28.0)
	var tw: float = _map.call("_text_width_world", text, 14)
	var th := _px(14.0 * 1.15)
	return {"tip": e, "tri": tri, "text": text, "text_pos": tp,
		"tri_rect": Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2]),
		"label_rect": Rect2(tp + Vector2(-tw * 0.5, -th * 0.8), Vector2(tw, th))}


## 朱箭三角 / 名字外框压到的港框、港名、船标，按名报
func _overlaps(h: Dictionary) -> Array:
	var lay: Dictionary = _map.get("_port_layout")
	var named: Array = []
	var ship: Node2D = _map.get("ship")
	if bool(_map.get("ship_visible")) and ship.visible:
		var sr := _px(26.0)
		named.append(["船标", Rect2(ship.position - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0))])
	for pid in lay.keys():
		named.append(["%s港框" % pid, (lay[pid]["box"] as Rect2).grow(_px(3.0))])
		named.append(["%s港名" % pid, lay[pid]["rect"]])
	var out: Array = []
	for pair in named:
		var o: Rect2 = pair[1]
		for part in [["朱箭", h["tri_rect"]], ["名字", h["label_rect"]]]:
			if o.intersects(part[1]) and o.intersection(part[1]).get_area() > 0.0:
				out.append("%s压%s" % [part[0], pair[0]])
	return out


## 箭尖在图带边（去 20 px 的那圈）上、离原位（带心朝目的地那条线与图带边的交点）不过 8 步、三角尖朝目的地
func _tip_check(h: Dictionary, dest: String) -> String:
	var band: Rect2 = (_map.call("_band_world_rect") as Rect2).grow(-_px(20.0))
	var e: Vector2 = h["tip"]
	var tol := _px(1.0)
	var on_edge := absf(e.x - band.position.x) <= tol or absf(e.x - band.end.x) <= tol \
		or absf(e.y - band.position.y) <= tol or absf(e.y - band.end.y) <= tol
	if not on_edge or not band.grow(tol).has_point(e):
		return "箭尖不在图带边上（%s）" % str(e.round())
	var d: Vector2 = (_map.get("port_px") as Dictionary)[dest]
	var c := band.get_center()
	var dir := (d - c).normalized()
	var half := band.size * 0.5
	var tx := INF if absf(dir.x) < 1e-6 else half.x / absf(dir.x)
	var ty := INF if absf(dir.y) < 1e-6 else half.y / absf(dir.y)
	var e0 := c + dir * minf(tx, ty)
	if e.distance_to(e0) > _px(8.0 * 14.0) + tol:
		return "离原位 %d 屏幕 px" % int(e.distance_to(e0) / _px(1.0))
	var tri: PackedVector2Array = h["tri"]
	var back := (tri[1] + tri[2]) * 0.5
	if (e - back).normalized().dot((d - e).normalized()) < 0.999:
		return "三角尖没朝目的地"
	return ""


func _report() -> void:
	print("DEST_HINT cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
