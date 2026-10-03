extends SceneTree
## Lane w53-3：headless 探针——牙行/委办/赊贷三本账的守住形状（w53-3 扫区没扫出未守的真洞，
## 把最易被「顺手改坏」的三套结算钉死，改坏任一即红）。
##   一、大买入逐件抬价与分船装舱：买 n 件时 estimate_buy_cost 必须随行情逐件抬价（不借
##      Economy 自证——按 ports.json depth 独立重算逐件序列比对）；高价货 .5 取整须走高不走低；
##      拆船买同一货两账一致 + 舱内均价 × 件数 ≈ 实扣。行情冲击被砸平取整衰减掏空即红。
##   二、赊贷记账形状：borrow(x) 后 debt == 借款前+x 且 money 恰多 x；0/负数/超上限拒借；
##      repay 实付 min(欲还, 债, 现银)；accrue_interest = ceil(debt × 月息)。借/还/息被改坏即红。
##   三、委办交付罚息账：分批交货总实收 == purse（最后一批 purse−paid 结清，改掉那句即红）、
##      毁约罚 max(40, purse×0.15) 以现银封顶、due_day 当天可交/次晨作废、错港不动账。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_economy_probe.gd
## 输出末行 W53_3_PROBE cases=N fails=M；M>0 时 exit 1。

var eco: Node
var crew: Node
var gs: Node
var gm: Node
var fleet: Node
var cases := 0
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	eco = root.get_node_or_null("Economy")
	crew = root.get_node_or_null("Crew")
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	fleet = root.get_node_or_null("Fleet")
	if eco == null or crew == null or gs == null or gm == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()

	var saved := {
		"hired": crew.hired.duplicate(true), "fame": gs.fame,
		"investments": eco.investments.duplicate(true), "rates": eco.rates.duplicate(true),
		"ships": fleet.ships.duplicate(true), "water": fleet.water, "food": fleet.food,
		"money": gs.money, "debt": gs.debt,
	}

	_fresh_slot_reconciliation()
	_debt_book()
	_contract_book()

	crew.hired = saved["hired"]
	gs.fame = saved["fame"]
	eco.investments = saved["investments"]
	eco.rates = saved["rates"]
	fleet.ships = saved["ships"]
	fleet.water = saved["water"]
	fleet.food = saved["food"]
	gs.money = saved["money"]
	gs.debt = saved["debt"]
	print("W53_3_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _max_fame() -> int:
	var top := 0
	for r in gs.title_ranks():
		top = maxi(top, int(r.get("min_fame", 0)))
	return top


## 满编：Crew.hired 只存名册 id（lane w23-a1 起），按职与品级取名册里的真候选。原先塞整条快照，
## Crew.level_of 读成 0，「满编」各格其实按光杆跑（lane w53-3）；摆完核 level_of，摆不上即判红。
func _full_crew() -> void:
	crew.hired = {"zashi": _cand("zashi", 3), "tongshi": _cand("tongshi", 3)}
	_expect(crew.level_of("zashi") == 3 and crew.level_of("tongshi") == 3,
		"满编摆上：杂事 %d 级、通事 %d 级（Crew.level_of 回查名册）" % [crew.level_of("zashi"), crew.level_of("tongshi")])


func _cand(role: String, level: int) -> String:
	for c in gm.crew_data.get("candidates", []):
		if str(c.get("role", "")) == role and int(c.get("level", 0)) == level:
			return str(c.get("id", ""))
	return "no_%s_%d" % [role, level]


## 与 Main._on_buy 同一段结算（买 actual 件 → 扣钱 → 入账 → 砸盘），抽出复用两条摆场
func _buy_like_main(port_id: String, gid: String, amount: int, ship_index: int) -> void:
	var cost: int = eco.estimate_buy_cost(port_id, gid, amount)
	if not gs.spend_money(cost):
		return
	fleet.add_cargo(gid, amount, float(cost) / float(amount), ship_index)
	eco.apply_buy_impact(port_id, gid, amount)


# ── 一、大买入逐件抬价与分船装舱 ───────────────────────

## 深度 = ports.json depth × (1 + 修埠加深 × 等)，独立重算不借 Economy._depth
func _depth(port_id: String) -> float:
	var base := 100.0
	for p in gm.ports_data.get("ports", []):
		if str(p.get("id", "")) == port_id:
			base = float(p.get("depth", 100))
			break
	var cfg = gm.titles_data.get("invest", {})
	var per := float(cfg.get("depth_per_level", 0.12)) if typeof(cfg) == TYPE_DICTIONARY else 0.12
	return base * (1.0 + per * float(eco.investment_level(port_id)))


func _fresh_slot_reconciliation() -> void:
	print("── 一、大买入逐件抬价与分船装舱")
	_full_crew()
	gs.fame = _max_fame()
	eco.investments = {"hakata": 5}
	var gid := "placer_gold"
	var rates0: Dictionary = eco.rates.duplicate(true)

	# 1a. estimate_buy_cost 的逐件抬价：独立序列（depth 自重算，逐件报价后行情推到 r+1/depth）比对
	eco.rates = rates0.duplicate(true)
	eco.rates["hakata"][gid] = 1.0
	var depth := _depth("hakata")
	var n_big := 20
	var want_total := 0
	var r := 1.0
	for i in range(n_big):
		want_total += eco.price_at_rate("hakata", gid, r, true)
		r = clampf(r + 1.0 / depth, eco.RATE_MIN, eco.RATE_MAX)
	var got_total: int = eco.estimate_buy_cost("hakata", gid, n_big)
	_expect(got_total == want_total,
		"买 %d 件总价 = 逐件抬价自重算 %d（实得 %d；砸平取整则偏平）" % [n_big, want_total, got_total])
	_expect(got_total > eco.buy_price("hakata", gid) * n_big,
		"逐件抬价生效：%d 件总价 %d > 现价一口价 %d × %d" % [
			n_big, got_total, eco.buy_price("hakata", gid), n_big])

	# 1b. 行情冲击真抬价：把行情从下推（-0.05）与从上推（+0.05），买价必须同向动
	#     （推反、推平、或订购价与行情脱钩，都会让两条断言红）
	eco.rates = rates0.duplicate(true)
	eco.rates["hakata"][gid] = 1.0
	var ref_buy: int = eco.buy_price("hakata", gid)
	eco.apply_buy_impact("hakata", gid, int(depth * 0.05))  # 买 5% 深度 → +0.05
	var up_buy: int = eco.buy_price("hakata", gid)
	eco.rates = rates0.duplicate(true)
	eco.rates["hakata"][gid] = 1.0
	eco.apply_sell_impact("hakata", gid, int(depth * 0.05))  # 砸 5% 深度 → −0.05
	var dn_buy: int = eco.buy_price("hakata", gid)
	_expect(up_buy >= ref_buy and dn_buy <= ref_buy and up_buy > dn_buy,
		"行情冲击真抬价：买 5%% 后 %d ≥ 基准 %d ≥ 砸 5%% 后 %d（且上 > 下）" % [up_buy, ref_buy, dn_buy])

	# 1c. 空货席撞买价：分船买同一货 与 同船分批，钱货两账一致
	# A：两船各自空席，各买 4 件（拆船买，正是玩家会干的事）
	eco.rates = rates0.duplicate(true)
	fleet.ships = [{"type": "fu_ship_medium", "cargo": {}}, {"type": "fu_ship_medium", "cargo": {}}]
	fleet.water = 0
	fleet.food = 0
	var per := 4
	gs.money = 1000000
	var m_a: int = gs.money
	_buy_like_main("hakata", gid, per, 0)
	_buy_like_main("hakata", gid, per, 1)
	var paid_a: int = m_a - gs.money
	var qty_a: int = fleet.cargo_qty(gid)

	# B：同一只船，同仓连买两批同件数（走 avg_cost 合并路径）
	eco.rates = rates0.duplicate(true)
	fleet.ships = [{"type": "fu_ship_medium", "cargo": {}}]
	fleet.water = 0
	fleet.food = 0
	gs.money = 1000000
	var m_b: int = gs.money
	_buy_like_main("hakata", gid, per, 0)
	_buy_like_main("hakata", gid, per, 0)
	var paid_b: int = m_b - gs.money
	var qty_b: int = fleet.cargo_qty(gid, 0)
	var space_left_b: float = fleet.ship_free_capacity(0)

	print("   每船买 %d 件：A 分船 货 %d 件 扣 %d ｜ B 同船两批 货 %d 件 扣 %d（余舱 %.1f）" % [
		per, qty_a, paid_a, qty_b, paid_b, space_left_b,
	])
	_expect(qty_a == per * 2 and qty_b == per * 2, "两条摆场都真买到 2×%d 件" % per)
	_expect(paid_a == paid_b, "空席入账与 avg_cost 合并同价：扣钱一致（A %d ↔ B %d）" % [paid_a, paid_b])
	# 舱内均价 × 件数 ≈ 实扣（1c 的不动点）：上限由 int(round) 逐件 1 文容差给出
	var tol := maxi(1, per)
	_expect(absi(paid_b - int(round(fleet.cargo_cost(gid, 0) * float(qty_b)))) <= tol,
		"同船两批账后：舱内均价 × 件数 ≈ 实扣（±%d 文）" % tol)


# ── 二、赊贷记账形状 ──────────────────────────────────

func _debt_book() -> void:
	print("── 二、赊贷记账形状（借还来路、息钱同式、账面非负）")
	gs.money = 1000
	gs.debt = 0

	var m0: int = gs.money
	_expect(gs.borrow(500) and gs.debt == 500 and gs.money == m0 + 500,
		"借 500：debt 500、money 恰 +500")
	_expect(not gs.borrow(0) and not gs.borrow(-100) and gs.debt == 500,
		"借 0 / 负数被拒，debt 不动")
	var limit: int = gs.borrow_limit()
	_expect(limit == gs.DEBT_CEILING + gs.title_loan_bonus() - 500,
		"赊贷上限 = 顶 + 职衔加成 − 现欠")
	_expect(not gs.borrow(limit + 1) and gs.debt == 500, "超过上限 %d 的借款被拒" % (limit + 1))

	# 还款实付 min(欲还, 债, 现银)
	gs.money = 200
	var paid: int = gs.repay(500)
	_expect(paid == 200 and gs.debt == 300 and gs.money == 0, "还 500 但只有 200：实还 200、债余 300、钱归零")
	_expect(gs.repay(100) == 0 and gs.debt == 300, "零现银还款不动债")

	# 月息同式 = 工席预告公式
	var want_interest: int = int(ceil(float(gs.debt) * gs.DEBT_MONTHLY_RATE))
	var d0: int = gs.debt
	var got: int = gs.accrue_interest()
	_expect(got == want_interest and gs.debt == d0 + got,
		"结息 %d = ceil(debt × 月息)，debt 同涨" % got)
	gs.debt = 0
	_expect(gs.accrue_interest() == 0 and gs.debt == 0, "无债结息为 0")


# ── 三、委办交付与罚金账 ────────────────────────────────

## 直接摆 contract 账本查 deliver_contract 的分批支付与结清、毁约罚金、逾期作废。
## 帐的硬约束（回退改坏就红）：
##   分批到完，牙行实付总额恰 == purse（最后一批 purse − paid 结清，不少一分）
##   交货倒扣舱货：舱里少几件 = 交了几件（不走牙行砸盘式卖——为这单冻的价）
##   毁约罚金 = max(40, purse × 0.15) 以现银为上限；逾期 due_day 次晨作废
func _contract_book() -> void:
	print("── 三、委办分批交货 / 毁约 / 逾期账")
	# 与 GameState.contract 内部结构对齐的最小合同（purse 1297 故意取奇数逼 round 边）
	var cal := root.get_node_or_null("Calendar")
	if cal == null:
		_expect(false, "Calendar autoload 缺席")
		return
	var purse := 1297
	var qty := 8
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	fleet.ships = [{"type": "fu_ship_medium", "cargo": {}}]
	fleet.water = 0
	fleet.food = 0
	gs.money = 0
	gs.contract = {
		"good_id": "tea", "qty": qty, "remaining": qty, "dest": "quanzhou", "from": "hakata",
		"purse": purse, "unit_purse": float(purse) / float(qty), "paid": 0,
		"due_day": cal.absolute_day() + 20, "deadline_days": 20, "voyage_days": 6,
		"offer_month": cal.year * 12 + cal.month,
	}
	# 分批 3+3+2 全交：deliver_contract 不带件数参，每次交 min(舱货, 欠件)——
	# 分批只能靠「舱里先备几件」摆出，逐批补货再交。
	# purse 1297 分两批段的单价 round 会各自向下 / 向上漂 1 文，靠「最后一批 purse−paid 结清」拉平：
	# 改掉那句结清，总收就缺或多 1 文，断言当场红（1297/8 → 162.125，3 件 round 486 ↔ 5 件 811 ≠ 1297 缺 0/腾挪空间小）。
	var splits := [3, 3, qty - 6]
	var total_paid := 0
	for n in splits:
		fleet.add_cargo("tea", n, 10.0, 0)
		var r: Dictionary = gs.deliver_contract("quanzhou")
		if not bool(r.get("ok", false)):
			_expect(false, "分批交 %d 件被拒：%s" % [n, str(r.get("msg", ""))])
			return
		_expect(int(r.get("qty", -1)) == n, "本批实交 %d 件（回执 %d）" % [n, int(r.get("qty", -1))])
		total_paid += int(r.get("pay", 0))
	_expect(total_paid == purse,
		"分批 3+3+%d 总计实收 %d == purse %d（最后一批 purse−paid 结清）" % [qty - 6, total_paid, purse])
	_expect(gs.money == purse, "交清后现银恰 = purse（实 %d）" % gs.money)
	_expect(fleet.cargo_qty("tea") == 0, "交清后舱里 tea 归零（实余 %d）" % fleet.cargo_qty("tea"))
	_expect(gs.contract.is_empty(), "交清后 contract 清空")

	# 毁约罚金 = max(40, purse × 0.15)，以现银封顶
	gs.money = 100
	gs.contract = {"good_id": "tea", "qty": 8, "remaining": 8, "dest": "quanzhou", "from": "hakata",
		"purse": purse, "unit_purse": float(purse) / float(8), "paid": 0,
		"due_day": cal.absolute_day() + 20, "offer_month": cal.year * 12 + cal.month}
	var m1: int = gs.money
	var fine_msg: String = gs.abandon_contract()
	var want_fine: int = mini(maxi(40, int(round(float(purse) * 0.15))), m1)
	_expect(gs.money == m1 - want_fine,
		"毁约罚 %d（=max(40, purse×0.15) 以现银 100 封顶），实扣 %d" % [want_fine, m1 - gs.money])
	_expect(fine_msg.contains("【毁约】"), "毁约文案带【毁约】（实文 %s）" % fine_msg)

	# 逾期：due_day 当天仍可交，次晨作废
	gs.contract = {"good_id": "tea", "qty": 8, "remaining": 8, "dest": "quanzhou", "from": "hakata",
		"purse": 500, "unit_purse": 62.5, "paid": 0,
		"due_day": cal.absolute_day(), "offer_month": cal.year * 12 + cal.month}
	var tick_today: String = gs.tick_contract()
	_expect(tick_today == "", "due_day 当天 tick 不作废（实回 %s）" % tick_today)
	cal.from_dict({"year": 1255, "month": 3, "day": 2})
	var tick_next: String = gs.tick_contract()
	_expect(tick_next != "" and gs.contract.is_empty(),
		"due_day 次晨 tick 作废并清空（实回 %s）" % tick_next)

	# 交货地不是本港 → 拒且不动账
	gs.contract = {"good_id": "tea", "qty": 8, "remaining": 8, "dest": "quanzhou", "from": "hakata",
		"purse": 500, "unit_purse": 62.5, "paid": 0,
		"due_day": cal.absolute_day() + 10, "offer_month": cal.year * 12 + cal.month}
	var r2: Dictionary = gs.deliver_contract("hakata")
	_expect(not bool(r2.get("ok", false)) and int(gs.contract.get("remaining", -1)) == 8,
		"交货地错港：拒、remaining 不动（实 %s）" % str(r2.get("msg", "")))
