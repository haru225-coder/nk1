extends Node

func _ready() -> void:
	var ok := true
	_reset_state()
	IntentResolver.clear_handlers()
	IntentResolver._ensure_bootstrapped()

	ok = ok and IntentResolver.has_handler("payment")
	ok = ok and IntentResolver.has_handler("market_buy")
	ok = ok and IntentResolver.has_handler("market_sell")
	ok = ok and IntentResolver.has_handler("bribe")
	ok = ok and IntentResolver.has_handler("repair_ship")
	ok = ok and IntentResolver.has_handler("refit_ship")
	ok = ok and IntentResolver.has_handler("hire_crew")
	ok = ok and IntentResolver.has_handler("buy_supplies")
	ok = ok and IntentResolver.has_handler("buy_intel")
	ok = ok and IntentResolver.has_handler("trade_request")

	# PaymentHandler
	LedgerSystem.from_save_dict({"balance": 1000})
	var pay_intent := Intent.new("payment", "player", "pirate", {"amount": 100})
	var pay_result := IntentResolver.resolve(pay_intent)
	ok = ok and pay_result.success
	ok = ok and LedgerSystem.get_balance() == 900
	ok = ok and pay_result.message_key == "intent.payment.success"

	# BribeHandler — 走私出港贿赂
	IdempotencyGuard.processed_intents.clear()
	GameState.pu_attention = 0
	var bribe_intent := Intent.new(
		"bribe", "player", "customs_officer",
		{"amount": 50, "attention_delta": 3, "smuggling_departure": true},
		{"customs_departure": true}
	)
	var bribe_result := IntentResolver.resolve(bribe_intent)
	ok = ok and bribe_result.success
	ok = ok and LedgerSystem.get_balance() == 850
	ok = ok and GameState.pu_attention == 3

	# BribeHandler — grant_permit（市舶司买通）
	IdempotencyGuard.processed_intents.clear()
	var permit_intent := Intent.new(
		"bribe", "player", "customs_officer",
		{"amount": 50, "attention_delta": 0, "grant_permit": true}
	)
	var permit_result := IntentResolver.resolve(permit_intent)
	ok = ok and permit_result.success
	ok = ok and GameState.has_customs_permit
	ok = ok and LedgerSystem.get_balance() == 800

	# Bribe 资金不足
	IdempotencyGuard.processed_intents.clear()
	GameState.has_customs_permit = false
	LedgerSystem.from_save_dict({"balance": 10})
	var broke_bribe := IntentResolver.resolve(Intent.new(
		"bribe", "player", "customs_officer", {"amount": 50}
	))
	ok = ok and not broke_bribe.success
	ok = ok and broke_bribe.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS

	# Bribe 海关封锁（pu_attention >= 15）
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 1000})
	GameState.pu_attention = 15
	var blocked_bribe := IntentResolver.resolve(Intent.new(
		"bribe", "player", "customs_officer",
		{"amount": 50, "smuggling_departure": true},
		{"customs_departure": true}
	))
	ok = ok and not blocked_bribe.success
	ok = ok and blocked_bribe.error_code == IntentErrorCodes.CUSTOMS_BLOCKED

	# TradeState.customs_inspection 走私贿赂路径
	_reset_trade_for_inspection()
	LedgerSystem.from_save_dict({"balance": 200})
	GameState.pu_attention = 0
	GameState.has_customs_permit = false
	var insp := GameState.customs_inspection()
	ok = ok and insp.get("passed", false)
	ok = ok and insp.get("was_smuggling", false)
	ok = ok and LedgerSystem.get_balance() == 150
	ok = ok and GameState.pu_attention == 3

	# RepairHandler — 半量修理
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 500})
	GameState.fleet.get_flagship().hp = 50.0
	GameState.fleet.get_flagship().max_hp = 100.0
	var repair_intent := Intent.new(
		"repair_ship", "player", "shipyard",
		{"ship_index": 0, "repair_ratio": 0.5, "cost_per_hp": 2}
	)
	var repair_result := IntentResolver.resolve(repair_intent)
	ok = ok and repair_result.success
	ok = ok and GameState.fleet.get_flagship().hp == 75.0
	ok = ok and repair_result.data.get("cost", 0) == 50
	ok = ok and LedgerSystem.get_balance() == 450

	# Repair 资金不足
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 5})
	var broke_repair := IntentResolver.resolve(Intent.new(
		"repair_ship", "player", "shipyard",
		{"ship_index": 0, "repair_ratio": 1.0, "cost_per_hp": 10}
	))
	ok = ok and not broke_repair.success
	ok = ok and broke_repair.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS

	# 海上巡逻贿赂 + 没收违禁品
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 1000})
	CargoSystem.from_save_dict({"cargo": {"smuggled_salt": 2}, "total": 2})
	GameState.pu_attention = 0
	var patrol_bribe := IntentResolver.resolve(Intent.new(
		"bribe", "player_fleet", "song_patrol",
		{"amount": 500, "attention_delta": 0, "confiscate_contraband": true}
	))
	ok = ok and patrol_bribe.success
	ok = ok and LedgerSystem.get_balance() == 500
	ok = ok and CargoSystem.get_amount("smuggled_salt") == 0
	ok = ok and GameState.pu_attention == 0

	# RefitHandler — 横帆改纵帆
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 1000})
	GameState.sail_type = "square"
	var refit_result := IntentResolver.resolve(Intent.new(
		"refit_ship", "player", "shipyard", {"cost": 500}
	))
	ok = ok and refit_result.success
	ok = ok and GameState.sail_type == "lateen"
	ok = ok and LedgerSystem.get_balance() == 500

	# RefitHandler — 福船换广船
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 2000})
	var flagship := GameState.fleet.get_flagship()
	flagship.hull_id = "fujian_merchant"
	flagship.name = "福船"
	flagship.sail_type = "square"
	flagship.hp = 80.0
	flagship.max_hp = 100.0
	flagship.crew = 30
	flagship.max_crew = 50
	var hull_result := IntentResolver.resolve(Intent.new(
		"refit_ship", "player", "shipyard",
		{"refit_mode": "hull", "hull_id": "guangzhou_trader", "cost": 800}
	))
	ok = ok and hull_result.success
	ok = ok and flagship.hull_id == "guangzhou_trader"
	ok = ok and flagship.name == "广船"
	ok = ok and flagship.sail_type == "lateen"
	ok = ok and is_equal_approx(flagship.hp, 88.0)
	ok = ok and LedgerSystem.get_balance() == 1200

	# HireCrewHandler — 招募 3 名
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 500})
	GameState.crew_count = 10
	GameState.max_crew = 50
	var hire_result := IntentResolver.resolve(Intent.new(
		"hire_crew", "player", "shipyard",
		{"crew_count": 3, "cost_per_crew": 10, "total_cost": 30},
		{"port_id": "quanzhou"}
	))
	ok = ok and hire_result.success
	ok = ok and GameState.crew_count == 13
	ok = ok and LedgerSystem.get_balance() == 470

	# HireCrew 满员
	IdempotencyGuard.processed_intents.clear()
	GameState.crew_count = 50
	var full_crew := IntentResolver.resolve(Intent.new(
		"hire_crew", "player", "shipyard",
		{"crew_count": 1, "cost_per_crew": 10},
		{"port_id": "quanzhou"}
	))
	ok = ok and not full_crew.success
	ok = ok and full_crew.error_code == IntentErrorCodes.CREW_LIMIT_REACHED

	# BuySupplies — 补满水粮
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 200})
	GameState.food = 10.0
	GameState.water = 10.0
	GameState.max_food = 100.0
	GameState.max_water = 100.0
	var supply_result := IntentResolver.resolve(Intent.new(
		"buy_supplies", "player", "shipyard",
		{"supply_type": "food_water", "total_cost": 20, "fill_to_max": true},
		{"port_id": "quanzhou"}
	))
	ok = ok and supply_result.success
	ok = ok and GameState.food == 100.0
	ok = ok and GameState.water == 100.0
	ok = ok and LedgerSystem.get_balance() == 180

	# BuySupplies 资金不足
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 5})
	GameState.food = 10.0
	var broke_supply := IntentResolver.resolve(Intent.new(
		"buy_supplies", "player", "shipyard",
		{"supply_type": "food", "amount": 20.0, "total_cost": 10},
		{"port_id": "quanzhou"}
	))
	ok = ok and not broke_supply.success
	ok = ok and broke_supply.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS

	# BuyIntelHandler — 成功购买 tier 2
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 100})
	GameState.market.upcoming_events.clear()
	GameState.market.upcoming_events.append({
		"days_left": 10, "type": "disaster", "port_name": "泉州", "purchased": false,
	})
	var intel_result := IntentResolver.resolve(Intent.new(
		"buy_intel", "player", "tavern",
		{"tier": 2, "total_cost": 50, "event_index": 0},
		{"port_id": "quanzhou"}
	))
	ok = ok and intel_result.success
	ok = ok and LedgerSystem.get_balance() == 50
	ok = ok and GameState.market.upcoming_events[0].get("purchased", false)

	# BuyIntel 已购买
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 200})
	var dup_intel := IntentResolver.resolve(Intent.new(
		"buy_intel", "player", "tavern",
		{"tier": 3, "total_cost": 120, "event_index": 0},
		{"port_id": "quanzhou"}
	))
	ok = ok and not dup_intel.success
	ok = ok and dup_intel.error_code == IntentErrorCodes.INTEL_ALREADY_PURCHASED

	# BuyIntel 资金不足（重置传闻为可购买）
	IdempotencyGuard.processed_intents.clear()
	GameState.market.upcoming_events[0]["purchased"] = false
	LedgerSystem.from_save_dict({"balance": 5})
	var broke_intel := IntentResolver.resolve(Intent.new(
		"buy_intel", "player", "tavern",
		{"tier": 1, "total_cost": 20, "event_index": 0},
		{"port_id": "quanzhou"}
	))
	ok = ok and not broke_intel.success
	ok = ok and broke_intel.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS

	# TradeHandler market_buy
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 10000})
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})
	GameState.pu_attention = 0
	var buy_intent := Intent.new(
		"market_buy", "player", "market",
		{"good_id": "fujian_porcelain", "amount": 1},
		{"port_id": "quanzhou"}
	)
	var buy_result := IntentResolver.resolve(buy_intent)
	ok = ok and buy_result.success
	ok = ok and CargoSystem.get_amount("fujian_porcelain") == 1
	ok = ok and LedgerSystem.get_balance() < 10000

	# 未知类型走 NO_HANDLER
	var unknown := IntentResolver.resolve(Intent.new("unknown_type", "a", "b"))
	ok = ok and not unknown.success
	ok = ok and unknown.error_code == IntentErrorCodes.NO_HANDLER

	print("[IntentResolverSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _reset_state() -> void:
	IdempotencyGuard.processed_intents.clear()
	GameState.pu_attention = 0
	GameState.has_customs_permit = false
	GameState.fleet.get_flagship().hp = 100.0
	GameState.fleet.get_flagship().max_hp = 100.0
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})

func _reset_trade_for_inspection() -> void:
	GameState.has_customs_permit = false
	GameState.pu_attention = 0
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})