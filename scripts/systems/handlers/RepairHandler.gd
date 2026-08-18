class_name RepairHandler extends RefCounted

## ── 修理默认值常量 ───────────────────────────────────────
const COST_PER_HP := 2.0  ## 与 ShipyardController.SHIPYARD_REPAIR_COST_PER_HP 一致

func handle(intent: Intent) -> IntentResult:
	var ship_index: int = int(intent.parameters.get("ship_index", 0))
	var fleet := GameState.fleet
	if ship_index < 0 or ship_index >= fleet.ships.size():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "无效的船只索引", IntentTypes.REPAIR_SHIP)

	var ship: ShipState = fleet.ships[ship_index]
	var missing_hp: float = ship.max_hp - ship.hp
	if missing_hp <= 0.0:
		var full := IntentResult.ok({
			"ship_index": ship_index,
			"hp": ship.hp,
			"repaired": 0.0,
			"cost": 0,
		}, TextKeys.INTENT_REPAIR_ALREADY_FULL)
		full.type = IntentTypes.REPAIR_SHIP
		return full

	var repair_amount: float
	if intent.parameters.has("repair_ratio"):
		repair_amount = missing_hp * clampf(float(intent.parameters["repair_ratio"]), 0.0, 1.0)
	else:
		repair_amount = float(intent.parameters.get("repair_amount", missing_hp))
	repair_amount = minf(repair_amount, missing_hp)
	if repair_amount <= 0.0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "修理量为零", IntentTypes.REPAIR_SHIP)

	var cost: int = ceili(repair_amount * COST_PER_HP)
	if cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "修理费用无效", IntentTypes.REPAIR_SHIP)

	var tx := {
		"amount": -cost,
		"source": "gameplay",
		"reason": "repair_ship_%d" % ship_index,
		"actor": "RepairHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.REPAIR_SHIP)

	ship.hp = minf(ship.hp + repair_amount, ship.max_hp)
	if ship_index == 0:
		GameState._sync_world_map_ship_hp()

	var r := IntentResult.ok({
		"ship_index": ship_index,
		"hp": ship.hp,
		"repaired": repair_amount,
		"cost": cost,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_REPAIR_SUCCESS)
	r.type = IntentTypes.REPAIR_SHIP
	return r