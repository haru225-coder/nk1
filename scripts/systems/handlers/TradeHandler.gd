class_name TradeHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	var type = intent.type
	var params = intent.parameters
	
	# 海上交易：无 port_id，直接扣款并补给物资
	if type == "trade_request":
		return _execute_sea_trade(intent)
	
	var port_id = intent.context.get("port_id", "")
	if port_id.is_empty():
		return IntentResult.new(false, type, "error.market.no_port")
		
	var good_id: String = params.get("good_id", "")
	var amount: int = int(params.get("amount", 0))
	
	if type == "market_buy":
		if good_id.is_empty():
			return IntentResult.new(false, type, "error.market.invalid_good")
		if amount <= 0:
			return IntentResult.new(false, type, "error.market.invalid_amount")
		var price = EconomySystem.get_price(port_id, good_id)
		if price <= 0:
			return IntentResult.new(false, type, "error.market.invalid_price")
		if not CargoSystem.has_space_for(amount):
			return IntentResult.new(false, type, "error.market.cargo_full")
		var total_cost = price * amount
		
		var tx = {
			"amount": -total_cost,
			"source": "market",
			"reason": "market_buy_%s_%d" % [good_id, amount],
			"actor": "TradeHandler"
		}
		if not LedgerSystem.apply(tx, intent.id):
			return IntentResult.new(false, type, "error.market.transaction_failed")
		if CargoSystem.add_item(good_id, amount):
			GameManager.state.market.adjust_stock(port_id, good_id, -amount)
			return IntentResult.new(true, type, "intent.market_buy.success")
		LedgerSystem.apply({
			"amount": total_cost,
			"source": "market",
			"reason": "market_buy_rollback_%s_%d" % [good_id, amount],
			"actor": "TradeHandler"
		}, intent.id + ":rollback")
		return IntentResult.new(false, type, "error.market.cargo_full")
			
	elif type == "market_sell":
		if good_id.is_empty():
			return IntentResult.new(false, type, "error.market.invalid_good")
		if amount <= 0:
			return IntentResult.new(false, type, "error.market.invalid_amount")
		var price = EconomySystem.get_price(port_id, good_id)
		if price <= 0:
			return IntentResult.new(false, type, "error.market.invalid_price")
		var total_revenue = price * amount
		
		if not CargoSystem.has_item(good_id, amount):
			return IntentResult.new(false, type, "error.market.missing_goods")
			
		var tx = {
			"amount": total_revenue,
			"source": "market",
			"reason": "market_sell_%s_%d" % [good_id, amount],
			"actor": "TradeHandler"
		}
		if LedgerSystem.apply(tx, intent.id):
			CargoSystem.remove_item(good_id, amount)
			GameManager.state.market.adjust_stock(port_id, good_id, amount)
			return IntentResult.new(true, type, "intent.market_sell.success")
		else:
			return IntentResult.new(false, type, "error.market.transaction_failed")
			
	return IntentResult.new(false, type, "error.intent.unknown_trade")

func _execute_sea_trade(intent: Intent) -> IntentResult:
	var params = intent.parameters
	var cost: int = int(params.get("cost", 0))
	var food_gain: int = int(params.get("food", 0))
	var water_gain: int = int(params.get("water", 0))
	
	if cost <= 0:
		return IntentResult.new(false, "trade_request", "error.trade.invalid_cost")
	
	var tx = {
		"amount": -cost,
		"source": "sea_trade",
		"reason": "merchant_trade",
		"actor": "TradeHandler"
	}
	if LedgerSystem.apply(tx, intent.id):
		GameState.apply_effects({"food": food_gain, "water": water_gain})
		return IntentResult.new(true, "trade_request", "intent.trade_request.success")
	else:
		return IntentResult.new(false, "trade_request", "error.trade.insufficient_funds")
