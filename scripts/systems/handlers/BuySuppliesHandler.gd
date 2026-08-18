class_name BuySuppliesHandler extends RefCounted

## ── 补给默认值常量 ───────────────────────────────────────
const SUPPLY_FILL_FLAT_COST := 20         ## 补满水粮的固定费用
const SUPPLY_PARTIAL_AMOUNT := 20.0       ## 与 ShipyardController.SUPPLY_PARTIAL_AMOUNT 一致
const SUPPLY_PARTIAL_COST := 10           ## 与 ShipyardController.SUPPLY_PARTIAL_COST 一致
const MAX_AMMO_PER_BUY := 20
const AMMO_UNIT_PRICE := 5

func handle(intent: Intent) -> IntentResult:
	var supply_type := str(intent.parameters.get("supply_type", "food_water"))
	var fill_to_max := bool(intent.parameters.get("fill_to_max", false))
	var amount := float(intent.parameters.get("amount", 0.0))
	var applied := _preview_supply(supply_type, amount, fill_to_max)

	if applied.is_empty():
		return IntentResult.error(IntentErrorCodes.SUPPLY_LIMIT_REACHED, "", IntentTypes.BUY_SUPPLIES)

	var total_cost := _compute_total_cost(supply_type, fill_to_max, applied)

	if total_cost <= 0:
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, "", IntentTypes.BUY_SUPPLIES)

	var tx := {
		"amount": -total_cost,
		"source": "gameplay",
		"reason": "buy_supplies_%s" % supply_type,
		"actor": "BuySuppliesHandler",
	}
	if not LedgerSystem.apply(tx, intent.id):
		return IntentResult.error(IntentErrorCodes.INSUFFICIENT_FUNDS, "", IntentTypes.BUY_SUPPLIES)

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

static func supply_unit_price() -> float:
	return float(SUPPLY_PARTIAL_COST) / SUPPLY_PARTIAL_AMOUNT

## 按实际缺额计价，至少收一口价，避免大舱位 20 钱补满。
static func estimate_fill_cost() -> int:
	var food_need := maxf(0.0, GameState.max_food - GameState.food)
	var water_need := maxf(0.0, GameState.max_water - GameState.water)
	return cost_for_units(food_need + water_need, true)

static func cost_for_units(units: float, apply_fill_floor: bool = false) -> int:
	if units <= 0.0:
		return 0
	var raw := ceili(units * supply_unit_price())
	if apply_fill_floor:
		return maxi(SUPPLY_FILL_FLAT_COST, raw)
	return raw

func _compute_total_cost(supply_type: String, fill_to_max: bool, applied: Dictionary) -> int:
	if supply_type == "ammo":
		return int(applied.get("ammo_added", 0)) * AMMO_UNIT_PRICE
	var units := 0.0
	match supply_type:
		"food":
			units = float(applied.get("food_added", 0.0))
		"water":
			units = float(applied.get("water_added", 0.0))
		"food_water":
			units = float(applied.get("food_added", 0.0)) + float(applied.get("water_added", 0.0))
		_:
			return 0
	return cost_for_units(units, fill_to_max and supply_type == "food_water")

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
			var ammo_amount := clampi(int(amount), 0, MAX_AMMO_PER_BUY)
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
			GameState.modify_artillery(int(applied.get("ammo_added", 0)))

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
		GameState.set_food_amount(GameState.max_food)
	elif amount > 0.0:
		GameState.modify_food(amount)

func _apply_water(amount: float, fill_to_max: bool) -> void:
	if fill_to_max:
		GameState.set_water_amount(GameState.max_water)
	elif amount > 0.0:
		GameState.modify_water(amount)
