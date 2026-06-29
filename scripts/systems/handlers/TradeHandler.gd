class_name TradeHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var type := intent.type
	var params := intent.parameters

	if type == IntentTypes.TRADE_REQUEST:
		return _handle_sea_trade(intent)

	var port_id: String = intent.context.get("port_id", "")
	if port_id.is_empty():
		return IntentResult.error(TextKeys.ERROR_MARKET_NO_PORT, "", type)

	var good_id: String = params.get("good_id", "")
	var amount: int = int(params.get("amount", 0))

	if type == IntentTypes.MARKET_BUY:
		return _handle_market_buy(intent, port_id, good_id, amount, type)
	if type == IntentTypes.MARKET_SELL:
		return _handle_market_sell(intent, port_id, good_id, amount, type)

	return IntentResult.error(TextKeys.ERROR_INTENT_UNKNOWN_TRADE, "", type)

func _handle_market_buy(intent: Intent, port_id: String, good_id: String, amount: int, type: String) -> IntentResult:
	if good_id.is_empty() or amount <= 0:
		return IntentResult.error(TextKeys.ERROR_MARKET_INVALID_AMOUNT, "", type)

	var price := EconomySystem.get_price(port_id, good_id)
	if price <= 0:
		return IntentResult.error(TextKeys.ERROR_MARKET_INVALID_PRICE, "", type)
	if not CargoSystem.has_space_for(amount):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, "", type)

	var total_cost := price * amount
	var tx := {
		"amount": -total_cost,
		"source": "market",
		"reason": "market_buy_%s_%d" % [good_id, amount],
		"actor": "TradeHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", type)
	if CargoSystem.add_item(good_id, amount):
		GameState.market.adjust_stock(port_id, good_id, -amount)
		_check_dump_economy_log(port_id, good_id, -amount)
		var r := IntentResult.ok({"good_id": good_id, "amount": amount, "cost": total_cost}, TextKeys.INTENT_MARKET_BUY_SUCCESS)
		r.type = type
		return r
	LedgerSystem.apply({
		"amount": total_cost,
		"source": "market",
		"reason": "market_buy_rollback_%s_%d" % [good_id, amount],
		"actor": "TradeHandler",
	}, intent.id + ":rollback")
	return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, "", type)

func _handle_market_sell(intent: Intent, port_id: String, good_id: String, amount: int, type: String) -> IntentResult:
	if good_id.is_empty() or amount <= 0:
		return IntentResult.error(TextKeys.ERROR_MARKET_INVALID_AMOUNT, "", type)

	var price := EconomySystem.get_price(port_id, good_id)
	if price <= 0:
		return IntentResult.error(TextKeys.ERROR_MARKET_INVALID_PRICE, "", type)
	if not CargoSystem.has_item(good_id, amount):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, "", type)

	var total_revenue := price * amount
	var tx := {
		"amount": total_revenue,
		"source": "market",
		"reason": "market_sell_%s_%d" % [good_id, amount],
		"actor": "TradeHandler",
	}
	if LedgerSystem.apply(tx, intent.id):
		CargoSystem.remove_item(good_id, amount)
		GameState.market.adjust_stock(port_id, good_id, amount)
		_check_dump_economy_log(port_id, good_id, amount)
		var r := IntentResult.ok({"good_id": good_id, "amount": amount, "revenue": total_revenue}, TextKeys.INTENT_MARKET_SELL_SUCCESS)
		r.type = type
		return r
	return IntentResult.error(TextKeys.ERROR_MARKET_TRANSACTION_FAILED, "", type)

func _handle_sea_trade(intent: Intent) -> IntentResult:
	var params := intent.parameters
	var cost: int = int(params.get("cost", 0))
	var food_gain: int = int(params.get("food", 0))
	var water_gain: int = int(params.get("water", 0))

	if cost <= 0:
		return IntentResult.error(TextKeys.ERROR_TRADE_INVALID_COST, "", IntentTypes.TRADE_REQUEST)

	var tx := {
		"amount": -cost,
		"source": "sea_trade",
		"reason": "merchant_trade",
		"actor": "TradeHandler",
	}
	if LedgerSystem.apply(tx, intent.id):
		GameState.apply_effects({"food": food_gain, "water": water_gain})
		var r := IntentResult.ok({"cost": cost, "food": food_gain, "water": water_gain}, TextKeys.INTENT_TRADE_REQUEST_SUCCESS)
		r.type = IntentTypes.TRADE_REQUEST
		return r
	return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", IntentTypes.TRADE_REQUEST)

## NK1-P5-ECON-002: 检测大量倾销并记录经济日志
## delta > 0 = 卖出（倾销），delta < 0 = 买入
## 仅在累计净流入超过阈值时记录，避免每笔交易都刷屏
func _check_dump_economy_log(port_id: String, good_id: String, delta: int) -> void:
	if delta <= 0:
		return  # 买入不记录倾销日志
	var market = GameState.market
	if market == null:
		return
	# 检查净流入是否超过基准库存的 50%（大量倾销）
	var base_stock = market.get_base_stock(port_id, good_id)
	var net_flow = 0
	if market.trade_history.has(port_id) and market.trade_history[port_id].has(good_id):
		net_flow = market.trade_history[port_id][good_id].get("net_flow", 0)
	# 仅在净流入刚好超过阈值时记录一次（避免重复刷屏）
	if net_flow > base_stock * 0.5 and net_flow - delta <= base_stock * 0.5:
		var log = GameState.economy_log
		if log == null:
			return
		var port_name = port_id
		var good_name = good_id
		var gm_port = GameManager.get_port_data(port_id)
		if not gm_port.is_empty():
			port_name = gm_port.get("name", port_id)
		var gm_good = GameManager.get_good_data(good_id)
		if not gm_good.is_empty():
			good_name = gm_good.get("name", good_id)
		log.log(EconomyLog.make_dump_notice(port_name, good_name))
