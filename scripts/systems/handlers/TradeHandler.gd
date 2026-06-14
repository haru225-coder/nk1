class_name TradeHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	var type = intent.type
	var params = intent.parameters
	var port_id = intent.context.get("port_id", "")
	
	if port_id.is_empty():
		return IntentResult.new(false, type, "error.market.no_port")
		
	var good_id = params.get("good_id", "")
	var amount = params.get("amount", 0)
	
	if type == "market_buy":
		var price = EconomySystem.get_price(port_id, good_id)
		var total_cost = price * amount
		
		var tx = {
			"amount": -total_cost,
			"source": "market",
			"reason": "market_buy_%s_%d" % [good_id, amount],
			"actor": "TradeHandler"
		}
		print("[TradeHandler] transaction created: buy %s" % good_id)
		if LedgerSystem.apply(tx, intent.id):
			CargoSystem.add_item(good_id, amount)
			return IntentResult.new(true, type, "intent.market_buy.success")
		else:
			return IntentResult.new(false, type, "error.market.transaction_failed")
			
	elif type == "market_sell":
		var price = EconomySystem.get_price(port_id, good_id)
		var total_revenue = price * amount
		
		if not CargoSystem.has_item(good_id, amount):
			return IntentResult.new(false, type, "error.market.missing_goods")
			
		var tx = {
			"amount": total_revenue,
			"source": "market",
			"reason": "market_sell_%s_%d" % [good_id, amount],
			"actor": "TradeHandler"
		}
		print("[TradeHandler] transaction created: sell %s" % good_id)
		if LedgerSystem.apply(tx, intent.id):
			CargoSystem.remove_item(good_id, amount)
			return IntentResult.new(true, type, "intent.market_sell.success")
		else:
			return IntentResult.new(false, type, "error.market.transaction_failed")
			
	return IntentResult.new(false, type, "error.intent.unknown_trade")
