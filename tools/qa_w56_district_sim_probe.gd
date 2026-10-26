extends SceneTree
## lane w56 城中各处深化探针（headless，经门锁跑）。
const TAG := "QA_W56_DISTRICT_SIM"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var Book
var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
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
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	Book = load("res://scripts/core/Districts.gd")
	if Book == null:
		_check(false, "城区账本没载入")
		_report()
		return
	_stage_boot()
	print("== 链 ==")
	_sec_chain()
	print("== 大比 ==")
	_sec_exam()
	print("== 季节 ==")
	_sec_season()
	print("== 风险 ==")
	_sec_risk()
	print("== 入股 ==")
	_sec_invest()
	print("== 传闻 ==")
	_sec_rumor()
	_report()

func _stage_boot() -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou", "guangzhou", "wenzhou", "hakata"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.last_port = "quanzhou"
	Book.wipe()

func _fresh() -> void:
	Book.wipe()
	gs.money = 30000
	gs.contract = {}
	gs.siege = {}
	gs.flags = {}
	gs.identity = "undecided"
	gs.player_name = "陈子龙"
	gs.pu_attention = 0
	gs.merchant_credit = 0
	gs.scholar_tendency = 0
	gs.hometown_tendency = 0
	gs.network = 0
	gs.fame = 0
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	cal.from_dict({"year": 1255, "month": 3, "day": 1})

func _sec_chain() -> void:
	_fresh()
	var r1: Dictionary = Book.apply("qz_houzhu_pilot")
	_check(bool(r1.get("ok", false)) and gs.has_flag("qz_houzhu_pilot"), "链：后渚请梢公记下旗")
	var before: Dictionary = Book.apply("qz_houzhu_fast")
	# before flag? we set flag above, so should succeed; test lack flag by wiping flag only
	gs.flags = {}
	var noflag: Dictionary = Book.apply("qz_houzhu_fast")
	_check(not bool(noflag.get("ok", false)) and str(noflag.get("msg", "")) == "还没到那一步", "链：没有旗，托梢公收盐办不成")
	gs.set_flag("qz_houzhu_pilot")
	var ok: Dictionary = Book.apply("qz_houzhu_fast")
	_check(bool(ok.get("ok", false)), "链：有了旗，托梢公收盐成")
	# Wenzhou academy patron chain
	_fresh()
	var patron: Dictionary = Book.apply("wz_academy_donate")
	_check(bool(patron.get("ok", false)) and gs.has_flag("wz_academy_patron"), "链：永嘉书院助书记下旗")
	var buy: Dictionary = Book.apply("wz_shop_buy2")
	_check(bool(buy.get("ok", false)), "链：有了旗，熟客价收漆盒成")

func _sec_exam() -> void:
	_fresh()
	cal.from_dict({"year": 1268, "month": 9, "day": 1})
	gs.identity = "scholar"
	gs.player_name = "陈文龙"
	gs.set_flag("renamed_wenlong")
	var aid: Dictionary = Book.apply("qz_bang_aid", "give")
	_check(bool(aid.get("ok", false)) and gs.has_flag("qz_bang_print") and int(gs.fame) > 0, "大比：助寒士记旗、名声加")
	var printbuy: Dictionary = Book.apply("qz_kaiyuan_print")
	_check(bool(printbuy.get("ok", false)), "大比：印本经按熟价成")
	# exam-year choice pass option
	_fresh()
	cal.from_dict({"year": 1268, "month": 9, "day": 1})
	var passr: Dictionary = Book.apply("xh_bang_aid", "pass")
	_check(bool(passr.get("ok", false)), "大比：旁观也成")

func _sec_season() -> void:
	_fresh()
	cal.from_dict({"year": 1255, "month": 6, "day": 1})
	var money0 := int(gs.money)
	var r: Dictionary = Book.apply("xh_lychee_price", "fresh")
	_check(bool(r.get("ok", false)) and int(gs.money) == money0 + 40, "季节：六月鲜果出手，钱入账")
	# winter month should not allow
	_fresh()
	cal.from_dict({"year": 1255, "month": 12, "day": 1})
	var bad: Dictionary = Book.apply("xh_lychee_price", "fresh")
	_check(not bool(bad.get("ok", false)), "季节：十二月鲜果价不成")

func _sec_risk() -> void:
	_fresh()
	var pu0 := int(gs.pu_attention)
	var cargo0 := int(fleet.cargo_qty("ironware"))
	var r: Dictionary = Book.apply("xh_smith_make", "make")
	_check(bool(r.get("ok", false)) and int(gs.pu_attention) == pu0 + 2 and fleet.cargo_qty("ironware") == cargo0 + 2, "风险：打铁加留意、进舱")
	_fresh()
	var r2: Dictionary = Book.apply("xh_smith_make", "no")
	_check(bool(r2.get("ok", false)), "风险：不打也成")

func _sec_invest() -> void:
	var ix: Dictionary = Book.interaction("wz_mochi_shop")
	var costs: Array = ix.get("costs", [])
	var monthly: Array = ix.get("monthly", [])
	var payback := float(costs[0]) / float(monthly[0])
	_check(costs.size() == monthly.size() and payback >= 18.0, "入股：小卖 payback %.1f 月" % payback)
	_fresh()
	var inv: Dictionary = Book.apply("wz_mochi_shop")
	var pay := int(ix.get("monthly", [0])[0])
	var before := int(gs.money)
	var notices: Array = eco.on_month_changed()
	var joined := ""
	for line in notices:
		joined += str(line)
	_check(bool(inv.get("ok", false)) and Book.level_of("wz_mochi_shop") == 1 and int(gs.money) - before == pay and joined.contains("入账"), "入股：小卖月初入账")

func _sec_rumor() -> void:
	_fresh()
	var tea0 := float(eco.rates["hakata"]["tea"])
	var r: Dictionary = Book.apply("qz_citong_rumor")
	_check(bool(r.get("ok", false)), "传闻：听茶价成")
	# new wager rumor
	_fresh()
	var base := float(eco.rates["hakata"]["silk_fabric"]) if eco.rates["hakata"].has("silk_fabric") else 0.0
	# ensure rate key exists
	var heard: Dictionary = Book.apply("qz_jubao_wager", "bet")
	_check(bool(heard.get("ok", false)), "传闻：押一注成")
