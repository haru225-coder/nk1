class_name CargoSystem extends RefCounted

static func get_total_cargo() -> int:
	var total = 0
	for count in GameState.cargo.values():
		total += count
	return total

static func has_space_for(amount: int) -> bool:
	return get_total_cargo() + amount <= GameState.max_cargo

static func get_available_space() -> int:
	return GameState.max_cargo - get_total_cargo()

static func has_item(good_id: String, amount: int = 1) -> bool:
	return GameState.cargo.get(good_id, 0) >= amount

static func add_item(good_id: String, amount: int) -> bool:
	if not has_space_for(amount): return false
	if not GameState.cargo.has(good_id):
		GameState.cargo[good_id] = 0
	GameState.cargo[good_id] += amount
	return true

static func remove_item(good_id: String, amount: int) -> bool:
	if not has_item(good_id, amount): return false
	GameState.cargo[good_id] -= amount
	if GameState.cargo[good_id] <= 0:
		GameState.cargo.erase(good_id)
	return true
