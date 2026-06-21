class_name IntentResolver extends RefCounted

# 预加载所有 Handler 脚本（避免运行时 load 开销）
const PaymentHandlerScript = preload("res://scripts/systems/handlers/PaymentHandler.gd")
const CombatHandlerScript = preload("res://scripts/systems/handlers/CombatHandler.gd")
const InspectionHandlerScript = preload("res://scripts/systems/handlers/InspectionHandler.gd")
const TradeHandlerScript = preload("res://scripts/systems/handlers/TradeHandler.gd")
const EscapeHandlerScript = preload("res://scripts/systems/handlers/EscapeHandler.gd")

static func process(intent: Intent) -> IntentResult:
	var validation = IntentValidator.validate(intent)
	if not validation.success:
		push_warning("[IntentResolver] Validation Failed: " + str(validation.message_key))
		return validation
		
	var result: IntentResult
	match intent.type:
		"payment":
			var handler = PaymentHandlerScript.new()
			result = handler.execute(intent)
		"combat_request":
			var handler = CombatHandlerScript.new()
			result = handler.execute(intent)
		"inspection_pass":
			var handler = InspectionHandlerScript.new()
			result = handler.execute(intent)
		"trade_request", "market_buy", "market_sell":
			var handler = TradeHandlerScript.new()
			result = handler.execute(intent)
		"escape_attempt":
			var handler = EscapeHandlerScript.new()
			result = handler.execute(intent)
		"ignore":
			result = IntentResult.new(true, intent.type, "intent.ignore.success")
		_:
			push_warning("[IntentResolver] Unhandled Intent Type: " + intent.type)
			result = IntentResult.new(false, intent.type, "error.intent.unhandled")
			
	return result
