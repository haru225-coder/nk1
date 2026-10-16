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
##       关态：门副题逐字同旧、不写耗日，不长 SiegeRow / SiegeSchedule 节点。
##   三、外援（开关 siege_relief）四样各自的增减：涵江押粮（城中粮加、舱里米减、委办留货不押、费两日、一围一趟）、
##       押陈瓒船股换乡兵（兵加至多 150、满千即止、没船股请不动、费三日）、拆船料修墙（那条船帆降一档、城墙加 40 不过上限、
##       帆一档拆不得、费一日）、劫粮道（骰子逐位同 SiegeMelee.clash、费四日耗四日水粮、得手压低下一阵敌骰上限 1400 → 1100
##       且只压那一阵、失手士气减 6、第三阵前 / 水粮不足 / 人手不够 / 城破前赶不回 / 入围那月一过都不开）；城破前办不完的不动账；
##       三页内页各一节、钮上写费几日、回车不按，按下去账真动；门上「少则当日・多则 N 日」、囊山门「元兵粮少」；
##       「元军行事」小笺末行记用过哪几样，岸带仍不越过定高 360；
##       关态：三页逐字同旧（硬抄），四样核心函数不动账，残留记号不压敌骰、不出外援一行。
##   四、守城仍最多三阵：外援全开打满三阵即记「三阵毕」、回城城破「力竭」；满配第三阵战力上限 < 第三阵敌军上限；
##       四档城防 × 外援全关 / 全开 × 240 固定种子打三阵（外援走 Main 的真钮；阵仗走快路 SiegeMelee + Main._siege_raid_cut，
##       先拿 96 个种子逐阵对过真 _siege_nangshan），印三阵全胜率（守住的概率）与各阵胜率，
##       全开不出必胜、满配抬不了顶、中等城防全开高过全关。
##   五、存档：外援记在城防记录（siege 字典）里，to_dict / from_dict 来回逐字同；旧档（无外援键）照读按没用过、来回不添键；
##       SaveLoad 存档位 88 真存真读过体检、读回同值。
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
var fleet: Node
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
	fleet = root.get_node("/root/Fleet")
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
	print("== 三、外援（siege_relief）四样各自的增减、不开的几种、内页与门、关态")
	await _sec_relief()
	print("== 四、守城仍最多三阵；外援全开 / 全关守住三阵的概率")
	await _sec_odds()
	print("== 五、存档：外援记在城防记录里，来回不丢不变，旧档照读")
	_sec_save()

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

	# 4. 五扇门各写耗几日（只开行事表；外援开着时门上另写「少则当日・多则 N 日」，见第三节）；岸带仍恰五扇门
	Switches.set_on("siege_relief", false)
	_stage_siege(1276, 11, 3)
	_main.load_scene("xinghua")
	var hand: PackedStringArray = _main.get("shore_hand")
	var notes := _door_notes()
	_check(hand.size() == 5 and notes == ["当日办完", "当日办完", "当日办完", "当日办完", "当日接战"],
		"五扇门（%d）副题下各写耗几日 %s" % [hand.size(), notes])
	Switches.reset()

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
		off_doors.append([str(fac.get("id", "")), str(fac.get("title", "")), str(fac.get("subtitle", ""))])
	var want_doors := []
	var want_subs := []
	for od in OLD_DOORS:
		want_doors.append([od[0], od[1], od[2]])
		want_subs.append(od[2])
	_check(off_doors == want_doors and _door_subs() == want_subs, "关：五扇门题、副题逐字同旧，门上不写耗日 %s" % [_door_subs()])
	_check(_named(_band(), "SiegeSchedule") == 0, "关：不长行事表小笺")
	_check(_band().get_child(0).name == "SiegeStat", "关：岸带头一个就是城防账，不套并排的一层")
	Switches.set_on("siege_schedule", true)
	_main.load_scene("xinghua")
	var on_lines := _labels(_band().find_child("SiegeStat", true, false))
	_check(on_lines == OLD_SLIP, "开：城防账本身各行仍逐字同旧（行事表另起小笺，不往城防账里添行）")
	Switches.reset()


# ══ 三、外援 ════════════════════════════════════════════════════════

## 两条大福船「安济」「通济」，各 crew 人、帆 sail 档；一号船舱里米 grain 石；水粮各 supplies
func _fleet(grain: int, crew := 75, sail := 3, supplies := 300) -> void:
	fleet.ships = []
	fleet.add_ship("fu_ship_large", "安济")
	fleet.add_ship("fu_ship_large", "通济")
	for s in fleet.ships:
		s["crew"] = crew
		s["sail_level"] = sail
	if grain > 0:
		fleet.ships[0]["cargo"] = {"grain": {"qty": grain, "avg_cost": 9.0}}
	fleet.water = supplies
	fleet.food = supplies
	fleet.morale = 80


func _sec_relief() -> void:
	Switches.reset()
	# 3a 涵江押粮：舱里的米进城，一围一趟，费两日；委办要交的米留在舱里；没米、城破前来不及都不动账
	_stage_siege(1276, 11, 3)
	_fleet(150)
	_main.load_scene("xinghua")
	var d0: int = cal.absolute_day()
	var n: int = _main.call("_siege_relief_convoy")
	_check(n == 120 and gs.siege_get("grain") == 240 and fleet.cargo_qty("grain") == 30 and cal.absolute_day() == d0 + 2
			and gs.siege_get("convoy") == 120,
		"涵江押粮：押进 %d 石（至多 120），城中粮 120 → %d、舱里米 150 → %d、过了 %d 日" % [
			n, gs.siege_get("grain"), fleet.cargo_qty("grain"), cal.absolute_day() - d0])
	_check(int(_main.call("_siege_relief_convoy")) == 0 and gs.siege_get("grain") == 240 and cal.absolute_day() == d0 + 2,
		"涵江押粮一围一趟：再押不动账、不过日子")
	_stage_siege(1276, 11, 3)
	_fleet(150)
	_main.load_scene("xinghua")
	gs.contract = {"good_id": "grain", "qty": 100, "remaining": 100, "dest": "quanzhou", "from": "xinghua", "purse": 1000,
		"unit_purse": 10.0, "paid": 0, "due_day": 99999, "deadline_days": 30, "voyage_days": 5, "offer_month": 0}
	n = _main.call("_siege_relief_convoy")
	_check(n == 50 and fleet.cargo_qty("grain") == 100, "委办要交的米留在舱里：只押 %d 石、舱里留 %d 石" % [n, fleet.cargo_qty("grain")])
	gs.contract = {}
	_stage_siege(1276, 11, 3)
	_fleet(0)
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	_check(int(_main.call("_siege_relief_convoy")) == 0 and gs.siege_get("grain") == 120 and cal.absolute_day() == d0,
		"舱里没米：押不了，不动账、不过日子")
	_stage_siege(1276, 11, 29)
	_fleet(150)
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	_check(int(_main.call("_siege_relief_convoy")) == 0 and gs.siege_get("grain") == 120 and fleet.cargo_qty("grain") == 150
			and cal.absolute_day() == d0,
		"城破前两日：押粮费两日、办不完，不动账")

	# 3b 押陈瓒船股换乡兵：兵加至多 150、城中兵满千即止，费三日，一围一回；没有船股请不动
	_stage_siege(1276, 11, 3)
	_fleet(0)
	gs.set_flag("chen_zan_stake")
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	n = _main.call("_siege_relief_levy")
	_check(n == 150 and gs.siege_get("troops") == 450 and gs.siege_get("levy") == 150 and cal.absolute_day() == d0 + 3
			and "押陈瓒船股换乡兵" in gs.ledger_notes,
		"押船股换乡兵：来 %d 人，兵 300 → %d、过了 %d 日、札记记下" % [n, gs.siege_get("troops"), cal.absolute_day() - d0])
	_check(int(_main.call("_siege_relief_levy")) == 0 and gs.siege_get("troops") == 450, "船股一围只押一回")
	for c in [[900, 100, 1000], [1000, 0, 1000], [1200, 0, 1200]]:
		_stage_siege(1276, 11, 3)
		_fleet(0)
		gs.set_flag("chen_zan_stake")
		_main.load_scene("xinghua")
		gs.siege_set("troops", int(c[0]))
		n = _main.call("_siege_relief_levy")
		_check(n == int(c[1]) and gs.siege_get("troops") == int(c[2]),
			"城中兵 %d：乡兵来 %d 人、兵到 %d（满千即止，石手军另算）" % [int(c[0]), n, gs.siege_get("troops")])
	_stage_siege(1276, 11, 3)
	_fleet(0)
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	_check(int(_main.call("_siege_relief_levy")) == 0 and gs.siege_get("troops") == 300 and cal.absolute_day() == d0,
		"没有陈瓒的船股：请不动乡兵，不动账")

	# 3c 拆船料修墙：那条船帆降一档、城墙加 40（不过上限 200），费一日；帆一档的拆不得
	_stage_siege(1276, 11, 3)
	_fleet(0)
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	n = _main.call("_siege_relief_timber", 0)
	_check(n == 40 and gs.siege_get("wall") == 100 and fleet.sail_level(0) == 2 and fleet.sail_level(1) == 3
			and gs.siege_get("timber") == 40 and cal.absolute_day() == d0 + 1,
		"拆「安济」船料：城墙 60 → %d、安济帆 3 → %d（通济仍 %d）、过了 %d 日" % [
			gs.siege_get("wall"), fleet.sail_level(0), fleet.sail_level(1), cal.absolute_day() - d0])
	gs.siege_set("wall", 190)
	n = _main.call("_siege_relief_timber", 1)
	_check(n == 10 and gs.siege_get("wall") == 200 and fleet.sail_level(1) == 2 and gs.siege_get("timber") == 50,
		"城墙 190：只加 %d 到上限 200，通济照样降一档（%d）" % [n, fleet.sail_level(1)])
	_check(int(_main.call("_siege_relief_timber", 0)) == 0 and fleet.sail_level(0) == 2,
		"城墙到了上限：不拆、帆不降")
	gs.siege_set("wall", 60)
	fleet.ships[0]["sail_level"] = 1
	_check(int(_main.call("_siege_relief_timber", 0)) == 0 and fleet.sail_level(0) == 1 and gs.siege_get("wall") == 60,
		"帆只剩一档：拆不得")

	# 3d 劫粮道：同 SiegeMelee 那一种结算（骰子逐位相等），费四日、耗四日水粮；得手记下压低第一阵，失手士气减 6
	var bad := 0
	var wins := 0
	var losses := 0
	var first_bad := ""
	for s in 60:
		_stage_siege(1276, 11, 3)
		_fleet(0, 75, 3, 400)
		_main.load_scene("xinghua")
		d0 = cal.absolute_day()
		var m0: int = gs.siege_get("morale")
		var power: float = SiegeMelee.raid_power(fleet.total_crew(), fleet.call("captain_power"), fleet.call("morale_factor"))
		var use: int = fleet.call("daily_supply_use")
		seed(5000 + s)
		var r: Dictionary = _main.call("_siege_relief_raid")
		seed(5000 + s)
		var want: Dictionary = SiegeMelee.clash(power, 40.0, 400.0, 1.0)
		var ok: bool = not r.is_empty() and bool(r["won"]) == bool(want["won"]) and float(r["enemy"]) == float(want["enemy"]) \
			and cal.absolute_day() == d0 + 4 and fleet.water == 400 - 4 * use and fleet.food == 400 - 4 * use
		if not r.is_empty() and bool(r["won"]):
			wins += 1
			ok = ok and str(gs.siege.get("raid", "")) == "won" and gs.siege_get("raid_round") == 1 and gs.siege_get("morale") == m0
		else:
			losses += 1
			ok = ok and str(gs.siege.get("raid", "")) == "lost" and gs.siege_get("morale") == m0 - 6
		ok = ok and (_main.call("_siege_relief_raid") as Dictionary).is_empty() and cal.absolute_day() == d0 + 4
		if not ok:
			bad += 1
			if first_bad == "":
				first_bad = "种子 %d：%s / 应 %s，城防 %s" % [5000 + s, r, want, gs.siege]
	_check(bad == 0 and wins > 5 and losses > 5,
		"劫粮道 60 种子：骰子同 SiegeMelee.clash(150 人战力, 40, 400)、费四日耗四日水粮、得手记第一阵 / 失手士气减 6、一围一回（得手 %d、失手 %d、不符 %d%s）" % [
			wins, losses, bad, "；首格 " + first_bad if first_bad != "" else ""])
	# 压低的正是那一阵：战力 1140 时，第一阵敌骰上限 1100 必胜、1400 不到七成——120 种子逐个对
	var cut_bad := 0
	var cut_diff := 0
	var cut_seeds := 120
	for s in cut_seeds:
		for rd in [1, 2]:
			gs.siege = {"troops": 700, "grain": 120, "wall": 150, "morale": 80, "round": rd - 1, "shishou": "kept",
				"envoy_wang": true, "envoy_kin": true, "lin_hua_sent": true, "raid": "won", "raid_round": 1}
			var power := float(gs.call("siege_power"))
			var m1: int = gs.siege_get("morale")
			seed(6000 + s)
			_main.call("_siege_nangshan")
			var won: bool = gs.siege_get("morale") > m1
			seed(6000 + s)
			var hi := 1100.0 if rd == 1 else 1400.0
			var want_won: bool = SiegeMelee.clash(power, 600.0, hi, SiegeMelee.nangshan_scale(rd))["won"]
			seed(6000 + s)
			var uncut_won: bool = SiegeMelee.clash(power, 600.0, 1400.0, SiegeMelee.nangshan_scale(rd))["won"]
			if won != want_won:
				cut_bad += 1
			if rd == 1 and want_won != uncut_won:
				cut_diff += 1
		_close_sheet()
		if s % 20 == 0:
			await process_frame
	_check(cut_bad == 0 and cut_diff > 20,
		"劫粮道得手压第一阵：第一阵敌骰上限 1100、第二阵照旧 1400，%d 阵逐阵对（不符 %d；与不压相比第一阵改了胜负 %d 阵）" % [cut_seeds * 2, cut_bad, cut_diff])

	# 3e 劫粮道不开的几种：缘由一句，劫了也不动账
	_stage_siege(1276, 11, 3)
	_fleet(0, 75, 3, 400)
	_main.load_scene("xinghua")
	d0 = cal.absolute_day()
	var blocks := []
	gs.siege_set("round", 2)
	blocks.append([_main.call("_siege_raid_block"), "第三阵"])
	gs.siege_set("round", 0)
	fleet.water = 200
	fleet.food = 200
	blocks.append([_main.call("_siege_raid_block"), "水粮撑不过四日"])
	fleet.water = 400
	fleet.food = 400
	for s in fleet.ships:
		s["crew"] = 0
	blocks.append([_main.call("_siege_raid_block"), "人手不够"])
	for s in fleet.ships:
		s["crew"] = 75
	cal.from_dict({"year": 1276, "month": 11, "day": 27})
	blocks.append([_main.call("_siege_raid_block"), "赶不回来"])
	cal.from_dict({"year": 1276, "month": 12, "day": 3})
	blocks.append([_main.call("_siege_raid_block"), "入围那个月一过"])
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	var blk_bad := []
	for b in blocks:
		if str(b[0]).find(str(b[1])) < 0:
			blk_bad.append(b)
	_check(blk_bad.is_empty() and str(_main.call("_siege_raid_block")) == "",
		"劫粮道不开：第三阵前 / 水粮不足四日 / 人手不够 / 城破前赶不回 / 入围那月一过，各有一句（不符 %s）" % [blk_bad])
	gs.siege_set("round", 2)
	_check((_main.call("_siege_relief_raid") as Dictionary).is_empty() and cal.absolute_day() == d0 and str(gs.siege.get("raid", "")) == "",
		"第三阵前劫粮道：不动账、不过日子")

	# 3f 内页与门：市场 / 衙门 / 船屋三页各一节外援，钮上写费几日、回车不替人按；门上写「少则当日・多则 N 日」；
	#     按钮真按下去账就动；城防账多一行外援
	_stage_siege(1276, 11, 3)
	_fleet(150, 200, 3, 1000)
	gs.set_flag("chen_zan_stake")
	_main.load_scene("xinghua")
	var notes := _door_notes()
	_check(notes == ["少则当日・多则三日", "少则当日・多则两日", "少则当日・多则四日", "当日办完", "当日接战"],
		"门上耗日：衙门乡兵三日、市场押粮两日、船屋劫粮道四日（%s）" % [notes])
	_main.call("_on_facility_pressed", {"id": "siege_grain", "title": "市场"})
	var convoy_btn := _btn(_main.choices_container, "从涵江海口押米 120 石入城（费 2 日）")
	_check(_label_with(_main.choices_container, "── 涵江海口 ──") != "" and convoy_btn != null and not convoy_btn.disabled
			and convoy_btn.has_meta("no_enter"),
		"市场页一节「涵江海口」、钮「从涵江海口押米 120 石入城（费 2 日）」回车不按")
	if convoy_btn != null:
		convoy_btn.pressed.emit()
	_check(gs.siege_get("convoy") == 120 and str(_main.get("_shore_mode")) == "siege", "按下押粮钮：米进城、回到守城页")
	_main.call("_on_facility_pressed", {"id": "siege_muster", "title": "衙门"})
	var levy_btn := _btn(_main.choices_container, "把陈瓒的船股押出去，换乡兵 150 人（费 3 日）")
	_check(_label_with(_main.choices_container, "── 陈瓒船股 ──") != "" and levy_btn != null and levy_btn.has_meta("no_enter"),
		"衙门页一节「陈瓒船股」、钮「把陈瓒的船股押出去，换乡兵 150 人（费 3 日）」")
	if levy_btn != null:
		levy_btn.pressed.emit()
	_main.call("_on_facility_pressed", {"id": "siege_wall", "title": "船屋"})
	var timber_btn := _btn(_main.choices_container, "拆「安济」的帆桅修墙（帆降一档，城墙加 40，费 1 日）")
	var raid_btn := _btn(_main.choices_container, "出海劫粮道（费 4 日・耗水粮四日份）")
	_check(_label_with(_main.choices_container, "── 拆船料 ──") != "" and _label_with(_main.choices_container, "── 出海劫粮道 ──") != ""
			and timber_btn != null and raid_btn != null and _btn(_main.choices_container, "拆「通济」的帆桅修墙") != null,
		"船屋页两节「拆船料」（两条船各一钮）「出海劫粮道」")
	if timber_btn != null:
		timber_btn.pressed.emit()
	_main.call("_on_facility_pressed", {"id": "siege_wall", "title": "船屋"})
	raid_btn = _btn(_main.choices_container, "出海劫粮道（费 4 日・耗水粮四日份）")
	if raid_btn != null:
		raid_btn.pressed.emit()
	var line := _label_with(_band(), "外援　")
	var side: Node = _band().find_child("SiegeSchedule", true, false)
	var side_lines := _labels(side)
	_check(line == "外援　押米・乡兵・拆船料・劫粮道得手" and side_lines.size() == 6 and str(side_lines[5]) == line
			and _named(_band(), "SiegeReliefLine") == 1,
		"四样用过，「元军行事」小笺末行「%s」（400 人出海必得手）" % line)
	_check(_labels(_band().find_child("SiegeStat", true, false)).find(line) < 0, "外援那一行不写进城防账（城防账本身仍是旧几行）")
	var bad_needles := []
	for nd in PINNED_NEEDLES:
		if line.find(str(nd)) >= 0:
			bad_needles.append(nd)
	_check(bad_needles.is_empty(), "外援一行不写 story / patrol 按子串找的字样（撞了 %s）" % [bad_needles])
	_check(cal.absolute_day() == _abs_ym("1276-11") + 2 + 2 + 3 + 1 + 4, "四样一共费了十日（今日 %s）" % cal.call("get_date_string"))
	notes = _door_notes()
	_check(notes == ["当日办完", "当日办完", "少则当日・多则一日", "当日办完", "当日接战・元兵粮少"],
		"用过之后门上耗日回「当日办完」，船屋只剩拆通济一日，囊山门「当日接战・元兵粮少」（%s）" % [notes])
	# 最挤：外援一行 + 行事表 + 缺粮、城破两行告急——岸带仍不越过定高 360，动作行整排在画面里
	cal.from_dict({"year": 1276, "month": 11, "day": 25})
	gs.siege_set("grain", 0)
	_main.load_scene("xinghua")
	for i in 3:
		await process_frame
	var band_c: Control = _band() as Control
	var acts: Control = band_c.get_node_or_null("ShoreActions") as Control
	var act_end := acts.get_global_rect().end.y if acts != null else 9999.0
	_check(band_c.size.y <= BAND_H + 0.5 and act_end <= float(VIEW.y) + 0.5 and _named(_band(), "SiegeReliefLine") == 1
			and _label_with(_band(), "援兵音信断绝") != "" and _label_with(_band(), "此时出战即城破") != "",
		"外援一行 + 行事表 + 两行告急同在：岸带高 %.0f（定高 %.0f）、动作行底 %.0f" % [band_c.size.y, BAND_H, act_end])
	# 压过的那一阵打完，囊山门不再写「元兵粮少」
	gs.siege_set("grain", 120)
	gs.siege_set("round", 1)
	_main.load_scene("xinghua")
	_check(_door_notes()[4] == "当日接战" and float(_main.call("_siege_raid_cut", 2)) == 0.0,
		"第一阵打过：囊山门回「当日接战」，第二阵不压（%s）" % [_door_notes()])
	gs.siege_set("round", 0)
	# 城破前办不完的钮灰掉、钮上写明
	cal.from_dict({"year": 1276, "month": 11, "day": 29})
	gs.siege_set("convoy", 0)
	_main.call("_on_facility_pressed", {"id": "siege_grain", "title": "市场"})
	var late := _btn(_main.choices_container, "城破前办不完")
	_check(late != null and late.disabled, "城破前两日：押粮钮灰、钮上写「城破前办不完」（%s）" % [late.text if late != null else "无"])

	# 3g 关态：三页不出外援一节（逐字同旧），四样核心函数不动账，残留的「劫粮道得手」不压敌骰，城防账不出外援一行
	Switches.set_on("siege_relief", false)
	_stage_siege(1276, 11, 3)
	_fleet(150, 200, 3, 1000)
	gs.set_flag("chen_zan_stake")
	_main.load_scene("xinghua")
	var pages := {
		"siege_grain": ["屯粮 40（480 钱・每石 12）", "屯粮 120（1440 钱・每石 12）"],
		"siege_muster": ["募兵 50 人（500 钱）", "募兵 200 人（2000 钱）", "── 石手军 ──",
			"两百个能把石头掷中人头的乡兵站在木兰陂上。朝廷议者说「不足用」，把他们裁了。他们说：不是反朝廷，是朝廷不要我们。",
			"重编石手军，归你麾下（兵 +200，囊山战力 ×1.5）", "按律解散，不追究"],
		"siege_wall": ["加固城墙　加 20（300 钱・上限 200）", "加固城墙　加 60（900 钱・上限 200）"],
	}
	for pid in pages:
		_main.call("_on_facility_pressed", {"id": pid})
		var got := _page_texts()
		_check(got == pages[pid], "关：%s 页逐字同旧 %s" % [pid, got])
	d0 = cal.absolute_day()
	var before := JSON.stringify(gs.siege)
	var sails := [fleet.sail_level(0), fleet.sail_level(1)]
	var outs := [_main.call("_siege_relief_convoy"), _main.call("_siege_relief_levy"), _main.call("_siege_relief_timber", 0),
		(_main.call("_siege_relief_raid") as Dictionary).size()]
	_check(outs == [0, 0, 0, 0] and JSON.stringify(gs.siege) == before and cal.absolute_day() == d0
			and [fleet.sail_level(0), fleet.sail_level(1)] == sails and fleet.cargo_qty("grain") == 150,
		"关：四样核心函数都不动账（%s）" % [outs])
	_check(_door_notes() == ["当日办完", "当日办完", "当日办完", "当日办完", "当日接战"], "关：门上耗日照行事表一节（%s）" % [_door_notes()])
	gs.siege_set("convoy", 120)
	gs.siege_set("raid", "won")
	gs.siege_set("raid_round", 1)
	_main.load_scene("xinghua")
	_check(_named(_band(), "SiegeReliefLine") == 0 and _named(_band(), "SiegeRelief") == 0 and float(_main.call("_siege_raid_cut", 1)) == 0.0
			and _door_notes()[4] == "当日接战",
		"关：残留的外援记号不出外援一行、囊山门不写「元兵粮少」、不压第一阵敌骰")
	# 只关行事表、外援开着且用过：小笺只剩外援一行（改叫 SiegeRelief），囊山门只写「元兵粮少」
	Switches.set_on("siege_relief", true)
	Switches.set_on("siege_schedule", false)
	_main.load_scene("xinghua")
	_check(_labels(_band().find_child("SiegeRelief", true, false)) == ["外援　押米・劫粮道得手"] and _named(_band(), "SiegeSchedule") == 0
			and _door_notes() == ["", "", "", "", "元兵粮少"],
		"只关行事表：小笺只剩外援一行、囊山门只写「元兵粮少」（%s）" % [_door_notes()])
	Switches.reset()


## 守城岸带五扇门的副题小字整段（按门排顺序）：门里那一列 VBox 是门题、副题两枚 Label（绢本另有水印字在 DoorMark 里，
## 不在这一列），耗日是副题的第二行
func _door_subs() -> Array:
	var out := []
	var doors: Node = _band().get_node_or_null("ShoreDoors") if _band() != null else null
	if doors == null:
		return out
	for d in doors.get_children():
		if (d as Node).is_queued_for_deletion():
			continue
		var cols := (d as Node).find_children("*", "VBoxContainer", true, false)
		var sub: Node = (cols[0] as Node).get_child(1) if not cols.is_empty() and (cols[0] as Node).get_child_count() > 1 else null
		out.append((sub as Label).text if sub is Label else "")
	return out


## 五扇门各自的耗日（副题第二行；门上没写的记 ""）
func _door_notes() -> Array:
	var out := []
	for sub in _door_subs():
		var lines := str(sub).split("\n")
		out.append(lines[1] if lines.size() > 1 else "")
	return out


## 内页（choices_container）里各 Label / Button 的字，按树序；「离开」不算（落在页脚还是这里随版式）
func _page_texts() -> Array:
	var out := []
	for c in _main.choices_container.get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		if c is Button and (c as Button).text != "离开":
			out.append((c as Button).text)
		elif c is Label:
			out.append((c as Label).text)
	return out


## 树里第一枚字里含 needle 的钮
func _btn(node: Node, needle: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text.find(needle) >= 0 and not node.is_queued_for_deletion():
		return node as Button
	for c in node.get_children():
		var b := _btn(c, needle)
		if b != null:
			return b
	return null


# ══ 四、三阵上限与守住的概率 ═════════════════════════════════════════

## 四档城防：[名, 名声, 兵, 士气, 城墙, 石手军]——士气 90 = 开城 55 + 斩使 10 + 焚书 12 + 石手军 8 + 林华 5
const ODDS_PROFILES := [
	["名声六十・钱足・全拿", 60, 1200, 90, 200, "kept"],
	["名声三十・钱足・石手军", 30, 860, 85, 200, "kept"],
	["名声十五・钱紧・石手军", 15, 680, 79, 140, "kept"],
	["名声零・白手", 0, 300, 55, 60, ""],
]
const ODDS_SEEDS := 240


func _sec_odds() -> void:
	Switches.reset()
	# 4a 外援全开真打：第三阵后记「三阵毕」，按「回城」即城破「力竭」——没有第四阵
	_stage_siege(1276, 11, 3)
	_fleet(150, 200, 3, 1000)
	gs.set_flag("chen_zan_stake")
	_main.load_scene("xinghua")
	gs.siege_set("lin_hua_sent", true)
	_main.call("_siege_relief_convoy")
	_main.call("_siege_relief_levy")
	_main.call("_siege_relief_timber", 0)
	_main.call("_siege_relief_raid")
	for rd in 3:
		seed(4242 + rd)
		_main.call("_siege_nangshan")
	_check(gs.siege_get("round") == 3 and str(gs.siege.get("pending_fall", "")) == "三阵毕" and int(gs.get("SIEGE_ROUNDS_MAX")) == 3,
		"外援全开打满三阵：阵数 %d、待结城破「%s」，SIEGE_ROUNDS_MAX 仍是 3" % [gs.siege_get("round"), gs.siege.get("pending_fall", "")])
	_main.call("_confirm_chapter_sheet")
	_check(gs.ended == "忠肃" and gs.ended_head.find("力竭") >= 0 and not gs.siege_open(),
		"战报按「回城」：城破结「%s」、题头「%s」，城防记录收了" % [gs.ended, gs.ended_head])
	_close_sheet()

	# 4b 满配第三阵的战力上限仍低于第三阵敌军上限：外援不把兵、墙、士气堆过原有的顶
	gs.siege = {"troops": 1200, "grain": 120, "wall": 200, "morale": 90, "round": 0, "shishou": "kept"}
	var lv: int = _main.call("_siege_levy_room")
	var tb := mini(int(_main.get("SIEGE_TIMBER_WALL")), int(gs.call("siege_wall_room")))
	var t := 1200
	var m := 90
	for i in 2:
		t -= SiegeMelee.casualties(t, true)
		m += SiegeMelee.WIN_MORALE
	var top := float(t) * (float(m) / 100.0) * 1.5 + 200.0 * 2.0
	var cap3 := SiegeMelee.NANGSHAN_HI * SiegeMelee.nangshan_scale(3)
	_check(lv == 0 and tb == 0 and top < cap3,
		"满配（兵 1200、士气 90、城墙 200、石手军）外援再添不进（乡兵 %d、墙 %d）；两胜后第三阵战力 %.1f < 第三阵敌军上限 %.0f" % [lv, tb, top, cap3])

	# 4c 守住三阵的概率：四档城防 × 外援全关 / 全开 × 240 种子（劫粮道在第一阵后、出海 150 人）。
	#    每步前按种子另播一次：同一种子的全关、全开三阵敌骰相同，差的只在外援；
	#    阵仗走快路（Main 的外援钮 + SiegeMelee.nangshan + Main._siege_raid_cut，照 _siege_nangshan 的次序落账，不出战报册页），
	#    先拿 96 个种子逐阵对一遍真 _siege_nangshan，对得上再信快路的 240 种子表
	var cross_bad := 0
	var cross_n := 0
	for pi in [1, 2]:
		for on in [false, true]:
			Switches.set_on("siege_relief", on)
			for s in 24:
				var fast := _odds_seed(ODDS_PROFILES[pi], on, s, false)
				var real := _odds_seed(ODDS_PROFILES[pi], on, s, true)
				cross_n += 1
				if fast != real:
					cross_bad += 1
				_close_sheet()
				if s % 8 == 7:
					await process_frame
	_check(cross_bad == 0, "快路对真 _siege_nangshan：两档城防 × 全关 / 全开 × 24 种子逐阵相同（%d 局里 %d 局不同）" % [cross_n, cross_bad])
	var rates := {}
	for pf in ODDS_PROFILES:
		for on in [false, true]:
			Switches.set_on("siege_relief", on)
			var full := 0
			var per := [0, 0, 0]
			for s in ODDS_SEEDS:
				var w := _odds_seed(pf, on, s, false)
				for rd in 3:
					if bool(w[rd]):
						per[rd] += 1
				if bool(w[0]) and bool(w[1]) and bool(w[2]):
					full += 1
			var key := "%s_%s" % [pf[0], "on" if on else "off"]
			rates[key] = float(full) / ODDS_SEEDS
			print("  · %s　外援%s　三阵全胜 %d / %d = %.1f%%（第一阵 %.0f%%・第二阵 %.0f%%・第三阵 %.0f%%）" % [
				pf[0], "全开" if on else "全关", full, ODDS_SEEDS, 100.0 * full / ODDS_SEEDS,
				100.0 * per[0] / ODDS_SEEDS, 100.0 * per[1] / ODDS_SEEDS, 100.0 * per[2] / ODDS_SEEDS])
	Switches.reset()
	var never_sure := true
	for pf in ODDS_PROFILES:
		if float(rates["%s_on" % pf[0]]) >= 1.0:
			never_sure = false
	_check(never_sure, "外援全开，四档城防都不是三阵必胜")
	var a_on: float = rates["%s_on" % ODDS_PROFILES[0][0]]
	var a_off: float = rates["%s_off" % ODDS_PROFILES[0][0]]
	_check(absf(a_on - a_off) <= 0.06 and a_on < 0.97,
		"满配守城外援抬不了顶：全开 %.1f%% / 全关 %.1f%%" % [100.0 * a_on, 100.0 * a_off])
	var helps := true
	for i in [1, 2]:
		if float(rates["%s_on" % ODDS_PROFILES[i][0]]) <= float(rates["%s_off" % ODDS_PROFILES[i][0]]):
			helps = false
	_check(helps, "外援对中等城防有用：名声三十、名声十五两档全开都高过全关")



## 一个种子打三阵：返回 [三阵胜负 ×3, 打完的兵, 城墙, 士气]。real = 真走 Main._siege_nangshan（出战报册页），否则走快路 _round_fast。
## 外援全开：押粮、乡兵、两条船各拆一回，第一阵后出海劫粮道；每步前按种子另播，全关、全开同一种子三阵敌骰相同
func _odds_seed(pf: Array, on: bool, s: int, real: bool) -> Array:
	_odds_stage(pf)
	var base := 31000 + s * 10
	if on:
		_main.call("_siege_relief_convoy")
		_main.call("_siege_relief_levy")
		_main.call("_siege_relief_timber", 0)
		_main.call("_siege_relief_timber", 1)
	var out := []
	for rd in 3:
		if on and rd == 1:
			seed(base + 5)
			_main.call("_siege_relief_raid")
		seed(base + rd)
		var m0: int = gs.siege_get("morale")
		if real:
			_main.call("_siege_nangshan")
			out.append(gs.siege_get("morale") > m0)
		else:
			out.append(_round_fast())
	out.append_array([gs.siege_get("troops"), gs.siege_get("wall"), gs.siege_get("morale")])
	return out


## 囊山一阵的快路：照 Main._siege_nangshan 的次序落账（阵数、耗粮、掷骰、增减，第一节已逐阵对过同式），不出战报册页
func _round_fast() -> bool:
	var rd: int = gs.siege_get("round") + 1
	gs.siege_set("round", rd)
	gs.siege_add("grain", -int(gs.get("SIEGE_GRAIN_PER_ROUND")))
	var power := float(gs.call("siege_power"))
	var won: bool = SiegeMelee.nangshan(rd, power, float(_main.call("_siege_raid_cut", rd)))["won"]
	if won:
		gs.siege_add("morale", SiegeMelee.WIN_MORALE)
		gs.add_fame(SiegeMelee.WIN_FAME)
		gs.siege_add("troops", -SiegeMelee.casualties(gs.siege_get("troops"), true))
	else:
		gs.siege_add("morale", SiegeMelee.LOSE_MORALE)
		gs.siege_add("troops", -SiegeMelee.casualties(gs.siege_get("troops"), false))
		gs.siege_add("wall", SiegeMelee.LOSE_WALL)
	return won


## 守住概率那一节每个种子的起点：1276-11-03、城防照档、林华已出侦（第三阵前不再停下问）、有陈瓒船股、两条大福船各 75 人帆三档、舱里米 150
func _odds_stage(pf: Array) -> void:
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.set_flag("chen_zan_stake")
	gs.identity = "scholar"
	gs.fame = int(pf[1])
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	gs.siege = {"troops": int(pf[2]), "grain": 120, "wall": int(pf[4]), "morale": int(pf[3]), "round": 0, "shishou": str(pf[5]),
		"envoy_wang": true, "envoy_kin": true, "lin_hua_sent": true}
	_fleet(150, 75, 3, 400)


# ══ 五、存档 ════════════════════════════════════════════════════════

const SAVE_SLOT := 88


func _sec_save() -> void:
	Switches.reset()
	# 5a GameState 来回：外援几个键随城防记录不丢不变
	_stage_siege(1276, 11, 3)
	gs.siege_begin()
	for kv in [["convoy", 120], ["levy", 150], ["timber", 40], ["raid", "won"], ["raid_round", 2]]:
		gs.siege_set(str(kv[0]), kv[1])
	var want := JSON.stringify(gs.siege)
	var d: Dictionary = gs.to_dict()
	gs.from_dict({})
	gs.from_dict(d)
	_check(JSON.stringify(gs.siege) == want, "to_dict / from_dict 来回：城防记录连外援键逐字同（%s）" % JSON.stringify(gs.siege))
	# 5b 旧档（f443e6e8 写的城防记录，没有外援键）照读：外援按没用过算，来回不添键
	var old_siege := {"troops": 300, "grain": 120, "wall": 60, "morale": 55, "round": 1, "shishou": "kept",
		"envoy_wang": true, "envoy_kin": false, "lin_hua_sent": false}
	gs.from_dict({"siege": old_siege.duplicate(true), "identity": "scholar", "flags": {"renamed_wenlong": true}})
	_check(gs.siege_get("convoy") == 0 and gs.siege_get("levy") == 0 and gs.siege_get("timber") == 0
			and str(gs.siege.get("raid", "")) == "" and float(_main.call("_siege_raid_cut", 2)) == 0.0
			and str(_main.call("_siege_relief_line")) == "",
		"旧档城防记录：外援四样都按没用过，不压敌骰、不出外援一行")
	var back: Dictionary = gs.to_dict()["siege"]
	_check(JSON.stringify(back) == JSON.stringify(old_siege), "旧档来回不添键（%s）" % JSON.stringify(back))
	# 5c SaveLoad 真存真读（存档位 88）：体检认得外援键、读回同值，JSON 读回的数照整数取
	_stage_siege(1276, 11, 3)
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	gs.siege_begin()
	for kv in [["convoy", 120], ["levy", 150], ["timber", 40], ["raid", "won"], ["raid_round", 2]]:
		gs.siege_set(str(kv[0]), kv[1])
	var sl: Node = root.get_node("/root/SaveLoad")
	_save_cleanup(sl)
	var saved: bool = sl.call("save_game", SAVE_SLOT, "xinghua")
	gs.from_dict({})
	var loaded: bool = sl.call("load_game", SAVE_SLOT)
	_check(saved and loaded and gs.siege_get("convoy") == 120 and gs.siege_get("levy") == 150 and gs.siege_get("timber") == 40
			and str(gs.siege.get("raid", "")) == "won" and gs.siege_get("raid_round") == 2
			and float(_main.call("_siege_raid_cut", 2)) == SiegeMelee.RAID_CUT,
		"存档位 %d 真存真读：外援键过体检、读回同值、第二阵照压（存 %s / 读 %s）" % [SAVE_SLOT, saved, loaded])
	_save_cleanup(sl)


func _save_cleanup(sl: Node) -> void:
	var base := str(sl.get("SAVE_DIR")) + "save_%d.json" % SAVE_SLOT
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(base + suffix):
			DirAccess.remove_absolute(base + suffix)


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

## 士人线改名、守城那年那月：城防还没开，进兴化即开（_siege_active）。船队回到开局那条小艍（6 人、水粮 60），职事清空
func _stage_siege(y: int, m: int, d: int) -> void:
	_close_sheet()
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	gs.money = 20000
	gs.fame = 30
	gs.last_port = "xinghua"
	cal.from_dict({"year": y, "month": m, "day": d})
	root.get_node("/root/Crew").from_dict({})
	fleet.ships = []
	fleet.add_ship("sampan", "无名小艍")
	fleet.water = 60
	fleet.food = 60
	fleet.morale = 70


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
