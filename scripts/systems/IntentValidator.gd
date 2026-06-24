class_name IntentValidator extends RefCounted

static func validate(intent: Intent) -> IntentResult:
	if intent.type.is_empty():
		return _validation_error(intent, "error.intent.missing_type")

	if intent.source.is_empty():
		return _validation_error(intent, "error.intent.missing_source")

	if intent.target.is_empty():
		return _validation_error(intent, "error.intent.missing_target")

	match intent.type:
		"payment":
			return _validate_payment(intent)
		"combat_request":
			if intent.source == intent.target:
				return _validation_error(intent, "error.intent.combat.self_target")
		"market_buy", "market_sell":
			return _validate_market(intent)
		"trade_request":
			return _validate_trade_request(intent)
		"bribe":
			return _validate_bribe(intent)
		"repair_ship":
			return _validate_repair_ship(intent)
		"inspection_pass":
			return _validate_inspection_pass(intent)

	return IntentResult.new(true, "validation_ok")

static func _validation_error(intent: Intent, message_key: String) -> IntentResult:
	return IntentResult.error(IntentErrorCodes.VALIDATION_ERROR, message_key, intent.type)

static func _validate_payment(intent: Intent) -> IntentResult:
	if not intent.parameters.has("amount"):
		return _validation_error(intent, "error.intent.payment.missing_amount")
	var amount_type := typeof(intent.parameters["amount"])
	if amount_type != TYPE_INT and amount_type != TYPE_FLOAT:
		return _validation_error(intent, "error.intent.payment.invalid_amount")
	var amount := int(intent.parameters["amount"])
	if amount < 0:
		return _validation_error(intent, "error.intent.payment.negative_amount")
	if amount > 0 and LedgerSystem.get_balance() < amount:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.payment.insufficient_funds", intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_bribe(intent: Intent) -> IntentResult:
	if not intent.parameters.has("amount"):
		return _validation_error(intent, "error.bribe.missing_amount")
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		return _validation_error(intent, "error.bribe.invalid_amount")
	if intent.parameters.get("smuggling_departure", false) or intent.context.get("customs_departure", false):
		if GameState.pu_attention >= 15:
			return IntentResult.error(IntentErrorCodes.CUSTOMS_BLOCKED, "error.bribe.customs_blocked", intent.type)
	if LedgerSystem.get_balance() < amount:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.bribe.insufficient_funds", intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_market(intent: Intent) -> IntentResult:
	if not intent.parameters.has("good_id"):
		return _validation_error(intent, "error.intent.market.missing_good")
	var good_id := str(intent.parameters.get("good_id", ""))
	if good_id.is_empty():
		return _validation_error(intent, "error.intent.market.missing_good")
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		return _validation_error(intent, "error.intent.market.invalid_amount")
	var port_id := str(intent.context.get("port_id", ""))
	if port_id.is_empty():
		return _validation_error(intent, "error.market.no_port")

	if intent.type == "market_buy":
		var price := EconomySystem.get_price(port_id, good_id)
		if price <= 0:
			return IntentResult.error(IntentErrorCodes.INVALID_STATE, "error.market.invalid_price", intent.type)
		if LedgerSystem.get_balance() < price * amount:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.market.insufficient_funds", intent.type)
		if not CargoSystem.has_space_for(amount):
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, "error.market.cargo_full", intent.type)
	elif intent.type == "market_sell":
		if not CargoSystem.has_item(good_id, amount):
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, "error.market.missing_goods", intent.type)

	return IntentResult.new(true, "validation_ok")

static func _validate_trade_request(intent: Intent) -> IntentResult:
	var cost := int(intent.parameters.get("cost", 0))
	if cost <= 0:
		return _validation_error(intent, "error.intent.trade.missing_cost")
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.trade.insufficient_funds", intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_repair_ship(intent: Intent) -> IntentResult:
	var ship_index := int(intent.parameters.get("ship_index", 0))
	var fleet := GameState.fleet
	if ship_index < 0 or ship_index >= fleet.ships.size():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "error.repair.invalid_ship", intent.type)

	var ship: ShipState = fleet.ships[ship_index]
	var missing_hp: float = ship.max_hp - ship.hp
	if missing_hp <= 0.0:
		return IntentResult.new(true, "validation_ok")

	var repair_amount: float
	if intent.parameters.has("repair_ratio"):
		repair_amount = missing_hp * clampf(float(intent.parameters["repair_ratio"]), 0.0, 1.0)
	else:
		repair_amount = float(intent.parameters.get("repair_amount", missing_hp))
	repair_amount = minf(repair_amount, missing_hp)
	if repair_amount <= 0.0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "error.repair.invalid_amount", intent.type)

	var cost: int
	if intent.parameters.has("cost"):
		cost = int(intent.parameters["cost"])
	else:
		var cost_per_hp: float = float(intent.parameters.get("cost_per_hp", 1.0))
		cost = ceili(repair_amount * cost_per_hp)
	if cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "error.repair.invalid_cost", intent.type)
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.repair.insufficient_funds", intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_inspection_pass(intent: Intent) -> IntentResult:
	var violation := EncounterSystem.calculate_cargo_violation()
	if violation == "illegal_trade":
		if LedgerSystem.get_balance() < 30:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "error.inspection.no_funds", intent.type)
	return IntentResult.new(true, "validation_ok")