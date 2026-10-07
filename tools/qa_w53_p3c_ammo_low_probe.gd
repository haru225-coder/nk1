extends SceneTree
## lane-w53-p3c 敌将「弹药告急」回归专项探针（headless）：钉住 EnemyCaptainAI 弹药告急那条路
## （AMMO_LOW / ammo_frac / 告急时 fire_side 收近射程 SAVE_RANGE / 守进惜弹射距 / 弹尽 + 劣势按各档案
## desperate 决断贴或走），在第三期开关（enemy_flood_fire、fire_attack_load）开 / 关两态下逐格对账——
## 三期不许碰这条路（COMMON 硬规矩）；本探针只读 EnemyCaptainAI.gd 与 CombatSwitches.gd，一个产品文件不改。
## 逐节（每节先归置开关跑一遍、开关还原后再直线跑第二遍，两遍结论须逐字一致）：
##   一、常量口径：AMMO_LOW = 0.25、SAVE_RANGE = 360.0（改数同改路，先钉死）。
##   二、ammo_frac：volleys 3/4 → 0.75、volleys 0 → 0.0；volleys_max = 0 兜底 1.0。
##   三、fire_side 惜弹收射程：满弹 500 进 FIRE_RANGE 要放；余一轮（0.25）后 500 不放、320 照放
##       （侧舷 90°、北海无风修正）；还填满弹照样放。
##   四、守进惜弹射距：矢石将尽（一轮）又不够拼接舷，相距 400 守的船要往敌船靠（船首向敌分量 > 0.15）；
##       满弹同位横着守（|分量| < 0.05）。
##   五、弹尽 + 劣势各档案定：哨船（desperate 1.3，比 1.0）弹尽按「矢石告罄」走 DISENGAGE；
##       海寇（0.85，比 1.0）弹尽改贴 BOARD；默认档（1.0，比 0.5）弹尽也走。
##   六、tick 快照：局势侧 ammo 键回写的就是 ammo_frac 自己（接线不漂）。
##   七、self_check：敌将自带的自检链在两态下都全过（兜底：哪里先走样这里先红）。
## 判词：QA_W53_P3C_AMMO_LOW PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。
## 用法：godot --headless --path . -s res://tools/qa_w53_p3c_ammo_low_probe.gd
## 附（回退验证）：把 EnemyCaptainAI.save_low_branch（fire_side 里那句 rng = minf(rng, SAVE_RANGE)）直删，
##   第三节 on/off 同红；开关两态逐字一致是本探针立着的意义——动了那条路，先在这里红。

const TAG := "QA_W53_P3C_AMMO_LOW"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _AI := preload("res://scripts/combat/EnemyCaptainAI.gd")

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
	var keys := ["enemy_flood_fire", "fire_attack_load"]
	for k in keys:
		_Switches.set_on(k, true)
	print("== 三期开关开（%s 全开）" % "、".join(keys))
	var on := _run_all("on")
	_Switches.reset()
	print("== 三期开关关（总表还原，两键照旧默认但本格按关态复跑）")
	for k in keys:
		_Switches.set_on(k, false)
	var off := _run_all("off")
	for k in keys:
		_Switches.set_on(k, true)
	var on2 := _run_all("on-复跑")
	_check(on == on2, "开关开态两遍自比逐字一致（复跑 %d 格）" % on2.size())
	_Switches.reset()
	_Switches.reset()
	OS.remove_logger(_errlog)
	_check(on == off, "弹药告急各节两态结论逐字一致（on %d 格 / off %d 格）" % [on.size(), off.size()])
	_check(on.size() == 6 and off.size() == 6, "两态各跑满 6 格标记（on %d / off %d）" % [on.size(), off.size()])
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


## 全七节跑一遍；返回各节一句话标记（开 / 关比对用，判红在 _check 里落了账的节标记带 ✗）
func _run_all(tag: String) -> Array:
	var sig: Array = []
	sig.append(_sec_consts(tag))
	sig.append(_sec_ammo_frac(tag))
	sig.append(_sec_save_range(tag))
	sig.append(_sec_hold_range(tag))
	sig.append(_sec_desperate(tag))
	sig.append(_sec_self_check(tag))
	return sig


## 假局势：敌（玩家）在原点、船首朝北；北风 80；我 60 人满员满血——同 EnemyCaptainAI._sit 的口径，
## 本探针不复用那边的私有 static（那是人家自检的件），这里自己立一份公开读法。
func _sit(over: Dictionary) -> Dictionary:
	var s := {
		"pos": Vector2(0, -400), "heading": Vector2.RIGHT, "vel": Vector2.ZERO, "max_speed": 250.0,
		"target_pos": Vector2.ZERO, "target_vel": Vector2(0, -60), "target_heading": Vector2.UP,
		"target_max_speed": 300.0, "target_hull": 1.0,
		"wind": Vector2(0, 1), "wind_strength": 80.0, "current": Vector2.ZERO,
		"hull": 1.0, "crew": 60, "morale": 60, "own_strength": 50.0, "target_strength": 50.0,
		"consorts": 0, "consorts_gone": 0, "consorts_struck": 0, "host_boarding": false, "frozen": false,
	}
	for k in over:
		s[k] = over[k]
	return s


func _fresh(ship_type := "fu_ship_medium", morale0 := 60.0):
	var ai = _AI.new()
	ai.force_builtin()
	ai.setup(ship_type, ship_type, 1.0, 60, morale0, 2)
	return ai


func _sec_consts(tag: String) -> String:
	var ok: bool = is_equal_approx(float(_AI.AMMO_LOW), 0.25) and is_equal_approx(float(_AI.SAVE_RANGE), 360.0)
	_check(ok, "一［%s］常量口径：AMMO_LOW = %.2f（须 0.25）、SAVE_RANGE = %.0f（须 360）" % [
		tag, float(_AI.AMMO_LOW), float(_AI.SAVE_RANGE)])
	return "consts:%.2f/%.0f" % [float(_AI.AMMO_LOW), float(_AI.SAVE_RANGE)]


func _sec_ammo_frac(tag: String) -> String:
	var ai = _fresh()
	var full := ai.ammo_frac()  # volleys = volleys_max ⇒ 1.0
	var bad: Array = []
	if not is_equal_approx(full, 1.0):
		bad.append("满弹 %.3f ≠ 1" % full)
	ai.volleys = int(roundi(float(ai.volleys_max) * 0.75))  # 3/4 轮（4 轮档案 → 3；5 轮档案 → 4，按 0.75 就近取整）
	var three_q := ai.ammo_frac()
	var want_q := float(ai.volleys) / float(maxi(ai.volleys_max, 1))
	ai.volleys = 0
	var dry := ai.ammo_frac()
	ai.volleys_max = 0
	var edge := ai.ammo_frac()
	if not is_equal_approx(three_q, want_q):
		bad.append("四分三轮 %.3f ≠ 口径 %.3f（volleys_max %d 取 %d 轮）" % [three_q, want_q, ai.volleys_max, ai.volleys])
	if not is_equal_approx(dry, 0.0):
		bad.append("弹尽 %.3f ≠ 0" % dry)
	if not is_equal_approx(edge, 1.0):
		bad.append("volleys_max = 0 兜底 %.3f ≠ 1" % edge)
	_check(bad.is_empty(), "二［%s］ammo_frac：满弹 1 · 四分三轮 %.2f（按档取轮）· 弹尽 0 · 零轮兜底 1%s" % [
		tag, want_q, "" if bad.is_empty() else "——" + "；".join(bad)])
	return "frac:%.2f/%.2f/%.2f/%.2f" % [full, three_q, dry, edge]


func _sec_save_range(tag: String) -> String:
	# 侧舷正 90°、北风 80：FIRE_RANGE = 500 往上够得着；惜弹（≤ 0.25）收到 SAVE_RANGE = 360 内才放
	var ai = _fresh()
	var far_full := ai.fire_side(PI * 0.5, 500.0)
	ai.volleys = 1  # 档案 4 轮 → 余一轮 = 0.25，恰好压着 AMMO_LOW 线（即惜弹态）
	var far_low := ai.fire_side(PI * 0.5, 500.0)
	ai = _fresh()
	ai.volleys = 1
	var near_low := ai.fire_side(PI * 0.5, 320.0)
	ai = _fresh()
	var near_full := ai.fire_side(PI * 0.5, 320.0)
	_check(far_full != 0 and far_low == 0 and near_low != 0 and near_full != 0,
		"三［%s］惜弹收射程：满弹 500 放（得 %d）、余一轮 500 不放（得 %d）、余一轮 320 照放（得 %d）、满弹 320 放（得 %d）" % [
			tag, far_full, far_low, near_low, near_full])
	return "save:%d>%d|%d|%d" % [far_full, far_low, near_low, near_full]


func _sec_hold_range(tag: String) -> String:
	# 守舷炮位的射距带：满弹在带内横着守不靠（|船首向敌分量| < 0.05）；矢石将尽收进惜弹射距，相距 400 要往敌船靠（> 0.15）
	var ai = _fresh()
	var o: Dictionary = ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 40.0}), 0.1)
	var hold := (o["heading"] as Vector2).dot(Vector2(0, 1))
	ai = _fresh()
	ai.volleys = 1
	o = ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 40.0}), 0.1)
	var close_in := (o["heading"] as Vector2).dot(Vector2(0, 1))
	_check(ai.state == _AI.BROADSIDE and close_in > 0.15 and absf(hold) < 0.05,
		"四［%s］守进惜弹射距 %d：矢石将尽相距 400 往敌船靠（分量 %.2f 须 > 0.15）；满弹横守（分量 %.2f 须 |·| < 0.05）" % [
			tag, int(_AI.SAVE_RANGE), close_in, hold])
	return "hold:%.3f>%.3f" % [close_in, hold]


func _sec_desperate(tag: String) -> String:
	# 弹尽 + 劣势（比够不上本档案拼接舷的线 desperate）：哨船 1.3 走、海寇 0.85 贴、默认档 1.0 比 0.5 也走
	var ai = _fresh("yuan_patrol")
	ai.volleys = 0
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	var patrol := "%s|%s" % [ai.state, ai.reason]
	ai = _fresh("pirate_boat")
	ai.volleys = 0
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	var pirate := "%s|%s" % [ai.state, ai.reason]
	ai = _fresh()  # 默认档 fu_ship_medium：desperate 1.0，own 40 / target 50 比 0.8 < 1.0 → 走
	ai.volleys = 0
	ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 40.0}), 0.1)
	var dflt := "%s|%s" % [ai.state, ai.reason]
	var bad: Array = []
	if not (patrol.begins_with(str(_AI.DISENGAGE) + "|") and patrol.find("矢石告罄") >= 0):
		bad.append("哨船弹尽劣势须按「矢石告罄」脱离，得 %s" % patrol)
	if not pirate.begins_with(str(_AI.BOARD) + "|"):
		bad.append("海寇弹尽够得上线须改贴，得 %s" % pirate)
	if not dflt.begins_with(str(_AI.DISENGAGE) + "|"):
		bad.append("默认档弹尽比 0.8 < 1.0 须走，得 %s" % dflt)
	_check(bad.is_empty(), "五［%s］弹尽 + 劣势决断分档案：哨船走 / 海寇贴 / 默认档走（%s）%s" % [
		tag, "；".join([patrol, pirate, dflt]), "" if bad.is_empty() else "——" + "；".join(bad)])
	return "dry:%s#%s#%s" % [patrol, pirate, dflt]


func _sec_self_check(tag: String) -> String:
	var gold: GDScript = load("res://scripts/combat/EnemyCaptainAI.gd")  # const 类绑定上 call() 限实例，走 GDScript 资源调 static（同 qa_w53_2 第十节的写法）
	var has_fn := gold != null and gold.has_method("self_check")
	var bad: Array = gold.call("self_check") if has_fn else ["self_check 不在"]
	_check(bad.is_empty(), "六、［%s］self_check 敌将自检链全过（%s）" % [tag,
		"0 条不合" if bad.is_empty() else "；".join(bad)])
	return "self:%d" % bad.size()


class _ScriptErrLog extends Logger:
	var lines: Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == 1:  # ERROR_TYPE_SCRIPT_ERROR
			lines.append(code)
