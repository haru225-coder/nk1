extends SceneTree
## Lane sim4：牙人赊销探针——锁价贴水、舱货移除、 receivable 入簿、到期结清、读档往返。
## 用法：godot --headless --path . -s res://tools/qa_w57_credit_probe.gd
## 输出末行 CREDIT_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var eco: Node
var cal: Node
var gs: Node
var fleet: Node
var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	eco = root.get_node_or_null("Economy")
	cal = root.get_node_or_null("Calendar")
	gs = root.get_node_or_null("GameState")
	fleet = root.get_node_or_null("Fleet")
	if eco == null or cal == null or gs == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()

	var saved_month: int = cal.month
	var saved_year: int = cal.year
	var saved_day: int = cal.day

	_expect(eco.has_method("credit_sale_price"), "Economy.credit_sale_price 存在")
	_expect(gs.has_method("sell_on_credit"), "GameState.sell_on_credit 存在")
	_expect(gs.has_method("settle_broker_credit"), "GameState.settle_broker_credit 存在")

	var spot: int = eco.estimate_sell_revenue("quanzhou", "tea", 1)
	var credit1: int = eco.credit_sale_price("quanzhou", "tea")
	_expect(credit1 == maxi(1, int(round(float(spot) * 1.08))), "赊一件锁价 = 现卖实得 × 1.08（%d vs %d）" % [credit1, spot])
	var rev3: int = eco.estimate_sell_revenue("quanzhou", "tea", 3)
	var credit: int = eco.credit_sale_price("quanzhou", "tea", 3)
	_expect(credit == maxi(1, int(round(float(rev3) / 3.0 * 1.08))), "赊三件按逐件压价均价加贴水（%d vs %d/3）" % [credit, rev3])
	var rev30: int = eco.estimate_sell_revenue("quanzhou", "tea", 30)
	_expect(eco.credit_sale_price("quanzhou", "tea", 30) * 30 <= int(ceil(float(rev30) * 1.08)) + 30, "赊多了同样压价，不成套利")

	fleet.add_cargo("tea", 5, 1.0)
	var before_qty: int = fleet.cargo_qty("tea")
	gs.money = 1000
	var res: Dictionary = gs.sell_on_credit("quanzhou", "tea", 3)
	_expect(bool(res.get("ok", false)), "赊销 3 件茶成功")
	_expect(fleet.cargo_qty("tea") == before_qty - 3, "赊销后舱里少 3 件")
	_expect(gs.broker_credit.size() == 1, "赊销簿添一笔")
	var entry: Dictionary = gs.broker_credit[0]
	_expect(int(entry.get("qty", 0)) == 3, "赊销簿件数 3")
	_expect(int(entry.get("unit_price", 0)) == credit, "赊销簿锁价 %d" % credit)
	_expect(int(entry.get("due_ym", 0)) == gs.broker_credit_due_ym(), "赊销簿到期月对")
	_expect(gs.broker_credit_outstanding() == 3 * credit, "未结本金 %d" % (3 * credit))

	var bad: Dictionary = gs.sell_on_credit("quanzhou", "tea", 999)
	_expect(not bool(bad.get("ok", false)), "舱里不够时赊销拒收")

	var d: Dictionary = gs.to_dict()
	gs.broker_credit = []
	gs.from_dict(d)
	_expect(gs.broker_credit.size() == 1, "读档恢复赊账")

	var due: int = int(entry.get("due_ym", 0))
	var due_month: int = due % 12
	if due_month == 0:
		due_month = 12
	var due_year: int = (due - due_month) / 12
	cal.year = due_year
	cal.month = due_month
	cal.day = 1
	var lines: Array = gs.settle_broker_credit()
	_expect(gs.broker_credit.is_empty(), "到期赊账结清（%d 行）" % lines.size())
	_expect(lines.size() == 1, "到期有且一行通告")

	cal.month = saved_month
	cal.year = saved_year
	cal.day = saved_day
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("CREDIT_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
