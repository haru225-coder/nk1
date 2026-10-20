extends SceneTree
## lane w54-audio：登岸剿寨补挂的声（SfxCues 表里登岸两行）。一段钉一条，回退即红。
##   六期海战赢了、敌是海寇、船在宋土沿海，战后单子多一行「登岸剿寨」——原先下船打一仗、搜出钱货或折了人，一声不出，只有札记。
##   一、表：两行都在、标 added、各带 gap_ms，都是「一阵鼓、随后磬音」两层（得手上行、失手下行）。
##   二、真起 SeaChart（headless）按「收拾停当」：卡上只挂剿寨那一行、选「登岸剿寨」（_on_after_action_done → _landing_settle），
##       按种子让这一仗得手 / 失手各一回：得手记 landing_win 两层、失手记 landing_lose 两层，另一行不响；收队回船（hold）、
##       船上没富余的人可下（也走 _landing_settle、won 假）都不响——没下船就没有这一仗。
##   三、开关 sfx_cues 关：同一处真路记 off、不响；账照旧（得手照进钱）。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_landing_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_LANDING PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_LANDING"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const LR := preload("res://scripts/combat/LandingRaid.gd")

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _fleet: Node = null
var _gs: Node = null
var _clock := 8_000_000


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_fleet = root.get_node("Fleet")
	_gs = root.get_node("GameState")
	_Switches.reset()
	print("== 一、表")
	_sec_table()
	print("== 二、真起海图按「收拾停当」")
	await _sec_chart()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


func _fresh() -> void:
	_clock += 10_000
	_AUDIO.clock_ms = _clock
	_AUDIO.journal.clear()


static func _whys(hook: StringName) -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if StringName(r.get("hook", &"")) == hook:
			out.append(str(r.get("why", "?")))
	return out


func _sec_table() -> void:
	var ok := true
	for pair in [[&"landing_win", &"combat_win"], [&"landing_lose", &"combat_lose"]]:
		var row: Dictionary = _SFX.HOOKS.get(pair[0], {})
		var layers: Array = row.get("layers", [])
		ok = ok and bool(row.get("added", false)) and int(row.get("gap_ms", 0)) > 0 and layers.size() == 2 \
			and StringName(layers[0][0]) == &"combat_start" and StringName(layers[1][0]) == pair[1] and float(layers[1][2]) > 0.0
	_check(ok, "登岸两行在、标 added、各带 gap_ms：一阵鼓当下、磬音晚出（得手上行 / 失手下行）")


## 一条福船（中）50 人、士气 60、钱 1000（同 qa_w53_p6_landing_probe 十一节的摆法）
func _stage_fleet() -> void:
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "福船", "durability": 300.0,
		"max_durability": 300.0, "crew": 50, "sail_level": 1, "armor_level": 1, "cargo": {}}])
	_fleet.set("water", 0)
	_fleet.set("food", 0)
	_fleet.set("morale", 60)
	_gs.set("money", 1000)
	_gs.set("fame", 0)
	_gs.set("martial", 0)


## 头一个让这一战力赢（won = true）/ 输（won = false）的种子
func _seed_for(power: float, won: bool) -> int:
	for k in range(1, 4000):
		seed(k)
		if bool(LR.roll(power)["won"]) == won:
			return k
	return -1


## 按一次「收拾停当」：卡上只挂剿寨那一行、选 chosen；剿寨那一掷之前 SeaChart 不掷别的骰
func _press(sc: Node, chosen: String, k: int) -> void:
	var choices := LR.choices_for("win", {"event": "pirate"}, "quanzhou")
	seed(k)
	sc.call("_on_after_action_done", {"landing": chosen}, choices, {})


func _sec_chart() -> void:
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	sc.set("remaining_li", 50.0)  # 收尾的 _after_combat 见 remaining_li ≤ 0 当是到港：留一段航程
	_check(LR.choices_for("win", {"event": "pirate"}, "quanzhou").size() == 1, "战后单子挂出「登岸剿寨」那一行")
	for won in [true, false]:
		_stage_fleet()
		var power: float = LR.raid_power(LR.landing_party(int(_fleet.call("total_crew"))),
			float(_fleet.call("captain_power")), float(_fleet.call("morale_factor")))
		var k := _seed_for(power, won)
		_fresh()
		_press(sc, "raid", k)
		await create_timer(1.0).timeout
		var rep: Dictionary = sc.call("last_landing_report")
		var hook: StringName = &"landing_win" if won else &"landing_lose"
		var other: StringName = &"landing_lose" if won else &"landing_win"
		_check(bool(rep.get("won", not won)) == won and _whys(hook) == ["", ""] and _whys(other).is_empty(),
			"剿寨%s（种子 %d）：记 %s 两层、%s 不响（%s）" % ["得手" if won else "失手", k, hook, other, str(_whys(hook))])
	_stage_fleet()
	_fresh()
	_press(sc, "hold", 1)
	await create_timer(1.0).timeout
	_check(_whys(&"landing_win").is_empty() and _whys(&"landing_lose").is_empty(), "收队回船（hold）不响（%s / %s）" % [
		_whys(&"landing_win"), _whys(&"landing_lose")])
	# 船上没富余的人：layout 照 ok 真、won 假返回、照走 _landing_settle
	_stage_fleet()
	var ships: Array = _fleet.get("ships")
	ships[0]["crew"] = 0
	_fresh()
	_press(sc, "raid", 1)
	await create_timer(1.0).timeout
	_check(_whys(&"landing_win").is_empty() and _whys(&"landing_lose").is_empty(), "船上没人可下：寨子留在岸上，不响（%s / %s）" % [
		_whys(&"landing_win"), _whys(&"landing_lose")])
	print("== 三、开关 sfx_cues 关")
	_stage_fleet()
	var power2: float = LR.raid_power(LR.landing_party(int(_fleet.call("total_crew"))),
		float(_fleet.call("captain_power")), float(_fleet.call("morale_factor")))
	var kw := _seed_for(power2, true)
	_Switches.set_on(_SFX.SWITCH, false)
	_fresh()
	_press(sc, "raid", kw)
	await create_timer(1.0).timeout
	_Switches.reset()
	_check(_whys(&"landing_win") == ["off"] and int(_gs.get("money")) > 1000,
		"开关关：剿寨得手记 off、不响；账照旧（钱 1000 → %d）" % int(_gs.get("money")))
	sc.queue_free()
	await process_frame
