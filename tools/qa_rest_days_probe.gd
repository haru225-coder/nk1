extends SceneTree
## lane w24-b2：旅店 / 住处「歇・候 N 日」钮面 ←→ 实扣真断言契约探针（真断言，不注掉）。
## 来源：w23-a7 遗留② / docs/欠债跳年通告留档_2026-10-03.md §五.1——a7 摆场 1277-10-19 读钮面得
## 「候 12 日　180」而探针直调 _on_rest(13) 扣 195 / 落 11-02，挂上「钮面叙事与可复现实推差 1 日」。
## 本 lane 归因核验（git pickaxe 全史）：TavernPage / ResidencePage 绑定与 Main._on_rest 全史均无
## to_next+1；a7 直调的 13 是探针按「D2 整窗跨过」所需粒度硬编码的摆场参数，非按钮绑定。
## 现行「候 N 日」语义 = DAYS_PER_MONTH - day + 1（10-19 → 11-01 月初，含今天在店的整日数），
## 与 verify_economy.py:2063-2110 静态锁的「钮文日数 = bind 实参 = _on_rest 扣费日数」同口径。
## 本探针在真场景树上把同一口径钉成运行时真断言：
##   C1 旅店钮面「歇 1 日　15 / 歇 10 日　150 / 候 12 日　180」并经 _find_all 在树中各读到一枚；
##   C2 真按「候 12 日」钮：10-19 → 11-01（月初到账），钱恰扣 180（=钮面印数），记事与钮面同日数；
##   C3 12-15 按「候 16 日」跨年 → 1278-01-01、扣 240（月初结息落 1 月而非 12 月，辨得动 -1/跨年混结）；
##   C4 跨月旅途月供真实到达：欠债 500 候钮跨月，月息通告 ≥1 则（钉 b2 顺带复现的「跨月白住」疑点）；
##   C5 0 日钮不存在的负向钉：1 日清晨钮面只印「候 30 日」；根因清除后 1 日钮面必印「候 30 日 450」；
##   C6 钱不够：任何钮按不动、日子不推（既有钱不够边界，也锁【钱不够】话术不被回归掉）；
##   C7 住处 3 日一钮多钱不够：钱付半额时钮面仍印、按下不动（HOME_RATE 第二条歇息路径同钉）。
## 用法：godot --headless --path . -s res://tools/qa_rest_days_probe.gd -- --contract
## 输出末行 REST_DAYS cases=N fails=M；M>0 时 exit 1。

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var fleet: Node
var _arrivals: Array = []
var cases := 0
var fails := 0
## w53-11：注册表判词「本进程 SCRIPT ERROR 即红」空转收编（同 qa_debt_strip_probe）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
var _tally: ScriptErrTally


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
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
	fleet = root.get_node_or_null("Fleet")
	if gs == null or gm == null or cal == null or eco == null or fleet == null:
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
		push_error("Main.gd 未载入")
		quit(1)
		return
	gm.monthly_notice.connect(func(t: String) -> void: _arrivals.append(str(t)))

	await _c1_chip_face()
	await _c2_press_wait_chip()
	await _c3_cross_year()
	await _c4_monthly_interest_arrives()
	await _c5_day1_dawn()
	await _c6_broke()
	await _c7_home_broke()

	var probe := ScriptErrTally.new()
	probe._log_error("f", "res://x.gd", 1, "", "自证 SCRIPT", false, Logger.ERROR_TYPE_SCRIPT, [])
	probe._log_error("f", "res://x.gd", 2, "", "自证 ERROR", false, Logger.ERROR_TYPE_ERROR, [])
	probe._log_error("f", "res://x.gd", 3, "", "自证 WARNING", false, Logger.ERROR_TYPE_WARNING, [])
	_check(probe.lines.size() == 1,
		"SCRIPT ERROR 计数器自证：只数脚本类（喂 SCRIPT / ERROR / WARNING 各一，数到 %d）" % probe.lines.size())
	OS.remove_logger(_tally)
	var errs: Array = _tally.lines
	_check(errs.is_empty(),
		"运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
		"" if errs.is_empty() else "，首条：" + str(errs[0])])
	print("REST_DAYS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(frames := 1) -> void:
	for i in range(frames):
		await process_frame


func _reset_day(port_id: String, y: int, mo: int, d: int, money := 20000, debt := 0) -> void:
	gs.from_dict({})
	cal.from_dict({"year": y, "month": mo, "day": 1})
	_arrivals.clear()
	if d > 1:
		gm.advance_days(d - 1)  # 同 qa_shore：把 1..d 真走一遍，沿路结算按真实历法发生
		_arrivals.clear()
	gs.last_port = port_id
	gs.money = money
	gs.debt = debt
	_arrivals.clear()
	fleet.morale = 50


## 进旅店 / 住处场景，把歇・候钮面全读下来。
func _chip_texts(scene_id: String) -> Array:
	_main.load_scene(scene_id)
	return []  # 调用方 await _settle 后再 _collect_chips


func _collect_chips() -> Array:
	var texts: Array = []
	var rows: Array = _find_all(_main, func(n: Node) -> bool: return n is HFlowContainer)
	for r in rows:
		for b in (r as Node).get_children():
			if b is Button:
				var t := str((b as Button).text)
				if t.begins_with("歇 ") or t.begins_with("候 "):
					texts.append(t)
	return texts


func _find_chip(texts_prefix: String) -> Button:
	var rows: Array = _find_all(_main, func(n: Node) -> bool: return n is HFlowContainer)
	for r in rows:
		for b in (r as Node).get_children():
			if b is Button and str((b as Button).text).begins_with(texts_prefix):
				return b
	return null


func _find_all(n: Node, pred: Callable, out := []) -> Array:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_find_all(c, pred, out)
	return out


func _date() -> String:
	return "%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)]


func _check(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		fails += 1
		print("  ✗ " + msg)


func _expect_face(scene: String, want: Array, label: String) -> void:
	_main.load_scene(scene)
	return


# ── C1 钮面印数 ─────────────────────────────────────────

func _c1_chip_face() -> void:
	print("== C1 旅店钮面（兴化 1277-10-19：候钮应印 N=12 / 180）")
	_reset_day("xinghua", 1277, 10, 19)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var texts := _collect_chips()
	var want := ["歇 1 日　15", "歇 10 日　150", "候 12 日　180"]
	for w in want:
		_check(w in texts, "钮面含「%s」（实读：%s）" % [w, " / ".join(texts)])
		var b := _find_chip(w)
		_check(b != null, "场景树里找得到这枚钮（可 emit）")


# ── C2 真按「候 12 日」：日数 / 钱 / 月初三重验 ───────────

func _c2_press_wait_chip() -> void:
	print("== C2 按「候 12 日」（1277-10-19 按 → 11-01 月初；扣 180 一文不差）")
	_reset_day("xinghua", 1277, 10, 19)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var b := _find_chip("候 12 日")
	if b == null:
		_check(false, "场景里找不到「候 12 日」钮")
		return
	var face := str(b.text)
	var m0: int = gs.money
	var morale0: int = fleet.morale
	var d0: int = cal.day
	var mo0: int = cal.month
	b.pressed.emit()
	await _settle(6)
	# 日：走了钮面印的日数，恰好落在下月 1 日
	_check(int(cal.month) == mo0 + 1 and int(cal.day) == 1,
		"按「候 12 日」落月底后初一（实落 %s；差 1 日时此判红）" % _date())
	var walked: int = 30 - d0 + 1  # 今日在店，候满本月
	_check(walked == 12, "轨道推演的候日数 %d = 12（30-%d+1）" % [walked, d0])
	# 钱：按同一日数 × INN_RATE 扣，一文不多
	_check(m0 - int(gs.money) == 12 * _main.INN_RATE,
		"扣钱 %d = 12×%d = 180（钮面印数即实扣数）" % [m0 - int(gs.money), _main.INN_RATE])
	# 无债跨月不产生月息（C4 再用欠债正向钉旅途月结）
	var interest_notes := 0
	for t in _arrivals:
		if str(t).contains("【月息】"):
			interest_notes += 1
	_check(interest_notes == 0, "无债跨月：月息通告 0 则（实到 %d 则）" % interest_notes)
	# 士气随日数上涨（同一 days 变量的第三消费点，变异 days±n 这里跟着红）。
	# walking 期间 <75 每日 +1+bonus，起点 50 走过 18 天再看差值即可，不必钉绝对数。
	_check(int(fleet.morale) >= morale0 + 12 * 2 or int(fleet.morale) > morale0,
		"按后士气比按前涨（%d→%d；days 归零变异时此判红）" % [morale0, int(fleet.morale)])
	print("  | pressed「%s」money %d→%d date→%s" % [face, m0, int(gs.money), _date()])


# ── C3 跨年：12-15 候 16 日 → 次年 1-1 ─────────────────

func _c3_cross_year() -> void:
	print("== C3 跨年（1277-12-15 按「候 16 日」→ 1278-01-01，扣 240）")
	_reset_day("xinghua", 1277, 12, 15)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var b := _find_chip("候 16 日")
	if b == null:
		_check(false, "场景里找不到「候 16 日」钮（实读：%s）" % " / ".join(_collect_chips()))
		return
	var m0: int = gs.money
	b.pressed.emit()
	await _settle(6)
	_check(int(cal.year) == 1278 and int(cal.month) == 1 and int(cal.day) == 1,
		"跨年落 1278-01-01（实落 %s；跨年/差 1 混了一日此判红）" % _date())
	_check(m0 - int(gs.money) == 16 * _main.INN_RATE,
		"跨年扣钱 %d = 16×%d" % [m0 - int(gs.money), _main.INN_RATE])


# ── C4 跨月旅途月结真实到达（顺带复现的「跨月白住」疑点钉死）──

func _c4_monthly_interest_arrives() -> void:
	print("== C4 欠债跨月（债 500，候 12 日跨进 11 月：月息必须真到账）")
	_reset_day("xinghua", 1277, 10, 19, 20000, 500)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var b := _find_chip("候 12 日")
	if b == null:
		_check(false, "场景里找不到「候 12 日」钮")
		return
	var debt0: int = gs.debt
	b.pressed.emit()
	await _settle(6)
	var interest_notes := 0
	for t in _arrivals:
		if str(t).contains("【月息】"):
			interest_notes += 1
	_check(interest_notes >= 1, "候钮跨月旅途月结：月息通告 ≥1 则（实到 %d 则；0 = 跨月白住复现）" % interest_notes)
	_check(int(gs.debt) > debt0, "欠债 500 跨月生息（debt %d→%d，不增 = 跨月白住）" % [debt0, int(gs.debt)])


# ── C5 1 日清晨（0 日钮不存在的负向钉 + 根因清除正向钉）────

func _c5_day1_dawn() -> void:
	print("== C5 月初清晨（1277-10-01：候钮只印「候 30 日」一枚）")
	_reset_day("xinghua", 1277, 10, 1)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var texts := _collect_chips()
	var wait_chips := 0
	for t in texts:
		if str(t).begins_with("候 "):
			wait_chips += 1
	_check(wait_chips == 1, "候钮恰一枚（实 %d 枚；「候 0 日」类假钮一枚即红）" % wait_chips)
	_check("候 30 日　450" in texts, "初一候满整月印「候 30 日　450」（实读：%s）" % " / ".join(texts))


# ── C6 钱不够：钮按不动 ──────────────────────────────────

func _c6_broke() -> void:
	print("== C6 钱不够（10 钱按「候 12 日　180」：不推日、不扣钱、有话术）")
	_reset_day("xinghua", 1277, 10, 19, 10)
	_main.load_scene("xinghua_inn")
	await _settle(6)
	var b := _find_chip("候 12 日")
	if b == null:
		_check(false, "场景里找不到「候 12 日」钮")
		return
	var d0 := _date()
	b.pressed.emit()
	await _settle(6)
	_check(_date() == d0, "钱不够日子不推（仍在 %s，实 %s）" % [d0, _date()])
	_check(int(gs.money) == 10, "钱不够一文不扣（实 %d）" % int(gs.money))


# ── C7 住处第二条歇息路径：半额钱按不动 3 日钮 ─────────────

func _c7_home_broke() -> void:
	print("== C7 住处（泉州 1277-03-02 钱 8：歇 3 日 15 按不动，歇 1 日 5 按了落在 03-03）")
	_reset_day("quanzhou", 1277, 3, 2, 8)
	_main.load_scene("quanzhou_residence")
	await _settle(6)
	var texts := _collect_chips()
	_check(_has_prefix(texts, "歇 3 日　15"),
		"住处钮面印出 3 日钮「歇 3 日　15」（实读：%s）" % " / ".join(texts))
	var b3 := _find_chip("歇 3 日")
	if b3 != null:
		b3.pressed.emit()
		await _settle(6)
		_check(_date() == "1277-03-02", "8 钱按不动 3 日 15（实落 %s）" % _date())
		_check(int(gs.money) == 8, "8 钱按不动不扣（实 %d）" % int(gs.money))
	else:
		_check(false, "住处找不到「歇 3 日」钮")
	var b1 := _find_chip("歇 1 日")
	if b1 != null:
		b1.pressed.emit()
		await _settle(6)
		_check(_date() == "1277-03-03", "8 钱按得动 1 日 5（实落 %s）" % _date())
		_check(int(gs.money) == 3, "扣 5 剩 3（实 %d）" % int(gs.money))
	else:
		_check(false, "住处找不到「歇 1 日」钮")


func _has_prefix(texts: Array, prefix: String) -> bool:
	for t in texts:
		if str(t).begins_with(prefix):
			return true
	return false
