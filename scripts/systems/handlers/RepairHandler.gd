class_name RepairHandler extends RefCounted

func handle(intent: Intent) -> IntentResult:
	var ship_index: int = int(intent.parameters.get("ship_index", 0))
	var fleet := GameState.fleet
	if ship_index < 0 or ship_index >= fleet.ships.size():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "无效的船只索引", "repair_ship")

	var ship: ShipState = fleet.ships[ship_index]
	var missing_hp: float = ship.max_hp - ship.hp
	if missing_hp <= 0.0:
		var full := IntentResult.ok({
			"ship_index": ship_index,
			"hp": ship.hp,
			"repaired": 0.0,
			"cost": 0,
		}, "intent.repair.already_full")
		full.type = "repair_ship"
		return full

	var repair_amount: float
	if intent.parameters.has("repair_ratio"):
		repair_amount = missing_hp * clampf(float(intent.parameters["repair_ratio"]), 0.0, 1.0)
	else:
		repair_amount = float(intent.parameters.get("repair_amount", missing_hp))
	repair_amount = minf(repair_amount, missing_hp)
	if repair_amount <= 0.0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "修理量为零", "repair_ship")

	var cost: int
	if intent.parameters.has("cost"):
		cost = int(intent.parameters["cost"])
	else:
		var cost_per_hp: float = float(intent.parameters.get("cost_per_hp", 1.0))
		cost = ceili(repair_amount * cost_per_hp)
	if cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "修理费用无效", "repair_ship")

	var tx := {
		"amount": -cost,
		"source": "gameplay",
		"reason": "repair_ship_%d" % ship_index,
		"actor": "RepairHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", "repair_ship")

	ship.hp = minf(ship.hp + repair_amount, ship.max_hp)
	if ship_index == 0:
		GameState._sync_world_map_ship_hp()

	var r := IntentResult.ok({
		"ship_index": ship_index,
		"hp": ship.hp,
		"repaired": repair_amount,
		"cost": cost,
		"balance": LedgerSystem.get_balance(),
	}, "intent.repair.success")
	r.type = "repair_ship"
	return r