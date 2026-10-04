extends SceneTree
## lane w28-k1：旅店 / 住处「歇・候 N 日」钮面——同一批歇息钮在两条贴文路径下各亮一路断言。
## 来源：w26-k9 Verify 交主控第 4 条+w27-k2 交主控第 2 条重申：qa_rest_days 钉了旅店一景的印数与扣钱，
## 未钉「同一批钮在旅店、住处两条不同贴文路径下各自正确亮出（且不该亮的地方没有混出一枚）」。
## 本探针不把两个场景同时挂上树（Main 是单页壳，load_scene 会换页）；钉的是同一主线状态（10-19 钱足）
## 下旅店一景歇工席亮三路（含随日的「候 12 日　180」）、住处一景另外亮两路（下处价，无候风钮）——
## 两路各自的独立断言 + 同一见证串里的并列一致断言。各枚读得到、文字逐字对、
## 看得見按得下（visible / disabled / focus_mode 逐字同）。
## 「该暗」用同管贴文路（同一 _slip_row 工席、同一 HFlowContainer 钮行）的寺观工席作反驾：
## 探针给旗标簿放进 hook_xinghua_asked，让仓内泉州真钩「追问兴化来人的下落」按 hide_if_flag 清出、
## 寺观工席确有贴文但没落进歇息这条路（跑完 erase 还原）→ 歇息 / 候钮一枚都不该混出来；两路串了线
## （歇候钮漏到别的工席）这里即红。
## lane w48-k5（w28-k1 Verify 剩余未守面 ①②③ 补钉，追加 S4–S6 于既有 18 案后，既有 S1–S3 零改）：
##   S4 在身委办剩 N 日时三枚旅店钮的「・误期」印尾逐字钉（歇 1 不带 / 歇 10・候 12 各带）+ 清净对照——
##      原仅 verify_economy 静态锁、运行时无断言（①）；
##   S5 「候 N 日」N 随日走：12-15 印「候 16 日　240」→ 历日 +1 重挂变「候 15 日　225」、旧印不残留（②）；
##   S6 旅店/住处 rate 错挂交叉直钉：真按「歇 10 日　150」（INN_RATE 150「店中」）与「歇 3 日　15」
##      （HOME_RATE 15「下处」）的扣钱 / 落日 / 记事原文逐字，互挂对方价即红（③，面值断言间接着住之外的第一根直钉）。
## lane w53-6（追加 S7 于 S6 后，既有 S1–S6 零改）：
##   S7 住处两钮同旅店印「・误期」尾、歇息工席带委办期限一句——原先只旅店有，委办剩两日时在下处按「歇 3 日」
##      不印尾、不提醒，误了期扣钱掉名声（剩 2 日：歇 1 不带 / 歇 3 带，句「还剩 2 日」；当日到期：两钮都带，句「还剩 0 日」；
##      清净景无此句。已逾期的委办 load_scene 先 tick_contract 结掉，页上见不到，不摆）。
## 读的都是 scene 树现挂的可枚举面；不撬 Main 内部钩子、不改 qa_rest_days_probe.gd 一字。
## 用法：godot --headless --path . -s res://tools/qa_rest_scenarios_probe.gd
## 输出末行 REST_SCENARIOS cases=N fails=M；M>0 时 exit 1。

const INN_SCENE := "xinghua_inn"  ## 旅店场景（兴化：候钮日数随历法日走，19 日摆场恰能钉「候 12 日　180」）
const HOME_SCENE := "quanzhou_residence"  ## 住处场景（泉州的走的是 _setup_residence；兴化住处是玉湖陈宅剧情页，没有歇息钮）
const TEMPLE_SCENE := "quanzhou_temple"  ## 反驾场景：同一管工席贴文路（_slip_row / HFlowContainer），但不进歇息这条路

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var fleet: Node
var cases := 0
var fails := 0
## w53-11：注册表判词「本进程 SCRIPT ERROR 即红」空转收编（同 qa_debt_strip_probe）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## w53-11 二轮：_run 被脚本错半路掐断时收尾不会被调到（quit 不再执行、进程空转到外层 timeout）——
## 回到这里就地判红收尾
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


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

	await _s1_inn_face()
	await _s2_home_face()
	await _s3_cross_scenarios()
	await _s4_overdue_mark()
	await _s5_wait_n_rolls()
	await _s6_rate_bind_press()
	await _s7_home_overdue()

	_report()


## 收尾（w53-11 二轮从 _run 尾挪出；_run_guarded 判中止时也走这里）：SCRIPT ERROR 两判走共用件 verdicts()
## （story :3156 同款判词），再印末行。
func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("REST_SCENARIOS cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(frames := 1) -> void:
	for i in range(frames):
		await process_frame


func _reset_day(port_id: String, y: int, mo: int, d: int, money := 20000) -> void:
	gs.from_dict({})
	cal.from_dict({"year": y, "month": mo, "day": 1})
	if d > 1:
		gm.advance_days(d - 1)
	gs.from_dict({})
	gs.last_port = port_id
	gs.money = money
	gs.debt = 0
	fleet.morale = 50


func _find_all(n: Node, pred: Callable, out := []) -> Array:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_find_all(c, pred, out)
	return out


## 歇・候钮一枚的描述：文字（逐字）／看得見／按得下／可聚焦（亮色链的两端）。
func _chip_state(b: Button) -> Array:
	return [str(b.text), b.visible, b.disabled, b.focus_mode != Control.FOCUS_NONE]


## 整棵树里钮面以「歇 」「候 」起头的钮。parent_chain 只记容器的「类・名」，单场景内恰能指认工席而不变易。
func _collect_rest_chips() -> Array:
	var got: Array = []
	var btns: Array = _find_all(_main, func(n: Node) -> bool: return n is Button)
	for b in btns:
		var t := str((b as Button).text)
		if t.begins_with("歇 ") or t.begins_with("候 "):
			var row := (b as Node).get_parent()
			var home := (row as Node).get_parent() if row != null else null
			var chain := ""
			if row != null:
				chain = "%s・%s" % [((row as Node).get_class()), str((row as Node).name)]
				if home != null:
					chain += " <- %s・%s" % [((home as Node).get_class()), str((home as Node).name)]
			got.append({"b": b, "state": _chip_state(b), "row": row, "chain": chain})
	return got


func _check(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		fails += 1
		print("  ✗ " + msg)


func _state_text(st: Array) -> String:
	return "「%s」见 %s・暗 %s・焦 %s" % [st[0], st[1], st[2], st[3]]


## ── S1 旅店场景：一景三钮，印数 / 亮起 / 工行 ────────────
func _s1_inn_face() -> void:
	print("== S1 旅店（兴化 1277-10-19：歇 1・歇 10・候 12 三钮同亮一工席行）")
	_reset_day("xinghua", 1277, 10, 19)
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var chips := _collect_rest_chips()
	var want := [["歇 1 日　15", false], ["歇 10 日　150", false], ["候 12 日　180", false]]
	for w in want:
		var face := str(w[0])
		var hits: Array = chips.filter(func(c: Dictionary) -> bool: return c["state"][0] == face)
		_check(hits.size() == 1, "旅店场景这行字里恰读出 1 枚「%s」（实 %d 枚；整树实读：%s）" % [
			face, hits.size(), " / ".join(chips.map(func(c: Dictionary) -> String: return str(c["state"][0])))])
		if hits.size() == 1:
			var st: Array = (hits[0] as Dictionary)["state"]
			_check(st[1] == true and st[2] == w[1] and st[3] == true,
				"旅店「%s」亮起逐字同（实读：%s）" % [face, _state_text(st)])
	var rows: Array = []
	for c in chips:
		if not (c as Dictionary)["row"] in rows:
			rows.append((c as Dictionary)["row"])
	var rest_cnt: Array = chips.filter(func(c: Dictionary) -> bool: return str(c["state"][0]).begins_with("歇 "))
	_check(chips.size() == 3 and rest_cnt.size() == 2 and rows.size() == 1,
		"旅店整树歇・候钮恰歇 2 + 候 1 = 3 枚且同出一枚钮行（实 %d 枚 / 歇 %d / %d 行；非此布局即串线或丢失）" % [chips.size(), rest_cnt.size(), rows.size()])
func _s2_home_face() -> void:
	print("== S2 住处（泉州 1277-10-19：歇 1 日　5 / 歇 3 日　15 两钮同亮一工席行，无候风钮）")
	_reset_day("quanzhou", 1277, 10, 19)
	_main.load_scene(HOME_SCENE)
	await _settle(6)
	var chips := _collect_rest_chips()
	var want := [["歇 1 日　5", false], ["歇 3 日　15", false]]
	for w in want:
		var face := str(w[0])
		var hits: Array = chips.filter(func(c: Dictionary) -> bool: return c["state"][0] == face)
		_check(hits.size() == 1, "住处场景这行字里恰读出 1 枚「%s」（实 %d 枚；整树实读：%s）" % [
			face, hits.size(), " / ".join(chips.map(func(c: Dictionary) -> String: return str(c["state"][0])))])
		if hits.size() == 1:
			var st: Array = (hits[0] as Dictionary)["state"]
			_check(st[1] == true and st[2] == w[1] and st[3] == true,
				"住处「%s」亮起逐字同（实读：%s）" % [face, _state_text(st)])
	var waits: Array = chips.filter(func(c: Dictionary) -> bool: return str(c["state"][0]).begins_with("候 "))
	_check(waits.is_empty(), "住处工席没有候风钮（实 %d 枚混出；旅店那枚串线来这里即红）" % waits.size())
	var rows: Array = []
	for c in chips:
		if not (c as Dictionary)["row"] in rows:
			rows.append((c as Dictionary)["row"])
	_check(chips.size() == 2 and rows.size() == 1,
		"住处整树歇息钮恰 2 枚且同出一枚钮行（实 %d 枚 / %d 行）" % [chips.size(), rows.size()])


## ── S3 两场景并列：同主线状态先亮旅店三路、再亮住处两路，住处另亮不误旅店印数 ──
func _s3_cross_scenarios() -> void:
	print("== S3 并列（同一主线状态 10-19 钱足：旅店三路亮 → 住处两路亮 → 寺观反驾该暗）")
	_reset_day("xinghua", 1277, 10, 19)
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var inn := _collect_rest_chips()
	_main.load_scene(HOME_SCENE)
	await _settle(6)
	var home := _collect_rest_chips()
	_check(inn.size() == 3 and not inn.is_empty(),
		"见证时旅店一景歇 / 候钮恰 3 枚（实 %d 枚）" % inn.size())
	_check(home.size() == 2 and not home.is_empty(),
		"见证时住处一景歇息钮恰 2 枚（实 %d 枚；与旅店并列两路各亮）" % home.size())
	var inn_waits: Array = inn.filter(func(c: Dictionary) -> bool: return str(c["state"][0]).begins_with("候 "))
	_check(inn_waits.size() == 1 and str((inn_waits[0] as Dictionary)["state"][0]) == "候 12 日　180",
		"旅店那枚随日的候钮印「候 12 日　180」；住处两枚仍是下处价，没把旅店印数带过去（实候钮 %d 枚）" % inn_waits.size())
	var inns := inn.map(func(c: Dictionary) -> String: return _state_text(c["state"]))
	var homes := home.map(func(c: Dictionary) -> String: return _state_text(c["state"]))
	_check(inns.size() + homes.size() == 5, "两路并列表各落齐（旅店 %d 项 + 住处 %d 项 = 5；下两行把五枚的钮面原文与亮起逐字抄出）" % [inns.size(), homes.size()])
	print("  | 旅店三路：%s" % " ｜ ".join(inn.map(func(c: Dictionary) -> String: return "%s@%s" % [_state_text(c["state"]), str(c["chain"])])))
	print("  | 住处两路：%s" % " ｜ ".join(home.map(func(c: Dictionary) -> String: return "%s@%s" % [_state_text(c["state"]), str(c["chain"])])))

	# 反驾：同管歇息管线的寺观工席（同 _slip_row 的 HFlowContainer、工席上确有贴文——探针给
	# GameState.flags 放进 hook_xinghua_asked，用仓内泉州真钩「追问兴化来人的下落」的 hide_if_flag
	# 反着读：放进即钩清出、正文不空；跑完还原）——不进歇息这条路，歇 / 候钮一枚都不该混出来。
	gs.set_flag("hook_xinghua_asked")
	_main.load_scene(TEMPLE_SCENE)
	await _settle(6)
	var tp := _collect_rest_chips()
	gs.flags.erase("hook_xinghua_asked")
	_check(tp.is_empty(), "寺观工席（该暗）歇息 / 候钮 0 枚（实 %d 枚：%s）" % [
		tp.size(), " / ".join(tp.map(func(c: Dictionary) -> String: return _state_text(c["state"])))])


## ── S4 「・误期」印尾（w28-k1 剩余未守面 ①）：在身委办 days_left < 钮面日数时，三枚旅店钮尾字逐字钉 ──
func _s4_overdue_mark() -> void:
	print("== S4 ・误期印尾（1277-10-19 委办剩 5 日：歇 1 不带尾 / 歇 10・候 12 各带「・误期」；清净对照全不带）")
	_reset_day("xinghua", 1277, 10, 19)
	_plant_contract(5)	# 剩 5 日（须在 _reset_day 后摆——reset 清档；due_day 现算见摆场证行）
	var due_now: int = cal.absolute_day() + 5	# 现算（摆场日不同自动跟，免抄死数）
	_check(int(gs.contract.get("due_day", -1)) == due_now and int(gs.contract_status().get("days_left", -1)) == 5,
		"摆场证：委办在档（due_day=%d、剩 5 日——from_dict 原样保回即此钉，摆不进全部断言失真）" % due_now)
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var texts: Array = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	_check(texts.size() == 3, "误期景旅店歇・候钮仍恰 3 枚（实 %d 枚：%s）" % [texts.size(), " / ".join(texts)])
	var want := ["歇 1 日　15", "歇 10 日　150・误期", "候 12 日　180・误期"]
	for w in want:
		_check(w in texts, "委办剩 5 日景钮面恰含「%s」（5<1 否、5<10 与 5<12 是——实读：%s）" % [w, " / ".join(texts)])
	_reset_day("xinghua", 1277, 10, 19)	# 委办清净
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var clean: Array = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	var clean_want := ["歇 1 日　15", "歇 10 日　150", "候 12 日　180"]
	_check(clean == clean_want, "清净景三钮逐字同且无「・误期」尾（实读：%s——钮面原印数不受委办影）" % " / ".join(clean))


## 摆一笔在场委办：absolute_day+due_in_days 作 due_day 直走 from_dict 保档路（不撬 contract_offer 随机口）。
func _plant_contract(due_in_days: int) -> void:
	var due: int = cal.absolute_day() + due_in_days
	gs.from_dict({"contract": {
		"good_id": "grain", "qty": 1, "remaining": 1, "dest": "hakata", "from": "xinghua",
		"purse": 100, "unit_purse": 100.0, "paid": 0, "due_day": due, "deadline_days": due_in_days,
	}})


## ── S5 「候 N 日」N 随日走（同 ②）：跨日后 load_scene 重挂，钮面印数须变天 ──────────
func _s5_wait_n_rolls() -> void:
	print("== S5 候 N 随日走（1277-12-15 印「候 16 日」→ 历日 +1 重挂印「候 15 日」，价同跟走）")
	_reset_day("xinghua", 1277, 12, 15)
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var t0: Array = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	_check("候 16 日　240" in t0, "12-15 旅店候钮印「候 16 日　240」（实读：%s）" % " / ".join(t0))
	_main.message_label.text = ""	# 只换历日不推日推链（advance_days 会带月结/委办 tick 一串效应）；跨日重挂前清屏，免旧屏条影 S6 读数
	cal.advance_days(1)
	_main.load_scene(INN_SCENE)
	await _settle(6)
	var t1: Array = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	_check("候 15 日　225" in t1, "跨日重挂候钮印变「候 15 日　225」（N 16→15、价 240→225 同跟——实读：%s）" % " / ".join(t1))
	_check(not ("候 16 日　240" in t1), "旧印「候 16 日　240」不残留（实读：%s——钉死不变者此判红）" % " / ".join(t1))


## ── S6 rate 错挂交叉直钉（同 ③）：旅店 (INN_RATE,店中) / 住处 (HOME_RATE,下处) 元组逐字互不通 ──
func _s6_rate_bind_press() -> void:
	print("== S6 rate 错挂交叉（泉州旅店歇 10 日按落 03-12 付 150「店中」；泉州住处歇 3 日按落 03-05 付 15「下处」）")
	_reset_day("quanzhou", 1277, 3, 2)
	_current_scene_setup("inn")
	await _settle(6)
	var b := _find_rest_button("歇 10 日　150")
	if b == null:
		_check(false, "旅店找不到「歇 10 日　150」钮（摆场败坏——实读：%s）" % " / ".join(
			_collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))))
	else:
		var m0: int = gs.money
		b.pressed.emit()
		await _settle(6)
		var line := _last_rest_log()
		_check(m0 - int(gs.money) == 10 * _main.INN_RATE,
			"旅店按「歇 10 日　150」扣 %d = 10×INN_RATE(%d) = 150——旅店错挂 HOME_RATE 扣 50 即红" % [m0 - int(gs.money), _main.INN_RATE])
		_check("%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)] == "1277-03-12",
			"旅店歇 10 日落 1277-03-12（实落 %s）" % "%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)])
		_check(line.contains("在店中歇了 10 日，付房钱 150。"),
			"旅店记事屏条逐字含「在店中歇了 10 日，付房钱 150。」（place 错挂即红——实条：%s）" % line)
	_reset_day("quanzhou", 1277, 3, 2)
	_current_scene_setup("residence")
	await _settle(6)
	var h := _find_rest_button("歇 3 日　15")
	if h == null:
		_check(false, "住处找不到「歇 3 日　15」钮（摆场败坏——实读：%s）" % " / ".join(
			_collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))))
	else:
		var m1: int = gs.money
		h.pressed.emit()
		await _settle(6)
		var hline := _last_rest_log()
		_check(m1 - int(gs.money) == 3 * _main.HOME_RATE,
			"住处按「歇 3 日　15」扣 %d = 3×HOME_RATE(%d) = 15——住处错挂 INN_RATE 扣 45 即红" % [m1 - int(gs.money), _main.HOME_RATE])
		_check("%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)] == "1277-03-05",
			"住处歇 3 日落 1277-03-05（实落 %s）" % "%04d-%02d-%02d" % [int(cal.year), int(cal.month), int(cal.day)])
		_check(hline.contains("在下处歇了 3 日，付房钱 15。"),
			"住处记事屏条逐字含「在下处歇了 3 日，付房钱 15。」（place 错挂即红——实条：%s）" % hline)


## ── S7 住处・误期（lane w53-6）：住处两钮同旅店印「・误期」尾，歇息工席带委办期限一句 ──
func _s7_home_overdue() -> void:
	print("== S7 住处・误期（1277-10-19 泉州住处：委办剩 2 日 歇 1 不带尾 / 歇 3 带「・误期」、句「还剩 2 日」；当日到期两钮都带、句「还剩 0 日」；清净景无句）")
	_reset_day("quanzhou", 1277, 10, 19)
	_plant_contract(2)
	_main.load_scene(HOME_SCENE)
	await _settle(6)
	var texts: Array = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	_check(texts == ["歇 1 日　5", "歇 3 日　15・误期"],
		"委办剩 2 日住处两钮「歇 1 日　5 / 歇 3 日　15・误期」（2<1 否、2<3 是——实读：%s）" % " / ".join(texts))
	_check(_note_with("在身委办还剩 2 日") != "", "委办剩 2 日住处歇息工席有「在身委办还剩 2 日」一句（同旅店——实读：%s）" % _note_with("在身委办"))
	_reset_day("quanzhou", 1277, 10, 19)
	_plant_contract(0)
	_main.load_scene(HOME_SCENE)
	await _settle(6)
	texts = _collect_rest_chips().map(func(c: Dictionary) -> String: return str(c["state"][0]))
	_check(texts == ["歇 1 日　5・误期", "歇 3 日　15・误期"] and _note_with("在身委办还剩 0 日") != "",
		"委办当日到期住处两钮都带「・误期」、句「还剩 0 日」（实读：%s｜%s）" % [" / ".join(texts), _note_with("在身委办")])
	_reset_day("quanzhou", 1277, 10, 19)
	_main.load_scene(HOME_SCENE)
	await _settle(6)
	_check(_note_with("在身委办") == "", "清净景住处无委办那句（实读：「%s」）" % _note_with("在身委办"))


## 现景里第一条含 needle 的可见 Label 原文（找不到给空串）
func _note_with(needle: String) -> String:
	var hits: Array = _find_all(_main, func(n: Node) -> bool:
		return n is Label and not n.is_queued_for_deletion() and (n as Label).is_visible_in_tree() and (n as Label).text.contains(needle))
	return str((hits[0] as Label).text) if not hits.is_empty() else ""


## 现景直挂本港某设施贴文路径（scenes.json 只有 quanzhou_inn / 没有 quanzhou_residence——fallback 会换港；
## 走与 _load_scene_inner 同一线的 _setup_dynamic_scene 寻址，current_scene_id 记全形与 Main 一致）。
func _current_scene_setup(scene_id: String) -> void:
	_main.set("current_scene_id", scene_id)
	_main.call("_setup_dynamic_scene", scene_id, "_" + scene_id)


## 按字面在现景里读出该钮（整树、不限于某行）。
func _find_rest_button(face: String) -> Button:
	var rows: Array = _find_all(_main, func(n: Node) -> bool: return n is HFlowContainer)
	for r in rows:
		for b in (r as Node).get_children():
			if b is Button and str((b as Button).text) == face:
				return b
	return null


## 取宿主 _log_lines 里末一条「在…歇了 …付房钱 …。」原文——每行即 log_msg 入档原文（新的在前），
## 不经折叠渲染那层解析。_on_rest 记事的运行时证。
func _last_rest_log() -> String:
	var lines: PackedStringArray = _main.get("_log_lines")
	for i in range(lines.size()):
		var s := str(lines[i]).strip_edges()
		if s.contains("歇了") and s.contains("付房钱"):
			return s
	return ""
