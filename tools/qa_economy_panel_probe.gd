extends SceneTree
## lane w27-k2 无门禁 sweep 二：名声栏与欠债跳年摘要句的文本断言（w26-k9 交主控 2/3，合一）。
##   摆场名望爬过跳级阈值，名声栏印新级别名；欠债走跳年册页（ChapterSheet 代价截 + 札记折叠原文），
##   息钱 / 现欠 / 年月名随玩家可见处一起印出——文案变即红。
## 用法：godot --headless --path . -s res://tools/qa_economy_panel_probe.gd
## 输出末行 ECON_PANEL_PROBE cases=N fails=0；N>0 时 exit 1。

## w53-11（二轮）：注册表判词「本进程 SCRIPT ERROR 即红」此前空转（没装 Logger：脚本错把断言整段跳过、
## fails 不涨、headless -s 退出码守 0）——接共用件 tools/script_err_tally.gd 判红；_run_guarded 包一层兜
## 「_run 自己的代码行出错即中止、quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
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
	if gs == null or gm == null or cal == null:
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

	await _c_fame_title()
	await _c_debt_year_sheet()
	_report()


func _settle(n := 5) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


# ── C1 名声栏：级别名随晋升上屏 ──────────────────────

func _c_fame_title() -> void:
	print("── C1 名声 / 海商信用 跳级上屏")
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	gs.money = 2000
	gs.peak_money = 2000
	gs.debt = 0
	gs.fame = 9
	_main.load_scene("xinghua")
	await _settle()
	_repaint()
	var page: String = _page()
	_expect(page.contains("名声　9　籍外散商"),
		"名望 9：名声栏名「名声　9　籍外散商」（实读：%s）" % _snippet(page, "名声"))
	_expect(page.contains("在册舶牙") == false,
		"名望 9：名声栏尚未出新级别「在册舶牙」")
	var add_res: Dictionary = gs.add_fame(2)
	_repaint()
	page = _page()
	_expect(int(add_res.get("fame", -1)) == 11,
		"add_fame(+2) 后实存 fame=11（探针自核现态）")
	_expect(page.contains("名声　11　在册舶牙"),
		"晋升后名声栏印「名声　11　在册舶牙」（实读：%s）" % _snippet(page, "名声"))
	# 反向：不加名望，白跑 advance_days 一年，称号不变、新级别名不上屏
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	gs.money = 2000
	gs.fame = 9
	gm.advance_days(365)
	_repaint()
	page = _page()
	_expect(page.contains("名声　9　籍外散商"),
		"白走一年后名声栏仍「名声　9　籍外散商」（实读：%s）" % _snippet(page, "名声"))
	_expect(page.contains("在册舶牙") == false,
		"反向：未晋升级别名「在册舶牙」不上屏——仅跑时间不得造真")


# ── C2 欠债跳年册页：息钱 / 现欠 / 年月名一并见屏 ──────

func _c_debt_year_sheet() -> void:
	print("── C2 欠债跳 2 年：册页代价截 + 札记折叠原文")
	gs.from_dict({})
	cal.from_dict({"year": 1277, "month": 10, "day": 30})
	gs.last_port = "quanzhou"
	gs.money = 6500
	gs.peak_money = 6500
	gs.debt = 1000
	gs.visited_ports = ["xinghua", "quanzhou", "zhangzhou", "zhanqiao", "ryukyu"]
	for n in gs.pending_news():
		gs.mark_news_seen(str(n.get("id", "")))
	gs.merchant_credit = 12
	gs.money = 0
	# 现银归零：沿途不再有钱发饷——每月一例「本月工食未发」计入折叠（摆场负债照旧计息）
	# 同会话两例：挂树继承与上例留下来的札记清空，折叠行的顶行指向才由本例自证
	(_main.get("_log_lines") as PackedStringArray).clear()
	(_main.get("_log_folds") as Dictionary).clear()
	_main.set("_notice_run", 0)
	(_main.get("_notice_when") as Array).clear()

	# 探针自起对照账：3% 月复利，24 期（不引 GameState.DEBT_MONTHLY_RATE，防共同变量同错）
	# 跳年沿途通告的「月息之外」一则探针自己从前文点：摆场已清雇佣亦无在职，沿途只该闻祥兴改元一声 +
	# 工食未发按月一次。此数若涨（杂息变 / 雇佣还原），折叠头则数跟着改——不看它一眼的全包含法镇不住
	var notice_extra := 5
	var debt0 := int(gs.debt)
	var expect_last_interest := 0
	var sim := debt0
	for i in 24:
		expect_last_interest = int(ceil(sim * 0.03))
		sim += expect_last_interest
	var expect_debt := sim

	var res: Dictionary = gs.try_advance_chapter()
	var chapter_script: GDScript = load("res://scripts/ui/ChapterSheet.gd")
	chapter_script.call("show_dialog", _main, res)
	await _settle()

	# 册页面（代价截）
	var sheet_text := ""
	var sheet_label := _find_label(_main, func(t: String) -> bool: return t.contains("代价"))
	if sheet_label != null:
		sheet_text = str(sheet_label.text)
	_expect(sheet_text.contains("【两年后・祥兴二年　十月三十】"),
		"册页题头「【两年后・祥兴二年　十月三十】」（实读头部：%s）" % sheet_text.substr(0, 30))
	_expect(sheet_text.contains("——自景炎二年　十月三十至于祥兴二年　十月三十。"),
		"册页末句年月起讫「——自…至于…。」（实读尾段：%s）" % sheet_text.substr(maxi(0, sheet_text.length() - 60), 60))

	# 船籍簿札记：折叠行 + 展开后月息原文
	var logs: PackedStringArray = _main.get("_log_lines")
	var fold_idx := -1
	for i in logs.size():
		if str(logs[i]).contains("通告一连"):
			fold_idx = i
			break
	_expect(fold_idx == 0,
		"札记顶行是跳年通告折叠（logs[0]=%s）" % str(logs[0] if not logs.is_empty() else "<empty>"))
	var fold_head := str(logs[0])
	_expect(fold_head.contains("自景炎二年　冬月初一至于祥兴二年　十月初一"),
		"折叠头记起讫年月名「自景炎二年　冬月初一至于祥兴二年　十月初一」（实读：%s）" % fold_head)
	_expect(fold_head.contains("通告一连 %d 则，凡 24 月" % (24 + notice_extra)),
		"折叠头记则数（24 则【月息】+ 探针自数余墨 %d 则）与凡月数 24（实读：%s）" % [notice_extra, fold_head])
	_expect(fold_head.contains(str(expect_last_interest)) == false,
		"反向：折叠头不带末月息文 %d（防把札记原文凑进同一行）" % expect_last_interest)

	# 折叠原件：凡 24 月即 24 则【月息】 + 一则另有余墨（景炎三年四月的【改元】祥兴）。
	var folds: Dictionary = _main.get("_log_folds")
	var fold: Dictionary = folds.get(fold_head, {})
	var fold_lines := (fold.get("lines") as Array) if not fold.is_empty() else []
	var interest_seen := 0
	for l in fold_lines:
		var t := str(l)
		if t.contains("蕃商结息"):
			interest_seen += 1
	_expect(interest_seen == 24,
		"折叠内【月息】则数 = 凡月数 24（实读 %d）" % interest_seen)
	var last_line := ""
	for l in fold_lines:
		var t := str(l)
		if t.contains("蕃商结息"):
			last_line = t
			break
	_expect(last_line.contains("蕃商结息 %d 钱，现欠 %d。" % [expect_last_interest, expect_debt]),
		"末月息句「蕃商结息 %d 钱，现欠 %d。」（实读末则：%s）" % [expect_last_interest, expect_debt, last_line])

	# 反向：无欠债的跳年，册页与札记俱不见「蕃商结息」与「现欠」字样
	gs.from_dict({})
	cal.from_dict({"year": 1277, "month": 10, "day": 30})
	gs.last_port = "quanzhou"
	gs.money = 6500
	gs.peak_money = 6500
	gs.debt = 0
	gs.visited_ports = ["xinghua", "quanzhou", "zhangzhou", "zhanqiao", "ryukyu"]
	for n in gs.pending_news():
		gs.mark_news_seen(str(n.get("id", "")))
	(_main.get("_log_lines") as PackedStringArray).clear()
	(_main.get("_log_folds") as Dictionary).clear()
	_main.set("_notice_run", 0)
	(_main.get("_notice_when") as Array).clear()
	res = gs.try_advance_chapter()
	chapter_script.call("show_dialog", _main, res)
	await _settle()
	sheet_label = _find_label(_main, func(t: String) -> bool: return t.contains("代价"))
	if sheet_label != null:
		sheet_text = str(sheet_label.text)
	_expect(sheet_text.contains("【两年后・祥兴二年　十月三十】"),
		"无债跳年：册页题头同款「【两年后・…】」（实读头部：%s）" % sheet_text.substr(0, 30))
	_expect(sheet_text.contains("蕃商结息") == false and sheet_text.contains("现欠") == false,
		"反向：无债跳年册页不见「蕃商结息」「现欠」（实读：%s）" % _snippet(sheet_text, "代价"))
	logs = _main.get("_log_lines")
	# 反向的最后一眼：遍及本例札记全本，薄薄 7 行里也不该有息钱字样（雇佣是开局那一档积下的随本例遗产，一并清扫）
	var neg_hit := "蕃商结息" in "\n".join(logs) or "现欠" in "\n".join(logs)
	_expect(neg_hit == false, "反向：无债跳年札记全本不见「蕃商结息」「现欠」（札记 %d 行）" % logs.size())


# ── 小件 ──────────────────────────────────────────────

func _page() -> String:
	var s := _main.get("status_label") as RichTextLabel
	return s.text if s != null else ""


func _repaint() -> void:
	if _main.has_method("update_status_panel"):
		_main.call("update_status_panel")


func _snippet(t: String, anchor: String, span := 46) -> String:
	var i := t.find(anchor)
	if i < 0:
		return t.substr(0, span)
	return t.substr(i, span)


func _find_label(n: Node, pred: Callable) -> Label:
	if n is Label:
		var t := str((n as Label).text)
		if pred.call(t):
			return n as Label
	for c in n.get_children():
		var hit := _find_label(c, pred)
		if hit != null:
			return hit
	return null


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("ECON_PANEL_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
