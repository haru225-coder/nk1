class_name RefitHandler extends RefCounted

## ── 改装默认值常量 ───────────────────────────────────────
const SAIL_REFIT_COST := 500

func handle(intent: Intent) -> IntentResult:
	var refit_mode := str(intent.parameters.get("refit_mode", "sail"))
	if refit_mode == "hull":
		return _handle_hull_change(intent)
	return _handle_sail_change(intent)


func _handle_sail_change(intent: Intent) -> IntentResult:
	var cost := SAIL_REFIT_COST
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
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.REFIT_SHIP)

	GameState.set_sail_type(new_type)
	var r := IntentResult.ok({
		"refit_mode": "sail",
		"cost": cost,
		"sail_type": new_type,
		"previous_sail_type": current_type,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_REFIT_SUCCESS)
	r.type = IntentTypes.REFIT_SHIP
	return r


func _handle_hull_change(intent: Intent) -> IntentResult:
	var hull_id := str(intent.parameters.get("hull_id", ""))
	var cost := ShipSystem.get_hull_change_cost(hull_id)
	var flagship := GameState.fleet.get_flagship()
	var previous_hull_id := flagship.hull_id if flagship else ""
	if cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_HULL, IntentTypes.REFIT_SHIP)

	var tx := {
		"amount": -cost,
		"source": "gameplay",
		"reason": "refit_hull",
		"actor": "RefitHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.REFIT_SHIP)

	if not ShipSystem.apply_hull_to_flagship(flagship, hull_id):
		LedgerSystem.apply({
			"amount": cost,
			"source": "gameplay",
			"reason": "refit_hull_rollback",
			"actor": "RefitHandler",
		}, intent.id + ":rollback")
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_HULL, IntentTypes.REFIT_SHIP)

	var r := IntentResult.ok({
		"refit_mode": "hull",
		"cost": cost,
		"hull_id": hull_id,
		"hull_name": flagship.name,
		"previous_hull_id": previous_hull_id,
		"sail_type": flagship.sail_type,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_REFIT_SUCCESS)
	r.type = IntentTypes.REFIT_SHIP
	return r
