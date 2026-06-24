class_name RefitHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var cost := int(intent.parameters.get("cost", 500))
	var current_type := GameState.sail_type
	var new_type := str(intent.parameters.get("sail_type", ""))
	if new_type.is_empty():
		new_type = "lateen" if current_type == "square" else "square"

	var tx := {
		"amount": -cost,
		"source": "gameplay",
		"reason": "refit_sail",
		"actor": "RefitHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", "refit_ship")

	GameState.sail_type = new_type
	var r := IntentResult.ok({
		"cost": cost,
		"sail_type": new_type,
		"previous_sail_type": current_type,
		"balance": LedgerSystem.get_balance(),
	}, "intent.refit.success")
	r.type = "refit_ship"
	return r