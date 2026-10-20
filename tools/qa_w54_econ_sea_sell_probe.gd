extends SceneTree
## lane w54-econ：headless 探针——海上「靠来一条空舱的船」只收货，不收账物。
## 序章林阿舶交的唐房寄物 / 硫黄旧账 / 货单押字是 goods.json 里 tradable=false 的账物（scenes.json 的 cargo 效果装进舱，成本 0）。
## 原先 Voyage._merchant_event 收货那一支从全舱随手挑一样开价，账物也挑：哪港都不收它，价按成本 0 落到「每件 1 钱」，
## 点「卖」就把寄物卖掉了。改后这一支只挑 tradable 的舱货，价格式子（sea_sell_unit）不动。
##   一、舱里只有三样账物：同种子 400 回海上相逢，没有一回开价收账物（改前约一半回开价，每件 1 钱）。
##   二、三样账物 + 青白瓷 5 件：开价收的回回是青白瓷（改前约四分之三挑到账物），件数 1–4、不超过舱里，单价落在 sea_sell_unit 的
##       成本 × 浮动区间里且不过最好消费地卖价九二折；确有开价（防空转）。
##   三、只装账物与空舱同种子逐回比：给的路数、货、件数、价、正文一字不差——账物不占「收货」那一支。
##   四、在身委办要交的货（GameState.contract_kept，牙行「委办货不上秤，要卖先毁约」；海上毁不了约）：舱里恰是委办那 16 件，
##       400 回不开价收、与空舱同种子逐回一字不差；多出 2 件，开价至多收 2 件（改前照收 1–4 件，交货时就短了）。
## 用法：godot --headless --path . -s res://tools/qa_w54_econ_sea_sell_probe.gd（经门锁跑）
## 输出末行 W54_ECON_SEA_SELL_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_rumor_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

const ROUNDS := 400
const SEED := 20261020
const LEDGER_GOODS := ["tangfang_parcel", "sulfur_ledger", "cargo_manifest_signature"]
const TRADE_GOOD := "qingbai_porcelain"
const TRADE_QTY := 5
const TRADE_COST := 40.0

var voyage: Node
var fleet: Node
var gm: Node
var gs: Node
var cases := 0
var fails := 0
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
	await process_frame
	voyage = root.get_node_or_null("Voyage")
	fleet = root.get_node_or_null("Fleet")
	gm = root.get_node_or_null("GameManager")
	gs = root.get_node_or_null("GameState")
	if voyage == null or fleet == null or gm == null or gs == null:
		_expect(false, "autoload Voyage / Fleet / GameManager / GameState 都在")
		_report()
		return
	var saved: Dictionary = fleet.to_dict().duplicate(true)
	fleet.water = 0
	fleet.food = 0
	for gid in LEDGER_GOODS:
		_expect(not bool(gm.get_good_by_id(gid).get("tradable", true)), "前提：%s 在 goods.json 里是 tradable=false 的账物" % gid)
	_expect(bool(gm.get_good_by_id(TRADE_GOOD).get("tradable", false)), "前提：%s 是可交易的货" % TRADE_GOOD)

	_ledger_only()
	_ledger_and_goods()
	_same_as_empty()
	_contract_kept()

	fleet.from_dict(saved)
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_ECON_SEA_SELL_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


## 舱里只摆这几样（旗舰一艘），账物各 1 件、成本 0（与 Main.apply_effects 的 cargo 效果同）
func _stock(with_goods: bool, with_ledgers: bool) -> void:
	fleet.clear_cargo()
	if with_ledgers:
		for gid in LEDGER_GOODS:
			fleet.add_cargo(gid, 1, 0.0, 0)
	if with_goods:
		fleet.add_cargo(TRADE_GOOD, TRADE_QTY, TRADE_COST, 0)


## 同种子连抽 ROUNDS 回海上相逢，返回各回的事件
func _roll_events() -> Array:
	seed(SEED)
	var out: Array = []
	for _i in ROUNDS:
		out.append(voyage.call("_merchant_event", "quanzhou"))
	return out


func _ledger_only() -> void:
	_stock(false, true)
	var held := 0
	for gid in LEDGER_GOODS:
		held += int(fleet.cargo_qty(gid))
	_expect(held == LEDGER_GOODS.size(), "一、三样账物各 1 件装进舱（实装 %d 件）" % held)
	var bad := 0
	var sample := ""
	for ev in _roll_events():
		if str(ev.get("offer", "")) == "sell":
			bad += 1
			if sample == "":
				sample = "%s ×%d 每件 %d" % [gm.get_good_name(str(ev.get("good_id", ""))), int(ev.get("qty", 0)), int(ev.get("unit", 0))]
	_expect(bad == 0, "一、舱里只有账物：%d 回海上相逢没有一回开价收账物（实有 %d 回%s）" % [
		ROUNDS, bad, "，如「%s」" % sample if sample != "" else ""])


func _ledger_and_goods() -> void:
	_stock(true, true)
	var best: int = int(voyage.call("_best_consumer_sell", TRADE_GOOD))
	var cap := maxi(1, int(float(best) * float(voyage.get("SEA_SELL_CAP"))))
	var lo := mini(int(round(TRADE_COST * float(voyage.get("SEA_SELL_JITTER_MIN")))), cap)
	var hi := mini(int(round(TRADE_COST * float(voyage.get("SEA_SELL_JITTER_MAX")))), cap)
	var sells := 0
	var wrong_good := 0
	var wrong_qty := 0
	var wrong_unit := 0
	var sample := ""
	for ev in _roll_events():
		if str(ev.get("offer", "")) != "sell":
			continue
		sells += 1
		var gid := str(ev.get("good_id", ""))
		var qty := int(ev.get("qty", 0))
		var unit := int(ev.get("unit", 0))
		if gid != TRADE_GOOD:
			wrong_good += 1
			if sample == "":
				sample = "%s ×%d 每件 %d" % [gm.get_good_name(gid), qty, unit]
		elif qty < 1 or qty > mini(4, TRADE_QTY):
			wrong_qty += 1
		elif unit < lo or unit > hi:
			wrong_unit += 1
	_expect(sells > 0, "二、账物 + %s %d 件：%d 回里确有开价收货（%d 回）" % [gm.get_good_name(TRADE_GOOD), TRADE_QTY, ROUNDS, sells])
	_expect(wrong_good == 0, "二、开价收的回回是%s，不挑账物（挑错 %d 回%s）" % [
		gm.get_good_name(TRADE_GOOD), wrong_good, "，如「%s」" % sample if sample != "" else ""])
	_expect(wrong_qty == 0, "二、收的件数 1–%d、不超过舱里（越界 %d 回）" % [mini(4, TRADE_QTY), wrong_qty])
	_expect(wrong_unit == 0, "二、单价落在成本 %d × 浮动 = %d–%d（最好消费地卖价 %d 的九二折 %d 封顶）里（越界 %d 回）" % [
		int(TRADE_COST), lo, hi, best, cap, wrong_unit])


func _same_as_empty() -> void:
	_stock(false, false)
	var empty := _roll_events()
	_stock(false, true)
	var ledgers := _roll_events()
	var diff := 0
	var first := -1
	for i in ROUNDS:
		if JSON.stringify(empty[i]) != JSON.stringify(ledgers[i]):
			diff += 1
			if first < 0:
				first = i
	var note := ""
	if first >= 0:
		note = "，头一处第 %d 回：空舱「%s」、账物「%s」" % [first + 1, str(empty[first].get("offer", "")), str(ledgers[first].get("offer", ""))]
	_expect(diff == 0, "三、只装账物与空舱同种子 %d 回逐回一字不差（不同 %d 回%s）" % [ROUNDS, diff, note])


const CONTRACT_GOOD := "fujian_porcelain"
const CONTRACT_QTY := 16


func _contract_kept() -> void:
	var saved_contract: Dictionary = (gs.contract as Dictionary).duplicate(true)
	gs.contract = {
		"good_id": CONTRACT_GOOD, "qty": CONTRACT_QTY, "remaining": CONTRACT_QTY, "dest": "penghu", "from": "quanzhou",
		"purse": 1600, "unit_purse": 100.0, "paid": 0, "due_day": 999999, "deadline_days": 8, "voyage_days": 5, "offer_month": 0,
	}
	fleet.clear_cargo()
	fleet.add_cargo(CONTRACT_GOOD, CONTRACT_QTY, 40.0, 0)
	_expect(int(gs.contract_kept(CONTRACT_GOOD)) == CONTRACT_QTY,
		"四、前提：在身委办要%s %d 件，舱里恰 %d 件，全数留着交货（contract_kept = %d）" % [
			gm.get_good_name(CONTRACT_GOOD), CONTRACT_QTY, CONTRACT_QTY, int(gs.contract_kept(CONTRACT_GOOD))])
	var kept_bids := 0
	for ev in _roll_events():
		if str(ev.get("offer", "")) == "sell" and str(ev.get("good_id", "")) == CONTRACT_GOOD:
			kept_bids += 1
	_expect(kept_bids == 0, "四、舱里只有委办要交的货：%d 回没有一回开价收它（实有 %d 回）" % [ROUNDS, kept_bids])
	var kept_events := _roll_events()
	fleet.clear_cargo()
	var empty := _roll_events()
	var diff := 0
	for i in ROUNDS:
		if JSON.stringify(empty[i]) != JSON.stringify(kept_events[i]):
			diff += 1
	_expect(diff == 0, "四、只装委办要交的货与空舱同种子 %d 回逐回一字不差（不同 %d 回）" % [ROUNDS, diff])
	fleet.add_cargo(CONTRACT_GOOD, CONTRACT_QTY + 2, 40.0, 0)
	var bids := 0
	var over := 0
	var most := 0
	for ev in _roll_events():
		if str(ev.get("offer", "")) != "sell" or str(ev.get("good_id", "")) != CONTRACT_GOOD:
			continue
		bids += 1
		most = maxi(most, int(ev.get("qty", 0)))
		if int(ev.get("qty", 0)) > 2:
			over += 1
	_expect(bids > 0 and over == 0,
		"四、委办之外多出 2 件：%d 回开价收它，件数至多 2（最多开 %d 件，超出 %d 回）" % [bids, most, over])
	gs.contract = saved_contract
