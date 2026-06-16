class_name CombatHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	GameState.modify_fame(-10)
	GameState.modify_crew(-5)
	if LedgerSystem.get_balance() > 100:
		LedgerSystem.apply({
			"amount": -100,
			"source": "combat",
			"reason": "combat_loss",
			"actor": "CombatHandler"
		}, intent.id)
	return IntentResult.new(true, "combat_request", "intent.combat.started")