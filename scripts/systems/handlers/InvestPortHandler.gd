class_name InvestPortHandler extends RefCounted

## 港口投资：扣款 → 好感/繁荣提升 → 检查特产解锁

const INVEST_COOLDOWN_FLAG_PREFIX := "port_invested_this_visit_"

const INVEST_TIERS := {
	"small": {"amount": 100, "affinity": 2.0, "prosperity": 0.02, "label": "小额"},
	"medium": {"amount": 500, "affinity": 5.0, "prosperity": 0.05, "label": "中额"},
	"large": {"amount": 2000, "affinity": 8.0, "prosperity": 0.08, "label": "大额"},
}

## port_id → 解锁条件与特产 good_id
const SPECIALTY_UNLOCK_RULES := {
	"quanzhou": {"good_id": "fujian_porcelain", "affinity_min": 8.0, "prosperity_min": 1.02},
	"xinghua": {"good_id": "aromatic_medicine", "affinity_min": 5.0, "prosperity_min": 1.0},
}

## 离港时清除本港「本访已投资」冷却，下次入港可再投
static func clear_visit_cooldown(port_id: String) -> void:
	if port_id.is_empty():
		return
	var cooldown_key := INVEST_COOLDOWN_FLAG_PREFIX + port_id
	GameState.set_story_flag(cooldown_key, false)
	if GameState.story_flags.has(cooldown_key):
		GameState.story_flags.erase(cooldown_key)

func handle(intent: Intent) -> IntentResult:
	var port_id := str(intent.target)
	if port_id.is_empty():
		port_id = str(intent.context.get("port_id", ""))
	if port_id.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_INVEST_NO_PORT, IntentTypes.INVEST_PORT)

	var cooldown_key := INVEST_COOLDOWN_FLAG_PREFIX + port_id
	if GameState.has_story_flag(cooldown_key):
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_INVEST_COOLDOWN, IntentTypes.INVEST_PORT)

	var tier_key := str(intent.parameters.get("tier", "small"))
	if not INVEST_TIERS.has(tier_key):
		return IntentResult.error(IntentErrorCodes.VALIDATION_ERROR, TextKeys.ERROR_INVEST_INVALID_TIER, IntentTypes.INVEST_PORT)
	var tier: Dictionary = INVEST_TIERS[tier_key]
	var amount: int = int(tier["amount"])

	var tx := {
		"amount": -amount,
		"source": "gameplay",
		"reason": "port_invest_" + port_id,
		"actor": "InvestPortHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", IntentTypes.INVEST_PORT)

	var market = GameState.market
	market.adjust_affinity(port_id, float(tier["affinity"]))
	market.apply_prosperity_boost(port_id, float(tier["prosperity"]))

	var specialty_id := _try_unlock_specialty(port_id, market)

	GameState.set_story_flag(cooldown_key, true)

	var port_name := str(GameManager.get_port_data(port_id).get("name", port_id))
	if GameState.economy_log != null:
		GameState.economy_log.log(EconomyLog.make_port_invest(port_name, str(tier["label"]), amount))
		if specialty_id != "":
			GameState.economy_log.log(EconomyLog.make_specialty_unlock(port_name, _resolve_good_name(specialty_id)))

	var r := IntentResult.ok({
		"port_id": port_id,
		"amount": amount,
		"tier": tier_key,
		"affinity": market.get_affinity(port_id),
		"prosperity": market.get_prosperity(port_id),
		"unlocked_specialty": specialty_id,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_INVEST_SUCCESS)
	r.type = IntentTypes.INVEST_PORT
	return r

func _try_unlock_specialty(port_id: String, market: MarketState) -> String:
	if not SPECIALTY_UNLOCK_RULES.has(port_id):
		return ""
	var rule: Dictionary = SPECIALTY_UNLOCK_RULES[port_id]
	var good_id := str(rule.get("good_id", ""))
	if good_id.is_empty():
		return ""
	if market.is_specialty_unlocked(port_id, good_id):
		return ""
	if market.get_affinity(port_id) < float(rule.get("affinity_min", 99.0)):
		return ""
	if market.get_prosperity(port_id) < float(rule.get("prosperity_min", 99.0)):
		return ""
	market.unlock_specialty(port_id, good_id)
	return good_id

static func _resolve_good_name(good_id: String) -> String:
	var g = GameManager.get_good_data(good_id)
	if g.is_empty():
		return good_id
	return str(g.get("name", good_id))