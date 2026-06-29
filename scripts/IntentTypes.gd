class_name IntentTypes extends RefCounted

## NK1-P6-POLISH-003: Intent 类型字符串常量
## 集中管理所有 Intent.new("type", ...) 中的 type 字符串
## 与 IntentResolver 的 handler map 保持一致

## ── 交易类 ─────────────────────────────────────────────
const PAYMENT := "payment"              ## 货币交易（LedgerSystem）
const TRADE_REQUEST := "trade_request"  ## 海上贸易（TradeHandler 别名）
const MARKET_BUY := "market_buy"        ## 市集购买
const MARKET_SELL := "market_sell"      ## 市集出售

## ── 经济活动类 ─────────────────────────────────────────
const BRIBE := "bribe"                  ## 贿赂
const REPAIR_SHIP := "repair_ship"      ## 修理船只
const REFIT_SHIP := "refit_ship"        ## 改装帆装
const HIRE_CREW := "hire_crew"          ## 招募水手
const BUY_SUPPLIES := "buy_supplies"    ## 购买补给
const BUY_INTEL := "buy_intel"          ## 购买情报
const INVEST_PORT := "invest_port"      ## 港口投资
const GIFT_NPC := "gift_npc"            ## 向 NPC 送礼
const STUDY_SKILL := "study_skill"      ## 向 NPC 求教秘技

## ── 战斗/海战类 ────────────────────────────────────────
const COMBAT_REQUEST := "combat_request"      ## 发起战斗
const INSPECTION_PASS := "inspection_pass"    ## 海关检查通过
const ESCAPE_ATTEMPT := "escape_attempt"      ## 试图逃跑

## ── 系统/默认 ───────────────────────────────────────────
const IGNORE := "ignore"                ## 无操作（默认 fallback）

## ── 验证 ─────────────────────────────────────────────────
## 验证给定字符串是否为已注册的 Intent 类型
static func is_known(intent_type: String) -> bool:
	var known := [
		PAYMENT, TRADE_REQUEST, MARKET_BUY, MARKET_SELL,
		BRIBE, REPAIR_SHIP, REFIT_SHIP, HIRE_CREW,
		BUY_SUPPLIES, BUY_INTEL, INVEST_PORT, GIFT_NPC, STUDY_SKILL,
		COMBAT_REQUEST, INSPECTION_PASS, ESCAPE_ATTEMPT,
		IGNORE,
	]
	return intent_type in known

## 获取所有已注册的 Intent 类型
static func all_types() -> Array[String]:
	return [
		PAYMENT, TRADE_REQUEST, MARKET_BUY, MARKET_SELL,
		BRIBE, REPAIR_SHIP, REFIT_SHIP, HIRE_CREW,
		BUY_SUPPLIES, BUY_INTEL, INVEST_PORT, GIFT_NPC, STUDY_SKILL,
		COMBAT_REQUEST, INSPECTION_PASS, ESCAPE_ATTEMPT,
		IGNORE,
	]
