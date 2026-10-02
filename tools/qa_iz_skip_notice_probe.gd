extends SceneTree
## lane w23-a7（P7，IZ2-3①）：欠债跳 3 年的通告序列全量留档探针（before 材料）。
##   摆欠债 835 钱（船屋赊贷整好一料的钱），自 1277-11-01 起 GameManager.skip_years(3)，
##   按月逐则打印 GameManager.monthly_notice 全量（raw 信号，未过 LogFold 折叠、未过 LOG_KEEP 截尾），
##   再印 skip_years 摘要行，指明哪些通告流没有进摘要、且不进册页「代价」栏。
## 用法：godot --headless --path . -s res://tools/qa_iz_skip_notice_probe.gd
## 输出末行 IZ_SKIP_PROBE fails=N；N>0 时 exit 1。

var gs: Node
var gm: Node
var cal: Node
var crew: Node
var eco: Node
var fleet: Node

var _bucket: Array = []        # 本月的通告（按到达序）
var _ledger: Array = []        # [{ym, lines}]
var _last_ym := ""
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	crew = root.get_node_or_null("Crew")
	eco = root.get_node_or_null("Economy")
	fleet = root.get_node_or_null("Fleet")
	if gs == null or gm == null or cal == null or crew == null or eco == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()

	gm.monthly_notice.connect(func(t: String) -> void:
		var ym := "%04d-%02d" % [int(cal.year), int(cal.month)]
		if ym != _last_ym:
			_flush()
			_last_ym = ym
		_bucket.append(str(t)))

	print("== 摆场：欠债 835（船屋赊贷 A 料整好一份），自 1277-10-30 推 1 日至 11-01，skip_years(3)")
	gs.from_dict({})
	crew.from_dict({})
	cal.from_dict({"year": 1277, "month": 10, "day": 30})
	gs.last_port = "quanzhou"
	gs.money = 200
	gs.debt = 835
	# 跳前到期的旧闻全置已见：留档只留「跳年沿途新到期」的通告，免得 22 条补投旧闻盖过利息 / 战况正戏
	for n in gs.pending_news():
		gs.mark_news_seen(str(n.get("id", "")))
	print("   起点：%s｜现银 %d｜欠债 %d｜在船职事 %d 人｜船 %d 条" % [
		str(cal.get_date_string()), int(gs.money), int(gs.debt), (crew.hired as Dictionary).size(), fleet.ships.size()])

	gm.advance_days(1)  # 10-30 → 11-01：先睹一条当月的月初通告（skip 前先折月）
	_flush()
	print("   推至：%s（skip 起点）" % str(cal.get_date_string()))

	var lines: Array = gm.skip_years(3)
	_flush()
	var total := 0
	for e in _ledger:
		total += (e["lines"] as Array).size()

	print("")
	print("## NOTICE_DUMP 全部通告（按月分组，月内按到达序）")
	for e in _ledger:
		print("### %s（%d 则）" % [str(e["ym"]), (e["lines"] as Array).size()])
		for i in range((e["lines"] as Array).size()):
			print("%02d. %s" % [i + 1, str(e["lines"][i])])

	print("")
	print("## SKIP_SUMMARY %d 行" % lines.size())
	for l in lines:
		print(str(l))

	print("")
	print("## TALLY")
	print("SKIP_MONTHS=36 NOTICE_TOTAL=%d SUMMARY_LINES=%d FINAL_DEBT=%d FINAL_MONEY=%d FINAL_DATE=%s" % [
		total, lines.size(), int(gs.debt), int(gs.money), str(cal.get_date_string())])

	if not (cal.year == 1280 and cal.month == 11 and cal.day == 1):
		fails += 1
		print("  ✗ 跳后历法应为 1280-11-01，得 %s" % str(cal.get_date_string()))
	print("IZ_SKIP_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _flush() -> void:
	if _bucket.is_empty():
		return
	_ledger.append({"ym": _last_ym, "lines": _bucket.duplicate()})
	_bucket.clear()
