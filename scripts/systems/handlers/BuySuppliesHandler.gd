class_name BuySuppliesHandler extends RefCounted

## ── 补给默认值常量 ───────────────────────────────────────
const SUPPLY_FILL_FLAT_COST := 20         ## 补满水粮的固定费用

func handle(intent: Intent) -> IntentResult:
	var supply_type := str(intent.parameters.get("supply_type", "food_water"))
	var fill_to_max := bool(intent.parameters.get("fill_to_max", false))
	var amount := float(intent.parameters.get("amount", 0.0))
	var unit_price := float(intent.parameters.get("unit_price", 0.0))
	var total_cost := int(intent.parameters.get("total_cost", 0))
	var applied := _preview_supply(supply_type, amount, fill_to_max)

	if applied.is_empty():
		return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, "", IntentTypes.BUY_SUPPLIES)

	if total_cost <= 0:
		if unit_price > 0.0:
			var units := float(applied.get("food_added", applied.get("water_added", applied.get("ammo_added", 0))))
			if supply_type == "food_water":
				units = float(applied.get("food_added", 0.0)) + float(applied.get("water_added", 0.0))
			total_cost = ceili(units * unit_price)
		elif fill_to_max and supply_type == "food_water":
			total_cost = SUPPLY_FILL_FLAT_COST

	if total_cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "", IntentTypes.BUY_SUPPLIES)

	var tx := {
		"amount": -total_cost,
		"source": "gameplay",
		"reason": "buy_supplies_%s" % supply_type,
		"actor": "BuySuppliesHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.TRANSACTION_FAILED, "", IntentTypes.BUY_SUPPLIES)

	_commit_supply(supply_type, amount, fill_to_max, applied)

	var r := IntentResult.ok({
		"supply_type": supply_type,
		"total_cost": total_cost,
		"applied": applied,
		"food": GameState.food,
		"water": GameState.water,
		"balance": LedgerSystem.get_balance(),
	}, TextKeys.INTENT_BUY_SUPPLIES_SUCCESS)
	r.type = IntentTypes.BUY_SUPPLIES
	return r

func _preview_supply(supply_type: String, amount: float, fill_to_max: bool) -> Dictionary:
	match supply_type:
		"food":
			return _preview_food(amount, fill_to_max)
		"water":
			return _preview_water(amount, fill_to_max)
		"food_water":
			if fill_to_max:
				return _preview_food_water_fill()
			var food_applied := _preview_food(amount, false)
			var water_applied := _preview_water(amount, false)
			if food_applied.is_empty() and water_applied.is_empty():
				return {}
			return {
				"food_added": food_applied.get("food_added", 0.0),
				"water_added": water_applied.get("water_added", 0.0),
			}
		"ammo":
			var ammo_amount := int(amount)
			if ammo_amount <= 0:
				return {}
			return {"ammo_added": ammo_amount}
	return {}

func _commit_supply(supply_type: String, amount: float, fill_to_max: bool, applied: Dictionary) -> void:
	match supply_type:
		"food":
			_apply_food(amount, fill_to_max)
		"water":
			_apply_water(amount, fill_to_max)
		"food_water":
			if fill_to_max:
				_apply_food(0.0, true)
				_apply_water(0.0, true)
			else:
				_apply_food(amount, false)
				_apply_water(amount, false)
		"ammo":
			GameState.artillery = maxi(0, GameState.artillery + int(applied.get("ammo_added", 0)))

func _preview_food(amount: float, fill_to_max: bool) -> Dictionary:
	if fill_to_max:
		if GameState.food >= GameState.max_food:
			return {}
		return {"food_added": GameState.max_food - GameState.food}
	if amount <= 0.0 or GameState.food >= GameState.max_food:
		return {}
	return {"food_added": minf(amount, GameState.max_food - GameState.food)}

func _preview_water(amount: float, fill_to_max: bool) -> Dictionary:
	if fill_to_max:
		if GameState.water >= GameState.max_water:
			return {}
		return {"water_added": GameState.max_water - GameState.water}
	if amount <= 0.0 or GameState.water >= GameState.max_water:
		return {}
	return {"water_added": minf(amount, GameState.max_water - GameState.water)}

func _preview_food_water_fill() -> Dictionary:
	var food_applied := _preview_food(0.0, true)
	var water_applied := _preview_water(0.0, true)
	if food_applied.is_empty() and water_applied.is_empty():
		return {}
	return {
		"food_added": food_applied.get("food_added", 0.0),
		"water_added": water_applied.get("water_added", 0.0),
	}

func _apply_food(amount: float, fill_to_max: bool) -> void:
	if fill_to_max:
		GameState.food = GameState.max_food
	elif amount > 0.0:
		GameState.food = minf(GameState.food + amount, GameState.max_food)

func _apply_water(amount: float, fill_to_max: bool) -> void:
	if fill_to_max:
		GameState.water = GameState.max_water
	elif amount > 0.0:
		GameState.water = minf(GameState.water + amount, GameState.max_water)