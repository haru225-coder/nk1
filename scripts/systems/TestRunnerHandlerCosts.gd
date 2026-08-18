extends RefCounted

# ═══════════════════════════════════════════════════════════
# TestRunnerHandlerCosts — 权威费用 + 战利品幂等
# 由 TestRunner 以 runner ctor 接入：TestRunnerHandlerCosts.new(self).run()
# ═══════════════════════════════════════════════════════════

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	print("[HandlerCosts]")
	_test_source_scans()
	_test_repair_ignores_client_cost()
	_test_hire_ignores_client_cost()
	_test_supplies_ignores_client_cost()
	_test_refit_sail_ignores_client_cost()
	_test_loot_same_intent_id()
	_test_validator_uses_authoritative_repair_cost()
	_test_fill_cost_scales_with_deficit()
	_test_sea_event_choice_lock_source()
	_test_cargo_save_recomputes_total()
	print("")

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _test_source_scans() -> void:
	var repair_src := FileAccess.get_file_as_string("res://scripts/systems/handlers/RepairHandler.gd")
	_assert_true(not repair_src.contains("intent.parameters.has(\"cost\")"), "RepairHandler 不以 parameters.cost 扣款")
	_assert_true(repair_src.contains("COST_PER_HP"), "RepairHandler 使用 COST_PER_HP 常量")

	var refit_src := FileAccess.get_file_as_string("res://scripts/systems/handlers/RefitHandler.gd")
	_assert_true(refit_src.contains("get_hull_change_cost"), "RefitHandler 船体费用走 get_hull_change_cost")
	_assert_true(not refit_src.contains("parameters.get(\"cost\""), "RefitHandler 不读取 parameters.cost")
	_assert_true(refit_src.contains(":rollback"), "RefitHandler 船体失败回滚 ledger")

	var hire_src := FileAccess.get_file_as_string("res://scripts/systems/handlers/HireCrewHandler.gd")
	_assert_true(not hire_src.contains("parameters.get(\"total_cost\""), "HireCrewHandler 不读取 total_cost")
	_assert_true(not hire_src.contains("parameters.get(\"cost_per_crew\""), "HireCrewHandler 不读取 cost_per_crew")

	var supply_src := FileAccess.get_file_as_string("res://scripts/systems/handlers/BuySuppliesHandler.gd")
	_assert_true(not supply_src.contains("parameters.get(\"total_cost\""), "BuySuppliesHandler 不读取 total_cost")
	_assert_true(not supply_src.contains("parameters.get(\"unit_price\""), "BuySuppliesHandler 不读取 unit_price")
	_assert_true(supply_src.contains("MAX_AMMO_PER_BUY"), "BuySuppliesHandler 有弹药上限")
	for path in [
		"res://scripts/PortScreenController.gd",
		"res://scripts/GameState.gd",
		"res://scripts/controllers/ChoiceHandler.gd",
		"res://scripts/controllers/ShipyardController.gd",
	]:
		var src := FileAccess.get_file_as_string(path)
		_assert_true(not src.contains("\"total_cost\": 20"), "%s 补给 intent 不塞一口价 20" % path.get_file())
		_assert_true(not src.contains("\"total_cost\": SUPPLY_FULL_COST"), "%s 补给 intent 不塞 SUPPLY_FULL_COST" % path.get_file())

	var combat_src := FileAccess.get_file_as_string("res://scripts/CombatSessionController.gd")
	_assert_true(combat_src.contains("_result_emitted") or combat_src.contains(".disabled"), "CombatSessionController 防连点 emit")

	var sea_src := FileAccess.get_file_as_string("res://scripts/SeaEventController.gd")
	_assert_true(sea_src.contains("_loot_resolved"), "SeaEventController 有 _loot_resolved")

	var loot_src := FileAccess.get_file_as_string("res://scripts/systems/LootResolver.gd")
	_assert_true(loot_src.contains("loot_%s") or loot_src.contains("Time.get_ticks_usec"), "LootResolver.apply_loot 生成非空 intent_id")
	_assert_true(not loot_src.contains("}, \"\")"), "LootResolver 不再向 Ledger 传入空 intent_id")

func _has_live_ledger() -> bool:
	if GameState == null or LedgerSystem == null:
		return false
	if GameState.fleet == null or GameState.fleet.ships.is_empty():
		return false
	return true

func _snapshot() -> Dictionary:
	var ship: ShipState = GameState.fleet.ships[0]
	return {
		"balance": LedgerSystem.get_balance(),
		"hp": ship.hp,
		"max_hp": ship.max_hp,
		"crew": GameState.crew_count,
		"max_crew": GameState.max_crew,
		"food": GameState.food,
		"water": GameState.water,
		"sail": GameState.sail_type,
		"artillery": GameState.artillery,
	}

func _restore(snap: Dictionary) -> void:
	var ship: ShipState = GameState.fleet.ships[0]
	ship.hp = snap.hp
	ship.max_hp = snap.max_hp
	LedgerSystem.from_save_dict({"balance": snap.balance})
	GameState.max_crew = snap.max_crew
	GameState.crew_count = snap.crew
	GameState.set_food_amount(snap.food)
	GameState.set_water_amount(snap.water)
	GameState.set_sail_type(snap.sail)
	GameState.artillery = snap.artillery

func _test_repair_ignores_client_cost() -> void:
	if not _has_live_ledger():
		_assert_true(true, "RepairHandler 实机跳过（无 Ledger/舰队），已做源码扫描")
		return
	var snap := _snapshot()
	var ship: ShipState = GameState.fleet.ships[0]
	ship.max_hp = 100.0
	ship.hp = 80.0
	LedgerSystem.from_save_dict({"balance": 1000})
	var handler := RepairHandler.new()
	var intent := Intent.new(IntentTypes.REPAIR_SHIP, "player", "shipyard", {
		"ship_index": 0,
		"cost": 1,
		"repair_amount": 10,
	})
	var result := handler.handle(intent)
	var debit := 1000 - LedgerSystem.get_balance()
	_assert_true(result.success, "RepairHandler: 伪造 cost=1 仍成功（按权威费用扣款）")
	_assert_eq(debit, 20, "RepairHandler: 扣款为 20 而非客户端 1")
	_assert_eq(int(result.data.get("cost", 0)), 20, "RepairHandler: result.cost 为权威费用 20")
	_assert_true(is_equal_approx(ship.hp, 90.0), "RepairHandler: 修理 10 HP")

	LedgerSystem.from_save_dict({"balance": 5})
	ship.hp = 80.0
	var broke := handler.handle(Intent.new(IntentTypes.REPAIR_SHIP, "player", "shipyard", {
		"ship_index": 0,
		"cost": 1,
		"repair_amount": 10,
	}))
	_assert_true(not broke.success, "RepairHandler: 余额不足时失败")
	_assert_eq(broke.error_code, IntentErrorCodes.INSUFFICIENT_FUNDS, "RepairHandler: 返回 INSUFFICIENT_FUNDS")
	_assert_eq(LedgerSystem.get_balance(), 5, "RepairHandler: 不足时不扣款")
	_assert_true(is_equal_approx(ship.hp, 80.0), "RepairHandler: 不足时不修理")
	_restore(snap)

func _test_hire_ignores_client_cost() -> void:
	if not _has_live_ledger():
		return
	var snap := _snapshot()
	GameState.crew_count = 10
	GameState.max_crew = 50
	LedgerSystem.from_save_dict({"balance": 1000})
	var handler := HireCrewHandler.new()
	var result := handler.handle(Intent.new(IntentTypes.HIRE_CREW, "player", "shipyard", {
		"crew_count": 3,
		"total_cost": 1,
		"cost_per_crew": 1,
	}))
	var debit := 1000 - LedgerSystem.get_balance()
	_assert_true(result.success, "HireCrewHandler: 伪造费用仍成功")
	_assert_eq(debit, 30, "HireCrewHandler: 扣款为 10*3=30 而非 1")
	_restore(snap)

func _test_supplies_ignores_client_cost() -> void:
	if not _has_live_ledger():
		return
	var snap := _snapshot()
	GameState.set_food_amount(10.0)
	GameState.set_water_amount(10.0)
	LedgerSystem.from_save_dict({"balance": 1000})
	var handler := BuySuppliesHandler.new()
	var food_result := handler.handle(Intent.new(IntentTypes.BUY_SUPPLIES, "player", "shipyard", {
		"supply_type": "food",
		"amount": 20.0,
		"total_cost": 1,
		"unit_price": 0.01,
	}))
	var food_debit := 1000 - LedgerSystem.get_balance()
	_assert_true(food_result.success, "BuySuppliesHandler: 伪造 total_cost 仍成功")
	_assert_eq(food_debit, 10, "BuySuppliesHandler: 20 单位粮食扣 10（0.5/单位）")

	LedgerSystem.from_save_dict({"balance": 1000})
	var ammo_result := handler.handle(Intent.new(IntentTypes.BUY_SUPPLIES, "player", "shipyard", {
		"supply_type": "ammo",
		"amount": 99,
		"total_cost": 1,
		"unit_price": 0.01,
	}))
	var ammo_debit := 1000 - LedgerSystem.get_balance()
	_assert_true(ammo_result.success, "BuySuppliesHandler: 弹药购买成功")
	_assert_eq(int(ammo_result.data.get("applied", {}).get("ammo_added", 0)), 20, "BuySuppliesHandler: 弹药钳制到 MAX_AMMO_PER_BUY")
	_assert_eq(ammo_debit, 100, "BuySuppliesHandler: 弹药 20*5=100")
	_restore(snap)

func _test_refit_sail_ignores_client_cost() -> void:
	if not _has_live_ledger():
		return
	var snap := _snapshot()
	GameState.set_sail_type("square")
	LedgerSystem.from_save_dict({"balance": 1000})
	var handler := RefitHandler.new()
	var result := handler.handle(Intent.new(IntentTypes.REFIT_SHIP, "player", "shipyard", {
		"refit_mode": "sail",
		"cost": 1,
	}))
	var debit := 1000 - LedgerSystem.get_balance()
	_assert_true(result.success, "RefitHandler: 伪造 sail cost 仍成功")
	_assert_eq(debit, 500, "RefitHandler: 换帆固定 500")
	_restore(snap)

func _test_loot_same_intent_id() -> void:
	if LedgerSystem == null:
		var loot_src := FileAccess.get_file_as_string("res://scripts/systems/LootResolver.gd")
		_assert_true(loot_src.contains("loot_%s") or loot_src.contains("Time.get_ticks_usec"), "LootResolver intent_id 非空（无 Ledger 时源码扫描）")
		return
	var saved := LedgerSystem.get_balance()
	LedgerSystem.from_save_dict({"balance": 100})
	var loot_id := "loot_testrunner_handler_costs"
	IdempotencyGuard.processed_intents.erase(loot_id)
	LootResolver.apply_loot({"money": 10}, loot_id)
	_assert_eq(LedgerSystem.get_balance(), 110, "LootResolver: 首次 apply_loot 入账")
	LootResolver.apply_loot({"money": 10}, loot_id)
	_assert_eq(LedgerSystem.get_balance(), 110, "LootResolver: 相同 intent_id 第二次不入账")
	var pickup_id := "pickup_testrunner_handler_costs"
	IdempotencyGuard.processed_intents.erase(pickup_id)
	LootResolver.apply_world_pickup(7, "", 0, pickup_id)
	_assert_eq(LedgerSystem.get_balance(), 117, "LootResolver: 首次 apply_world_pickup 入账")
	LootResolver.apply_world_pickup(7, "", 0, pickup_id)
	_assert_eq(LedgerSystem.get_balance(), 117, "LootResolver: 相同 pickup id 第二次不入账")
	IdempotencyGuard.processed_intents.erase(loot_id)
	IdempotencyGuard.processed_intents.erase(pickup_id)
	LedgerSystem.from_save_dict({"balance": saved})

func _test_validator_uses_authoritative_repair_cost() -> void:
	if not _has_live_ledger():
		var src := FileAccess.get_file_as_string("res://scripts/systems/IntentValidator.gd")
		_assert_true(src.contains("RepairHandler.COST_PER_HP"), "IntentValidator 修理用 COST_PER_HP（无 live 时源码）")
		_assert_true(src.contains("RefitHandler.SAIL_REFIT_COST"), "IntentValidator 换帆用 SAIL_REFIT_COST")
		_assert_true(src.contains("HireCrewHandler.DEFAULT_COST_PER_CREW"), "IntentValidator 招募用 DEFAULT_COST_PER_CREW")
		return
	var snap := _snapshot()
	var ship: ShipState = GameState.fleet.ships[0]
	ship.hp = maxf(1.0, ship.max_hp - 10.0)
	LedgerSystem.from_save_dict({"balance": 5})
	var intent := Intent.new(IntentTypes.REPAIR_SHIP, "player", "shipyard", {
		"ship_index": 0,
		"repair_amount": 10.0,
		"cost": 1,
	})
	var validation := IntentValidator.validate(intent)
	_assert_true(not validation.success, "Validator: 伪造 cost=1 仍按 2/HP 判余额不足")
	_assert_eq(validation.error_code, IntentErrorCodes.INSUFFICIENT_FUNDS, "Validator: 权威修理价触发 INSUFFICIENT_FUNDS")
	_restore(snap)

func _test_fill_cost_scales_with_deficit() -> void:
	if GameState == null:
		_assert_true(BuySuppliesHandler.SUPPLY_FILL_FLAT_COST == 20, "补满一口价常量仍在")
		return
	var snap_food := GameState.food
	var snap_water := GameState.water
	var snap_max_food := GameState.max_food
	var snap_max_water := GameState.max_water
	GameState.max_food = 100.0
	GameState.max_water = 100.0
	GameState.set_food_amount(0.0)
	GameState.set_water_amount(0.0)
	var empty_cost := BuySuppliesHandler.estimate_fill_cost()
	_assert_true(empty_cost >= 100, "空舱补满按缺额计价，不低于 100")
	GameState.set_food_amount(99.0)
	GameState.set_water_amount(99.0)
	var near_full := BuySuppliesHandler.estimate_fill_cost()
	_assert_eq(near_full, BuySuppliesHandler.SUPPLY_FILL_FLAT_COST, "接近满舱仍收一口价下限")
	GameState.max_food = snap_max_food
	GameState.max_water = snap_max_water
	GameState.set_food_amount(snap_food)
	GameState.set_water_amount(snap_water)

func _test_sea_event_choice_lock_source() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/SeaEventController.gd")
	_assert_true(src.contains("_choice_resolved"), "SeaEventController 有选项锁")
	_assert_true(src.contains("_disable_action_buttons"), "SeaEventController 点选后立刻禁用按钮")

func _test_cargo_save_recomputes_total() -> void:
	var saved := CargoSystem.to_save_dict()
	CargoSystem.from_save_dict({"cargo": {"silk": 5, "tea": 3}, "total": 0})
	_assert_eq(CargoSystem.get_total_cargo(), 8, "读档按货柜重算总量，不信客户端 total")
	_assert_eq(CargoSystem.get_amount("silk"), 5, "读档保留 silk")
	CargoSystem.from_save_dict({"cargo": {"silk": -4, "tea": 2}, "total": 99})
	_assert_eq(CargoSystem.get_amount("silk"), 0, "读档丢弃负数量")
	_assert_eq(CargoSystem.get_total_cargo(), 2, "负数量不计入总量")
	CargoSystem.from_save_dict(saved)
