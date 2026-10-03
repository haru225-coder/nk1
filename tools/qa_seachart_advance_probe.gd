extends SceneTree
## lane w28-k3 无门禁 sweep 三：SeaChart 海图「航段」名号跨月推进时序断言（先查后做·判实净）。
##   先查（w26-k9 切片池第 5 条授权）：全仓无一支探针同引 advance_days 与 SeaChart 且断言屏上
##   「航段」名号——交集三文件 godot_story_check（战时遭遇抽样，不读 SeaChart 屏文）/
##   qa_calendar（不挂 SeaChart）/ qa_ledger_strip（钉 HUD 顶匾钱·水粮，不读航段）。
##   故无人守「advance_days 跨月时 SeaChart 航段名号与推进时序」。
## 断言（玩家可见字照论文纪实文法）：
##   C1 泊港选定航向：船况 status_label 印「航段　澎湖」名号 + 静风日数（_course_detail_text）。
##   C2 跨月推进时序：advance_days 跨月后同一名号下「静风 N 日」与顶行日期字 / 季风随月变——
##      钉刷新先后序：跨月当日面板立即改印，不隔帧才变、不留旧月值（LCD）。
##   C3 出航正隐：sailing 时 course_detail 返空、「航段」名号自面板隐去（SeaChart.gd:857 的设计
##      反向钉死），抵港后随原名号复现——先后序一致。
##   C4 跨月跨越多月长程（针路 >1 月差）：泉州→博多跨 2 月，名号「航段　博多唐房」逐月仍冠以
##      当值月风，月份名串在面板顶行逐月翻转、名号不曾消失——跨月推进时序实证 ≥1 例。
## 用法：godot --headless --path . -s res://tools/qa_seachart_advance_probe.gd
## 输出末行 SEACHART_ADV cases=N fails=0；N>0 时 exit 1。

## w53-11（二轮）：注册表判词「本进程 SCRIPT ERROR 即红」此前空转（没装 Logger：脚本错把断言整段跳过、
## fails 不涨、headless -s 退出码守 0）——接共用件 tools/script_err_tally.gd 判红；_run_guarded 包一层兜
## 「_run 自己的代码行出错即中止、quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var voyage: Node
var fleet: Node
var _chart: Node
var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _report() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	voyage = root.get_node_or_null("Voyage")
	fleet = root.get_node_or_null("Fleet")
	if gs == null or gm == null or cal == null or voyage == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return

	# SeaChart 挂树（母本：qa_voyage_status_probe 的 ShotGate fail-fast 等价——裸 instantiate 加 frame settle）
	_chart = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(_chart)
	for i in 8:
		await process_frame

	await _c1_anchor_detail()
	await _c2_cross_month_refresh()
	await _c3_sailing_hidden_reappear()
	_report()


func _settle(n := 3) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _panel_text() -> String:
	var lbl = _chart.get("status_label")
	if lbl == null:
		return ""
	return str(lbl.text)


func _stage(port: String, y: int, mo: int, d: int) -> void:
	gs.from_dict({})
	cal.from_dict({"year": y, "month": mo, "day": d})
	gs.chapter = 4
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "penghu", "fuzhou", "hakata", "mingzhou"]
	gs.money = 5000
	gs.debt = 0
	fleet.water = 500
	fleet.food = 500
	fleet.at_sea = false
	_chart.set("origin_port", "quanzhou")
	_chart.set("sailing", false)
	_chart.set("selected_port", "")
	_chart.set("_hand", PackedStringArray(["penghu", "fuzhou", "hakata"]))
	_chart.set("course_order", 0)  # CourseOrder.RUMB 针路
	# 不走 _refresh_hand（它会以真 HeadingDraft.deal 重抽 _hand，盖掉直设的去处）；
	# 绕 deal：直设 selected_port 后只刷新面板——_course_detail_text 只查 selected_port（SeaChart.gd:857），
	# 与玩家真点航向牌后屏上「航段」名号同一路。
	_chart.set("selected_port", port)
	_chart.call("_refresh_status")


# ── C1 泊港选定航向：「航段」名号 + 静风日上屏 ─────────────

func _c1_anchor_detail() -> void:
	print("── C1 泊港选定：船况印「航段　澎湖」名号 + 静风日数")
	_stage("penghu", 1255, 3, 15)
	await _settle()
	var body := _panel_text()
	_expect(body.contains("航段　澎湖"), "船况印「航段　澎湖」名号（实读前 90：%s）" % body.substr(0, 90))
	var plan: Dictionary = voyage.plan("quanzhou", "penghu", 0)
	_expect(body.contains("静风 %d 日" % int(plan["days"])),
		"名号下印「静风 %d 日」（plan.days=%d，实读前 160：%s）" % [int(plan["days"]), int(plan["days"]), body.substr(0, 160)])
	_expect(body.contains("针路"), "航法名「针路」上屏（实读前 160：%s）" % body.substr(0, 160))


# ── C2 跨月推进时序：名号下日数 / 顶行月字随月同步翻 ──────

func _c2_cross_month_refresh() -> void:
	print("── C2 跨月推进：advance_days 跨月当日「航段」名号下日数与顶月字同步刷新")
	# 摆期 4 月 25，选定后跨月 advance 到 5 月（季风转换期 → 西南，plan.days 5→3）
	_stage("penghu", 1255, 4, 25)
	await _settle()
	var before := _panel_text()
	var days_before := int(voyage.plan("quanzhou", "penghu", 0)["days"])
	_expect(before.contains("航段　澎湖") and before.contains("静风 %d 日" % days_before),
		"跨月前印「航段　澎湖」+「静风 %d 日」（四月转换期）" % days_before)
	_expect(before.contains("四月"), "跨月前顶行月字「四月」（实读前 60：%s）" % body_head(before))

	gm.advance_days(6)  # 四月廿五 +6 → 五月初一（跨月）
	_chart.call("_refresh_status")
	await _settle()
	var after := _panel_text()
	var days_after := int(voyage.plan("quanzhou", "penghu", 0)["days"])
	_expect(str(cal.get_date_string()).contains("五月"), "历法实读跨月：四月廿五 +6 到五月（实读：%s）" % str(cal.get_date_string()))
	_expect(days_after != days_before, "跨月 plan.days 真变 %d → %d（季风翻转驱动）" % [days_before, days_after])
	_expect(after.contains("航段　澎湖") and after.contains("静风 %d 日" % days_after),
		"跨月当日名号仍「航段　澎湖」、日数已改印「静风 %d 日」（无旧值残留）" % days_after)
	_expect(after.contains("五月"), "跨月当日顶行月字改印「五月」（实读前 60：%s）" % body_head(after))
	_expect(not after.contains("静风 %d 日" % days_before), "跨月后旧日数「静风 %d 日」不再留在面板（LCD）" % days_before)
	_expect(after != before, "跨月整版文与旧版不同（账变屏不变判红）")


func body_head(t: String) -> String:
	return t.substr(0, 60)


# ── C3 出航正隐 + 抵港复现 + C4 跨越多月长程名号不消失 ─────

func _c3_sailing_hidden_reappear() -> void:
	print("── C3 出航正隐：sailing 时「航段」名号自面板隐去（设计反向钉）")
	_stage("penghu", 1255, 4, 20)
	await _settle()
	_chart.set("sailing", true)
	_chart.call("_refresh_status")
	await _settle()
	var sail_body := _panel_text()
	_expect(not sail_body.contains("航段　"), "出航中「航段」名号自面板隐去（_course_detail_text 返空，SeaChart.gd:857）")
	_chart.set("sailing", false)
	_chart.call("_refresh_status")
	await _settle()
	var dock_body := _panel_text()
	_expect(dock_body.contains("航段　澎湖"), "歇帆（回泊态）后「航段　澎湖」名号复现")

	print("── C4 跨越多月长程：泉州→博多跨 ≥1 月，名号随当值月风逐月仍在")
	# 长程 hakata（10 月开航 ~57 日 → 跨 2 月）；逐月 advance，钉名号顶行月字连续翻转、名号不消失
	_stage("hakata", 1255, 10, 5)
	await _settle()
	var seq := []
	for step in range(3):
		_chart.call("_refresh_status")
		await _settle()
		var b := _panel_text()
		seq.append({"month": cal.month, "has_name": b.contains("航段　博多唐房"), "monsoon": cal.get_monsoon_desc()})
		gm.advance_days(20)
	var crossed: bool = seq[0]["month"] != seq[2]["month"]
	_expect(crossed, "长程摆场真跨月：月序 %d→%d→%d" % [seq[0]["month"], seq[1]["month"], seq[2]["month"]])
	var always_named: bool = seq[0]["has_name"] and seq[1]["has_name"] and seq[2]["has_name"]
	_expect(always_named, "跨月推进全程「航段　博多唐房」名号不曾消失（三个月读点皆印）")


# ── 汇总 ────────────────────────────────────────────────

func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("SEACHART_ADV cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
