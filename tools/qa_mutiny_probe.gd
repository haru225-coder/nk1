extends SceneTree
## lane probe1：舰队哗变路径探针（mutiny ready/cost/dismiss/suppress/resolve 各分支与 crew/cargo/money/morale/cooldown）。
## 用法：godot --headless --path . -s res://tools/qa_mutiny_probe.gd
## 输出末行 MUTINY_PROBE cases=N fails=M；M>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fleet: Node
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
	fleet = root.get_node_or_null("Fleet")
	gs = root.get_node_or_null("GameState")
	if fleet == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return

	_ready_ship()

	# A. mutiny_ready
	_reset(true, 10, 0)
	fleet.at_sea = false
	_expect(not fleet.mutiny_ready(), "岸上不闹哗变")

	_reset(true, 70, 0)
	_expect(not fleet.mutiny_ready(), "士气高不闹")

	_reset(true, 10, 0)
	_expect(fleet.mutiny_ready(), "海上士气低冷却尽可闹")

	_reset(true, 10, 3)
	_expect(not fleet.mutiny_ready(), "冷却未尽不闹")

	_reset(true, 10, 0)
	fleet.ships[0]["crew"] = 1
	_expect(not fleet.mutiny_ready(), "无人走得掉不闹")

	# B. 成本
	_reset(true, 10, 0)
	_expect(fleet.mutiny_bribe_cost() == 80, "15 人散钱走地板 80")

	_reset(true, 10, 0)
	fleet.ships[0]["crew"] = 100
	_expect(fleet.mutiny_bribe_cost() == 400, "100 人散钱 400")

	# C. 放人人数
	_reset(true, 10, 0)
	_expect(fleet.mutiny_dismiss_count() == 1, "15 人放 1")

	_reset(true, 10, 0)
	fleet.ships[0]["crew"] = 100
	_expect(fleet.mutiny_dismiss_count() == 10, "100 人放 10")

	# D. 放人是否会卡下趟出海
	_reset(true, 10, 0)
	_expect(fleet.mutiny_dismiss_blocks_next_sail(), "放 1 人跌破最低水手")

	# E. 压住
	gs.martial = 50
	_reset(true, 10, 0)
	_expect(fleet.mutiny_suppress_succeeds(), "武力 50 + 士气 10 压得住")

	_reset(true, 9, 0)
	_expect(not fleet.mutiny_suppress_succeeds(), "武力 50 + 士气 9 压不住")

	# F. resolve 分支
	gs.martial = 50
	# bribe success
	_reset(true, 10, 0)
	gs.money = 1000
	var before_crew: int = fleet.total_crew()
	var before_cargo: Dictionary = fleet.cargo.duplicate(true)
	var r: Dictionary = fleet.resolve_mutiny("bribe")
	_expect(r.get("outcome", "") == "bribe" and int(r.get("paid", -1)) == 80, "散钱成：outcome=paid=80")
	_expect(fleet.morale == 34, "散钱成：士气 34")
	_expect(fleet.mutiny_cooldown == 5, "散钱成：冷却 5")
	_expect(fleet.total_crew() == before_crew, "散钱成：人不走")
	_expect(gs.money == 920, "散钱成：钱扣 80")
	# cargo unchanged
	_expect(fleet.cargo.keys().size() == before_cargo.keys().size(), "散钱成：货不变")

	# bribe fail (money 0)
	_reset(true, 10, 0)
	fleet.add_cargo("tea", 10, 1.0, 0)
	gs.money = 0
	var crew0: int = fleet.total_crew()
	r = fleet.resolve_mutiny("bribe")
	_expect(r.get("outcome", "") == "bribe_fail" and int(r.get("paid", -1)) == 0, "散钱败：outcome=paid=0")
	_expect(fleet.total_crew() == crew0 - 1, "散钱败：放 1 人")
	_expect(int(r.get("crew_lost", 0)) == 1, "散钱败：crew_lost=1")
	_expect(fleet.morale == 30, "散钱败：士气 30")
	_expect(gs.money == 0, "散钱败：钱不动")

	# dismiss
	_reset(true, 10, 0)
	fleet.add_cargo("tea", 10, 1.0, 0)
	r = fleet.resolve_mutiny("dismiss")
	_expect(r.get("outcome", "") == "dismiss", "辞人：outcome=dismiss")
	_expect(int(r.get("crew_lost", 0)) == 1, "辞人：crew_lost=1")
	_expect(fleet.morale == 30, "辞人：士气 30")

	# suppress ok
	_reset(true, 10, 0)
	fleet.add_cargo("tea", 10, 1.0, 0)
	gs.martial = 50
	var crew_before: int = fleet.total_crew()
	var cargo_before: int = int(fleet.cargo.get("tea", {}).get("qty", 0))
	r = fleet.resolve_mutiny("suppress")
	_expect(r.get("outcome", "") == "suppress_ok", "压住成：outcome=suppress_ok")
	_expect(fleet.morale == 20, "压住成：士气 20")
	_expect(fleet.total_crew() == crew_before, "压住成：人不走")
	_expect(fleet.cargo.get("tea", {}).get("qty", 0) == cargo_before, "压住成：货不走")
	_expect(int(r.get("crew_lost", 0)) == 0, "压住成：crew_lost=0")

	# suppress fail
	_reset(true, 9, 0)
	fleet.add_cargo("tea", 10, 1.0, 0)
	gs.martial = 50
	r = fleet.resolve_mutiny("suppress")
	_expect(r.get("outcome", "") == "suppress_fail", "压不住：outcome=suppress_fail")
	_expect(fleet.morale == 9, "压不住：士气不变 9")
	_expect(fleet.mutiny_cooldown == 5, "压不住：冷却 5")

	# resolve 后冷却在，mutiny_ready 假
	_expect(not fleet.mutiny_ready(), "解决后冷却内不闹")

	_restore()
	_report()


func _reset(at_sea: bool, morale: int, cooldown: int) -> void:
	fleet.ships.clear()
	fleet.add_ship("keel_boat", "通济")
	fleet.water = 60
	fleet.food = 60
	fleet.morale = morale
	fleet.mutiny_cooldown = cooldown
	fleet.at_sea = at_sea
	gs.money = 1000
	gs.martial = 50


func _ready_ship() -> void:
	pass


func _restore() -> void:
	fleet.ships.clear()
	fleet.add_ship("keel_boat", "通济")
	fleet.water = 60
	fleet.food = 60
	fleet.morale = 70
	fleet.mutiny_cooldown = 0
	fleet.at_sea = false
	gs.money = 1000
	gs.martial = 50


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
	print("MUTINY_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
