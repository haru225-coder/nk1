class_name CombatHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.new(false, "combat_request", "error.intent.duplicate")
	GameState.modify_fame(-10)
	GameState.modify_crew(-5)
	if LedgerSystem.get_balance() > 100:
		LedgerSystem.apply({
			"amount": -100,
			"source": "combat",
			"reason": "combat_loss",
			"actor": "CombatHandler"
		}, "")
	return IntentResult.new(true, "combat_request", "intent.combat.started")