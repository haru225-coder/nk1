class_name IntentResolver extends RefCounted

# ═══════════════════════════════════════════════════════════
# IntentResolver — 意图解析器
# ═══════════════════════════════════════════════════════════
#
# Intent 类型与 Handler 对照（动态注册于 _ensure_bootstrapped）：
#   payment→PaymentHandler | market_buy/market_sell/trade_request→TradeHandler
#   bribe→BribeHandler | repair_ship→RepairHandler | refit_ship→RefitHandler
#   hire_crew→HireCrewHandler | buy_supplies→BuySuppliesHandler | buy_intel→BuyIntelHandler
#   combat_request→CombatHandler | inspection_pass→InspectionHandler | escape_attempt→EscapeHandler
#
# 幂等保护流程：
#   1. IntentValidator.validate() — 纯校验，无副作用
#   2. IdempotencyGuard.is_processed() — 检查是否重复
#   3. Handler.handle() — 执行业务逻辑
#   4. 成功后 IdempotencyGuard.mark_processed() — 标记已处理
#
# 两层防护：
#   - IntentResolver: 统一入口，Handler 执行前检查、成功后标记
#   - LedgerSystem: 底层安全网，apply() 内部也检查 intent_id
# ═══════════════════════════════════════════════════════════

const _PaymentHandler = preload(ResourcePaths.SCRIPT_HANDLER_PAYMENT)
const _TradeHandler = preload(ResourcePaths.SCRIPT_HANDLER_TRADE)
const _BribeHandler = preload(ResourcePaths.SCRIPT_HANDLER_BRIBE)
const _CombatHandler = preload(ResourcePaths.SCRIPT_HANDLER_COMBAT)
const _InspectionHandler = preload(ResourcePaths.SCRIPT_HANDLER_INSPECTION)
const _EscapeHandler = preload(ResourcePaths.SCRIPT_HANDLER_ESCAPE)
const _RepairHandler = preload(ResourcePaths.SCRIPT_HANDLER_REPAIR)
const _RefitHandler = preload(ResourcePaths.SCRIPT_HANDLER_REFIT)
const _HireCrewHandler = preload(ResourcePaths.SCRIPT_HANDLER_HIRE_CREW)
const _BuySuppliesHandler = preload(ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES)
const _BuyIntelHandler = preload(ResourcePaths.SCRIPT_HANDLER_BUY_INTEL)
const _InvestPortHandler = preload(ResourcePaths.SCRIPT_HANDLER_INVEST_PORT)
const _GiftNPCHandler = preload(ResourcePaths.SCRIPT_HANDLER_GIFT_NPC)
const _StudySkillHandler = preload(ResourcePaths.SCRIPT_HANDLER_STUDY_SKILL)

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
	_bind_handler(IntentTypes.PAYMENT, _PaymentHandler.new())
	var trade := _TradeHandler.new()
	_handler_instances.append(trade)
	var trade_callable := trade.handle
	register_handler(IntentTypes.TRADE_REQUEST, trade_callable)
	register_handler(IntentTypes.MARKET_BUY, trade_callable)
	register_handler(IntentTypes.MARKET_SELL, trade_callable)
	_bind_handler(IntentTypes.BRIBE, _BribeHandler.new())
	_bind_handler(IntentTypes.REPAIR_SHIP, _RepairHandler.new())
	_bind_handler(IntentTypes.REFIT_SHIP, _RefitHandler.new())
	_bind_handler(IntentTypes.HIRE_CREW, _HireCrewHandler.new())
	_bind_handler(IntentTypes.BUY_SUPPLIES, _BuySuppliesHandler.new())
	_bind_handler(IntentTypes.BUY_INTEL, _BuyIntelHandler.new())
	_bind_handler(IntentTypes.INVEST_PORT, _InvestPortHandler.new())
	_bind_handler(IntentTypes.GIFT_NPC, _GiftNPCHandler.new())
	_bind_handler(IntentTypes.STUDY_SKILL, _StudySkillHandler.new())
	_bind_handler(IntentTypes.COMBAT_REQUEST, _CombatHandler.new())
	_bind_handler(IntentTypes.INSPECTION_PASS, _InspectionHandler.new())
	_bind_handler(IntentTypes.ESCAPE_ATTEMPT, _EscapeHandler.new())
	register_handler(IntentTypes.IGNORE, _handle_ignore)
	_bootstrapped = true

static func _handle_ignore(intent: Intent) -> IntentResult:
	var r := IntentResult.ok({}, TextKeys.INTENT_IGNORE_SUCCESS)
	r.type = intent.type
	return r

## 兼容旧调用方式
static func process(intent: Intent) -> IntentResult:
	return resolve(intent)

static func resolve(intent: Intent) -> IntentResult:
	_ensure_bootstrapped()

	# 第一步：纯校验（无副作用，失败可重试）
	var validation := IntentValidator.validate(intent)
	if not validation.success:
		push_warning("[IntentResolver] Validation Failed: " + str(validation.message_key))
		return validation

	# 第二步：幂等检查（验证通过后、Handler 执行前）
	if IdempotencyGuard.is_processed(intent.id):
		push_warning("[IntentResolver] Duplicate intent blocked: " + intent.id)
		return IntentResult.error(IntentErrorCodes.DUPLICATE_INTENT, "", intent.type)

	if not _handlers.has(intent.type):
		push_warning("[IntentResolver] No handler for: " + intent.type)
		return IntentResult.error(IntentErrorCodes.NO_HANDLER, "未找到对应的 Handler: " + intent.type, intent.type)

	# 第三步：执行 Handler
	var handler: Callable = _handlers[intent.type]
	var result: Variant = handler.call(intent)

	if result is IntentResult:
		# 第四步：Handler 成功后标记已处理
		if result.success:
			IdempotencyGuard.mark_processed(intent.id)
		return result

	push_error("[IntentResolver] Handler returned invalid result for: " + intent.type)
	return IntentResult.error(IntentErrorCodes.HANDLER_ERROR, "Handler 返回无效结果", intent.type)