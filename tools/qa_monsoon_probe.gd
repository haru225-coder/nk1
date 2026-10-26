extends SceneTree
## lane probe1：历法季风探针（各月季风类型/强度/风向方位）。
## 用法：godot --headless --path . -s res://tools/qa_monsoon_probe.gd
## 输出末行 MONSOON_PROBE cases=N fails=M；M>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var cal: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	cal = root.get_node_or_null("Calendar")
	if cal == null:
		push_error("autoload missing")
		quit(1)
		return

	# 季风类型：0=东北 1=西南 2=转换
	var expected_monsoon := {
		1: 0, 2: 0, 3: 2, 4: 2, 5: 1, 6: 1, 7: 1, 8: 1, 9: 2, 10: 0, 11: 0, 12: 0,
	}
	for m in range(1, 13):
		var got := int(cal.monsoon_of(m))
		_expect(got == expected_monsoon[m], "月 %d 季风类型 %d" % [m, expected_monsoon[m]])

	# 强度
	_expect(is_equal_approx(cal.monsoon_strength_of(11), 1.0), "十一月东北盛 1.0")
	_expect(is_equal_approx(cal.monsoon_strength_of(1), 1.0), "正月东北盛 1.0")
	_expect(is_equal_approx(cal.monsoon_strength_of(10), 0.8), "十月东北 0.8")
	_expect(is_equal_approx(cal.monsoon_strength_of(6), 1.0), "六月西南盛 1.0")
	_expect(is_equal_approx(cal.monsoon_strength_of(7), 1.0), "七月西南盛 1.0")
	_expect(is_equal_approx(cal.monsoon_strength_of(5), 0.8), "五月西南 0.8")
	_expect(is_equal_approx(cal.monsoon_strength_of(3), 0.3), "三月转换 0.3")

	# 风向方位
	_expect(is_equal_approx(cal.wind_bearing_of(1), 225.0), "正月东北风向 225")
	_expect(is_equal_approx(cal.wind_bearing_of(6), 45.0), "六月西南风向 45")
	_expect(is_equal_approx(cal.wind_bearing_of(3), -1.0), "三月转换无稳定风 -1")

	# 当前月同步
	cal.year = 1255
	cal.month = 7
	cal.day = 1
	_expect(int(cal.get_monsoon()) == 1, "当前七月 get_monsoon 西南")
	_expect(is_equal_approx(cal.get_monsoon_strength(), 1.0), "当前七月强度 1.0")
	_expect(is_equal_approx(cal.get_wind_bearing(), 45.0), "当前七月风向 45")

	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("MONSOON_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
