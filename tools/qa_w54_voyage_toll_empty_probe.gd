extends SceneTree
## lane w54-voyage：海寇「献上买路财」拿不出钱、舱里又空着——札记不再说「搬走了三成货」。
##   SeaChart._on_pay_pirates 钱不够时 Fleet.lose_cargo_ratio(0.3) 每样货至少搬走一件；舱里一件货没有，什么也没搬走，
##   札记照写「拿不出买路钱，他们自己动手搬走了三成货。」（后头货单是空的）。lane w53-10 把这句从「搬空了半个货舱」
##   改成实扣三成（check_w53_copy 钉 K），空舱这一形漏了。
## 断言（直调 SeaChart._on_pay_pirates，札记取最新一条）：
##   T1 钱不够、舱空：札记不提「三成货」，写对方没搬着东西；钱、舱、船体都不动。
##   T2 钱不够、舱里有货：照旧「搬走了三成货」并列出货单，舱里按三成少了（每样至少一件）。
##   T3 钱够：照旧付买路钱（与舱空不空无关）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_toll_empty_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_TOLL_EMPTY cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _gs: Node
var _cal: Node
var _fleet: Node
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
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	if _gs == null or _cal == null or _fleet == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1262, "month": 6, "day": 5})
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(4)
	# 停在海上半途：回调末尾的 _after_combat 见没在航行、余程未尽就不往下走，札记最上一条就是这一句
	chart.set("sailing", false)
	chart.set("remaining_li", 500.0)
	_t1_empty(chart)
	_t2_cargo(chart)
	_t3_paid(chart)
	chart.queue_free()
	await _frames(2)
	_report()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _latest(chart: Node) -> String:
	var lines: PackedStringArray = chart.get("_log_lines")
	return str(lines[0]) if lines.size() > 0 else ""


func _t1_empty(chart: Node) -> void:
	print("── T1 钱不够、舱空")
	_fleet.call("clear_cargo")
	_gs.set("money", 40)
	var dur := float(_fleet.call("total_durability"))
	chart.call("_on_pay_pirates")
	var line := _latest(chart)
	_expect(line.contains("拿不出买路钱") and not line.contains("三成货") and int(_gs.get("money")) == 40
		and float(_fleet.call("total_durability")) == dur and (_fleet.get("cargo") as Dictionary).is_empty(),
		"札记「%s」：不提三成货，钱 40、船体、空舱都不动" % line)


func _t2_cargo(chart: Node) -> void:
	print("── T2 钱不够、舱里有货")
	_fleet.call("clear_cargo")
	_fleet.call("add_cargo", "tea", 10, 20.0)
	_fleet.call("add_cargo", "pepper", 1, 30.0)
	_gs.set("money", 40)
	chart.call("_on_pay_pirates")
	var line := _latest(chart)
	_expect(line.contains("搬走三成的货") and int(_fleet.call("cargo_qty", "tea")) == 7 and int(_fleet.call("cargo_qty", "pepper")) == 0,
		"札记「%s」：茶 10 → 7、胡椒 1 → 0" % line)


func _t3_paid(chart: Node) -> void:
	print("── T3 钱够")
	_fleet.call("clear_cargo")
	_gs.set("money", 1000)
	chart.call("_on_pay_pirates")
	var line := _latest(chart)
	_expect(line.contains("买路") and int(_gs.get("money")) == 850, "札记「%s」：付 150、余 %d" % [line, int(_gs.get("money"))])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_TOLL_EMPTY cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
