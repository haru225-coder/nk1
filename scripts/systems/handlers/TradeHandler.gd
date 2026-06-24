class_name TradeHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	return execute(intent)

func execute(intent: Intent) -> IntentResult:
	var type := intent.type
	var params := intent.parameters

	if type == "trade_request":
		return _execute_sea_trade(intent)

	var port_id: String = intent.context.get("port_id", "")
	if port_id.is_empty():
		return IntentResult.error("error.market.no_port", "", type)

	var good_id: String = params.get("good_id", "")
	var amount: int = int(params.get("amount", 0))

	if type == "market_buy":
		return _execute_market_buy(intent, port_id, good_id, amount, type)
	if type == "market_sell":
		return _execute_market_sell(intent, port_id, good_id, amount, type)

	return IntentResult.error("error.intent.unknown_trade", "", type)

func _execute_market_buy(intent: Intent, port_id: String, good_id: String, amount: int, type: String) -> IntentResult:
	if good_id.is_empty() or amount <= 0:
		return IntentResult.error("error.market.invalid_amount", "", type)

	var price := EconomySystem.get_price(port_id, good_id)
	if price <= 0:
		return IntentResult.error("error.market.invalid_price", "", type)
	if not CargoSystem.has_space_for(amount):
		return IntentResult.error("error.market.cargo_full", "", type)

	var total_cost := price * amount
	var tx := {
		"amount": -total_cost,
		"source": "market",
		"reason": "market_buy_%s_%d" % [good_id, amount],
		"actor": "TradeHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error("error.market.transaction_failed", "", type)
	if CargoSystem.add_item(good_id, amount):
		GameState.market.adjust_stock(port_id, good_id, -amount)
		var r := IntentResult.ok({"good_id": good_id, "amount": amount, "cost": total_cost}, "intent.market_buy.success")
		r.type = type
		return r
	LedgerSystem.apply({
		"amount": total_cost,
		"source": "market",
		"reason": "market_buy_rollback_%s_%d" % [good_id, amount],
		"actor": "TradeHandler",
	}, intent.id + ":rollback")
	return IntentResult.error("error.market.cargo_full", "", type)

func _execute_market_sell(intent: Intent, port_id: String, good_id: String, amount: int, type: String) -> IntentResult:
	if good_id.is_empty() or amount <= 0:
		return IntentResult.error("error.market.invalid_amount", "", type)

	var price := EconomySystem.get_price(port_id, good_id)
	if price <= 0:
		return IntentResult.error("error.market.invalid_price", "", type)
	if not CargoSystem.has_item(good_id, amount):
		return IntentResult.error("error.market.missing_goods", "", type)

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
		var r := IntentResult.ok({"good_id": good_id, "amount": amount, "revenue": total_revenue}, "intent.market_sell.success")
		r.type = type
		return r
	return IntentResult.error("error.market.transaction_failed", "", type)

func _execute_sea_trade(intent: Intent) -> IntentResult:
	var params := intent.parameters
	var cost: int = int(params.get("cost", 0))
	var food_gain: int = int(params.get("food", 0))
	var water_gain: int = int(params.get("water", 0))

	if cost <= 0:
		return IntentResult.error("error.trade.invalid_cost", "", "trade_request")

	var tx := {
		"amount": -cost,
		"source": "sea_trade",
		"reason": "merchant_trade",
		"actor": "TradeHandler",
	}
	if LedgerSystem.apply(tx, intent.id):
		GameState.apply_effects({"food": food_gain, "water": water_gain})
		var r := IntentResult.ok({"cost": cost, "food": food_gain, "water": water_gain}, "intent.trade_request.success")
		r.type = "trade_request"
		return r
	return IntentResult.error("error.trade.insufficient_funds", "", "trade_request")