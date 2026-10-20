extends SceneTree
## lane w54-hunt 剿寨那一行挂卡判据探针（headless，经 glock 跑；真起 SeaChart、真走 _on_battle_result）。
##   godot --headless --path . -s res://tools/qa_w54_hunt_landing_offer_probe.gd
## 来由：w54-polish 记在 COORDINATION 的一条（交本 lane）——胜局 _on_battle_result 先调 _after_action_offer 挂战后小卡、
## 后才扣这一仗的 source 与所在港（_landing_src / _landing_port），而挂卡判「登岸剿寨」那一行读的正是这两样：
## 窗口下头一回打赢海寇那一行不挂，之后按上一仗是不是海寇、上一仗停在哪港判。headless 下卡不挂（attach_after_action 返 null），
## qa_w53_p6_landing_probe 只核收战后扣住的两样，测不出先后。
## 本探针现编一个 SeaChart 的子类（只在内存里，不落盘），覆写 _after_action_offer：进来那一刻记下它读到的两样，再照原样调回父类——
## 走的仍是 SeaChart 自己的 _on_battle_result 与挂卡判据，只多一双眼睛看「挂卡那一刻读到的是哪一仗」。
##   一、头一仗：泉州外打赢海寇——挂卡那一刻读到的就是这一仗（海寇、泉州），剿寨那一行挂得上。
##   二、第二仗：泉州外打赢元军哨船——读到的是这一仗（元军哨船），那一行不挂（不沿用上一仗的海寇）。
##   三、第三仗：博多外打赢海寇——读到的所在港是博多（不在宋土沿海），那一行不挂（不沿用上一仗的泉州）。
## 判词：末行 QA_W54_HUNT_LANDING_OFFER PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_HUNT_LANDING_OFFER"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## SeaChart 的探针子类：覆写挂卡入口，进来那一刻记下读到的来处与所在港，再调回父类原样挂卡
const SPY_SRC := """extends "res://scripts/SeaChart.gd"

var spy: Array = []


func _after_action_offer(outcome: String, data: Dictionary) -> void:
	spy.append({"src": _landing_src.duplicate(), "port": _landing_port})
	super(outcome, data)
"""

var _LR = null
var _gm: Node = null
var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_LR = load("res://scripts/combat/LandingRaid.gd")
	_gm = root.get_node("GameManager")
	var spy_script := GDScript.new()
	spy_script.source_code = SPY_SRC
	var err := spy_script.reload()
	_check(err == OK, "SeaChart 探针子类编得过（err=%d）" % err)
	if err != OK:
		_report()
		return
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	sc.set_script(spy_script)
	root.add_child(sc)
	await process_frame
	await process_frame
	# 收尾的 _after_combat 见 remaining_li ≤ 0 当是到港（到港换场景）：留一段航程，船又没在走，_sail_next_day 当即返回
	sc.set("remaining_li", 50.0)

	print("== 一、头一仗：泉州外打赢海寇")
	await _fight(sc, "quanzhou", {"scene": "SeaChart", "event": "pirate"})
	var a := _last(sc)
	_check(str((a.get("src", {}) as Dictionary).get("event", "")) == "pirate" and str(a.get("port", "")) == "quanzhou",
		"挂卡那一刻读到的就是这一仗：海寇、泉州（读到 %s）" % JSON.stringify(a))
	_check(not (_LR.choices_for("win", a.get("src", {}), str(a.get("port", ""))) as Array).is_empty(),
		"头一回打赢海寇、船在宋土沿海：剿寨那一行挂得上")

	print("== 二、第二仗：泉州外打赢元军哨船")
	await _fight(sc, "quanzhou", {"scene": "SeaChart", "event": "yuan_patrol"})
	var b := _last(sc)
	_check(str((b.get("src", {}) as Dictionary).get("event", "")) == "yuan_patrol",
		"挂卡那一刻读到的是这一仗的元军哨船，不是上一仗的海寇（读到 %s）" % JSON.stringify(b))
	_check((_LR.choices_for("win", b.get("src", {}), str(b.get("port", ""))) as Array).is_empty(),
		"打赢元军哨船：剿寨那一行不挂")

	print("== 三、第三仗：博多外打赢海寇")
	await _fight(sc, "hakata", {"scene": "SeaChart", "event": "pirate"})
	var c := _last(sc)
	_check(str(c.get("port", "")) == "hakata", "挂卡那一刻读到的所在港是博多，不是上一仗的泉州（读到 %s）" % JSON.stringify(c))
	_check((_LR.choices_for("win", c.get("src", {}), str(c.get("port", ""))) as Array).is_empty(),
		"博多不在宋土沿海：剿寨那一行不挂")

	_check((sc.get("spy") as Array).size() == 3, "三仗各挂一回卡（挂卡入口进了 %d 回）" % (sc.get("spy") as Array).size())
	sc.queue_free()
	await process_frame
	_report()


## 摆一仗：船停在 port（起锚港 = 所在港，未定去向）、pending_battle 写这一仗的来处，走 SeaChart._on_battle_result 收一场胜仗
func _fight(sc: Node, port: String, source: Dictionary) -> void:
	sc.set("origin_port", port)
	sc.set("selected_port", "")
	sc.set("total_li", 0.0)
	_gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "外海", "source": source.duplicate()})
	sc.call("_on_battle_result", "win", {"player_damage": 5.0, "fates": [{"type": "pirate_boat", "fate": "sunk", "count": 2}]})
	await process_frame
	await process_frame


static func _last(sc: Node) -> Dictionary:
	var spy: Array = sc.get("spy")
	return spy[spy.size() - 1] if not spy.is_empty() else {}
