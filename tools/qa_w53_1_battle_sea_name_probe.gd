extends SceneTree
## lane w53-1：海上遇敌的海域名（SeaChart._battle_sea_name → pending_battle.sea_name）按船这一日的所在取港，不按起锚港。
## 海域名写进海战墨边题签（「泉州外海・遇敌」、出战「…・夺船」）与海战海况（SeaState 按名里的港名认闽海 / 南海 / 黑潮……定流）。
## 原先恒取起锚港：泉州往博多走到九成、船离泉州两千三百里就在博多唐房外，题签仍写「泉州外海・遇敌」、海流按闽海；
## 占城往博多走到九成五、离占城五千里，写「占城外海」、流按南海。第四章已解锁港两两成对、航程 5%…95% 共 3458 处，
## 74% 起锚港并不是离船最近的港（1280×720 实跑截图）。
## 断言：
##   S1 全表（第四章已解锁港两两成对 × 航程 5%…95% 每 5%）：_battle_sea_name 写的港 = 离船最近的港
##      （船位取 Voyage.point_along_track——海图船标即按它落点；港位取 ports.json 经纬，大圆距离本探针自算，不借 Voyage.nearest_sea_port）；
##   S2 起锚当日（航程 0）仍写起锚港——近港开战照旧是「泉州外海」；
##   S3 实点「迎战」：泉州→博多九成处遇海盗、遇元军哨船各点一次「迎战」，pending_battle.sea_name 写博多一带的港名，
##      海战 SeaState 认的海域是东海外洋（黑潮），不是闽海。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_battle_sea_name_probe.gd
## 末行 BATTLE_SEA_NAME cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const EARTH_R_LI := 6371.0 / 0.576

var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false
var _gm: Node
var _voy: Node
var _chart: Node


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
	_gm = root.get_node_or_null("GameManager")
	_voy = root.get_node_or_null("Voyage")
	var cal: Node = root.get_node_or_null("Calendar")
	var fleet: Node = root.get_node_or_null("Fleet")
	if gs == null or _gm == null or _voy == null or cal == null or fleet == null:
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
	if not _chart.has_method("_battle_sea_name") or _chart.get("map") == null:
		_expect(false, "SeaChart 挂上了但没有 _battle_sea_name / map（SeaChart.gd 编不过？）")
		_report()
		return
	var ids: Array = []
	for p in _gm.unlocked_ports():
		ids.append(str(p.get("id", "")))
	var n_pts := 0
	var wrong: Array = []
	var wrong_start: Array = []
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var total: float = _voy.distance_li(a, b)
			for k in range(0, 20):
				var tr := total * float(k) / 20.0
				_put_at(a, b, tr)
				var got := str(_chart.call("_battle_sea_name"))
				if k == 0:
					var want0 := "%s外海" % _gm.get_port_name(a)
					if got != want0:
						wrong_start.append("%s→%s 写「%s」" % [a, b, got])
					continue
				n_pts += 1
				var at: Dictionary = _voy.point_along_track(a, b, tr)
				var near := _nearest_port(float(at["lon"]), float(at["lat"]))
				var want := "%s外海" % _gm.get_port_name(near)
				if got != want:
					var pa: Dictionary = _gm.get_port_by_id(a)
					var off := _li(float(at["lon"]), float(at["lat"]), float(pa["lon"]), float(pa["lat"]))
					wrong.append([off, "%s→%s@%d%% 写「%s」，船离%s %d 里、最近是%s" % [a, b, k * 5, got, _gm.get_port_name(a),
						int(off), _gm.get_port_name(near)]])
	# 报离起锚港最远的几处
	wrong.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var worst: Array = []
	for w in wrong.slice(0, 4):
		worst.append(w[1])
	_expect(n_pts >= 3000 and wrong.is_empty(), "S1 航程 5%%…95%% 共 %d 处，海域名都取离船最近的港（不合 %d 处：%s）" % [
		n_pts, wrong.size(), "; ".join(worst)])
	_expect(wrong_start.is_empty(), "S2 起锚当日仍写起锚港（不合 %d 对：%s）" % [wrong_start.size(), "; ".join(wrong_start.slice(0, 4))])
	# S3：真点「迎战」——海盗与元军哨船两条路都写 pending_battle.sea_name，海战按它定海域流况
	fleet.water = 200
	fleet.food = 200
	var pirate: Array = await _fight_at("quanzhou", "hakata", 0.9, _voy.pirate_sighting())
	var patrol: Array = await _fight_at("quanzhou", "hakata", 0.9, _voy.call("_yuan_patrol_event"))
	for pair in [["海盗", pirate], ["元军哨船", patrol]]:
		var r: Array = pair[1]
		_expect(r.size() == 3 and r[0] == "博多唐房外海" and r[1] == "kuroshio",
			"S3 泉州→博多九成处遇%s点「迎战」：题签海域「%s」、海战海况认作「%s」（应为博多唐房外海 / 东海外洋）" % [
				pair[0], r[0] if r.size() > 0 else "?", r[2] if r.size() > 2 else "?"])
	_report()


## 海图停在 a→b 已行 tr 里处、正在航行（_on_sail_pressed / _sail_next_day 改的那几项），不起逐日链
func _put_at(a: String, b: String, tr: float) -> void:
	var total: float = _voy.distance_li(a, b)
	_chart.set("origin_port", a)
	_chart.set("selected_port", b)
	_chart.set("total_li", total)
	_chart.set("remaining_li", total - tr)
	_chart.set("sailing", true)


## 停到 a→b 航程 f 处，摆出遇事板，点「迎战」；返回 [pending_battle.sea_name, 海况 region_id, region_name]，拆掉海战布景
func _fight_at(a: String, b: String, f: float, event: Dictionary) -> Array:
	var total: float = _voy.distance_li(a, b)
	_put_at(a, b, total * f)
	_chart.set("voyage_started", true)
	_chart.call("_show_event", event)
	await _frames(2)
	var fight: Button = null
	for btn in (_chart.get("event_actions") as Node).get_children():
		if btn is Button and not btn.is_queued_for_deletion() and btn.text == "迎战":
			fight = btn
	if fight == null:
		return []
	fight.emit_signal("pressed")
	await _frames(3)
	var wm: Node = null
	for c in _chart.get_children():
		if c.has_signal("battle_finished") and not c.is_queued_for_deletion():
			wm = c
	var out: Array = [str(_gm.pending_battle.get("sea_name", "")), "", ""]
	if wm != null:
		var sea = wm.call("sea_state")
		if sea != null:
			out[1] = str(sea.get("region_id"))
			out[2] = str(sea.get("region_name"))
		wm.set("resolved", true)  # 拆布景不收战（不发 battle_finished）
		wm.queue_free()
	_gm.pending_battle = {}
	for c in _chart.get_children():
		if c is CanvasItem and c != wm:
			(c as CanvasItem).visible = true
	await _frames(2)
	return out


## 离 (lon, lat) 大圆距离最近的港（ports.json 全表，数据序先到先得）
func _nearest_port(lon: float, lat: float) -> String:
	var best := ""
	var best_d := INF
	for p in _gm.ports_data.get("ports", []):
		var d := _li(lon, lat, float(p.get("lon", 0.0)), float(p.get("lat", 0.0)))
		if d < best_d:
			best_d = d
			best = str(p.get("id", ""))
	return best


func _li(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := p2 - p1
	var dl := deg_to_rad(lon2 - lon1)
	var h := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return EARTH_R_LI * 2.0 * atan2(sqrt(h), sqrt(1.0 - h))


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
	print("BATTLE_SEA_NAME cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
