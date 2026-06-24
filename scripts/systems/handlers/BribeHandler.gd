class_name BribeHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var amount: int = int(intent.parameters.get("amount", 50))
	var ledger_source := "encounter" if intent.source == "player_fleet" else "gameplay"
	var tx := {
		"amount": -amount,
		"source": ledger_source,
		"reason": "bribe_" + intent.target,
		"actor": "BribeHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", "bribe")

	if intent.parameters.get("confiscate_contraband", false) or intent.parameters.get("confiscate", false):
		for good_id in CargoSystem.get_contraband_keys():
			CargoSystem.remove_all_of(good_id)

	var attention_delta: int = int(intent.parameters.get("attention_delta", 3))
	GameState.pu_attention = clampi(GameState.pu_attention + attention_delta, 0, 20)

	if intent.parameters.get("grant_permit", false):
		GameState.has_customs_permit = true

	if intent.parameters.get("grant_departure", false):
		GameState.set_flag("departure_authorized")

	var r := IntentResult.ok({
		"amount": amount,
		"balance": LedgerSystem.get_balance(),
		"pu_attention": GameState.pu_attention,
		"has_customs_permit": GameState.has_customs_permit,
	}, "intent.bribe.success")
	r.type = "bribe"
	return r