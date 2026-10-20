extends SceneTree
## lane w54-voyage：海上遇事的札记写实扣——名声、士气都封底 0，扣不满照实写扣了几，一点没扣就不写。
##   SeaChart._on_requisition_flee（征船「趁夜溜走」被追上）原先一律写「名声减 4」，_on_refugee_pass（难民船「不停船」）
##   一律写「士气减 3」：名声只剩 2 时实扣 2、札记写 4；名声 0 时一点没扣也写「名声减 4」；断粮多日士气见底时同此。
##   lane w53-10 七轮修过委办逾期那一条（「名声已到 0 封底时扣不下去，罚条就不写『名声减 1』」），海上这两条漏了。
## 断言（直调 SeaChart 的两个钮回调，札记取最新一条）：
##   E1 被哨船追上：名声 10 写「名声减 4」实扣 4；名声 2 写「名声减 2」扣到 0；名声 0 不写名声减、仍 0。
##   E2 不停船：士气 50 写「士气减 3」；士气 1 写「士气减 1」扣到 0；士气 0 不写士气减。
##   E3 罚钱那半句照旧：「罚钱 N」= 现银实扣（与 qa_fine_text_probe 同口径）。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_voyage_event_cut_probe.gd（经门锁跑）
## 末行 W54_VOYAGE_EVENT_CUT cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _gs: Node
var _cal: Node
var _fleet: Node
var _re := RegEx.new()
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
	_re.compile("罚钱 (\\d+)")
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1275, "month": 6, "day": 5})
	_fleet.call("clear_cargo")
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(4)
	# 停在海上半途：回调末尾的 _on_event_continue 见没在航行、余程未尽就不往下走，札记最上一条就是这一句
	chart.set("sailing", false)
	chart.set("remaining_li", 500.0)
	print("── E1 / E3 征船「趁夜溜走」被哨船追上")
	for fame in [10, 2, 0]:
		_flee_caught(chart, fame)
	print("── E2 难民船「不停船」")
	for morale in [50, 1, 0]:
		_pass_refugee(chart, morale)
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


func _flee_caught(chart: Node, fame: int) -> void:
	var chance := clampf(float(_fleet.call("fleet_speed")) / 240.0, 0.2, 0.85)
	var s := -1
	for k in range(1, 5000):
		seed(k)
		if randf() >= chance:
			s = k
			break
	_gs.set("fame", fame)
	_gs.set("money", 1000)
	seed(s)
	chart.call("_on_requisition_flee")
	var line := _latest(chart)
	var cut := fame - int(_gs.get("fame"))
	var want := "名声减 %d" % mini(4, fame)
	var ok := line.contains("被哨船追上") and ((fame > 0 and line.contains(want) and cut == mini(4, fame))
		or (fame == 0 and not line.contains("名声减") and cut == 0))
	_expect(ok, "名声 %d：实扣 %d，札记「%s」" % [fame, cut, line])
	var m := _re.search(line)
	_expect(m != null and int(m.get_string(1)) == 1000 - int(_gs.get("money")),
		"名声 %d：「罚钱 %s」= 现银实扣 %d" % [fame, m.get_string(1) if m != null else "?", 1000 - int(_gs.get("money"))])


func _pass_refugee(chart: Node, morale: int) -> void:
	_fleet.set("morale", morale)
	chart.call("_on_refugee_pass")
	var line := _latest(chart)
	var cut := morale - int(_fleet.get("morale"))
	var ok := line.contains("没有停") and ((morale > 0 and line.contains("士气减 %d" % mini(3, morale)) and cut == mini(3, morale))
		or (morale == 0 and not line.contains("士气减") and cut == 0))
	_expect(ok, "士气 %d：实扣 %d，札记「%s」" % [morale, cut, line])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_VOYAGE_EVENT_CUT cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
