class_name IntentResolver extends RefCounted

const _PaymentHandler = preload("res://scripts/systems/handlers/PaymentHandler.gd")
const _TradeHandler = preload("res://scripts/systems/handlers/TradeHandler.gd")
const _BribeHandler = preload("res://scripts/systems/handlers/BribeHandler.gd")
const _CombatHandler = preload("res://scripts/systems/handlers/CombatHandler.gd")
const _InspectionHandler = preload("res://scripts/systems/handlers/InspectionHandler.gd")
const _EscapeHandler = preload("res://scripts/systems/handlers/EscapeHandler.gd")

static var _handlers: Dictionary = {}
static var _handler_instances: Array = []
static var _bootstrapped := false

static func register_handler(intent_type: String, handler: Callable) -> void:
	_handlers[intent_type] = handler

static func unregister_handler(intent_type: String) -> void:
	_handlers.erase(intent_type)

static func has_handler(intent_type: String) -> bool:
	_ensure_bootstrapped()
	return _handlers.has(intent_type)

static func clear_handlers() -> void:
	_handlers.clear()
	_handler_instances.clear()
	_bootstrapped = false

static func _bind_handler(intent_type: String, handler_obj: RefCounted) -> void:
	_handler_instances.append(handler_obj)
	register_handler(intent_type, handler_obj.handle)

static func _ensure_bootstrapped() -> void:
	if _bootstrapped:
		return
	_bind_handler("payment", _PaymentHandler.new())
	var trade := _TradeHandler.new()
	_handler_instances.append(trade)
	var trade_callable := trade.handle
	register_handler("trade_request", trade_callable)
	register_handler("market_buy", trade_callable)
	register_handler("market_sell", trade_callable)
	_bind_handler("bribe", _BribeHandler.new())
	_bind_handler("combat_request", _CombatHandler.new())
	_bind_handler("inspection_pass", _InspectionHandler.new())
	_bind_handler("escape_attempt", _EscapeHandler.new())
	register_handler("ignore", _handle_ignore)
	_bootstrapped = true

static func _handle_ignore(intent: Intent) -> IntentResult:
	var r := IntentResult.ok({}, "intent.ignore.success")
	r.type = intent.type
	return r

## 兼容旧调用方式
static func process(intent: Intent) -> IntentResult:
	return resolve(intent)

static func resolve(intent: Intent) -> IntentResult:
	_ensure_bootstrapped()

	var validation := IntentValidator.validate(intent)
	if not validation.success:
		push_warning("[IntentResolver] Validation Failed: " + str(validation.message_key))
		return validation

	if not _handlers.has(intent.type):
		push_warning("[IntentResolver] No handler for: " + intent.type)
		return IntentResult.error("NO_HANDLER", "未找到对应的 Handler: " + intent.type, intent.type)

	var handler: Callable = _handlers[intent.type]
	var result: Variant = handler.call(intent)
	if result is IntentResult:
		return result
	push_error("[IntentResolver] Handler returned invalid result for: " + intent.type)
	return IntentResult.error("HANDLER_ERROR", "Handler 返回无效结果", intent.type)