extends SceneTree
## lane w53-p5-siege 守城专项探针（headless，不截图；回退即红）。
##   一、陆战骰子搬家（Main._siege_nangshan → scripts/combat/SiegeMelee.gd）前后逐字一致：
##       1. 纯算：400 种子 × 三阵 × 八档战力，搬家前原式（本探针留一份 f443e6e8 的副本）与 SiegeMelee.nangshan
##          敌军数逐位相等、胜负相同，掷完下一枚 randf() 也相同（掷骰次数不变）；折兵 0–1500 人逐人相等。
##       2. 真走 Main：三档城防（必败 / 胜负参半 / 多胜）× 40 种子，每阵前同种子，Main._siege_nangshan 真打三阵，
##          与原式副本照原先次序落账的城防账（兵、粮、墙、士气、阵数、待结城破）和名声逐阵相等。
## 用法：godot --headless --path . -s res://tools/qa_w53_p5_siege_probe.gd
## 判词：逐条「  ✓ / ✗ 判词」，末行 QA_W53_P5_SIEGE_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const SiegeMelee := preload("res://scripts/combat/SiegeMelee.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W53_P5_SIEGE_PROBE"

## 纯算段的战力档：必败（<600）、卡在骰子边上、各阵胜负参半、第三阵上限（2100）两侧
const POWERS := [0.0, 599.9, 600.0, 900.0, 1200.0, 1500.0, 2015.4, 2100.0, 2500.0]
## 真走 Main 段的三档城防：[兵, 士气, 城墙, 石手军, 名声]
const PROFILES := [
	[300, 55, 60, "", 0],
	[700, 80, 150, "kept", 30],
	[1200, 90, 200, "kept", 60],
]

var _fails: Array = []
var _main: Node
var gs: Node
var cal: Node
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时不会走到 _report——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	print("%s_BEGIN" % TAG)
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	cal = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	_main = packed.instantiate() if packed != null else null
	if _main == null or _main.get_script() == null:
		_check(false, "Main.tscn 挂得出（根脚本无 Parse Error）")
		_report()
		return
	root.add_child(_main)
	for i in 6:
		await process_frame

	print("== 一、陆战骰子搬家前后一致（SiegeMelee 对 f443e6e8 原式副本）")
	_sec_move_pure()
	_sec_move_main()

	_stage_off()
	_report()


# ══ 一、搬家 ════════════════════════════════════════════════════════

## 搬家前 Main._siege_nangshan 的敌军骰与胜负（f443e6e8 原式，逐字抄下的对照副本）
func _old_roll(rd: int, power: float) -> Dictionary:
	var enemy := randf_range(600.0, 1400.0) * (1.0 + 0.25 * (rd - 1))
	var won := power >= enemy
	return {"enemy": enemy, "won": won}


func _sec_move_pure() -> void:
	var same := 0
	var diff := 0
	var wins := 0
	var losses := 0
	var after_diff := 0
	var first_bad := ""
	for s in 400:
		for rd in [1, 2, 3]:
			for p in POWERS:
				seed(9000 + s)
				var old := _old_roll(rd, float(p))
				var old_next := randf()
				seed(9000 + s)
				var now: Dictionary = SiegeMelee.nangshan(rd, float(p))
				var now_next := randf()
				if float(now["enemy"]) == float(old["enemy"]) and bool(now["won"]) == bool(old["won"]):
					same += 1
				else:
					diff += 1
					if first_bad == "":
						first_bad = "种子 %d 第 %d 阵 战力 %.1f：原式 %s / 新件 %s" % [9000 + s, rd, p, old, now]
				if now_next != old_next:
					after_diff += 1
				if bool(old["won"]):
					wins += 1
				else:
					losses += 1
	_check(diff == 0, "敌军数与胜负逐位相等（%d 格相等、%d 格不等%s）" % [same, diff, "；首格 " + first_bad if first_bad != "" else ""])
	_check(after_diff == 0, "掷完一阵后下一枚 randf() 相同——一阵仍只掷一次（%d 格不同）" % after_diff)
	_check(wins > 1000 and losses > 1000, "胜负两路都走到（胜 %d 格、败 %d 格）" % [wins, losses])
	var cas_bad := 0
	for t in range(0, 1501):
		if SiegeMelee.casualties(t, true) != int(t * 0.08) or SiegeMelee.casualties(t, false) != int(t * 0.22):
			cas_bad += 1
	_check(cas_bad == 0, "折兵 0–1500 人逐人相等（胜 8%%、败 22%%；%d 格不等）" % cas_bad)
	_check(SiegeMelee.WIN_MORALE == 8 and SiegeMelee.WIN_FAME == 4 and SiegeMelee.LOSE_MORALE == -12 and SiegeMelee.LOSE_WALL == -20,
		"胜负增减照旧：胜士气加 8、名声加 4；败士气减 12、城墙减 20")


## 搬家前一阵照原先次序落账（f443e6e8 Main._siege_nangshan，siege_add 不落负、add_fame 不落负；战力是 GameState.siege_power 原式）
func _old_round(st: Dictionary, fame: int) -> int:
	var rd := int(st.get("round", 0)) + 1
	st["round"] = rd
	st["grain"] = maxi(0, int(st["grain"]) - 40)
	var shishou := 1.5 if str(st.get("shishou", "")) == "kept" else 1.0
	var power := float(st["troops"]) * (float(st["morale"]) / 100.0) * shishou + float(st["wall"]) * 2.0
	var r := _old_roll(rd, power)
	if bool(r["won"]):
		st["morale"] = maxi(0, int(st["morale"]) + 8)
		fame = maxi(0, fame + 4)
		var killed: int = int(int(st["troops"]) * 0.08)
		st["troops"] = maxi(0, int(st["troops"]) - killed)
	else:
		st["morale"] = maxi(0, int(st["morale"]) - 12)
		var killed2: int = int(int(st["troops"]) * 0.22)
		st["troops"] = maxi(0, int(st["troops"]) - killed2)
		st["wall"] = maxi(0, int(st["wall"]) - 20)
	if rd >= 3:
		st["pending_fall"] = "三阵毕"
	return fame


func _sec_move_main() -> void:
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	_check(str(_main.get("_shore_mode")) == "siege" and gs.siege_open(), "1276-11 进兴化开守城页（页型 %s）" % _main.get("_shore_mode"))
	var runs := 0
	var bad := 0
	var first_bad := ""
	var won_rounds := 0
	var lost_rounds := 0
	for pi in PROFILES.size():
		var pf: Array = PROFILES[pi]
		for s in 40:
			var st := {"troops": pf[0], "grain": 120, "wall": pf[2], "morale": pf[1], "round": 0,
				"shishou": pf[3], "envoy_wang": true, "envoy_kin": true, "lin_hua_sent": true}
			gs.siege = st.duplicate(true)
			gs.fame = int(pf[4])
			var old_st := st.duplicate(true)
			var old_fame := int(pf[4])
			runs += 1
			for rd in [1, 2, 3]:
				var m0: int = gs.siege_get("morale")
				seed(7000 + pi * 1000 + s * 3 + rd)
				_main.call("_siege_nangshan")
				seed(7000 + pi * 1000 + s * 3 + rd)
				old_fame = _old_round(old_st, old_fame)
				if gs.siege_get("morale") > m0:
					won_rounds += 1
				else:
					lost_rounds += 1
				var keys := ["troops", "grain", "wall", "morale", "round"]
				var row_ok: bool = gs.fame == old_fame and str(gs.siege.get("pending_fall", "")) == str(old_st.get("pending_fall", ""))
				for k in keys:
					if gs.siege_get(k) != int(old_st[k]):
						row_ok = false
				if not row_ok:
					bad += 1
					if first_bad == "":
						first_bad = "档 %d 种子 %d 第 %d 阵：Main %s 名声 %d / 原式 %s 名声 %d" % [pi, s, rd, gs.siege, gs.fame, old_st, old_fame]
	_check(bad == 0, "Main 真打三阵 × %d 局，城防账与名声逐阵同原式（%d 阵不等%s）" % [runs, bad, "；首阵 " + first_bad if first_bad != "" else ""])
	_check(won_rounds > 30 and lost_rounds > 30, "真打的阵胜负两路都走到（胜 %d 阵、败 %d 阵）" % [won_rounds, lost_rounds])
	_check(str(gs.siege.get("pending_fall", "")) == "三阵毕", "第三阵打完记待结城破「三阵毕」（%s）" % gs.siege.get("pending_fall", ""))


# ══ 摆场 ════════════════════════════════════════════════════════════

## 士人线改名、守城那年那月：城防还没开，进兴化即开（_siege_active）
func _stage_siege(y: int, m: int, d: int) -> void:
	_close_sheet()
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	gs.money = 20000
	gs.fame = 30
	gs.last_port = "xinghua"
	cal.from_dict({"year": y, "month": m, "day": d})


func _stage_off() -> void:
	_close_sheet()
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _close_sheet() -> void:
	var host = _main.get("_chapter_host") if _main != null else null
	if host != null and is_instance_valid(host):
		_main.set("_chapter_host", null)
		(host as Node).queue_free()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)
