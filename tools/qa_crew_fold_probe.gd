extends SceneTree
## lane w30-k3 无门禁 sweep 二：多雇员【欠饷】字面一览 + LogFold.render 折起行 / 就地展开字样断言
##（w28-k2 交主控①「另一档【欠饷】变体——多雇员俸总句的字面与『俸最高者先走』在多雇员时哪句上屏」、
##   w29-k4 交主控「LogFold 折叠行 meta / 折起一行就地展开上屏面仍净」两片点名面合一补守）。
##   C1：泉州籍 ch1 即见、无 leave_from 不带 flags 的候选人名册现读（不写姓名），窄样本取俸居首一名
##     + 最薄一名凑两人，现银摆 0 走月结——「本月工食 <工资合计> 未发。船上人心浮动。」合计数现算、逐字钉；
##     连欠三月册上俸最厚者（现读名册对出）「不告而去」逐字钉、走后册余合计转一句再连欠六月、
##     册空之后当批一则不添。摆场只填 hired 名册（不经雇市、不入伙钱、不进量功簿），
##     样本窄为了自历开 1275-05 起 7 个月落在剧情静默窗（前一则战况 1275-04、下一则 1276-01 明州降元）。
##   C2：仿作宿主自述 _log_lines 上码一字 Key【同一折句】，_log_folds 上录两则白话、按月分组各有其月，
##     直调 LogFold.render(仿作宿主, "\n", false) 直收 BBCode 串（不经屏控件）——
##     折起时「[url=fold:0]【同一折句】（点开）[/url]」逐字钉；点开后折头转「（收起）」、
##     各月行「[url=fold:0:<ym>]」引子与「（点开）」、点开当月「（收起）」、原文缩一格淡一档「　」逐字钉。
## 用法：godot --headless --path . -s res://tools/qa_crew_fold_probe.gd
## 输出末行 CREW_FOLD cases=N fails=0；N>0 时 exit 1。

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

	await _c_crew_wages()
	_c_logfold_render()
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


## 当前上屏最新下则（未折读顶批则；一折收起的照 LogFold 口径取其折内最下则；均 plain_log 后的札记原文）
func _latest() -> String:
	return str(LogFold.latest(_main)).strip_edges()


## 札记头顶上连着几则是本批通告（探针自数）
func _notice_top() -> Array:
	var logs: PackedStringArray = _main.get("_log_lines")
	var run: int = int(_main.get("_notice_run"))
	var out := []
	for i in mini(run, logs.size()):
		out.append(str(logs[i]))
	return out


## 每例起手同一摆场：身分清讫（merchant）、无债无银、新闻尽数封讫、名册空、札记四件空
func _stage() -> void:
	gs.from_dict({})
	gs.set("last_port", "quanzhou")
	gs.set("money", 0)
	gs.set("peak_money", 0)
	gs.set("debt", 0)
	gs.set("identity", "merchant")
	(crew.get("hired") as Dictionary).clear()
	crew.set("unpaid_months", 0)
	(crew.get("departed") as Dictionary).clear()
	for n in gs.pending_news():
		gs.mark_news_seen(str(n.get("id", "")))
	(_main.get("_log_lines") as PackedStringArray).clear()
	(_main.get("_log_folds") as Dictionary).clear()
	_main.set("_notice_run", 0)
	(_main.get("_notice_when") as Array).clear()


# ── C1【欠饷】多雇员：工食合计一句 + 俸最高者挨月先走 ──

func _c_crew_wages() -> void:
	print("── C1【欠饷】多人同船：工食合计当月上屏 / 俸最高者挨月不告而去")
	# 始自 1275-05 初一：全例 2+2×3+1 个月至 1275-12 初一，落在剧情静默窗（前一则战况 1275-04、
	# 下一则 1276-01 明州降元）之内，随批之外句句只断「当前上屏」（最新下屏则）欠饷原文
	cal.from_dict({"year": 1275, "month": 5, "day": 1})
	# 现港泉州、ch1 即见、无 leave_from 不带 flags 的候选人——名册现读，不写姓名；饷银摆 0 遂欠。
	# 剧情静默窗只有七个月（同 w28-k2 摆单人 4 月的先例），窄样本取俸居首一名 + 最薄一名凑两人：
	# 头名合计句、俸最高者先走、走后册余合计转一句，两档字面一个不落。
	var all_qz: Dictionary = {}
	for cand in gm.crew_data.get("candidates", []):
		var key := str(cand.get("id", ""))
		if key == "" or str(cand.get("port", "")) != "quanzhou":
			continue
		if str(cand.get("unlock", "ch1")) != "ch1" or cand.has("leave_from") or cand.has("flags"):
			continue
		all_qz[key] = {"role": str(cand.get("role", "")), "wage": int(cand.get("wage", 0)),
			"name": str(cand.get("name", "")), "level": int(cand.get("level", 0))}
	var all_keys := all_qz.keys()
	all_keys.sort_custom(func(a, b): return int((all_qz[a] as Dictionary)["wage"]) > int((all_qz[b] as Dictionary)["wage"]))
	var ids: Dictionary = {}
	ids[all_keys[0]] = all_qz[all_keys[0]]
	ids[all_keys[all_keys.size() - 1]] = all_qz[all_keys[all_keys.size() - 1]]
	gs.set("chapter", 1)
	_stage()
	var roster_keys := ids.keys()
	var wage_sum := 0
	for k in roster_keys:
		wage_sum += int((ids[k] as Dictionary)["wage"])
	_expect(roster_keys.size() == 2 and wage_sum > 0,
		"摆场：泉州 / ch1 现读候选人取 2 人、月俸合计 %d（%s）" % [
			wage_sum, ", ".join(roster_keys)])
	for k in roster_keys:
		(crew.get("hired") as Dictionary)[str((ids[k] as Dictionary)["role"])] = k

	# —— 头两个月连欠：工食合计一句两次「当前上屏」（多人同一句式，合计数现算钉子句）
	var want_unpaid := "本月工食 %d 未发。船上人心浮动。" % wage_sum
	for j in 2:
		gm.advance_days(30)
		await _settle()
		if j == 0:
			print("    当月札记通告：%s" % _latest())
		_expect(_latest() == want_unpaid and int(crew.get("unpaid_months")) == j + 1,
			"连欠 %d 月：当前上屏工食合计「%s」逐字、欠月数到 %d（实读：%s / unpaid=%d）" % [
				j + 1, want_unpaid, j + 1, _latest(), int(crew.get("unpaid_months"))])

	# —— 欠足三月，册上每人每月俸最厚者（现读名册对出）不告而去、欠月归零；
	#    人一走当月的【欠饷】罢话（连月工食也未少于上一册），再连欠两月——人人照此挨次而去，直至册空
	var order := roster_keys.duplicate()
	order.sort_custom(func(a, b): return int((ids[a] as Dictionary)["wage"]) > int((ids[b] as Dictionary)["wage"]))
	var gone: Array = []
	for i in roster_keys.size():
		await _advance_one_month()
		var want_name := str((ids[order[i]] as Dictionary)["name"])
		var want_line := "工食欠满三月，%s 不告而去。" % want_name
		_expect(_latest() == want_line,
			"欠满三月（第 %d 去）：当前上屏「%s」逐字（实读：%s）" % [
				i + 1, want_line, _latest() if _latest() != "" else "<无>"])
		gone.append(order[i])
		var hired_now: Dictionary = crew.get("hired")
		var left := 0
		for k in roster_keys:
			if not gone.has(k):
				left += 1
		_expect(hired_now.size() == left and not (hired_now.values() as Array).has(order[i])
			and int(crew.get("unpaid_months")) == 0,
			"欠满三月（第 %d 去）：册上恰剩 %d 人、欠月归零（实读册 %d / unpaid=%d）" % [
				i + 1, left, hired_now.size(), int(crew.get("unpaid_months"))])
		if i + 1 < roster_keys.size():
			var rest_sum := 0
			for k in roster_keys:
				if not gone.has(k):
					rest_sum += int((ids[k] as Dictionary)["wage"])
			var want_rest := "本月工食 %d 未发。船上人心浮动。" % rest_sum
			for _j in 2:
				await _advance_one_month()
			_expect(_latest() == want_rest and int(crew.get("unpaid_months")) == 2,
				"第 %d 去之后再连欠两月：当前上屏合计「%s」逐字、欠月到 2（实读：%s / unpaid=%d）" % [
					i + 1, want_rest, _latest() if _latest() != "" else "<无>", int(crew.get("unpaid_months"))])

	# —— 反向一笔：册空之后再走一月——工食无可欠，札记当批一则不添（照 w28-k2「顶批仍是上月三则」口径）
	var run_before: int = int(_main.get("_notice_run"))
	await _advance_one_month()
	_expect(int(_main.get("_notice_run")) == run_before
		and (crew.get("hired") as Dictionary).is_empty() and int(crew.get("unpaid_months")) == 0,
		"反向：人尽去后札记当批一则不添（走前 %d 走后 %d）、册空欠月仍 0" % [
			run_before, int(_main.get("_notice_run"))])


## 仓内历法凡月 30 日（Calendar.DAYS_PER_MONTH），由初一走到下月头一天再加满，准定跨一个月结
func _advance_one_month() -> void:
	gm.advance_days(cal.DAYS_PER_MONTH)
	await _settle()


# ── C2 LogFold.render：折起行字样 + 就地展开后 Color / 折行 ──

func _c_logfold_render() -> void:
	print("── C2 LogFold.render：折起（点开）/ 就地展开（收起）与原文缩一格淡一档字样")
	# 仿作宿主（tools/qa_crew_fold_host.gd）备 LogFold 读写的五件现价字段；探针直调 render 直收 BBCode 串，不经屏控件
	var host: Object = load("res://tools/qa_crew_fold_host.gd").new()
	host.set("_log_lines", PackedStringArray(["【同一折句】", "底句"]))
	host.set("_log_folds", {"【同一折句】": {
		"lines": ["新一则", "旧一则"],
		"groups": [
			{"ym": "1278-05", "date": "1278-05-01", "md": "五月初一", "last": "1278-05-30", "lines": ["新一则"]},
			{"ym": "1278-04", "date": "1278-04-01", "md": "四月初一", "last": "1278-04-29", "lines": ["旧一则"]},
		],
		"open": "",
	}})
	host.set("_log_fold_open", "")
	host.set("_notice_run", 0)
	host.set("_notice_when", [])
	var dim: String = UiTheme.hex(UiTheme.TEXT_DIM)

	var closed: String = LogFold.render(host, "\n", false)
	_expect(closed.contains("[url=fold:0]【同一折句】（点开）[/url]"),
		"折起：折行含「[url=fold:0]」与「（点开）」（实读：%s）" % closed.left(60))
	_expect(closed.contains("（收起）") == false and closed.contains("[color=") == false,
		"折起：不见「（收起）」、原色不着（实读：%s）" % closed.left(60))

	# 点开整折：折头转「（收起）」，两月各列一行、原文不就便铺开
	host.set("_log_fold_open", "【同一折句】")
	var opened: String = LogFold.render(host, "\n", false)
	_expect(opened.contains("[url=fold:0]【同一折句】（收起）[/url]"),
		"点开：折行转「（收起）」（实读：%s）" % opened.left(60))
	_expect(opened.contains("[color=#%s][url=fold:0:1278-05]　1278-05-01，通告 1 则（点开）[/url][/color]" % dim)
		and opened.contains("[color=#%s][url=fold:0:1278-04]　1278-04-01，通告 1 则（点开）[/url][/color]" % dim),
		"点开：两月各列一行，淡一档缩一格、引「[url=fold:0:<ym>]」、起本日间字、各月「通告 1 则（点开）」逐字")
	_expect(opened.contains("　新一则") == false and opened.contains("　旧一则") == false,
		"点开：原文不就便铺开（「　」一字未上屏）")

	# 再点最新那一月：该月转「（收起）」，当月原文缩一格淡一档，另一月仍折着
	(host.get("_log_folds") as Dictionary)["【同一折句】"]["open"] = "1278-05"
	var month_t: String = LogFold.render(host, "\n", false)
	_expect(month_t.contains("[url=fold:0:1278-05]　1278-05-01，通告 1 则（收起）[/url]"),
		"再点新月月行：「（收起）」逐字（实读前 60：%s）" % month_t.left(60))
	_expect(month_t.contains("[color=#%s]　　新一则[/color]" % dim),
		"再点新月：当月原文缩一格淡一档「　　新一则」逐字")
	_expect(month_t.contains("　　旧一则") == false
		and month_t.contains("[url=fold:0:1278-04]　1278-04-01，通告 1 则（点开）[/url]"),
		"再点新月：另一月仍折着「（点开）」，其原文一字不上屏")
	host.free()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("CREW_FOLD cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
