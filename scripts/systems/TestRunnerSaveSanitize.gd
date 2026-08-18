extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	print("[SaveSanitize]")
	_test_ledger_floor_not_ceiling()
	_test_survival_clamps()
	_test_ship_and_empty_fleet()
	_test_cargo_trim_and_unknown()
	_test_market_stock_and_mods()
	_test_save_manager_load_sanitizes()
	print("")

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _test_ledger_floor_not_ceiling() -> void:
	var snap := LedgerSystem.to_save_dict()
	LedgerSystem.from_save_dict({"balance": -80})
	_assert_eq(LedgerSystem.get_balance(), 0, "读档负余额抬回 0")
	LedgerSystem.from_save_dict({"balance": 98765})
	_assert_eq(LedgerSystem.get_balance(), 98765, "读档不封顶明文高余额")
	LedgerSystem.from_save_dict(snap)

func _test_survival_clamps() -> void:
	var s := SurvivalState.new()
	s.from_dict({
		"food": -12.0,
		"max_food": 9999.0,
		"water": 500.0,
		"max_water": 0.0,
		"max_cargo": 99999,
	})
	_assert_eq(s.max_food, SurvivalState.MAX_FOOD, "max_food 读档封顶")
	_assert_eq(s.food, 0.0, "负存粮抬回 0")
	_assert_eq(s.max_water, 1.0, "max_water 下限 1")
	_assert_true(s.water <= s.max_water, "淡水不超过上限")
	_assert_eq(s.max_cargo, SurvivalState.MAX_CARGO, "max_cargo 不信存档膨胀")

func _test_ship_and_empty_fleet() -> void:
	var ship := ShipState.new()
	ship.from_dict({
		"hull_id": "",
		"hp": 900.0,
		"max_hp": -4.0,
		"crew": 80,
		"max_crew": 10,
		"sail_type": "rocket",
		"artillery": -3,
	})
	_assert_eq(ship.hull_id, "fujian_merchant", "空 hull_id 回默认")
	_assert_true(ship.max_hp >= 1.0, "max_hp 至少 1")
	_assert_true(ship.hp <= ship.max_hp, "hp 不超过 max_hp")
	_assert_eq(ship.crew, 10, "水手不超过 max_crew")
	_assert_eq(ship.sail_type, "square", "非法帆型回横帆")
	_assert_eq(ship.artillery, 0, "负炮位抬回 0")

	var fleet := FleetState.new()
	fleet.from_dict({"ships": []})
	_assert_eq(fleet.ships.size(), 1, "空舰队补回旗舰")
	_assert_true(fleet.get_flagship() != null, "空舰队读档后仍有旗舰")

func _test_cargo_trim_and_unknown() -> void:
	var saved := CargoSystem.to_save_dict()
	var snap_cap := GameState.max_cargo
	GameState.max_cargo = 5
	CargoSystem.from_save_dict({
		"cargo": {"fujian_porcelain": 4, "ghost_crate": 3},
		"total": 99,
	})
	_assert_eq(CargoSystem.get_total_cargo(), 7, "sanitize 前按货柜重算")
	CargoSystem.sanitize_after_load()
	_assert_eq(CargoSystem.get_amount("ghost_crate"), 0, "未登记货丢掉")
	_assert_true(CargoSystem.get_total_cargo() <= 5, "总量压回舱容")
	_assert_true(CargoSystem.get_amount("fujian_porcelain") > 0, "登记货保留一部分")
	GameState.max_cargo = snap_cap
	CargoSystem.from_save_dict(saved)

func _test_market_stock_and_mods() -> void:
	var market := MarketState.new()
	market.from_dict({
		"port_stocks": {
			"p1": {
				"g1": {"stock": -20, "base_stock": 40},
				"bad": "nope",
			},
			"p2": "nope",
		},
		"port_prosperity": {"p1": 9.0},
		"port_affinity": {"p1": -99.0},
	})
	_assert_eq(market.get_stock("p1", "g1"), 0, "负库存抬回 0")
	_assert_eq(market.get_base_stock("p1", "g1"), 40, "base_stock 保留")
	_assert_eq(market.get_stock("p1", "bad"), 0, "非字典货条丢掉")
	_assert_eq(market.get_stock("p2", "g1"), 0, "非字典港口丢掉")
	_assert_eq(market.get_prosperity("p1"), 1.3, "繁荣度封顶")
	_assert_eq(market.get_affinity("p1"), -20.0, "好感度封底")

func _test_save_manager_load_sanitizes() -> void:
	if not OS.is_debug_build():
		return
	var snap_gs := GameState.to_save_dict()
	var snap_led := LedgerSystem.to_save_dict()
	var snap_cargo := CargoSystem.to_save_dict()
	SaveManager._set_test_path_stem("nk1_sanitize_save")
	var slot := 3
	var payload := {
		"save_version": SaveManager.CURRENT_VERSION,
		"timestamp": "2026-08-19T00:00:00",
		"current_scene_id": "cg_title",
		"game_state": {
			"survival": {
				"food": -8.0,
				"max_food": 100.0,
				"water": 10.0,
				"max_water": 100.0,
				"max_cargo": 4,
			},
			"fleet": {"ships": []},
		},
		"ledger": {"balance": -3},
		"cargo": {
			"cargo": {"fujian_porcelain": 9, "ghost_crate": 5},
			"total": 999,
		},
		"world_events": {
			"active_events": [],
			"triggered_events": {},
			"port_triggered": {},
			"cooldowns": {},
			"version": 1,
		},
	}
	var path := "user://nk1_sanitize_save_%d.json" % slot
	var f := FileAccess.open(path, FileAccess.WRITE)
	_assert_true(f != null, "可写测试存档")
	if f == null:
		SaveManager._reset_path_templates()
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	var ok := SaveManager.load_game(slot)
	_assert_true(ok, "脏档仍可读")
	_assert_eq(LedgerSystem.get_balance(), 0, "SaveManager: 负余额抬回 0")
	_assert_eq(GameState.food, 0.0, "SaveManager: 负存粮抬回 0")
	_assert_eq(GameState.max_cargo, 4, "SaveManager: 舱容按存档合法值")
	_assert_eq(CargoSystem.get_amount("ghost_crate"), 0, "SaveManager: 未登记货丢掉")
	_assert_true(CargoSystem.get_total_cargo() <= GameState.max_cargo, "SaveManager: 总量不超过舱容")
	_assert_true(GameState.fleet.get_flagship() != null, "SaveManager: 空舰队补旗舰")
	SaveManager.delete_save(slot)
	SaveManager._reset_path_templates()
	GameState.from_save_dict(snap_gs)
	LedgerSystem.from_save_dict(snap_led)
	CargoSystem.from_save_dict(snap_cargo)
