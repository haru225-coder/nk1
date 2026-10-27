extends SceneTree
## lane npc2 / npc3 城中 NPC 链探针（headless，经门锁跑）。
## 断言：七条 NPC 线的 flag 顺序、各段可达、两条分支收益不同、存档来回。

const TAG := "QA_W57_NPC"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var Book
var gs: Node
var cal: Node

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	gs = root.get_node_or_null("GameState")
	cal = root.get_node_or_null("Calendar")
	Book = load("res://scripts/core/Districts.gd")
	if gs == null or cal == null or Book == null:
		_check(false, "GameState / Calendar / Districts 没载入")
		_report()
		return
	_check_data()
	_arc_maruding()
	_arc_zhubo()
	_arc_cairong()
	_arc_zhouxing()
	_arc_liang()
	_arc_zhengyan()
	_arc_xudai()
	_save_roundtrip()
	_report()


func _fresh(y: int = 1255, m: int = 3, d: int = 1) -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.flags = {}
	gs.identity = "undecided"
	gs.player_name = "陈子龙"
	gs.pu_attention = 0
	gs.merchant_credit = 0
	gs.scholar_tendency = 0
	gs.hometown_tendency = 0
	gs.network = 0
	gs.fame = 0
	gs.sea_tendency = 0
	cal.from_dict({"year": y, "month": m, "day": d})
	Book.wipe()


func _apply(ix_id: String, opt_id: String = "") -> Dictionary:
	return Book.apply(ix_id, opt_id)


func _ok(ix_id: String, opt_id: String = "") -> bool:
	var r: Dictionary = _apply(ix_id, opt_id)
	return bool(r.get("ok", false))


func _blocked(ix_id: String, why: String, opt_id: String = "") -> bool:
	var r: Dictionary = _apply(ix_id, opt_id)
	return not bool(r.get("ok", false)) and str(r.get("msg", "")) == why


func _check_data() -> void:
	var txt := FileAccess.get_file_as_string("res://data/npcs.json")
	var parsed = JSON.parse_string(txt)
	var ids: Dictionary = {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for n in parsed.get("npcs", []):
			if typeof(n) == TYPE_DICTIONARY:
				ids[str(n.get("id", ""))] = n
	for id in ["maruding", "zhubo", "cairong", "zhouxing", "liang_ashui", "zhengyan", "xudai"]:
		var n: Dictionary = ids.get(id, {})
		_check(str(n.get("name", "")) != "" and str(n.get("role", "")) != "" and str(n.get("function", "")) != "", "表：NPC %s 有名字、身份、小传" % id)
	for id in [
		"npc_maruding_meet", "npc_maruding_ledger", "npc_maruding_settle",
		"npc_zhubo_ask", "npc_zhubo_letter", "npc_zhubo_wind", "npc_zhubo_deliver",
		"npc_cairong_meet", "npc_cairong_evidence", "npc_cairong_settle",
		"npc_zhouxing_meet", "npc_zhouxing_rumor", "npc_zhouxing_bet",
		"npc_liang_wreck", "npc_liang_tide", "npc_liang_dive",
		"npc_zhengyan_meet", "npc_zhengyan_ledger", "npc_zhengyan_split",
		"npc_xudai_meet", "npc_xudai_contract", "npc_xudai_bargain",
	]:
		var ix: Dictionary = Book.interaction(id)
		_check(str(ix.get("id", "")) == id and bool(ix.get("once", false)), "表：事 %s 在册且只办一次" % id)
	var inv: Dictionary = Book.interaction("npc_zhengyan_invest")
	_check(str(inv.get("id", "")) == "npc_zhengyan_invest" and not bool(inv.get("once", false)) and (inv.get("costs", []) as Array).size() == 2 and (inv.get("monthly", []) as Array).size() == 2, "表：修陂工分两级入股，不标只办一次")


func _arc_maruding() -> void:
	_fresh()
	_check(_blocked("npc_maruding_ledger", "还没到那一步"), "马鲁丁：未见面时对账不可办")
	_check(_blocked("npc_maruding_settle", "还没到那一步", "forgive"), "马鲁丁：未对账时结账不可办")
	_check(_ok("npc_maruding_meet") and gs.has_flag("npc_maruding_met"), "马鲁丁：初见留 flag")
	_check(_ok("npc_maruding_ledger") and gs.has_flag("npc_maruding_ledger"), "马鲁丁：对账留 flag")
	_fresh()
	var ready := _ok("npc_maruding_meet") and _ok("npc_maruding_ledger")
	var c0 := int(gs.merchant_credit)
	var n0 := int(gs.network)
	var m0 := int(gs.money)
	var r: Dictionary = _apply("npc_maruding_settle", "forgive")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_maruding_forgiven") and int(gs.merchant_credit) == c0 + 2 and int(gs.network) == n0 + 1 and int(gs.money) == m0 and not gs.has_flag("npc_maruding_paid"), "马鲁丁：销账得信用与人脉，不收钱")
	_fresh()
	ready = _ok("npc_maruding_meet") and _ok("npc_maruding_ledger")
	m0 = int(gs.money)
	r = _apply("npc_maruding_settle", "call")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_maruding_paid") and int(gs.money) == m0 + 90 and not gs.has_flag("npc_maruding_forgiven"), "马鲁丁：收九十钱，铜牌归你")


func _arc_zhubo() -> void:
	_fresh()
	_check(_blocked("npc_zhubo_letter", "还没到那一步"), "祝伯：未接札时托札不可办")
	_check(_blocked("npc_zhubo_wind", "还没到那一步"), "祝伯：未托札时看潮信不可办")
	_check(_blocked("npc_zhubo_deliver", "还没到那一步", "temple"), "祝伯：未带札时顺济宫不可办")
	_check(_ok("npc_zhubo_ask") and gs.has_flag("npc_zhubo_asked"), "祝伯：接札留 flag")
	_check(_ok("npc_zhubo_letter") and gs.has_flag("npc_zhubo_letter"), "祝伯：托札留 flag")
	_check(_ok("npc_zhubo_wind") and gs.has_flag("npc_zhubo_carry"), "祝伯：看潮信留 flag")
	_fresh()
	var ready := _ok("npc_zhubo_ask") and _ok("npc_zhubo_letter") and _ok("npc_zhubo_wind")
	var f0: int = int(Book.favour_of("quanzhou"))
	var fame0 := int(gs.fame)
	var m0 := int(gs.money)
	var r: Dictionary = _apply("npc_zhubo_deliver", "temple")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhubo_temple") and Book.favour_of("quanzhou") == f0 + 2 and int(gs.fame) == fame0 + 1 and int(gs.money) == m0 and not gs.has_flag("npc_zhubo_broker"), "祝伯：交顺济宫得泉州人情与名声")
	_fresh()
	ready = _ok("npc_zhubo_ask") and _ok("npc_zhubo_letter") and _ok("npc_zhubo_wind")
	var n0 := int(gs.network)
	m0 = int(gs.money)
	r = _apply("npc_zhubo_deliver", "broker")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhubo_broker") and int(gs.network) == n0 + 2 and int(gs.money) == m0 + 60 and Book.favour_of("quanzhou") == 0 and not gs.has_flag("npc_zhubo_temple"), "祝伯：转蕃坊得人脉与六十钱")


func _arc_cairong() -> void:
	_fresh()
	_check(_blocked("npc_cairong_evidence", "还没到那一步"), "蔡荣：未见面时查纳屋不可办")
	_check(_blocked("npc_cairong_settle", "还没到那一步", "expose"), "蔡荣：未查纳屋时报与不报不可办")
	_check(_ok("npc_cairong_meet") and gs.has_flag("npc_cairong_met"), "蔡荣：初见留 flag")
	_check(_ok("npc_cairong_evidence") and gs.has_flag("npc_cairong_evidence"), "蔡荣：查纳屋留 flag")
	_fresh()
	var ready := _ok("npc_cairong_meet") and _ok("npc_cairong_evidence")
	var fame0 := int(gs.fame)
	var f0: int = int(Book.favour_of("hakata"))
	var n0 := int(gs.network)
	var r: Dictionary = _apply("npc_cairong_settle", "expose")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_cairong_exposed") and int(gs.fame) == fame0 + 2 and Book.favour_of("hakata") == f0 + 1 and int(gs.network) == n0 and not gs.has_flag("npc_cairong_covered"), "蔡荣：报大宰府得名声与博多人情")
	_fresh()
	ready = _ok("npc_cairong_meet") and _ok("npc_cairong_evidence")
	n0 = int(gs.network)
	var c0 := int(gs.merchant_credit)
	r = _apply("npc_cairong_settle", "cover")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_cairong_covered") and int(gs.network) == n0 + 2 and int(gs.merchant_credit) == c0 + 1 and not gs.has_flag("npc_cairong_exposed"), "蔡荣：遮下得人脉与海商信用")


func _arc_zhouxing() -> void:
	_fresh(1259, 11, 1)
	_check(_blocked("npc_zhouxing_rumor", "还没到那一步"), "周行：未见面时听两种说法不可办")
	_check(_blocked("npc_zhouxing_bet", "还没到那一步", "peace"), "周行：未听说法时押一句不可办")
	_check(_ok("npc_zhouxing_meet") and gs.has_flag("npc_zhouxing_met"), "周行：初见留 flag")
	_check(_ok("npc_zhouxing_rumor") and gs.has_flag("npc_zhouxing_heard"), "周行：听两种说法留 flag")
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_check(_blocked("npc_zhouxing_bet", "年份未到", "peace"), "周行：1255 年押一句不可办")
	cal.from_dict({"year": 1259, "month": 9, "day": 1})
	_check(_blocked("npc_zhouxing_bet", "还不是这个月的事", "peace"), "周行：1259 年九月押一句不可办")
	cal.from_dict({"year": 1259, "month": 11, "day": 1})
	_check(_ok("npc_zhouxing_bet", "peace"), "周行：1259 年十一月押一句可办")
	_fresh(1259, 11, 1)
	var ready := _ok("npc_zhouxing_meet") and _ok("npc_zhouxing_rumor")
	var m0 := int(gs.money)
	var c0 := int(gs.merchant_credit)
	var s0 := int(gs.scholar_tendency)
	var r: Dictionary = _apply("npc_zhouxing_bet", "peace")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhouxing_peace") and int(gs.money) == m0 - 30 + 90 and int(gs.merchant_credit) == c0 + 1 and int(gs.scholar_tendency) == s0 and not gs.has_flag("npc_zhouxing_war"), "周行：押和议得九十钱与海商信用")
	_fresh(1259, 11, 1)
	ready = _ok("npc_zhouxing_meet") and _ok("npc_zhouxing_rumor")
	m0 = int(gs.money)
	s0 = int(gs.scholar_tendency)
	var fame0 := int(gs.fame)
	r = _apply("npc_zhouxing_bet", "war")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhouxing_war") and int(gs.money) == m0 - 30 and int(gs.scholar_tendency) == s0 + 2 and int(gs.fame) == fame0 + 1 and not gs.has_flag("npc_zhouxing_peace"), "周行：押兵事得学者与名声")


func _arc_liang() -> void:
	_fresh()
	_check(_blocked("npc_liang_tide", "还没到那一步"), "梁阿水：未闻沉船时等潮不可办")
	_check(_blocked("npc_liang_dive", "还没到那一步", "push"), "梁阿水：未等潮时去不去不可办")
	_check(_ok("npc_liang_wreck") and gs.has_flag("npc_liang_met"), "梁阿水：闻沉船留 flag")
	_check(_ok("npc_liang_tide") and gs.has_flag("npc_liang_tide"), "梁阿水：等潮留 flag")
	_fresh()
	var ready := _ok("npc_liang_wreck") and _ok("npc_liang_tide")
	var m0 := int(gs.money)
	var c0 := int(gs.merchant_credit)
	var r: Dictionary = _apply("npc_liang_dive", "push")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_liang_lost") and int(gs.money) == m0 + 90 and int(gs.merchant_credit) == c0 - 1 and not gs.has_flag("npc_liang_saved"), "梁阿水：今夜就去得九十钱，信用减一")
	_fresh()
	ready = _ok("npc_liang_wreck") and _ok("npc_liang_tide")
	var n0 := int(gs.network)
	var s0 := int(gs.sea_tendency)
	m0 = int(gs.money)
	r = _apply("npc_liang_dive", "wait")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_liang_saved") and int(gs.network) == n0 + 2 and int(gs.sea_tendency) == s0 + 1 and int(gs.money) == m0 and not gs.has_flag("npc_liang_lost"), "梁阿水：等风平得人脉与海路")


func _arc_zhengyan() -> void:
	_fresh()
	_check(_blocked("npc_zhengyan_ledger", "还没到那一步"), "郑堰：未见面时对水租簿不可办")
	_check(_blocked("npc_zhengyan_invest", "还没到那一步"), "郑堰：未对簿时认修陂工不可办")
	_check(_blocked("npc_zhengyan_split", "还没到那一步", "weir"), "郑堰：未认工时分水租不可办")
	_check(_ok("npc_zhengyan_meet") and gs.has_flag("npc_zhengyan_met"), "郑堰：初见留 flag")
	_check(_ok("npc_zhengyan_ledger") and gs.has_flag("npc_zhengyan_ledger"), "郑堰：对水租簿留 flag")
	_fresh()
	var ready := _ok("npc_zhengyan_meet") and _ok("npc_zhengyan_ledger")
	var costs: Array = Book.interaction("npc_zhengyan_invest").get("costs", [])
	var monthly: Array = Book.interaction("npc_zhengyan_invest").get("monthly", [])
	var m0 := int(gs.money)
	var inv: Dictionary = _apply("npc_zhengyan_invest")
	_check(ready and bool(inv.get("ok", false)) and gs.has_flag("npc_zhengyan_invested") and Book.level_of("npc_zhengyan_invest") == 1 and int(gs.money) == m0 - int(costs[0]), "郑堰：认修陂工入本一级")
	var after := int(gs.money)
	var notice: String = Book.month_tick()
	_check(int(gs.money) == after + int(monthly[0]) and notice.contains("修陂工入账 %d 钱" % int(monthly[0])), "郑堰：修陂工按月入账")
	_fresh()
	ready = _ok("npc_zhengyan_meet") and _ok("npc_zhengyan_ledger") and _ok("npc_zhengyan_invest")
	m0 = int(gs.money)
	var h0 := int(gs.hometown_tendency)
	var f0: int = int(Book.favour_of("xinghua"))
	var r: Dictionary = _apply("npc_zhengyan_split", "weir")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhengyan_weir") and int(gs.hometown_tendency) == h0 + 2 and Book.favour_of("xinghua") == f0 + 2 and int(gs.money) == m0 and not gs.has_flag("npc_zhengyan_share"), "郑堰：留作堰工得乡土与兴化人情")
	_fresh()
	ready = _ok("npc_zhengyan_meet") and _ok("npc_zhengyan_ledger") and _ok("npc_zhengyan_invest")
	m0 = int(gs.money)
	var c0 := int(gs.merchant_credit)
	var h0b := int(gs.hometown_tendency)
	r = _apply("npc_zhengyan_split", "share")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_zhengyan_share") and int(gs.money) == m0 + 80 and int(gs.merchant_credit) == c0 + 1 and int(gs.hometown_tendency) == h0b and not gs.has_flag("npc_zhengyan_weir"), "郑堰：按契分得八十钱与海商信用")


func _arc_xudai() -> void:
	_fresh()
	_check(_blocked("npc_xudai_contract", "还没到那一步"), "许岱：未见面时立盐契不可办")
	_check(_blocked("npc_xudai_bargain", "年份未到", "old"), "许岱：1255 年盐价不可议")
	_check(_ok("npc_xudai_meet") and gs.has_flag("npc_xudai_met"), "许岱：初见留 flag")
	_check(_ok("npc_xudai_contract") and gs.has_flag("npc_xudai_contract"), "许岱：立盐契留 flag")
	cal.from_dict({"year": 1276, "month": 10, "day": 1})
	_check(_blocked("npc_xudai_bargain", "眼下的战况不对", "old"), "许岱：1276 年十月太平不可议价")
	cal.from_dict({"year": 1276, "month": 11, "day": 1})
	_check(_ok("npc_xudai_bargain", "old"), "许岱：1276 年十一月围城可议价")
	_fresh(1276, 12, 1)
	var ready := _ok("npc_xudai_meet") and _ok("npc_xudai_contract")
	var h0 := int(gs.hometown_tendency)
	var f0: int = int(Book.favour_of("xinghua"))
	var m0 := int(gs.money)
	var r: Dictionary = _apply("npc_xudai_bargain", "old")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_xudai_oldprice") and int(gs.hometown_tendency) == h0 + 2 and Book.favour_of("xinghua") == f0 + 2 and int(gs.money) == m0 and not gs.has_flag("npc_xudai_guanzi"), "许岱：认旧价得乡土与兴化人情")
	_fresh(1276, 12, 1)
	ready = _ok("npc_xudai_meet") and _ok("npc_xudai_contract")
	m0 = int(gs.money)
	var c0 := int(gs.merchant_credit)
	var h0b := int(gs.hometown_tendency)
	r = _apply("npc_xudai_bargain", "paper")
	_check(ready and bool(r.get("ok", false)) and gs.has_flag("npc_xudai_guanzi") and int(gs.money) == m0 + 100 and int(gs.merchant_credit) == c0 + 1 and int(gs.hometown_tendency) == h0b and not gs.has_flag("npc_xudai_oldprice"), "许岱：折关子得一百钱与海商信用")
	_fresh(1277, 3, 1)
	ready = _ok("npc_xudai_meet") and _ok("npc_xudai_contract")
	_check(ready and _blocked("npc_xudai_bargain", "眼下的战况不对", "old"), "许岱：1277 年三月复归太平不可议价")


func _save_roundtrip() -> void:
	_fresh()
	var flags := [
		"npc_maruding_met", "npc_maruding_ledger", "npc_maruding_forgiven", "npc_maruding_paid",
		"npc_zhubo_asked", "npc_zhubo_letter", "npc_zhubo_carry", "npc_zhubo_temple", "npc_zhubo_broker",
		"npc_cairong_met", "npc_cairong_evidence", "npc_cairong_exposed", "npc_cairong_covered",
		"npc_zhouxing_met", "npc_zhouxing_heard", "npc_zhouxing_peace", "npc_zhouxing_war",
		"npc_liang_met", "npc_liang_tide", "npc_liang_lost", "npc_liang_saved",
		"npc_zhengyan_met", "npc_zhengyan_ledger", "npc_zhengyan_invested", "npc_zhengyan_weir", "npc_zhengyan_share",
		"npc_xudai_met", "npc_xudai_contract", "npc_xudai_oldprice", "npc_xudai_guanzi",
	]
	for f in flags:
		gs.set_flag(str(f))
	var raw := JSON.stringify(gs.to_dict())
	var back = JSON.parse_string(raw)
	gs.from_dict(back)
	var missing: Array[String] = []
	for f in flags:
		if not gs.has_flag(str(f)):
			missing.append(str(f))
	_check(missing.is_empty(), "存档：三十枚 NPC flag 来回不丢（缺 %d）" % missing.size())
