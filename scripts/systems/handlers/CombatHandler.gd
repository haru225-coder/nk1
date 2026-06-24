class_name CombatHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	return execute(intent)

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.error("error.intent.duplicate", "", "combat_request")
	GameState.modify_fame(-10)
	GameState.modify_crew(-5)
	if LedgerSystem.get_balance() > 100:
		LedgerSystem.apply({
			"amount": -100,
			"source": "combat",
			"reason": "combat_loss",
			"actor": "CombatHandler",
		}, intent.id)
	var r := IntentResult.ok({}, "intent.combat.started")
	r.type = "combat_request"
	return r