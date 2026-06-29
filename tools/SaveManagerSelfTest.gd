extends Node

const PirateAttackEvent = preload(ResourcePaths.SCRIPT_PIRATE_ATTACK)
const TradeDisasterEvent = preload(ResourcePaths.SCRIPT_TRADE_DISASTER)
const TradeRecoveryEvent = preload(ResourcePaths.SCRIPT_TRADE_RECOVERY)
const BaseEconomicEvent = preload(ResourcePaths.SCRIPT_BASE_EVENT)

func _ready() -> void:
	var ok := true
	GameState.fame = 42
	GameState.navigation.last_port = "quanzhou"
	LedgerSystem.from_save_dict({"balance": 2500})
	CargoSystem.from_save_dict({"cargo": {"silk": 5}, "total": 5})
	SaveManager.set_current_scene_id("port_quanzhou")

	# === WorldEventTracker 序列化测试准备 ===
	# 清空状态（含新触发/冷却数据）
	WorldEventTracker.active_events.clear()
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()

	WorldEventTracker.add_event(PirateAttackEvent.new("quanzhou", 5))
	WorldEventTracker.add_event(TradeDisasterEvent.new("guangzhou", 3))
	# 验证去重逻辑
	WorldEventTracker.add_event(PirateAttackEvent.new("quanzhou", 2))  # 应刷新为 max(5,2) = 5

	ok = ok and SaveManager.save_game(0)
	var path := "user://nk1_save_0.json"
	ok = ok and FileAccess.file_exists(path)

	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and raw.get("save_version") == 2
	ok = ok and raw.has("timestamp") and str(raw["timestamp"]) != ""
	ok = ok and raw.get("current_scene_id") == "port_quanzhou"
	ok = ok and raw.has("game_state") and raw.has("ledger") and raw.has("cargo") and raw.has("world_events")
	ok = ok and raw["game_state"].has("fleet")
	ok = ok and int(raw["ledger"].get("balance", 0)) == 2500
	var we_raw: Dictionary = raw.get("world_events", {})
	ok = ok and we_raw.has("active_events")
	ok = ok and we_raw.get("active_events", []).size() >= 2

	GameState.fame = 0
	LedgerSystem.from_save_dict({"balance": 0})
	CargoSystem.from_save_dict({"cargo": {}, "total": 0})
	ok = ok and SaveManager.load_game(0)
	ok = ok and GameState.fame == 42
	ok = ok and LedgerSystem.get_balance() == 2500
	ok = ok and CargoSystem.get_amount("silk") == 5
	ok = ok and SaveManager.has_save(0)

	# WorldEventTracker 恢复验证
	var active_after_load: Array = WorldEventTracker.get_active_events()
	ok = ok and active_after_load.size() >= 2
	# 查找对应事件
	var qz_pirate := _find_event(active_after_load, "pirate_attack", "quanzhou")
	var gz_disaster := _find_event(active_after_load, "trade_disaster", "guangzhou")
	ok = ok and qz_pirate != null and qz_pirate.duration_days == 5   # 去重后应保留5
	ok = ok and gz_disaster != null and gz_disaster.duration_days == 3

	# 验证读档后重复添加不会错误叠加（持续时间刷新）
	# 临时重置触发记录以允许本次测试的刷新逻辑（历史记录本身由其他用例覆盖）
	WorldEventTracker.reset_event_trigger("pirate_attack", "quanzhou")
	WorldEventTracker.add_event(PirateAttackEvent.new("quanzhou", 7))
	var qz_after := _find_event(WorldEventTracker.get_active_events(), "pirate_attack", "quanzhou")
	ok = ok and qz_after != null and qz_after.duration_days == 7  # max(5,7)

	# 模拟 process_day，验证冷却/持续时间恢复后能正确递减
	var days_before := qz_after.duration_days
	WorldEventTracker.process_day()
	var qz_ticked := _find_event(WorldEventTracker.get_active_events(), "pirate_attack", "quanzhou")
	ok = ok and qz_ticked != null and qz_ticked.duration_days == days_before - 1

	# === NK1-P3-WORLDEVENT-002 触发历史与冷却测试 ===
	# 重置用于干净测试
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()
	WorldEventTracker.active_events.clear()

	# 手动记录触发 + 冷却
	WorldEventTracker.record_trigger("pirate_attack", "quanzhou", 5)
	ok = ok and WorldEventTracker.is_event_triggered("pirate_attack", "quanzhou")
	ok = ok and not WorldEventTracker.can_trigger_event("pirate_attack", "quanzhou")
	ok = ok and WorldEventTracker.is_on_cooldown("pirate_attack", "quanzhou")

	# 其他港口的同事件应该仍可触发（已修复：不再错误污染全局触发记录）
	ok = ok and WorldEventTracker.can_trigger_event("pirate_attack", "xiamen")

	# 不同事件类型在同港口应该允许
	ok = ok and WorldEventTracker.can_trigger_event("trade_recovery", "quanzhou")

	# 模拟保存当前触发/冷却状态 (使用独立 slot 避免干扰)
	WorldEventTracker.active_events.clear()  # 不存 active，仅测试历史
	var hist_slot := 2
	var save_ok := SaveManager.save_game(hist_slot)
	ok = ok and save_ok
	var hist_path := "user://nk1_save_%d.json" % hist_slot
	var file_content := FileAccess.get_file_as_string(hist_path)
	var raw2: Dictionary = JSON.parse_string(file_content) if not file_content.is_empty() else {}
	var we2: Dictionary = raw2.get("world_events", {})
	ok = ok and we2.has("triggered_events")
	ok = ok and we2.has("port_triggered")
	ok = ok and we2.has("cooldowns")
	ok = ok and we2["triggered_events"].get("pirate_attack", false)
	ok = ok and we2.get("cooldowns", {}).has("quanzhou:pirate_attack")

	# 手动从文件加载 WE 数据（避免 load_game 侧作用 + 后续 load(0) 污染）
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()
	var hist_content2: String = FileAccess.get_file_as_string(hist_path)
	var hist_raw2: Dictionary = (JSON.parse_string(hist_content2) if not hist_content2.is_empty() else {}) as Dictionary
	var hist_we2: Dictionary = hist_raw2.get("world_events", {}) as Dictionary
	WorldEventTracker.from_save_dict(hist_we2)

	ok = ok and WorldEventTracker.is_event_triggered("pirate_attack", "quanzhou")
	ok = ok and not WorldEventTracker.can_trigger_event("pirate_attack", "quanzhou")
	ok = ok and WorldEventTracker.is_on_cooldown("pirate_attack", "quanzhou")

	# 过一天，冷却应递减
	WorldEventTracker.process_day()
	ok = ok and WorldEventTracker.is_on_cooldown("pirate_attack", "quanzhou")

	# 清理我们使用的测试槽位，避免影响后续 all_saves 断言
	ok = ok and SaveManager.delete_save(2)

	# === NK1-P3-WORLDEVENT-005 max_triggers + 安全阀加权测试 ===
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()
	WorldEventTracker.max_triggers_overrides.clear()

	# 设置 trade_disaster 最大触发 2 次
	WorldEventTracker.max_triggers_overrides["trade_disaster"] = 2

	WorldEventTracker.record_trigger("trade_disaster", "quanzhou", 0)
	ok = ok and WorldEventTracker.can_trigger_event("trade_disaster", "quanzhou")
	WorldEventTracker.record_trigger("trade_disaster", "quanzhou", 0)
	ok = ok and not WorldEventTracker.can_trigger_event("trade_disaster", "quanzhou")

	# 全局 count 也算
	WorldEventTracker.record_trigger("trade_disaster", "", 0)
	# 现在 global count 高，但 per port 也

	# 清理
	WorldEventTracker.max_triggers_overrides.clear()

	# === NK1-P3-WORLDEVENT-003 权重机制 + 配置化测试 ===
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()
	WorldEventTracker.active_events.clear()

	# 验证事件配置
	var disaster_sample := TradeDisasterEvent.new("testport", 10)
	ok = ok and disaster_sample.cooldown_days == 25
	ok = ok and abs(disaster_sample.base_weight - 1.0) < 0.01
	ok = ok and not disaster_sample.use_global_cooldown

	var recovery_sample := TradeRecoveryEvent.new("testport", 10)
	ok = ok and recovery_sample.cooldown_days == 15

	# 设置触发状态
	WorldEventTracker.record_trigger("trade_disaster", "quanzhou", 0)
	WorldEventTracker.record_trigger("pirate_attack", "quanzhou", 5)

	var cands := WorldEventTracker.get_weighted_event_candidates("quanzhou")
	# 找到对应
	var d_w := 1.0
	var r_w := 1.0
	var p_w := 1.0
	for c in cands:
		if c.get("event_id", "") == "trade_disaster": d_w = c.get("weight", 1.0)
		if c.get("event_id", "") == "trade_recovery": r_w = c.get("weight", 1.0)
		if c.get("event_id", "") == "pirate_attack": p_w = c.get("weight", 1.0)

	ok = ok and d_w < 0.1   # 已触发应大幅降低
	ok = ok and p_w < 0.1   # 冷却中应大幅降低
	ok = ok and r_w > 0.5   # recovery 未触发，应保持较高

	# 测试 add_event 拉取事件自身 cooldown 配置（使用 record 后的状态验证）
	WorldEventTracker.clear_trigger_history()
	WorldEventTracker.clear_cooldowns()
	var rec := TradeRecoveryEvent.new("quanzhou", 10)
	WorldEventTracker.add_event(rec)  # 应使用 rec.cooldown_days = 15
	ok = ok and WorldEventTracker.is_on_cooldown("trade_recovery", "quanzhou")

	var info0: Dictionary = SaveManager.get_save_info(0)
	ok = ok and info0.get("exists", false)
	ok = ok and info0.get("balance", -1) == 2500
	ok = ok and info0.get("current_location_name", "") == "泉州"

	# 多槽位：slot 1 存档 + get_all_saves_info
	SaveManager.set_current_scene_id("port_guangzhou")
	GameState.navigation.last_port = "guangzhou"
	LedgerSystem.from_save_dict({"balance": 9999})
	ok = ok and SaveManager.save_game(1)
	ok = ok and SaveManager.has_save(1)

	var all_saves: Array[Dictionary] = SaveManager.get_all_saves_info()
	ok = ok and all_saves.size() == 4
	ok = ok and all_saves[0].get("exists", false)
	ok = ok and all_saves[1].get("exists", false)
	ok = ok and not all_saves[2].get("exists", true)
	ok = ok and all_saves[1].get("current_location_name", "") != ""

	# 删除 slot 1
	ok = ok and SaveManager.delete_save(1)
	ok = ok and not SaveManager.has_save(1)
	all_saves = SaveManager.get_all_saves_info()
	ok = ok and not all_saves[1].get("exists", true)

	# 模拟标题页：仅 load_game(0)，靠 load_completed 跳转
	var load_hits: Array = [0]
	var load_scene: Array = [""]
	var on_load := func(_slot: int, success: bool, data: Dictionary) -> void:
		if success:
			load_hits[0] += 1
			load_scene[0] = data.get("current_scene_id", "")
	SaveManager.load_completed.connect(on_load)
	var reload_ok := SaveManager.load_game(0)
	ok = ok and reload_ok
	ok = ok and load_hits[0] == 1
	ok = ok and load_scene[0] == "port_quanzhou"
	SaveManager.load_completed.disconnect(on_load)

	# quick_save 仍写 slot 0
	ok = ok and SaveManager.quick_save()
	ok = ok and FileAccess.file_exists("user://nk1_save_0.json")

	if not ok:
		print("[SaveManagerSelfTest] FAIL - dumping WE state:")
		print("  triggered_events=", WorldEventTracker.triggered_events)
		print("  port_triggered=", WorldEventTracker.port_triggered)
		print("  cooldowns=", WorldEventTracker.cooldowns)
		print("  active count=", WorldEventTracker.get_active_events().size())
	print("[SaveManagerSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _find_event(events: Array, event_id: String, target_port: String) -> BaseEconomicEvent:
	for e in events:
		if e != null and e.event_id == event_id and e.target_port == target_port:
			return e
	return null
