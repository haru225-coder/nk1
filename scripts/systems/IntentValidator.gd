class_name IntentValidator extends RefCounted

static func validate(intent: Intent) -> IntentResult:
	if intent.type.is_empty():
		return _validation_error(intent, TextKeys.ERROR_INTENT_MISSING_TYPE)

	if intent.source.is_empty():
		return _validation_error(intent, TextKeys.ERROR_INTENT_MISSING_SOURCE)

	if intent.target.is_empty():
		return _validation_error(intent, TextKeys.ERROR_INTENT_MISSING_TARGET)

	match intent.type:
		IntentTypes.PAYMENT:
			return _validate_payment(intent)
		IntentTypes.COMBAT_REQUEST:
			if intent.source == intent.target:
				return _validation_error(intent, TextKeys.ERROR_INTENT_COMBAT_SELF_TARGET)
		IntentTypes.MARKET_BUY, IntentTypes.MARKET_SELL:
			return _validate_market(intent)
		IntentTypes.TRADE_REQUEST:
			return _validate_trade_request(intent)
		IntentTypes.BRIBE:
			return _validate_bribe(intent)
		IntentTypes.REPAIR_SHIP:
			return _validate_repair_ship(intent)
		IntentTypes.REFIT_SHIP:
			return _validate_refit_ship(intent)
		IntentTypes.HIRE_CREW:
			return _validate_hire_crew(intent)
		IntentTypes.BUY_SUPPLIES:
			return _validate_buy_supplies(intent)
		IntentTypes.BUY_INTEL:
			return _validate_buy_intel(intent)
		IntentTypes.INSPECTION_PASS:
			return _validate_inspection_pass(intent)

	return IntentResult.new(true, "validation_ok")

static func _validation_error(intent: Intent, message_key: String) -> IntentResult:
	return IntentResult.error(IntentErrorCodes.VALIDATION_ERROR, message_key, intent.type)

static func _validate_payment(intent: Intent) -> IntentResult:
	if not intent.parameters.has("amount"):
		return _validation_error(intent, TextKeys.ERROR_INTENT_PAYMENT_MISSING_AMOUNT)
	var amount_type := typeof(intent.parameters["amount"])
	if amount_type != TYPE_INT and amount_type != TYPE_FLOAT:
		return _validation_error(intent, TextKeys.ERROR_INTENT_PAYMENT_INVALID_AMOUNT)
	var amount := int(intent.parameters["amount"])
	if amount < 0:
		return _validation_error(intent, TextKeys.ERROR_INTENT_PAYMENT_NEGATIVE_AMOUNT)
	if amount > 0 and LedgerSystem.get_balance() < amount:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_PAYMENT_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_bribe(intent: Intent) -> IntentResult:
	if not intent.parameters.has("amount"):
		return _validation_error(intent, TextKeys.ERROR_BRIBE_MISSING_AMOUNT)
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		return _validation_error(intent, TextKeys.ERROR_BRIBE_INVALID_AMOUNT)
	if intent.parameters.get("smuggling_departure", false) or intent.context.get("customs_departure", false):
		if GameState.pu_attention >= TradeState.CUSTOMS_BLOCKED_ATTENTION:
			return IntentResult.error(IntentErrorCodes.CUSTOMS_BLOCKED, TextKeys.ERROR_BRIBE_CUSTOMS_BLOCKED, intent.type)
	if LedgerSystem.get_balance() < amount:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_BRIBE_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_market(intent: Intent) -> IntentResult:
	if not intent.parameters.has("good_id"):
		return _validation_error(intent, TextKeys.ERROR_INTENT_MARKET_MISSING_GOOD)
	var good_id := str(intent.parameters.get("good_id", ""))
	if good_id.is_empty():
		return _validation_error(intent, TextKeys.ERROR_INTENT_MARKET_MISSING_GOOD)
	var amount := int(intent.parameters.get("amount", 0))
	if amount <= 0:
		return _validation_error(intent, TextKeys.ERROR_INTENT_MARKET_INVALID_AMOUNT)
	var port_id := str(intent.context.get("port_id", ""))
	if port_id.is_empty():
		return _validation_error(intent, TextKeys.ERROR_MARKET_NO_PORT)

	if intent.type == IntentTypes.MARKET_BUY:
		var price := EconomySystem.get_price(port_id, good_id)
		if price <= 0:
			return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_MARKET_INVALID_PRICE, intent.type)
		if LedgerSystem.get_balance() < price * amount:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_MARKET_INSUFFICIENT_FUNDS, intent.type)
		if not CargoSystem.has_space_for(amount):
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, TextKeys.ERROR_MARKET_CARGO_FULL, intent.type)
	elif intent.type == IntentTypes.MARKET_SELL:
		if not CargoSystem.has_item(good_id, amount):
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_CARGO, TextKeys.ERROR_MARKET_MISSING_GOODS, intent.type)

	return IntentResult.new(true, "validation_ok")

static func _validate_trade_request(intent: Intent) -> IntentResult:
	var cost := int(intent.parameters.get("cost", 0))
	if cost <= 0:
		return _validation_error(intent, TextKeys.ERROR_INTENT_TRADE_MISSING_COST)
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_TRADE_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_repair_ship(intent: Intent) -> IntentResult:
	var ship_index := int(intent.parameters.get("ship_index", 0))
	var fleet := GameState.fleet
	if ship_index < 0 or ship_index >= fleet.ships.size():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REPAIR_INVALID_SHIP, intent.type)

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
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REPAIR_INVALID_AMOUNT, intent.type)

	var cost: int
	if intent.parameters.has("cost"):
		cost = int(intent.parameters["cost"])
	else:
		var cost_per_hp: float = float(intent.parameters.get("cost_per_hp", 1.0))
		cost = ceili(repair_amount * cost_per_hp)
	if cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REPAIR_INVALID_COST, intent.type)
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_REPAIR_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_refit_ship(intent: Intent) -> IntentResult:
	var refit_mode := str(intent.parameters.get("refit_mode", "sail"))
	if refit_mode == "hull":
		return _validate_hull_change(intent)
	return _validate_sail_change(intent)


static func _validate_sail_change(intent: Intent) -> IntentResult:
	var cost := int(intent.parameters.get("cost", 500))
	if cost <= 0:
		return _validation_error(intent, TextKeys.ERROR_REFIT_INVALID_COST)
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_REFIT_INSUFFICIENT_FUNDS, intent.type)
	var current_type := GameState.sail_type
	var new_type := str(intent.parameters.get("sail_type", ""))
	if new_type.is_empty():
		new_type = "lateen" if current_type == "square" else "square"
	if new_type == current_type:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_SAME_SAIL, intent.type)
	if new_type not in ["square", "lateen"]:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_SAIL, intent.type)
	return IntentResult.new(true, "validation_ok")


static func _validate_hull_change(intent: Intent) -> IntentResult:
	var hull_id := str(intent.parameters.get("hull_id", ""))
	if hull_id.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_HULL, intent.type)
	var hull := ShipSystem.get_hull(hull_id)
	if hull.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_HULL, intent.type)
	if not ShipSystem._is_shipyard_candidate(hull):
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_INVALID_HULL, intent.type)
	if not ShipSystem.is_hull_unlocked(hull, GameState.fame, GameState.has_story_flag):
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_HULL_LOCKED, intent.type)

	var flagship := GameState.fleet.get_flagship()
	if flagship != null and hull_id == flagship.hull_id:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_REFIT_SAME_HULL, intent.type)

	var cost := int(intent.parameters.get("cost", ShipSystem.get_hull_change_cost(hull_id)))
	if cost <= 0:
		return _validation_error(intent, TextKeys.ERROR_REFIT_INVALID_COST)
	if LedgerSystem.get_balance() < cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_REFIT_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_hire_crew(intent: Intent) -> IntentResult:
	var port_id := str(intent.context.get("port_id", ""))
	if port_id.is_empty():
		return IntentResult.error(IntentErrorCodes.PORT_RECRUIT_BLOCKED, TextKeys.ERROR_HIRE_CREW_NO_PORT, intent.type)

	var cost_per_crew := int(intent.parameters.get("cost_per_crew", 10))
	if cost_per_crew <= 0:
		return _validation_error(intent, TextKeys.ERROR_HIRE_CREW_INVALID_COST)

	var space := GameState.max_crew - GameState.crew_count
	if space <= 0:
		return IntentResult.error(IntentErrorCodes.CREW_LIMIT_REACHED, TextKeys.ERROR_HIRE_CREW_FULL, intent.type)

	var crew_count := int(intent.parameters.get("crew_count", 0))
	if crew_count <= 0 or intent.parameters.get("recruit_max", false):
		if LedgerSystem.get_balance() < cost_per_crew:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_HIRE_CREW_INSUFFICIENT_FUNDS, intent.type)
	else:
		crew_count = mini(crew_count, space)
		if crew_count <= 0:
			return IntentResult.error(IntentErrorCodes.CREW_LIMIT_REACHED, TextKeys.ERROR_HIRE_CREW_FULL, intent.type)
		var total_cost := int(intent.parameters.get("total_cost", crew_count * cost_per_crew))
		if LedgerSystem.get_balance() < total_cost:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_HIRE_CREW_INSUFFICIENT_FUNDS, intent.type)

	return IntentResult.new(true, "validation_ok")

static func _validate_buy_supplies(intent: Intent) -> IntentResult:
	var supply_type := str(intent.parameters.get("supply_type", ""))
	if supply_type.is_empty():
		return _validation_error(intent, TextKeys.ERROR_BUY_SUPPLIES_MISSING_TYPE)

	var fill_to_max := bool(intent.parameters.get("fill_to_max", false))
	var amount := float(intent.parameters.get("amount", 0.0))
	var total_cost := int(intent.parameters.get("total_cost", 0))
	var unit_price := float(intent.parameters.get("unit_price", 0.0))

	match supply_type:
		"food":
			if not _has_supply_headroom("food", amount, fill_to_max):
				return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, TextKeys.ERROR_BUY_SUPPLIES_FOOD_FULL, intent.type)
		"water":
			if not _has_supply_headroom("water", amount, fill_to_max):
				return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, TextKeys.ERROR_BUY_SUPPLIES_WATER_FULL, intent.type)
		"food_water":
			if fill_to_max:
				if GameState.food >= GameState.max_food and GameState.water >= GameState.max_water:
					return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, TextKeys.ERROR_BUY_SUPPLIES_FULL, intent.type)
			elif amount <= 0.0:
				return _validation_error(intent, TextKeys.ERROR_BUY_SUPPLIES_INVALID_AMOUNT)
			else:
				if GameState.food >= GameState.max_food and GameState.water >= GameState.max_water:
					return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, TextKeys.ERROR_BUY_SUPPLIES_FULL, intent.type)
		"ammo":
			if int(intent.parameters.get("amount", amount)) <= 0:
				return _validation_error(intent, TextKeys.ERROR_BUY_SUPPLIES_INVALID_AMOUNT)
		_:
			return _validation_error(intent, TextKeys.ERROR_BUY_SUPPLIES_INVALID_TYPE)

	if total_cost <= 0:
		if unit_price > 0.0 and amount > 0.0:
			total_cost = ceili(amount * unit_price)
		elif fill_to_max and supply_type == "food_water":
			total_cost = 20
		else:
			return _validation_error(intent, TextKeys.ERROR_BUY_SUPPLIES_INVALID_COST)

	if LedgerSystem.get_balance() < total_cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_BUY_SUPPLIES_INSUFFICIENT_FUNDS, intent.type)

	return IntentResult.new(true, "validation_ok")

static func _has_supply_headroom(resource: String, amount: float, fill_to_max: bool) -> bool:
	if fill_to_max:
		if resource == "food":
			return GameState.food < GameState.max_food
		if resource == "water":
			return GameState.water < GameState.max_water
		return false
	if amount <= 0.0:
		return false
	if resource == "food":
		return GameState.food < GameState.max_food
	if resource == "water":
		return GameState.water < GameState.max_water
	return false

static func _validate_buy_intel(intent: Intent) -> IntentResult:
	var tier := int(intent.parameters.get("tier", 0))
	if tier < 1 or tier > 3:
		return _validation_error(intent, TextKeys.ERROR_BUY_INTEL_INVALID_TIER)
	var expected_cost := TradeEventGenerator.get_tier_cost(tier)
	var total_cost := int(intent.parameters.get("total_cost", 0))
	if total_cost != expected_cost:
		return _validation_error(intent, TextKeys.ERROR_BUY_INTEL_INVALID_COST)
	var event_index := int(intent.parameters.get("event_index", -1))
	if TradeEventGenerator.get_event_at(event_index).is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_BUY_INTEL_INVALID_EVENT, intent.type)
	if TradeEventGenerator.is_rumor_purchased(event_index):
		return IntentResult.error(IntentErrorCodes.INTEL_ALREADY_PURCHASED, TextKeys.ERROR_BUY_INTEL_ALREADY_PURCHASED, intent.type)
	if LedgerSystem.get_balance() < total_cost:
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_BUY_INTEL_INSUFFICIENT_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")

static func _validate_inspection_pass(intent: Intent) -> IntentResult:
	var violation := EncounterSystem.calculate_cargo_violation()
	if violation == "illegal_trade":
		if LedgerSystem.get_balance() < InspectionHandler.ILLEGAL_TRADE_FINE:
			return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, TextKeys.ERROR_INSPECTION_NO_FUNDS, intent.type)
	return IntentResult.new(true, "validation_ok")