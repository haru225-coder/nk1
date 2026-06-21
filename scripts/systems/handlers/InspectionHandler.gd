class_name InspectionHandler extends RefCounted

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.new(false, "inspection_pass", "error.intent.duplicate")

	var violation := EncounterSystem.calculate_cargo_violation()
	match violation:
		"contraband":
			return IntentResult.new(false, "inspection_pass", "error.inspection.contraband")
		"illegal_trade":
			if LedgerSystem.get_balance() < 30:
				return IntentResult.new(false, "inspection_pass", "error.inspection.no_funds")
			LedgerSystem.apply({
				"amount": -30,
				"source": "encounter",
				"reason": "sea_patrol_fine",
				"actor": "InspectionHandler"
			}, "")
			GameState.modify_fame(-2)
			return IntentResult.new(true, "inspection_pass", "intent.inspection.fined")
		_:
			GameState.modify_fame(1)
			return IntentResult.new(true, "inspection_pass", "intent.inspection.cleared")