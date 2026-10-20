extends SceneTree
## lane w54-hunt 闯封锁与在身委办探针（headless，经 glock 跑；真起 SeaChart 走 _run_sell / _run_seize）。
##   godot --headless --path . -s res://tools/qa_w54_hunt_run_contract_probe.gd
## 口径：在身委办要留着交货的米不上秤（牙行卖钮、守城押粮入城都按 GameState.contract_kept 扣掉）。闯封锁原先不分，
## 一趟把委办要的米也一起卖了、被扣被抛时也一样赔进去——委办再没有米可交，只剩毁约一条路。
##   一、舱里米 20、委办要 8：闯进兴化卖粮，只卖 12 件、得 12 × 围城米价；舱里留 8 件（够交货），札记写「在身委办要留」。
##   二、舱里米 20、委办要 8：闯输 / 掉头被扣，扣的也是要卖的那 12 件，委办要留的 8 件还在舱里。
##   三、舱里的米全是在身委办要留的：这个港就不算闯得（_run_offerable 假），点它只给「港已封」。
## 判词：末行 QA_W54_HUNT_RUN_CONTRACT PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_HUNT_RUN_CONTRACT"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var gs: Node = null
var eco: Node = null
var fleet: Node = null
var cal: Node = null
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
	gs = root.get_node("GameState")
	eco = root.get_node("Economy")
	fleet = root.get_node("Fleet")
	cal = root.get_node("Calendar")
	print("== 一、闯进兴化卖粮：委办要留的米不上秤")
	await _sec_sell()
	print("== 二、被扣 / 掉头：赔进去的也只是要卖的那批")
	await _sec_seize()
	print("== 三、舱里全是委办要留的米：不算闯得")
	await _sec_offer()
	_report()


## 摆一局：1276 冬兴化被围、福船一条、舱里 grain_qty 件米，in 身委办要 keep 件（keep = 0 则无委办）
func _stage(grain_qty: int, keep: int) -> Node:
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "旗舰", "durability": 300.0, "max_durability": 300.0,
		"crew": 60, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	fleet.set("water", 50)
	fleet.set("food", 50)
	fleet.set("morale", 60)
	gs.set("money", 1000)
	gs.set("fame", 0)
	gs.set("contract", {})
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	if grain_qty > 0:
		fleet.call("add_cargo", "grain", grain_qty, 5.0)
	if keep > 0:
		gs.set("contract", {"good_id": "grain", "qty": keep, "remaining": keep, "dest": "fuzhou", "from": "quanzhou",
			"purse": keep * 25, "unit_purse": 25.0, "paid": 0, "due_day": 999999, "deadline_days": 10,
			"voyage_days": 3, "offer_month": 1276 * 12 + 11})
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	# 收尾的 _after_combat 见 remaining_li ≤ 0 当是到港：留一段航程，船没在走，_sail_next_day 当即返回
	sc.set("remaining_li", 50.0)
	sc.set("origin_port", "quanzhou")
	sc.set("selected_port", "xinghua")
	sc.set("_run_port", "xinghua")
	return sc


func _teardown(sc: Node) -> void:
	if sc != null and is_instance_valid(sc):
		sc.set("sailing", false)
		sc.queue_free()
	await process_frame


func _sec_sell() -> void:
	var sc: Node = await _stage(20, 8)
	_check(str(eco.call("war_status", "xinghua")) == "besieged", "兴化正被围（besieged）")
	_check(int(gs.call("contract_kept", "grain")) == 8, "在身委办要留米 8 件")
	_check(bool(sc.call("_run_offerable", "xinghua")), "舱里有可卖的米：闯得")
	var unit := float(eco.call("blockade_grain_unit", "xinghua"))
	sc.call("_run_sell")
	await process_frame
	var left := int(fleet.call("cargo_qty", "grain"))
	_check(left == 8, "只卖要卖的那 12 件：舱里留 8 件（得 %d）" % left)
	_check(int(gs.get("money")) == 1000 + int(round(unit * 12.0)),
		"钱匣按 12 件 × 围城米价 %.2f 进账（1000 → %d，应 %d）" % [unit, int(gs.get("money")), 1000 + int(round(unit * 12.0))])
	_check(int(gs.call("contract_kept", "grain")) == 8, "委办那 8 件的货还在舱里，交得出去")
	var note := str(sc.get("_latest_note"))
	_check(note.contains("米粮 12 件") and note.contains("在身委办要留"), "札记写清卖了几件、余下的是委办要留的（「%s」）" % note)
	await _teardown(sc)


func _sec_seize() -> void:
	for how in ["lose", "yield"]:
		var sc: Node = await _stage(20, 8)
		sc.set("_run_port", "xinghua")
		sc.call("_run_seize", how)
		await process_frame
		var left := int(fleet.call("cargo_qty", "grain"))
		_check(left == 8, "（%s）赔进去的是要卖的 12 件：委办要留的 8 件还在舱里（得 %d）" % [how, left])
		_check(int(gs.call("contract_kept", "grain")) == 8, "（%s）委办那 8 件交得出去" % how)
		await _teardown(sc)


func _sec_offer() -> void:
	var sc: Node = await _stage(8, 8)
	_check(int(fleet.call("cargo_qty", "grain")) == 8 and int(gs.call("contract_kept", "grain")) == 8,
		"舱里 8 件全是委办要留的")
	_check(not bool(sc.call("_run_offerable", "xinghua")), "没有可卖的米：这个港不算闯得（不给「闯封锁」）")
	var take: Array = sc.call("_run_take", "xinghua")
	_check(int(take[0]) == 0 and int(take[1]) == 0, "城里一件也收不到（%s）" % str(take))
	await _teardown(sc)
