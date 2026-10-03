extends SceneTree
## Lane ea3：headless 探针——市舶司验引 GameState.customs_duty 与牙行买价抽解吃同一套倍率。
## 期望值在这里按公式独立算（不调 Economy.duty_rate）：base_value × 件数 × tariff_rate
## × WAR_TARIFF[战况] × 站蒲家泉州 0.8 × 杂事 (1 − 0.12·级) × 职衔 duty_factor，地板 20，违禁不计。
## 修前 customs_duty 只乘职衔：平时光杆、职衔档不变，战况 / 站蒲家 / 杂事各档判红。
## 用法：godot --headless --path . -s res://tools/qa_customs_duty_probe.gd
## 输出末行 EA3_PROBE cases=N fails=M；M>0 时 exit 1。

## lane w53-3（四轮）：本进程 SCRIPT ERROR 即红——接共用件 tools/script_err_tally.gd（某段函数里出脚本错只中止那一个函数，
## 断言整段跳过、fails 不涨、headless -s 退出码守 0）；_run_guarded 包一层兜「_run 自己的代码行出错即中止、
## quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var eco: Node
var crew: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false

## 三档货值（与 docs/市舶验引与牙行抽解.md 对照表同）+ 一件违禁
const LOAD := {"tea": 10, "qingbai_porcelain": 10, "ivory": 10, "song_coin": 5}


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _report() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		cases += 1
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	eco = root.get_node_or_null("Economy")
	crew = root.get_node_or_null("Crew")
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	fleet = root.get_node_or_null("Fleet")
	if eco == null or crew == null or gs == null or gm == null or cal == null or fleet == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()
	var saved := {
		"hired": crew.hired.duplicate(true), "fame": gs.fame, "flags": gs.flags.duplicate(true),
		"last_port": gs.last_port, "ships": fleet.ships.duplicate(true),
		"y": cal.year, "m": cal.month, "d": cal.day,
	}
	fleet.ships = [{"cargo": {}}]
	for gid in LOAD:
		fleet.ships[0]["cargo"][gid] = {"qty": LOAD[gid], "avg_cost": 0.0}

	var top_fame := 0
	for r in gs.title_ranks():
		top_fame = maxi(top_fame, int(r.get("min_fame", 0)))

	# 港 × 年月 × 预期战况；闽粤、异国、无战况表各取一
	var spots := [
		["quanzhou", 1270, 1, "loyal"], ["quanzhou", 1276, 6, "contested"],
		["quanzhou", 1277, 1, "fallen"], ["wenzhou", 1276, 6, "fallen"],
		["hakata", 1274, 11, "closed"], ["penghu", 1277, 1, "loyal"],
	]
	for s in spots:
		cal.year = s[1]
		cal.month = s[2]
		cal.day = 1
		var st: String = eco.war_status(s[0])
		if st != s[3]:
			_fail("%s %d-%02d 战况 %s，预期 %s（ports.json 变了？）" % [s[0], s[1], s[2], st, s[3]])
		for pu in [false, true]:
			gs.flags = {"sided_pu": true} if pu else {}
			for z in range(4):
				# Crew.hired 只存名册 id（lane w23-a1 起）：塞整条快照读出来是 0 级，杂事三档整片假红（lane w53-3）
				crew.hired = {} if z == 0 else {"zashi": _cand("zashi", z)}
				if crew.level_of("zashi") != z:
					_fail("杂事没摆上：要 %d 级，Crew.level_of 读出 %d" % [z, crew.level_of("zashi")])
				for fame in [0, top_fame]:
					gs.fame = fame
					gs.last_port = s[0]
					_check(s[0], st, pu, z, "last_port")
					# 显式传港优先于 last_port
					gs.last_port = "penghu"
					_check(s[0], st, pu, z, "arg")

	# 空舱地板 20
	fleet.ships = [{"cargo": {}}]
	cases += 1
	if gs.customs_duty() != 20:
		_fail("空舱验引 %d，预期地板 20" % gs.customs_duty())

	crew.hired = saved["hired"]
	gs.fame = saved["fame"]
	gs.flags = saved["flags"]
	gs.last_port = saved["last_port"]
	fleet.ships = saved["ships"]
	cal.year = saved["y"]
	cal.month = saved["m"]
	cal.day = saved["d"]
	_report()


## 名册里该职该品级的第一位候选 id；没有这一级给个查不到的名，摆完判红
func _cand(role: String, level: int) -> String:
	for c in gm.crew_data.get("candidates", []):
		if str(c.get("role", "")) == role and int(c.get("level", 0)) == level:
			return str(c.get("id", ""))
	return "no_%s_%d" % [role, level]


func _expected(pid: String, st: String, pu: bool, z: int) -> int:
	var war_mul: float = float(eco.WAR_TARIFF.get(st, 1.0))
	if pu and pid == "quanzhou":
		war_mul *= 0.8
	var zashi := maxf(0.0, 1.0 - 0.12 * z)
	var title := float(gs.title_rank().get("duty_factor", 1.0))
	var total := 0.0
	for gid in LOAD:
		var g: Dictionary = gm.get_good_by_id(gid)
		if g.get("contraband", false):
			continue
		total += float(g.get("base_value", 0)) * LOAD[gid] * eco.tariff_rate * war_mul * zashi * title
	return maxi(20, int(round(total)))


func _check(pid: String, st: String, pu: bool, z: int, via: String) -> void:
	cases += 1
	if via == "arg" and gs.get_method_argument_count("customs_duty") == 0:
		_fail("customs_duty 不收 port_id（修前签名），显式传港无从验")
		return
	var got: int = gs.customs_duty() if via == "last_port" else gs.call("customs_duty", pid)
	var want := _expected(pid, st, pu, z)
	if got != want:
		_fail("%s %s 站蒲家=%s 杂事=%d 职衔=%s（%s）：验引 %d，预期 %d" % [
			pid, st, pu, z, gs.title_name(), via, got, want,
		])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		cases += 1
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("EA3_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)
