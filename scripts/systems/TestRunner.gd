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
	_run_controller_tests()
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
	var controller_tests_script = _load_script_or_fail("res://scripts/systems/TestRunnerController.gd", "TestRunnerController script loads", false)
	if controller_tests_script == null:
		return
	var controller_tests = controller_tests_script.new(self)
	if controller_tests == null or not controller_tests.has_method("run"):
		_fail("TestRunnerController: run() callable")
		return
	controller_tests.run()

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
	_assert_true(bool(refuse_effects.get("career_promote", false)), "Chapter3: 忠义收束触发 career_promote")
	_assert_true(int(refuse_effects.get("linboyuan_relationship", 0)) >= 50, "Chapter3: 忠义收束满足 loyalty_ending 关系条件")
	_assert_true(bool(burn_effects.get("career_promote", false)), "Chapter3: 远航收束触发 career_promote")
	_assert_true(_effects_set_story_flag(burn_effects, "overseas_voyage"), "Chapter3: 远航收束写入 overseas_voyage")

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
