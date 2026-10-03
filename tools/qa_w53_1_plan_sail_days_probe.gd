extends SceneTree
## lane w53-1：航段推演（Voyage.plan）与实航逐日走法对账。
##   实航（SeaChart._sail_next_day）每日先过一日、取已行里程所在那一段的罗经（Voyage.bearing_at）、按 _day_progress 扣里程；
##   推演原先拿出港第一段的方位套全程——泉州出湾三条线都是 102 度，六月往广州去向牌写「侧风　约 10 日　八成 11 日」，
##   实航大半程顶头逆风，无事也要 23 日（实跑四趟 23–30 日）：水粮按十日备、委办期限按十日给，都赶不上。
## 断言：
##   C0 SeaChart 实航走法仍是「过一日 → bearing_at(已行) → _day_progress」，本探针照它走才算数。
##   C1 静风日数 = 照 SeaChart 无事日逐日走（GameManager.advance_days + SeaChart._day_progress）走到的日数；
##      季风两向、转换期、跨月换季、三航法、出湾段与主航段风不同的航线。
##   C2 全表：可去的港两两 × 十二个月初一，静风日数 = 同一逐日走法（只推历法）。
##   C3 去向牌：泉州→广州六月写全程占里程最多的「顶头逆风」与实走日数，不写出湾那段的侧风；不标换风。
##   C4 水粮只够 15 日：去向牌标「水粮不够」，船况航段写「半途必尽」（原先八成 11 日，不报）。
##   C5 图上航线按全程风着色：泉州→广州六月为逆风淡墨（原先按出湾段算成顺风朱砂）。
##   C6 途中换风只记季风变了：泉州→广州六月初一整段在六月不标；泉州→博多八月廿日西南风入转换期要标。
## 运行期脚本错（被测代码某条路径出错）只中止出错的那一个函数——断言整段跳过、fails 不涨、退出码守 0：
## 接共用件 tools/script_err_tally.gd，本进程 SCRIPT ERROR 即红；_run_guarded 包一层兜 _run 自己半路中止（lane w53-1）。
## 用法：godot --headless --path . -s res://tools/qa_w53_1_plan_sail_days_probe.gd
## 末行 PLAN_SAIL_DAYS cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 MapView 类型（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var gs: Node
var gm: Node
var cal: Node
var voyage: Node
var fleet: Node
var _chart: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


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
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou", "penghu", "hakata", "mingzhou", "guangzhou"]
	gs.money = 5000
	gs.contract = {}
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(8)
	if _chart.get("map") == null or _chart.get("heading_row") == null:
		_expect(false, "SeaChart 挂上了但字段为空（SeaChart.gd / MapView 编不过？）")
		_report()
		return
	_c0_sail_walk_anchor()
	var gz_days := _c1_sail_replay()
	_c2_full_table()
	await _c3_c5_card_route(gz_days)
	_c6_wind_changes()
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


func _stage(y: int, m: int, d: int, supply: int) -> void:
	cal.from_dict({"year": y, "month": m, "day": d})
	fleet.morale = 70
	fleet.water = supply
	fleet.food = supply
	fleet.at_sea = false


## 照 SeaChart._sail_next_day 的无事日逐日走：过一日 → 取当日所在段罗经 → _day_progress 扣里程，余程 ≤ 0 即抵港
func _sail_calm(a: String, b: String, order: int) -> int:
	var total: float = voyage.distance_li(a, b)
	_chart.set("origin_port", a)
	_chart.set("selected_port", b)
	_chart.set("course_order", order)
	_chart.set("total_li", total)
	_chart.set("remaining_li", total)
	fleet.at_sea = true
	var n := 0
	while n < 900:
		gm.advance_days(1)
		n += 1
		var rem: float = float(_chart.get("remaining_li"))
		_chart.set("course_bearing", voyage.bearing_at(a, b, maxf(0.0, total - rem)))
		rem -= float(_chart.call("_day_progress", {}))
		_chart.set("remaining_li", rem)
		if rem <= 0.0:
			break
	fleet.at_sea = false
	_chart.set("total_li", 0.0)
	_chart.set("remaining_li", 0.0)
	return n


# ── C0 实航走法锚 ──────────────────────────────────────

func _c0_sail_walk_anchor() -> void:
	print("── C0 SeaChart 实航走法（本探针 _sail_calm 照它走）")
	var src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	var body := src.substr(src.find("func _sail_next_day("))
	body = body.substr(0, body.find("\nfunc ", 10))
	var adv := body.find("GameManager.advance_days(1)")
	var brg := body.find("course_bearing = Voyage.bearing_at(origin_port, selected_port, maxf(0.0, total_li - remaining_li))")
	var step := body.find("remaining_li -= _day_progress(event)")
	_expect(adv >= 0 and brg > adv and step > brg, "_sail_next_day 仍是 过一日 → bearing_at(已行) → _day_progress（%d/%d/%d）" % [adv, brg, step])


# ── C1 静风日数 = 实航无事日逐日走 ─────────────────────

func _c1_sail_replay() -> int:
	print("── C1 静风日数 = 照 SeaChart 无事日逐日走到港的日数")
	var gz := -1
	var rows := [
		["quanzhou", "guangzhou", 1260, 6, 1, 0],
		["quanzhou", "guangzhou", 1260, 6, 1, 1],
		["quanzhou", "guangzhou", 1260, 6, 1, 2],
		["quanzhou", "mingzhou", 1260, 11, 15, 0],
		["quanzhou", "wenzhou", 1260, 6, 1, 0],
		["mingzhou", "champa", 1260, 11, 1, 0],
		["quanzhou", "hakata", 1260, 8, 20, 0],
		["guangzhou", "quanzhou", 1260, 12, 1, 0],
		["quanzhou", "penghu", 1260, 3, 1, 0],
		["quanzhou", "ryukyu", 1260, 12, 1, 1],
	]
	for r in rows:
		_stage(int(r[2]), int(r[3]), int(r[4]), 900)
		var plan: Dictionary = voyage.plan(str(r[0]), str(r[1]), int(r[5]))
		var sail := _sail_calm(str(r[0]), str(r[1]), int(r[5]))
		_expect(int(plan["days"]) == sail, "%s→%s %d-%02d-%02d %s：推演静风 %d 日 = 实走 %d 日（%s）" % [
			r[0], r[1], r[2], r[3], r[4], voyage.order_name(int(r[5])), int(plan["days"]), sail, str(plan["wind_desc"])])
		if str(r[1]) == "guangzhou" and int(r[5]) == 0:
			gz = sail
	return gz


# ── C2 全表 ────────────────────────────────────────────

func _c2_full_table() -> void:
	print("── C2 全表：可去的港两两 × 十二个月初一，静风日数 = 逐日走法")
	var ids: Array = []
	for p in gm.unlocked_ports():
		if int(p.get("depth", 0)) > 0:
			ids.append(str(p.get("id", "")))
	var n := 0
	var bad := 0
	var worst := ""
	var worst_gap := 0
	for a in ids:
		for b in ids:
			if a == b:
				continue
			for m in range(1, 13):
				_stage(1260, m, 1, 900)
				var plan: Dictionary = voyage.plan(a, b, 0)
				var total: float = voyage.distance_li(a, b)
				var rem := total
				var y := 1260
				var mo := m
				var d := 1
				var k := 0
				while k < 900:
					d += 1
					if d > 30:
						d = 1
						mo += 1
						if mo > 12:
							mo = 1
							y += 1
					k += 1
					var brg: float = voyage.bearing_at(a, b, maxf(0.0, total - rem))
					rem -= float(fleet.fleet_speed()) * float(voyage.wind_factor(brg, mo)) * float(voyage.order_speed_mult(0))
					if rem <= 0.0:
						break
				n += 1
				var gap: int = k - int(plan["days"])
				if gap != 0:
					bad += 1
					if absi(gap) > absi(worst_gap):
						worst_gap = gap
						worst = "%s→%s %d 月初一 推演 %d / 实走 %d" % [a, b, m, int(plan["days"]), k]
	_expect(n >= 12 * 12 * 11, "全表覆盖 %d 格（%d 港两两 × 十二月）" % [n, ids.size()])
	_expect(bad == 0, "全表静风日数与逐日走法对不上 %d / %d 格%s" % [bad, n, ("，最差 " + worst) if bad > 0 else ""])


# ── C3–C5 去向牌、水粮告警、航线着色 ─────────────────

func _c3_c5_card_route(gz_days: int) -> void:
	print("── C3 去向牌写全程的风与实走日数 / C4 水粮告警 / C5 航线着色")
	_stage(1260, 6, 1, 45)  # 小艍六人日耗 3，水粮 45 = 足 15 日
	var hd: GDScript = load("res://scripts/core/HeadingDraft.gd") as GDScript
	var salt := -1
	for s in range(0, 40):
		if "guangzhou" in hd.call("deal", "quanzhou", s):
			salt = s
			break
	_expect(salt >= 0, "泉州有一手风放出广州（salt=%d）" % salt)
	if salt < 0:
		return
	gs.draft_salt = salt
	_chart.set("origin_port", "quanzhou")
	_chart.set("sailing", false)
	_chart.set("course_order", 0)  # 针路（C1 末格留下的是外洋）
	_chart.set("selected_port", "guangzhou")
	_chart.call("_refresh_hand")
	await _frames(4)
	var hand: PackedStringArray = _chart.get("_hand")
	var row: HBoxContainer = _chart.get("heading_row")
	var card: Control = null
	var i := 0
	for c in row.get_children():
		if c.is_queued_for_deletion():
			continue
		if i < hand.size() and str(hand[i]) == "guangzhou":
			card = c as Control
		i += 1
	_expect(card != null and str(_chart.get("selected_port")) == "guangzhou", "去向牌里有广州、已选定")
	if card == null:
		return
	var lines: Array = []
	for l in card.find_children("*", "Label", true, false):
		lines.append((l as Label).text)
	var wind_line := str(lines[1]) if lines.size() > 1 else ""
	_expect(wind_line == "顶头逆风　约 %d 日" % gz_days, "C3 牌上风与日数「%s」= 「顶头逆风　约 %d 日」（实走）" % [wind_line, gz_days])
	_expect(not wind_line.contains("换风"), "C3 整段在六月，牌上不标换风")
	_expect("水粮不够" in lines, "C4 水粮足 15 日，牌上标「水粮不够」（牌文：%s）" % " / ".join(lines))
	var panel := str((_chart.get("status_label") as RichTextLabel).text)
	_expect(panel.contains("半途必尽"), "C4 船况航段写「半途必尽」")
	var map: Node = _chart.get("map")
	var consts: Dictionary = map.get_script().get_script_constant_map()
	var col: Color = map.get("route_color")
	_expect(col == consts["COL_ROUTE_FOUL"], "C5 泉州→广州六月航线着逆风淡墨（实为 %s）" % str(col))


# ── C6 途中换风 ────────────────────────────────────────

func _c6_wind_changes() -> void:
	print("── C6 途中换风只记季风变了")
	_stage(1260, 6, 1, 900)
	var gz: Dictionary = voyage.plan("quanzhou", "guangzhou", 0)
	_expect(not bool(gz["wind_changes"]), "泉州→广州六月初一：航线转弯各段风不同，季风没换，不标换风")
	_stage(1260, 8, 20, 900)
	var hk: Dictionary = voyage.plan("quanzhou", "hakata", 0)
	_expect(bool(hk["wind_changes"]), "泉州→博多八月廿日：西南风入九月转换期，标换风（静风 %d 日）" % int(hk["days"]))


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("PLAN_SAIL_DAYS cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
