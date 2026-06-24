class_name InspectionHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	return execute(intent)

func execute(intent: Intent) -> IntentResult:
	if not IdempotencyGuard.check_and_record(intent.id):
		return IntentResult.error(IntentErrorCodes.DUPLICATE_INTENT, "", "inspection_pass")

	var violation := EncounterSystem.calculate_cargo_violation()
	match violation:
		"contraband":
			return IntentResult.error(IntentErrorCodes.INVALID_STATE, "", "inspection_pass")
		"illegal_trade":
			LedgerSystem.apply({
				"amount": -30,
				"source": "encounter",
				"reason": "sea_patrol_fine",
				"actor": "InspectionHandler",
			}, intent.id)
			GameState.modify_fame(-2)
			var fined := IntentResult.ok({"fine": 30}, "intent.inspection.fined")
			fined.type = "inspection_pass"
			return fined
		_:
			GameState.modify_fame(1)
			var cleared := IntentResult.ok({}, "intent.inspection.cleared")
			cleared.type = "inspection_pass"
			return cleared