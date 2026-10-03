extends SceneTree
## lane w53-1：海图地区名（日本 / 筑前 / 交趾……，MapView 里 kind = region 的地名）不压港框、港名，也不压别的小字地名。
## 原先地区名不做避让（小字地名才避）：选向框福州—博多（缩放 0.28）时「日本」两字压在「博多」港名上，读成「博多本」；
## 放大到 2.6 看博多，「筑前」压港名（1280×720 实跑截图）。改后地区名原处撞了往下、往上各挪一行，都撞就不画。
## 取景：全图；第四章已解锁港两两成对的选向取景（SeaChart._refresh_hand 那一框，pad 0.30）；每港放大 0.5 / 0.8 / 1.2 / 1.8 / 2.6 / 3.2。
## 断言（每个镜头按 MapView.label_layout 的落点、本探针自算字框；没有 label_layout 的旧版照原先 _draw_labels 的取舍复算）：
##   G1 镜头够多、画出来的地区名够多（不然测不到）；
##   G2 地区名不压港框（外扩 3 屏幕 px）与港名；
##   G3 地区名不压同一镜头里画出来的小字地名（岛 / 岬 / 水门 / 山 / 河 / 注）；
##   G4 不为让位把地区名大批丢掉：该画的地区名（层级可见、在视野里、不与港同名同地）画出来不少于九成五，
##      挪过的离原处不过一行（字高 × 1.1）。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_region_label_probe.gd
## 末行 REGION_LABEL cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const ZOOMS := [0.5, 0.8, 1.2, 1.8, 2.6, 3.2]
const SMALL_KINDS := ["island", "cape", "strait", "mountain", "river", "note"]

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
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
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(12)
	_map = chart.get("map")
	if _map == null:
		_expect(false, "SeaChart 挂上了但 map 为空（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	if not _map.has_method("label_layout"):
		print("  （MapView 无 label_layout：照原先 _draw_labels 的取舍复算）")
	_cam = _map.get("camera")
	var ids: Array = []
	for p in gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	var specs: Array = [["全图", "quanzhou"]]
	for a in ids:
		for b in ids:
			if str(a) < str(b):
				specs.append(["选向", a, b])
	for a in ids:
		for z in ZOOMS:
			specs.append(["放大", a, z])
	var views := 0
	var drawn_n := 0
	var cand_n := 0
	var hit_port: Array = []
	var hit_small: Array = []
	var far_moved: Array = []
	for sp in specs:
		_map.call("clear_route")
		if sp[0] == "全图":
			_map.call("show_ship_at_port", sp[1])
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
		_map.set("_layout_key", "")
		_map.call("_ensure_layout")
		views += 1
		var tag := "%s %s" % [sp[0], " ".join(sp.slice(1).map(func(x): return str(x)))]
		var items: Array = _map.call("label_layout") if _map.has_method("label_layout") else _legacy_layout()
		var marks := _port_marks()
		var smalls: Array = []
		var regions: Array = []
		for it: Dictionary in items:
			var kind := str(it["kind"])
			if kind == "region":
				regions.append(it)
			elif kind in SMALL_KINDS:
				smalls.append(_small_rect(it))
		cand_n += _region_candidates()
		for it: Dictionary in regions:
			drawn_n += 1
			var lb: Dictionary = it["lb"]
			var text := str(it["text"])
			var r := _region_rect(it["pos"], text, int(lb.get("size", 16)))
			for m in marks:
				if (m[1] as Rect2).intersects(r) and (m[1] as Rect2).intersection(r).get_area() > 0.0:
					hit_port.append("%s「%s」压%s" % [tag, text, m[0]])
			for s: Rect2 in smalls:
				if s.intersects(r) and s.intersection(r).get_area() > 0.0:
					hit_small.append("%s「%s」压小字地名" % [tag, text])
			var anchor: Vector2 = _map.get("proj").to_px(float(lb.get("lon", 0.0)), float(lb.get("lat", 0.0)))
			var moved := (it["pos"] as Vector2).distance_to(anchor)
			if moved > r.size.y * 1.1 + 0.01:
				far_moved.append("%s「%s」挪了 %d 屏幕 px" % [tag, text, int(moved * _cam.zoom.x)])
	_expect(views >= 150 and drawn_n >= 200, "G1 镜头 %d 个、画出地区名 %d 处" % [views, drawn_n])
	_expect(hit_port.is_empty(), "G2 地区名不压港框与港名（压 %d 处：%s）" % [hit_port.size(), "; ".join(hit_port.slice(0, 6))])
	_expect(hit_small.is_empty(), "G3 地区名不压小字地名（压 %d 处：%s）" % [hit_small.size(), "; ".join(hit_small.slice(0, 6))])
	var kept := float(drawn_n) / float(maxi(cand_n, 1))
	_expect(cand_n > 0 and kept >= 0.95 and far_moved.is_empty(), "G4 该画的地区名画出 %d / %d（%.1f%%，限九成五），挪过的不出一行（超 %d 处：%s）" % [
		drawn_n, cand_n, kept * 100.0, far_moved.size(), "; ".join(far_moved.slice(0, 4))])
	_report()


## 港框（外扩 3 屏幕 px）与港名，按名报
func _port_marks() -> Array:
	var lay: Dictionary = _map.get("_port_layout")
	var out: Array = []
	for pid in lay.keys():
		out.append(["%s港框" % pid, (lay[pid]["box"] as Rect2).grow(_px(3.0))])
		out.append(["%s港名" % pid, lay[pid]["rect"]])
	return out


## 地区名的字框：仿宋（font_title）、字号 = 数据 + 1、以落点为基线中点（_draw_labels 的画法，本探针自算）
func _region_rect(pos: Vector2, text: String, data_size: int) -> Rect2:
	var sz := data_size + 1
	var fnt: Font = _map.get("font_title")
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / _cam.zoom.x
	var th := _px(sz * 1.15)
	return Rect2(pos + Vector2(-w * 0.5, -th * 0.8), Vector2(w, th))


## 小字地名的字框（文楷、数据字号；山名写在三峰下方 字号 + 4 处）
func _small_rect(it: Dictionary) -> Rect2:
	var lb: Dictionary = it["lb"]
	var text := str(it["text"])
	var sz := int(lb.get("size", 12))
	var fnt: Font = _map.get("font")
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / _cam.zoom.x
	var th := _px(sz * 1.15)
	var off_y := _px(sz + 4) if str(it["kind"]) == "mountain" else 0.0
	return Rect2((it["pos"] as Vector2) + Vector2(-w * 0.5, off_y - th * 0.8), Vector2(w, th))


## 这一镜头里「该画」的地区名个数：层级可见、落点在视野（外扩 200）里、不与画出来的港同名、不在港旁 30 屏幕 px 内
func _region_candidates() -> int:
	var z := _cam.zoom.x
	var view: Rect2 = (_map.call("world_visible_rect") as Rect2).grow(200.0)
	var names: Dictionary = _map.get("_port_label_texts")
	var n := 0
	for lb in _map.get("labels"):
		if str(lb.get("kind", "")) != "region" or not _tier_ok(lb, z):
			continue
		var v: Vector2 = _map.get("proj").to_px(float(lb.get("lon", 0.0)), float(lb.get("lat", 0.0)))
		if not view.has_point(v) or names.has(str(lb.get("text", ""))) or _map.call("_near_drawn_port", v, _px(30.0)):
			continue
		n += 1
	return n


func _tier_ok(lb: Dictionary, z: float) -> bool:
	if lb.has("zoom_min") or lb.has("zoom_max"):
		return z >= float(lb.get("zoom_min", 0.0)) and z <= float(lb.get("zoom_max", 99.0))
	return bool(_map.call("_tier_visible", str(lb.get("tier", "mid")), z))


## 旧版（无 label_layout）的取舍：小字地名避港框 / 港名 / 船标 / 先摆的小字，撞了不画；地区名、海名不避，画在经纬落点
func _legacy_layout() -> Array:
	var z := _cam.zoom.x
	var view: Rect2 = (_map.call("world_visible_rect") as Rect2).grow(200.0)
	var names: Dictionary = _map.get("_port_label_texts")
	var obst: Array = _map.get("_port_obstacles")
	var placed: Array = []
	var out: Array = []
	for lb in _map.get("labels"):
		if not _tier_ok(lb, z):
			continue
		var v: Vector2 = _map.get("proj").to_px(float(lb.get("lon", 0.0)), float(lb.get("lat", 0.0)))
		if not view.has_point(v):
			continue
		var kind := str(lb.get("kind", "sea"))
		var text := str(lb.get("text", ""))
		if kind in ["island", "region", "cape", "mountain", "note"]:
			if names.has(text) or _map.call("_near_drawn_port", v, _px(30.0 if kind != "mountain" else 20.0)):
				continue
		var it := {"lb": lb, "kind": kind, "text": text, "pos": v}
		if kind in SMALL_KINDS or not (kind in ["sea", "region"]):
			var r := _small_rect(it)
			var hit := false
			for o in obst + placed:
				if (o as Rect2).intersects(r):
					hit = true
					break
			if hit:
				continue
			placed.append(r)
		out.append(it)
	return out


func _px(screen_px: float) -> float:
	return screen_px / _cam.zoom.x


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
	print("REGION_LABEL cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
