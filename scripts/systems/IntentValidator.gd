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
			if not intent.parameters.has("amount") or intent.parameters["amount"] <= 0:
				return IntentResult.new(false, "validation_error", "error.intent.market.invalid_amount")
				
	return IntentResult.new(true, "validation_ok")
