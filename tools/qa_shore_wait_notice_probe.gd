extends SceneTree
## lane w23-a7（P7，V0928-3① 两个前置缺陷复现 + D2 涵江卡窗口）。
##   一、「候一日」盖住月初通告（`scripts/Main.gd:2908` 自陈「候日句先写」）：
##      兴化 1277-10-31 岸上按 ONE「再候一日」跨进 11 月（战况转 fallen 的月份），
##      印「压缩前」原始流（候日句 → 若干月初通告）与压缩后 LOG_KEEP=8 的记事栏快照
##      （fold 头 + 点开全文）对照：真城里人这一手看到的序列。
##   二、旅店「候 N 日」一钮跨窗口：兴化 1277-10-19 进旅店，读钮面，直接 _on_rest(13)，
##      10-19 → 11-02 一钮跨过涵江卡催促窗（10-20 起，全窗不足一屏）；
##      补对照 10-20 按「歇 1 日」→ 10-21 仍在窗内。
##   三、涵江卡窗口扫描：1277-10-01 → 12-31 逐日在兴化、海口喊 _special_cards()，
##      按月折日（30→1）逐日印卡「在在兴化」「到了海口」的真上卡带与副题——候一日跨月与跨窗钮各自损失多少天窗口。
## 用法：godot --headless --path . -s res://tools/qa_shore_wait_notice_probe.gd
## 输出末行 SHORE_PROBE fails=N；N>0 时 exit 1。

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var _arrivals: Array = []   # 主信号留底（未过 LogFold / LOG_KEEP）
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	eco = root.get_node_or_null("Economy")
	if gs == null or gm == null or cal == null or eco == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Main.tscn missing")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		print("  ✗ Main.gd 未载入")
		print("SHORE_PROBE fails=1")
		quit(1)
		return
	gm.monthly_notice.connect(func(t: String) -> void: _arrivals.append(str(t)))

	await _d1_shore_wait()
	await _d2_inn_cross()
	await _card_window_scan()

	print("SHORE_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _reset_day(port_id: String, y: int, mo: int, d: int, money := 20000, debt := 500, walk := true) -> void:
	gs.from_dict({})
	cal.from_dict({"year": y, "month": mo, "day": 1})
	_arrivals.clear()
	if walk and d > 1:
		gm.advance_days(d - 1)  # 把 1..d 真走一遍：LedgerPage 城防记录之类按真实历法记档，空投 d=31 会破框
		_arrivals.clear()
	elif d > 1:
		cal.from_dict({"year": y, "month": mo, "day": d})  # 空投：LedgerPage 干净局读 save_date 不炸（day≤30 合法）
	gs.last_port = port_id
	gs.money = money
	gs.debt = debt
	gs.record_discovery("nameless_shelter_bay")
	_arrivals.clear()


# ── 一、候一日盖住月初通告 ──────────────────────────────

func _d1_shore_wait() -> void:
	print("== D1 候一日跨月（兴化 1277-10-30 按「再候一日」→ 11-01；欠债 500；10 月摆着 besieged，跨月 fallen）")
	# 先实测一句对照：月内月末按，只来一推日、不来月度账，栏顶应该还是候日句
	# 锚本会话的守城记录清空（from_dict 会带默认 siege，连按场景的暗病；真玩家新局 / 读档不遇）
	_reset_day("xinghua", 1277, 10, 29, 20000, 500, false)
	gs.siege = {}
	_main.load_scene("xinghua")
	await _settle(8)
	_main._on_shore_wait()
	var mid_logs: PackedStringArray = _main.get("_log_lines")
	print("D1_CTRL 月内（10-29 按）栏顶：%s｜行数 %d｜当日 %s" % [
		str(mid_logs[0]) if mid_logs.size() > 0 else "(空)", mid_logs.size(), str(cal.get_date_string())])
	# 摆场 10-30：LedgerPage 之类按合法历法排版、不走日子本身（空投 31 会破框、又不发生跨月结算）；
	# 跨月的纯月度结算（月息 + fallen 战况）全部留给玩家那一按。
	_reset_day("xinghua", 1277, 10, 30, 20000, 500, false)
	gs.siege = {}
	print("   摆场后战况：%s" % str(eco.war_status("xinghua")))
	_main.load_scene("xinghua")
	await _settle(10)
	var mark: int = (_main.get("_log_lines") as PackedStringArray).size()
	_arrivals.clear()
	_main._on_shore_wait()
	print("   当日：%s｜战况 %s" % [str(cal.get_date_string()), str(eco.war_status("xinghua"))])
	# 观测立刻做完（不等帧）：过场演出按开场的历法预排版，等帧会让破框日先泄进排版
	var fresh: Array = (_main.get("_log_lines") as PackedStringArray).slice(0, int((_main.get("_log_lines") as PackedStringArray).size()) - mark)
	print("RAW_SEQUENCE %d 句（压缩前，新→旧）：" % fresh.size())
	for l in fresh:
		print("RAW| %s" % str(l))
	print("RAW_NOTICES 同刻新到通告 %d 则（主信号留底，先进折叠在后台）：" % _arrivals.size())
	for t in _arrivals:
		print("RAW_NOTICE| %s" % str(t))
	print("LOG_SNAPSHOT 记事栏 %d 行（LOG_KEEP=%d，新→旧）：" % [int((_main.get("_log_lines") as PackedStringArray).size()), int(_main.LOG_KEEP)])
	var logs: PackedStringArray = _main.get("_log_lines")
	for i in logs.size():
		print("LOG%d| %s" % [i, str(logs[i])])
	var folds: Dictionary = _main.get("_log_folds")
	for key in folds.keys():
		var f: Dictionary = folds[key]
		print("FOLD_OPEN| %s｜内 %d 则｜%d 月" % [str(key), (f["lines"] as Array).size(), (f["groups"] as Array).size()])
		for sub in f["lines"]:
			print("FOLD_LINE| %s" % str(sub))
	var wait_i := -1
	for i in logs.size():
		if str(logs[i]).contains("候了一日"):
			wait_i = i
	if wait_i > 0 and not str(logs[0]).contains("候了一日"):
		print("D1_OBS 候日句在 LOG%d：压它的 %d 行（折成一行者原文在折叠里，点开才见；这行之前的行已全是通告）" % [wait_i, wait_i])
	elif wait_i == 0:
		print("D1_OBS 候日句仍在栏顶（通告数未过折叠门槛 %d）" % int(LogFold.FOLD_AT))
	elif wait_i < 0:
		fails += 1
		print("  ✗ 记事栏里找不到候日句（被截尾顶出 LOG_KEEP）")
	# 观测完复位：空白局 from_dict({}) 扫不净会话态（城防记录仍然「开着」会把守城开场排在 load_scene 里、
	# 按复位后的历法过一遍 get_date_string 弄脏终端），索性办终局浮名横在卡前一并压住，人挪去泉州落地
	gs.set_flag("ending_root_sea")
	cal.from_dict({"year": 1277, "month": 10, "day": 19})
	_main.load_scene("quanzhou")
	await _settle(8)


# ── 二、旅店一钮跨窗 ────────────────────────────────────

func _d2_inn_chip(port_id: String, y: int, mo: int, d: int, label_re: RegEx, cross_from: int, cross_to: int) -> Array:
	_reset_day(port_id, y, mo, d)
	_main.load_scene(port_id + "_inn")
	await _settle(6)
	var chips: Array = []
	var rows: Array = _find_all(_main, func(n: Node) -> bool: return n is HFlowContainer)
	for r in rows:
		for b in (r as Node).get_children():
			if b is Button and label_re.search(str((b as Button).text)) != null:
				chips.append(b)
	var texts: Array = []
	for b in chips:
		texts.append(str((b as Button).text))
	var cross: Button = null
	var rebind := 0
	for b in chips:
		if cross_from > 1 and str((b as Button).text).begins_with("候 "):
			cross = b
			rebind = cross_from
	var want := "歇 1 日" if cross_from == 1 else "候 %d 日" % cross_from
	if chips.is_empty():
		fails += 1
		print("  ✗ %s %s：旅店找不到歇 / 候钮" % [port_id, "%04d-%02d-%02d" % [y, mo, d]])
		return ["", ""]
	# before：今天（按钮前）涵江卡可见性
	var sub_before := _card_row_now(port_id)
	var pressed: Button = cross if cross != null else (chips[0] as Button)
	var debt0: int = gs.debt
	var money0: int = gs.money
	var d0: String = "%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)]
	var d1: String
	if rebind > 0:
		_main._on_rest(rebind, port_id)
	else:
		pressed.pressed.emit()
	await _settle(6)
	d1 = "%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)]
	var sub_after := _card_row_now(port_id)
	var day_to := int(cal.day)
	var new_notices: Array = _arrivals.duplicate()
	if cross != null:
		day_to = cross_to
	print("REST_CLICK|%s|钮面「%s」|chips=%s|debt %d→%d|money %d→%d|notices %d 则|card %s→%s" % [
		d0, want, " / ".join(texts), debt0, int(gs.debt),
		money0, int(gs.money), new_notices.size(), sub_before, sub_after])
	for t in new_notices:
		print("REST_NOTICE| %s" % t)
	print("REST_DATE| %s → %s" % [d0, d1])
	return [sub_before, sub_after, int(cal.year), int(cal.month), day_to]


func _d2_inn_cross() -> void:
	print("")
	print("== D2 旅店「候 N 日」一钮（兴化 1277-10-19，窗口外 1 日；催促窗 10-20 起）")
	var re := RegEx.new()
	re.compile("^(歇|候) ")
	var r: Array = await _d2_inn_chip("xinghua", 1277, 10, 19, re, 13, 2)
	var ok_cross: bool = int(r[2]) == 1277 and int(r[3]) == 11 and int(r[4]) == 2
	if not ok_cross:
		fails += 1
		print("  ✗ 「候 13 日」按下后应落在 1277-11-02")
	if str(r[0]) == "" and str(r[1]) == "":
		print("D2_OBS 一钮成眠前卡不在、醒来卡已不在：10-20→10-31 催促窗 12 天整段被跨过（11-01 起卡已收回）")
	else:
		print("D2_OBS 按下前副题「%s」→ 醒来副题「%s」" % [str(r[0]), str(r[1])])
	print("")
	print("== D2 对照：10-20 按「歇 1 日」（只推一日，不跨窗）")
	var r2: Array = await _d2_inn_chip("xinghua", 1277, 10, 20, re, 1, 21)
	if not (int(r2[2]) == 1277 and int(r2[3]) == 10 and int(r2[4]) == 21):
		fails += 1
		print("  ✗ 「歇 1 日」按下后应落在 1277-10-21")
	if str(r2[1]).contains("城撑不过这个月了"):
		print("D2_OBS 歇一日醒来副题仍为催促：一日一推的店客还有 11 天能看见")
	else:
		print("D2_OBS 歇一日醒来副题「%s」" % str(r2[1]))


# ── 三、涵江卡窗口扫描 ──────────────────────────────────

func _card_row_now(at: String) -> String:
	if gs.has_flag("ending_root_sea"):
		return "(已被终局压住)"
	if not (int(cal.year) == 1277 and int(cal.month) in [9, 10]):
		return ""
	if str(eco.war_status("xinghua")) != "besieged":
		return ""
	if gs.has_flag("renamed_wenlong"):
		return "(士人线不出此卡)"
	if not gs.has_found("nameless_shelter_bay"):
		return "(未勘见旧避风澳)"
	return "涵江海口｜%s" % str(_main._hanjiang_card_subtitle())


func _card_window_scan() -> void:
	print("")
	print("== D2C 涵江卡窗口扫描（1277-10-01 → 12-31，逐日：在兴化喊 / 到了海口喊）")
	_reset_day("xinghua", 1277, 10, 1, 20000, 500)
	_main.load_scene("xinghua")
	await _settle(6)
	while true:
		var y: int = cal.year
		var mo: int = cal.month
		var d: int = cal.day
		if y > 1277 or (y == 1277 and mo > 12):
			break
		var prev := "%04d-%02d-%02d" % [y, mo, d]
		gm.advance_days(1)
		await _settle(1)
		var in_xh := _card_row_now("xinghua")
		var at_harbor := ""
		if d == int(cal.DAYS_PER_MONTH) or str(in_xh) != "" or (mo == 10 and d >= 17) or (mo == 11 and d <= 5):
			at_harbor = _card_row_now("xinghua_harbor")
			for t in _arrivals:
				print("SCAN_NOTICE|%s→| %s" % [prev, t])
			_arrivals.clear()
			print("SCAN|%04d-%02d-%02d→%04d-%02d-%02d|在兴化:%s|到了海口:%s" % [
				y, mo, d, int(cal.year), int(cal.month), int(cal.day), in_xh, at_harbor])
		else:
			_arrivals.clear()


# ── 小件 ──────────────────────────────────────────────

func _find_all(n: Node, pred: Callable, out := []) -> Array:
	if n == null:
		return out
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_find_all(c, pred, out)
	return out


func _settle(n: int) -> void:
	for _i in n:
		await process_frame
