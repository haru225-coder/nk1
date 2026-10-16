extends SceneTree
## lane w53-p5-siege 守城专项探针（headless，不截图；回退即红）。
##   一、陆战骰子搬家（Main._siege_nangshan → scripts/combat/SiegeMelee.gd）前后逐字一致：
##       1. 纯算：400 种子 × 三阵 × 八档战力，搬家前原式（本探针留一份 f443e6e8 的副本）与 SiegeMelee.nangshan
##          敌军数逐位相等、胜负相同，掷完下一枚 randf() 也相同（掷骰次数不变）；折兵 0–1500 人逐人相等。
##       2. 真走 Main：三档城防（必败 / 胜负参半 / 多胜）× 40 种子，每阵前同种子，Main._siege_nangshan 真打三阵，
##          与原式副本照原先次序落账的城防账（兵、粮、墙、士气、阵数、待结城破）和名声逐阵相等。
##   二、行事表（开关 siege_schedule）：围城那天 / 援兵断绝 / 城破三个日子与探针自读 ports.json 兴化战况表另算的相等
##       （第一段 besieged 的月初、城破前 SIEGE_DIRE_DAYS 日、首守城破时点）；「元军行事」小笺并在城防账右边、各行逐字、
##       已过的淡写，候一日「还有几日」跟着少、剩两日写「两」；小笺不写 story_check 按子串找的告急行 / 阵数 / 兵粮字样，
##       告急行仍只在城破前十日内出；五扇门各一行「当日办完 / 当日接战」、岸带仍恰五扇门；最挤的一格（缺粮告急 + 城破告急
##       + 小笺）岸带不越过定高 360、动作行整排在画面里；城防账本身开关两态都逐字同 f443e6e8（硬抄同局旧字）；
##       关态：门副题逐字同旧，不长 SiegeRow / SiegeSchedule / DoorDays 节点。
## 用法：godot --headless --path . -s res://tools/qa_w53_p5_siege_probe.gd
## 判词：逐条「  ✓ / ✗ 判词」，末行 QA_W53_P5_SIEGE_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const SiegeMelee := preload("res://scripts/combat/SiegeMelee.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W53_P5_SIEGE_PROBE"
const VIEW := Vector2i(1280, 720)
## 岸带定高（Main._shore_band 的 offset_top −372 / offset_bottom −12）：守城页排满也不许越过
const BAND_H := 360.0

## f443e6e8 守城页同一局（1276-11-03 初开城防、名声 30、粮 120）的城防账各行与五扇门副题——关态须逐字同这几行
const OLD_SLIP := [
	"城头白布八字　生为宋臣　死为宋鬼", "城", "三阵・尚未接战",
	"兵 300（募兵上限 660）　粮 120・够打三阵　城墙 60 / 200　士气 55",
	"福州尼寺：母亲与璥儿在那里。这件事没有选项。",
]
const OLD_DOORS := [
	["siege_muster", "衙门", "募兵・石手军"], ["siege_grain", "市场", "屯粮（粮即守城日）"],
	["siege_wall", "船屋", "把修船的料改修城墙"], ["siege_envoy", "酒馆", "城下有使者求见"],
	["siege_nangshan", "囊山", "设伏迎敌・第一阵"],
]
## story_check / patrol_shell 在守城岸带里按子串找的字样：行事表一个都不许写
const PINNED_NEEDLES := ["援兵音信断绝", "二阵", "三阵・", "兵 ", "粮 ", "零阵", "一阵也不够", "牙行", "贡院", "看风"]

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
	root.size = VIEW
	root.add_child(_main)
	for i in 6:
		await process_frame

	print("== 一、陆战骰子搬家前后一致（SiegeMelee 对 f443e6e8 原式副本）")
	_sec_move_pure()
	_sec_move_main()
	print("== 二、行事表（siege_schedule）")
	await _sec_schedule()

	Switches.reset()
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


# ══ 二、行事表 ══════════════════════════════════════════════════════

func _sec_schedule() -> void:
	Switches.reset()
	# 1. 三个日子：探针自读 ports.json 兴化战况表（不经 Main）另算，再对 Main._siege_schedule
	var war: Dictionary = root.get_node("/root/GameManager").get_port_by_id("xinghua").get("war", {})
	var keys: Array = war.keys()
	keys.sort()
	var start_ym := ""
	var fall_ym := ""
	for k in keys:
		if str(war[k]) == "besieged" and start_ym == "":
			start_ym = str(k)
		elif start_ym != "" and str(war[k]) != "besieged":
			fall_ym = str(k)
			break
	var s_abs := _abs_ym(start_ym)
	var f_abs := _abs_ym(fall_ym)
	var dire: int = int(_main.get("SIEGE_DIRE_DAYS"))
	var sched: Array = _main.call("_siege_schedule")
	var got := []
	for it in sched:
		got.append(int(it[0]))
	_check(start_ym == "1276-11" and fall_ym == "1276-12", "战况表第一段围城 %s 起、%s 破（陈文龙守的那一次）" % [start_ym, fall_ym])
	_check(got == [s_abs, f_abs - dire, f_abs], "行事表三个日子 = 围城月初 %d / 城破前 %d 日 %d / 城破 %d（Main 给 %s）" % [s_abs, dire, f_abs - dire, f_abs, got])
	_check(f_abs == int((_main.call("_siege_fall_point") as Dictionary).get("abs", -1)), "城破那天与 _siege_fall_point（忠肃落款、告急行同源）是同一天")

	# 2. 「元军行事」小笺并在城防账右边：各行逐字（已过的淡写）；候一日「还有几日」跟着少；剩两日写「两」
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	var want := ["元军行事", "冬月初一　前锋到囊山・使者到城下", "冬月廿一　援兵断绝", "腊月初一　城破", "今日冬月初三・还有二十八日"]
	var side: Node = _band().find_child("SiegeSchedule", true, false)
	var lines := _labels(side)
	_check(lines == want, "元军行事小笺各行 %s" % [lines])
	var row: Node = _band().get_node_or_null("SiegeRow")
	_check(row != null and row.get_child_count() == 2 and row.get_child(0).name == "SiegeStat" and row.get_child(1).name == "SiegeSchedule"
			and _named(_band(), "SiegeSchedule") == 1,
		"小笺与城防账并排（SiegeRow：城防账在左、元军行事在右）")
	var first: Label = side.get_child(0).get_child(1) as Label if side != null else null
	var later: Label = side.get_child(0).get_child(2) as Label if side != null else null
	_check(first != null and later != null and first.get_theme_color("font_color") != later.get_theme_color("font_color"),
		"已过的（冬月初一）与未到的（冬月廿一）字色分开")
	var bad_needles := []
	for ln in lines:
		for nd in PINNED_NEEDLES:
			if str(ln).find(str(nd)) >= 0:
				bad_needles.append(nd)
	_check(bad_needles.is_empty(), "小笺不写 story / patrol 按子串找的字样（撞了 %s）" % [bad_needles])
	_main.call("_on_shore_wait")
	var today_l := _label_with(_band(), "今日")
	_check(today_l == "今日冬月初四・还有二十七日", "候一日：「%s」" % today_l)
	cal.from_dict({"year": 1276, "month": 11, "day": 29})
	_main.load_scene("xinghua")
	today_l = _label_with(_band(), "今日")
	_check(today_l == "今日冬月廿九・还有两日", "剩两日写「两」：「%s」" % today_l)

	# 3. 告急行照旧只在城破前 SIEGE_DIRE_DAYS 日内出（行事表写「援兵断绝」，不顶替它）
	for off in [dire + 1, dire]:
		var d_abs: int = f_abs - int(off)
		cal.from_dict({"year": 1276, "month": 11, "day": d_abs - s_abs + 1})
		_main.load_scene("xinghua")
		var dire_line := _label_with(_band(), "援兵音信断绝")
		_check((dire_line != "") == (off <= dire), "城破前 %d 日告急行%s（「%s」）" % [off, "有" if off <= dire else "没有", dire_line])

	# 4. 五扇门各写耗几日；岸带仍恰五扇门
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	var hand: PackedStringArray = _main.get("shore_hand")
	var notes := []
	var doors: Node = _band().get_node_or_null("ShoreDoors")
	if doors != null:
		for d in doors.get_children():
			var dl := (d as Node).find_child("DoorDays", true, false)
			notes.append((dl as Label).text if dl is Label else "")
	_check(hand.size() == 5 and notes == ["当日办完", "当日办完", "当日办完", "当日办完", "当日接战"],
		"五扇门（%d）各写耗几日 %s" % [hand.size(), notes])

	# 5. 最挤的一格：粮不够一阵（急）+ 城破前告急（急）+ 元军行事小笺——岸带仍不越过定高 360、动作行整排在画面里
	#    （同 qa_w53_4_epilogue_fit_probe 守终局札记的判据；小笺并排放，不加岸带的高）
	cal.from_dict({"year": 1276, "month": 11, "day": 25})
	_main.load_scene("xinghua")
	gs.siege_set("grain", 0)
	_main.call("_build_shore")
	for i in 3:
		await process_frame
	var band_c: Control = _band() as Control
	var acts: Control = band_c.get_node_or_null("ShoreActions") as Control if band_c != null else null
	var act_rect := acts.get_global_rect() if acts != null else Rect2()
	var band_h := band_c.size.y if band_c != null else 9999.0
	_check(acts != null and band_h <= BAND_H + 0.5 and act_rect.end.y <= float(VIEW.y) + 0.5 and _label_with(_band(), "援兵音信断绝") != ""
			and _label_with(_band(), "此时出战即城破") != "" and _named(_band(), "SiegeSchedule") == 1,
		"缺粮告急 + 城破告急 + 元军行事同在：岸带高 %.0f（定高 %.0f）、动作行底 %.0f（画面高 %d）" % [band_h, BAND_H, act_rect.end.y, VIEW.y])

	# 6. 关态逐字回旧：城防账各行、门副题同 f443e6e8，不长新节点
	Switches.set_on("siege_schedule", false)
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	var slip_off: Node = _band().find_child("SiegeStat", true, false)
	var off_lines := _labels(slip_off)
	_check(off_lines == OLD_SLIP, "关：城防账各行逐字同旧 %s" % [off_lines])
	var off_doors := []
	for fac in _main.get("_shore_facilities"):
		off_doors.append([str(fac.get("id", "")), str(fac.get("title", "")), str(fac.get("subtitle", "")), fac.has("days")])
	var want_doors := []
	for od in OLD_DOORS:
		want_doors.append([od[0], od[1], od[2], false])
	_check(off_doors == want_doors, "关：五扇门题、副题逐字同旧，不带耗日 %s" % [off_doors])
	_check(_named(_band(), "SiegeSchedule") == 0 and _named(_band(), "DoorDays") == 0, "关：不长行事表、门上耗日两种节点")
	_check(_band().get_child(0).name == "SiegeStat", "关：岸带头一个就是城防账，不套并排的一层")
	Switches.set_on("siege_schedule", true)
	_main.load_scene("xinghua")
	var on_lines := _labels(_band().find_child("SiegeStat", true, false))
	_check(on_lines == OLD_SLIP, "开：城防账本身各行仍逐字同旧（行事表另起小笺，不往城防账里添行）")
	Switches.reset()


# ══ 小件 ════════════════════════════════════════════════════════════

## "YYYY-MM" 那月初一的绝对日（Calendar.absolute_day 同式：每月 30 日、自 1255 正月初一起）
func _abs_ym(ym: String) -> int:
	if ym == "":
		return -1
	var p := ym.split("-")
	return ((int(p[0]) - 1255) * 12 + (int(p[1]) - 1)) * 30


func _band() -> Node:
	return _main.port_mode.get_node_or_null("ShoreBand")


## 树里第一个含 needle 的 Label 文本（同 story_check 的 _find_label_text）；没有返回 ""
func _label_with(node: Node, needle: String) -> String:
	if node == null:
		return ""
	if node is Label and (node as Label).text.find(needle) >= 0 and not node.is_queued_for_deletion():
		return (node as Label).text
	for c in node.get_children():
		var t := _label_with(c, needle)
		if t != "":
			return t
	return ""


## 树里全部 Label 文本，深度优先（城防账逐行比对用）
func _labels(node: Node) -> Array:
	var out := []
	if node == null:
		return out
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out.append_array(_labels(c))
	return out


## 树里叫 n 的节点数（排队待删的不算）
func _named(node: Node, n: String) -> int:
	if node == null:
		return 0
	var k := 1 if node.name == n and not node.is_queued_for_deletion() else 0
	for c in node.get_children():
		k += _named(c, n)
	return k


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
