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
