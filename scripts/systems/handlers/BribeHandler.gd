class_name BribeHandler extends RefCounted

## ── 贿赂默认值常量 ───────────────────────────────────────
const DEFAULT_BRIBE_AMOUNT := 50           ## 默认贿赂金额
const DEFAULT_ATTENTION_DELTA := 3         ## 默认蒲氏关注度增量
const PU_ATTENTION_MAX := 20               ## 蒲氏关注度上限

func handle(intent: Intent) -> IntentResult:
	var amount: int = int(intent.parameters.get("amount", DEFAULT_BRIBE_AMOUNT))
	var ledger_source := "encounter" if intent.source == "player_fleet" else "gameplay"
	var tx := {
		"amount": -amount,
		"source": ledger_source,
		"reason": "bribe_" + intent.target,
		"actor": "BribeHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", IntentTypes.BRIBE)

	if intent.parameters.get("confiscate_contraband", false) or intent.parameters.get("confiscate", false):
		for good_id in CargoSystem.get_contraband_keys():
			CargoSystem.remove_all_of(good_id)

	var attention_delta: int = int(intent.parameters.get("attention_delta", DEFAULT_ATTENTION_DELTA))
	GameState.pu_attention = clampi(GameState.pu_attention + attention_delta, 0, PU_ATTENTION_MAX)

	if intent.parameters.get("grant_permit", false):
		GameState.has_customs_permit = true

	if intent.parameters.get("grant_departure", false):
		GameState.set_flag("departure_authorized")

	var r := IntentResult.ok({
		"amount": amount,
		"balance": LedgerSystem.get_balance(),
		"pu_attention": GameState.pu_attention,
		"has_customs_permit": GameState.has_customs_permit,
	}, TextKeys.INTENT_BRIBE_SUCCESS)
	r.type = IntentTypes.BRIBE
	return r