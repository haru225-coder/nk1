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
