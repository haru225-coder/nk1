class_name IntentValidator extends RefCounted

static func validate(intent: Intent) -> IntentResult:
	if intent.type.is_empty():
		return IntentResult.new(false, "validation_error", "error.intent.missing_type")
		
	if intent.source.is_empty():
		return IntentResult.new(false, "validation_error", "error.intent.missing_source")
		
	if intent.target.is_empty():
		return IntentResult.new(false, "validation_error", "error.intent.missing_target")
		
	match intent.type:
		"payment":
			if not intent.parameters.has("amount"):
				return IntentResult.new(false, "validation_error", "error.intent.payment.missing_amount")
			if typeof(intent.parameters["amount"]) != TYPE_INT and typeof(intent.parameters["amount"]) != TYPE_FLOAT:
				return IntentResult.new(false, "validation_error", "error.intent.payment.invalid_amount")
			if intent.parameters["amount"] < 0:
				return IntentResult.new(false, "validation_error", "error.intent.payment.negative_amount")
				
		"combat_request":
			if intent.source == intent.target:
				return IntentResult.new(false, "validation_error", "error.intent.combat.self_target")
				
		"market_buy", "market_sell":
			if not intent.parameters.has("good_id"):
				return IntentResult.new(false, "validation_error", "error.intent.market.missing_good")
			if str(intent.parameters.get("good_id", "")).is_empty():
				return IntentResult.new(false, "validation_error", "error.intent.market.missing_good")
			if not intent.parameters.has("amount") or int(intent.parameters.get("amount", 0)) <= 0:
				return IntentResult.new(false, "validation_error", "error.intent.market.invalid_amount")
			if intent.context.get("port_id", "").is_empty():
				return IntentResult.new(false, "validation_error", "error.market.no_port")
				
		"trade_request":
			if not intent.parameters.has("cost") or int(intent.parameters.get("cost", 0)) <= 0:
				return IntentResult.new(false, "validation_error", "error.intent.trade.missing_cost")
				
	return IntentResult.new(true, "validation_ok")
