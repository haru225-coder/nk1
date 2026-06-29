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
	_test_event_economy_integration()
	_test_polish_constants()
	_test_game_log()
	_test_ui_theme_constants()
	_test_resource_paths()
	_test_event_config()
	_test_ui_builder()
	_test_game_colors()
	_test_intent_types()
	_test_all_event_config()
	_test_asset_placeholder_json()
	_test_text_keys()
	_test_floating_text_config()
	_test_cutscene_player()
	_test_ship_system()
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

# ── NK1-P5-ECON-003: 事件与经济系统集成测试 ───────────────

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

	# 1. CombatState 常量值与原硬编码一致
	_assert_eq(CombatState.BASE_CANNON_DAMAGE_PER_ARTILLERY, 8.0, "CombatState: 炮基础伤害 8.0")
	_assert_eq(CombatState.DODGE_PER_MANEUVER, 0.04, "CombatState: 闪避系数 0.04")
	_assert_eq(CombatState.SWORDPLAY_POWER_COEFF, 0.15, "CombatState: 剑术加成 0.15")
	_assert_eq(CombatState.DAMAGE_CREW_LOSS_RATIO, 0.05, "CombatState: 伤害→水手比例 0.05")
	_assert_eq(CombatState.MANEUVER_SUCCESS_THRESHOLD, 0.6, "CombatState: 机动成功阈值 0.6")
	_assert_eq(CombatState.MANEUVER_PARTIAL_THRESHOLD, 0.3, "CombatState: 机动部分阈值 0.3")
	_assert_eq(CombatState.MANEUVER_WIN_PLAYER_MULT, 1.5, "CombatState: 机动成功玩家倍率 1.5")
	_assert_eq(CombatState.FLEE_SUCCESS_THRESHOLD, 0.5, "CombatState: 撤退成功阈值 0.5")
	_assert_eq(CombatState.DUEL_ROUNDS, 3, "CombatState: 单挑回合 3")
	_assert_eq(CombatState.DUEL_WIN_THRESHOLD, 0.6, "CombatState: 单挑胜阈值 0.6")
	_assert_eq(CombatState.DEFAULT_ENEMY_DURABILITY, 80.0, "CombatState: 敌方默认耐久 80")
	_assert_eq(CombatState.DEFAULT_ENEMY_CREW, 40, "CombatState: 敌方默认船员 40")
	_assert_eq(CombatState.DEFAULT_ENEMY_ARTILLERY, 3, "CombatState: 敌方默认炮数 3")
	_assert_eq(CombatState.DEFAULT_ENEMY_SWORDPLAY, 2, "CombatState: 敌方默认剑术 2")
	_assert_eq(CombatState.DEFAULT_ENEMY_MANEUVER, 4, "CombatState: 敌方默认机动 4")

	# 2. TradeState 常量
	_assert_eq(TradeState.CUSTOMS_BLOCKED_ATTENTION, 15, "TradeState: 海关封锁阈值 15")
	_assert_eq(TradeState.CUSTOMS_FINE_MAX, 200, "TradeState: 海关罚款上限 200")
	_assert_eq(TradeState.CUSTOMS_BRIBE_AMOUNT, 50, "TradeState: 海关贿赂金额 50")
	_assert_eq(TradeState.CUSTOMS_BRIBE_ATTENTION_DELTA, 3, "TradeState: 海关贿赂关注度增量 3")

	# 3. SurvivalState 常量
	_assert_eq(SurvivalState.DEFAULT_FOOD, 30.0, "SurvivalState: 初始粮食 30")
	_assert_eq(SurvivalState.MAX_FOOD, 100.0, "SurvivalState: 粮食上限 100")
	_assert_eq(SurvivalState.MAX_CARGO, 200, "SurvivalState: 货舱上限 200")
	_assert_eq(SurvivalState.DAILY_CONSUME_DIVISOR, 10.0, "SurvivalState: 每日消耗除数 10")
	_assert_eq(SurvivalState.STARVATION_DEATH_RATIO, 0.1, "SurvivalState: 断粮死亡率 0.1")

	# 4. Handler 常量
	_assert_eq(BribeHandler.DEFAULT_BRIBE_AMOUNT, 50, "BribeHandler: 默认贿赂 50")
	_assert_eq(BribeHandler.DEFAULT_ATTENTION_DELTA, 3, "BribeHandler: 默认关注度增量 3")
	_assert_eq(BribeHandler.PU_ATTENTION_MAX, 20, "BribeHandler: 关注度上限 20")
	_assert_eq(BuySuppliesHandler.SUPPLY_FILL_FLAT_COST, 20, "BuySuppliesHandler: 补满固定费用 20")
	_assert_eq(HireCrewHandler.DEFAULT_COST_PER_CREW, 10, "HireCrewHandler: 默认招募费用 10")
	_assert_eq(InspectionHandler.ILLEGAL_TRADE_FINE, 30, "InspectionHandler: 走私罚款 30")

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

# ── NK1-P6-POLISH-002: UITheme 常量类测试 ─────────────────

func _test_ui_theme_constants() -> void:
	print("[UITheme Constants]")

	# 按钮常量
	_assert_eq(UITheme.BTN_ACTION, "ActionButton", "UITheme.BTN_ACTION")
	_assert_eq(UITheme.BTN_CHOICE, "ChoiceButton", "UITheme.BTN_CHOICE")
	_assert_eq(UITheme.BTN_SET_SAIL, "SetSailButton", "UITheme.BTN_SET_SAIL")
	_assert_eq(UITheme.BTN_TITLE_MENU, "TitleMenuButton", "UITheme.BTN_TITLE_MENU")
	_assert_eq(UITheme.BTN_NPC, "NPCButton", "UITheme.BTN_NPC")

	# 市集常量
	_assert_eq(UITheme.MARKET_SHELL, "MarketShell", "UITheme.MARKET_SHELL")
	_assert_eq(UITheme.MARKET_TITLE, "MarketTitle", "UITheme.MARKET_TITLE")
	_assert_eq(UITheme.MARKET_ALERT, "MarketAlert", "UITheme.MARKET_ALERT")
	_assert_eq(UITheme.MARKET_PANEL, "MarketPanel", "UITheme.MARKET_PANEL")
	_assert_eq(UITheme.MARKET_PREVIEW, "MarketPreview", "UITheme.MARKET_PREVIEW")

	# 设施卡片常量
	_assert_eq(UITheme.CARD_FACILITY, "PortFacilityCard", "UITheme.CARD_FACILITY")
	_assert_eq(UITheme.CARD_FACILITY_QUEST, "PortFacilityCardQuest", "UITheme.CARD_FACILITY_QUEST")
	_assert_eq(UITheme.TITLE_FACILITY, "FacilityTitle", "UITheme.TITLE_FACILITY")
	_assert_eq(UITheme.SUBTITLE_FACILITY, "FacilitySubtitle", "UITheme.SUBTITLE_FACILITY")

	# 事件/对话常量
	_assert_eq(UITheme.TITLE_EVENT, "EventTitle", "UITheme.TITLE_EVENT")
	_assert_eq(UITheme.BODY_EVENT, "EventBody", "UITheme.BODY_EVENT")
	_assert_eq(UITheme.PANEL_DIALOGUE_INNER, "DialoguePanelInner", "UITheme.PANEL_DIALOGUE_INNER")
	_assert_eq(UITheme.TEXT_DIALOGUE_NARRATION, "DialogueNarrationText", "UITheme.TEXT_DIALOGUE_NARRATION")
	_assert_eq(UITheme.TEXT_DIALOGUE_SPEECH, "DialogueSpeechText", "UITheme.TEXT_DIALOGUE_SPEECH")

	# assert_all_known 验证
	_assert_true(UITheme.assert_all_known("ActionButton"), "assert_all_known: ActionButton")
	_assert_true(UITheme.assert_all_known("SetSailButton"), "assert_all_known: SetSailButton")
	_assert_true(not UITheme.assert_all_known("FakeTheme"), "assert_all_known: FakeTheme 不存在")
	_assert_true(not UITheme.assert_all_known(""), "assert_all_known: 空字符串不存在")

	# 总数验证（28 个唯一常量）
	var known_count := 0
	var all_themes := [
		UITheme.BTN_ACTION, UITheme.BTN_CHOICE, UITheme.BTN_SET_SAIL, UITheme.BTN_TITLE_MENU, UITheme.BTN_NPC,
		UITheme.MARKET_SHELL, UITheme.MARKET_TITLE, UITheme.MARKET_ALERT, UITheme.MARKET_PANEL, UITheme.MARKET_PREVIEW,
		UITheme.CARD_FACILITY, UITheme.CARD_FACILITY_QUEST, UITheme.TITLE_FACILITY, UITheme.SUBTITLE_FACILITY,
		UITheme.BTN_FACILITY_CARD, UITheme.BADGE_FACILITY_QUEST, UITheme.FRAME_FACILITY_ICON,
		UITheme.CHIP_PORT_STAT, UITheme.LABEL_PORT_STAT, UITheme.VALUE_PORT_STAT,
		UITheme.SECTION_LABEL, UITheme.TITLE_EVENT, UITheme.BODY_EVENT, UITheme.PANEL_DIALOGUE_INNER,
		UITheme.TEXT_DIALOGUE_NARRATION, UITheme.TEXT_DIALOGUE_SPEECH, UITheme.TEXT_TITLE_SUB,
		UITheme.LABEL_SEA_HUD_FLEET,
	]
	for t in all_themes:
		if UITheme.assert_all_known(t):
			known_count += 1
	_assert_eq(known_count, 28, "UITheme: 共 28 个唯一常量")

	print("")

# ── NK1-P6-POLISH-002: ResourcePaths 常量类测试 ─────────────

func _test_resource_paths() -> void:
	print("[ResourcePaths]")

	# 主题与样式
	_assert_eq(ResourcePaths.THEME_MAIN, "res://assets/main_theme.tres", "ResourcePaths.THEME_MAIN")
	_assert_eq(ResourcePaths.FRAME_KOEI, "res://assets/ui_frame_koei.png", "ResourcePaths.FRAME_KOEI")
	_assert_eq(ResourcePaths.GRADIENT_SHADER, "res://assets/ui_bottom_gradient.gdshader", "ResourcePaths.GRADIENT_SHADER")

	# 纹理
	_assert_eq(ResourcePaths.TEX_SHIP_TOPDOWN, "res://assets/ship_topdown.png", "ResourcePaths.TEX_SHIP_TOPDOWN")
	_assert_eq(ResourcePaths.TEX_SEAGULL, "res://assets/seagull.png", "ResourcePaths.TEX_SEAGULL")
	_assert_eq(ResourcePaths.TEX_WHALE_SHADOW, "res://assets/whale_shadow.png", "ResourcePaths.TEX_WHALE_SHADOW")
	_assert_eq(ResourcePaths.TEX_ICON_MARKET, "res://assets/icon_market_koei.png", "ResourcePaths.TEX_ICON_MARKET")
	_assert_eq(ResourcePaths.BG_DEFAULT, "res://assets/bg_sea_route_koei.png", "ResourcePaths.BG_DEFAULT")

	# 场景
	_assert_eq(ResourcePaths.SCENE_MAIN, "res://scenes/Main.tscn", "ResourcePaths.SCENE_MAIN")
	_assert_eq(ResourcePaths.SCENE_WORLD_MAP, "res://scenes/WorldMap.tscn", "ResourcePaths.SCENE_WORLD_MAP")
	_assert_eq(ResourcePaths.SCENE_FLOATING_TEXT, "res://scenes/FloatingText.tscn", "ResourcePaths.SCENE_FLOATING_TEXT")
	_assert_eq(ResourcePaths.SCENE_CRATE, "res://scenes/Crate.tscn", "ResourcePaths.SCENE_CRATE")
	_assert_eq(ResourcePaths.SCENE_PORT_ZONE, "res://scenes/PortZone.tscn", "ResourcePaths.SCENE_PORT_ZONE")
	_assert_eq(ResourcePaths.SCENE_MAP_FLEET, "res://scenes/MapFleetNode.tscn", "ResourcePaths.SCENE_MAP_FLEET")
	_assert_eq(ResourcePaths.SCENE_COMMAND_BAR, "res://scenes/CommandBar.tscn", "ResourcePaths.SCENE_COMMAND_BAR")
	_assert_eq(ResourcePaths.SCENE_TOWN_MAP_HOTSPOT, "res://scenes/TownMapHotspot.tscn", "ResourcePaths.SCENE_TOWN_MAP_HOTSPOT")
	_assert_eq(ResourcePaths.SCENE_PORT_STATUS_BAR, "res://scenes/PortStatusBar.tscn", "ResourcePaths.SCENE_PORT_STATUS_BAR")

	# 事件脚本
	_assert_eq(ResourcePaths.SCRIPT_PIRATE_ATTACK, "res://scripts/events/PirateAttackEvent.gd", "ResourcePaths.SCRIPT_PIRATE_ATTACK")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_DISASTER, "res://scripts/events/TradeDisasterEvent.gd", "ResourcePaths.SCRIPT_TRADE_DISASTER")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_RECOVERY, "res://scripts/events/TradeRecoveryEvent.gd", "ResourcePaths.SCRIPT_TRADE_RECOVERY")
	_assert_eq(ResourcePaths.SCRIPT_SUPPLY_SHORTAGE, "res://scripts/events/SupplyShortageEvent.gd", "ResourcePaths.SCRIPT_SUPPLY_SHORTAGE")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_BOOM, "res://scripts/events/TradeBoomEvent.gd", "ResourcePaths.SCRIPT_TRADE_BOOM")
	_assert_eq(ResourcePaths.SCRIPT_ECONOMIC_RIPPLE, "res://scripts/events/EconomicRippleEvent.gd", "ResourcePaths.SCRIPT_ECONOMIC_RIPPLE")

	# Handler 脚本
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_PAYMENT, "res://scripts/systems/handlers/PaymentHandler.gd", "ResourcePaths.SCRIPT_HANDLER_PAYMENT")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_REPAIR, "res://scripts/systems/handlers/RepairHandler.gd", "ResourcePaths.SCRIPT_HANDLER_REPAIR")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES, "res://scripts/systems/handlers/BuySuppliesHandler.gd", "ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_BUY_INTEL, "res://scripts/systems/handlers/BuyIntelHandler.gd", "ResourcePaths.SCRIPT_HANDLER_BUY_INTEL")

	# 资源目录
	_assert_eq(ResourcePaths.DIR_ASSETS, "res://assets/", "ResourcePaths.DIR_ASSETS")
	_assert_eq(ResourcePaths.DIR_PORTRAITS, "res://assets/portraits/", "ResourcePaths.DIR_PORTRAITS")
	_assert_eq(ResourcePaths.DIR_ICONS_STAT, "res://assets/icons_stat/", "ResourcePaths.DIR_ICONS_STAT")

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

# ── NK1-P6-POLISH-002: UIBuilder 测试 ──────────────────────

func _test_ui_builder() -> void:
	print("[UIBuilder]")

	# 按钮创建
	var btn := UIBuilder.make_action_button("测试按钮")
	_assert_true(btn is Button, "make_action_button 返回 Button")
	_assert_eq(btn.text, "测试按钮", "按钮文本正确")
	_assert_eq(btn.theme_type_variation, UITheme.BTN_ACTION, "按钮主题 = BTN_ACTION")
	_assert_eq(int(btn.custom_minimum_size.y), 52, "操作按钮高度=52")

	var choice_btn := UIBuilder.make_choice_button("选择")
	_assert_eq(choice_btn.theme_type_variation, UITheme.BTN_CHOICE, "选择按钮主题 = BTN_CHOICE")
	_assert_eq(int(choice_btn.custom_minimum_size.y), 40, "选择按钮高度=40")

	var sail_btn := UIBuilder.make_set_sail_button("升帆")
	_assert_eq(sail_btn.theme_type_variation, UITheme.BTN_SET_SAIL, "升帆按钮主题 = BTN_SET_SAIL")
	_assert_eq(int(sail_btn.custom_minimum_size.y), 60, "升帆按钮高度=60")

	# 标签创建
	var lbl := UIBuilder.make_market_preview("预览文本")
	_assert_true(lbl is Label, "make_market_preview 返回 Label")
	_assert_eq(lbl.text, "预览文本", "标签文本正确")
	_assert_eq(lbl.theme_type_variation, UITheme.MARKET_PREVIEW, "标签主题 = MARKET_PREVIEW")
	_assert_eq(lbl.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "市场预览居中对齐")

	var alert_lbl := UIBuilder.make_market_alert("告警")
	_assert_eq(alert_lbl.theme_type_variation, UITheme.MARKET_ALERT, "告警标签主题 = MARKET_ALERT")

	var title_lbl := UIBuilder.make_market_title("市集")
	_assert_eq(title_lbl.theme_type_variation, UITheme.MARKET_TITLE, "市集标题主题 = MARKET_TITLE")

	# 面板创建
	var panel := UIBuilder.make_market_panel()
	_assert_true(panel is PanelContainer, "make_market_panel 返回 PanelContainer")
	_assert_eq(panel.theme_type_variation, UITheme.MARKET_PANEL, "市集面板主题 = MARKET_PANEL")

	var shell := UIBuilder.make_market_shell()
	_assert_eq(shell.theme_type_variation, UITheme.MARKET_SHELL, "市集外壳主题 = MARKET_SHELL")

	var card := UIBuilder.make_facility_card(false)
	_assert_eq(card.theme_type_variation, UITheme.CARD_FACILITY, "普通设施卡主题")

	var quest_card := UIBuilder.make_facility_card(true)
	_assert_eq(quest_card.theme_type_variation, UITheme.CARD_FACILITY_QUEST, "任务设施卡主题")

	# 港状态栏芯片
	var chip := UIBuilder.make_port_stat_chip("铜钱", "1000")
	_assert_true(chip is PanelContainer, "make_port_stat_chip 返回 PanelContainer")
	_assert_eq(chip.theme_type_variation, UITheme.CHIP_PORT_STAT, "港状态栏芯片背景主题")
	# 芯片内部应有 2 个标签（标题+值）
	_assert_eq(chip.get_child_count(), 1, "芯片含 1 个 VBox 子节点")
	var vbox = chip.get_child(0)
	_assert_eq(vbox.get_child_count(), 2, "VBox 含 2 个标签")
	_assert_true(vbox.get_child(0) is Label, "子节点 0 是 Label（标题）")
	_assert_true(vbox.get_child(1) is Label, "子节点 1 是 Label（值）")

	# RichText 创建
	var rtl := UIBuilder.make_rich_text("富文本", UITheme.MARKET_PREVIEW, true)
	_assert_true(rtl is RichTextLabel, "make_rich_text 返回 RichTextLabel")
	_assert_true(rtl.bbcode_enabled, "BBCode 已启用")
	_assert_eq(rtl.theme_type_variation, UITheme.MARKET_PREVIEW, "富文本主题")

	# 区域标签
	var section_lbl := UIBuilder.make_section_label("区域标题")
	_assert_eq(section_lbl.theme_type_variation, UITheme.SECTION_LABEL, "区域标签主题")

	# 自定义按钮
	var custom_btn := UIBuilder.make_button("自定义", UITheme.BTN_SET_SAIL, 80)
	_assert_eq(int(custom_btn.custom_minimum_size.y), 80, "自定义高度=80")
	_assert_eq(custom_btn.theme_type_variation, UITheme.BTN_SET_SAIL, "自定义主题")

	# NPC 按钮
	var npc_btn := UIBuilder.make_npc_button("对话")
	_assert_eq(npc_btn.theme_type_variation, UITheme.BTN_NPC, "NPC 按钮主题")
	_assert_eq(int(npc_btn.custom_minimum_size.y), 48, "NPC 按钮高度=48")

	print("")

# ── NK1-P6-POLISH-003: GameColors 常量类测试 ───────────────

func _test_game_colors() -> void:
	print("[GameColors]")

	# 警告/危险色
	_assert_eq(GameColors.WARNING, Color(1, 0.3, 0.3), "GameColors.WARNING")
	_assert_eq(GameColors.DAMAGE, Color(1, 0.28, 0.22), "GameColors.DAMAGE")
	_assert_eq(GameColors.WARNING_SOFT, Color(1.0, 0.7, 0.4), "GameColors.WARNING_SOFT")
	_assert_eq(GameColors.PIRATE_RED, Color(1.0, 0.45, 0.4), "GameColors.PIRATE_RED")
	_assert_eq(GameColors.ENEMY_BLIP, Color(1.0, 0.35, 0.35), "GameColors.ENEMY_BLIP")
	_assert_eq(GameColors.DANGER_TEXT, Color(0.95, 0.55, 0.45), "GameColors.DANGER_TEXT")

	# 成功色
	_assert_eq(GameColors.SUCCESS, Color(0.2, 1.0, 0.2), "GameColors.SUCCESS")
	_assert_eq(GameColors.PERMIT_OK, Color(0.55, 0.95, 0.7), "GameColors.PERMIT_OK")
	_assert_eq(GameColors.PRICE_CRASH, Color(0.4, 1.0, 0.4), "GameColors.PRICE_CRASH")
	_assert_eq(GameColors.PRICE_DROP, Color(0.7, 1.0, 0.7), "GameColors.PRICE_DROP")
	_assert_eq(GameColors.PORT_BLIP, Color.GREEN, "GameColors.PORT_BLIP")

	# 信息色
	_assert_eq(GameColors.INFO, Color(0.5, 0.8, 1), "GameColors.INFO")
	_assert_eq(GameColors.SCENERY, Color(0.7, 0.85, 1.0, 0.9), "GameColors.SCENERY")
	_assert_eq(GameColors.PATROL_BLUE, Color(0.55, 0.75, 1.0), "GameColors.PATROL_BLUE")
	_assert_eq(GameColors.NAVY_HUD, Color(0, 0.1, 0.2, 0.8), "GameColors.NAVY_HUD")
	_assert_eq(GameColors.RADAR_RING, Color(0.2, 0.5, 0.8), "GameColors.RADAR_RING")

	# UI 文字色
	_assert_eq(GameColors.TEXT_GOLD, Color(0.98, 0.84, 0.42, 1), "GameColors.TEXT_GOLD")
	_assert_eq(GameColors.TEXT_GOLD_BRIGHT, Color(0.98, 0.92, 0.72, 1), "GameColors.TEXT_GOLD_BRIGHT")
	_assert_eq(GameColors.TEXT_WARN, Color(1.0, 0.75, 0.4, 1), "GameColors.TEXT_WARN")
	_assert_eq(GameColors.TEXT_DIM, Color(0.62, 0.6, 0.52, 1), "GameColors.TEXT_DIM")
	_assert_eq(GameColors.TEXT_ICON_DIM, Color(0.72, 0.72, 0.72, 1), "GameColors.TEXT_ICON_DIM")
	_assert_eq(GameColors.FLEET_DEFAULT, Color(0.85, 0.85, 0.9), "GameColors.FLEET_DEFAULT")

	# 港状态栏色
	_assert_eq(GameColors.METER_NORMAL, Color(0.82, 0.62, 0.24, 1), "GameColors.METER_NORMAL")
	_assert_eq(GameColors.METER_WARN, Color(0.95, 0.72, 0.28, 1), "GameColors.METER_WARN")
	_assert_eq(GameColors.METER_DANGER, Color(0.92, 0.38, 0.32, 1), "GameColors.METER_DANGER")

	# 浮文色
	_assert_eq(GameColors.FLOATING_ECONOMY, Color(1.0, 0.9, 0.6, 0.85), "GameColors.FLOATING_ECONOMY")
	_assert_eq(GameColors.FLOATING_PORT_NEAR, Color(0.9, 1.0, 0.8, 0.95), "GameColors.FLOATING_PORT_NEAR")
	_assert_eq(GameColors.FLOATING_CREW_LOSS, Color.RED, "GameColors.FLOATING_CREW_LOSS")
	_assert_eq(GameColors.FLOATING_PICKUP, Color(0.2, 1.0, 0.2), "GameColors.FLOATING_PICKUP")

	# 天气/时间色
	_assert_eq(GameColors.LIGHT_NOON, Color(1, 1, 1, 1), "GameColors.LIGHT_NOON")
	_assert_eq(GameColors.LIGHT_NIGHT, Color(0.2, 0.2, 0.4, 1.0), "GameColors.LIGHT_NIGHT")
	_assert_eq(GameColors.LIGHT_DAWN, Color(0.8, 0.5, 0.4, 1.0), "GameColors.LIGHT_DAWN")
	_assert_eq(GameColors.LIGHT_DUSK, Color(0.8, 0.4, 0.2, 1.0), "GameColors.LIGHT_DUSK")
	_assert_eq(GameColors.LIGHT_STORM, Color(0.3, 0.3, 0.4, 1.0), "GameColors.LIGHT_STORM")
	_assert_eq(GameColors.WEATHER_CLEAR, Color(0.5, 0.8, 1), "GameColors.WEATHER_CLEAR")
	_assert_eq(GameColors.WEATHER_STORM, Color(1, 0.3, 0.3), "GameColors.WEATHER_STORM")
	_assert_eq(GameColors.MAP_LINE, Color(1, 1, 1, 0.3), "GameColors.MAP_LINE")
	_assert_eq(GameColors.MAP_LABEL, Color(0.8, 0.8, 0.8, 0.8), "GameColors.MAP_LABEL")

	# 模态遮罩
	_assert_eq(GameColors.MODAL_TOP, Color(0.02, 0.02, 0.03, 0.72), "GameColors.MODAL_TOP")
	_assert_eq(GameColors.MODAL_BOTTOM, Color(0.01, 0.01, 0.02, 0.88), "GameColors.MODAL_BOTTOM")
	_assert_eq(GameColors.MODAL_DIM, Color(0.02, 0.02, 0.02, 0.82), "GameColors.MODAL_DIM")
	_assert_eq(GameColors.MARKET_BG, Color(0.02, 0.02, 0.02, 0.88), "GameColors.MARKET_BG")

	# 通用
	_assert_eq(GameColors.WHITE, Color.WHITE, "GameColors.WHITE")
	_assert_eq(GameColors.TRANSPARENT, Color.TRANSPARENT, "GameColors.TRANSPARENT")

	# 辅助方法：价格趋势色
	var trend_color: Color = GameColors.get_price_trend_color(2.5)
	_assert_eq(trend_color, GameColors.WARNING, "价格趋势 ≥2.0: WARNING")
	trend_color = GameColors.get_price_trend_color(1.3)
	_assert_eq(trend_color, GameColors.WARNING_SOFT, "价格趋势 1.2-2.0: WARNING_SOFT")
	trend_color = GameColors.get_price_trend_color(1.0)
	_assert_eq(trend_color, GameColors.TRANSPARENT, "价格趋势 0.8-1.2: TRANSPARENT")
	trend_color = GameColors.get_price_trend_color(0.4)
	_assert_eq(trend_color, GameColors.PRICE_CRASH, "价格趋势 ≤0.5: PRICE_CRASH")
	trend_color = GameColors.get_price_trend_color(0.6)
	_assert_eq(trend_color, GameColors.PRICE_DROP, "价格趋势 0.5-0.8: PRICE_DROP")

	# 辅助方法：繁荣度色
	var p_color: Color = GameColors.get_prosperity_color(1.2)
	_assert_eq(p_color, GameColors.TEXT_GOLD, "繁荣度>1.1: TEXT_GOLD")
	p_color = GameColors.get_prosperity_color(1.0)
	_assert_eq(p_color, GameColors.TEXT_GOLD_BRIGHT, "繁荣度0.9-1.1: TEXT_GOLD_BRIGHT")
	p_color = GameColors.get_prosperity_color(0.8)
	_assert_eq(p_color, GameColors.WARNING, "繁荣度<0.9: WARNING")

	# 辅助方法：港状态栏色
	var r_color: Color = GameColors.get_ratio_status_color(0.05)
	_assert_eq(r_color, GameColors.WARNING, "比例 ≤0.1: WARNING")
	r_color = GameColors.get_ratio_status_color(0.2)
	_assert_eq(r_color, GameColors.WARNING_SOFT, "比例 0.1-0.25: WARNING_SOFT")
	r_color = GameColors.get_ratio_status_color(0.5)
	_assert_eq(r_color, GameColors.TEXT_GOLD_BRIGHT, "比例 >0.25: TEXT_GOLD_BRIGHT")

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
	_assert_true(not IntentTypes.is_known("unknown_type"), "is_known: unknown_type 不存在")
	_assert_true(not IntentTypes.is_known(""), "is_known: 空字符串不存在")

	# all_types 返回 14 个
	var all_types: Array = IntentTypes.all_types()
	_assert_eq(all_types.size(), 14, "IntentTypes.all_types: 共 14 个类型")

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

# ── NK1-P6-POLISH-004: AssetPlaceholder JSON 化测试 ────────

func _test_asset_placeholder_json() -> void:
	print("[AssetPlaceholder JSON]")

	# JSON 文件存在
	_assert_true(FileAccess.file_exists("res://data/asset_backgrounds.json"), "asset_backgrounds.json 文件存在")

	# 实例化 AssetPlaceholder（extends Node）
	var ap: Node = Node.new()
	ap.set_script(load("res://scripts/AssetPlaceholder.gd"))
	_assert_not_null(ap, "AssetPlaceholder 实例化成功")

	# 有图池的港口不再走单图别名
	var mapped_path: String = ap.get_background_path("res://assets/bg_quanzhou_port.png")
	_assert_eq(mapped_path, "res://assets/bg_quanzhou_port.png", "bg_quanzhou_port passthrough (pool)")

	mapped_path = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped_path, "res://assets/bg_northern_fortress_snow.png", "bg_byland_port -> bg_northern_fortress_snow")

	mapped_path = ap.get_background_path("res://assets/bg_xinghua_school.png")
	_assert_eq(mapped_path, "res://assets/bg_xinghua_residence.png", "bg_xinghua_school -> bg_xinghua_residence")

	# 不存在的 key 返回原值（passthrough）
	mapped_path = ap.get_background_path("res://assets/bg_nonexistent.png")
	_assert_eq(mapped_path, "res://assets/bg_nonexistent.png", "不存在 key: passthrough")

	# Legacy avatar 查询
	var avatar_path: String = ap.get_legacy_avatar_path("chen_wenlong")
	_assert_eq(avatar_path, "res://assets/placeholders/avatar_chen.png", "legacy avatar: chen_wenlong")

	avatar_path = ap.get_legacy_avatar_path("customs_official")
	_assert_eq(avatar_path, "res://assets/placeholders/avatar_official.png", "legacy avatar: customs_official")

	avatar_path = ap.get_legacy_avatar_path("unknown_npc")
	_assert_eq(avatar_path, "", "不存在 NPC: 空字符串")

	# 进港图池轮换
	var pick1: String = ap.pick_background_path("res://assets/bg_tunmen_port.png")
	var pick2: String = ap.pick_background_path("res://assets/bg_tunmen_port.png")
	_assert_true(pick1.begins_with("res://assets/port_pools/tunmen/"), "tunmen pool pick1")
	_assert_true(pick2.begins_with("res://assets/port_pools/tunmen/"), "tunmen pool pick2")
	_assert_true(pick1 != pick2, "tunmen pool rotates")

	# 热重载（应仍返回同样的映射）
	ap.reload_config()
	mapped_path = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped_path, "res://assets/bg_northern_fortress_snow.png", "reload 后映射仍正确")

	# 验证剩余别名都能查询（无图池港口仍走 fallback）
	var expected_count := 0
	var known_aliases: Array[String] = [
		"res://assets/bg_xinghua_school.png", "res://assets/bg_lin_ship.png",
		"res://assets/bg_departure.png", "res://assets/bg_black_water.png",
		"res://assets/bg_sea_route_aligned.png", "res://assets/bg_keelung_coast.png",
		"res://assets/bg_keelung_port.png", "res://assets/bg_hakata_port.png",
		"res://assets/bg_champa_port.png", "res://assets/bg_qiongzhou_port.png",
		"res://assets/bg_sanfoqi_port.png", "res://assets/bg_longyamen_port.png",
		"res://assets/bg_bugan_port.png", "res://assets/bg_jiaozhi_port.png",
		"res://assets/bg_yeshou_port.png", "res://assets/bg_tsushima_port.png",
		"res://assets/bg_byland_port.png", "res://assets/bg_xuwen_port.png",
	]
	for key in known_aliases:
		if ap.get_background_path(key) != key:
			expected_count += 1
	_assert_eq(expected_count, known_aliases.size(), "fallback 别名都正确加载")

	# 清理
	ap.queue_free()

	print("")

# ── NK1-P6-POLISH-004: TextKeys 常量类测试 ─────────────────

func _test_text_keys() -> void:
	print("[TextKeys]")

	# Intent 成功消息
	_assert_eq(TextKeys.INTENT_OK, "intent.ok", "TextKeys.INTENT_OK")
	_assert_eq(TextKeys.INTENT_PAYMENT_SUCCESS, "intent.payment.success", "TextKeys.INTENT_PAYMENT_SUCCESS")
	_assert_eq(TextKeys.INTENT_MARKET_BUY_SUCCESS, "intent.market_buy.success", "TextKeys.INTENT_MARKET_BUY_SUCCESS")
	_assert_eq(TextKeys.INTENT_MARKET_SELL_SUCCESS, "intent.market_sell.success", "TextKeys.INTENT_MARKET_SELL_SUCCESS")
	_assert_eq(TextKeys.INTENT_REPAIR_SUCCESS, "intent.repair.success", "TextKeys.INTENT_REPAIR_SUCCESS")
	_assert_eq(TextKeys.INTENT_BRIBE_SUCCESS, "intent.bribe.success", "TextKeys.INTENT_BRIBE_SUCCESS")
	_assert_eq(TextKeys.INTENT_COMBAT_STARTED, "intent.combat.started", "TextKeys.INTENT_COMBAT_STARTED")

	# Error 消息
	_assert_eq(TextKeys.ERROR_INTENT_MISSING_TYPE, "error.intent.missing_type", "TextKeys.ERROR_INTENT_MISSING_TYPE")
	_assert_eq(TextKeys.ERROR_MARKET_NO_PORT, "error.market.no_port", "TextKeys.ERROR_MARKET_NO_PORT")
	_assert_eq(TextKeys.ERROR_PAYMENT_INSUFFICIENT_FUNDS, "error.payment.insufficient_funds", "TextKeys.ERROR_PAYMENT_INSUFFICIENT_FUNDS")
	_assert_eq(TextKeys.ERROR_BRIBE_CUSTOMS_BLOCKED, "error.bribe.customs_blocked", "TextKeys.ERROR_BRIBE_CUSTOMS_BLOCKED")
	_assert_eq(TextKeys.ERROR_COMBAT_NO_FLEET, "error.combat.no_fleet", "TextKeys.ERROR_COMBAT_NO_FLEET")
	_assert_eq(TextKeys.ERROR_INSPECTION_NO_FUNDS, "error.inspection.no_funds", "TextKeys.ERROR_INSPECTION_NO_FUNDS")

	# is_intent_success 验证
	_assert_true(TextKeys.is_intent_success("intent.payment.success"), "is_intent_success: payment")
	_assert_true(TextKeys.is_intent_success("intent.bribe.success"), "is_intent_success: bribe")
	_assert_true(not TextKeys.is_intent_success("unknown.key"), "is_intent_success: unknown 不存在")

	# is_error 验证
	_assert_true(TextKeys.is_error("error.intent.missing_type"), "is_error: missing_type")
	_assert_true(TextKeys.is_error("error.combat.no_fleet"), "is_error: combat")
	_assert_true(not TextKeys.is_error("intent.payment.success"), "is_error: intent.* 不属于 error")

	# all_intent_success_keys 返回 16 个
	_assert_eq(TextKeys.all_intent_success_keys().size(), 16, "all_intent_success_keys: 16 个")

	# all_error_keys 返回 50+ 个
	var err_count: int = TextKeys.all_error_keys().size()
	_assert_true(err_count >= 50, "all_error_keys: >= 50 个")

	print("")

# ── NK1-P6-POLISH-004: FloatingTextConfig 测试 ─────────────

func _test_floating_text_config() -> void:
	print("[FloatingTextConfig]")

	# 基础参数
	_assert_eq(FloatingTextConfig.DEFAULT_FLOAT_SPEED, 50.0, "DEFAULT_FLOAT_SPEED=50.0")
	_assert_eq(FloatingTextConfig.DEFAULT_LIFETIME, 1.5, "DEFAULT_LIFETIME=1.5")

	# 偏移量
	_assert_eq(FloatingTextConfig.OFFSET_CREW_LOSS, Vector2(-100, -100), "OFFSET_CREW_LOSS")
	_assert_eq(FloatingTextConfig.OFFSET_SCENERY, Vector2(-120, -80), "OFFSET_SCENERY")
	_assert_eq(FloatingTextConfig.OFFSET_ECONOMY, Vector2(-200, -120), "OFFSET_ECONOMY")
	_assert_eq(FloatingTextConfig.OFFSET_PORT_NEAR, Vector2(-150, -100), "OFFSET_PORT_NEAR")
	_assert_eq(FloatingTextConfig.OFFSET_PICKUP, Vector2(0, 0), "OFFSET_PICKUP")

	# 生命周期
	_assert_eq(FloatingTextConfig.LIFETIME_CREW_LOSS, 2.0, "LIFETIME_CREW_LOSS=2.0")
	_assert_eq(FloatingTextConfig.LIFETIME_SCENERY, 3.0, "LIFETIME_SCENERY=3.0")
	_assert_eq(FloatingTextConfig.LIFETIME_ECONOMY, 4.0, "LIFETIME_ECONOMY=4.0")
	_assert_eq(FloatingTextConfig.LIFETIME_PORT_NEAR, 3.5, "LIFETIME_PORT_NEAR=3.5")

	# 抖动
	_assert_eq(FloatingTextConfig.RANDOM_JITTER, 20.0, "RANDOM_JITTER=20.0")
	_assert_eq(FloatingTextConfig.Z_INDEX_DEFAULT, 100, "Z_INDEX_DEFAULT=100")

	# 航海风景池
	_assert_eq(FloatingTextConfig.VOYAGE_SCENERY.size(), 10, "VOYAGE_SCENERY 池: 10 条")
	_assert_true(FloatingTextConfig.VOYAGE_SCENERY[0].length() > 0, "VOYAGE_SCENERY[0] 非空")
	_assert_true(FloatingTextConfig.VOYAGE_SCENERY[9].length() > 0, "VOYAGE_SCENERY[9] 非空")

	print("")

# ── P7-X: CutscenePlayer 测试 ─────────────────────────────

func _test_cutscene_player() -> void:
	print("[CutscenePlayer]")

	# 实例化 CutscenePlayer（从场景加载，确保 @onready 节点存在）
	var scene: PackedScene = load("res://scenes/CutscenePlayer.tscn") as PackedScene
	_assert_not_null(scene, "CutscenePlayer.tscn 加载成功")
	_assert_true(scene != null, "CutscenePlayer.tscn 是 PackedScene")

	var player: Node = scene.instantiate()
	_assert_not_null(player, "CutscenePlayer 实例化成功")
	root.add_child(player)

	# 数据加载
	_assert_true(player._data.size() > 0, "cutscenes.json 加载: _data.size() > 0")
	_assert_true(player._data.has("quanzhou_arrival"), "_data 含 quanzhou_arrival")
	_assert_true(player._data.has("ch3_start"), "_data 含 ch3_start (含 panels)")
	_assert_true(player._data.has("rank_up_1"), "_data 含 rank_up_1")
	_assert_true(player._data.has("ending_loyalty"), "_data 含 ending_loyalty")
	_assert_eq(player._data["quanzhou_arrival"]["hook"], "port_arrival", "quanzhou_arrival.hook=port_arrival")
	_assert_eq(player._data["quanzhou_arrival"]["port_id"], "quanzhou", "quanzhou_arrival.port_id=quanzhou")
	_assert_eq(int(player._data["rank_up_1"]["rank"]), 1, "rank_up_1.rank=1（JSON 解析为 float 但数值正确）")

	# 1. play("不存在") 静默返回，_playing 保持 false
	player.play("nonexistent_id_xyz")
	_assert_true(not player._playing, "play(不存在 id): _playing 保持 false")
	_assert_true(not player.visible, "play(不存在 id): visible 保持 false")

	# 4. _find_by_hook("port_arrival","quanzhou") 返回 "quanzhou_arrival"
	_assert_eq(player._find_by_hook("port_arrival", "quanzhou"), "quanzhou_arrival", "port_arrival+quanzhou -> quanzhou_arrival")

	# 5. _find_by_hook("port_arrival","不存在的港") 返回 ""
	_assert_eq(player._find_by_hook("port_arrival", "不存在的港"), "", "port_arrival+不存在 -> ''")

	# 6. _find_by_hook("chapter_change","chapter3_pu_counter") 返回 "ch3_start"
	_assert_eq(player._find_by_hook("chapter_change", "chapter3_pu_counter"), "ch3_start", "chapter_change+chapter3_pu_counter -> ch3_start")

	# 额外：rank_up / ending 钩子覆盖
	_assert_eq(player._find_by_hook("rank_up", "1"), "rank_up_1", "rank_up+1 -> rank_up_1")
	_assert_eq(player._find_by_hook("ending", "loyalty_ending"), "ending_loyalty", "ending+loyalty_ending -> ending_loyalty")
	_assert_eq(player._find_by_hook("unknown_hook", "x"), "", "未知 hook -> ''")

	# 公开 API get_cutscene_id_for / has_cutscene
	_assert_eq(player.get_cutscene_id_for("port_arrival", "quanzhou"), "quanzhou_arrival", "get_cutscene_id_for 公共 API")
	_assert_true(player.has_cutscene("port_arrival", "quanzhou"), "has_cutscene(存在) -> true")
	_assert_true(not player.has_cutscene("port_arrival", "不存在的港"), "has_cutscene(不存在) -> false")

	# 2. play("quanzhou_arrival") 后 _playing=true，visible=true
	player.play("quanzhou_arrival")
	_assert_true(player._playing, "play(quanzhou_arrival): _playing=true")
	_assert_true(player.visible, "play(quanzhou_arrival): visible=true")
	_assert_eq(player._current_id, "quanzhou_arrival", "play: _current_id 正确")

	# 3. skip() 后 _playing=false, visible=false, finished 信号发出
	var finished_emitted: Array = [false]
	var finished_id: Array = [""]
	player.finished.connect(func(id: String):
		finished_emitted[0] = true
		finished_id[0] = id
	)
	player.skip()
	_assert_true(not player._playing, "skip(): _playing=false")
	_assert_true(not player.visible, "skip(): visible=false")
	_assert_true(finished_emitted[0], "skip(): finished 信号发出")
	_assert_eq(finished_id[0], "quanzhou_arrival", "skip(): finished id 正确")

	# 7. _data={} 模拟 JSON 缺失：play 任何 id 静默不崩
	var player_empty: Node = scene.instantiate()
	root.add_child(player_empty)
	player_empty._data = {}
	player_empty.play("quanzhou_arrival")
	_assert_true(not player_empty._playing, "_data={} 时 play: 静默，_playing=false")
	_assert_true(not player_empty.visible, "_data={} 时 play: visible=false")
	player_empty.queue_free()

	# 8. panels 多分镜：_panel_index 推进至 size 后触发 _end
	# 注：tween 异步推进；这里直接验证状态机 + 数据。
	var player2: Node = scene.instantiate()
	root.add_child(player2)
	player2.play("ch3_start")
	_assert_eq(player2._panels.size(), 2, "ch3_start panels 数量 = 2")
	_assert_eq(player2._panel_index, 0, "_panel_index 起始 = 0")
	_assert_true(player2._playing, "play(ch3_start) _playing=true（多分镜）")
	# panels 耗尽判断：_panel_index >= _panels.size() 走 _end 分支
	player2._panel_index = player2._panels.size()
	# 直接调 _end 验证结束态（替代等待 tween）
	player2._end()
	_assert_true(not player2._playing, "_end 后 _playing=false")
	_assert_true(not player2.visible, "_end 后 visible=false")
	player2.queue_free()

	# 9. CG 路径经 AssetPlaceholder.get_background_path 解析别名（验证调用，非实际加载）
	# 实例化 AssetPlaceholder（autoload，避免编译期依赖）
	var ap: Node = Node.new()
	ap.set_script(load("res://scripts/AssetPlaceholder.gd"))
	var entry: Dictionary = player._data["quanzhou_arrival"]
	var alias: String = entry.get("cg_alias", "")
	_assert_eq(alias, "res://assets/bg_quanzhou_harbor_koei.png", "cg_alias 字段正确")
	var resolved: String = ap.get_background_path(alias)
	_assert_eq(resolved, "res://assets/bg_quanzhou_harbor_koei.png", "CG 路径经 get_background_path 解析（passthrough）")
	# 验证别名映射确实会触发（无图池港口）
	var mapped: String = ap.get_background_path("res://assets/bg_byland_port.png")
	_assert_eq(mapped, "res://assets/bg_northern_fortress_snow.png", "get_background_path 别名映射生效")
	ap.queue_free()

	# panels 中的 cg_alias 同样走解析路径
	var panels: Array = player._data["ch3_start"].get("panels", [])
	_assert_eq(panels.size(), 2, "ch3_start panels 字段读取正确")
	_assert_eq(panels[0].get("duration", 0.0), 3.0, "panel[0].duration=3.0")
	_assert_eq(panels[1].get("duration", 0.0), 2.5, "panel[1].duration=2.5")

	player.queue_free()
	print("")


func _test_ship_system() -> void:
	print("[ShipSystem]")

	var ship: ShipState = ShipSystem.create_ship_state("fujian_merchant")
	_assert_eq(ship.hull_id, "fujian_merchant", "create_ship_state hull_id")
	_assert_eq(ship.name, "福船", "create_ship_state name")
	_assert_eq(ship.sail_type, "square", "福船 sail_type")

	var perf: Dictionary = ShipSystem.compute_performance(ship)
	_assert_eq(perf.max_speed, 280.0, "福船 base max_speed")
	_assert_eq(perf.max_gear, 2, "福船 max_gear")

	ship.sail_level = 2
	perf = ShipSystem.compute_performance(ship)
	_assert_eq(perf.max_speed, 330.0, "sail_level 2 adds speed")

	var lateen: ShipState = ShipSystem.create_ship_state("guangzhou_trader")
	_assert_eq(lateen.sail_type, "lateen", "广船 lateen sail")
	_assert_gt(float(ShipSystem.compute_performance(lateen).base_turn_speed), 2.0, "广船 turn speed")

	_assert_true(ShipSystem.should_storm_damage(160.0, 2), "storm damage when full sail")
	_assert_true(not ShipSystem.should_storm_damage(120.0, 2), "no storm damage calm wind")

	var flagship: ShipState = ShipSystem.create_ship_state("fujian_merchant")
	flagship.hp = 50.0
	flagship.crew = 25
	_assert_true(ShipSystem.apply_hull_to_flagship(flagship, "guangzhou_trader"), "apply_hull_to_flagship")
	_assert_eq(flagship.hull_id, "guangzhou_trader", "hull changed to guangzhou_trader")
	_assert_eq(flagship.name, "广船", "hull name updated")
	_assert_eq(flagship.sail_type, "lateen", "广船 sail_type applied")
	_assert_eq(flagship.max_hp, 110.0, "广船 max_hp")
	_assert_eq(flagship.hp, 55.0, "hp ratio preserved")
	_assert_eq(flagship.crew, 28, "crew ratio preserved")

	var options: Array = ShipSystem.list_shipyard_hulls("fujian_merchant", 0)
	_assert_eq(options.size(), 1, "one shipyard hull from 福船")
	_assert_eq(str(options[0].get("id", "")), "guangzhou_trader", "shipyard offers 广船")

	var fujian: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("fujian_merchant")
	var guang: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("guangzhou_trader")
	var warship: ShipModelLibrary.ShipModel = ShipModelLibrary.get_model("warship_patrol")
	_assert_eq(fujian.sail_type, "square", "福船 model sail_type")
	_assert_eq(guang.sail_type, "lateen", "广船 model sail_type")
	_assert_gt(guang.hull_points.size(), 4, "广船 hull polygon")
	_assert_gt(warship.gun_ports.size(), 0, "巡防舰 gun ports")

	var fujian_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("fujian_merchant")
	var guang_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("guangzhou_trader")
	var warship_spawn: Vector2 = ShipModelLibrary.get_port_spawn_offset("warship_patrol")
	_assert_gt(fujian_spawn.y, 100.0, "福船出港偏移 > 旧固定 100")
	_assert_gt(warship_spawn.y, fujian_spawn.y, "巡防舰出港偏移大于福船")
	_assert_gt(guang_spawn.y, 90.0, "广船出港偏移合理")

	var summary: String = ShipSystem.format_ship_summary(ship)
	_assert_true(summary.contains("福船"), "format_ship_summary name")
	_assert_true(summary.contains("横帆"), "format_ship_summary sail")

	var delta: String = ShipSystem.format_hull_change_delta(ship, "guangzhou_trader")
	_assert_true(delta.contains("耐久+10"), "hull delta max_hp")
	_assert_true(delta.contains("帆→纵帆"), "hull delta sail change")

	var mini_hull: PackedVector2Array = ShipModelLibrary.get_minimap_hull("fujian_merchant")
	_assert_gt(mini_hull.size(), 4, "minimap hull points")

	var patrol_hull := ShipSystem.get_hull("warship_patrol")
	var no_flags := func(_flag: String) -> bool: return false
	_assert_true(not ShipSystem.is_hull_unlocked(patrol_hull, 0, no_flags), "warship locked by default")
	var hull_offers: Array = ShipSystem.list_shipyard_hull_offers("fujian_merchant", 0, no_flags)
	var has_locked_warship := false
	for offer in hull_offers:
		if str(offer.get("hull", {}).get("id", "")) == "warship_patrol":
			has_locked_warship = true
			_assert_true(offer.get("locked", false), "warship offer shown locked")
	_assert_true(has_locked_warship, "warship in shipyard offers")

	var has_ch1 := func(flag: String) -> bool: return flag == "chapter1_complete"
	_assert_true(ShipSystem.is_hull_unlocked(patrol_hull, 30, has_ch1), "warship unlocked with fame+flag")

	var fujian_hull: Dictionary = ShipSystem.get_hull("fujian_merchant")
	_assert_true(not fujian_hull.get("visual", {}).is_empty(), "福船 visual block in ships.json")
	_assert_eq(fujian.hull_id, "fujian_merchant", "JSON model hull_id")
	_assert_eq(fujian.hull_points.size(), 6, "JSON 福船 hull_points count")

	var combat_detail: String = ShipSystem.format_combat_ship_detail(ship)
	_assert_true(combat_detail.contains("福船"), "combat detail hull name")
	_assert_true(combat_detail.contains("横帆"), "combat detail sail")
	_assert_true(combat_detail.contains("炮2"), "combat detail artillery")
	_assert_true(combat_detail.contains("机动5"), "combat detail maneuver")

	var nav := NavigationState.new()
	nav.save_world_map_pose(Vector2(1200.5, -800.25), 1.57)
	_assert_true(nav.world_map_pose_saved, "nav pose saved flag")
	_assert_eq(nav.world_map_position, Vector2(1200.5, -800.25), "nav pose position")
	var nav_dict: Dictionary = nav.to_dict()
	var nav2 := NavigationState.new()
	nav2.from_dict(nav_dict)
	_assert_true(nav2.world_map_pose_saved, "nav pose round-trip saved")
	_assert_eq(nav2.world_map_position, Vector2(1200.5, -800.25), "nav pose round-trip position")
	_assert_lt(absf(nav2.world_map_rotation - 1.57), 0.001, "nav pose round-trip rotation")
	nav2.clear_world_map_pose()
	_assert_true(not nav2.world_map_pose_saved, "nav pose cleared")
	print("")

# ═══════════════════════════════════════════════════════════
# Mock 事件 — 用于测试 PriceEngine 事件修正逻辑
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
