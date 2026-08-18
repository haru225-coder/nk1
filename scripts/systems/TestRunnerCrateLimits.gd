extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	_test_crate_limit_constants()
	_test_scripts_and_ship_drop_source()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

func _const_map(script) -> Dictionary:
	if script == null:
		return {}
	if script.has_method("get_script_constant_map"):
		var mapped = script.get_script_constant_map()
		if mapped is Dictionary:
			return mapped
	return {}

func _test_crate_limit_constants() -> void:
	print("[CrateLimits constants]")

	var crate_script = _load_script_or_fail("res://scripts/Crate.gd", "Crate.gd loads")
	var world_script = _load_script_or_fail("res://scripts/WorldMap.gd", "WorldMap.gd loads")

	var crate_consts := _const_map(crate_script)
	var world_consts := _const_map(world_script)

	var interval_min := float(world_consts.get("CRATE_SPAWN_INTERVAL_MIN", 0.0))
	var money_max := int(crate_consts.get("MONEY_MAX", 999))
	var daily_cap := int(crate_consts.get("DAILY_PICKUP_CAP", world_consts.get("DAILY_PICKUP_CAP", 0)))
	var max_alive := int(world_consts.get("MAX_ALIVE_WORLD_CRATES", 0))

	_assert_true(interval_min >= 45.0, "WorldMap CRATE_SPAWN_INTERVAL_MIN >= 45")
	_assert_true(money_max <= 40, "Crate MONEY_MAX <= 40")
	_assert_eq(daily_cap, 8, "daily pickup cap == 8")
	_assert_eq(max_alive, 3, "WorldMap MAX_ALIVE_WORLD_CRATES == 3")

	if world_consts.has("DAILY_PICKUP_CAP"):
		_assert_eq(int(world_consts.get("DAILY_PICKUP_CAP", 0)), 8, "WorldMap DAILY_PICKUP_CAP == 8")
	if crate_consts.has("MONEY_MIN"):
		_assert_true(int(crate_consts.get("MONEY_MIN", 0)) >= 15, "Crate MONEY_MIN >= 15")

	print("")

func _test_scripts_and_ship_drop_source() -> void:
	print("[CrateLimits source]")

	var crate_script = _load_script_or_fail("res://scripts/Crate.gd", "Crate.gd script loads")
	var ship_script = _load_script_or_fail("res://scripts/Ship.gd", "Ship.gd script loads")
	_assert_not_null_script(crate_script, "Crate.gd Script")
	_assert_not_null_script(ship_script, "Ship.gd Script")

	var ship_src := FileAccess.get_file_as_string("res://scripts/Ship.gd")
	_assert_true(ship_src.contains("_drop_cargo_if_hit"), "Ship.gd contains _drop_cargo_if_hit")
	_assert_true(
		ship_src.contains("preset_good") or ship_src.contains("preset_good_id"),
		"Ship _drop_cargo_if_hit sets preset_good"
	)

	var crate_src := FileAccess.get_file_as_string("res://scripts/Crate.gd")
	_assert_true(crate_src.contains("world_crate"), "Crate.gd adds world_crate group")
	_assert_true(crate_src.contains("preset_good_id"), "Crate.gd has preset_good_id")
	_assert_true(not crate_src.contains("randi_range(100, 500)"), "Crate.gd no longer uses 100-500 money")

	var world_src := FileAccess.get_file_as_string("res://scripts/WorldMap.gd")
	_assert_true(world_src.contains("CRATE_SPAWN_INTERVAL_MIN"), "WorldMap.gd has spawn interval constant")
	_assert_true(world_src.contains("MAX_ALIVE_WORLD_CRATES"), "WorldMap.gd has max-alive constant")
	_assert_true(not world_src.contains("randf_range(10.0, 20.0)"), "WorldMap.gd no longer uses 10-20s crate interval")

	print("")

func _assert_not_null_script(value, msg: String) -> void:
	if _runner != null and _runner.has_method("_assert_not_null"):
		_runner._assert_not_null(value, msg)
	else:
		_assert_true(value != null, msg)
