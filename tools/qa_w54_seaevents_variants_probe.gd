extends SceneTree
## lane w54-seaevents：海上遇事变体（开关 sea_event_variants）专项探针——只换字，扣数、行程与骰序一字不动；关 = 逐字回旧。
## 断言：
##   V0 开关关：十二个月、逐日轮过，风涛起笔 / 无风带 / 不明船影 / 海上相逢没谈成买卖 / 迷航五处逐字是原句。
##   V1 风涛：十月到二月写北风、五六月南风带雨、七到九月飓母、三四月风向不定；风势重（severity ≥ 0.8）补「船身吃不住劲」；
##      风涛扣的船体、损的货与札记里那两句（「舱内货物翻倒，损折」「船体受损 N」）开关两侧一样。
##   V2 无风带：五到九月烈日、二到四月大雾、其余月份原句。
##   V3 不明船影：按日子轮出三句，句句「两条快船」「不挂旗」（与 SeaChart.PIRATE_ENEMY 两艘同数）。
##   V4 海上相逢没谈成买卖：轮出三句，句句「没谈成买卖」、后接对方说的那条行情；新添两句不提淡水。
##   V5 迷航：轮出两句，句句「白走了，还退回去一截」（行程系数照旧 LOST_PROGRESS）。
##   V6 骰序不动：同一种子真抽三千日（泉州→明州针路、1276-06 战时），开关两侧逐日遇的事、风势、行程系数、买卖开价、
##      收尾的船队（船体、货、士气、水粮）全同，只有字不同。
## 运行期脚本错即红（共用件 tools/script_err_tally.gd；_run_guarded 兜 _run 半路中止）。
## 用法：godot --headless --path . -s res://tools/qa_w54_seaevents_variants_probe.gd（经门锁跑）
## 末行 W54_SEAEVENTS_VARIANTS cases=N fails=M；M>0 时 exit 1。
## -s 下勿写 autoload 标识符（编译期尚无 autoload），一律 root.get_node 取。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")
const KEY := "sea_event_variants"

var _gs: Node
var _cal: Node
var _fleet: Node
var _voy: Node
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
	_gs = root.get_node_or_null("GameState")
	_cal = root.get_node_or_null("Calendar")
	_fleet = root.get_node_or_null("Fleet")
	_voy = root.get_node_or_null("Voyage")
	if _gs == null or _cal == null or _fleet == null or _voy == null:
		_expect(false, "autoload 不全")
		_report()
		return
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", "quanzhou")
	_fleet.set("at_sea", false)
	_expect(Switches.DEFAULTS.has(KEY) and bool(Switches.DEFAULTS.get(KEY, false)), "开关 %s 在表里、默认开" % KEY)
	var storm_old := str(_voy.get("STORM_OPEN_OLD"))
	var calm_old := str(_voy.get("CALM_OLD"))
	var sight_old := str(_voy.get("SIGHTING_OLD"))
	var pass_old := str(_voy.get("PASSING_OLD"))
	var lost_old := str(_voy.get("LOST_OLD"))
	_expect(storm_old.begins_with("风起于西北") and calm_old.begins_with("海面平得像一张铺开的绢") and sight_old.begins_with("桅斗上的瞭望手")
		and pass_old.begins_with("迎面来了一条福船") and lost_old.begins_with("海图上这一段是空白"), "原句五处照旧存着")

	print("── V0 开关关：逐字原句")
	Switches.set_on(KEY, false)
	var same := true
	for m in range(1, 13):
		for d in [1, 2, 3, 4]:
			_cal.call("from_dict", {"year": 1260, "month": m, "day": d})
			if str(_voy.call("_storm_opening", 0.95)) != storm_old or str(_voy.call("_calm_text")) != calm_old \
					or str(_voy.call("_sighting_text")) != sight_old or str(_voy.call("_passing_text")) != pass_old \
					or str(_voy.call("_lost_text")) != lost_old:
				same = false
	_expect(same, "V0 关着时十二个月逐日五处都是原句")
	_fleet_one()
	_cal.call("from_dict", {"year": 1260, "month": 8, "day": 5})
	seed(77)
	var ev_off: Dictionary = _voy.call("_storm_event")
	_expect(str(ev_off.get("text", "")).begins_with(storm_old), "V0 关着时真走 _storm_event 起笔是原句")

	print("── V1 风涛")
	Switches.set_on(KEY, true)
	var want := {12: "北风", 1: "北风", 6: "南风", 8: "飓母", 9: "飓母", 4: "风向说变就变"}
	for m in want.keys():
		_cal.call("from_dict", {"year": 1260, "month": int(m), "day": 5})
		var light := str(_voy.call("_storm_opening", 0.5))
		var heavy := str(_voy.call("_storm_opening", 0.9))
		_expect(light.contains(str(want[m])) and not light.contains("吃不住劲") and heavy.begins_with(light) and heavy.contains("吃不住劲"),
			"V1 %d 月风涛起笔「%s」，风势重补「%s」" % [int(m), light, heavy.substr(light.length())])
	var cmp_ok := true
	for m in [1, 5, 8, 11]:
		var off_on: Array = []
		for on in [false, true]:
			Switches.set_on(KEY, on)
			_fleet_one()
			_fleet.call("add_cargo", "qingbai_porcelain", 20, 90.0, 0)
			_cal.call("from_dict", {"year": 1260, "month": m, "day": 5})
			seed(4000 + m)
			var ev: Dictionary = _voy.call("_storm_event")
			var txt := str(ev.get("text", ""))
			var tail := txt.substr(txt.find("\n")) if txt.find("\n") >= 0 else ""
			off_on.append([tail, float(ev.get("severity", 0.0)), _fleet.call("to_dict")])
		if str(off_on[0][0]) != str(off_on[1][0]) or not is_equal_approx(float(off_on[0][1]), float(off_on[1][1])) \
				or str(off_on[0][2]) != str(off_on[1][2]):
			cmp_ok = false
			print("    %d 月：关「%s」/ 开「%s」" % [m, str(off_on[0][0]), str(off_on[1][0])])
	Switches.set_on(KEY, true)
	_expect(cmp_ok, "V1 风涛扣的船体、损的货、札记里损折与受损那两句开关两侧一样（1 / 5 / 8 / 11 月）")

	print("── V2 无风带")
	var calm_want := {7: "日头毒", 3: "大雾", 11: calm_old, 1: calm_old}
	for m in calm_want.keys():
		_cal.call("from_dict", {"year": 1260, "month": int(m), "day": 5})
		var t := str(_voy.call("_calm_text"))
		_expect(t.contains(str(calm_want[m])), "V2 %d 月无风带「%s」" % [int(m), t])
	_cal.call("from_dict", {"year": 1260, "month": 7, "day": 5})
	var calm_ev: Dictionary = _voy.call("_calm_event")
	_expect(int(calm_ev.get("kind", -1)) == int((_voy.get("EventKind") as Dictionary)["CALM"]) and str(calm_ev.get("text", "")).contains("日头毒"),
		"V2 真走 _calm_event 也换句、kind 照旧")

	print("── V3 不明船影 / V4 海上相逢 / V5 迷航")
	var sights := {}
	var passes := {}
	var losts := {}
	for d in range(1, 13):
		_cal.call("from_dict", {"year": 1260, "month": 6, "day": d})
		sights[str(_voy.call("pirate_sighting").get("text", ""))] = true
		passes[str(_voy.call("_passing_text"))] = true
		losts[str(_voy.call("_lost_event").get("text", ""))] = true
	var sight_ok := sights.size() == 3
	for t in sights.keys():
		sight_ok = sight_ok and str(t).contains("两条快船") and str(t).contains("不挂旗")
	_expect(sight_ok, "V3 不明船影轮出 %d 句，句句两条快船、不挂旗" % sights.size())
	var pass_ok := passes.size() == 3
	for t in passes.keys():
		pass_ok = pass_ok and str(t).contains("没谈成买卖") and str(t).ends_with("\n") and (str(t) == pass_old or not str(t).contains("淡水"))
	_expect(pass_ok, "V4 海上相逢没谈成买卖轮出 %d 句，句句没谈成买卖、新添的不提淡水" % passes.size())
	var lost_ok := losts.size() == 2
	for t in losts.keys():
		lost_ok = lost_ok and str(t).contains("白走了，还退回去一截")
	_expect(lost_ok, "V5 迷航轮出 %d 句，句句白走了还退回去一截" % losts.size())
	# 真走 _merchant_event：没谈成买卖那一面也接上对方说的行情
	_fleet_one()
	_fleet.set("food", 60)
	var joined := false
	seed(91)
	for _i in 400:
		var mev: Dictionary = _voy.call("_merchant_event", "quanzhou")
		var tx := str(mev.get("text", ""))
		if str(mev.get("offer", "")) == "rumor" and tx.contains("没谈成买卖") and tx.contains("对方说"):
			joined = true
			break
	_expect(joined, "V4 真走 _merchant_event：没谈成买卖那一面后接对方说的行情")

	print("── V6 骰序不动")
	var runs: Array = []
	for on in [false, true]:
		Switches.set_on(KEY, on)
		_fleet_one()
		_fleet.call("add_cargo", "qingbai_porcelain", 30, 90.0, 0)
		_fleet.call("add_cargo", "tea", 20, 25.0, 0)
		_cal.call("from_dict", {"year": 1276, "month": 6, "day": 5})
		_voy.call("begin_voyage")
		seed(5407)
		var trace: Array = []
		for _i in 3000:
			var ev: Dictionary = _voy.call("roll_day_event", 35.0, "quanzhou", "mingzhou")
			trace.append([int(ev.get("kind", 0)), snappedf(float(ev.get("severity", 0.0)), 0.0001), float(ev.get("progress_mult", 1.0)),
				str(ev.get("offer", "")), str(ev.get("good_id", "")), int(ev.get("qty", 0)), int(ev.get("unit", 0))])
		runs.append([trace, str(_fleet.call("to_dict"))])
	Switches.set_on(KEY, true)
	var diff_at := -1
	for i in (runs[0][0] as Array).size():
		if str(runs[0][0][i]) != str(runs[1][0][i]):
			diff_at = i
			break
	_expect(diff_at < 0 and str(runs[0][1]) == str(runs[1][1]),
		"V6 同种子三千日：逐日遇事 / 风势 / 行程系数 / 买卖开价开关两侧全同（头一处不同 %d）、收尾船队相同" % diff_at)
	Switches.reset()
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fleet_one() -> void:
	_fleet.set("ships", [])
	_fleet.call("add_ship", "fu_ship_medium", "探针福船")
	_fleet.set("water", 60)
	_fleet.set("food", 60)
	_fleet.set("morale", 70)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W54_SEAEVENTS_VARIANTS cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)
