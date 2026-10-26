extends SceneTree
## Lane sim3：季节需求（节令）探针——月推移时行情倍数随月而变，价格排序正确，存档结构不变。
## 用法：godot --headless --path . -s res://tools/qa_w57_seasonal_probe.gd
## 输出末行 SEASONAL_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var eco: Node
var cal: Node
var gs: Node
var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	eco = root.get_node_or_null("Economy")
	cal = root.get_node_or_null("Calendar")
	gs = root.get_node_or_null("GameState")
	if eco == null or cal == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()

	var saved_month: int = cal.month
	var saved_year: int = cal.year
	var saved_day: int = cal.day

	# 1. 季节倍数存在且默认 1.0
	_expect(eco.has_method("seasonal_mul"), "Economy.seasonal_mul 存在")
	var d0: float = eco.seasonal_mul("grain", 3)
	_expect(d0 > 0.0, "grain 3 月倍数 %.2f" % d0)

	# 2. 价格排序：米粮春贵秋贱
	cal.month = 4
	cal.year = 1255
	var p_spring: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	cal.month = 9
	var p_autumn: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	_expect(p_spring > p_autumn, "米粮春月买价 %d > 秋月买价 %d" % [p_spring, p_autumn])

	# 3. 月推移：十二月→一月，倍数随月而变
	cal.month = 12
	cal.year = 1255
	cal.day = 1
	var m12: float = eco.seasonal_mul("grain", 12)
	cal.advance_days(30)
	var m01: float = eco.seasonal_mul("grain", cal.month)
	_expect(cal.month == 1, "推进 30 日跨到一月（实际 %d）" % cal.month)
	_expect(not is_equal_approx(m12, m01), "十二月倍数 %.2f ≠ 一月倍数 %.2f" % [m12, m01])

	# 4. 存档结构不变
	var d: Dictionary = eco.to_dict()
	_expect(d.has("rates") and d.has("tariff") and d.has("broker") and d.has("investments"), "to_dict 四键齐全")
	_expect(d.keys().size() == 4, "to_dict 仅四键（无季节状态）")
	var before: Dictionary = d.duplicate(true)
	eco.from_dict(d)
	var after: Dictionary = eco.to_dict()
	_expect(after.keys() == before.keys(), "from_dict 后键集不变")

	cal.month = saved_month
	cal.year = saved_year
	cal.day = saved_day
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("SEASONAL_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
