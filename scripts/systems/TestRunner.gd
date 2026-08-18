extends SceneTree

# ═══════════════════════════════════════════════════════════
# TestRunner — 轻量级原生断言测试入口
# 运行方式: godot --headless -s scripts/systems/TestRunner.gd
# ═══════════════════════════════════════════════════════════

const FAIL := 1
const PASS := 0

var _failures: Array[String] = []
var _pass_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TestRunner: Core System Tests ===")
	print("")
	_test_price_engine()
	_test_idempotency_guard()
	_test_ledger_failed_debit_retry_intent()
	_test_intent_id_format()
	_test_event_registry()
	_test_market_state()
	_test_pricing_integration()
	_test_safety_valve()
	_test_cross_port_linkage()
	_test_event_persistence()
	_test_trade_history_saturation()
	_test_supply_chain_mod()
	_test_regional_pressure_mod()
	_test_prosperity_impact()
	_test_economy_log()
	_test_stability()
	_test_new_event_registry()
	_test_supply_shortage_event()
	_test_trade_boom_event()
	_test_economic_ripple_event()
	_test_port_affinity()
	_test_port_specialty_unlock()
	_run_calendar_tests()
	_test_career_state()
	_test_ending_resolver()
	_test_chapter3_ending_bridge()
	_test_completion_vertical_slice()
	_test_ending_ux()
	_test_scene_router()
	_test_mode_stack()
	_test_sea_hud_layout()
	_test_content_experience_hooks()
	_test_ui_icon_resolution()
	_test_facility_column_split()
	_test_sea_feedback()
	_test_economy_feel()
	_test_intel_notes()
	_test_title_and_hotspot_visual()
	_test_p9a_first_hour_ux()
	_test_p9c_architecture_boundaries()
	_run_controller_tests()
	_run_suite("res://scripts/systems/TestRunnerMarketIntegrity.gd", "TestRunnerMarketIntegrity")
	_run_suite("res://scripts/systems/TestRunnerCrateLimits.gd", "TestRunnerCrateLimits")
	_run_suite("res://scripts/systems/TestRunnerHandlerCosts.gd", "TestRunnerHandlerCosts")
	_run_story_tests()
	_test_event_economy_integration()
	_test_polish_constants()
	_test_game_log()
	_run_ui_test("run_ui_theme_constants")
	_run_ui_test("run_resource_paths")
	_test_event_config()
	_run_ui_test("run_ui_builder")
	_run_ui_test("run_game_colors")
	_test_intent_types()
	_test_all_event_config()
	_run_asset_test("run_asset_placeholder_json")
	_run_asset_test("run_text_keys")
	_run_ui_test("run_floating_text_config")
	_run_asset_test("run_cutscene_player")
	_run_world_test("run_ship_system")
	_run_world_test("run_map_layout")
	_run_ui_test("run_map_visual_style")
	_print_summary()
	quit(PASS if _failures.is_empty() else FAIL)

# ── 断言辅助 ─────────────────────────────────────────────

func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS: ", msg)
	else:
		_failures.append(msg)
		print("  FAIL: ", msg)

func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_pass_count += 1
		print("  PASS: ", msg)
	else:
		_failures.append("%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)])
		print("  FAIL: ", msg, " (expected=", str(expected), " actual=", str(actual), ")")

func _assert_gt(actual: float, threshold: float, msg: String) -> void:
	if actual > threshold:
		_pass_count += 1
		print("  PASS: ", msg)
	else:
		_failures.append("%s (actual=%s, threshold=%s)" % [msg, str(actual), str(threshold)])
		print("  FAIL: ", msg, " (actual=", str(actual), " threshold=", str(threshold), ")")

func _assert_lt(actual: float, threshold: float, msg: String) -> void:
	if actual < threshold:
		_pass_count += 1
		print("  PASS: ", msg)
	else:
		_failures.append("%s (actual=%s, threshold=%s)" % [msg, str(actual), str(threshold)])
		print("  FAIL: ", msg, " (actual=", str(actual), " threshold=", str(threshold), ")")

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FAIL: ", msg)

func _pass(msg: String) -> void:
	_pass_count += 1
	print("  PASS: ", msg)

func _assert_not_null(value, msg: String) -> void:
	if value != null:
		_pass_count += 1
		print("  PASS: ", msg)
	else:
		_failures.append("%s (value is null)" % msg)
		print("  FAIL: ", msg, " (value is null)")

func _load_script_or_fail(path: String, msg: String, count_pass := true):
	var script = load(path)
	var ok := script is Script
	if ok:
		ok = (script as Script).can_instantiate()
	if count_pass:
		_assert_true(ok, msg)
	elif not ok:
		_fail(msg)
	return script if ok else null

func _run_calendar_tests() -> void:
	var calendar_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerCalendar.gd", "TestRunnerCalendar 脚本可加载", false)
	if calendar_tests_script == null:
		return
	var calendar_tests = calendar_tests_script.new(self)
	if calendar_tests == null or not calendar_tests.has_method("run"):
		_fail("TestRunnerCalendar: run() 可调用")
		return
	calendar_tests.run()

func _run_story_tests() -> void:
	var story_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerStory.gd", "TestRunnerStory 脚本可加载", false)
	if story_tests_script == null:
		return
	var story_tests = story_tests_script.new(self)
	if story_tests == null or not story_tests.has_method("run"):
		_fail("TestRunnerStory: run() 可调用")
		return
	story_tests.run()

func _run_controller_tests() -> void:
	_run_suite("res://scripts/systems/TestRunnerController.gd", "TestRunnerController")

func _run_suite(path: String, label: String) -> void:
	var suite_script = _load_script_or_fail(path, "%s 脚本可加载" % label, false)
	if suite_script == null:
		return
	var suite = suite_script.new(self)
	if suite == null or not suite.has_method("run"):
		_fail("%s: run() 可调用" % label)
		return
	suite.run()

func _run_ui_test(method_name: String) -> void:
	var ui_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerUi.gd", "TestRunnerUi script loads", false)
	if ui_tests_script == null:
		return
	var ui_tests = ui_tests_script.new(self)
	if ui_tests == null or not ui_tests.has_method(method_name):
		_fail("TestRunnerUi: %s callable" % method_name)
		return
	ui_tests.call(method_name)

func _run_asset_test(method_name: String) -> void:
	var asset_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerAssets.gd", "TestRunnerAssets script loads", false)
	if asset_tests_script == null:
		return
	var asset_tests = asset_tests_script.new(self)
	if asset_tests == null or not asset_tests.has_method(method_name):
		_fail("TestRunnerAssets: %s callable" % method_name)
		return
	asset_tests.call(method_name)

func _run_world_test(method_name: String) -> void:
	var world_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerWorld.gd", "TestRunnerWorld script loads", false)
	if world_tests_script == null:
		return
	var world_tests = world_tests_script.new(self)
	if world_tests == null or not world_tests.has_method(method_name):
		_fail("TestRunnerWorld: %s callable" % method_name)
		return
	world_tests.call(method_name)

class KernelFakeState:
	var fame: int = 0
	var market = null
	var career = null
	var _story_flags: Dictionary = {}
	var _flags: Dictionary = {}
	var _story_items: Dictionary = {}
	var _npc_relationships: Dictionary = {}

	func has_story_flag(key: String) -> bool:
		return bool(_story_flags.get(key, false))

	func set_story_flag(key: String, value = true) -> void:
		_story_flags[key] = value

	func get_story_flag(key: String, default = null):
		return _story_flags.get(key, default)

	func has_flag(key: String) -> bool:
		return bool(_flags.get(key, false))

	func has_item_flag(item_id: String) -> bool:
		return bool(_story_items.get(item_id, false))

	func acquire_item(item_id: String) -> void:
		_story_items[item_id] = true

	func get_npc_relationship(npc_id: String) -> int:
		return int(_npc_relationships.get(npc_id, 0))

	func adjust_npc_relationship(npc_id: String, delta: int) -> void:
		_npc_relationships[npc_id] = get_npc_relationship(npc_id) + delta

	func apply_effects(effects: Dictionary) -> void:
		if effects.has("fame"):
			fame += int(effects["fame"])
		if effects.has("npc_relationship"):
			var payload: Dictionary = effects["npc_relationship"]
			adjust_npc_relationship(str(payload.get("npc_id", "")), int(payload.get("delta", 0)))

class EndingFakeCareer:
	var apex: bool = false

	func is_apex() -> bool:
		return apex

class EndingFakeCutscenePlayer:
	var played: Array[String] = []

	func play(cutscene_id: String) -> void:
		played.append(cutscene_id)

# ── PriceEngine 测试 ─────────────────────────────────────

func _test_price_engine() -> void:
	print("[PriceEngine]")

	# 测试 1: 正常场景 — 标准供需
	var events_empty: Array[BaseEconomicEvent] = []
	var r1 = PriceEngine.calculate_price(100, 1.0, 1.0, 1.0, events_empty, "port_quanzhou", "silk")
	_assert_eq(r1["final_price"], 100, "正常场景: base=100, 1.0x1.0x1.0 => 100")
	_assert_eq(r1["base_price"], 100, "正常场景: base_price 字段正确")
	_assert_gt(float(r1["final_price"]), 0.0, "正常场景: final_price > 0")

	# 测试 2: 极端丰收 — 超低基础价 + 供给过剩
	# 模拟: base=1（最低基础价）, prod=0.1（特大丰收供过于求）, demand=0.2（极低需求）, dist=0.5
	var r2 = PriceEngine.calculate_price(1, 0.1, 0.2, 0.5, events_empty, "port_quanzhou", "rice")
	_assert_gt(float(r2["final_price"]), 0.0, "极端丰收: base=1, 0.1x0.2x0.5 => final_price > 0 (保底)")
	_assert_eq(r2["final_price"], 1, "极端丰收: 最低价保底为 1")

	# 测试 3: 极端灾害 — 高需求高价格
	# 模拟: base=50, prod=0.3（减产）, demand=5.0（恐慌抢购）, dist=2.0（偏远）
	var r3 = PriceEngine.calculate_price(50, 0.3, 5.0, 2.0, events_empty, "port_quanzhou", "food")
	_assert_gt(float(r3["final_price"]), 0.0, "极端灾害: final_price > 0")
	# 50 * 0.3 * 5.0 * 2.0 = 150
	_assert_eq(r3["final_price"], 150, "极端灾害: base=50, 0.3x5.0x2.0 => 150")

	# 测试 4: 乘数归零 — 任何因子为 0 都触发保底
	var r4 = PriceEngine.calculate_price(200, 0.0, 1.0, 1.0, events_empty, "port_quanzhou", "tea")
	_assert_eq(r4["final_price"], 1, "零因子: prod=0 触发保底 => 1")
	_assert_gt(float(r4["final_price"]), 0.0, "零因子: final_price > 0")

	# 测试 5: 超高倍率 — 命中上限保护（base*5），不溢出为负
	var r5 = PriceEngine.calculate_price(100, 10.0, 10.0, 10.0, events_empty, "port_quanzhou", "gold")
	_assert_gt(float(r5["final_price"]), 0.0, "超高倍率: 100x1000 => final_price > 0")
	_assert_eq(r5["final_price"], 500, "超高倍率: 上限保护封顶为 base*5 = 500")

	# 测试 6: 带事件修正 — 使用自定义 BaseEconomicEvent 子类
	var mock_event = MockPriceEvent.new("test_drought", "port_quanzhou", 30, 2.5)
	var events_with_mock: Array[BaseEconomicEvent] = [mock_event]
	var r6 = PriceEngine.calculate_price(100, 1.0, 1.0, 1.0, events_with_mock, "port_quanzhou", "rice")
	# 100 * 1.0 * 1.0 * 1.0 * 2.5 = 250
	_assert_eq(r6["final_price"], 250, "事件修正: base=100, event_mod=2.5 => 250")
	_assert_gt(float(r6["final_price"]), 0.0, "事件修正: final_price > 0")

	# 测试 7: 多事件叠加
	var mock_event2 = MockPriceEvent.new("test_flood", "port_quanzhou", 15, 0.5)
	var events_multi: Array[BaseEconomicEvent] = [mock_event, mock_event2]
	var r7 = PriceEngine.calculate_price(100, 1.0, 1.0, 1.0, events_multi, "port_quanzhou", "rice")
	# 100 * 1.0 * 1.0 * 1.0 * (2.5 * 0.5) = 125
	_assert_eq(r7["final_price"], 125, "多事件叠加: event_mod=2.5*0.5=1.25 => 125")

	print("")

# ── IdempotencyGuard 测试 ────────────────────────────────

func _test_idempotency_guard() -> void:
	print("[IdempotencyGuard]")

	# 先清空静态状态，确保测试隔离
	IdempotencyGuard.processed_intents.clear()

	# ── check_and_record 兼容性测试 ──

	# 测试 1: 空 ID 应被忽略（始终通过）
	var r_empty = IdempotencyGuard.check_and_record("")
	_assert_true(r_empty, "空 ID: check_and_record 返回 true（非意图驱动交易忽略）")

	# 测试 2: 首次提交
	var intent_id_1 = "tavern_treat_001"
	var r_first = IdempotencyGuard.check_and_record(intent_id_1)
	_assert_true(r_first, "首次提交: intent_id='tavern_treat_001' => true")

	# 测试 3: 重复提交必须被拦截
	var r_dup = IdempotencyGuard.check_and_record(intent_id_1)
	_assert_true(not r_dup, "重复提交: intent_id='tavern_treat_001' => false")

	# 测试 4: 不同 ID 正常通过
	var intent_id_2 = "tavern_treat_002"
	var r_other = IdempotencyGuard.check_and_record(intent_id_2)
	_assert_true(r_other, "不同 ID: intent_id='tavern_treat_002' => true")

	# 测试 5: 空 ID 可以反复通过
	var r_empty2 = IdempotencyGuard.check_and_record("")
	_assert_true(r_empty2, "空 ID 重复: 再次返回 true")

	# ── is_processed / mark_processed 新 API 测试 ──

	# 清空重新开始
	IdempotencyGuard.processed_intents.clear()

	# 测试 6: is_processed 空 ID 返回 false
	_assert_true(not IdempotencyGuard.is_processed(""), "is_processed('') => false")

	# 测试 7: is_processed 未记录的 ID 返回 false
	_assert_true(not IdempotencyGuard.is_processed("new_id"), "is_processed('new_id') => false（未记录）")

	# 测试 8: mark_processed 后 is_processed 返回 true
	IdempotencyGuard.mark_processed("mark_test_001")
	_assert_true(IdempotencyGuard.is_processed("mark_test_001"), "mark 后 is_processed => true")

	# 测试 9: mark_processed 空 ID 不应记录
	IdempotencyGuard.mark_processed("")
	_assert_true(not IdempotencyGuard.is_processed(""), "mark('') 不记录")

	# 测试 10: mark_processed 重复标记不报错
	IdempotencyGuard.mark_processed("mark_test_001")
	_assert_true(IdempotencyGuard.is_processed("mark_test_001"), "重复 mark 不影响状态")

	# ── cleanup_old_records 测试 ──

	# 清空并手动设置带时间戳的记录
	IdempotencyGuard.processed_intents.clear()
	var now := Time.get_ticks_msec() / 1000.0
	IdempotencyGuard.processed_intents["old_record"] = now - 7200.0  # 2 小时前
	IdempotencyGuard.processed_intents["new_record"] = now - 100.0   # 100 秒前

	# 测试 11: cleanup 清除超过 1 小时的记录
	IdempotencyGuard.cleanup_old_records(3600.0)
	_assert_true(not IdempotencyGuard.processed_intents.has("old_record"), "cleanup: 旧记录(2h)被清除")
	_assert_true(IdempotencyGuard.processed_intents.has("new_record"), "cleanup: 新记录(100s)保留")

	# ── clear_all 测试 ──

	IdempotencyGuard.mark_processed("survive_check")
	_assert_true(IdempotencyGuard.is_processed("survive_check"), "clear_all 前: 记录存在")
	IdempotencyGuard.clear_all()
	_assert_true(not IdempotencyGuard.is_processed("survive_check"), "clear_all 后: 记录清空")

	# ── 内部状态验证 ──

	IdempotencyGuard.processed_intents.clear()
	IdempotencyGuard.mark_processed("tavern_treat_001")
	IdempotencyGuard.mark_processed("tavern_treat_002")
	_assert_true(IdempotencyGuard.processed_intents.has("tavern_treat_001"), "内部状态: 'tavern_treat_001' 在 processed_intents 中")
	_assert_true(IdempotencyGuard.processed_intents.has("tavern_treat_002"), "内部状态: 'tavern_treat_002' 在 processed_intents 中")
	_assert_true(not IdempotencyGuard.processed_intents.has(""), "内部状态: 空字符串不在 processed_intents 中")

	# 清理
	IdempotencyGuard.processed_intents.clear()

	print("")

# ── LedgerSystem 幂等测试 ────────────────────────────────

func _test_ledger_failed_debit_retry_intent() -> void:
	print("[LedgerSystem idempotency]")

	var tree := Engine.get_main_loop() as SceneTree
	var ledger = tree.root.get_node_or_null("/root/LedgerSystem") if tree != null else null
	_assert_not_null(ledger, "LedgerSystem autoload 可取得")
	if ledger == null:
		return

	IdempotencyGuard.clear_all()
	ledger.from_save_dict({"balance": 10})
	var retry_intent_id := "ledger_retry_after_insufficient_funds"
	var expensive_tx := {
		"amount": -20,
		"source": "test",
		"reason": "retry_after_insufficient_funds",
		"actor": "TestRunner",
	}

	var first_attempt: bool = bool(ledger.apply(expensive_tx, retry_intent_id))
	_assert_true(not first_attempt, "failed debit: insufficient funds returns false")
	_assert_true(not IdempotencyGuard.is_processed(retry_intent_id), "failed debit: intent id not consumed")

	ledger.from_save_dict({"balance": 25})
	var retry_attempt: bool = bool(ledger.apply(expensive_tx, retry_intent_id))
	_assert_true(retry_attempt, "retry: same intent succeeds after balance changes")
	_assert_eq(ledger.get_balance(), 5, "retry: balance debited once")
	_assert_true(IdempotencyGuard.is_processed(retry_intent_id), "success: intent id consumed")

	ledger.from_save_dict({})
	IdempotencyGuard.clear_all()
	print("")

# ── Intent ID 格式测试 ───────────────────────────────────

func _test_intent_id_format() -> void:
	print("[Intent ID Format]")

	# 测试 1: ID 以 "intent_" 开头
	var intent := Intent.new("payment", "player", "pirate", {"amount": 10})
	_assert_true(intent.id.begins_with("intent_"), "ID 前缀: 以 'intent_' 开头")

	# 测试 2: ID 长度 = "intent_" (7) + 16 位十六进制 = 23
	_assert_eq(intent.id.length(), 23, "ID 长度: 23 字符 (intent_ + 16 hex)")

	# 测试 3: 生成多个 ID，验证唯一性
	var ids: Dictionary = {}
	var collisions := 0
	for i in range(1000):
		var test_intent := Intent.new("test", "a", "b")
		if ids.has(test_intent.id):
			collisions += 1
		ids[test_intent.id] = true
	_assert_eq(collisions, 0, "唯一性: 1000 个 Intent 无碰撞")

	# 测试 4: ID 十六进制部分只包含合法字符
	var hex_part := intent.id.substr(7)
	var valid_hex := true
	for c_idx in range(hex_part.length()):
		var c := hex_part.unicode_at(c_idx)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):  # 0-9, a-f
			valid_hex = false
			break
	_assert_true(valid_hex, "ID 格式: 十六进制部分只含 0-9, a-f")

	print("")

# ── 事件注册表测试 ───────────────────────────────────────

func _test_event_registry() -> void:
	print("[Event Registry]")
	var samples := BaseEconomicEvent.all_samples()
	_assert_gt(float(samples.size()), 2.0, "all_samples 返回至少 3 个事件")
	var ids: Dictionary = {}
	for s in samples:
		ids[s.event_id] = true
	_assert_true(ids.has("pirate_attack"), "注册表含 pirate_attack")
	_assert_true(ids.has("trade_disaster"), "注册表含 trade_disaster")
	_assert_true(ids.has("trade_recovery"), "注册表含 trade_recovery")

	var ev := BaseEconomicEvent.create("pirate_attack", "quanzhou", 5)
	_assert_true(ev is PirateAttackEvent, "create(pirate_attack) 返回 PirateAttackEvent 实例")
	_assert_eq(ev.event_id, "pirate_attack", "create 后 event_id 正确")
	_assert_eq(ev.target_port, "quanzhou", "create 后 target_port 正确")
	_assert_eq(ev.duration_days, 5, "create 后 duration_days 正确")

	var unk := BaseEconomicEvent.create("no_such_event", "x", 1)
	_assert_eq(unk.event_id, "no_such_event", "未知 id 回退为基类且保留 id")

	_assert_eq(BaseEconomicEvent.get_display_name("trade_disaster"), "贸易灾难", "get_display_name 已知 id")
	_assert_eq(BaseEconomicEvent.get_display_name("zzz"), "zzz", "get_display_name 未知 id 原样返回")

	# from_dict 反序列化走同一注册表
	var restored := BaseEconomicEvent.from_dict({"event_id": "trade_recovery", "target_port": "linan", "duration_days": 3})
	_assert_true(restored is TradeRecoveryEvent, "from_dict(trade_recovery) 返回 TradeRecoveryEvent")
	_assert_eq(restored.target_port, "linan", "from_dict 保留 target_port")
	print("")

# ── 汇总 ─────────────────────────────────────────────────

func _print_summary() -> void:
	print("=== Summary ===")
	if _failures.is_empty():
		print("ALL TESTS PASSED (%d assertions)" % _pass_count)
	else:
		print("%d FAILURE(S) out of %d assertions:" % [_failures.size(), _pass_count + _failures.size()])
		for f in _failures:
			print("  - ", f)


# ── MarketState 单元测试 ─────────────────────────────────

func _test_market_state() -> void:
	print("[MarketState]")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "quanzhou", "production": {"fujian_porcelain": 0.6}, "demand": {}},
		{"id": "liuqiu",   "production": {},                         "demand": {"fujian_porcelain": 1.5}},
	]
	var mock_goods: Array = [
		{"id": "fujian_porcelain", "category": "货物", "base_value": 50},
	]
	market.init_from_ports(mock_ports, mock_goods)

	# 初始库存分配
	var producer_base := 50 * 15
	var consumer_base := 50 * 3
	_assert_eq(market.get_base_stock("quanzhou", "fujian_porcelain"), producer_base, "产地 base_stock = base_value × 15")
	_assert_eq(market.get_base_stock("liuqiu",   "fujian_porcelain"), consumer_base, "需求地 base_stock = base_value × 3")

	# 买入使库存减少
	market.adjust_stock("quanzhou", "fujian_porcelain", -100)
	_assert_eq(market.get_stock("quanzhou", "fujian_porcelain"), producer_base - 100, "买入后库存减 100")

	# 库存不低于 0
	market.adjust_stock("quanzhou", "fujian_porcelain", -99999)
	_assert_eq(market.get_stock("quanzhou", "fujian_porcelain"), 0, "库存不低于 0")

	# stock=0 时 ratio 返回 5.0（最高价保底）
	_assert_eq(market.get_stock_ratio("quanzhou", "fujian_porcelain"), 5.0, "stock=0 → ratio=5.0")

	# reset_stock 恢复 base_stock
	market.reset_stock("quanzhou", "fujian_porcelain")
	_assert_eq(market.get_stock("quanzhou", "fujian_porcelain"), producer_base, "reset_stock 恢复 base_stock")

	# 卖出使库存增加
	market.adjust_stock("liuqiu", "fujian_porcelain", 200)
	_assert_eq(market.get_stock("liuqiu", "fujian_porcelain"), consumer_base + 200, "卖出后库存增 200")

	# ratio clamp min（极度过剩）
	market.adjust_stock("liuqiu", "fujian_porcelain", 999999)
	var ratio_low := market.get_stock_ratio("liuqiu", "fujian_porcelain")
	_assert_true(ratio_low >= 0.2, "极度过剩: ratio clamp 下限 >= 0.2")
	_assert_eq(ratio_low, 0.2, "极度过剩: ratio 精确 clamp 至 0.2")

	# 每日库存向 base_stock 缓慢回归（短缺回补 / 过剩消化，不立刻重置）
	var regen_good := "fujian_porcelain"
	var q_base := market.get_base_stock("quanzhou", regen_good)
	market.port_stocks["quanzhou"][regen_good]["stock"] = 0
	var q_before := market.get_stock("quanzhou", regen_good)
	market.process_daily_economy()
	var q_after := market.get_stock("quanzhou", regen_good)
	_assert_true(q_after > q_before, "短缺: process_daily_economy 库存向 base 回升")
	_assert_true(q_after < q_base, "短缺: 不立刻回满 base_stock")

	var l_base := market.get_base_stock("liuqiu", regen_good)
	market.port_stocks["liuqiu"][regen_good]["stock"] = l_base * 2
	var l_before := market.get_stock("liuqiu", regen_good)
	market.process_daily_economy()
	var l_after := market.get_stock("liuqiu", regen_good)
	_assert_true(l_after < l_before, "过剩: process_daily_economy 库存向 base 回落")
	_assert_true(l_after > l_base, "过剩: 不立刻重置到 base_stock")

	print("")

# ── 库存-定价集成测试 ────────────────────────────────────

func _test_pricing_integration() -> void:
	print("[Pricing Integration: stock_ratio → prod_mod → price]")

	var events_empty: Array[BaseEconomicEvent] = []

	# 库存减半 → ratio=2.0 → prod_mod=2.0 → 价格翻倍
	var r1 = PriceEngine.calculate_price(100, 1.0 * 2.0, 1.0, 1.0, events_empty, "quanzhou", "silk")
	_assert_eq(r1["final_price"], 200, "库存减半(ratio=2.0): 100 → 200")

	# 库存翻倍 → ratio=0.5 → prod_mod=0.5 → 价格减半
	var r2 = PriceEngine.calculate_price(100, 1.0 * 0.5, 1.0, 1.0, events_empty, "quanzhou", "silk")
	_assert_eq(r2["final_price"], 50, "库存翻倍(ratio=0.5): 100 → 50")

	# ratio 上限 5.0 → 最高 5 倍价格
	var r3 = PriceEngine.calculate_price(100, 1.0 * 5.0, 1.0, 1.0, events_empty, "quanzhou", "silk")
	_assert_eq(r3["final_price"], 500, "ratio 上限 5.0: 100 → 500")

	# ratio 下限 0.2 → 最低 20% 价格
	var r4 = PriceEngine.calculate_price(100, 1.0 * 0.2, 1.0, 1.0, events_empty, "quanzhou", "silk")
	_assert_eq(r4["final_price"], 20, "ratio 下限 0.2: 100 → 20")

	# 事件 × 库存叠加：ratio=2.0 × disaster_mod=2.5 → ×5
	var disaster := MockPriceEvent.new("test_disaster", "quanzhou", 5, 2.5)
	var events_with: Array[BaseEconomicEvent] = [disaster]
	var r5 = PriceEngine.calculate_price(100, 1.0 * 2.0, 1.0, 1.0, events_with, "quanzhou", "silk")
	_assert_eq(r5["final_price"], 500, "库存减半 + 灾害事件: 100 × 2.0 × 2.5 = 500")

	print("")

# ── 安全阀阈值测试 ────────────────────────────────────────

func _test_safety_valve() -> void:
	print("[Safety Valve: avg_ratio threshold detection]")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "p1", "production": {"g1": 1.0}, "demand": {}},
		{"id": "p2", "production": {},          "demand": {"g1": 1.5}},
	]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	# 正常状态：avg_ratio ≈ 1.0，不触发安全阀
	var r1 := market.get_stock_ratio("p1", "g1")
	var r2 := market.get_stock_ratio("p2", "g1")
	var avg_normal := (r1 + r2) / 2.0
	_assert_true(avg_normal >= 0.3, "正常库存: avg_ratio >= 0.3，不触发安全阀")

	# 极度过剩状态：ratio 被 clamp 至 0.2，avg < 0.3 → 安全阀条件满足
	market.adjust_stock("p1", "g1", 999999)
	market.adjust_stock("p2", "g1", 999999)
	var r3 := market.get_stock_ratio("p1", "g1")
	var r4 := market.get_stock_ratio("p2", "g1")
	_assert_eq(r3, 0.2, "p1 极度过剩: ratio clamp 至 0.2")
	_assert_eq(r4, 0.2, "p2 极度过剩: ratio clamp 至 0.2")
	var avg_collapse := (r3 + r4) / 2.0
	_assert_true(avg_collapse < 0.3, "全港口崩盘: avg_ratio=0.2 < 0.3，安全阀触发条件满足")

	# 库存枯竭状态：ratio=5.0，avg >> 0.3，不会误触安全阀
	market.reset_stock("p1", "g1")
	market.reset_stock("p2", "g1")
	market.adjust_stock("p1", "g1", -999999)
	market.adjust_stock("p2", "g1", -999999)
	var r5 := market.get_stock_ratio("p1", "g1")
	var r6 := market.get_stock_ratio("p2", "g1")
	_assert_eq(r5, 5.0, "p1 库存枯竭: ratio=5.0")
	_assert_eq(r6, 5.0, "p2 库存枯竭: ratio=5.0")
	var avg_shortage := (r5 + r6) / 2.0
	_assert_true(avg_shortage >= 0.3, "库存枯竭: avg_ratio=5.0，不误触安全阀")

	print("")

# ── 跨港口供需联动测试 ───────────────────────────────────

func _test_cross_port_linkage() -> void:
	print("[Cross-Port Linkage]")
	var events_empty: Array[BaseEconomicEvent] = []

	# 场景 1: 邻近港口库存短缺 → 本港价格应上涨
	# 本港 ratio=1.0（正常），邻近 ratio=3.0（短缺），应触发联动上涨
	var r1 = PriceEngine.calculate_price_linked(
		100, 1.0, 1.0, 1.0, events_empty, "p_a", "g1",
		1.0, [3.0]
	)
	_assert_gt(float(r1["final_price"]), 100.0, "邻近短缺(ratio=3.0): 本港价格 > 100（联动上涨）")
	_assert_gt(float(r1.get("regional_mod", 1.0)), 1.0, "邻近短缺: regional_mod > 1.0")

	# 场景 2: 邻近港口库存过剩 → 本港价格应下跌
	var r2 = PriceEngine.calculate_price_linked(
		100, 1.0, 1.0, 1.0, events_empty, "p_a", "g1",
		1.0, [0.3]
	)
	_assert_lt(float(r2["final_price"]), 100.0, "邻近过剩(ratio=0.3): 本港价格 < 100（联动下跌）")
	_assert_lt(float(r2.get("regional_mod", 1.0)), 1.0, "邻近过剩: regional_mod < 1.0")

	# 场景 3: 邻近港口无偏差 → 不联动
	var r3 = PriceEngine.calculate_price_linked(
		100, 1.0, 1.0, 1.0, events_empty, "p_a", "g1",
		1.0, [1.0, 1.05]
	)
	_assert_eq(r3.get("regional_mod", 0.0), 1.0, "邻近无偏差(ratio≈1.0): regional_mod = 1.0（不联动）")

	# 场景 4: 同向偏差时联动减弱 — 对比同向有无减半的效果
	# 同向(local=3,neighbor=3) 应比 单纯neighbor=3(无local偏差) 更接近 1.0
	var r4_same = PriceEngine.calculate_price_linked(
		100, 3.0, 1.0, 1.0, events_empty, "p_a", "g1",
		3.0, [3.0]
	)
	var r4_only_neighbor = PriceEngine.calculate_price_linked(
		100, 1.0, 1.0, 1.0, events_empty, "p_a", "g1",
		1.0, [3.0]
	)
	_assert_true(
		abs(r4_same.get("regional_mod", 1.0) - 1.0) <= abs(r4_only_neighbor.get("regional_mod", 1.0) - 1.0),
		"同向偏差联动减弱: 同向|mod-1| <= 仅邻近|mod-1|"
	)

	# 场景 5: 无邻近港口 → 不联动（regional_mod=1.0）
	var r5 = PriceEngine.calculate_price_linked(
		100, 1.0, 1.0, 1.0, events_empty, "p_a", "g1",
		1.0, []
	)
	_assert_eq(r5.get("regional_mod", 0.0), 1.0, "无邻近港口: regional_mod = 1.0")

	print("")

# ── 事件持续性 + 衰减 + 价格回归测试 ─────────────────────

func _test_event_persistence() -> void:
	print("[Event Persistence & Decay]")
	var events_empty: Array[BaseEconomicEvent] = []

	# 使用 MockDecayEvent 测试衰减逻辑（避免 autoload 依赖）
	var disaster := MockDecayEvent.new("test_disaster", "quanzhou", 10, 2.5)

	# 测试 1: 事件初期满效果
	var mod_initial: float = disaster.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_initial, 2.0, "灾难事件初期: modifier > 2.0（满效果接近 2.5）")

	# 测试 2: 事件持续中效果衰减但持续
	for i in range(5):
		disaster.tick_day()
	var mod_mid: float = disaster.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_mid, 1.0, "灾难事件中期: modifier > 1.0（持续影响）")
	_assert_lt(mod_mid, mod_initial, "灾难事件中期: modifier < 初期（梯度衰减）")

	# 测试 3: 事件末期仍有效果但接近回归
	while disaster.duration_days > 1:
		disaster.tick_day()
	var mod_late: float = disaster.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_late, 1.0, "灾难事件末期: modifier > 1.0（仍有持续影响）")
	_assert_lt(mod_late, mod_mid, "灾难事件末期: modifier < 中期（继续衰减）")

	# 测试 4: 事件结束后 tick_day 返回 false（不再活跃）
	var alive: bool = disaster.tick_day()
	_assert_true(not alive, "事件结束: tick_day 返回 false")

	# 测试 5: 恢复事件方向相反（modifier < 1.0）
	var recovery := MockDecayEvent.new("test_recovery", "quanzhou", 10, 0.8)
	var mod_rec: float = recovery.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_lt(mod_rec, 1.0, "恢复事件: modifier < 1.0（降价方向）")
	_assert_gt(mod_rec, 0.5, "恢复事件: modifier > 0.5（不至于崩盘）")

	# 测试 6: 非目标港口不受事件影响
	var mod_other: float = disaster.get_price_modifier("guangzhou", "fujian_porcelain")
	_assert_eq(mod_other, 1.0, "非目标港口: modifier = 1.0（不受影响）")

	# 测试 7: PriceEngine 整合事件衰减 — 事件完全结束后 modifier=1.0，价格回归
	# 构造一个已完全过期的事件（duration=0, _initial_duration=0 → decay=1.0 → mod=peak）
	# 正确验证方式：事件 tick 到结束后，get_price_modifier 应返回 lerp(1.0, peak, decay)
	# 当 duration_days=0 且 _initial_duration=1 时，progress=1.0, decay=0.3
	# 但我们验证的是"事件不再活跃时不参与价格计算"——即不应在 active_events 中
	var events_done: Array[BaseEconomicEvent] = []
	var r_event = PriceEngine.calculate_price(
		100, 1.0, 1.0, 1.0, events_done, "quanzhou", "fujian_porcelain"
	)
	_assert_eq(r_event["final_price"], 100, "事件不在活跃列表: 价格回归基础价")

	# 测试 8: 活跃恢复事件通过 PriceEngine 降价
	var active_recovery: Array[BaseEconomicEvent] = [recovery]
	var r_rec = PriceEngine.calculate_price(
		100, 1.0, 1.0, 1.0, active_recovery, "quanzhou", "fujian_porcelain"
	)
	_assert_lt(float(r_rec["final_price"]), 100.0, "活跃恢复事件: final_price < 100（降价生效）")

	print("")

# ── NK1-P5-ECON-002: 贸易历史与市场饱和测试 ───────────────

func _test_trade_history_saturation() -> void:
	print("[Trade History & Saturation]")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "p1", "production": {"g1": 1.0}, "demand": {}},
	]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	# 初始无贸易历史 → 饱和修正 = 1.0
	_assert_eq(market.get_saturation_mod("p1", "g1"), 1.0, "无贸易历史: saturation_mod = 1.0")

	# 少量买入（delta<0）不影响饱和
	market.adjust_stock("p1", "g1", -50)
	_assert_eq(market.get_saturation_mod("p1", "g1"), 1.0, "净采购不影响饱和: mod = 1.0")

	# 大量倾销（delta>0）→ 饱和修正下降
	# base_stock = 100 * 15 = 1500, 倾销 1000 单位
	market.adjust_stock("p1", "g1", 1000)
	var mod_after_dump: float = market.get_saturation_mod("p1", "g1")
	_assert_lt(mod_after_dump, 1.0, "大量倾销后: saturation_mod < 1.0")
	_assert_true(mod_after_dump >= 1.0 - 0.30, "饱和修正不低于 0.70（上限保护）")

	# 贸易历史记录正确
	var net_flow: int = market.trade_history["p1"]["g1"]["net_flow"]
	_assert_eq(net_flow, 950, "贸易历史 net_flow = -50 + 1000 = 950")

	# 每日衰减后 net_flow 减少
	market.process_daily_economy()
	var net_flow_after: int = market.trade_history["p1"]["g1"]["net_flow"]
	_assert_lt(float(net_flow_after), float(net_flow), "每日衰减: net_flow 减少")

	print("")

# ── NK1-P5-ECON-002: 供应链修正测试 ───────────────────────

func _test_supply_chain_mod() -> void:
	print("[Supply Chain Modifier]")

	var events_empty: Array[BaseEconomicEvent] = []

	# 场景 1: 消费港受产出港短缺影响 → mod > 1.0
	# upstream_ratio = 3.0 (产出港严重短缺), downstream = 1.0 (正常)
	var mod1 := PriceEngine.compute_supply_chain_mod(false, true, 3.0, 1.0)
	_assert_gt(mod1, 1.0, "消费港: 产出港短缺(ratio=3.0) → mod > 1.0")

	# 场景 2: 产出港受消费港过剩影响 → mod < 1.0
	# upstream = 1.0, downstream = 0.3 (消费港过剩)
	var mod2 := PriceEngine.compute_supply_chain_mod(true, false, 1.0, 0.3)
	_assert_lt(mod2, 1.0, "产出港: 消费港过剩(ratio=0.3) → mod < 1.0")

	# 场景 3: 产出港受消费港需求旺盛影响 → mod > 1.0
	# downstream = 1.5 (消费港需求旺)
	var mod3 := PriceEngine.compute_supply_chain_mod(true, false, 1.0, 1.5)
	_assert_gt(mod3, 1.0, "产出港: 消费港需求旺(ratio=1.5) → mod > 1.0")

	# 场景 4: 无供应链关系 → mod = 1.0
	# 非产出非消费，或偏差在阈值内
	var mod4 := PriceEngine.compute_supply_chain_mod(false, false, 3.0, 0.3)
	_assert_eq(mod4, 1.0, "非产出非消费: mod = 1.0")

	# 场景 5: 产出港库存正常 → 消费港不受影响
	var mod5 := PriceEngine.compute_supply_chain_mod(false, true, 1.0, 1.0)
	_assert_eq(mod5, 1.0, "产出港正常: 消费港 mod = 1.0")

	# 场景 6: 修正因子在合理范围 [0.7, 1.3]
	var mod_extreme := PriceEngine.compute_supply_chain_mod(true, true, 5.0, 0.2)
	_assert_true(mod_extreme >= 0.7 and mod_extreme <= 1.3, "极端供应链: mod 在 [0.7, 1.3] 范围内")

	print("")

# ── NK1-P5-ECON-002: 区域压力修正测试 ─────────────────────

func _test_regional_pressure_mod() -> void:
	print("[Regional Pressure Modifier]")

	# 场景 1: 区域整体短缺 → mod > 1.0
	var mod1 := PriceEngine.compute_regional_pressure_mod(2.0)
	_assert_gt(mod1, 1.0, "区域短缺(avg_ratio=2.0): mod > 1.0")

	# 场景 2: 区域整体过剩 → mod < 1.0
	var mod2 := PriceEngine.compute_regional_pressure_mod(0.3)
	_assert_lt(mod2, 1.0, "区域过剩(avg_ratio=0.3): mod < 1.0")

	# 场景 3: 区域正常 → mod = 1.0
	var mod3 := PriceEngine.compute_regional_pressure_mod(1.0)
	_assert_eq(mod3, 1.0, "区域正常(avg_ratio=1.0): mod = 1.0")

	# 场景 4: 微小偏差在阈值内 → mod = 1.0
	var mod4 := PriceEngine.compute_regional_pressure_mod(1.05)
	_assert_eq(mod4, 1.0, "微小偏差(avg_ratio=1.05): mod = 1.0")

	# 场景 5: 修正因子在合理范围 [0.85, 1.15]
	var mod_extreme := PriceEngine.compute_regional_pressure_mod(5.0)
	_assert_true(mod_extreme <= 1.15, "极端区域压力: mod 不超过 1.15")
	var mod_extreme_low := PriceEngine.compute_regional_pressure_mod(0.2)
	_assert_true(mod_extreme_low >= 0.85, "极端区域过剩: mod 不低于 0.85")

	print("")

# ── NK1-P5-ECON-002: 港口繁荣度测试 ───────────────────────

func _test_prosperity_impact() -> void:
	print("[Port Prosperity]")

	var market := MarketState.new()
	var mock_ports: Array = [{"id": "p1", "production": {}, "demand": {}}]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	# 初始繁荣度 = 1.0
	_assert_eq(market.get_prosperity("p1"), 1.0, "初始繁荣度 = 1.0")

	# 交易提升繁荣度
	for i in range(50):
		market.adjust_stock("p1", "g1", 10)
	var prosperity_after_trade: float = market.get_prosperity("p1")
	_assert_gt(prosperity_after_trade, 1.0, "大量交易后: 繁荣度 > 1.0")

	# 灾难降低繁荣度
	market.apply_prosperity_shock("p1", 0.3)
	var prosperity_after_shock: float = market.get_prosperity("p1")
	_assert_lt(prosperity_after_shock, prosperity_after_trade, "灾难冲击后: 繁荣度下降")

	# 繁荣度有下限保护
	market.apply_prosperity_shock("p1", 1.0)
	_assert_true(market.get_prosperity("p1") >= 0.7, "繁荣度下限保护: >= 0.7")

	# 繁荣度有上限保护
	market.apply_prosperity_boost("p1", 1.0)
	_assert_true(market.get_prosperity("p1") <= 1.3, "繁荣度上限保护: <= 1.3")

	# 每日经济处理 → 繁荣度向 1.0 回归
	var before_decay: float = market.get_prosperity("p1")
	for i in range(100):
		market.process_daily_economy()
	var after_decay: float = market.get_prosperity("p1")
	_assert_lt(absf(after_decay - 1.0), absf(before_decay - 1.0), "长期衰减: 繁荣度向 1.0 回归")

	# 繁荣度影响恢复速度
	market.port_prosperity["p1"] = 0.8  # 萧条
	market.adjust_stock("p1", "g1", -99999)  # 清空库存
	market.apply_partial_recovery("p1", 0.8)
	var stock_depressed: int = market.get_stock("p1", "g1")

	market.port_prosperity["p1"] = 1.0  # 正常
	market.adjust_stock("p1", "g1", -99999)  # 再次清空
	market.apply_partial_recovery("p1", 0.8)
	var stock_normal: int = market.get_stock("p1", "g1")

	_assert_gt(float(stock_normal), float(stock_depressed), "繁荣度影响恢复: 正常繁荣恢复 > 萧条恢复")

	print("")

# ── NK1-P5-ECON-002: 经济日志测试 ─────────────────────────

func _test_economy_log() -> void:
	print("[Economy Log]")

	var log := EconomyLog.new()

	# 初始为空
	_assert_eq(log.get_latest(), "", "初始: 无日志")
	_assert_eq(log.get_entries().size(), 0, "初始: entries 为空")

	# 记录日志
	log.log("测试日志1")
	log.log("测试日志2")
	_assert_eq(log.get_latest(), "测试日志2", "最新日志: 测试日志2")
	_assert_eq(log.get_entries().size(), 2, "记录2条后: entries.size = 2")

	# 超过上限自动裁剪
	for i in range(35):
		log.log("批量日志%d" % i)
	_assert_true(log.get_entries().size() <= 30, "超过上限: entries <= 30")

	# 清空
	log.clear()
	_assert_eq(log.get_entries().size(), 0, "clear 后: entries 为空")

	# 序列化/反序列化
	log.log("序列化测试")
	var d := log.to_dict()
	var log2 := EconomyLog.new()
	log2.from_dict(d)
	_assert_eq(log2.get_latest(), "序列化测试", "反序列化: 恢复日志内容")

	# 工厂方法生成可读描述
	var notice := EconomyLog.make_dump_notice("泉州", "福建瓷")
	_assert_true(notice.contains("泉州") and notice.contains("福建瓷"), "工厂方法: 倾销通知含港口和货物名")

	var disaster_notice := EconomyLog.make_disaster_notice("兴化")
	_assert_true(disaster_notice.contains("兴化") and disaster_notice.contains("灾难"), "工厂方法: 灾难通知含港口和关键词")

	print("")

# ── NK1-P5-ECON-002: 经济系统稳定性测试 ───────────────────

func _test_stability() -> void:
	print("[Economy Stability]")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "producer", "production": {"g1": 0.8}, "demand": {}},
		{"id": "consumer", "production": {}, "demand": {"g1": 1.5}},
	]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	var events_empty: Array[BaseEconomicEvent] = []

	# 模拟大量混合交易后价格仍稳定
	for i in range(20):
		# 玩家在产出港买入
		market.adjust_stock("producer", "g1", -50)
		# 玩家在消费港卖出
		market.adjust_stock("consumer", "g1", 50)

	# 计算最终价格（通过 PriceEngine 直接验证）
	var p_ratio := market.get_stock_ratio("producer", "g1")
	var c_ratio := market.get_stock_ratio("consumer", "g1")
	var r1 = PriceEngine.calculate_price_linked(
		100, 0.8 * p_ratio, 1.0, 1.0, events_empty, "producer", "g1",
		p_ratio, [c_ratio]
	)
	var r2 = PriceEngine.calculate_price_linked(
		100, 1.0, 1.5, 1.0, events_empty, "consumer", "g1",
		c_ratio, [p_ratio]
	)

	_assert_gt(float(r1["final_price"]), 0, "稳定性: 产出港价格 > 0")
	_assert_gt(float(r2["final_price"]), 0, "稳定性: 消费港价格 > 0")
	_assert_true(r1["final_price"] <= 500, "稳定性: 产出港价格不超过 base*5")
	_assert_true(r2["final_price"] <= 500, "稳定性: 消费港价格不超过 base*5")
	_assert_true(r1["final_price"] >= 1, "稳定性: 产出港价格不低于保底 1")
	_assert_true(r2["final_price"] >= 1, "稳定性: 消费港价格不低于保底 1")

	# 极端操作：清空+灌满+清空循环
	for cycle in range(5):
		market.adjust_stock("producer", "g1", -99999)
		market.adjust_stock("consumer", "g1", 99999)
		market.adjust_stock("producer", "g1", 99999)
		market.adjust_stock("consumer", "g1", -99999)

	# 最终价格仍稳定
	var p_ratio_final := market.get_stock_ratio("producer", "g1")
	var c_ratio_final := market.get_stock_ratio("consumer", "g1")
	_assert_true(p_ratio_final >= 0.2 and p_ratio_final <= 5.0, "极端操作后: 产出港 ratio 在 [0.2, 5.0]")
	_assert_true(c_ratio_final >= 0.2 and c_ratio_final <= 5.0, "极端操作后: 消费港 ratio 在 [0.2, 5.0]")

	# 深度价格计算稳定性（所有修正因子叠加）
	var sat_mod: float = market.get_saturation_mod("producer", "g1")
	var chain_mod := PriceEngine.compute_supply_chain_mod(true, false, 1.0, c_ratio_final)
	var pressure_mod := PriceEngine.compute_regional_pressure_mod(1.0)
	var r_deep = PriceEngine.calculate_price_deep(
		100, 0.8 * p_ratio_final, 1.5, 1.0, events_empty,
		"producer", "g1", p_ratio_final, [c_ratio_final],
		chain_mod, pressure_mod, sat_mod, 1.0
	)
	_assert_true(r_deep["final_price"] >= 1 and r_deep["final_price"] <= 500, "深度价格计算: final_price 在 [1, 500]")

	print("")

# ── NK1-P5-ECON-003: 新事件注册表测试 ─────────────────────

func _test_new_event_registry() -> void:
	print("[New Event Registry]")
	var samples := BaseEconomicEvent.all_samples()
	_assert_gt(float(samples.size()), 5.0, "all_samples 返回至少 6 个事件")
	var ids: Dictionary = {}
	for s in samples:
		ids[s.event_id] = true
	_assert_true(ids.has("supply_shortage"), "注册表含 supply_shortage")
	_assert_true(ids.has("trade_boom"), "注册表含 trade_boom")
	_assert_true(ids.has("economic_ripple"), "注册表含 economic_ripple")

	# create 返回正确类型
	var ss := BaseEconomicEvent.create("supply_shortage", "quanzhou", 8)
	_assert_true(ss is SupplyShortageEvent, "create(supply_shortage) 返回 SupplyShortageEvent")
	_assert_eq(ss.event_id, "supply_shortage", "supply_shortage event_id 正确")

	var boom := BaseEconomicEvent.create("trade_boom", "quanzhou", 12)
	_assert_true(boom is TradeBoomEvent, "create(trade_boom) 返回 TradeBoomEvent")
	_assert_eq(boom.event_id, "trade_boom", "trade_boom event_id 正确")

	var ripple := BaseEconomicEvent.create("economic_ripple", "quanzhou", 8)
	_assert_true(ripple is EconomicRippleEvent, "create(economic_ripple) 返回 EconomicRippleEvent")
	_assert_eq(ripple.event_id, "economic_ripple", "economic_ripple event_id 正确")

	# 显示名
	_assert_eq(BaseEconomicEvent.get_display_name("supply_shortage"), "供应短缺", "get_display_name(supply_shortage)")
	_assert_eq(BaseEconomicEvent.get_display_name("trade_boom"), "贸易繁荣", "get_display_name(trade_boom)")
	_assert_eq(BaseEconomicEvent.get_display_name("economic_ripple"), "经济涟漪", "get_display_name(economic_ripple)")

	# 序列化/反序列化
	var ss_dict := ss.to_dict()
	_assert_true(ss_dict.has("target_good"), "supply_shortage to_dict 含 target_good")
	var ss_restored := BaseEconomicEvent.from_dict(ss_dict)
	_assert_true(ss_restored is SupplyShortageEvent, "from_dict(supply_shortage) 返回正确类型")

	print("")

# ── NK1-P5-ECON-003: 供应短缺事件测试 ─────────────────────

func _test_supply_shortage_event() -> void:
	print("[SupplyShortageEvent]")

	var event := SupplyShortageEvent.new("quanzhou", 5)
	event.target_good = "fujian_porcelain"

	# 价格修正：目标港口目标商品
	var mod_local := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_local, 1.0, "供应短缺: 目标港目标商品 mod > 1.0")
	_assert_true(mod_local <= 2.0, "供应短缺: mod 不超过峰值 2.0")

	# 非目标商品不受影响
	var mod_other_good := event.get_price_modifier("quanzhou", "sulfur")
	_assert_eq(mod_other_good, 1.0, "供应短缺: 非目标商品 mod = 1.0")

	# 非目标港口不受影响
	var mod_other_port := event.get_price_modifier("guangzhou", "fujian_porcelain")
	_assert_eq(mod_other_port, 1.0, "供应短缺: 非目标港 mod = 1.0（无 autoload 时不判定区域）")

	# 衰减验证
	for i in range(3):
		event.tick_day()
	var mod_late := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_lt(mod_late, mod_local, "供应短缺: 衰减后 mod < 初期")

	# 结束
	var alive := event.tick_day()
	var alive2 := event.tick_day()
	_assert_true(not alive2, "供应短缺: tick_day 返回 false（事件结束）")

	# activate 对库存的影响（使用 mock market）
	var market := MarketState.new()
	var mock_ports: Array = [{"id": "test_port", "production": {"g1": 1.0}, "demand": {}}]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	var stock_before: int = market.get_stock("test_port", "g1")
	var event2 := SupplyShortageEvent.new("test_port", 3)
	event2.target_good = "g1"
	event2.activate(market)
	var stock_after: int = market.get_stock("test_port", "g1")
	_assert_lt(float(stock_after), float(stock_before), "供应短缺 activate: 库存下降")

	# 繁荣度冲击（activate 在 gm==null 前已执行 prosperity_shock）
	var prosperity: float = market.get_prosperity("test_port")
	_assert_lt(prosperity, 1.0, "供应短缺 activate: 繁荣度下降")

	print("")

# ── NK1-P5-ECON-003: 贸易繁荣事件测试 ─────────────────────

func _test_trade_boom_event() -> void:
	print("[TradeBoomEvent]")

	var event := TradeBoomEvent.new("quanzhou", 10)

	# 价格修正：降价方向（促进交易）
	var mod_local := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_lt(mod_local, 1.0, "贸易繁荣: 目标港 mod < 1.0（降价）")
	_assert_true(mod_local >= 0.85, "贸易繁荣: mod 不低于 0.85")

	# 非目标港口不受影响（无 autoload 时无法判定区域）
	var mod_other := event.get_price_modifier("guangzhou", "fujian_porcelain")
	_assert_eq(mod_other, 1.0, "贸易繁荣: 非目标港 mod = 1.0")

	# 衰减
	for i in range(5):
		event.tick_day()
	var mod_late := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_late, mod_local, "贸易繁荣: 衰减后 mod 回升（接近 1.0）")

	# activate 对繁荣度的影响
	var market := MarketState.new()
	var mock_ports: Array = [{"id": "boom_port", "production": {}, "demand": {}}]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	var prosperity_before: float = market.get_prosperity("boom_port")
	var boom_event := TradeBoomEvent.new("boom_port", 10)
	boom_event.activate(market)
	var prosperity_after: float = market.get_prosperity("boom_port")
	_assert_gt(prosperity_after, prosperity_before, "贸易繁荣 activate: 繁荣度提升")

	# 库存补充
	var stock_after: int = market.get_stock("boom_port", "g1")
	var base_stock: int = market.get_base_stock("boom_port", "g1")
	_assert_gt(float(stock_after), float(base_stock), "贸易繁荣 activate: 库存补充超过基准")

	# on_expire 注入市场饱和（传入 mock market 避免 autoload 依赖）
	boom_event.on_expire(market)
	var net_flow: int = market.trade_history["boom_port"]["g1"]["net_flow"]
	_assert_gt(float(net_flow), 0.0, "贸易繁荣 on_expire: 注入净流入（市场饱和）")

	print("")

# ── NK1-P5-ECON-003: 经济涟漪事件测试 ─────────────────────

func _test_economic_ripple_event() -> void:
	print("[EconomicRippleEvent]")

	var event := EconomicRippleEvent.new("quanzhou", 6)

	# 价格修正：目标港涨价
	var mod_local := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_gt(mod_local, 1.0, "经济涟漪: 目标港 mod > 1.0")
	_assert_true(mod_local <= 1.8, "经济涟漪: mod 不超过峰值 1.8")

	# 非目标港口不受影响（无 autoload 无法判定区域）
	var mod_other := event.get_price_modifier("guangzhou", "fujian_porcelain")
	_assert_eq(mod_other, 1.0, "经济涟漪: 非目标港 mod = 1.0（无 autoload）")

	# 衰减
	for i in range(3):
		event.tick_day()
	var mod_late := event.get_price_modifier("quanzhou", "fujian_porcelain")
	_assert_lt(mod_late, mod_local, "经济涟漪: 衰减后 mod < 初期")

	# activate 库存冲击
	var market := MarketState.new()
	var mock_ports: Array = [{"id": "ripple_port", "production": {"g1": 1.0}, "demand": {}}]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	var stock_before: int = market.get_stock("ripple_port", "g1")
	var ripple_event := EconomicRippleEvent.new("ripple_port", 6)
	ripple_event.activate(market)
	var stock_after: int = market.get_stock("ripple_port", "g1")
	_assert_lt(float(stock_after), float(stock_before), "经济涟漪 activate: 库存下降")

	# 繁荣度冲击
	var prosperity: float = market.get_prosperity("ripple_port")
	_assert_lt(prosperity, 1.0, "经济涟漪 activate: 繁荣度下降")

	print("")

# ── NK1-P5-ECON-003: 港口好感度测试 ───────────────────────

func _test_port_affinity() -> void:
	print("[Port Affinity]")

	var market := MarketState.new()
	var mock_ports: Array = [{"id": "p1", "production": {}, "demand": {}}]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	# 初始好感度 = 0
	_assert_eq(market.get_affinity("p1"), 0.0, "初始好感度 = 0.0")
	_assert_eq(market.get_affinity_label("p1"), "中立", "初始好感度标签 = 中立")

	# 交易提升好感度
	for i in range(50):
		market.adjust_stock("p1", "g1", 10)
	var affinity_after_trade: float = market.get_affinity("p1")
	_assert_gt(affinity_after_trade, 0.0, "交易后好感度 > 0")

	# 好感度影响价格修正
	var aff_mod := market.get_affinity_price_mod("p1")
	_assert_lt(aff_mod, 1.0, "好感度高: 价格修正 < 1.0（买入更便宜）")

	# 负好感度
	market.adjust_affinity("p1", -50.0)
	var affinity_negative: float = market.get_affinity("p1")
	_assert_true(affinity_negative <= 0.0, "负好感度: <= 0")
	_assert_eq(market.get_affinity_label("p1"), "敌意", "极端负好感度: 标签 = 敌意")

	var aff_mod_neg := market.get_affinity_price_mod("p1")
	_assert_gt(aff_mod_neg, 1.0, "好感度低: 价格修正 > 1.0（买入更贵）")

	# 好感度上下限保护
	market.adjust_affinity("p1", 100.0)
	_assert_true(market.get_affinity("p1") <= 20.0, "好感度上限: <= 20")
	market.adjust_affinity("p1", -100.0)
	_assert_true(market.get_affinity("p1") >= -20.0, "好感度下限: >= -20")

	# 每日衰减
	market.adjust_affinity("p1", 10.0)
	var before_decay: float = market.get_affinity("p1")
	for i in range(50):
		market.process_daily_economy()
	var after_decay: float = market.get_affinity("p1")
	_assert_lt(absf(after_decay), absf(before_decay), "每日衰减: 好感度向 0 回归")

	# 好感度标签分级
	_assert_eq(market.get_affinity_label_when(18.0), "敬重", "好感度 18 = 敬重")
	_assert_eq(market.get_affinity_label_when(10.0), "友善", "好感度 10 = 友善")
	_assert_eq(market.get_affinity_label_when(3.0), "好感", "好感度 3 = 好感")
	_assert_eq(market.get_affinity_label_when(-5.0), "冷淡", "好感度 -5 = 冷淡")
	_assert_eq(market.get_affinity_label_when(-10.0), "排斥", "好感度 -10 = 排斥")

	print("")

# ── NK1-P6: 港口特产解锁测试 ─────────────────────────────

func _test_port_specialty_unlock() -> void:
	print("[Port Specialty Unlock]")

	var market := MarketState.new()
	_assert_true(not market.is_specialty_unlocked("quanzhou", "fujian_porcelain"), "初始未解锁特产")
	market.unlock_specialty("quanzhou", "fujian_porcelain")
	_assert_true(market.is_specialty_unlocked("quanzhou", "fujian_porcelain"), "解锁后 is_specialty_unlocked=true")
	market.unlock_specialty("quanzhou", "fujian_porcelain")
	var list: Array = market.unlocked_specialties.get("quanzhou", [])
	_assert_eq(list.size(), 1, "重复解锁不追加")

	var saved := market.to_dict()
	var restored := MarketState.new()
	restored.from_dict(saved)
	_assert_true(restored.is_specialty_unlocked("quanzhou", "fujian_porcelain"), "存档往返: 特产解锁保留")

	print("")


# ── P7-C: CareerState 秩禄阶梯测试 ───────────────────────

func _test_career_state() -> void:
	print("[Career]")

	var career_script = _load_script_or_fail(ResourcePaths.SCRIPT_CAREER_STATE, "CareerState 脚本可加载")
	if career_script == null:
		print("")
		return
	_assert_true(ResourcePaths.DATA_CAREER != "", "ResourcePaths.DATA_CAREER")

	var career = career_script.new()
	_assert_true(career.has_method("load_from_data"), "CareerState: 支持测试数据加载")
	_assert_true(career.has_method("check_promotion"), "CareerState: 暴露 check_promotion")
	_assert_true(career.has_method("promote"), "CareerState: 暴露 promote")
	_assert_true(career.has_method("mandate_expired"), "CareerState: 暴露 mandate_expired")
	_assert_true(career.has_method("is_apex"), "CareerState: 暴露 is_apex")

	var fixture := {
		"version": 1,
		"tiers": [
			{"rank": 0, "title": "商船水手", "req": {"fame": 0}},
			{
				"rank": 1,
				"title": "副纲首",
				"req": {"fame": 50, "flag": "chapter1_complete"},
				"mandate": {
					"id": "m1",
					"deadline_months": 3,
					"objective": "三月内扩大名声",
					"on_complete": "promote",
					"on_fail_effects": {"fame": -5}
				}
			},
			{
				"rank": 2,
				"title": "都纲",
				"req": {"fame": 120, "flag": "chapter2_complete", "relationship": {"lin_boyuan": 10}},
				"apex": true
			}
		]
	}
	career.load_from_data(fixture)
	_assert_eq(career.get_rank(), 0, "CareerState: 初始 rank=0")
	_assert_eq(career.get_title(), "商船水手", "CareerState: 初始头衔来自配置")

	var fake_state := KernelFakeState.new()
	fake_state.fame = 49
	fake_state.set_story_flag("chapter1_complete", true)
	_assert_true(not career.check_promotion(fake_state), "CareerState: fame 不足不可升秩")
	fake_state.fame = 50
	_assert_true(career.check_promotion(fake_state), "CareerState: 满足 fame+flag 可升秩")

	var calendar_script = _load_script_or_fail("res://scripts/state/CalendarState.gd", "CalendarState 脚本可加载")
	if calendar_script == null:
		print("")
		return
	var calendar = calendar_script.new()
	calendar.from_dict({"year": 1255, "month": 2, "day": 1})
	var changed_ranks: Array = []
	career.rank_changed.connect(func(new_rank: int): changed_ranks.append(new_rank))
	_assert_true(career.promote(fake_state, calendar), "CareerState: promote 成功")
	_assert_eq(career.get_rank(), 1, "CareerState: 升至 rank 1")
	_assert_eq(changed_ranks[0], 1, "CareerState: rank_changed 发出新 rank")
	_assert_eq(career.get_title(), "副纲首", "CareerState: 升秩后头衔更新")
	_assert_eq(str(career.current_mandate.get("id", "")), "m1", "CareerState: 升秩后分配 mandate")
	_assert_eq(career.mandate_deadline_month, calendar.months_elapsed() + 3, "CareerState: mandate 截止月按当前月+期限")

	calendar.from_dict({"year": 1255, "month": 4, "day": 1})
	_assert_true(not career.mandate_expired(calendar, fake_state), "CareerState: 未过截止月不惩罚")
	calendar.from_dict({"year": 1255, "month": 6, "day": 1})
	var fame_before_penalty := fake_state.fame
	_assert_true(career.mandate_expired(calendar, fake_state), "CareerState: 过截止月触发惩罚")
	_assert_eq(fake_state.fame, fame_before_penalty - 5, "CareerState: mandate 惩罚走 apply_effects 已知 key")
	_assert_true(career.current_mandate.is_empty(), "CareerState: 过期后清空当前 mandate 防重复惩罚")
	_assert_true(not career.mandate_expired(calendar, fake_state), "CareerState: mandate 惩罚不重复触发")

	fake_state.fame = 120
	fake_state.set_story_flag("chapter2_complete", true)
	fake_state.adjust_npc_relationship("lin_boyuan", 10)
	_assert_true(career.check_promotion(fake_state), "CareerState: relationship req 满足可升 apex")
	_assert_true(career.promote(fake_state, calendar), "CareerState: promote 至 apex 成功")
	_assert_true(career.is_apex(), "CareerState: apex 可达")

	var saved: Dictionary = career.to_dict()
	var restored = career_script.new()
	restored.load_from_data(fixture)
	restored.from_dict(saved)
	_assert_eq(restored.get_rank(), career.get_rank(), "CareerState: rank 存档恢复")
	_assert_eq(restored.mandate_deadline_month, career.mandate_deadline_month, "CareerState: deadline 存档恢复")

	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "CareerState: GameState autoload 可取得")
	if game_state != null:
		_assert_true(game_state.get("career") != null, "GameState: career 模块已挂接")
		var gs_saved: Dictionary = game_state.to_save_dict()
		_assert_true(gs_saved.has("career"), "GameState: 存档包含 career")

		var before_promotion_state: Dictionary = game_state.to_save_dict()
		var promotion_career = game_state.get("career")
		if promotion_career != null and promotion_career.has_method("load_defs"):
			promotion_career.load_defs()
			promotion_career.from_dict({"rank": 4})
			game_state.fame = 0
			game_state.set_story_flag("chapter2_complete", true)
			game_state.apply_effects({"career_promote": true, "fame": 400})
			_assert_eq(promotion_career.get_rank(), 5, "GameState effects: career_promote 在 fame 后升至 apex rank")
			_assert_true(promotion_career.is_apex(), "GameState effects: career_promote 可触发 apex")
		game_state.from_save_dict(before_promotion_state)

		var status_scene: PackedScene = load(ResourcePaths.SCENE_PORT_STATUS_BAR) as PackedScene
		_assert_true(status_scene != null, "CareerState UI: PortStatusBar 可加载")
		if status_scene != null:
			var before_state: Dictionary = game_state.to_save_dict()
			var gs_career = game_state.get("career")
			if gs_career != null and gs_career.has_method("load_from_data"):
				gs_career.load_from_data(fixture)
				gs_career.from_dict({"rank": 1})
			var status_bar = status_scene.instantiate()
			root.add_child(status_bar)
			status_bar.refresh()
			var location_label: Label = status_bar.get_node("Panel/Body/VBox/PrimaryRow/Location/Margin/Row/VBox/Value") as Label
			_assert_true(location_label.text.contains("副纲首"), "PortStatusBar: 所在 chip 显示秩禄头衔")
			status_bar.queue_free()
			game_state.from_save_dict(before_state)

	print("")

# ── P7-E: EndingResolver 结局判定测试 ─────────────────────

func _test_ending_resolver() -> void:
	print("[Endings]")

	var resolver_script = _load_script_or_fail(ResourcePaths.SCRIPT_ENDING_RESOLVER, "EndingResolver 脚本可加载")
	if resolver_script == null:
		print("")
		return
	_assert_true(ResourcePaths.DATA_ENDINGS != "", "ResourcePaths.DATA_ENDINGS")

	var fixture := {
		"version": 1,
		"endings": [
			{
				"id": "loyalty_ending",
				"condition": {"rank_apex": true, "flag": "spring_autumn_scroll", "linboyuan_gte": 50},
				"cutscene": "ending_loyalty",
				"terminal_state": "completed_loyalty",
				"priority": 30,
			},
			{
				"id": "defection_ending",
				"condition": {"rank_apex": true, "jia_gte": 50},
				"cutscene": "ending_defection",
				"terminal_state": "completed_defection",
				"priority": 20,
			},
			{
				"id": "overseas_ending",
				"condition": {"rank_apex": true, "flag": "overseas_voyage"},
				"cutscene": "ending_overseas",
				"terminal_state": "completed_overseas",
				"priority": 10,
			},
		],
	}

	var resolver = resolver_script.new()
	_assert_true(resolver.has_method("load_from_data"), "EndingResolver: 支持测试数据加载")
	_assert_true(resolver.has_method("evaluate"), "EndingResolver: 暴露 evaluate")
	resolver.load_from_data(fixture)
	_assert_eq(resolver.get_ending_count(), 3, "EndingResolver: 载入3条结局")

	var fake_state := KernelFakeState.new()
	fake_state.career = EndingFakeCareer.new()
	fake_state.acquire_item("spring_autumn_scroll")
	fake_state.adjust_npc_relationship("lin_boyuan", 50)
	var not_apex = resolver.evaluate(fake_state)
	_assert_true(not not_apex.success, "EndingResolver: 非 apex 不触发结局")

	fake_state.career.apex = true
	fake_state.adjust_npc_relationship("jia", 50)
	var player := EndingFakeCutscenePlayer.new()
	resolver.bind(fake_state, player)
	var result = resolver.evaluate()
	_assert_true(result.success, "EndingResolver: apex 且条件满足可触发")
	_assert_eq(result.data.get("ending_id", ""), "loyalty_ending", "EndingResolver: 多结局同时满足按 priority 选忠义")
	_assert_eq(player.played[0], "ending_loyalty", "EndingResolver: 播放所选结局过场")
	_assert_true(fake_state.has_story_flag("game_completed"), "EndingResolver: 写入 game_completed")
	_assert_true(fake_state.has_story_flag("ending:loyalty_ending"), "EndingResolver: 写入具体 ending flag")
	_assert_true(fake_state.has_story_flag("completed_loyalty"), "EndingResolver: 写入 terminal_state")

	var defection_state := KernelFakeState.new()
	defection_state.career = EndingFakeCareer.new()
	defection_state.career.apex = true
	defection_state.adjust_npc_relationship("jia", 50)
	var defection = resolver.evaluate(defection_state, EndingFakeCutscenePlayer.new())
	_assert_eq(defection.data.get("ending_id", ""), "defection_ending", "EndingResolver: 贾氏线可触发投附结局")

	var no_match_state := KernelFakeState.new()
	no_match_state.career = EndingFakeCareer.new()
	no_match_state.career.apex = true
	var no_match = resolver.evaluate(no_match_state)
	_assert_true(not no_match.success, "EndingResolver: apex 但无分支条件时不误判通关")
	_assert_true(not no_match_state.has_story_flag("game_completed"), "EndingResolver: 无匹配不写终局 flag")

	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "EndingResolver: GameState autoload 可取得")
	if game_state != null:
		_assert_true(game_state.get("ending_resolver") != null, "GameState: ending_resolver 模块已挂接")

	print("")


## 通关后 UX：结算文案 + 回标题 / 新航程
func _test_ending_ux() -> void:
	print("[Ending UX]")
	_assert_eq(ResourcePaths.SCRIPT_ENDING_SETTLEMENT, "res://scripts/EndingSettlementController.gd", "ResourcePaths.SCRIPT_ENDING_SETTLEMENT")
	var settle_script: GDScript = load(ResourcePaths.SCRIPT_ENDING_SETTLEMENT) as GDScript
	_assert_true(settle_script != null, "EndingUX: EndingSettlementController 可加载")

	# endings.json 展示字段
	var f := FileAccess.open(ResourcePaths.DATA_ENDINGS, FileAccess.READ)
	_assert_true(f != null, "EndingUX: endings.json 可读")
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		_assert_true(parsed is Dictionary, "EndingUX: endings 根对象")
		if parsed is Dictionary:
			var list: Array = parsed.get("endings", [])
			_assert_true(list.size() >= 3, "EndingUX: 至少三结局")
			for eid in ["loyalty_ending", "defection_ending", "overseas_ending"]:
				var found := false
				for raw in list:
					if str(raw.get("id", "")) != eid:
						continue
					found = true
					_assert_true(str(raw.get("title", "")) != "", "EndingUX: %s 有 title" % eid)
					_assert_true(str(raw.get("summary", "")) != "", "EndingUX: %s 有 summary" % eid)
					_assert_true(str(raw.get("epilogue", "")) != "", "EndingUX: %s 有 epilogue" % eid)
				_assert_true(found, "EndingUX: 含 %s" % eid)

	var resolver_script = load(ResourcePaths.SCRIPT_ENDING_RESOLVER)
	_assert_true(resolver_script != null, "EndingUX: EndingResolver 可加载")
	if resolver_script != null:
		var resolver = resolver_script.new()
		resolver.load_defs()
		var def_l: Dictionary = resolver.get_ending_def("loyalty_ending")
		_assert_eq(str(def_l.get("title", "")), "忠义", "EndingUX: loyalty title=忠义")
		var def_d: Dictionary = resolver.get_ending_def("defection_ending")
		_assert_eq(str(def_d.get("title", "")), "投附", "EndingUX: defection title=投附")
		var def_o: Dictionary = resolver.get_ending_def("overseas_ending")
		_assert_eq(str(def_o.get("title", "")), "远航", "EndingUX: overseas title=远航")

	# 结算 UI 节点树
	if settle_script != null:
		var layer: CanvasLayer = settle_script.new() as CanvasLayer
		root.add_child(layer)
		if layer.has_method("present"):
			layer.call("present", {
				"ending_id": "loyalty_ending",
				"title": "忠义",
				"subtitle": "测",
				"summary": "摘要",
				"epilogue": "后记",
				"rank_title": "市舶司都纲",
				"date_key": "宝祐三年正月",
			})
		_assert_true(layer.get_node_or_null("SettlementRoot") != null, "EndingUX: SettlementRoot 存在")
		var title_lbl := layer.find_child("Title", true, false) as Label
		_assert_true(title_lbl != null and "忠义" in title_lbl.text, "EndingUX: 标题含结局名")
		var actions := layer.find_child("Actions", true, false)
		_assert_true(actions != null and actions.get_child_count() >= 3, "EndingUX: 三个操作按钮")
		layer.queue_free()

	# begin_new_run 清通关标记
	var gs = root.get_node_or_null("/root/GameState")
	_assert_true(gs != null, "EndingUX: GameState 可取得")
	if gs != null and gs.has_method("begin_new_run"):
		var before: Dictionary = gs.to_save_dict()
		gs.set_story_flag("game_completed", true)
		gs.set_story_flag("ending_id", "loyalty_ending")
		gs.begin_new_run()
		_assert_true(not gs.has_story_flag("game_completed"), "EndingUX: begin_new_run 清除 game_completed")
		_assert_true(gs.has_signal("ending_resolved"), "EndingUX: GameState.ending_resolved 信号")
		gs.from_save_dict(before)
		if gs.has_method("bind_ending_resolver"):
			gs.bind_ending_resolver()

	# build_display 走真实 defs
	if gs != null and gs.has_method("build_ending_display"):
		var er = gs.get("ending_resolver")
		if er != null:
			er.last_result = {
				"ending_id": "overseas_ending",
				"title": "远航",
				"summary": "x",
			}
			var disp: Dictionary = gs.build_ending_display()
			_assert_eq(str(disp.get("ending_id", "")), "overseas_ending", "EndingUX: build_display ending_id")
			_assert_true(str(disp.get("title", "")) != "", "EndingUX: build_display 有 title")
			er.last_result = {}
	print("")


func _test_chapter3_ending_bridge() -> void:
	print("[Chapter3 Ending Bridge]")

	var game_manager = root.get_node_or_null("/root/GameManager")
	_assert_true(game_manager != null, "Chapter3: GameManager autoload 可取得")
	if game_manager == null:
		print("")
		return

	var comply = game_manager.get_scene_by_id("chapter3_after_summon_comply_audit_done")
	var refuse = game_manager.get_scene_by_id("chapter3_refuse_sea_route")
	var burn = game_manager.get_scene_by_id("chapter3_burn_flee")
	_assert_true(not comply.is_empty(), "Chapter3: 投附收束场景存在")
	_assert_true(not refuse.is_empty(), "Chapter3: 忠义收束场景存在")
	_assert_true(not burn.is_empty(), "Chapter3: 远航收束场景存在")

	var comply_effects := _first_choice_effects(comply)
	var refuse_effects := _first_choice_effects(refuse)
	var burn_effects := _first_choice_effects(burn)
	_assert_true(bool(comply_effects.get("career_promote", false)), "Chapter3: 投附收束触发 career_promote")
	_assert_true(int(comply_effects.get("jia_relationship", 0)) >= 50, "Chapter3: 投附收束满足 defection_ending 条件")
	_assert_true(int(comply_effects.get("fame", 0)) >= 150, "Chapter3: 投附收束 fame 足以连升 apex")
	_assert_eq(str(comply_effects.get("play_cutscene", "")), "ch3_end_comply", "Chapter3: 投附收束过场")
	_assert_true(bool(refuse_effects.get("career_promote", false)), "Chapter3: 忠义收束触发 career_promote")
	_assert_true(int(refuse_effects.get("linboyuan_relationship", 0)) >= 50, "Chapter3: 忠义收束满足 loyalty_ending 关系条件")
	_assert_true(int(refuse_effects.get("fame", 0)) >= 150, "Chapter3: 忠义收束 fame 足以连升 apex")
	_assert_eq(str(refuse_effects.get("play_cutscene", "")), "ch3_end_refuse", "Chapter3: 拒召收束过场")
	_assert_true(bool(burn_effects.get("career_promote", false)), "Chapter3: 远航收束触发 career_promote")
	_assert_true(_effects_set_story_flag(burn_effects, "overseas_voyage"), "Chapter3: 远航收束写入 overseas_voyage")
	_assert_true(int(burn_effects.get("fame", 0)) >= 150, "Chapter3: 远航收束 fame 足以连升 apex")
	_assert_eq(str(burn_effects.get("play_cutscene", "")), "ch3_end_burn", "Chapter3: 烧帖收束过场")

	# cutscenes.json 含三条章三收束
	var cs_path := ResourcePaths.DATA_CUTSCENES
	var cs_file := FileAccess.open(cs_path, FileAccess.READ)
	_assert_true(cs_file != null, "Chapter3: cutscenes.json 可读")
	if cs_file != null:
		var cs_data = JSON.parse_string(cs_file.get_as_text())
		cs_file.close()
		_assert_true(cs_data is Dictionary, "Chapter3: cutscenes 根对象")
		if cs_data is Dictionary:
			var bag: Dictionary = cs_data.get("cutscenes", {})
			_assert_true(bag.has("ch3_end_comply"), "Chapter3: 有 ch3_end_comply")
			_assert_true(bag.has("ch3_end_refuse"), "Chapter3: 有 ch3_end_refuse")
			_assert_true(bag.has("ch3_end_burn"), "Chapter3: 有 ch3_end_burn")
			for key in ["ch3_end_comply", "ch3_end_refuse", "ch3_end_burn"]:
				var entry: Dictionary = bag.get(key, {})
				_assert_true(entry.get("panels", []).size() >= 2, "Chapter3: %s 至少 2 镜" % key)

	print("")

## P7-A：章一/二/三 effects 串联后应可触发结局（三条分支）
func _test_completion_vertical_slice() -> void:
	print("[Completion Vertical Slice]")
	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "Completion: GameState autoload 可取得")
	if game_state == null:
		print("")
		return

	var before: Dictionary = game_state.to_save_dict()
	var career = game_state.get("career")
	_assert_true(career != null, "Completion: career 已挂接")
	if career == null:
		print("")
		return
	if career.has_method("load_defs"):
		career.load_defs()

	# 忠义线：拒蒲府 → linboyuan + 春秋 → loyalty_ending
	_reset_completion_state(game_state, career)
	game_state.acquire_item("spring_autumn_scroll")
	game_state.apply_effects({
		"story_flag": "chapter1_complete",
		"fame": 80,
		"linboyuan_relationship": 10,
		"career_promote": true,
	})
	game_state.apply_effects({
		"story_flag": "chapter2_complete",
		"fame": 180,
		"career_promote": true,
	})
	_assert_true(int(career.get_rank()) >= 3, "Completion: 章二后至少 rank3")
	game_state.apply_effects({
		"story_flag": "chapter3_refuse_escape_done",
		"story_flag2": {"chapter3_complete": true},
		"fame": 150,
		"linboyuan_relationship": 50,
		"career_promote": true,
	})
	_assert_true(career.is_apex(), "Completion loyalty: 抵达 apex")
	_assert_true(game_state.has_story_flag("game_completed"), "Completion loyalty: 写入 game_completed")
	_assert_true(game_state.has_story_flag("completed_loyalty") or str(game_state.get_story_flag("ending_id", "")) == "loyalty_ending",
		"Completion loyalty: 忠义结局成立")

	# 投附线：交书换籍 → jia_relationship → defection_ending
	_reset_completion_state(game_state, career)
	game_state.apply_effects({
		"story_flag": "chapter1_complete",
		"fame": 80,
		"linboyuan_relationship": 10,
		"career_promote": true,
	})
	game_state.apply_effects({
		"story_flag": "chapter2_complete",
		"fame": 180,
		"career_promote": true,
	})
	game_state.apply_effects({
		"story_flag": "chapter3_comply_audit_done",
		"story_flag2": {"chapter3_complete": true},
		"fame": 150,
		"jia_relationship": 50,
		"career_promote": true,
	})
	_assert_true(career.is_apex(), "Completion defection: 抵达 apex")
	_assert_true(game_state.has_story_flag("game_completed"), "Completion defection: 写入 game_completed")
	_assert_true(game_state.has_story_flag("completed_defection") or str(game_state.get_story_flag("ending_id", "")) == "defection_ending",
		"Completion defection: 投附结局成立")

	# 远航线：烧帖出走 → overseas_voyage → overseas_ending
	_reset_completion_state(game_state, career)
	game_state.apply_effects({
		"story_flag": "chapter1_complete",
		"fame": 80,
		"linboyuan_relationship": 10,
		"career_promote": true,
	})
	game_state.apply_effects({
		"story_flag": "chapter2_complete",
		"fame": 180,
		"career_promote": true,
	})
	game_state.apply_effects({
		"story_flag": "chapter3_burn_escape_done",
		"story_flag2": {"chapter3_complete": true, "overseas_voyage": true},
		"fame": 150,
		"career_promote": true,
	})
	_assert_true(career.is_apex(), "Completion overseas: 抵达 apex")
	_assert_true(game_state.has_story_flag("game_completed"), "Completion overseas: 写入 game_completed")
	_assert_true(game_state.has_story_flag("completed_overseas") or str(game_state.get_story_flag("ending_id", "")) == "overseas_ending",
		"Completion overseas: 远航结局成立")

	# 月历数据：章三召见条件不再锁死 rank4
	var cal_path := ResourcePaths.DATA_CALENDAR_EVENTS
	var cal_file := FileAccess.open(cal_path, FileAccess.READ)
	_assert_true(cal_file != null, "Completion: calendar_events.json 可读")
	if cal_file != null:
		var parsed = JSON.parse_string(cal_file.get_as_text())
		cal_file.close()
		_assert_true(parsed is Dictionary, "Completion: calendar_events 为对象")
		if parsed is Dictionary:
			var events: Array = (parsed as Dictionary).get("events", [])
			_assert_true(events.size() >= 5, "Completion: 月历事件 ≥5 条节拍")
			var summon_ok := false
			for raw in events:
				if not raw is Dictionary:
					continue
				var ev: Dictionary = raw
				if str(ev.get("id", "")) != "ch3_pu_summon":
					continue
				var cond: Dictionary = ev.get("condition", {})
				summon_ok = int(cond.get("rank_gte", 99)) <= 1 and str(cond.get("flag", "")) == "chapter2_complete"
			_assert_true(summon_ok, "Completion: ch3_pu_summon 仅需 chapter2 + rank≥1")

	game_state.from_save_dict(before)
	print("")

func _reset_completion_state(game_state, career) -> void:
	if career != null and career.has_method("from_dict"):
		career.from_dict({"rank": 0, "current_mandate": {}, "mandate_deadline_month": -1})
	if game_state.story != null and game_state.story.has_method("from_dict"):
		game_state.story.from_dict({
			"fame": 0,
			"flags": {},
			"story_flags": {},
			"story_items": {},
			"cards": {},
			"titles": {},
			"npc_relationships": {},
			"linboyuan_relationship": 0,
			"jia_relationship": 0,
			"unlocked_chapters": [],
		})
	game_state.fame = 0
	if game_state.has_method("bind_ending_resolver"):
		game_state.bind_ending_resolver(null)


## P7-B：SceneRouter 分类/解析（行为等价于旧 Main.load_scene 分支）
func _test_scene_router() -> void:
	print("[SceneRouter]")
	var SR = load(ResourcePaths.SCRIPT_SCENE_ROUTER)
	_assert_true(SR != null, "SceneRouter script 可加载")
	if SR == null:
		print("")
		return
	_assert_eq(SR.classify("world_map"), SR.KIND_WORLD_MAP, "SceneRouter: world_map")
	_assert_eq(SR.classify("quanzhou_market"), SR.KIND_MARKET, "SceneRouter: *_market")
	_assert_eq(SR.classify("port_linan"), SR.KIND_NARRATIVE, "SceneRouter: narrative port")
	_assert_eq(SR.classify("chapter3_pu_summon"), SR.KIND_NARRATIVE, "SceneRouter: narrative story")
	_assert_true(SR.is_world_map("world_map"), "SceneRouter.is_world_map")
	_assert_true(SR.is_market("x_market"), "SceneRouter.is_market")
	_assert_true(not SR.is_market("port_x"), "SceneRouter: port 不是 market")

	var gm = root.get_node_or_null("/root/GameManager")
	_assert_true(gm != null, "SceneRouter: GameManager 可取得")
	if gm != null:
		var port_data: Dictionary = SR.resolve_scene_data("port_linan")
		_assert_true(not port_data.is_empty(), "SceneRouter: port_linan 可解析")
		var missing: Dictionary = SR.resolve_scene_data("definitely_missing_scene_xyz")
		_assert_true(missing.is_empty(), "SceneRouter: 缺失场景返回空")
		# 设施后缀回退：若存在 city_tavern，则 foo_tavern 应解析到它
		var city_tavern: Dictionary = gm.get_scene_by_id("city_tavern")
		if not city_tavern.is_empty():
			var fallback: Dictionary = SR.resolve_scene_data("unknown_port_tavern")
			_assert_true(not fallback.is_empty(), "SceneRouter: *_tavern 回退 city_tavern")
			_assert_eq(str(fallback.get("id", "")), "city_tavern", "SceneRouter: 回退 id=city_tavern")

	var gs = root.get_node_or_null("/root/GameState")
	if gs != null:
		var before_port := str(gs.last_port)
		gs.last_port = "quanzhou"
		_assert_eq(SR.market_port_id("linan_market"), "quanzhou", "SceneRouter: market 优先 last_port")
		gs.last_port = ""
		_assert_eq(SR.market_port_id("linan_market"), "linan", "SceneRouter: market 回退 scene_id")
		gs.last_port = before_port

	_assert_eq(ResourcePaths.SCRIPT_SCENE_ROUTER, "res://scripts/SceneRouter.gd", "ResourcePaths.SCRIPT_SCENE_ROUTER")
	print("")


## 视觉 UI：设施/指令栏图标关键字解析
func _test_ui_icon_resolution() -> void:
	print("[UI Icon Resolution]")
	var FR = load(ResourcePaths.SCRIPT_FACILITY_RESOLVER)
	_assert_true(FR != null, "UI: FacilityResolver 可加载")
	if FR == null:
		print("")
		return
	_assert_true(FR.has_method("icon_keys_for"), "UI: icon_keys_for 存在")
	var keys_market: Array = FR.icon_keys_for("keelung_market", "市集")
	_assert_true("market" in keys_market, "UI: keelung_market → market")
	var keys_wharf: Array = FR.icon_keys_for("quanzhou_wharf", "码头")
	_assert_true("wharf" in keys_wharf, "UI: wharf 关键字")
	var keys_taixue: Array = FR.icon_keys_for("linan_taixue", "太学")
	_assert_true("exam" in keys_taixue, "UI: taixue → exam")
	var keys_temple: Array = FR.icon_keys_for("xinghua_temple", "寺庙")
	_assert_true("temple" in keys_temple or "residence" in keys_temple, "UI: temple 关键字")
	# 贴图可加载（autoload AssetPlaceholder 经 root 取）
	var ap = root.get_node_or_null("/root/AssetPlaceholder")
	_assert_true(ap != null, "UI: AssetPlaceholder autoload")
	if ap != null:
		var tex_market = ap.load_texture("res://assets/ui/icons/icon_market.png", "texture")
		_assert_true(tex_market != null, "UI: icon_market.png 可加载")
		var tex_story = ap.load_texture("res://assets/ui/icons/icon_storybook.png", "texture")
		_assert_true(tex_story != null, "UI: icon_storybook.png 可加载")
	var fac_tex: Texture2D = FR.resolve_facility_icon({"id": "bugan_tavern", "title": "酒肆"})
	_assert_true(fac_tex != null, "UI: bugan_tavern 解析到图标")
	var fac_look: Texture2D = FR.resolve_facility_icon({"id": "ryukyu_lookout", "title": "望台"})
	_assert_true(fac_look != null, "UI: lookout 解析到图标")
	print("")


## 无城镇图港口：双列设施分类（R1）
func _test_facility_column_split() -> void:
	print("[Facility Column Split]")
	var FR = load(ResourcePaths.SCRIPT_FACILITY_RESOLVER)
	_assert_true(FR != null and FR.has_method("split_facility_columns"), "Col: split_facility_columns 存在")
	if FR == null:
		print("")
		return
	_assert_eq(FR.column_side_for({"id": "city_tavern", "title": "酒肆"}), "left", "Col: tavern → left")
	_assert_eq(FR.column_side_for({"id": "xinghua_exam", "title": "县学"}), "left", "Col: exam → left")
	_assert_eq(FR.column_side_for({"id": "xinghua_temple", "title": "寺庙"}), "left", "Col: temple → left")
	_assert_eq(FR.column_side_for({"id": "city_market", "title": "市集"}), "right", "Col: market → right")
	_assert_eq(FR.column_side_for({"id": "linan_canal", "title": "运河"}), "right", "Col: canal → right")
	_assert_eq(FR.column_side_for({"id": "xinghua_wharf", "title": "码头"}), "right", "Col: wharf → right")

	var sample: Array = [
		{"id": "xinghua_exam", "title": "县学"},
		{"id": "xinghua_market", "title": "市集"},
		{"id": "xinghua_inn", "title": "客栈"},
		{"id": "xinghua_tavern", "title": "酒肆"},
		{"id": "xinghua_temple", "title": "寺庙"},
		{"id": "xinghua_wharf", "title": "码头"},
	]
	var split: Dictionary = FR.split_facility_columns(sample)
	var left_ids: Array = []
	var right_ids: Array = []
	for f in split.get("left", []):
		left_ids.append(str(f.get("id", "")))
	for f in split.get("right", []):
		right_ids.append(str(f.get("id", "")))
	_assert_true("xinghua_tavern" in left_ids or "xinghua_inn" in left_ids, "Col: 社交设施进左列")
	_assert_true("xinghua_exam" in left_ids or "xinghua_temple" in left_ids, "Col: 学/寺进左列")
	_assert_true("xinghua_market" in right_ids, "Col: 市集进右列")
	_assert_true("xinghua_wharf" in right_ids, "Col: 码头进右列")
	_assert_eq(left_ids.size() + right_ids.size(), sample.size(), "Col: 设施不丢不重")

	# 临安样例
	var linan: Array = [
		{"id": "linan_canal", "title": "运河"},
		{"id": "city_market", "title": "市集"},
		{"id": "city_inn", "title": "客栈"},
		{"id": "city_tavern", "title": "酒肆"},
		{"id": "linan_taixue", "title": "太学"},
	]
	var ls: Dictionary = FR.split_facility_columns(linan)
	var l_left: Array = []
	var l_right: Array = []
	for f in ls.get("left", []):
		l_left.append(str(f.get("id", "")))
	for f in ls.get("right", []):
		l_right.append(str(f.get("id", "")))
	_assert_true("city_tavern" in l_left and "city_inn" in l_left, "Col: 临安社交在左")
	_assert_true("linan_taixue" in l_left, "Col: 太学在左")
	_assert_true("city_market" in l_right and "linan_canal" in l_right, "Col: 市集/运河在右")

	# builder 脚本路径（避免 headless 下 class_name 静态链编译问题）
	_assert_true(
		ResourceLoader.exists("res://scripts/controllers/FacilitySlotBuilder.gd"),
		"Col: FacilitySlotBuilder 脚本存在"
	)
	print("")


## 航海/海战壳层文案
func _test_sea_feedback() -> void:
	print("[Sea Feedback]")
	_assert_eq(ResourcePaths.SCRIPT_SEA_FEEDBACK, "res://scripts/SeaFeedback.gd", "SeaFB: ResourcePaths")
	var SF = load(ResourcePaths.SCRIPT_SEA_FEEDBACK)
	_assert_true(SF != null, "SeaFB: 脚本可加载")
	if SF == null:
		print("")
		return
	_assert_true("遭遇" in SF.combat_start_log("倭寇"), "SeaFB: 开战日志含遭遇")
	_assert_true(SF.combat_start_log("").find("未知") >= 0 or SF.combat_start_log("").find("敌") >= 0, "SeaFB: 空敌名有兜底")
	var end_sunk: String = SF.combat_end_log({
		"victory_type": SF.VT_SUNK,
		"round": 3,
	})
	_assert_true("击沉" in end_sunk, "SeaFB: 击沉摘要")
	_assert_true("第3回合" in end_sunk, "SeaFB: 含回合")
	var end_empty: String = SF.combat_end_log({})
	_assert_true("中止" in end_empty, "SeaFB: 空结果=中止")
	_assert_eq(SF.victory_short(SF.VT_FLED), "成功撤退", "SeaFB: 撤退短文案")
	_assert_eq(SF.victory_short(SF.VT_DUEL_VICTORY), "单挑获胜", "SeaFB: 单挑短文案")
	_assert_true(SF.is_player_victory(SF.VT_SUNK), "SeaFB: 击沉算我方胜")
	_assert_true(not SF.is_player_victory(SF.VT_DEFEATED_SUNK), "SeaFB: 沉没算败")
	# 序值与 CombatState.VictoryType 对齐（运行时校验）
	var CS = load("res://scripts/state/CombatState.gd")
	if CS != null:
		_assert_eq(SF.VT_SUNK, int(CS.VictoryType.SUNK), "SeaFB: VT_SUNK 对齐 CombatState")
		_assert_eq(SF.VT_FLED, int(CS.VictoryType.FLED), "SeaFB: VT_FLED 对齐 CombatState")
	_assert_true("海遇" in SF.event_open_log("台风压顶"), "SeaFB: 海遇开场")
	_assert_true("台风" in SF.event_result_log("台风压顶", "损失淡水。"), "SeaFB: 海遇结果")
	_assert_true("开战" in SF.event_to_combat_log("水师"), "SeaFB: 升级开战")
	_assert_true("接敌" in SF.contact_engage_bbcode("海盗"), "SeaFB: 接敌 bbcode")
	_assert_true("远距离" in SF.phase_status_bbcode("远距离对峙"), "SeaFB: 阶段 bbcode")
	_assert_true("第 2" in SF.round_header_bbcode(2, "回合"), "SeaFB: 回合头")
	print("")


## 经济手感：三策可感知
func _test_economy_feel() -> void:
	print("[Economy Feel]")
	_assert_eq(ResourcePaths.SCRIPT_ECONOMY_FEEL, "res://scripts/EconomyFeel.gd", "EconFeel: ResourcePaths")
	var EF = load(ResourcePaths.SCRIPT_ECONOMY_FEEL)
	_assert_true(EF != null, "EconFeel: 脚本可加载")
	if EF == null:
		print("")
		return
	var triad: Array = EF.strategy_triad("quanzhou")
	_assert_eq(triad.size(), 3, "EconFeel: 三策恒为 3 条")
	_assert_true("稳" in str(triad[0]), "EconFeel: 第1条为稳策")
	_assert_true("赌" in str(triad[1]), "EconFeel: 第2条为赌策")
	_assert_true("搬" in str(triad[2]), "EconFeel: 第3条为搬策")
	var block: String = EF.format_triad_block("quanzhou")
	_assert_true(block.find("\n") >= 0, "EconFeel: format 多行")
	# 交易提示非空
	var buy_h: String = EF.trade_decision_hint("quanzhou", "fujian_porcelain", "buy", 5)
	_assert_true(buy_h != "" and "商策" in buy_h, "EconFeel: 买入商策")
	var sell_h: String = EF.trade_decision_hint("quanzhou", "fujian_porcelain", "sell", 5)
	_assert_true(sell_h != "" and "商策" in sell_h, "EconFeel: 卖出商策")
	# arbitrage 结构（可能为空字典，但应可调用）
	var arb: Dictionary = EF.best_arbitrage("quanzhou")
	_assert_true(arb is Dictionary, "EconFeel: best_arbitrage 返回字典")
	if not arb.is_empty():
		_assert_true(str(arb.get("good_id", "")) != "", "EconFeel: 差价含 good_id")
		_assert_true(str(arb.get("direction", "")) != "", "EconFeel: 差价含方向")
	# 空 port 不崩
	var empty_triad: Array = EF.strategy_triad("")
	_assert_eq(empty_triad.size(), 3, "EconFeel: 空 port 仍给三策")
	print("")


## 情报账本：信息差可购可记
func _test_intel_notes() -> void:
	print("[Intel Notes]")
	_assert_eq(ResourcePaths.SCRIPT_INTEL_NOTES, "res://scripts/IntelNotes.gd", "Intel: ResourcePaths")
	var IN = load(ResourcePaths.SCRIPT_INTEL_NOTES)
	_assert_true(IN != null, "Intel: 脚本可加载")
	if IN == null:
		print("")
		return
	_assert_eq(IN.event_type_label("disaster"), "市舶灾变", "Intel: disaster 标签")
	_assert_eq(IN.event_type_label("boom"), "贸易繁荣", "Intel: boom 标签")
	var rumor := {
		"port_name": "泉州",
		"days_left": 8,
		"type": "shortage",
		"event": {"target_port": "quanzhou", "event_id": "supply_shortage"},
	}
	var n1: Dictionary = IN.build_from_rumor(rumor, 1)
	_assert_true("变故" in str(n1.get("summary", "")) or "不寻常" in str(n1.get("summary", "")) or "风闻" in str(n1.get("summary", "")), "Intel: t1 模糊")
	_assert_eq(str(n1.get("port_id", "")), "", "Intel: t1 不点名 port_id")
	var n2: Dictionary = IN.build_from_rumor(rumor, 2)
	_assert_true("日" in str(n2.get("summary", "")), "Intel: t2 有时间窗")
	var n3: Dictionary = IN.build_from_rumor(rumor, 3)
	_assert_true("泉州" in str(n3.get("summary", "")), "Intel: t3 点名港口")
	_assert_true("确报" in str(n3.get("summary", "")), "Intel: t3 确报")
	_assert_eq(str(n3.get("port_id", "")), "quanzhou", "Intel: t3 port_id")

	var book = IN.new()
	book.record(n3)
	var n3b: Dictionary = n3.duplicate(true)
	n3b["summary"] = "【确报】升级版摘要"
	n3b["tier"] = 3
	book.record(n3b)
	_assert_true(book.has_any(), "Intel: 有记录")
	_assert_eq(book.list_recent(5).size(), 1, "Intel: 同 port+type 覆盖不叠两条")
	_assert_true("升级版" in str(book.list_recent(1)[0].get("summary", "")), "Intel: 覆盖为更高摘要")
	# 不同 type 并存
	var n_other: Dictionary = IN.build_from_rumor({
		"port_name": "琉球", "days_left": 5, "type": "pirate",
		"event": {"target_port": "ryukyu", "event_id": "pirate_attack"},
	}, 3)
	book.record(n_other)
	_assert_eq(book.list_recent(5).size(), 2, "Intel: 不同类型并存")
	var block: String = IN.format_notes_block(book.list_recent(3), 3)
	_assert_true("已知情报" in block, "Intel: 格式块标题")
	# 存档往返
	var d: Dictionary = book.to_dict()
	var book2 = IN.new()
	book2.from_dict(d)
	_assert_eq(book2.list_recent(5).size(), 2, "Intel: 反序列化条数")

	var gs = root.get_node_or_null("/root/GameState")
	_assert_true(gs != null and gs.get("intel_notes") != null, "Intel: GameState.intel_notes")
	if gs != null and gs.intel_notes != null:
		var before_n: int = gs.intel_notes.list_recent(20).size()
		gs.intel_notes.record(n3)
		_assert_true(gs.intel_notes.list_recent(20).size() >= before_n, "Intel: GameState 可记")
		# 三策应能读到情报（赌线）
		var EF = load(ResourcePaths.SCRIPT_ECONOMY_FEEL)
		if EF != null:
			var triad: Array = EF.strategy_triad("quanzhou")
			_assert_true(triad.size() == 3, "Intel: 三策仍 3 条")
	print("")


const P9A_KOEI_PATCH := 40

## 标题 KOEI 外框 + 城镇热区图标板
func _test_title_and_hotspot_visual() -> void:
	print("[Title + Hotspot Visual]")
	var frame_tex: Texture2D = load(ResourcePaths.FRAME_KOEI) as Texture2D
	_assert_true(frame_tex != null, "Visual: ui_frame_koei.png 可加载")
	if frame_tex != null:
		_assert_true(frame_tex.get_width() > P9A_KOEI_PATCH * 2, "Visual: 框纹理宽 > 2*patch")
		_assert_true(frame_tex.get_height() > P9A_KOEI_PATCH * 2, "Visual: 框纹理高 > 2*patch")

	var title_script: GDScript = load("res://scripts/TitleScreenController.gd") as GDScript
	_assert_true(title_script != null, "Visual: TitleScreenController 可加载")
	if title_script != null:
		var host := Control.new()
		host.set_script(title_script)
		host.size = Vector2(1280, 720)
		var panel := PanelContainer.new()
		panel.name = "TitlePanel"
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.offset_left = -380
		panel.offset_top = -280
		panel.offset_right = 380
		panel.offset_bottom = 280
		host.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.name = "VBoxContainer"
		panel.add_child(vbox)
		var mt := Label.new()
		mt.name = "MainTitle"
		vbox.add_child(mt)
		var st := Label.new()
		st.name = "SubTitle"
		vbox.add_child(st)
		var bc := VBoxContainer.new()
		bc.name = "ButtonContainer"
		vbox.add_child(bc)
		root.add_child(host)
		# setup 内会 _ensure_koei_chrome / _ensure_title_divider
		if host.has_method("setup"):
			host.call("setup", {
				"cg_title": "测",
				"cg_sub": "副",
				"choices": [
					{"label": "开始旅程", "next": "scene01_xianghua_school"},
					{"label": "跳过序章：直接进入泉州港", "next": "port_quanzhou"},
				],
			})
		_assert_true(host.has_node("KoeiOuterFrame"), "Visual: 标题有 KoeiOuterFrame")
		if host.has_node("KoeiOuterFrame"):
			var fr := host.get_node("KoeiOuterFrame") as NinePatchRect
			_assert_true(fr != null and fr.texture != null, "Visual: KOEI 框贴图就绪")
			_assert_true(fr.patch_margin_left == P9A_KOEI_PATCH, "Visual: KOEI patch margin 对齐 DialogueBox")
		var has_div := panel.get_node_or_null("VBoxContainer/TitleDivider") != null \
			or panel.get_node_or_null("VBoxContainer/TitleDividerWrap/TitleDivider") != null
		_assert_true(has_div, "Visual: 副标题下有金线分隔")
		# 标题页保留两个剧情选择，不出现假“继续”
		var choice_labels: Array[String] = []
		for child in bc.get_children():
			if child is Button:
				choice_labels.append(str((child as Button).text))
		_assert_true(choice_labels.has("开始旅程"), "Visual: 标题有开始旅程")
		_assert_true(choice_labels.has("跳过序章：直接进入泉州港"), "Visual: 标题有跳过序章")
		var fake_continue := false
		for lab in choice_labels:
			if lab == "继续" or lab == "开始":
				fake_continue = true
		_assert_true(not fake_continue, "Visual: 标题无 CommandBar 假入口文案")
		host.queue_free()

	var hs_scene: PackedScene = load(ResourcePaths.SCENE_TOWN_MAP_HOTSPOT) as PackedScene
	_assert_true(hs_scene != null, "Visual: TownMapHotspot 场景可加载")
	if hs_scene != null:
		var hs_parent := Control.new()
		hs_parent.size = Vector2(1280, 720)
		root.add_child(hs_parent)
		var hs: Control = hs_scene.instantiate() as Control
		hs_parent.add_child(hs)
		if hs.has_method("setup"):
			hs.call("setup",
				{"rect": [0.1, 0.1, 0.2, 0.2], "label": "市集", "hint": "买卖"},
				{"state": "default", "text": ""},
				"keelung_market",
				{"id": "keelung_market", "title": "市集"}
			)
			# setup 里 call_deferred；测试直接 finalize，避免 await 打断 _run
			if hs.has_method("_finalize_icon_layout"):
				hs.call("_finalize_icon_layout")
			var icon := hs.get_node_or_null("IconRect") as TextureRect
			_assert_true(icon != null, "Visual: Hotspot 有 IconRect")
			if icon != null:
				_assert_true(icon.visible and icon.texture != null, "Visual: Hotspot 图标已解析显示")
			var plate := hs.get_node_or_null("IconPlate") as PanelContainer
			_assert_true(plate != null and plate.visible, "Visual: Hotspot 有黄铜 IconPlate")
		hs_parent.queue_free()

	var tmv_scene: PackedScene = load("res://scenes/TownMapView.tscn") as PackedScene
	_assert_true(tmv_scene != null, "Visual: TownMapView 场景可加载")
	if tmv_scene != null:
		var tmv: Control = tmv_scene.instantiate() as Control
		root.add_child(tmv)
		_assert_true(tmv.has_node("MapFrame"), "Visual: TownMapView 有 MapFrame")
		var map_frame := tmv.get_node_or_null("MapFrame") as NinePatchRect
		_assert_true(map_frame != null, "Visual: MapFrame 为 NinePatchRect")
		if map_frame != null:
			_assert_true(map_frame.texture != null, "Visual: MapFrame 木框贴图就绪")
			_assert_true(map_frame.patch_margin_left == P9A_KOEI_PATCH and map_frame.patch_margin_top == P9A_KOEI_PATCH, "Visual: MapFrame patch 对齐 DialogueBox")
			_assert_true(map_frame.patch_margin_right == P9A_KOEI_PATCH and map_frame.patch_margin_bottom == P9A_KOEI_PATCH, "Visual: MapFrame patch 右下对齐")
			_assert_true(map_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Visual: MapFrame 不抢热区点击")
		_assert_true(tmv.has_node("MapFrame/MapClip/HotspotLayer"), "Visual: HotspotLayer 在 MapClip 内")
		_assert_true(tmv.has_node("MapFrame/MapClip/MapTexture"), "Visual: MapTexture 在 MapClip 内")
		var clip := tmv.get_node_or_null("MapFrame/MapClip") as Control
		if clip != null:
			_assert_true(clip.clip_contents, "Visual: MapClip 裁切地图内容")
		# setup 后 _ready 已跑 → HintPlaque 应存在
		if tmv.has_method("_ensure_hint_plaque"):
			tmv.call("_ensure_hint_plaque")
		_assert_true(
			tmv.has_node("MapFrame/MapClip/HintPlaque") or tmv.get_node_or_null("MapFrame/MapClip/MapHint") != null,
			"Visual: 地图提示牌或 MapHint 存在"
		)
		if tmv.has_node("MapFrame/MapClip/HintPlaque"):
			var plaque := tmv.get_node("MapFrame/MapClip/HintPlaque") as PanelContainer
			_assert_true(plaque != null, "Visual: HintPlaque 为 PanelContainer")
		# 新图标 import 后可 ResourceLoader
		var market_ok := ResourceLoader.exists("res://assets/ui/icons/icon_market.png") \
			or FileAccess.file_exists("res://assets/ui/icons/icon_market.png")
		_assert_true(market_ok, "Visual: icon_market.png 资源可访问")
		tmv.queue_free()
	print("")


## P9-A：标题单一导航 + KOEI 边框消费者 patch 统一
func _test_p9a_first_hour_ux() -> void:
	print("[P9-A First Hour UX]")
	var ui_file := FileAccess.open("res://data/ui_commands.json", FileAccess.READ)
	var ui_data = JSON.parse_string(ui_file.get_as_text()) if ui_file != null else {}
	if ui_file != null:
		ui_file.close()
	var templates: Dictionary = ui_data.get("templates", {}) if ui_data is Dictionary else {}
	_assert_true(not templates.has("title"), "P9-A: ui_commands templates 不含 title 假入口")

	var shell_script: GDScript = load("res://scripts/GameShell.gd") as GDScript
	_assert_true(shell_script != null, "P9-A: GameShell 可加载")
	if shell_script != null:
		var shell := Control.new()
		shell.set_script(shell_script)
		shell.size = Vector2(1280, 720)
		var background_layer := Control.new()
		background_layer.name = 'BackgroundLayer'
		var background := TextureRect.new()
		background.name = 'Background'
		background_layer.add_child(background)
		shell.add_child(background_layer)
		var vignette_layer := Control.new()
		vignette_layer.name = 'VignetteLayer'
		shell.add_child(vignette_layer)
		var content := Control.new()
		content.name = "ContentLayer"
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		shell.add_child(content)
		var host := PanelContainer.new()
		host.name = "CommandBarHost"
		host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		host.offset_top = -104.0
		shell.add_child(host)
		root.add_child(shell)
		# 手动注入 onready 依赖后走 apply_scene
		shell.set("content_layer", content)
		shell.set("command_bar_host", host)
		shell.set("_command_bar", null)
		if shell.has_method("_set_command_bar_active"):
			shell.call("_set_command_bar_active", false)
		_assert_true(not host.visible, "P9-A: type=title 时 CommandBarHost 隐藏")
		_assert_eq(content.offset_bottom, 0.0, "P9-A: 标题页不保留底部 104px 空间")
		_assert_eq(host.offset_top, 0.0, "P9-A: CommandBarHost 折叠 offset_top=0")
		if shell.has_method("_set_command_bar_active"):
			shell.call("_set_command_bar_active", true)
		_assert_true(host.visible, "P9-A: 游戏模式 CommandBarHost 可见")
		_assert_eq(content.offset_bottom, -104.0, "P9-A: 游戏模式保留 CommandBar 高度")
		if shell.has_method("_resolve_command_spec"):
			var spec: Dictionary = shell.call("_resolve_command_spec", "title", {"type": "title"})
			_assert_eq(str(spec.get("template", "x")), "", "P9-A: title 解析为空 template")
		shell.queue_free()

	# 有存档槽走真实 load；空槽不显示“继续”
	var title_script: GDScript = load("res://scripts/TitleScreenController.gd") as GDScript
	if title_script != null:
		var host2 := Control.new()
		host2.set_script(title_script)
		var panel2 := PanelContainer.new()
		panel2.name = "TitlePanel"
		host2.add_child(panel2)
		var vbox2 := VBoxContainer.new()
		vbox2.name = "VBoxContainer"
		panel2.add_child(vbox2)
		var mt2 := Label.new()
		mt2.name = "MainTitle"
		vbox2.add_child(mt2)
		var st2 := Label.new()
		st2.name = "SubTitle"
		vbox2.add_child(st2)
		var bc2 := VBoxContainer.new()
		bc2.name = "ButtonContainer"
		vbox2.add_child(bc2)
		root.add_child(host2)
		if host2.has_method("setup"):
			host2.call("setup", {"cg_title": "t", "cg_sub": "s", "choices": []})
		var has_continue_btn := _tree_has_continue_button(bc2)
		# 空存档行是 Label「空存档」，不应出现独立“继续”按钮
		_assert_true(not has_continue_btn, "P9-A: 无存档时不显示继续按钮")
		var src := FileAccess.get_file_as_string("res://scripts/TitleScreenController.gd")
		_assert_true(src.contains("SaveManager.load_game(slot)"), "P9-A: 槽位按钮走真实 load_game")
		host2.queue_free()

	# KOEI 消费者：可实例化且 patch < 纹理半宽
	var frame_tex2: Texture2D = load(ResourcePaths.FRAME_KOEI) as Texture2D
	var half_w := frame_tex2.get_width() / 2 if frame_tex2 != null else 0
	var half_h := frame_tex2.get_height() / 2 if frame_tex2 != null else 0
	_assert_true(P9A_KOEI_PATCH < half_w and P9A_KOEI_PATCH < half_h, "P9-A: patch margin < 纹理半宽高")

	var consumers: Array = [
		"res://scenes/DialogueBox.tscn",
		"res://scenes/TownMapView.tscn",
		"res://scenes/WorldMap.tscn",
		"res://scenes/StrategicMapOverlay.tscn",
	]
	for path in consumers:
		var ps: PackedScene = load(path) as PackedScene
		_assert_true(ps != null, "P9-A: 可加载 %s" % path.get_file())
		if ps == null:
			continue
		var node: Node = ps.instantiate()
		root.add_child(node)
		_assert_koei_patch_on_tree(node, path.get_file())
		node.queue_free()

	# DialogueBox Frame 高度范围：1280x720 / 1920x1080 不盖顶栏
	var dlg_ps: PackedScene = load("res://scenes/DialogueBox.tscn") as PackedScene
	if dlg_ps != null:
		for size_value in [Vector2(1280, 720), Vector2(1920, 1080)]:
			var sz: Vector2 = size_value
			var dlg: Control = dlg_ps.instantiate() as Control
			dlg.set_anchors_preset(Control.PRESET_TOP_LEFT)
			dlg.size = sz
			root.add_child(dlg)
			var frame := dlg.get_node_or_null("Frame") as NinePatchRect
			_assert_true(frame != null, "P9-A: DialogueBox 有 Frame @%dx%d" % [int(sz.x), int(sz.y)])
			if frame != null:
				var frame_h := absf(frame.offset_top - frame.offset_bottom)
				_assert_true(frame_h >= 200.0 and frame_h <= 480.0, "P9-A: Frame 高度在设计范围 @%dx%d (h=%.0f)" % [int(sz.x), int(sz.y), frame_h])
				# 底锚 + offset_top 负值 → 顶部应低于状态栏区域（约 80px）
				var top_y: float = sz.y + frame.offset_top
				var margin = frame.get_node_or_null('Margin')
				_assert_true(margin != null, 'P9-A: DialogueBox margin exists')
				if margin != null:
					var top_margin: int = margin.get_theme_constant('margin_top')
					_assert_true(top_margin >= 48, 'P9-A: content clears frame ornament')
				_assert_true(top_y > 80.0, "P9-A: Frame 不覆盖顶部状态栏 @%dx%d" % [int(sz.x), int(sz.y)])
				_assert_eq(frame.patch_margin_left, P9A_KOEI_PATCH, "P9-A: DialogueBox patch L")
				_assert_eq(frame.patch_margin_top, P9A_KOEI_PATCH, "P9-A: DialogueBox patch T")
			dlg.queue_free()
	print("")


## P9-C：GameState 只聚合状态，过场交给壳层，经济文案交给 EconomyFeel。
func _test_p9c_architecture_boundaries() -> void:
	print("[P9-C Architecture Boundaries]")
	var game_state_source := FileAccess.get_file_as_string("res://scripts/GameState.gd")
	_assert_true(game_state_source.contains("signal cutscene_requested"), "P9-C: GameState 暴露过场请求信号")
	_assert_true(not game_state_source.contains("ShellCutscenePlayer"), "P9-C: GameState 不查找 ShellCutscenePlayer")
	_assert_true(not game_state_source.contains('find_child("CutscenePlayer"'), "P9-C: GameState 不遍历查找 CutscenePlayer")
	_assert_true(not game_state_source.contains("SCRIPT_MODE_STACK"), "P9-C: GameState 不动态加载 ModeStack")
	_assert_true(not game_state_source.contains("func _compose_economy_pulse_message"), "P9-C: GameState 不组合经济月报文案")

	var economy_source := FileAccess.get_file_as_string(ResourcePaths.SCRIPT_ECONOMY_FEEL)
	_assert_true(economy_source.contains("func monthly_pulse_message"), "P9-C: EconomyFeel 接管经济月报文案")
	var app_root_source := FileAccess.get_file_as_string("res://scripts/AppRoot.gd")
	var main_source := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_assert_true(app_root_source.contains("cutscene_requested.is_connected"), "P9-C: AppRoot 防重复绑定过场请求")
	_assert_true(main_source.contains("cutscene_requested.is_connected"), "P9-C: Main 兼容入口防重复绑定过场请求")

	var theme: Theme = load("res://assets/main_theme.tres") as Theme
	var required_variations := [
		UITheme.ENDING_KICKER, UITheme.ENDING_TITLE, UITheme.ENDING_SUBTITLE,
		UITheme.ENDING_META, UITheme.ENDING_SUMMARY, UITheme.ENDING_EPILOGUE,
		UITheme.TOWN_HOTSPOT_PANEL, UITheme.TOWN_HOTSPOT_TITLE,
		UITheme.TOWN_HINT_PANEL, UITheme.TOWN_HINT_LABEL,
		UITheme.PORT_COLUMN_HEADER, UITheme.PORT_COLUMN_HEADER_LABEL,
		UITheme.TEXT_TITLE_SAVE_HEADER, UITheme.PORT_FACILITY_HINT,
		UITheme.MAP_STRATEGIC_POPUP, UITheme.MAP_STRATEGIC_TITLE,
		UITheme.MAP_STRATEGIC_INFO, UITheme.MAP_STRATEGIC_BUTTON,
	]
	for variation in required_variations:
		_assert_true(UITheme.assert_all_known(variation), "P9-C: UITheme 登记 %s" % variation)
		_assert_true(theme != null and theme.get_type_variation_base(variation) != &"", "P9-C: main_theme 定义 %s" % variation)
	var ending_source := FileAccess.get_file_as_string("res://scripts/EndingSettlementController.gd")
	_assert_true(not ending_source.contains("add_theme_color_override"), "P9-C: EndingSettlement 无固定颜色 override")
	_assert_true(not ending_source.contains("add_theme_font_size_override"), "P9-C: EndingSettlement 无固定字号 override")
	print("")


func _tree_has_continue_button(node: Node) -> bool:
	if node is Button:
		var t := str((node as Button).text)
		if t == "继续" or t.begins_with("继续"):
			return true
	for child in node.get_children():
		if _tree_has_continue_button(child):
			return true
	return false


func _assert_koei_patch_on_tree(node: Node, label: String) -> void:
	if node is NinePatchRect:
		var np := node as NinePatchRect
		if np.texture != null and str(np.texture.resource_path).ends_with("ui_frame_koei.png"):
			_assert_eq(np.patch_margin_left, P9A_KOEI_PATCH, "P9-A: %s/%s patch L" % [label, np.name])
			_assert_eq(np.patch_margin_top, P9A_KOEI_PATCH, "P9-A: %s/%s patch T" % [label, np.name])
			_assert_eq(np.patch_margin_right, P9A_KOEI_PATCH, "P9-A: %s/%s patch R" % [label, np.name])
			_assert_eq(np.patch_margin_bottom, P9A_KOEI_PATCH, "P9-A: %s/%s patch B" % [label, np.name])
	for child in node.get_children():
		_assert_koei_patch_on_tree(child, label)


## 内容/体验：章三续进 + shell_log / economy_pulse
func _test_content_experience_hooks() -> void:
	print("[Content Experience]")
	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "ContentExp: GameState 可取得")
	if game_state == null:
		print("")
		return
	var before: Dictionary = game_state.to_save_dict()
	var noticed: Array = []
	var cb := func(msg: String): noticed.append(msg)
	if not game_state.story_unlock_notified.is_connected(cb):
		game_state.story_unlock_notified.connect(cb)

	# shell_log
	game_state.apply_effects({"shell_log": "【测试】时局提示一条"})
	_assert_true(noticed.size() >= 1, "ContentExp: shell_log 触发 story_unlock_notified")
	_assert_true(str(noticed[-1]).contains("时局提示"), "ContentExp: shell_log 文案透传")

	# economy_pulse
	var econ_before := 0
	if game_state.economy_log != null:
		econ_before = game_state.economy_log.get_entries().size()
	game_state.apply_effects({"economy_pulse": true})
	if game_state.economy_log != null:
		_assert_true(game_state.economy_log.get_entries().size() > econ_before, "ContentExp: economy_pulse 写入 EconomyLog")
	_assert_true(noticed.size() >= 2, "ContentExp: economy_pulse 推消息栏")

	# chapter3 resume resolver
	var C3 = load(ResourcePaths.SCRIPT_CHAPTER3_FLOW)
	_assert_true(C3 != null, "ContentExp: Chapter3Flow 可加载")
	if C3 != null:
		game_state.story.from_dict({
			"fame": 0, "flags": {}, "story_flags": {}, "story_items": {},
			"cards": {}, "titles": {}, "npc_relationships": {},
			"linboyuan_relationship": 0, "jia_relationship": 0, "unlocked_chapters": [],
		})
		_assert_eq(C3.resolve_resume_scene(), "", "ContentExp: 无章二不可续")
		game_state.set_story_flag("chapter2_complete", true)
		_assert_eq(C3.resolve_resume_scene(), "chapter3_pu_summon", "ContentExp: 章二后应召")
		game_state.set_story_flag("chapter3_pu_deal_accepted", true)
		_assert_eq(C3.resolve_resume_scene(), "chapter3_after_summon_comply", "ContentExp: 投附后续")
		game_state.set_story_flag("chapter3_comply_taixue_registered", true)
		_assert_eq(C3.resolve_resume_scene(), "chapter3_comply_audit", "ContentExp: 名籍后续试")
		game_state.set_story_flag("chapter3_complete", true)
		_assert_eq(C3.resolve_resume_scene(), "", "ContentExp: 章三完结不续")

	# 月历节拍数量
	var cal_path := ResourcePaths.DATA_CALENDAR_EVENTS
	var f := FileAccess.open(cal_path, FileAccess.READ)
	_assert_true(f != null, "ContentExp: calendar_events 可读")
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var events: Array = parsed.get("events", [])
			_assert_true(events.size() >= 8, "ContentExp: 月历节拍 ≥8")
			var has_pulse := false
			var has_rumor := false
			for raw in events:
				if not raw is Dictionary:
					continue
				var eid := str(raw.get("id", ""))
				if eid == "econ_gossip_pulse":
					has_pulse = true
				if eid == "ch3_street_rumor":
					has_rumor = true
			_assert_true(has_pulse, "ContentExp: 含月报商情脉搏")
			_assert_true(has_rumor, "ContentExp: 含章三城中风声")

	if game_state.story_unlock_notified.is_connected(cb):
		game_state.story_unlock_notified.disconnect(cb)
	game_state.from_save_dict(before)
	print("")


## P8-5：WorldMap HUD 顶边避让公式
func _test_sea_hud_layout() -> void:
	print("[SeaHudLayout]")
	_assert_eq(GameUILayout.SEA_HUD_MARGIN_DEFAULT, 20.0, "SEA_HUD_MARGIN_DEFAULT")
	_assert_eq(GameUILayout.sea_hud_top_margin(false), 20.0, "无壳层: top=20")
	_assert_eq(
		GameUILayout.sea_hud_top_margin(true, GameUILayout.STATUS_BAR_HEIGHT_FULL),
		GameUILayout.STATUS_BAR_HEIGHT_FULL + GameUILayout.SEA_HUD_MARGIN_BELOW_CHROME,
		"有壳层 FULL: top=bar+8"
	)
	_assert_eq(
		GameUILayout.sea_hud_top_margin(true, GameUILayout.STATUS_BAR_HEIGHT_COMPACT),
		GameUILayout.STATUS_BAR_HEIGHT_COMPACT + 8.0,
		"有壳层 COMPACT: top=bar+8"
	)
	print("")


## P8：ModeStack / AppRoot API（无宿主回退；轻量 stub 宿主）
func _test_mode_stack() -> void:
	print("[ModeStack]")
	var MS = load(ResourcePaths.SCRIPT_MODE_STACK)
	_assert_true(MS != null, "ModeStack script 可加载")
	if MS == null:
		print("")
		return
	_assert_eq(MS.MODE_NARRATIVE, "narrative", "ModeStack.MODE_NARRATIVE")
	_assert_eq(MS.MODE_VOYAGE, "voyage", "ModeStack.MODE_VOYAGE")
	_assert_eq(MS.MODE_COMBAT, "combat", "ModeStack.MODE_COMBAT")
	_assert_eq(MS.MODE_CUTSCENE, "cutscene", "ModeStack.MODE_CUTSCENE")
	# TestRunner 作为 SceneTree 通常无 AppRoot 宿主
	_assert_true(not MS.go_voyage(self), "ModeStack: 无宿主 go_voyage=false（调用方应回退 change_scene）")
	_assert_true(not MS.go_narrative(self, "port_linan"), "ModeStack: 无宿主 go_narrative=false")
	_assert_eq(MS.current_mode(self), "", "ModeStack: 无宿主 current_mode 空")
	_assert_true(MS.start_combat(self, {"id": "x"}) == null, "ModeStack: 无宿主 start_combat=null")
	_assert_true(not MS.is_combat(self), "ModeStack: 无宿主 is_combat=false")
	_assert_true(not MS.play_cutscene(self, "any"), "ModeStack: 无宿主 play_cutscene=false")
	_assert_true(MS.get_cutscene_player(self) == null, "ModeStack: 无宿主 get_cutscene_player=null")
	_assert_true(not MS.is_cutscene(self), "ModeStack: 无宿主 is_cutscene=false")

	# 轻量 stub 宿主（不实例化 Main/WorldMap）
	var stub_gd := GDScript.new()
	stub_gd.source_code = """
extends Node
var voyage_hits: int = 0
var narrative_hits: int = 0
var combat_hits: int = 0
var cutscene_hits: int = 0
var last_scene: String = \"\"
var last_enemy: Dictionary = {}
var last_cutscene: String = \"\"
var _mode: String = \"narrative\"
var _cs: Node = null
func show_voyage() -> void:
	voyage_hits += 1
	_mode = \"voyage\"
func show_narrative(scene_id: String = \"\") -> void:
	narrative_hits += 1
	last_scene = scene_id
	_mode = \"narrative\"
func show_combat(enemy: Dictionary) -> Node:
	combat_hits += 1
	last_enemy = enemy
	_mode = \"combat\"
	return Node.new()
func play_cutscene(cutscene_id: String) -> bool:
	cutscene_hits += 1
	last_cutscene = cutscene_id
	_mode = \"cutscene\"
	return cutscene_id != \"\"
func get_cutscene_player() -> Node:
	if _cs == null:
		_cs = Node.new()
		add_child(_cs)
	return _cs
func get_mode() -> String:
	return _mode
"""
	var reload_err := stub_gd.reload()
	_assert_eq(reload_err, OK, "ModeStack stub GDScript reload OK")
	var stub := Node.new()
	stub.set_script(stub_gd)
	root.add_child(stub)
	_assert_true(MS.find_host(self) == stub, "ModeStack.find_host 找到 stub 宿主")
	_assert_true(MS.go_voyage(self), "ModeStack.go_voyage 经 stub 成功")
	_assert_eq(stub.get("voyage_hits"), 1, "ModeStack: stub.show_voyage 被调用")
	_assert_true(MS.go_narrative(self, "port_linan"), "ModeStack.go_narrative 经 stub 成功")
	_assert_eq(stub.get("narrative_hits"), 1, "ModeStack: stub.show_narrative 被调用")
	_assert_eq(str(stub.get("last_scene")), "port_linan", "ModeStack: scene_id 透传")
	_assert_eq(MS.current_mode(self), "narrative", "ModeStack.current_mode 读 stub")
	var combat_node = MS.start_combat(self, {"id": "pirate_junk", "name": "海寇"})
	_assert_true(combat_node != null, "ModeStack.start_combat 经 stub 返回节点")
	_assert_eq(stub.get("combat_hits"), 1, "ModeStack: stub.show_combat 被调用")
	_assert_eq(str((stub.get("last_enemy") as Dictionary).get("id", "")), "pirate_junk", "ModeStack: enemy 透传")
	_assert_true(MS.is_combat(self), "ModeStack.is_combat 在 stub 战斗中")
	if combat_node != null and is_instance_valid(combat_node):
		combat_node.free()
	_assert_true(MS.play_cutscene(self, "ending_loyalty"), "ModeStack.play_cutscene 经 stub 成功")
	_assert_eq(stub.get("cutscene_hits"), 1, "ModeStack: stub.play_cutscene 被调用")
	_assert_eq(str(stub.get("last_cutscene")), "ending_loyalty", "ModeStack: cutscene_id 透传")
	_assert_true(MS.is_cutscene(self), "ModeStack.is_cutscene 在 stub 过场中")
	_assert_true(MS.get_cutscene_player(self) != null, "ModeStack.get_cutscene_player 经 stub")
	stub.free()

	var app_scr = load(ResourcePaths.SCRIPT_APP_ROOT)
	_assert_true(app_scr != null and app_scr is Script, "AppRoot script 可加载")
	if app_scr != null and app_scr is Script:
		_assert_true((app_scr as Script).can_instantiate(), "AppRoot 可实例化")
		var app: Node = (app_scr as Script).new()
		_assert_true(app.has_method("show_voyage"), "AppRoot.show_voyage")
		_assert_true(app.has_method("show_narrative"), "AppRoot.show_narrative")
		_assert_true(app.has_method("show_combat"), "AppRoot.show_combat")
		_assert_true(app.has_method("get_combat"), "AppRoot.get_combat")
		_assert_true(app.has_method("play_cutscene"), "AppRoot.play_cutscene")
		_assert_true(app.has_method("get_cutscene_player"), "AppRoot.get_cutscene_player")
		_assert_true(app.has_method("get_mode"), "AppRoot.get_mode")
		app.free()

	# CutscenePlayer API
	var cs_scene: PackedScene = load(ResourcePaths.SCENE_CUTSCENE_PLAYER) as PackedScene
	_assert_true(cs_scene != null, "CutscenePlayer scene 可加载")
	if cs_scene != null:
		var cs = cs_scene.instantiate()
		root.add_child(cs)
		_assert_true(cs.has_method("is_playing"), "CutscenePlayer.is_playing")
		_assert_true(cs.has_signal("started"), "CutscenePlayer.started 信号")
		_assert_true(cs.has_signal("finished"), "CutscenePlayer.finished 信号")
		_assert_true(not bool(cs.call("is_playing")), "CutscenePlayer: 初始未播放")
		cs.queue_free()

	_assert_eq(ResourcePaths.SCENE_APP_ROOT, "res://scenes/AppRoot.tscn", "ResourcePaths.SCENE_APP_ROOT")
	_assert_eq(ResourcePaths.SCRIPT_MODE_STACK, "res://scripts/ModeStack.gd", "ResourcePaths.SCRIPT_MODE_STACK")
	_assert_eq(ResourcePaths.SCRIPT_APP_ROOT, "res://scripts/AppRoot.gd", "ResourcePaths.SCRIPT_APP_ROOT")

	# P8-2: AppRoot chrome API + PortStatusBar sea_mode
	var app_scr2 = load(ResourcePaths.SCRIPT_APP_ROOT)
	if app_scr2 != null and app_scr2 is Script:
		var app2: Node = (app_scr2 as Script).new()
		_assert_true(app2.has_method("refresh_chrome"), "AppRoot.refresh_chrome")
		_assert_true(app2.has_method("log_event"), "AppRoot.log_event")
		_assert_true(app2.has_method("get_status_bar"), "AppRoot.get_status_bar")
		app2.free()
	var status_scene: PackedScene = load(ResourcePaths.SCENE_PORT_STATUS_BAR) as PackedScene
	_assert_true(status_scene != null, "PortStatusBar scene 可加载 (chrome)")
	if status_scene != null:
		var bar = status_scene.instantiate()
		root.add_child(bar)
		_assert_true(bar.has_method("set_sea_mode"), "PortStatusBar.set_sea_mode")
		if bar.has_method("set_sea_mode"):
			bar.call("set_sea_mode", true)
			_assert_true(bool(bar.get("_sea_mode")), "PortStatusBar: sea_mode 开启")
			bar.call("set_sea_mode", false)
			_assert_true(not bool(bar.get("_sea_mode")), "PortStatusBar: sea_mode 关闭")
		bar.queue_free()
	print("")


func _first_choice_effects(scene_data: Dictionary) -> Dictionary:
	var choices: Array = scene_data.get("choices", [])
	if choices.is_empty():
		return {}
	var first_choice = choices[0]
	if not first_choice is Dictionary:
		return {}
	var choice: Dictionary = first_choice
	var effects = choice.get("effects", {})
	return effects if effects is Dictionary else {}

func _effects_set_story_flag(effects: Dictionary, flag: String) -> bool:
	for key in ["story_flag", "story_flag2"]:
		if not effects.has(key):
			continue
		var raw = effects[key]
		if raw is String and raw == flag:
			return true
		if raw is Dictionary and bool((raw as Dictionary).get(flag, false)):
			return true
	return false

# ── NK1-P6: ConditionEvaluator 测试 ───────────────────────

func _test_event_economy_integration() -> void:
	print("[Event-Economy Integration]")

	var market := MarketState.new()
	var mock_ports: Array = [
		{"id": "target", "production": {"g1": 1.0}, "demand": {}},
	]
	var mock_goods: Array = [{"id": "g1", "category": "货物", "base_value": 100}]
	market.init_from_ports(mock_ports, mock_goods)

	# 1. 灾难事件 → 繁荣度冲击 + 库存下降
	var disaster := MockDecayEvent.new("test_disaster", "target", 5, 2.5)
	disaster.activate(market)
	# MockDecayEvent.activate 无副作用，手动模拟
	market.apply_disaster_zero("target")
	market.apply_prosperity_shock("target", 0.15)
	_assert_lt(market.get_prosperity("target"), 1.0, "灾难后繁荣度 < 1.0")
	_assert_lt(float(market.get_stock("target", "g1")), float(market.get_base_stock("target", "g1")), "灾难后库存 < 基准")

	# 2. 恢复事件 → 繁荣度恢复 + 库存恢复
	market.apply_recovery_restore("target")
	market.apply_prosperity_boost("target", 0.08)
	_assert_gt(market.get_prosperity("target"), 0.7, "恢复后繁荣度 > 0.7（下限保护）")

	# 3. 贸易繁荣 → 繁荣度激增 + 后期饱和
	var boom := TradeBoomEvent.new("target", 8)
	boom.activate(market)
	_assert_gt(market.get_prosperity("target"), 1.0, "贸易繁荣后繁荣度 > 1.0")
	boom.on_expire(market)
	# on_expire 注入饱和
	var net_flow: int = market.trade_history["target"]["g1"]["net_flow"]
	_assert_gt(float(net_flow), 0.0, "繁荣结束后: 贸易历史注入净流入")
	var sat_mod: float = market.get_saturation_mod("target", "g1")
	_assert_lt(sat_mod, 1.0, "繁荣结束后: 饱和修正 < 1.0（价格受压）")

	# 4. 好感度 × 交易联动
	market.port_affinity["target"] = 10.0  # 高好感度
	var aff_mod_high: float = market.get_affinity_price_mod("target")
	market.port_affinity["target"] = -10.0  # 低好感度
	var aff_mod_low: float = market.get_affinity_price_mod("target")
	_assert_lt(aff_mod_high, aff_mod_low, "好感度联动: 高好感价格修正 < 低好感")

	# 5. 事件链偏置衰减（通过 EconomySystem 集成验证，不直接访问 autoload）
	# 使用 PriceEngine 验证所有修正因子叠加后仍稳定
	var all_mods_stable := true
	var chain_mod := PriceEngine.compute_supply_chain_mod(true, false, 3.0, 0.3)
	var pressure_mod := PriceEngine.compute_regional_pressure_mod(2.0)
	var combined := chain_mod * pressure_mod * sat_mod * aff_mod_high
	_assert_true(combined > 0.0, "所有修正因子叠加: 乘积 > 0")
	_assert_true(combined < 10.0, "所有修正因子叠加: 乘积 < 10（无极端膨胀）")

	# 6. 新事件 EconomyLog 工厂方法
	var shortage_notice := EconomyLog.make_shortage_notice("泉州", "福建瓷")
	_assert_true(shortage_notice.contains("供应短缺"), "工厂方法: 短缺通知")
	var boom_notice := EconomyLog.make_boom_notice("泉州")
	_assert_true(boom_notice.contains("繁荣"), "工厂方法: 繁荣通知")
	var ripple_notice := EconomyLog.make_ripple_notice("泉州")
	_assert_true(ripple_notice.contains("涟漪"), "工厂方法: 涟漪通知")

	print("")

# ── NK1-P6-POLISH: 常量提取后行为一致性验证 ─────────────────

func _test_polish_constants() -> void:
	print("[Polish Constants]")

	var combat_state = _load_script_or_fail("res://scripts/state/CombatState.gd", "CombatState 脚本可加载")
	var trade_state = _load_script_or_fail("res://scripts/state/TradeState.gd", "TradeState 脚本可加载")
	var bribe_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_BRIBE, "BribeHandler 脚本可加载")
	var buy_supplies_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES, "BuySuppliesHandler 脚本可加载")
	var hire_crew_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_HIRE_CREW, "HireCrewHandler 脚本可加载")
	var inspection_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_INSPECTION, "InspectionHandler 脚本可加载")
	_assert_true(combat_state != null, "CombatState 常量脚本可加载")
	_assert_true(trade_state != null, "TradeState 常量脚本可加载")
	_assert_true(bribe_handler != null, "BribeHandler 常量脚本可加载")
	_assert_true(buy_supplies_handler != null, "BuySuppliesHandler 常量脚本可加载")
	_assert_true(hire_crew_handler != null, "HireCrewHandler 常量脚本可加载")
	_assert_true(inspection_handler != null, "InspectionHandler 常量脚本可加载")
	if combat_state == null or trade_state == null or bribe_handler == null or buy_supplies_handler == null or hire_crew_handler == null or inspection_handler == null:
		print("")
		return

	# 1. CombatState 常量值与原硬编码一致
	_assert_eq(combat_state.BASE_CANNON_DAMAGE_PER_ARTILLERY, 8.0, "CombatState: 炮基础伤害 8.0")
	_assert_eq(combat_state.DODGE_PER_MANEUVER, 0.04, "CombatState: 闪避系数 0.04")
	_assert_eq(combat_state.SWORDPLAY_POWER_COEFF, 0.15, "CombatState: 剑术加成 0.15")
	_assert_eq(combat_state.DAMAGE_CREW_LOSS_RATIO, 0.05, "CombatState: 伤害→水手比例 0.05")
	_assert_eq(combat_state.MANEUVER_SUCCESS_THRESHOLD, 0.6, "CombatState: 机动成功阈值 0.6")
	_assert_eq(combat_state.MANEUVER_PARTIAL_THRESHOLD, 0.3, "CombatState: 机动部分阈值 0.3")
	_assert_eq(combat_state.MANEUVER_WIN_PLAYER_MULT, 1.5, "CombatState: 机动成功玩家倍率 1.5")
	_assert_eq(combat_state.FLEE_SUCCESS_THRESHOLD, 0.5, "CombatState: 撤退成功阈值 0.5")
	_assert_eq(combat_state.DUEL_ROUNDS, 3, "CombatState: 单挑回合 3")
	_assert_eq(combat_state.DUEL_WIN_THRESHOLD, 0.6, "CombatState: 单挑胜阈值 0.6")
	_assert_eq(combat_state.DEFAULT_ENEMY_DURABILITY, 80.0, "CombatState: 敌方默认耐久 80")
	_assert_eq(combat_state.DEFAULT_ENEMY_CREW, 40, "CombatState: 敌方默认船员 40")
	_assert_eq(combat_state.DEFAULT_ENEMY_ARTILLERY, 3, "CombatState: 敌方默认炮数 3")
	_assert_eq(combat_state.DEFAULT_ENEMY_SWORDPLAY, 2, "CombatState: 敌方默认剑术 2")
	_assert_eq(combat_state.DEFAULT_ENEMY_MANEUVER, 4, "CombatState: 敌方默认机动 4")

	# 2. TradeState 常量
	_assert_eq(trade_state.CUSTOMS_BLOCKED_ATTENTION, 15, "TradeState: 海关封锁阈值 15")
	_assert_eq(trade_state.CUSTOMS_FINE_MAX, 200, "TradeState: 海关罚款上限 200")
	_assert_eq(trade_state.CUSTOMS_BRIBE_AMOUNT, 50, "TradeState: 海关贿赂金额 50")
	_assert_eq(trade_state.CUSTOMS_BRIBE_ATTENTION_DELTA, 3, "TradeState: 海关贿赂关注度增量 3")

	# 3. SurvivalState 常量
	_assert_eq(SurvivalState.DEFAULT_FOOD, 30.0, "SurvivalState: 初始粮食 30")
	_assert_eq(SurvivalState.MAX_FOOD, 100.0, "SurvivalState: 粮食上限 100")
	_assert_eq(SurvivalState.MAX_CARGO, 200, "SurvivalState: 货舱上限 200")
	_assert_eq(SurvivalState.DAILY_CONSUME_DIVISOR, 10.0, "SurvivalState: 每日消耗除数 10")
	_assert_eq(SurvivalState.STARVATION_DEATH_RATIO, 0.1, "SurvivalState: 断粮死亡率 0.1")

	# 4. Handler 常量
	_assert_eq(bribe_handler.DEFAULT_BRIBE_AMOUNT, 50, "BribeHandler: 默认贿赂 50")
	_assert_eq(bribe_handler.DEFAULT_ATTENTION_DELTA, 3, "BribeHandler: 默认关注度增量 3")
	_assert_eq(bribe_handler.PU_ATTENTION_MAX, 20, "BribeHandler: 关注度上限 20")
	_assert_eq(buy_supplies_handler.SUPPLY_FILL_FLAT_COST, 20, "BuySuppliesHandler: 补满固定费用 20")
	_assert_eq(hire_crew_handler.DEFAULT_COST_PER_CREW, 10, "HireCrewHandler: 默认招募费用 10")
	_assert_eq(inspection_handler.ILLEGAL_TRADE_FINE, 30, "InspectionHandler: 走私罚款 30")

	# 5. PriceEngine 常量
	_assert_eq(PriceEngine.PRICE_FLOOR, 1, "PriceEngine: 价格下限 1")
	_assert_eq(PriceEngine.PRICE_CAP_MULT, 5, "PriceEngine: 价格上限倍率 5")
	_assert_eq(PriceEngine.SUPPLY_CHAIN_MOD_MIN, 0.7, "PriceEngine: 供应链修正下限 0.7")
	_assert_eq(PriceEngine.SUPPLY_CHAIN_MOD_MAX, 1.3, "PriceEngine: 供应链修正上限 1.3")
	_assert_eq(PriceEngine.REGIONAL_PRESSURE_MOD_MIN, 0.85, "PriceEngine: 区域压力下限 0.85")
	_assert_eq(PriceEngine.REGIONAL_PRESSURE_MOD_MAX, 1.15, "PriceEngine: 区域压力上限 1.15")

	# 6. 行为一致性验证：常量提取后价格计算结果不变
	var events_empty: Array[BaseEconomicEvent] = []
	var r1 = PriceEngine.calculate_price(100, 1.0, 1.0, 1.0, events_empty, "p", "g")
	_assert_eq(r1["final_price"], 100, "价格计算: base=100, 无修正 = 100")
	var r2 = PriceEngine.calculate_price(100, 10.0, 10.0, 10.0, events_empty, "p", "g")
	_assert_eq(r2["final_price"], 500, "价格计算: 超高倍率命中 cap = 500")
	var r3 = PriceEngine.calculate_price(100, 0.1, 0.2, 0.5, events_empty, "p", "g")
	_assert_eq(r3["final_price"], 1, "价格计算: 极端丰收保底 = 1")
	_assert_eq(SurvivalState.MAX_FOOD, 100.0, "SurvivalState: 上限一致")

	print("")

# ── NK1-P6-POLISH: GameLog 分类日志系统测试 ─────────────────

func _test_game_log() -> void:
	print("[GameLog]")

	var log := GameLog.new()

	# 初始为空
	_assert_eq(log.get_entries(GameLog.Category.ECONOMY).size(), 0, "初始: 经济分类为空")
	_assert_eq(log.get_entries(GameLog.Category.COMBAT).size(), 0, "初始: 战斗分类为空")
	_assert_eq(log.get_latest(GameLog.Category.VOYAGE), "", "初始: 航行最新为空")

	# info/warning/debug 三个级别
	log.info(GameLog.Category.ECONOMY, "test economy info")
	log.warning(GameLog.Category.COMBAT, "test combat warning")
	log.debug(GameLog.Category.EVENT, "test event debug")
	_assert_eq(log.get_entries(GameLog.Category.ECONOMY).size(), 1, "info: 经济1条")
	_assert_eq(log.get_entries(GameLog.Category.COMBAT).size(), 1, "warning: 战斗1条")
	_assert_eq(log.get_entries(GameLog.Category.EVENT).size(), 1, "debug: 事件1条")

	# 日志包含级别和分类前缀
	var latest: String = log.get_latest(GameLog.Category.ECONOMY)
	_assert_true(latest.contains("[INFO]") and latest.contains("经济"), "日志含级别和分类前缀")
	var latest_combat: String = log.get_latest(GameLog.Category.COMBAT)
	_assert_true(latest_combat.contains("[WARN]") and latest_combat.contains("战斗"), "警告日志含前缀")

	# add_entry 完整 API
	log.add_entry(GameLog.Category.VOYAGE, GameLog.Level.DEBUG, "航行debug")
	_assert_eq(log.get_entries(GameLog.Category.VOYAGE).size(), 1, "add_entry: 航行1条")
	_assert_true(log.get_latest(GameLog.Category.VOYAGE).contains("[DEBUG]"), "add_entry: DEBUG级别")

	# get_latest_all: 多分类最新
	log.info(GameLog.Category.SYSTEM, "系统通知")
	var all_latest: Array = log.get_latest_all()
	_assert_eq(all_latest.size(), 5, "get_latest_all: 5个分类各有1条")
	for entry in all_latest:
		_assert_true(entry.contains("【") and entry.contains("】"), "每条日志含分类名")

	# 容量限制：超过 20 条自动裁剪
	for i in range(25):
		log.info(GameLog.Category.ECONOMY, "entry %d" % i)
	_assert_true(log.get_entries(GameLog.Category.ECONOMY).size() <= 20, "容量限制: 经济 ≤20条")

	# get_entries 限制条数
	var last_5: Array = log.get_entries(GameLog.Category.ECONOMY, 5)
	_assert_eq(last_5.size(), 5, "get_entries(N): 返回 N 条")

	# clear_category
	log.clear_category(GameLog.Category.ECONOMY)
	_assert_eq(log.get_entries(GameLog.Category.ECONOMY).size(), 0, "clear_category: 经济清空")
	_assert_gt(log.get_entries(GameLog.Category.COMBAT).size(), 0, "clear_category: 不影响其他分类")

	# clear_all
	log.clear_all()
	_assert_eq(log.get_latest_all().size(), 0, "clear_all: 全部清空")

	# 序列化
	log.info(GameLog.Category.ECONOMY, "serialization test")
	var d: Dictionary = log.to_dict()
	var log2: GameLog = GameLog.new()
	log2.from_dict(d)
	_assert_eq(log2.get_latest(GameLog.Category.ECONOMY), log.get_latest(GameLog.Category.ECONOMY), "序列化往返一致")

	# 枚举值
	_assert_eq(GameLog.Level.INFO, 0, "Level.INFO = 0")
	_assert_eq(GameLog.Level.WARNING, 1, "Level.WARNING = 1")
	_assert_eq(GameLog.Level.DEBUG, 2, "Level.DEBUG = 2")
	_assert_eq(GameLog.Category.ECONOMY, 0, "Category.ECONOMY = 0")
	_assert_eq(GameLog.Category.VOYAGE, 3, "Category.VOYAGE = 3")
	_assert_eq(GameLog.Category.SYSTEM, 4, "Category.SYSTEM = 4")

	print("")

# ── NK1-P6-POLISH-002: EventConfigLoader 测试 ───────────────

func _test_event_config() -> void:
	print("[Event Config]")

	# 清空缓存确保干净状态
	EventConfigLoader.clear_cache()

	# 1. 加载配置
	var cfg: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
	_assert_true(not cfg.is_empty(), "pirate_attack 配置非空")
	_assert_eq(float(cfg["base_weight"]), 0.8, "pirate_attack: base_weight=0.8")
	_assert_eq(int(cfg["cooldown_days"]), 30, "pirate_attack: cooldown_days=30")
	_assert_eq(float(cfg["peak_local_mod"]), 1.5, "pirate_attack: peak_local_mod=1.5")
	_assert_eq(float(cfg["peak_neighbor_mod"]), 1.15, "pirate_attack: peak_neighbor_mod=1.15")
	_assert_eq(float(cfg["activate_prosperity_shock"]), 0.10, "pirate_attack: activate_prosperity_shock=0.10")
	_assert_eq(float(cfg["expire_prosperity_boost"]), 0.05, "pirate_attack: expire_prosperity_boost=0.05")
	_assert_eq(float(cfg["expire_chain_bias"]["trade_recovery"]), 2.0, "pirate_attack: chain_bias=2.0")

	# 2. trade_disaster 配置
	var cfg_d: Dictionary = EventConfigLoader.get_event_config("trade_disaster")
	_assert_eq(float(cfg_d["base_weight"]), 1.0, "trade_disaster: base_weight=1.0")
	_assert_eq(int(cfg_d["cooldown_days"]), 25, "trade_disaster: cooldown_days=25")
	_assert_eq(float(cfg_d["peak_local_mod"]), 2.5, "trade_disaster: peak_local_mod=2.5")
	_assert_eq(float(cfg_d["expire_partial_recovery"]), 0.8, "trade_disaster: expire_partial_recovery=0.8")
	_assert_eq(float(cfg_d["expire_prosperity_boost"]), 0.08, "trade_disaster: expire_prosperity_boost=0.08")
	_assert_eq(float(cfg_d["expire_chain_bias"]["trade_recovery"]), 3.0, "trade_disaster: chain_bias=3.0")

	# 3. trade_recovery 配置
	var cfg_r: Dictionary = EventConfigLoader.get_event_config("trade_recovery")
	_assert_eq(float(cfg_r["base_weight"]), 1.1, "trade_recovery: base_weight=1.1")
	_assert_eq(int(cfg_r["cooldown_days"]), 15, "trade_recovery: cooldown_days=15")
	_assert_eq(float(cfg_r["peak_local_mod"]), 0.8, "trade_recovery: peak_local_mod=0.8")
	_assert_eq(float(cfg_r["activate_prosperity_boost"]), 0.05, "trade_recovery: activate_prosperity_boost=0.05")
	_assert_eq(float(cfg_r["expire_prosperity_boost"]), 0.02, "trade_recovery: expire_prosperity_boost=0.02")

	# 4. 其他事件配置（验证所有 6 个事件都有配置）
	_assert_true(not EventConfigLoader.get_event_config("supply_shortage").is_empty(), "supply_shortage 配置非空")
	_assert_true(not EventConfigLoader.get_event_config("trade_boom").is_empty(), "trade_boom 配置非空")
	_assert_true(not EventConfigLoader.get_event_config("economic_ripple").is_empty(), "economic_ripple 配置非空")

	# 5. 初始持续时间
	_assert_eq(EventConfigLoader.get_initial_duration("trade_disaster", 99), 10, "trade_disaster initial_duration=10")
	_assert_eq(EventConfigLoader.get_initial_duration("pirate_attack", 99), 5, "pirate_attack initial_duration=5")
	_assert_eq(EventConfigLoader.get_initial_duration("nonexistent_event", 42), 42, "不存在事件: 返回 fallback=42")

	# 6. 生成器配置
	var gen: Dictionary = EventConfigLoader.get_generator_config()
	_assert_eq(float(gen["daily_event_chance"]), 0.08, "generator: daily_event_chance=0.08")
	_assert_eq(int(gen["rumor_delay_min"]), 5, "generator: rumor_delay_min=5")
	_assert_eq(int(gen["rumor_delay_max"]), 15, "generator: rumor_delay_max=15")
	_assert_eq(float(gen["safety_valve_threshold"]), 0.3, "generator: safety_valve_threshold=0.3")
	_assert_eq(int(gen["intel_tier_costs"][0]), 20, "generator: intel_tier_costs[0]=20")
	_assert_eq(int(gen["intel_tier_costs"][1]), 50, "generator: intel_tier_costs[1]=50")
	_assert_eq(int(gen["intel_tier_costs"][2]), 120, "generator: intel_tier_costs[2]=120")

	# 7. 行为验证：事件实例使用配置
	EventConfigLoader.clear_cache()
	var pirate := PirateAttackEvent.new("quanzhou", 5)
	_assert_eq(pirate.base_weight, 0.8, "PirateAttackEvent 从配置加载 base_weight=0.8")
	_assert_eq(pirate.cooldown_days, 30, "PirateAttackEvent 从配置加载 cooldown_days=30")
	_assert_eq(pirate.max_triggers, -1, "PirateAttackEvent 从配置加载 max_triggers=-1")

	var disaster := TradeDisasterEvent.new("quanzhou", 10)
	_assert_eq(disaster.base_weight, 1.0, "TradeDisasterEvent 从配置加载 base_weight=1.0")
	_assert_eq(disaster.cooldown_days, 25, "TradeDisasterEvent 从配置加载 cooldown_days=25")

	var recovery := TradeRecoveryEvent.new("quanzhou", 10)
	_assert_eq(recovery.base_weight, 1.1, "TradeRecoveryEvent 从配置加载 base_weight=1.1")
	_assert_eq(recovery.cooldown_days, 15, "TradeRecoveryEvent 从配置加载 cooldown_days=15")

	# 8. 缓存机制
	EventConfigLoader.clear_cache()
	var cfg1: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
	var cfg2: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
	_assert_true(cfg1 == cfg2, "缓存: 两次获取返回相同 dict")

	# 9. JSON 文件存在性
	_assert_true(FileAccess.file_exists(EventConfigLoader._CONFIG_PATH), "events_config.json 文件存在")

	# 10. 配置版本
	var data: Dictionary = EventConfigLoader._load()
	_assert_eq(int(data["version"]), 1, "events_config.json version=1")

	print("")

# ── NK1-P6-POLISH-003: IntentTypes 常量类测试 ───────────────

func _test_intent_types() -> void:
	print("[IntentTypes]")

	# 所有交易类
	_assert_eq(IntentTypes.PAYMENT, "payment", "IntentTypes.PAYMENT")
	_assert_eq(IntentTypes.TRADE_REQUEST, "trade_request", "IntentTypes.TRADE_REQUEST")
	_assert_eq(IntentTypes.MARKET_BUY, "market_buy", "IntentTypes.MARKET_BUY")
	_assert_eq(IntentTypes.MARKET_SELL, "market_sell", "IntentTypes.MARKET_SELL")

	# 经济活动类
	_assert_eq(IntentTypes.BRIBE, "bribe", "IntentTypes.BRIBE")
	_assert_eq(IntentTypes.REPAIR_SHIP, "repair_ship", "IntentTypes.REPAIR_SHIP")
	_assert_eq(IntentTypes.REFIT_SHIP, "refit_ship", "IntentTypes.REFIT_SHIP")
	_assert_eq(IntentTypes.HIRE_CREW, "hire_crew", "IntentTypes.HIRE_CREW")
	_assert_eq(IntentTypes.BUY_SUPPLIES, "buy_supplies", "IntentTypes.BUY_SUPPLIES")
	_assert_eq(IntentTypes.BUY_INTEL, "buy_intel", "IntentTypes.BUY_INTEL")
	_assert_eq(IntentTypes.INVEST_PORT, "invest_port", "IntentTypes.INVEST_PORT")
	_assert_eq(IntentTypes.GIFT_NPC, "gift_npc", "IntentTypes.GIFT_NPC")
	_assert_eq(IntentTypes.STUDY_SKILL, "study_skill", "IntentTypes.STUDY_SKILL")

	# 战斗/海战类
	_assert_eq(IntentTypes.COMBAT_REQUEST, "combat_request", "IntentTypes.COMBAT_REQUEST")
	_assert_eq(IntentTypes.INSPECTION_PASS, "inspection_pass", "IntentTypes.INSPECTION_PASS")
	_assert_eq(IntentTypes.ESCAPE_ATTEMPT, "escape_attempt", "IntentTypes.ESCAPE_ATTEMPT")

	# 系统/默认
	_assert_eq(IntentTypes.IGNORE, "ignore", "IntentTypes.IGNORE")

	# is_known 验证
	_assert_true(IntentTypes.is_known("payment"), "is_known: payment")
	_assert_true(IntentTypes.is_known("bribe"), "is_known: bribe")
	_assert_true(IntentTypes.is_known("combat_request"), "is_known: combat_request")
	_assert_true(IntentTypes.is_known("ignore"), "is_known: ignore")
	_assert_true(IntentTypes.is_known("invest_port"), "is_known: invest_port")
	_assert_true(IntentTypes.is_known("gift_npc"), "is_known: gift_npc")
	_assert_true(IntentTypes.is_known("study_skill"), "is_known: study_skill")
	_assert_true(not IntentTypes.is_known("unknown_type"), "is_known: unknown_type 不存在")
	_assert_true(not IntentTypes.is_known(""), "is_known: 空字符串不存在")

	# all_types 返回 17 个
	var all_types: Array = IntentTypes.all_types()
	_assert_eq(all_types.size(), 17, "IntentTypes.all_types: 共 17 个类型")

	print("")

# ── NK1-P6-POLISH-003: 全事件配置验证 ─────────────────────

func _test_all_event_config() -> void:
	print("[All Event Config]")

	# 验证所有 6 个事件从配置加载
	EventConfigLoader.clear_cache()
	var event_ids: Array[String] = [
		"pirate_attack", "trade_disaster", "trade_recovery",
		"supply_shortage", "trade_boom", "economic_ripple"
	]

	for eid in event_ids:
		var cfg: Dictionary = EventConfigLoader.get_event_config(eid)
		_assert_true(not cfg.is_empty(), "%s: 配置非空" % eid)
		_assert_true(cfg.has("base_weight"), "%s: 有 base_weight" % eid)
		_assert_true(cfg.has("cooldown_days"), "%s: 有 cooldown_days" % eid)
		_assert_true(cfg.has("initial_duration"), "%s: 有 initial_duration" % eid)

	# 验证初始持续时间
	_assert_eq(EventConfigLoader.get_initial_duration("supply_shortage", 99), 8, "supply_shortage initial_duration=8")
	_assert_eq(EventConfigLoader.get_initial_duration("trade_boom", 99), 12, "trade_boom initial_duration=12")
	_assert_eq(EventConfigLoader.get_initial_duration("economic_ripple", 99), 8, "economic_ripple initial_duration=8")

	# 验证事件实例化使用配置
	EventConfigLoader.clear_cache()
	var ss := SupplyShortageEvent.new("quanzhou", 8)
	_assert_eq(ss.base_weight, 0.7, "SupplyShortageEvent: base_weight=0.7")
	_assert_eq(ss.cooldown_days, 35, "SupplyShortageEvent: cooldown_days=35")

	var tb := TradeBoomEvent.new("quanzhou", 12)
	_assert_eq(tb.base_weight, 0.6, "TradeBoomEvent: base_weight=0.6")
	_assert_eq(tb.cooldown_days, 40, "TradeBoomEvent: cooldown_days=40")

	var er := EconomicRippleEvent.new("quanzhou", 8)
	_assert_eq(er.base_weight, 0.5, "EconomicRippleEvent: base_weight=0.5")
	_assert_eq(er.cooldown_days, 50, "EconomicRippleEvent: cooldown_days=50")

	# 验证 supply_shortage 的 JSON 配置细节
	EventConfigLoader.clear_cache()
	var ss_cfg: Dictionary = EventConfigLoader.get_event_config("supply_shortage")
	_assert_eq(float(ss_cfg["peak_local_mod"]), 2.0, "supply_shortage: peak_local_mod=2.0")
	_assert_eq(float(ss_cfg["peak_regional_mod"]), 1.4, "supply_shortage: peak_regional_mod=1.4")
	_assert_eq(float(ss_cfg["shortage_ratio"]), 0.25, "supply_shortage: shortage_ratio=0.25")
	_assert_eq(float(ss_cfg["regional_shortage_multiplier"]), 1.8, "supply_shortage: regional_shortage_multiplier=1.8")
	_assert_eq(float(ss_cfg["expire_partial_recovery"]), 0.7, "supply_shortage: expire_partial_recovery=0.7")
	_assert_eq(float(ss_cfg["expire_chain_bias"]["trade_recovery"]), 2.0, "supply_shortage: chain_bias=2.0")

	# 验证 trade_boom 配置细节
	var tb_cfg: Dictionary = EventConfigLoader.get_event_config("trade_boom")
	_assert_eq(float(tb_cfg["peak_local_mod"]), 0.85, "trade_boom: peak_local_mod=0.85")
	_assert_eq(float(tb_cfg["boom_prosperity_gain"]), 0.12, "trade_boom: boom_prosperity_gain=0.12")
	_assert_eq(float(tb_cfg["boom_stock_replenish"]), 1.3, "trade_boom: boom_stock_replenish=1.3")
	_assert_eq(int(tb_cfg["post_boom_saturation"]), 300, "trade_boom: post_boom_saturation=300")
	_assert_eq(float(tb_cfg["regional_prosperity_gain_factor"]), 0.5, "trade_boom: regional_factor=0.5")

	# 验证 economic_ripple 配置细节
	var er_cfg: Dictionary = EventConfigLoader.get_event_config("economic_ripple")
	_assert_eq(float(er_cfg["peak_local_mod"]), 1.8, "economic_ripple: peak_local_mod=1.8")
	_assert_eq(float(er_cfg["ripple_stock_cut"]), 0.3, "economic_ripple: ripple_stock_cut=0.3")
	_assert_eq(float(er_cfg["ripple_regional_cut"]), 0.6, "economic_ripple: ripple_regional_cut=0.6")
	_assert_eq(float(er_cfg["expire_partial_recovery"]), 0.75, "economic_ripple: expire_partial_recovery=0.75")
	_assert_eq(float(er_cfg["expire_regional_partial_recovery"]), 0.9, "economic_ripple: expire_regional=0.9")

	print("")





# ═══════════════════════════════════════════════════════════

class MockPriceEvent extends BaseEconomicEvent:
	var _modifier: float

	func _init(id: String, port: String, days: int, mod: float) -> void:
		super(id, port, days)
		self._modifier = mod

	func get_price_modifier(port_id: String, good_id: String) -> float:
		return _modifier

	func on_expire(_market = null) -> void:
		pass

# Mock 衰减事件 — 测试梯度衰减 + 持续性逻辑（不依赖 autoload）
class MockDecayEvent extends BaseEconomicEvent:
	var _peak_mod: float

	func _init(id: String, port: String, days: int, peak_mod: float) -> void:
		super(id, port, days)
		_peak_mod = peak_mod

	func get_price_modifier(port_id: String, good_id: String) -> float:
		if port_id != target_port:
			return 1.0
		return lerp(1.0, _peak_mod, get_decay_factor())

	func on_expire(_market = null) -> void:
		pass
