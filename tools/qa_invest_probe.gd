extends SceneTree
## lane probe1：修埠入股探针（花费/等级/名声/职衔/满级/钱不够）。
## 用法：godot --headless --path . -s res://tools/qa_invest_probe.gd
## 输出末行 INVEST_PROBE cases=N fails=M；M>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var eco: Node
var gs: Node
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
	eco = root.get_node_or_null("Economy")
	gs = root.get_node_or_null("GameState")
	if eco == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return

	_reset()

	_expect(eco.invest_max_level() == 5, "满级 5")
	_expect(eco.investment_level("quanzhou") == 0, "开局等级 0")
	_expect(eco.invest_cost("quanzhou") == 800, "第一等花费 800")

	var bad: Dictionary = eco.invest("")
	_expect(not bad.get("ok", true), "空港名拒修")
	bad = eco.invest("no_such_port")
	_expect(not bad.get("ok", true), "无此港拒修")

	# 钱不够
	gs.money = 100
	var r: Dictionary = eco.invest("quanzhou")
	_expect(not r.get("ok", true), "钱不够拒修")
	_expect(gs.money == 100, "钱不够钱不动")
	_expect(eco.investment_level("quanzhou") == 0, "钱不够等级不动")

	# 成功第一等
	gs.money = 100000
	gs.fame = 0
	r = eco.invest("quanzhou")
	_expect(r.get("ok", false), "第一等成功")
	_expect(int(r.get("level", 0)) == 1, "第一等等级 1")
	_expect(int(r.get("cost", 0)) == 800, "第一等花费 800")
	_expect(int(r.get("fame", 0)) == 4, "第一等名声加 4")
	_expect(gs.money == 100000 - 800, "第一等钱扣 800")
	_expect(eco.investment_level("quanzhou") == 1, "存档等级 1")
	_expect(eco.invest_cost("quanzhou") == 2000, "第二等花费 2000")
	_expect(is_equal_approx(eco.invest_edge("quanzhou"), 0.025), "一等 edge 0.025")

	# 连续升到满级，测职衔晋升与满级
	gs.money = 100000
	var promoted_seen := false
	for i in range(2, 6):
		r = eco.invest("quanzhou")
		_expect(r.get("ok", false), "第 %d 等成功" % i)
		if r.get("promoted", false):
			promoted_seen = true
	_expect(promoted_seen, "过程中有一次职衔晋升")
	_expect(eco.investment_level("quanzhou") == 5, "升到 5 等")
	_expect(eco.invest_cost("quanzhou") == 0, "满级花费 0")
	var top: Dictionary = eco.invest("quanzhou")
	_expect(not top.get("ok", true), "满级拒修")
	_expect(str(top.get("msg", "")).find("顶等") >= 0, "满级提示顶等")

	# 其他港独立
	_expect(eco.investment_level("fuzhou") == 0, "福州未修")
	_expect(eco.invest_cost("fuzhou") == 800, "福州第一等 800")

	_restore()
	_report()


func _reset() -> void:
	eco.investments = {}
	gs.money = 0
	gs.fame = 0
	eco.rates = eco.rates if eco.rates != null else {}


func _restore() -> void:
	eco.investments = {}
	gs.money = 1000
	gs.fame = 0


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
	print("INVEST_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
