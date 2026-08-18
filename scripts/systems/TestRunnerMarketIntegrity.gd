extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	_test_buy_amount_exceeds_stock_rejected()
	_test_same_port_flip_no_profit()
	_test_daily_stock_moves_toward_base()
	_test_sell_price_below_buy_price_spread()
	_test_affinity_buy_sell_opposite()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _assert_lt(actual: float, threshold: float, msg: String) -> void:
	_runner._assert_lt(actual, threshold, msg)

func _port_good() -> Dictionary:
	return {"port_id": "quanzhou", "good_id": "fujian_porcelain"}

func _ensure_stock_entry(port_id: String, good_id: String, stock: int) -> bool:
	if GameState.market == null:
		return false
	if not GameState.market.port_stocks.has(port_id):
		GameState.market.port_stocks[port_id] = {}
	if not GameState.market.port_stocks[port_id].has(good_id):
		var base := maxi(stock, 1)
		GameState.market.port_stocks[port_id][good_id] = {"stock": stock, "base_stock": base}
	else:
		GameState.market.port_stocks[port_id][good_id]["stock"] = maxi(0, stock)
	return true

func _snapshot_trade_env() -> Dictionary:
	return {
		"market": GameState.market.to_dict() if GameState.market != null else {},
		"ledger": LedgerSystem.to_save_dict(),
		"cargo": CargoSystem.get_all(),
	}

func _restore_trade_env(snap: Dictionary) -> void:
	if GameState.market != null and not snap.get("market", {}).is_empty():
		GameState.market.from_dict(snap["market"])
	LedgerSystem.from_save_dict(snap.get("ledger", {}))
	CargoSystem.clear_all()
	var cargo: Dictionary = snap.get("cargo", {})
	for good_id in cargo.keys():
		var amt := int(cargo[good_id])
		if amt > 0:
			CargoSystem.add_item(str(good_id), amt)

func _test_buy_amount_exceeds_stock_rejected() -> void:
	print("[MarketIntegrity] buy over stock")

	var ids := _port_good()
	var port_id: String = ids["port_id"]
	var good_id: String = ids["good_id"]
	var snap := _snapshot_trade_env()
	_assert_true(_ensure_stock_entry(port_id, good_id, 3), "可写入港口库存")

	var intent := Intent.new(
		IntentTypes.MARKET_BUY, "player", "market",
		{"good_id": good_id, "amount": 10},
		{"port_id": port_id}
	)
	var validation := IntentValidator.validate(intent)
	_assert_true(not validation.success, "买入数量 > 库存: Validator 拒绝")
	_assert_eq(validation.error_code, IntentErrorCodes.INSUFFICIENT_STOCK, "超额买入 error_code=INSUFFICIENT_STOCK")

	var handler := TradeHandler.new()
	var handled := handler.handle(intent)
	_assert_true(not handled.success, "买入数量 > 库存: TradeHandler 拒绝")
	_assert_eq(handled.error_code, IntentErrorCodes.INSUFFICIENT_STOCK, "Handler 超额买入 error_code=INSUFFICIENT_STOCK")

	_ensure_stock_entry(port_id, good_id, 0)
	var empty_intent := Intent.new(
		IntentTypes.MARKET_BUY, "player", "market",
		{"good_id": good_id, "amount": 1},
		{"port_id": port_id}
	)
	var empty_v := IntentValidator.validate(empty_intent)
	_assert_true(not empty_v.success, "库存为 0: Validator 拒绝")
	var empty_h := handler.handle(empty_intent)
	_assert_true(not empty_h.success, "库存为 0: TradeHandler 拒绝")

	_restore_trade_env(snap)
	print("")

func _test_same_port_flip_no_profit() -> void:
	print("[MarketIntegrity] same-port flip")

	var ids := _port_good()
	var port_id: String = ids["port_id"]
	var good_id: String = ids["good_id"]
	var snap := _snapshot_trade_env()

	_assert_true(_ensure_stock_entry(port_id, good_id, 80), "翻盘测试: 写入库存")
	if GameState.market != null:
		GameState.market.reset_stock(port_id, good_id)
		var base := GameState.market.get_base_stock(port_id, good_id)
		if base > 0:
			GameState.market.port_stocks[port_id][good_id]["stock"] = base

	CargoSystem.clear_all()
	LedgerSystem.from_save_dict({"balance": 20000})
	var before := LedgerSystem.get_balance()
	var amount := 8

	var handler := TradeHandler.new()
	var buy := handler.handle(Intent.new(
		IntentTypes.MARKET_BUY, "player", "market",
		{"good_id": good_id, "amount": amount},
		{"port_id": port_id}
	))
	_assert_true(buy.success, "同港翻盘: 买入成功")
	var sell := handler.handle(Intent.new(
		IntentTypes.MARKET_SELL, "player", "market",
		{"good_id": good_id, "amount": amount},
		{"port_id": port_id}
	))
	_assert_true(sell.success, "同港翻盘: 卖出成功")

	var after := LedgerSystem.get_balance()
	var profit := after - before
	var data_profit := int(sell.data.get("revenue", 0)) - int(buy.data.get("cost", 0))
	_assert_true(profit <= 0, "同港买后再卖: Ledger 余额不增加")
	_assert_true(data_profit <= 0, "同港买后再卖: 成交利润 <= 0")

	_restore_trade_env(snap)
	print("")

func _test_daily_stock_moves_toward_base() -> void:
	print("[MarketIntegrity] daily stock regen")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "p1", "production": {"g1": 1.0}, "demand": {}},
	]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)
	var base := market.get_base_stock("p1", "g1")

	market.port_stocks["p1"]["g1"]["stock"] = 0
	var low_before := market.get_stock("p1", "g1")
	market.process_daily_economy()
	var low_after := market.get_stock("p1", "g1")
	_assert_true(low_after > low_before, "短缺: 库存向 base 回升")
	_assert_true(low_after < base, "短缺: 不立刻回满")

	market.port_stocks["p1"]["g1"]["stock"] = base * 2
	var high_before := market.get_stock("p1", "g1")
	market.process_daily_economy()
	var high_after := market.get_stock("p1", "g1")
	_assert_true(high_after < high_before, "过剩: 库存向 base 回落")
	_assert_true(high_after > base, "过剩: 不立刻归位")

	print("")

func _test_sell_price_below_buy_price_spread() -> void:
	print("[MarketIntegrity] bid/ask spread")

	var ids := _port_good()
	var port_id: String = ids["port_id"]
	var good_id: String = ids["good_id"]
	var snap := _snapshot_trade_env()
	_ensure_stock_entry(port_id, good_id, 100)
	if GameState.market != null:
		GameState.market.reset_stock(port_id, good_id)

	var buy_p := EconomySystem.get_trade_price(port_id, good_id, 1, true)
	var sell_p := EconomySystem.get_trade_price(port_id, good_id, 1, false)
	_assert_true(buy_p > 0, "买入成交价 > 0")
	_assert_true(sell_p > 0, "卖出成交价 > 0")
	_assert_lt(float(sell_p), float(buy_p), "同库存: 卖出价 < 买入价（价差）")

	var mid := EconomySystem.get_price(port_id, good_id)
	var cap := maxi(1, int(round(float(mid) * EconomySystem.SELL_PRICE_RATIO)))
	_assert_true(sell_p <= cap, "卖出价 <= 同库存参考价 × SELL_PRICE_RATIO")

	_restore_trade_env(snap)
	print("")

func _test_affinity_buy_sell_opposite() -> void:
	print("[MarketIntegrity] affinity buy/sell opposite")
	var market := MarketState.new()
	market.adjust_affinity("p1", 10.0)
	var buy_mod := market.get_affinity_price_mod("p1", true)
	var sell_mod := market.get_affinity_price_mod("p1", false)
	_assert_lt(buy_mod, 1.0, "好感高: 买入修正 < 1")
	_assert_true(sell_mod > 1.0, "好感高: 卖出修正 > 1")
	_assert_lt(buy_mod, sell_mod, "好感高: 买入修正 < 卖出修正")
	market.adjust_affinity("p1", -30.0)
	_assert_true(market.get_affinity_price_mod("p1", true) > 1.0, "敌意: 买入更贵")
	_assert_lt(market.get_affinity_price_mod("p1", false), 1.0, "敌意: 卖出更贱")
	print("")
