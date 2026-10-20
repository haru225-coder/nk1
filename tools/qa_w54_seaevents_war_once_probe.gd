extends SceneTree
## lane w54-seaevents：战时遭遇了结过的，同一程不再来第二回。
##   征船（Voyage._war_event 逐日掷 5%）：交出一条船「小官在册子上记了你的名字」、塞钱换了册上「已征」两个字、抗征被追上
##   「『抗征』二字记入册子，罚钱」——原先第二天照样再来一条哨船「朝廷用船。按册征调」，一程里能连征几回。
## 断言（真走 Voyage.roll_day_event：泉州→福州 1275-06，两端都是宋土战港，逐日掷 2000 回数征船那一面）：
##   R0 发舶后没碰过征船：照常会抽到（基线）。
##   R1 塞钱免征之后 / R2 交出一条船之后 / R3 趁夜溜走被追上罚过之后：同一程 2000 回一回不出。
##   R4 趁夜溜走溜成了：不算了结，照常会再遇。
##   R5 了结过，下一程真走 SeaChart._on_sail_pressed 发舶：记录清掉，又照常会抽到。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_war_once_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_WAR_ONCE cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const ROLLS := 2000

var _gs: Node
var _cal: Node
var _fleet: Node
var _voy: Node
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
	_voy = root.get_node_or_null("Voyage")
	if _gs == null or _cal == null or _fleet == null or _voy == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_cal.call("from_dict", {"year": 1275, "month": 6, "day": 5})
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(4)
	# 停在海上半途：回调末尾的 _on_event_continue 见没在航行、余程未尽就不往下走
	chart.set("sailing", false)
	chart.set("remaining_li", 500.0)
	var req: int = int(_voy.get("EventKind")["REQUISITION"])
	print("── R 征船")
	_voy.call("begin_voyage")
	var base := _count(req, "quanzhou", "fuzhou")
	_expect(base > 0, "R0 没碰过征船：%d 回里抽到 %d 回" % [ROLLS, base])
	_voy.call("begin_voyage")
	_fleet_two()
	_gs.set("money", 1000)
	chart.call("_on_requisition_bribe")
	var line := _latest(chart)
	var n := _count(req, "quanzhou", "fuzhou")
	_expect(line.contains("已征") and n == 0, "R1 塞钱免征（札记「%s」）之后同一程抽到 %d 回" % [line, n])
	_voy.call("begin_voyage")
	_fleet_two()
	chart.call("_on_requisition_surrender")
	line = _latest(chart)
	n = _count(req, "quanzhou", "fuzhou")
	_expect(line.contains("编入官军") and (_fleet.get("ships") as Array).size() == 1 and n == 0,
		"R2 交出一条船（札记「%s」）之后同一程抽到 %d 回" % [line, n])
	_voy.call("begin_voyage")
	_fleet_two()
	_gs.set("money", 1000)
	seed(_flee_seed(false))
	chart.call("_on_requisition_flee")
	line = _latest(chart)
	n = _count(req, "quanzhou", "fuzhou")
	_expect(line.contains("被哨船追上") and n == 0, "R3 抗征被追上罚过（札记「%s」）之后同一程抽到 %d 回" % [line, n])
	_voy.call("begin_voyage")
	_fleet_two()
	seed(_flee_seed(true))
	chart.call("_on_requisition_flee")
	line = _latest(chart)
	n = _count(req, "quanzhou", "fuzhou")
	_expect(line.contains("漂出哨船视线") and n > 0, "R4 趁夜溜走溜成了（札记「%s」）不算了结：同一程抽到 %d 回" % [line, n])
	# R5：上面 R3 那样了结过一回，再真点一次发舶
	_fleet_two()
	_gs.set("money", 1000)
	seed(_flee_seed(false))
	chart.call("_on_requisition_flee")
	var settled_before := bool(_voy.call("war_event_settled", req))
	chart.set("origin_port", "quanzhou")
	chart.set("selected_port", "fuzhou")
	chart.call("_on_sail_pressed")
	# 发舶那一刻同步清了记录；船标补间还挂着，掐掉这一程（序号一换，等着的协程醒来自退）
	var settled_after := bool(_voy.call("war_event_settled", req))
	chart.set("sailing", false)
	chart.set("_sail_serial", int(chart.get("_sail_serial")) + 1)
	chart.call("_cancel_marker")
	_fleet.set("at_sea", false)
	await _frames(2)
	n = _count(req, "quanzhou", "fuzhou")
	_expect(settled_before and not settled_after and n > 0,
		"R5 了结过（%s）、下一程发舶后记录清掉（%s），抽到 %d 回" % [str(settled_before), str(settled_after), n])
	chart.queue_free()
	await _frames(2)
	_report()


func _frames(k: int) -> void:
	for _i in k:
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


## 旗舰客舟 + 护航小艍（交船交最小的那条，交的是护航），水粮各 60
func _fleet_two() -> void:
	_fleet.set("ships", [])
	_fleet.call("add_ship", "keel_boat", "探针客舟")
	_fleet.call("add_ship", "sampan", "探针小艍")
	_fleet.set("water", 60)
	_fleet.set("food", 60)
	_fleet.set("morale", 70)
	_gs.set("fame", 10)


## 逐日真抽 ROLLS 回（Voyage.roll_day_event，船向 90°、针路），数 kind 那一面；抽之前存下船队与历法，抽完原样还回
## （风涛扣船体、无风扣士气，抽两千日会把船队抽空；历法不动，抽的始终是这一日的战况）
func _count(kind: int, from_id: String, to_id: String) -> int:
	var keep_fleet: Dictionary = _fleet.call("to_dict")
	seed(5401)
	var hits := 0
	for _i in ROLLS:
		var ev: Dictionary = _voy.call("roll_day_event", 90.0, from_id, to_id)
		if int(ev.get("kind", 0)) == kind:
			hits += 1
	_fleet.call("from_dict", keep_fleet)
	return hits


## 趁夜溜走那一下的种子：want_ok 要溜成就挑 randf() < 成功率的，反之挑掷不中的
func _flee_seed(want_ok: bool) -> int:
	var chance := clampf(float(_fleet.call("fleet_speed")) / 240.0, 0.2, 0.85)
	for k in range(1, 5000):
		seed(k)
		if (randf() < chance) == want_ok:
			return k
	return 1


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_WAR_ONCE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
