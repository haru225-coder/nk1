class_name CargoSystem extends RefCounted

# 货物数据的唯一持有者（单一数据源）
static var _cargo: Dictionary = {}
# 货物总量计数器 - 避免每次 get_total_cargo() 遍历
static var _total: int = 0

# ── 读取接口 ──────────────────────────────────────────────

static func get_all() -> Dictionary:
	return _cargo.duplicate()

static func get_amount(good_id: String) -> int:
	return _cargo.get(good_id, 0)

static func get_keys() -> Array:
	return _cargo.keys()

static func is_empty() -> bool:
	return _cargo.is_empty()

static func get_total_cargo() -> int:
	return _total

static func has_space_for(amount: int) -> bool:
	if amount <= 0:
		return false
	return _total + amount <= GameState.max_cargo

static func get_available_space() -> int:
	return GameState.max_cargo - _total

static func has_item(good_id: String, amount: int = 1) -> bool:
	return _cargo.get(good_id, 0) >= amount

# ── 写入接口 ──────────────────────────────────────────────

static func add_item(good_id: String, amount: int) -> bool:
	if good_id.is_empty() or amount <= 0:
		return false
	if not has_space_for(amount):
		return false
	if not _cargo.has(good_id):
		_cargo[good_id] = 0
	_cargo[good_id] += amount
	_total += amount
	return true

static func remove_item(good_id: String, amount: int) -> bool:
	if good_id.is_empty() or amount <= 0:
		return false
	if not has_item(good_id, amount):
		return false
	_cargo[good_id] -= amount
	_total -= amount
	if _cargo[good_id] <= 0:
		_cargo.erase(good_id)
	return true

static func remove_all_of(good_id: String) -> int:
	var amount = _cargo.get(good_id, 0)
	if amount > 0:
		_cargo.erase(good_id)
		_total -= amount
	return amount

static func clear_all() -> void:
	_cargo.clear()
	_total = 0

static func remove_random_item() -> String:
	if _cargo.is_empty():
		return ""
	var keys = _cargo.keys()
	var key = keys[randi() % keys.size()]
	remove_item(key, 1)
	return key

static func remove_fraction(ratio: float) -> int:
	if ratio <= 0.0 or is_empty():
		return 0
	var to_remove := int(ceil(float(_total) * ratio))
	var removed := 0
	while removed < to_remove and not is_empty():
		remove_random_item()
		removed += 1
	return removed

# ── 显示辅助 ──────────────────────────────────────────────

static func to_display_string(separator: String = "\n") -> String:
	if _cargo.is_empty():
		return "空"
	var parts: PackedStringArray = []
	for key in _cargo.keys():
		parts.append(key + " x" + str(_cargo[key]))
	var result := ""
	for i in range(parts.size()):
		if i > 0:
			result += separator
		result += parts[i]
	return result

# ── 查询辅助 ──────────────────────────────────────────────

static func get_contraband_keys() -> Array:
	var result: Array = []
	for good_id in _cargo.keys():
		if _cargo[good_id] > 0:
			var g_data = GameManager.get_good_data(good_id)
			if g_data.get("legality") == "contraband":
				result.append(good_id)
	return result

static func to_save_dict() -> Dictionary:
	return {"cargo": _cargo.duplicate(), "total": _total}

static func from_save_dict(data: Dictionary) -> void:
	_cargo = data.get("cargo", {}).duplicate()
	_total = int(data.get("total", 0))

static func to_dict() -> Dictionary:
	return to_save_dict()

static func from_dict(d: Dictionary) -> void:
	from_save_dict(d)
