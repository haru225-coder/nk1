extends SceneTree
## lane w54-voyage：晨潮三向「顺风优先」按全程的风排——与去向牌上的风（Voyage.plan 的 wind_factor / wind_desc）同一个数。
##   HeadingDraft.deal 原先拿 Voyage.bearing()（出港第一段）的方位算风排先后；lane w53-1 已把推演与牌改成全程逐段吃风，
##   发牌还按第一段：广州七月出珠江口那段偏东南，往占城（全程顶头逆风，0.48）排成顺风（1.29），头一手就发，牌上写「顶头逆风」；
##   流求夏月往漳州 / 广州、明州夏月往温州、澎湖冬月往兴化同此——十四港 × 十二月里 21 格把全程逆风的港排进头三。
## 断言：
##   H1 全表：十四港 × 十二月（初十与三十两天，三十那天明日换月、牌上写的是明日那月的风）——每一个盐位发出的三向，
##      都等于按 plan() 的 wind_factor（牌上那个风的数）、里程、id 排出的轮转窗口（钉第一席的港照 _pinned 先占）。
##   H2 广州七月盐位 0：发出的三向是全程风最顺的三港（博多、耽罗、萨摩），不发占城；占城的牌写「顶头逆风」。
##   H3 真开海图（广州七月）：去向牌三张的风行没有一张写逆风；改前头一张就是「占城　顶头逆风」。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_heading_wind_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_HEADING_WIND cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符与 HeadingDraft 类名（编译期尚无 autoload / 类名表），一律 root.get_node / load 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const HD_PATH := "res://scripts/core/HeadingDraft.gd"

var gs: Node
var gm: Node
var cal: Node
var voyage: Node
var hd: GDScript
var ports: Array = []
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
	hd = load(HD_PATH) as GDScript
	if gs == null or gm == null or cal == null or voyage == null or hd == null:
		_expect(false, "autoload / HeadingDraft 不全")
		_report()
		return
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(8)
	# 第四章、十四港都到过：章目不钉港（_pinned 照算，钉了也照它先占）；1262 年无战况，没有封着的港
	gs.chapter = 4
	for p in gm.ports_data.get("ports", []):
		ports.append(str(p.get("id", "")))
	gs.visited_ports = ports.duplicate()
	gs.contract = {}
	_h1_full_table()
	_h2_canton_july()
	await _h3_chart_cards()
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


## 牌上那个风的数（Voyage.plan 的 wind_factor）、里程、id 排出的轮转序；钉第一席的港照 HeadingDraft._pinned 先占
func _expected_rest(origin: String) -> Array:
	var ids := PackedStringArray()
	for pid in hd.call("pool", origin):
		ids.append(str((pid as Dictionary).get("id", "")))
	var pin := str(hd.call("_pinned", ids))
	var rest: Array = []
	for pid in ids:
		if pid == pin:
			continue
		var plan: Dictionary = voyage.plan(origin, pid, 0)
		rest.append({"id": pid, "wf": float(plan["wind_factor"]), "dist": float(plan["distance"])})
	rest.sort_custom(func(a, b): return bool(hd.call("_before", a, b)))
	return [pin, rest]


func _window(pin: String, rest: Array, salt: int) -> PackedStringArray:
	var seats := PackedStringArray()
	if pin != "":
		seats.append(pin)
	if rest.is_empty():
		return seats
	var start := posmod(salt, rest.size())
	var i := 0
	while seats.size() < 3 and i < rest.size():
		var pid := str((rest[(start + i) % rest.size()] as Dictionary)["id"])
		if pid not in seats:
			seats.append(pid)
		i += 1
	return seats


func _h1_full_table() -> void:
	print("── H1 全表：每一手三向 = 按牌上的风排出的轮转窗口")
	var n := 0
	var bad := 0
	var first_bad := ""
	for origin in ports:
		for m in range(1, 13):
			for d in [10, 30]:
				cal.from_dict({"year": 1262, "month": m, "day": d})
				var ex: Array = _expected_rest(str(origin))
				var rest: Array = ex[1]
				for salt in maxi(1, rest.size()):
					n += 1
					var want := _window(str(ex[0]), rest, salt)
					var got: PackedStringArray = hd.call("deal", str(origin), salt)
					if got != want:
						bad += 1
						if first_bad == "":
							first_bad = "%s %d月%d日 盐位 %d 发 %s、牌上的风排出 %s" % [origin, m, d, salt, str(got), str(want)]
	_expect(n >= 14 * 24 * 12, "覆盖 %d 手（十四港 × 十二月 × 初十 / 三十 × 一圈盐位）" % n)
	_expect(bad == 0, "发牌与牌上的风排出的轮转对不上 %d / %d 手%s" % [bad, n, ("，头一处 " + first_bad) if bad > 0 else ""])


func _h2_canton_july() -> void:
	print("── H2 广州七月盐位 0：发全程最顺的三港，不发占城")
	cal.from_dict({"year": 1262, "month": 7, "day": 10})
	var hand: PackedStringArray = hd.call("deal", "guangzhou", 0)
	var wf := {}
	for pid in ports:
		if pid != "guangzhou":
			wf[pid] = float(voyage.plan("guangzhou", pid, 0)["wind_factor"])
	var worst_dealt := 99.0
	for pid in hand:
		worst_dealt = minf(worst_dealt, float(wf[str(pid)]))
	var best_left := 0.0
	for pid in wf.keys():
		if str(pid) not in hand:
			best_left = maxf(best_left, float(wf[pid]))
	_expect(not ("champa" in hand) and worst_dealt >= best_left - 0.00001,
		"发 %s（最逆的一张 %.2f ≥ 没发的最顺 %.2f），不发占城（全程 %.2f）" % [str(hand), worst_dealt, best_left, float(wf["champa"])])
	_expect(str(voyage.plan("guangzhou", "champa", 0)["wind_desc"]) == "顶头逆风" and float(wf["champa"]) < 0.6
		and float(voyage.wind_factor(voyage.bearing("guangzhou", "champa"))) > 1.15,
		"占城牌写「顶头逆风」（全程 %.2f），出珠江口那段却是顺风（%.2f）——改前就按这一段排进头一手" % [
			float(wf["champa"]), float(voyage.wind_factor(voyage.bearing("guangzhou", "champa")))])


func _h3_chart_cards() -> void:
	print("── H3 真开海图（广州七月）：三张去向牌的风行没有逆风")
	cal.from_dict({"year": 1262, "month": 7, "day": 10})
	gs.last_port = "guangzhou"
	gs.draft_salt = 0
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(6)
	var hand: PackedStringArray = chart.get("_hand")
	var row: HBoxContainer = chart.get("heading_row")
	var winds: Array = []
	for c in row.get_children():
		if c.is_queued_for_deletion():
			continue
		var labels: Array = c.find_children("*", "Label", true, false)
		if labels.size() > 1:
			winds.append((labels[1] as Label).text)
	var foul := winds.filter(func(t): return str(t).contains("逆风"))
	_expect(hand.size() == 3 and winds.size() == 3 and foul.is_empty(),
		"牌三张 %s，风行 %s，没有一张写逆风" % [str(hand), str(winds)])
	chart.queue_free()
	await _frames(2)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_HEADING_WIND cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
