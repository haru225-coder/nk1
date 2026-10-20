extends SceneTree
## lane w54-chartui：海图港名摆位（MapView._ensure_layout）不出露出的图带、不压东西——
## 候选八处（右、左、上、下、右上、右下、左上、左下），先挑不压东西（港框、船标、HUD 块、先摆下的港名）的，
## 重叠一样时挑出图带（顶匾之下、牌区之上，左右到屏幕边）最少的。
## 原先只有前六处、带外不算：贴着图带右边的港名照样摆右边、半截出了屏幕，右边让罗盘或别的港名占着时宁可摆到左边屏幕外；
## 挨着的港（兴化 / 兴化海口、泉州）六处都撞，名字压名字。全图、选向与拖到图带四边的 743 个镜头里，港框整个在带里的
## 1561 处有 59 处港名出带（40 处出了屏幕），港名互压 13 处、压别的港框 16 处、压 HUD 块 12 处（1280×720 实跑）。
## 取景：全图；第四章已解锁港两两成对的选向取景（SeaChart._refresh_hand 那一框，pad 0.30）；
##   拖图：每港在缩放 0.5 / 0.8 / 1.2 / 2.0 / 3.0 下把镜头挪到那港离图带右 / 左 / 上 / 下边 10、30 屏幕 px（玩家拖图的落点，照钳位）。
## 每个镜头按这一帧的港口布局逐港复算八处候选与摆它那一刻的障碍（船标、HUD 块、全部港框外扩 3 屏幕 px、先摆下的港名）：
##   B0 镜头够多、港框在带里的港够多、其中贴着图带边（80 屏幕 px 内）的够多（不然测不到）；
##   B1 港框（外扩 3 屏幕 px）整个在图带里的港，港名出了带，必是八处里没有一处既不压东西又整个在带里；
##   B2 港名压了东西，必是八处里没有一处不压东西；
##   B3 港名落点是八处候选之一（本探针的候选算法与 MapView 对得上，B1 / B2 才作数）；
##   B4 全部镜头合计不比改前多：港名出带 ≤ 59、互压 ≤ 13、压别的港框 ≤ 16、压 HUD 块 ≤ 12。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w54_chartui_name_band_probe.gd
## 末行 NAME_BAND cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const DRAG_ZOOMS := [0.5, 0.8, 1.2, 2.0, 3.0]
const DRAG_EDGES := ["右", "左", "上", "下"]
const DRAG_GAPS := [10.0, 30.0]
## 改前同一批镜头的合计（1280×720 实跑）：港名出带、互压、压别的港框、压 HUD 块
const BEFORE := {"out": 59, "nn": 13, "box": 16, "hud": 12}

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
	for a in ids:
		for z in DRAG_ZOOMS:
			for edge in DRAG_EDGES:
				for gap in DRAG_GAPS:
					specs.append(["拖图", a, z, edge, gap])
	var views := 0
	var n_in := 0
	var n_edge := 0
	var tot := {"out": 0, "nn": 0, "box": 0, "hud": 0}
	var b1_bad: Array = []
	var b2_bad: Array = []
	var b3_bad: Array = []
	for sp in specs:
		_map.call("clear_route")
		_map.call("show_ship_at_port", "quanzhou")
		if sp[0] == "全图":
			_chart.call("_frame_home", 0.0)
		elif sp[0] == "选向":
			_map.call("show_ship_at_port", sp[1])
			_map.call("set_route", sp[1], sp[2], Color(0.66, 0.2, 0.16), true)
			_map.call("frame_ports", [sp[1], sp[2]], 0.30, 0.0)
		else:
			_drag_to_edge(str(sp[1]), float(sp[2]), str(sp[3]), float(sp[4]))
		_map.call("_on_camera_moved")
		_map.set("_layout_key", "")
		_map.call("_ensure_layout")
		views += 1
		var tag := " ".join(sp.map(func(x): return str(x)))
		var z := _cam.zoom.x
		var band: Rect2 = _map.call("_band_world_rect")
		var lay: Dictionary = _map.get("_port_layout")
		var hud: Array[Rect2] = []
		for hr: Rect2 in _map.get("hud_rects"):
			hud.append(_map.call("_screen_to_world_rect", hr))
		# 摆港名之前就有的障碍：船标、HUD 块、全部港框（外扩 3 屏幕 px）；港名按布局先后一个个加进去
		var obstacles: Array[Rect2] = []
		var ship: Node2D = _map.get("ship")
		if bool(_map.get("ship_visible")) and ship.visible:
			var sr := 26.0 / z
			obstacles.append(Rect2(ship.position - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)))
		obstacles.append_array(hud)
		var boxes := {}
		for pid: String in lay.keys():
			boxes[pid] = (lay[pid]["box"] as Rect2).grow(3.0 / z)
			obstacles.append(boxes[pid])
		var names := {}
		for pid: String in lay.keys():
			var L: Dictionary = lay[pid]
			if bool(L.get("name_hidden", false)):
				continue
			var nm: Rect2 = L["rect"]
			var cands := _candidates(L, z)
			var hit := -1
			for i in cands.size():
				if _same_rect(cands[i], nm):
					hit = i
					break
			if hit < 0:
				b3_bad.append("%s %s港名 %s 不在八处候选里" % [tag, pid, str(nm)])
			var any_clean := false
			var any_clean_in := false
			for c: Rect2 in cands:
				if _cost(c, obstacles) <= 0.0:
					any_clean = true
					if band.encloses(c):
						any_clean_in = true
			if _cost(nm, obstacles) > 0.0 and any_clean:
				b2_bad.append("%s %s港名压了东西，八处里有不压的" % [tag, pid])
			if band.encloses(boxes[pid]):
				n_in += 1
				if not band.grow(-80.0 / z).has_point(L["v"]):
					n_edge += 1
				if not band.encloses(nm):
					tot["out"] = int(tot["out"]) + 1
					if any_clean_in:
						b1_bad.append("%s %s港名出%s，八处里有不压东西又在带里的" % [tag, pid, _side(band, nm)])
			for h in hud:
				if h.intersects(nm):
					tot["hud"] = int(tot["hud"]) + 1
					break
			for other: String in boxes.keys():
				if other != pid and (boxes[other] as Rect2).intersects(nm):
					tot["box"] = int(tot["box"]) + 1
			for other: String in names.keys():
				var o: Rect2 = names[other]
				if o.intersects(nm) and o.intersection(nm).get_area() * z * z > 4.0:
					tot["nn"] = int(tot["nn"]) + 1
			names[pid] = nm
			obstacles.append(nm)
	_expect(views >= 700 and n_in >= 1400 and n_edge >= 300,
		"B0 镜头 %d 个、港框在带里 %d 处、其中贴边 %d 处" % [views, n_in, n_edge])
	_expect(b1_bad.is_empty(), "B1 港名出带只在带里每一处都压东西时（违例 %d 处：%s）" % [b1_bad.size(), "; ".join(b1_bad.slice(0, 5))])
	_expect(b2_bad.is_empty(), "B2 港名压东西只在八处都压时（违例 %d 处：%s）" % [b2_bad.size(), "; ".join(b2_bad.slice(0, 5))])
	_expect(b3_bad.is_empty(), "B3 港名落点都是八处候选之一（对不上 %d 处：%s）" % [b3_bad.size(), "; ".join(b3_bad.slice(0, 3))])
	var worse: Array = []
	for k in BEFORE.keys():
		if int(tot[k]) > int(BEFORE[k]):
			worse.append("%s %d > 改前 %d" % [k, int(tot[k]), int(BEFORE[k])])
	_expect(worse.is_empty(), "B4 合计不比改前多（出带 %d / 互压 %d / 压港框 %d / 压 HUD 块 %d；改前 %d / %d / %d / %d）%s" % [
		int(tot["out"]), int(tot["nn"]), int(tot["box"]), int(tot["hud"]),
		int(BEFORE["out"]), int(BEFORE["nn"]), int(BEFORE["box"]), int(BEFORE["hud"]), "；".join(worse)])
	_report()


## 港名八处候选（与 MapView._ensure_layout 同一套：右、左、上、下、右上、右下、左上、左下），各自的字框
func _candidates(L: Dictionary, z: float) -> Array[Rect2]:
	var v: Vector2 = L["v"]
	var size_px := float(L["size_px"])
	var sz: Vector2 = (L["rect"] as Rect2).size
	var bw := sz.x
	var bh := sz.y
	var th := size_px * 1.15 / z
	var pad := float(L["r"]) + 7.0 / z
	var offs := [
		Vector2(pad, size_px * 0.4 / z),
		Vector2(-pad - bw, size_px * 0.4 / z),
		Vector2(-bw * 0.5, -pad - bh + th),
		Vector2(-bw * 0.5, pad + th),
		Vector2(pad, -pad - bh + th),
		Vector2(pad, pad + th),
		Vector2(-pad - bw, -pad - bh + th),
		Vector2(-pad - bw, pad + th),
	]
	var out: Array[Rect2] = []
	for o: Vector2 in offs:
		out.append(Rect2(v + o - Vector2(0, th * 0.8), sz))
	return out


func _cost(r: Rect2, obstacles: Array[Rect2]) -> float:
	var c := 0.0
	for o in obstacles:
		if o.intersects(r):
			c += o.intersection(r).get_area()
	return c


func _same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 0.01 and a.size.distance_to(b.size) < 0.01


## 玩家拖图：缩放 z 下把镜头挪到 pid 离图带某边 gap 屏幕 px（照 MapView 钳位，贴画布边的港挪不到就停在钳位处）
func _drag_to_edge(pid: String, z: float, edge: String, gap: float) -> void:
	_cam.zoom = Vector2(z, z)
	var band: Rect2 = _map.call("_band_world_rect")
	var v: Vector2 = (_map.get("port_px") as Dictionary)[pid]
	var g := gap / z
	var shift := Vector2.ZERO
	match edge:
		"右":
			shift.x = v.x - (band.end.x - g)
		"左":
			shift.x = v.x - (band.position.x + g)
		"上":
			shift.y = v.y - (band.position.y + g)
		"下":
			shift.y = v.y - (band.end.y - g)
	_cam.position += shift
	_map.call("_clamp_camera")


func _side(band: Rect2, r: Rect2) -> String:
	if r.end.x > band.end.x:
		return "右边"
	if r.position.x < band.position.x:
		return "左边"
	if r.position.y < band.position.y:
		return "上沿"
	return "下沿"


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
	print("NAME_BAND cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
