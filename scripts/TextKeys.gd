class_name TextKeys extends RefCounted

## NK1-P6-POLISH-004: 统一本地化 key 字符串常量
## 将散落在各处的 GameManager.get_text("intent.xxx.success", ...) 等字符串提取
## 对应 res://data/localization/zh_cn.json 中的 key

## ── Intent 结果消息 ─────────────────────────────────────
const INTENT_OK := "intent.ok"

## ── Intent 成功消息（按 type 分组）───────────────────────
const INTENT_PAYMENT_SUCCESS := "intent.payment.success"
const INTENT_IGNORE_SUCCESS := "intent.ignore.success"
const INTENT_ESCAPE_SUCCESS := "intent.escape.success"
const INTENT_MARKET_BUY_SUCCESS := "intent.market_buy.success"
const INTENT_MARKET_SELL_SUCCESS := "intent.market_sell.success"
const INTENT_TRADE_REQUEST_SUCCESS := "intent.trade_request.success"
const INTENT_REPAIR_ALREADY_FULL := "intent.repair.already_full"
const INTENT_REPAIR_SUCCESS := "intent.repair.success"
const INTENT_REFIT_SUCCESS := "intent.refit.success"
const INTENT_HIRE_CREW_SUCCESS := "intent.hire_crew.success"
const INTENT_BUY_SUPPLIES_SUCCESS := "intent.buy_supplies.success"
const INTENT_BUY_INTEL_SUCCESS := "intent.buy_intel.success"
const INTENT_BRIBE_SUCCESS := "intent.bribe.success"
const INTENT_COMBAT_STARTED := "intent.combat.started"
const INTENT_INSPECTION_FINED := "intent.inspection.fined"
const INTENT_INSPECTION_CLEARED := "intent.inspection.cleared"

## ── Error 消息 ───────────────────────────────────────────
const ERROR_INTENT_MISSING_TYPE := "error.intent.missing_type"
const ERROR_INTENT_MISSING_SOURCE := "error.intent.missing_source"
const ERROR_INTENT_MISSING_TARGET := "error.intent.missing_target"
const ERROR_INTENT_COMBAT_SELF_TARGET := "error.intent.combat.self_target"
const ERROR_INTENT_PAYMENT_MISSING_AMOUNT := "error.intent.payment.missing_amount"
const ERROR_INTENT_PAYMENT_INVALID_AMOUNT := "error.intent.payment.invalid_amount"
const ERROR_INTENT_PAYMENT_NEGATIVE_AMOUNT := "error.intent.payment.negative_amount"
const ERROR_INTENT_MARKET_MISSING_GOOD := "error.intent.market.missing_good"
const ERROR_INTENT_MARKET_INVALID_AMOUNT := "error.intent.market.invalid_amount"
const ERROR_INTENT_TRADE_MISSING_COST := "error.intent.trade.missing_cost"
const ERROR_INTENT_UNKNOWN_TRADE := "error.intent.unknown_trade"

const ERROR_PAYMENT_INSUFFICIENT_FUNDS := "error.payment.insufficient_funds"
const ERROR_BRIBE_MISSING_AMOUNT := "error.bribe.missing_amount"
const ERROR_BRIBE_INVALID_AMOUNT := "error.bribe.invalid_amount"
const ERROR_BRIBE_CUSTOMS_BLOCKED := "error.bribe.customs_blocked"
const ERROR_BRIBE_INSUFFICIENT_FUNDS := "error.bribe.insufficient_funds"

const ERROR_MARKET_NO_PORT := "error.market.no_port"
const ERROR_MARKET_INVALID_PRICE := "error.market.invalid_price"
const ERROR_MARKET_INSUFFICIENT_FUNDS := "error.market.insufficient_funds"
const ERROR_MARKET_CARGO_FULL := "error.market.cargo_full"
const ERROR_MARKET_MISSING_GOODS := "error.market.missing_goods"
const ERROR_MARKET_INVALID_AMOUNT := "error.market.invalid_amount"
const ERROR_MARKET_TRANSACTION_FAILED := "error.market.transaction_failed"

const ERROR_TRADE_INSUFFICIENT_FUNDS := "error.trade.insufficient_funds"
const ERROR_TRADE_INVALID_COST := "error.trade.invalid_cost"

const ERROR_REPAIR_INVALID_SHIP := "error.repair.invalid_ship"
const ERROR_REPAIR_INVALID_AMOUNT := "error.repair.invalid_amount"
const ERROR_REPAIR_INVALID_COST := "error.repair.invalid_cost"
const ERROR_REPAIR_INSUFFICIENT_FUNDS := "error.repair.insufficient_funds"

const ERROR_REFIT_INVALID_COST := "error.refit.invalid_cost"
const ERROR_REFIT_INSUFFICIENT_FUNDS := "error.refit.insufficient_funds"
const ERROR_REFIT_SAME_SAIL := "error.refit.same_sail"
const ERROR_REFIT_INVALID_SAIL := "error.refit.invalid_sail"
const ERROR_REFIT_SAME_HULL := "error.refit.same_hull"
const ERROR_REFIT_INVALID_HULL := "error.refit.invalid_hull"
const ERROR_REFIT_HULL_LOCKED := "error.refit.hull_locked"

const ERROR_HIRE_CREW_NO_PORT := "error.hire_crew.no_port"
const ERROR_HIRE_CREW_INVALID_COST := "error.hire_crew.invalid_cost"
const ERROR_HIRE_CREW_FULL := "error.hire_crew.full"
const ERROR_HIRE_CREW_INSUFFICIENT_FUNDS := "error.hire_crew.insufficient_funds"

const ERROR_BUY_SUPPLIES_MISSING_TYPE := "error.buy_supplies.missing_type"
const ERROR_BUY_SUPPLIES_FOOD_FULL := "error.buy_supplies.food_full"
const ERROR_BUY_SUPPLIES_WATER_FULL := "error.buy_supplies.water_full"
const ERROR_BUY_SUPPLIES_FULL := "error.buy_supplies.full"
const ERROR_BUY_SUPPLIES_INVALID_AMOUNT := "error.buy_supplies.invalid_amount"
const ERROR_BUY_SUPPLIES_INVALID_TYPE := "error.buy_supplies.invalid_type"
const ERROR_BUY_SUPPLIES_INVALID_COST := "error.buy_supplies.invalid_cost"
const ERROR_BUY_SUPPLIES_INSUFFICIENT_FUNDS := "error.buy_supplies.insufficient_funds"

const ERROR_BUY_INTEL_INVALID_TIER := "error.buy_intel.invalid_tier"
const ERROR_BUY_INTEL_INVALID_COST := "error.buy_intel.invalid_cost"
const ERROR_BUY_INTEL_INVALID_EVENT := "error.buy_intel.invalid_event"
const ERROR_BUY_INTEL_ALREADY_PURCHASED := "error.buy_intel.already_purchased"
const ERROR_BUY_INTEL_INSUFFICIENT_FUNDS := "error.buy_intel.insufficient_funds"

const ERROR_INSPECTION_NO_FUNDS := "error.inspection.no_funds"

const ERROR_COMBAT_NO_FLEET := "error.combat.no_fleet"
const ERROR_COMBAT_FLAGSHIP_DESTROYED := "error.combat.flagship_destroyed"
const ERROR_COMBAT_NO_ENEMY := "error.combat.no_enemy"

## ── 验证 ─────────────────────────────────────────────────

## 返回所有 Intent 结果消息
static func all_intent_success_keys() -> Array[String]:
	return [
		INTENT_PAYMENT_SUCCESS, INTENT_IGNORE_SUCCESS, INTENT_ESCAPE_SUCCESS,
		INTENT_MARKET_BUY_SUCCESS, INTENT_MARKET_SELL_SUCCESS, INTENT_TRADE_REQUEST_SUCCESS,
		INTENT_REPAIR_ALREADY_FULL, INTENT_REPAIR_SUCCESS, INTENT_REFIT_SUCCESS,
		INTENT_HIRE_CREW_SUCCESS, INTENT_BUY_SUPPLIES_SUCCESS, INTENT_BUY_INTEL_SUCCESS,
		INTENT_BRIBE_SUCCESS, INTENT_COMBAT_STARTED,
		INTENT_INSPECTION_FINED, INTENT_INSPECTION_CLEARED,
	]

## 返回所有 Error 消息（intent.* 错误）
static func all_error_keys() -> Array[String]:
	return [
		ERROR_INTENT_MISSING_TYPE, ERROR_INTENT_MISSING_SOURCE, ERROR_INTENT_MISSING_TARGET,
		ERROR_INTENT_COMBAT_SELF_TARGET, ERROR_INTENT_PAYMENT_MISSING_AMOUNT,
		ERROR_INTENT_PAYMENT_INVALID_AMOUNT, ERROR_INTENT_PAYMENT_NEGATIVE_AMOUNT,
		ERROR_INTENT_MARKET_MISSING_GOOD, ERROR_INTENT_MARKET_INVALID_AMOUNT,
		ERROR_INTENT_TRADE_MISSING_COST, ERROR_INTENT_UNKNOWN_TRADE,
		ERROR_PAYMENT_INSUFFICIENT_FUNDS, ERROR_BRIBE_MISSING_AMOUNT,
		ERROR_BRIBE_INVALID_AMOUNT, ERROR_BRIBE_CUSTOMS_BLOCKED, ERROR_BRIBE_INSUFFICIENT_FUNDS,
		ERROR_MARKET_NO_PORT, ERROR_MARKET_INVALID_PRICE, ERROR_MARKET_INSUFFICIENT_FUNDS,
		ERROR_MARKET_CARGO_FULL, ERROR_MARKET_MISSING_GOODS, ERROR_MARKET_INVALID_AMOUNT,
		ERROR_MARKET_TRANSACTION_FAILED,
		ERROR_TRADE_INSUFFICIENT_FUNDS, ERROR_TRADE_INVALID_COST,
		ERROR_REPAIR_INVALID_SHIP, ERROR_REPAIR_INVALID_AMOUNT,
		ERROR_REPAIR_INVALID_COST, ERROR_REPAIR_INSUFFICIENT_FUNDS,
		ERROR_REFIT_INVALID_COST, ERROR_REFIT_INSUFFICIENT_FUNDS,
		ERROR_REFIT_SAME_SAIL, ERROR_REFIT_INVALID_SAIL,
		ERROR_REFIT_SAME_HULL, ERROR_REFIT_INVALID_HULL, ERROR_REFIT_HULL_LOCKED,
		ERROR_HIRE_CREW_NO_PORT, ERROR_HIRE_CREW_INVALID_COST,
		ERROR_HIRE_CREW_FULL, ERROR_HIRE_CREW_INSUFFICIENT_FUNDS,
		ERROR_BUY_SUPPLIES_MISSING_TYPE, ERROR_BUY_SUPPLIES_FOOD_FULL,
		ERROR_BUY_SUPPLIES_WATER_FULL, ERROR_BUY_SUPPLIES_FULL,
		ERROR_BUY_SUPPLIES_INVALID_AMOUNT, ERROR_BUY_SUPPLIES_INVALID_TYPE,
		ERROR_BUY_SUPPLIES_INVALID_COST, ERROR_BUY_SUPPLIES_INSUFFICIENT_FUNDS,
		ERROR_BUY_INTEL_INVALID_TIER, ERROR_BUY_INTEL_INVALID_COST,
		ERROR_BUY_INTEL_INVALID_EVENT, ERROR_BUY_INTEL_ALREADY_PURCHASED,
		ERROR_BUY_INTEL_INSUFFICIENT_FUNDS,
		ERROR_INSPECTION_NO_FUNDS,
		ERROR_COMBAT_NO_FLEET, ERROR_COMBAT_FLAGSHIP_DESTROYED, ERROR_COMBAT_NO_ENEMY,
	]

## 验证 key 是否为已知的 Intent 成功消息
static func is_intent_success(key: String) -> bool:
	return key in all_intent_success_keys()

## 验证 key 是否为已知的 Error 消息
static func is_error(key: String) -> bool:
	return key in all_error_keys()
