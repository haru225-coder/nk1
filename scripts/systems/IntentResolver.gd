class_name IntentResolver extends RefCounted

static func process(intent: Intent) -> IntentResult:
	var validation = IntentValidator.validate(intent)
	if not validation.success:
		print("[ERROR] Intent Validation Failed: ", validation.message_key)
		return validation
		
	var result: IntentResult
	match intent.type:
		"payment":
			var handler = load("res://scripts/systems/handlers/PaymentHandler.gd").new()
			result = handler.execute(intent)
		"combat_request":
			var handler = load("res://scripts/systems/handlers/CombatHandler.gd").new()
			result = handler.execute(intent)
		"inspection_pass":
			var handler = load("res://scripts/systems/handlers/InspectionHandler.gd").new()
			result = handler.execute(intent)
		"trade_request", "market_buy", "market_sell":
			var handler = load("res://scripts/systems/handlers/TradeHandler.gd").new()
			result = handler.execute(intent)
		"escape_attempt":
			var handler = load("res://scripts/systems/handlers/EscapeHandler.gd").new()
			result = handler.execute(intent)
		"ignore":
			print("\n[STUB] Ignore intent received. Player sailed away.")
			result = IntentResult.new(true, intent.type, "intent.ignore.success")
		_:
			print("Unhandled Intent Type: ", intent.type)
			result = IntentResult.new(false, intent.type, "error.intent.unhandled")
			
	return result
