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
	_test_market_state()
	_test_pricing_integration()
	_test_safety_valve()
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

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("  FAIL: ", msg)

func _pass(msg: String) -> void:
	_pass_count += 1
	print("  PASS: ", msg)

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

	# 测试 5: 超高倍率 — 大数不溢出为负
	var r5 = PriceEngine.calculate_price(100, 10.0, 10.0, 10.0, events_empty, "port_quanzhou", "gold")
	_assert_gt(float(r5["final_price"]), 0.0, "超高倍率: 100x1000 => final_price > 0")
	_assert_eq(r5["final_price"], 100000, "超高倍率: 100 * 10.0 * 10.0 * 10.0 => 100000")

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

	# 测试 1: 空 ID 应被忽略（始终通过）
	var r_empty = IdempotencyGuard.check_and_record("")
	_assert_true(r_empty, "空 ID: check_and_record 返回 true（非意图驱动交易忽略）")

	# 测试 2: 首次提交 — 酒馆请客事件
	var intent_id_1 = "tavern_treat_001"
	var r_first = IdempotencyGuard.check_and_record(intent_id_1)
	_assert_true(r_first, "首次提交: intent_id='tavern_treat_001' => true（扣费成功）")

	# 测试 3: 重复提交 — 同一酒馆请客事件必须被拦截
	var r_dup = IdempotencyGuard.check_and_record(intent_id_1)
	_assert_true(not r_dup, "重复提交: intent_id='tavern_treat_001' => false（拦截重复）")

	# 测试 4: 不同 ID — 另一笔交易应正常通过
	var intent_id_2 = "tavern_treat_002"
	var r_other = IdempotencyGuard.check_and_record(intent_id_2)
	_assert_true(r_other, "不同 ID: intent_id='tavern_treat_002' => true（正常通过）")

	# 测试 5: 第三次提交同一 ID — 仍然被拦截
	var r_trip = IdempotencyGuard.check_and_record(intent_id_1)
	_assert_true(not r_trip, "第三次提交: intent_id='tavern_treat_001' => false（持续拦截）")

	# 测试 6: 空 ID 可以反复通过（多次调用都应成功）
	var r_empty2 = IdempotencyGuard.check_and_record("")
	_assert_true(r_empty2, "空 ID 重复: 再次返回 true（空 ID 不记入记录）")

	# 测试 7: 验证内部状态 — processed_intents 应包含已记录的 ID
	_assert_true(IdempotencyGuard.processed_intents.has("tavern_treat_001"), "内部状态: 'tavern_treat_001' 在 processed_intents 中")
	_assert_true(IdempotencyGuard.processed_intents.has("tavern_treat_002"), "内部状态: 'tavern_treat_002' 在 processed_intents 中")
	_assert_true(not IdempotencyGuard.processed_intents.has(""), "内部状态: 空字符串不在 processed_intents 中")

	# 清理
	IdempotencyGuard.processed_intents.clear()

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
