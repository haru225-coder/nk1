extends SceneTree
## lane w28-k2 无门禁 sweep 二：札记折叠内非月息通告（【欠饷】按月一则 /【辞船】随例 / 改元一瞥）的原文断言
##（w27-k2 交主控①补新见：折叠内非月息通告之前只有则数被钉、字句未钉——文案改不红，本片补钉）。
##   C1【欠饷】：现银摆 0、雇火长吴针走月——「本月工食 60 未发。船上人心浮动。」随月结上屏，月月逐字钉；
##     欠足三月「工食欠满三月，吴针 不告而去。」逐字钉（吴针 名姓名气之间空一字，照仓内本名）。
##     仓内口径（UiTheme.plain_log）：【欠饷】【月息】之号登札记概不上书，惟【辞船】留头着蜜色——札记原文即不带头那句。
##   C2【改元】：景炎三年四月 → 1278-05 抵祥兴——仓内遍搜无【改元】札记通告，改元的月结留墨唯历一笔：
##     本月页首印「祥兴元年」、旧号「景炎」不复上屏、札记不着一字。景改祥那一瞥据此钉死，
##     【改元】字样原系 w27-k2 摆场余墨的称呼，本片不造词。
## 用法：godot --headless --path . -s res://tools/qa_fold_notice_probe.gd
## 输出末行 FOLD_NOTICE cases=N fails=0；N>0 时 exit 1。

## w53-11（二轮）：注册表判词「本进程 SCRIPT ERROR 即红」此前空转（没装 Logger：脚本错把断言整段跳过、
## fails 不涨、headless -s 退出码守 0）——接共用件 tools/script_err_tally.gd 判红；_run_guarded 包一层兜
## 「_run 自己的代码行出错即中止、quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var crew: Node
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
	crew = root.get_node_or_null("Crew")
	if gs == null or gm == null or cal == null or crew == null:
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

	await _c_unpaid_wage()
	await _c_era_page()
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


## 札记头顶上连着几则是本批通告（探针自数）
func _notice_top() -> Array:
	var logs: PackedStringArray = _main.get("_log_lines")
	var run: int = int(_main.get("_notice_run"))
	var out := []
	for i in mini(run, logs.size()):
		out.append(str(logs[i]))
	return out


## 同会话多例必先 clear 札记四件（lines/folds/run/when），不然挂树初始札记蒙混进顶批
func _clear_notes() -> void:
	(_main.get("_log_lines") as PackedStringArray).clear()
	(_main.get("_log_folds") as Dictionary).clear()
	_main.set("_notice_run", 0)
	(_main.get("_notice_when") as Array).clear()


## 每例起手同一摆场：身分清讫（merchant）、无债无银、新闻尽数封讫、名册空、札记四件空
func _stage(port := "quanzhou") -> void:
	gs.from_dict({})
	gs.set("last_port", port)
	gs.set("money", 0)
	gs.set("peak_money", 0)
	gs.set("debt", 0)
	gs.set("identity", "merchant")
	(crew.get("hired") as Dictionary).clear()
	crew.set("unpaid_months", 0)
	(crew.get("departed") as Dictionary).clear()
	for n in gs.pending_news():
		gs.mark_news_seen(str(n.get("id", "")))
	_clear_notes()


# ── C1【欠饷】现银摆 0：按月一例原文 + 欠满三月不告而去原文 ──

func _c_unpaid_wage() -> void:
	print("── C1【欠饷】工食未发按月一例 / 欠满三月不告而去（船籍簿札记原文）")
	# 1278-04：改元前一月；所雇之人（火长吴针，泉州本港生人，ch1 即见，册上无 leave_from）
	# 月结不带史实辞船；沿途无未读新闻、无欠债、无委办——本例每月只该闻欠饷一则。
	cal.from_dict({"year": 1278, "month": 4, "day": 1})
	_stage()
	var c: Dictionary = crew.candidate_def("wu_zhen")
	_expect(not c.is_empty() and str(c.get("port", "")) == "quanzhou",
		"摆场：火长吴针在册、出身泉州（实读 port=%s）" % str(c.get("port", "<查无此人>")))
	var wage: int = int(c.get("wage", -1))
	_expect(wage == 60, "摆场：吴针月俸 60（实读 %d）" % wage)
	(crew.get("hired") as Dictionary)["huozhang"] = "wu_zhen"

	# —— 首个发饷月：1278-04 → 05（历面上正是景炎三年四月改祥兴元年五月，月历一笔由 C2 钉）
	gm.advance_days(30)
	await _settle()
	var top := _notice_top()
	print("    当月札记通告 %d 则：%s" % [top.size(), " / ".join(top)])
	# 札记原文（plain_log 去了【欠饷】号，照仓内「论文纪实」屏上样子钉）
	var unpaid1 := "本月工食 60 未发。船上人心浮动。"
	_expect(top.size() == 1, "欠饷当月：札记通告恰 1 则（实读 %d）" % top.size())
	_expect(not top.is_empty() and str(top[0]) == unpaid1,
		"欠饷当月一句原文「%s」（实读：%s）" % [unpaid1, (str(top[0]) if not top.is_empty() else "<无>")])

	# —— 第二个月：1278-05 → 06，同一句再来一则（则数随例一探针自数）
	gm.advance_days(31)
	await _settle()
	top = _notice_top()
	_expect(top.size() == 2, "连欠两月：札记通告恰 2 则（实读 %d）" % top.size())
	_expect(top.size() == 2 and str(top[0]) == unpaid1 and str(top[1]) == unpaid1,
		"连欠两月：两则皆是工食未发原文")

	# —— 第三个月：1278-06 → 07，俸最高者（船上只他一位）不告而去
	gm.advance_days(30)
	await _settle()
	top = _notice_top()
	print("    当月札记通告 %d 则：%s" % [top.size(), " / ".join(top)])
	var quit_line := "工食欠满三月，吴针 不告而去。"
	_expect(top.size() == 3 and str(top[0]) == quit_line and str(top[1]) == unpaid1 and str(top[2]) == unpaid1,
		"欠满三月则：顶则原文「%s」、其下两则仍是工食未发原文（实读 %d 则）" % [quit_line, top.size()])
	_expect(int(crew.get("unpaid_months")) == 0 and (crew.get("hired") as Dictionary).is_empty(),
		"探针自核现态：人去册空、欠月数归零（实读 unpaid=%d，hired=%d）" % [
			int(crew.get("unpaid_months")), (crew.get("hired") as Dictionary).size()])

	# —— 反向一笔：人走后再走一月，更无新墨（上月三则仍在顶、当月一则不添）
	gm.advance_days(31)
	await _settle()
	top = _notice_top()
	_expect(top.size() == 3 and str(top[0]) == quit_line,
		"反向：人走后当月无欠饷新墨，顶批仍是上月三则（实读 %d 则）" % top.size())


# ── C2【改元】改元月历：1278-05 页首印祥兴元年（景改祥无札记通告，唯历一笔）──

func _c_era_page() -> void:
	print("── C2【改元】改元月历上屏（景炎三年四月 → 祥兴元年五月）")
	cal.from_dict({"year": 1278, "month": 4, "day": 1})
	_stage()
	_main.call("update_status_panel")
	var page := _page()
	_expect(page.contains("景炎三年"),
		"改元前：页首「景炎三年」（实读前 40：%s）" % page.substr(0, 40))
	gm.advance_days(30)
	await _settle()
	_main.call("update_status_panel")
	page = _page()
	_expect(page.contains("祥兴元年"),
		"1278-05 改元月：页首印「祥兴元年」（实读前 40：%s）" % page.substr(0, 40))
	_expect(page.contains("景炎") == false,
		"改元月：页首旧年号「景炎」不再上屏（实读前 40：%s）" % page.substr(0, 40))
	# 改元的月结留墨唯历一笔：札记本例不觉「改元」字样（上例余墨照旧，文法比则数更稳——本探针同会话两例、初例的札记随例而留）
	var all_text := "\n".join(_main.get("_log_lines") as PackedStringArray)
	_expect(all_text.contains("改元") == false and all_text.contains("祥兴") == false,
		"改元月：札记不着「改元」「祥兴」字样（札记 %d 行）" % ((_main.get("_log_lines") as PackedStringArray).size()))


# ── 小件 ──────────────────────────────────────────────

func _page() -> String:
	var s := _main.get("status_label") as RichTextLabel
	return s.text if s != null else ""


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("FOLD_NOTICE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
