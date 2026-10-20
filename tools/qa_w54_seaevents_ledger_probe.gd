extends SceneTree
## lane w54-seaevents：海上遇事的札记与实扣对得上——札记说搬走多少，舱里就少多少；一件没少就不说搬。
##   T 献上买路财拿不出钱（SeaChart._on_pay_pirates）：原先一律写「他们自己动手搬走了三成货。」——舱里空着一件没搬也这么写；
##     实扣走 Fleet.lose_cargo_ratio(0.3)，逐船逐样向上取整，一件的货整件被搬、两件的搬一件，札记仍说三成。
## 断言（直调钮回调，札记取最新一条，按札记里说的规矩推算该搬几件，与舱里实少的件数逐样比）：
##   T1 钱够：递过去的钱数 = 现银实扣，舱货不动。
##   T2 拿不出钱、舱里空：一件没搬，札记不说「搬」；现银不动。
##   T3 拿不出钱、整批大货：札记写三成，件数对得上。
##   T4 拿不出钱、一件两件的零头货：札记照它说的规矩（三成；说了零头算一件就向上取整，没说就四舍五入）推出的件数 = 实少件数。
##   T5 两船各装一件同样货：札记说逐船就逐船推，没说就按全队合计推，推出的件数 = 实少件数。
##   F 扬帆逃走没甩脱（SeaChart._on_flee_pirates，海寇与元军哨船两面共用）：原先只写「未能甩脱。被追上跳帮，货舱被夺。」加被抢清单——
##     旗舰挨的那一下（damage_fleet 30 × 甲档减伤）一字不提，舱里空着一件没抢也说货舱被夺。
##   F1 有货：札记写的被抢件数 = 实少件数，「船体受损 N」= 旗舰实扣（30）。F2 舱空：不说货舱被夺，照写船体受损。
##   F3 甲满三档：实扣 24 写 24。F4 旗舰只剩 12：扣到 0 为止，写 12。F5 甩脱了：不扣船体、不写受损，绕路多一程。
##   B 花钱的钮写出要花多少（SeaChart._show_event）：遇海寇「献上买路财」、征船「塞钱免征」原先只写四个字，同面板「散钱 N」
##     「交出一条船（名声 +6）」「载人同行（水粮 −2 成）」都写了代价。B1 / B3 钱够：钮上写的钱数 = 真按下去现银实扣；
##     B2 / B4 钱不够：钮上写明「要 N 钱，囊中不足」，按下去现银不扣（买路财由他们搬货，免征改走溜）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_ledger_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_LEDGER cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TOLL_RATIO := 0.3

var _gs: Node
var _cal: Node
var _fleet: Node
var _gm: Node
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
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	_gm = root.get_node_or_null("GameManager")
	if _gs == null or _cal == null or _fleet == null or _gm == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1260, "month": 6, "day": 5})
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(4)
	# 停在海上半途：回调末尾的 _after_combat 见没在航行、余程未尽就不往下走，札记最上一条就是这一句
	chart.set("sailing", false)
	chart.set("remaining_li", 500.0)
	print("── T 献上买路财")
	_toll_paid(chart)
	_toll_short(chart, "T2 舱里空", 1, [])
	_toll_short(chart, "T3 整批大货", 1, [[0, "qingbai_porcelain", 10]])
	_toll_short(chart, "T4 零头货", 1, [[0, "ivory", 1], [0, "pepper", 2]])
	_toll_short(chart, "T5 两船各一件", 2, [[0, "coral", 1], [1, "coral", 1]])
	print("── F 扬帆逃走")
	_flee(chart, "F1 有货", 1, [[0, "qingbai_porcelain", 10]], 1, -1.0, false)
	_flee(chart, "F2 舱里空", 1, [], 1, -1.0, false)
	_flee(chart, "F3 甲满三档", 1, [[0, "pepper", 3]], 3, -1.0, false)
	_flee(chart, "F4 旗舰只剩 12", 2, [[1, "tea", 5]], 1, 12.0, false)
	_flee(chart, "F5 甩脱了", 1, [[0, "qingbai_porcelain", 10]], 1, -1.0, true)
	print("── B 花钱的钮")
	var voy: Node = root.get_node("Voyage")
	_cost_button(chart, "B1 献上买路财，钱够", voy.call("pirate_sighting"), "献上买路财", 1000)
	_cost_button(chart, "B2 献上买路财，钱不够", voy.call("pirate_sighting"), "献上买路财", 50)
	_cost_button(chart, "B3 塞钱免征，钱够", voy.call("_requisition_event"), "塞钱免征", 2000)
	_cost_button(chart, "B4 塞钱免征，钱不够", voy.call("_requisition_event"), "塞钱免征", 60)
	chart.queue_free()
	await _frames(2)
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


func _latest(chart: Node) -> String:
	var lines: PackedStringArray = chart.get("_log_lines")
	return str(lines[0]) if lines.size() > 0 else ""


## 船队：ship_count 艘客舟，水粮各 20；hold = [[船序, 货, 件数], …]
func _fleet_with(ship_count: int, hold: Array) -> void:
	_fleet.set("ships", [])
	for i in ship_count:
		_fleet.call("add_ship", "keel_boat", "探针船%d" % i)
	_fleet.set("water", 20)
	_fleet.set("food", 20)
	_fleet.set("morale", 70)
	for row in hold:
		_fleet.call("add_cargo", str(row[1]), int(row[2]), 40.0, int(row[0]))


## {货: 全队件数}
func _cargo_now() -> Dictionary:
	var out := {}
	var agg: Dictionary = _fleet.get("cargo")
	for gid in agg.keys():
		out[str(gid)] = int((agg[gid] as Dictionary).get("qty", 0))
	return out


func _toll_paid(chart: Node) -> void:
	_fleet_with(1, [[0, "qingbai_porcelain", 10]])
	_gs.set("money", 1000)
	chart.call("_on_pay_pirates")
	var line := _latest(chart)
	var re := RegEx.new()
	re.compile("递过去 (\\d+) 钱买路")
	var m := re.search(line)
	var spent := 1000 - int(_gs.get("money"))
	_expect(m != null and int(m.get_string(1)) == spent and spent > 0 and int(_cargo_now().get("qingbai_porcelain", 0)) == 10,
		"T1 钱够：札记「%s」，现银实扣 %d，舱货照旧" % [line, spent])


## 拿不出买路钱（现银 50 < 地板 100）：按札记说的规矩推该搬几件，与舱里实少的逐样比
func _toll_short(chart: Node, tag: String, ship_count: int, hold: Array) -> void:
	_fleet_with(ship_count, hold)
	_gs.set("money", 50)
	var before := _cargo_now()
	chart.call("_on_pay_pirates")
	var line := _latest(chart)
	var after := _cargo_now()
	var taken := {}
	for gid in before.keys():
		var d := int(before[gid]) - int(after.get(gid, 0))
		if d > 0:
			taken[gid] = d
	var money_ok := int(_gs.get("money")) == 50
	if before.is_empty():
		_expect(taken.is_empty() and not line.contains("搬走") and line.contains("拿不出买路钱") and money_ok,
			"%s：一件没搬，札记不说搬走——「%s」" % [tag, line])
		return
	var said_ratio := line.contains("三成")
	var round_up := line.contains("零头也算一件")
	var per_ship := line.contains("逐船")
	# 札记说的规矩推出来的件数：逐船就按每船那一份推，否则按全队合计推
	var want := {}
	if per_ship:
		for row in hold:
			var gid := str(row[1])
			want[gid] = int(want.get(gid, 0)) + _rule(int(row[2]), round_up)
	else:
		for gid in before.keys():
			want[gid] = _rule(int(before[gid]), round_up)
	var same := said_ratio and money_ok
	for gid in before.keys():
		if int(want.get(gid, 0)) != int(taken.get(gid, 0)):
			same = false
	var listed := true
	for gid in taken.keys():
		if not line.contains("%s %d" % [str(_gm.call("get_good_name", gid)), int(taken[gid])]):
			listed = false
	_expect(same and listed, "%s：札记「%s」照它说的推 %s，实少 %s" % [tag, line, str(want), str(taken)])


func _rule(qty: int, round_up: bool) -> int:
	var raw := float(qty) * TOLL_RATIO
	return mini(qty, int(ceil(raw)) if round_up else int(round(raw)))


## 定种子掷「逃走」那一下：want_ok 要甩脱就挑 randf() < 成功率的种子，反之挑掷不中的
func _flee_seed(want_ok: bool) -> int:
	var chance := clampf(float(_fleet.call("fleet_speed")) / 220.0, 0.25, 0.9)
	for k in range(1, 5000):
		seed(k)
		if (randf() < chance) == want_ok:
			return k
	return 1


## armor = 旗舰甲档；flag_hull >= 0 时把旗舰耐久先压到这个数
func _flee(chart: Node, tag: String, ship_count: int, hold: Array, armor: int, flag_hull: float, want_ok: bool) -> void:
	_fleet_with(ship_count, hold)
	var ships: Array = _fleet.get("ships")
	(ships[0] as Dictionary)["armor_level"] = armor
	if flag_hull >= 0.0:
		(ships[0] as Dictionary)["durability"] = flag_hull
	var hull_was := float((ships[0] as Dictionary).get("durability", 0.0))
	var left_was := float(chart.get("remaining_li"))
	var before := _cargo_now()
	seed(_flee_seed(want_ok))
	chart.call("_on_flee_pirates")
	var line := _latest(chart)
	var cut := int(hull_was - float((_fleet.get("ships")[0] as Dictionary).get("durability", 0.0)))
	var after := _cargo_now()
	var detour := float(chart.get("remaining_li")) - left_was
	chart.set("remaining_li", 500.0)
	if want_ok:
		_expect(cut == 0 and not line.contains("受损") and before == after and detour > 0.0 and line.contains("甩在后面"),
			"%s：札记「%s」，船体不扣、舱货不动，绕路多 %d 里" % [tag, line, int(detour)])
		return
	var re := RegEx.new()
	re.compile("船体受损 (\\d+)")
	var m := re.search(line)
	var said := int(m.get_string(1)) if m != null else 0
	var cargo_ok := true
	for gid in before.keys():
		var d := int(before[gid]) - int(after.get(gid, 0))
		var mark := "%s %d" % [str(_gm.call("get_good_name", gid)), d]
		if d <= 0 or not line.contains(mark):
			cargo_ok = false
	if before.is_empty():
		cargo_ok = not line.contains("货舱被夺") and after.is_empty()
	_expect(cut > 0 and said == cut and cargo_ok and line.contains("未能甩脱"),
		"%s：札记「%s」写船体受损 %d，旗舰实扣 %d" % [tag, line, said, cut])


## 挂一面遭遇，找到 what 那颗钮，读钮上写的钱数，真按下去，看现银实扣
func _cost_button(chart: Node, tag: String, ev: Dictionary, what: String, money: int) -> void:
	_fleet_with(1, [[0, "qingbai_porcelain", 10]])
	_gs.set("money", money)
	chart.call("_show_event", ev)
	var btn: Button = null
	for c in (chart.get("event_actions") as Node).get_children():
		if c is Button and not c.is_queued_for_deletion() and str((c as Button).text).begins_with(what):
			btn = c
	if btn == null:
		_expect(false, "%s：面板上找不到「%s」那颗钮" % [tag, what])
		return
	var label := str(btn.text)
	var re := RegEx.new()
	re.compile("（(?:要 )?(\\d+) 钱")
	var m := re.search(label)
	var said := int(m.get_string(1)) if m != null else -1
	var short := label.contains("囊中不足")
	# 免征拿不出钱改走「趁夜溜走」：种子挑征船那条成功率（航速 / 240，比海寇那条严）也掷得中的，溜成了不罚钱
	var chance := clampf(float(_fleet.call("fleet_speed")) / 240.0, 0.2, 0.85)
	var k := 1
	while k < 5000:
		seed(k)
		if randf() < chance:
			break
		k += 1
	seed(k)
	btn.pressed.emit()
	var spent := money - int(_gs.get("money"))
	chart.set("remaining_li", 500.0)
	if money >= said and said > 0:
		_expect(not short and spent == said, "%s：钮「%s」，按下去现银实扣 %d" % [tag, label, spent])
	else:
		_expect(short and said > 0 and spent == 0, "%s：钮「%s」，按下去现银实扣 %d" % [tag, label, spent])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_LEDGER cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
