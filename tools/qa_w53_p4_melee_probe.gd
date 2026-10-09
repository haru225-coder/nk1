extends SceneTree
## lane-w53-p4-melee 白刃三决断 + 追窗口探针（headless，秒级；回退即红）。
##   一、MeleeResolve 决断口径：压上 / 收势簿直入（strength / 伤亡折扣 / 推进阈值）——
##       三场档位（双方均势 60v60）：全收势收场（fights 满合占比升、总归阵亡降）对全压上；
##       自动口径拍拍 push 偏密（士气 70 对 60 这条跟强度无关、跟立场有关）。
##   二、超时默认：decision_cb 恒返回 null（= WorldMap 那一路亮拍无果）→ 结果里决断段照自动落，
##       decisions[].how = "自动"；关开关 melee_decision：ctx 里 decisions 打开、resolve 照旧自动收（开关的关态实证）。
##   三、decision_cb 玩家择路：q_press Space = 压上这拍一进决局面即知（探针同段不落两难）；
##       三段都拍 收势 → 推进阈值抬高、合数拉长（对一段收势 60；how="择"）。
##   四、追窗口（EnemyCaptainAI，假局势照 EnemyCaptainAI._sit）：s.pursue_window=true/false 对——
##       脱节线 1500/1760 上前一拍 leave=false；逃速对 can_escape::hull 0.2 重伤：
##       开窗口被咬住（strike）多过旧径。窗口关 = 逐字旧（同 s 一场账一字不差）。
##   五、CombatSwitches 两新键默认开、关掉只动本 lane 线：melee_decision / pursue_window on() 默认 true。
## 用法：godot --headless --path . -s res://tools/qa_w53_p4_melee_probe.gd
## 判词：QA_W53_P4_MELEE_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const Melee := preload("res://scripts/combat/MeleeResolve.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const ECAI := preload("res://scripts/combat/EnemyCaptainAI.gd")
const TAG := "QA_W53_P4_MELEE_PROBE"

var _fails: Array = []
var _errlog: _ScriptErrLog = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame

	print("== 一、MeleeResolve 决断口径（压上 / 收势直入）")
	_sec_strength()
	print("== 二、超时默认 + 开关关逐字回旧")
	_sec_timeout_and_off()
	print("== 三、decision_cb 玩家择路（收势拉长、账记「择」）")
	_sec_decided_path()
	print("== 四、追窗口（EnemyCaptainAI 假局势）")
	_sec_pursue()
	print("== 五、CombatSwitches 两新键默认开")
	_sec_switches()

	OS.remove_logger(_errlog)
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)


func _ctx(over := {}) -> Dictionary:
	# 均势场：双方 60 人、土气 60、横风微浪；钩已挂牢（直探甲板——决断在甲板段里停，不是钩索里）
	var c := {"hooked": true, "seed": 0, "windward": 0, "sea": 1, "rel_speed": 0.0, "distance": 60.0}
	for k in over:
		c[k] = over[k]
	return c


func _sides(over_att := {}, over_def := {}) -> Array:
	var att := {"crew": 60, "morale": 60, "captain": 1.0, "type": "keel_boat", "is_player": true}
	var def := {"crew": 60, "morale": 60, "captain": 1.0, "type": "pirate_boat"}
	for k in over_att:
		att[k] = over_att[k]
	for k in over_def:
		def[k] = over_def[k]
	return [att, def]


func _sec_strength() -> void:
	# 收势满场 vs 压上满场（各 300 种子）：收势收场——合数拉长、总归阵亡降、打满合数两下罢手更多
	var runs := 300
	var hold_rounds := 0.0
	var hold_dead := 0
	var hold_full := 0
	var push_rounds := 0.0
	var push_dead := 0
	var push_full := 0
	for i in runs:
		var sd: Array = _sides()
		var ch := _ctx({"decisions": [0, 0, 0]})
		ch["seed"] = 41 + i
		var rh: Dictionary = Melee.resolve(sd[0], sd[1], ch)
		hold_rounds += float(rh["rounds_fought"])
		hold_dead += int(rh["att_dead"]) + int(rh["def_dead"])
		if int(rh["rounds_fought"]) >= 6 and str(rh["outcome"]) == Melee.OUTCOME_CUT_LOOSE:
			hold_full += 1
		ch = _ctx({"decisions": [1, 1, 1]})
		ch["seed"] = 41 + i
		var rp: Dictionary = Melee.resolve(sd[0], sd[1], ch)
		push_rounds += float(rp["rounds_fought"])
		push_dead += int(rp["att_dead"]) + int(rp["def_dead"])
		if int(rp["rounds_fought"]) >= 6 and str(rp["outcome"]) == Melee.OUTCOME_CUT_LOOSE:
			push_full += 1
	hold_rounds /= runs
	push_rounds /= runs
	_check(hold_rounds > push_rounds, "收势：合数拉长（%.2f 合 > 压上 %.2f 合）" % [hold_rounds, push_rounds])
	_check(hold_dead < push_dead, "收势：总归阵亡少（%d 人 < 压上 %d 人）" % [hold_dead, push_dead])
	_check(hold_full > push_full, "收势：打满合数两下罢手更多（%d / 300 场对压上 %d / 300 场）" % [hold_full, push_full])


func _sec_timeout_and_off() -> void:
	# 超时默认：decision_cb 返回 null（WorldMap 决策层没亮拍 / 顶掉）→ 决断段照「开战拍定簿」走、账不记「择」——
	# 与「玩家在二层探记里没拍板」一回事：不注字（注字记的是玩家那点事，自动全顺的没有）
	var sd: Array = _sides()
	var c := _ctx({"decision_cb": func(_out: Dictionary, _left: Array) -> Variant: return null, "player_decides": true})
	c["seed"] = 1123
	var r: Dictionary = Melee.resolve(sd[0], sd[1], c)
	var n_chosen := 0
	for d in r.get("decisions", []):
		if str(d.get("how", "")) == "择":
			n_chosen += 1
	_check(str(r.get("outcome", "")) != "", "超时一路照常收战（了局 %s）" % str(r.get("outcome", "")))
	_check(n_chosen == 0, "超时默认：决断段照开战拍定簿走、账不记「择」（%d 段记 / 共 %d 段）" % [
		n_chosen, (r.get("decisions", []) as Array).size()])
	# 与自动一路同源同式：同 seed 不挂 cb 重打一场要一字不差（null 一路的字、掷骰序 = 自动一路）
	var plain: Dictionary = Melee.resolve(sd[0], sd[1], _ctx({"seed": 1123}))
	var plain_match := int(r["att_dead"]) == int(plain["att_dead"]) and int(r["def_dead"]) == int(plain["def_dead"]) \
		and int(r["rounds_fought"]) == int(plain["rounds_fought"]) and str(r["outcome"]) == str(plain["outcome"])
	_check(plain_match, "超时默认：照「裸自动」场一字不差（了局 %s、攻死 %d / 守死 %d、%d 合）" % [
		str(r.get("outcome", "")), int(r.get("att_dead", 0)), int(r.get("def_dead", 0)), int(r.get("rounds_fought", 0))])
	# 开关关 = 逐字旧白刃：整块决断代码跳过——ctx 里直供博弈簿也一枚骰不多掷（掷骰序照旧、账内零决断段）
	var was := Switches.on("melee_decision")
	Switches.set_on("melee_decision", false)
	var sd2: Array = _sides()
	var c2 := _ctx({"decisions": [1, 1, 1]})
	c2["seed"] = 901
	var off_a: Dictionary = Melee.resolve(sd2[0], sd2[1], c2.duplicate())
	var off_plain: Dictionary = Melee.resolve(sd2[0], sd2[1], {"hooked": true, "seed": 901, "windward": 0, "sea": 1})
	Switches.set_on("melee_decision", was)
	# off 两路同掷骰序（塞关节照关 = 逐字旧）：off_a 与 off_plain 一字不差；on（同一 ctx）应与 off_plain 差——三路出数对账
	_check(int(off_a["att_dead"]) == int(off_plain["att_dead"]) and int(off_a["def_dead"]) == int(off_plain["def_dead"])
		and int(off_a["rounds_fought"]) == int(off_plain["rounds_fought"]) and str(off_a["outcome"]) == str(off_plain["outcome"])
		and (off_a.get("decisions", []) as Array).is_empty(),
		"开关 melee_decision 关 = 逐字旧白刃（同 seed ctx 塞决断簿：了局 %s、攻死 %d / 守死 %d、%d 合 与关开关裸场一字不差，账内零决断段）" % [
			str(off_a.get("outcome", "")), int(off_a.get("att_dead", 0)), int(off_a.get("def_dead", 0)), int(off_a.get("rounds_fought", 0))])


func _sec_decided_path() -> void:
	# 玩家收势三段 vs 自动（各 300 种子）：收势推进阈值抬高 → 各回合都更磨（合数更长、攻方得更慢夺舵）
	var sd: Array = _sides()
	var hold_c := _ctx({"decisions": [0, 0, 0]})
	var ctrl_hold := {"rounds": 0.0, "helm": 0, "repelled": 0}
	var ctrl_push := {"rounds": 0.0, "helm": 0, "repelled": 0}
	for i in 300:
		for cfg in [[{"decisions": [0, 0, 0]}, ctrl_hold], [{"decisions": [1, 1, 1]}, ctrl_push]]:
			var c := _ctx(cfg[0])
			c["seed"] = 307 + i
			var r: Dictionary = Melee.resolve(sd[0], sd[1], c)
			(cfg[1] as Dictionary)["rounds"] = float(cfg[1]["rounds"]) + float(r["rounds_fought"])
			if str(r["outcome"]) == Melee.OUTCOME_CAPTURE or str(r["outcome"]) == Melee.OUTCOME_SURRENDER:
				(cfg[1] as Dictionary)["helm"] = int(cfg[1]["helm"]) + 1
			if str(r["outcome"]) == Melee.OUTCOME_REPELLED:
				(cfg[1] as Dictionary)["repelled"] = int(cfg[1]["repelled"]) + 1
	ctrl_hold["rounds"] = float(ctrl_hold["rounds"]) / 300.0
	ctrl_push["rounds"] = float(ctrl_push["rounds"]) / 300.0
	# 收势：合数仍长（each juncture 阈值抬到 0.5）；与一节的 60v60 满场合数比对一路收，不抄数
	_check(float(ctrl_hold["rounds"]) > float(ctrl_push["rounds"]),
		"玩家收势三段：照样收势的模（%.2f 合 > 压上 %.2f 合）" % [float(ctrl_hold["rounds"]), float(ctrl_push["rounds"])])
	# 收势 / 压上各 300 场：两档收场取向要有差距——压上夺船（攻上舵楼）更密、收势更易打满被砍缆
	var hold_full := 0
	var push_full := 0
	for i in 300:
		var ch := _ctx({"decisions": [0, 0, 0]})
		ch["seed"] = 607 + i
		var rh: Dictionary = Melee.resolve(sd[0], sd[1], ch)
		if int(rh.get("rounds_fought", 0)) >= 6 and str(rh.get("outcome", "")) == Melee.OUTCOME_CUT_LOOSE:
			hold_full += 1
		var cp := _ctx({"decisions": [1, 1, 1]})
		cp["seed"] = 607 + i
		var rp: Dictionary = Melee.resolve(sd[0], sd[1], cp)
		if int(rp.get("rounds_fought", 0)) >= 6 and str(rp.get("outcome", "")) == Melee.OUTCOME_CUT_LOOSE:
			push_full += 1
	_check(hold_full > push_full, "收势更易打满合数两下罢手（%d / 300 场对压上 %d / 300 场）" % [hold_full, push_full])
	# 玩家择路记账（decision_cb 直给 0 = 收势）：how="择"、summary 带「收势（择）」
	var c2 := _ctx({"decision_cb": func(_out: Dictionary, _left: Array) -> Variant: return 0, "player_decides": true})
	c2["seed"] = 47
	var r2: Dictionary = Melee.resolve(sd[0], sd[1], c2)
	var n_choose := 0
	var n_junct := 0
	for d in r2.get("decisions", []):
		n_junct += 1
		if str(d.get("how", "")) == "择":
			n_choose += 1
	_check(str(r2.get("decisions_note", "")).find("收势（择）") >= 0,
		"玩家收势三段：summary 注照记（%s）" % str(r2.get("decisions_note", "")))
	_check(n_junct > 0 and n_choose == n_junct, "玩家收势三段：本段合拍全记「择」（%d / %d）" % [n_choose, n_junct])
	# 压上一段 vs 收势一段 —— 收势被反推的机会多，但两档百余场对收势照記即可；胜负账掷骰走路本缘量难度
	var slow_attack := 0
	for i in 120:
		var c3 := _ctx({"decisions": [0, -1, -1]})
		c3["seed"] = 990 + i
		var r3: Dictionary = Melee.resolve(sd[0], sd[1], c3)
		if int(r3.get("rounds_fought", 0)) >= 3:
			slow_attack += 1
	_check(slow_attack > 0, "收势开场一段：有拉长场（%d / 120 场打到第三合以后还在打）" % slow_attack)


func _sec_pursue() -> void:
	# EnemyCaptainAI 假局势：脱离线 1500/1760 前后一拍 leave 两态
	var sit := {"pos": Vector2(0, 0), "target_pos": Vector2(0, -1580.0), "morale": 20, "hull": 0.9,
		"own_strength": 40.0, "target_strength": 50.0}
	var ai := ECAI.new()
	ai.force_builtin()
	ai.setup("pirate_boat", "pirate_boat", 1.0, 60, 60.0, 2)
	var s1: Dictionary = ai._sit(sit)
	s1["pursue_window"] = false
	var out_off: Dictionary = ai.tick(s1, 0.3)
	# 1580 ≥ 1500：旧径直接离场
	_check(bool(out_off["leave"]), "追窗关：1580px 下旧径离场（leave=true）")
	ai = ECAI.new()
	ai.force_builtin()
	ai.setup("pirate_boat", "pirate_boat", 1.0, 60, 60.0, 2)
	s1 = ai._sit(sit)
	s1["pursue_window"] = true
	var out_on: Dictionary = ai.tick(s1, 0.3)
	_check(not bool(out_on["leave"]), "追窗开：1580px 还留场（离场线拖到 1760；leave=false）")
	# 开窗口也要出得去：1850 下照常离场（敌不困住）
	sit["target_pos"] = Vector2(0, -1850.0)
	s1 = ai._sit(sit)
	s1["pursue_window"] = true
	out_on = ai.tick(s1, 0.3)
	_check(bool(out_on["leave"]), "追窗开：1850px 照出得去（1760 已过；leave=true）")
	# 追窗关 = 逐字旧：会话末段的假场敌伤重却逃得脱（旧 self_check 同档：多桨船重创逃离应脱离）
	var sit3 := {"pos": Vector2(0, -400), "morale": 38.0, "hull": 0.2, "target_max_speed": 320.0}
	var b_off = _fresh("pirate_boat", 38.0)
	b_off.tick(_sit2(sit3, false), 0.1)
	var b_on = _fresh("pirate_boat", 38.0)
	b_on.tick(_sit2(sit3, true), 0.1)
	_check(b_off.state == ECAI.DISENGAGE, "多桨船重伤旧径逃得脱应脱离（得 %s）" % b_off.state)
	# 追窗挫速：can_escape 为假 → 同一伤重船被咬住（降幡）——窗口的「追得上的咬住、追不上的照走」就在这一拍分野
	_check(b_on.state == ECAI.STRIKE, "多桨船重伤追窗挫速被咬住应降幡（得 %s %s）" % [b_on.state, b_on.reason])


func _sec_switches() -> void:
	var a := Switches.on("melee_decision")
	var b := Switches.on("pursue_window")
	_check(a, "melee_decision 缺省开")
	_check(b, "pursue_window 缺省开")
	var was_a := Switches.on("melee_decision")
	Switches.set_on("melee_decision", false)
	var off_check := not Switches.on("melee_decision")
	Switches.set_on("melee_decision", was_a)
	_check(off_check and Switches.on("melee_decision") == was_a,
		"set_on(false) 关上、复回原态照旧缺省开（不改别人那几行；不动 reset，免得冲走别的 lane 临时键）")


# ── EnemyCaptainAI 假局势（同它 self_check 的 _sit 一套，只盖 pursue_window 一键；_fresh 照抄）──

func _sit2(over: Dictionary, pursue: bool) -> Dictionary:
	var s: Dictionary = ECAI._sit(over)
	s["pursue_window"] = pursue
	return s


func _fresh(ship_type := "fu_ship_medium", morale0 := 60.0):
	var ai = ECAI.new()
	ai.force_builtin()
	ai.setup(ship_type, ship_type, 1.0, 60, morale0, 2)
	return ai


## 本进程 SCRIPT ERROR 数（qa_w53_15_cut_probe 同款：判红格之一）
class _ScriptErrLog extends Logger:
	var lines: PackedStringArray = []

	func _log_message(message: String, error: bool) -> void:
		if error and (message.find("SCRIPT ERROR") >= 0 or message.find("Parse Error") >= 0):
			lines.append(message)

	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		lines.append("%s:%d %s %s" % [_file, line, code, rationale])
