extends SceneTree
## lane-w53-16 战后单子与赏钱专项探针（战斗系统方案第一、二期，一条一节、回退即红）：
##   一、旗舰沉了由护航接任（已定 13c，一期）：旗舰沉了、护航还在时，沉船先要移出船队——
##       修前它以耐久 0 留在名册 0 号格，下一仗 Fleet.flagship() 还是它，4.7 秒就被跳帮。
##       格：① 名册剩 1 艘、无耐久 ≤ 0 的船；② 幸存护航顶成旗舰（舱货水手跟着它）；③ 坞位归 0；
##       ④ 札记写一句护航接任；⑤ 关 flagship_handoff 照旧（沉船以耐久 0 留名册、无接任句）。
##   二、赏钱按打法分（一期）：赏钱读 combat_phases.json「spoil」分赃规则——击沉 1/3（50–200）、
##       敌逃一半（75–300）、逼降全赏（150–600）、夺船给船不加钱；读不到数据退回旧区间 150–600 / 75–300。
##       修前不管什么打法一律 150–600，把敌船全打沉反而最划算。关 bounty_by_outcome 照旧区间。
##   三、战后单子（一期）：回海图不只一行钱数——先把敌船下场明细成句（谁降了、沉几艘、救起几人），
##       再写原账目行。修前两艘一降一沉，札记只有「敌船已退。获财货 N 钱…」一行。关 after_action 照旧。
##   四、大风两散（一期，机制归 w53-17 的 gale 键对接）：outcome = disengaged 且 data.gale 时
##       写「海风转厉，两边各自收帆。」，不写「天色晚了」；flee{parted} 照旧写天晚，两式两局可辨。
##   五、职事「杂事缴获」（二期）：没雇杂事赏钱照原价；雇了杂事每级多一成（spoil.zashi_spoil_mul_per_level）。
##       关 crew_role_effects 不加。
## 用法：godot --headless --path . -s res://tools/qa_w53_16_aftermath_probe.gd
## 末行 W53_16_AFTERMATH cases=N fails=M；fails>0 退 1。本进程有 SCRIPT ERROR 即红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CS := preload("res://scripts/combat/CombatSwitches.gd")

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	call_deferred("_run")


func _report() -> void:
	if _reported:
		return
	_reported = true
	await process_frame
	OS.remove_logger(_tally)
	_expect(_tally.lines.is_empty(), "本进程无 SCRIPT ERROR（%s）" % [
		"0 行" if _tally.lines.is_empty() else "%d 行：%s" % [_tally.lines.size(), str(_tally.lines[0])]])
	if fails == 0:
		print("W53_16_AFTERMATH cases=%d fails=0" % cases)
		quit(0)
		return
	print("W53_16_AFTERMATH cases=%d fails=%d" % [cases, fails])
	quit(1)


func _run() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	var gm: Node = root.get_node("GameManager")
	var saved := {
		"ships": (fleet.get("ships") as Array).duplicate(true),
		"morale": fleet.get("morale"),
		"berth": gs.get("berth_index"),
		"money": gs.get("money"),
		"fame": gs.get("fame"),
		"hired": (root.get_node("Crew").get("hired") as Dictionary).duplicate(true),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true),
	}
	await _sec_flagship_handoff(fleet, gs)
	await _sec_bounty(fleet, gs)
	await _sec_after_action(fleet, gs)
	await _sec_gale(fleet, gs)
	await _sec_zashi(fleet, gs)
	CS.reset()
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gs.set("berth_index", saved["berth"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	gm.set("pending_battle", saved["pb"])
	root.get_node("Crew").set("hired", saved["hired"])
	await _report()


func _mk_ship(type_id: String, nm: String, dur: float, crew: int, cargo := {}) -> Dictionary:
	var fleet: Node = root.get_node("Fleet")
	var d: Dictionary = fleet.call("ship_def", type_id)
	return {"type": type_id, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1,
		"cargo": cargo, "durability": dur, "max_durability": float(d.get("durability", dur))}


## 真起一张 SeaChart、悬一段航程；调用方用完 free
func _mk_chart() -> Node:
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	return chart


## 给 SeaChart 喂一场胜局，取回现金实付（GameState.money 增量）
func _win_gain(chart: Node, gs: Node, data: Dictionary) -> int:
	(chart.get("log_label") as RichTextLabel).text = ""
	gs.call("set", "money", 0)
	chart.call("_on_battle_result", "win", data)
	return int(gs.get("money"))


## 札记账面（「获财货 N 钱」那个 N）：探针账与实付对账用；取不到返 −1
func _win_logged(chart: Node) -> int:
	var log_text := (chart.get("log_label") as RichTextLabel).get_parsed_text()
	var i := log_text.find("获财货 ")
	if i < 0:
		return -1
	return log_text.substr(i + 4).split(" ")[0].to_int()


## ── 一、13c 旗舰沉了由护航接任 ─────────────────────────

func _sec_flagship_handoff(fleet: Node, gs: Node) -> void:
	print("== 一、旗舰沉了由护航接任（13c）")
	fleet.set("ships", [
		_mk_ship("sampan", "试旗舰", 0.0, 0),
		_mk_ship("fu_ship_medium", "护航甲", 260.0, 40, {"tea": {"qty": 5, "avg_cost": 20.0}}),
	])
	gs.set("berth_index", 1)
	var chart := _mk_chart()
	for _i in 4:
		await process_frame
	chart.set("remaining_li", 50.0)
	(chart.get("log_label") as RichTextLabel).text = ""
	chart.call("_on_battle_result", "lose", {"player_damage": 260.0, "sunk": true})
	var ships: Array = fleet.get("ships")
	var no_dead := true
	for s in ships:
		if float((s as Dictionary).get("durability", 0.0)) <= 0.0:
			no_dead = false
	_expect(ships.size() == 1 and no_dead,
		"沉旗舰移出船队（剩 %d 艘、无耐久 0 船=%s）" % [ships.size(), no_dead])
	var top: Dictionary = fleet.get("ships")[0] if fleet.get("ships").size() > 0 else {}
	_expect(str(top.get("name", "")) == "护航甲" and (top.get("cargo") as Dictionary).has("tea") and int(top.get("crew", 0)) == 40,
		"护航顶成旗舰，舱货水手跟着它（得 %s / crew %s / cargo %s）" % [
			top.get("name", "∅"), top.get("crew", "∅"), (top.get("cargo") as Dictionary).keys()])
	_expect(int(gs.get("berth_index")) == 0, "坞位归位到 0（得 %s）" % str(gs.get("berth_index")))
	var log_text := (chart.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(log_text.contains("接任旗舰"),
		"札记写了护航接任一句（得首段「%s」）" % log_text.left(80))
	chart.free()
	await process_frame
	# 开关关掉：照旧（沉船留名册、无接任句）
	CS.set_on("flagship_handoff", false)
	fleet.set("ships", [
		_mk_ship("sampan", "试旗舰", 0.0, 0),
		_mk_ship("fu_ship_medium", "护航甲", 260.0, 40),
	])
	var chart2 := _mk_chart()
	for _i in 4:
		await process_frame
	chart2.set("remaining_li", 50.0)
	(chart2.get("log_label") as RichTextLabel).text = ""
	chart2.call("_on_battle_result", "lose", {"player_damage": 260.0, "sunk": true})
	var ships2: Array = fleet.get("ships")
	var log2 := (chart2.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(ships2.size() == 2 and float((ships2[0] as Dictionary).get("durability", 1.0)) <= 0.0,
		"关 flagship_handoff 照旧：沉船以耐久 0 留在名册（%d 艘、旗舰耐久 %s）" % [
			ships2.size(), str((ships2[0] as Dictionary).get("durability", "∅"))])
	_expect(not log2.contains("接任旗舰"), "关时札记无接任句")
	chart2.free()
	CS.reset()
	await process_frame


## ── 二、赏钱按打法分 ─────────────────────────────────

func _sec_bounty(fleet: Node, gs: Node) -> void:
	print("== 二、赏钱按打法分（击沉 1/3・敌逃一半・逼降全赏）")
	fleet.set("ships", [_mk_ship("fu_ship_medium", "试船", 500.0, 40)])
	fleet.set("morale", 70)
	root.get_node("Crew").set("hired", {})
	var chart := _mk_chart()
	for _i in 4:
		await process_frame
	chart.set("remaining_li", 50.0)
	# 击沉全灭：多抽都须落在 50–200（全赏的三分之一）且现金实付一致
	var sunk_seen: Array = []
	for _i in 6:
		sunk_seen.append(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "sunk", "count": 2}]}))
	var sunk_ok := true
	for g in sunk_seen:
		if int(g) < 50 or int(g) > 200:
			sunk_ok = false
	_expect(sunk_ok, "击沉按三分之一分赃（六抽 %s，须各 ∈ [50, 200]）" % [sunk_seen])
	# 敌船全遁：75–300（半赏，照旧区间）
	var fled_seen: Array = []
	for _i in 4:
		fled_seen.append(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "fled", "count": 2}]}))
	var fled_ok := true
	for g in fled_seen:
		if int(g) < 75 or int(g) > 300:
			fled_ok = false
	_expect(fled_ok, "敌逃一半（四抽 %s，须各 ∈ [75, 300]）" % [fled_seen])
	# 有降幡：全赏 150–600；一降一沉不再被「先沉后遁」拖半
	var full_seen: Array = []
	for _i in 4:
		full_seen.append(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "struck", "count": 1},
				{"type": "pirate_boat", "fate": "sunk", "count": 1}]}))
	var full_ok := true
	for g in full_seen:
		if int(g) < 150 or int(g) > 600:
			full_ok = false
	_expect(full_ok, "有降幡全赏（四抽 %s，须各 ∈ [150, 600]）" % [full_seen])
	# 夺船：船给船，钱不给
	var boarded_gain := _win_gain(chart, gs, {"player_damage": 0.0, "boarded": true,
		"fates": [{"type": "pirate_boat", "fate": "boarded", "count": 1}]})
	_expect(int(boarded_gain) == 0, "夺船给船不加钱（得 %d 钱）" % int(boarded_gain))
	# 现金实付与札记账面一致：抽同一笔
	var paid1 := _win_gain(chart, gs, {"player_damage": 30.0,
		"fates": [{"type": "pirate_boat", "fate": "sunk", "count": 1}]})
	var log1 := _win_logged(chart)
	_expect(paid1 == log1, "札记账面（获财货 %d 钱）与现金实付（%d）一致" % [log1, paid1])
	chart.free()
	await process_frame
	# 开关关掉：不管什么打法一律 150–600（旧区间）
	CS.set_on("bounty_by_outcome", false)
	var chart2 := _mk_chart()
	for _i in 4:
		await process_frame
	chart2.set("remaining_li", 50.0)
	var off_seen: Array = []
	for _i in 4:
		off_seen.append(_win_gain(chart2, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "sunk", "count": 2}]}))
	var off_ok := true
	for g in off_seen:
		if int(g) < 150 or int(g) > 600:
			off_ok = false
	_expect(off_ok, "关 bounty_by_outcome 照全赏旧区间（四抽 %s，须各 ∈ [150, 600]）" % [off_seen])
	chart2.free()
	CS.reset()
	await process_frame


## ── 三、战后单子 ────────────────────────────────────

func _sec_after_action(fleet: Node, gs: Node) -> void:
	print("== 三、战后单子（敌船下场、救起几人成句）")
	fleet.set("ships", [_mk_ship("fu_ship_medium", "试船", 500.0, 40)])
	fleet.set("morale", 70)
	root.get_node("Crew").set("hired", {})
	var chart := _mk_chart()
	for _i in 4:
		await process_frame
	chart.set("remaining_li", 50.0)
	(chart.get("log_label") as RichTextLabel).text = ""
	chart.call("_on_battle_result", "win", {"player_damage": 12.0, "rescued": 8,
		"fates": [{"type": "sea_falcon", "fate": "sunk", "count": 1},
			{"type": "pirate_boat", "fate": "struck", "count": 1}]})
	var log_text := (chart.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(log_text.contains("击沉") and log_text.contains("受降"),
		"单子写了敌船下场（击沉、受降）（首段「%s」）" % log_text.left(80))
	_expect(log_text.contains("救起水手八人"), "单子写了救起几人（得「%s」）" % log_text.left(100))
	_expect(log_text.contains("获财货"), "账目行照旧（那句还在）")
	chart.free()
	await process_frame
	# 开关关掉：照旧只一行账目
	CS.set_on("after_action", false)
	var chart2 := _mk_chart()
	for _i in 4:
		await process_frame
	chart2.set("remaining_li", 50.0)
	(chart2.get("log_label") as RichTextLabel).text = ""
	chart2.call("_on_battle_result", "win", {"player_damage": 12.0, "rescued": 8,
		"fates": [{"type": "sea_falcon", "fate": "sunk", "count": 1}]})
	var log2 := (chart2.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(not log2.contains("击沉") and not log2.contains("救起"),
		"关 after_action 照旧只一行（无下场句、无救起句）（得「%s」）" % log2.left(60))
	chart2.free()
	CS.reset()
	await process_frame


## ── 四、大风两散 ────────────────────────────────────

func _sec_gale(fleet: Node, gs: Node) -> void:
	print("== 四、大风两散收场文字（gale 键）")
	fleet.set("ships", [_mk_ship("fu_ship_medium", "试船", 500.0, 40)])
	fleet.set("morale", 70)
	var chart := _mk_chart()
	for _i in 4:
		await process_frame
	chart.set("remaining_li", 50.0)
	(chart.get("log_label") as RichTextLabel).text = ""
	chart.call("_on_battle_result", "disengaged", {"player_damage": 0.0, "parted": true, "gale": true})
	var log_gale := (chart.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(log_gale.contains("海风转厉"), "起风两散写「海风转厉」（得「%s」）" % log_gale.left(40))
	_expect(not log_gale.contains("天色晚了"), "起风两散不写「天色晚了」")
	(chart.get("log_label") as RichTextLabel).text = ""
	chart.call("_on_battle_result", "flee", {"player_damage": 0.0, "flee_ok": true, "parted": true})
	var log_parted := (chart.get("log_label") as RichTextLabel).get_parsed_text()
	_expect(log_parted.contains("天色晚了"), "天黑两散照旧写「天色晚了」（得「%s」）" % log_parted.left(40))
	chart.free()
	await process_frame


## ── 五、职事「杂事缴获」──────────────────────────────

func _sec_zashi(fleet: Node, gs: Node) -> void:
	print("== 五、职事「杂事缴获」")
	fleet.set("ships", [_mk_ship("fu_ship_medium", "试船", 500.0, 40)])
	fleet.set("morale", 70)
	var crew: Node = root.get_node("Crew")
	var chart := _mk_chart()
	for _i in 4:
		await process_frame
	chart.set("remaining_li", 50.0)
	# 先无糖（全赏 150–600），再雇三级杂事（+30% 落在 195–780；区间不重叠，增益界定得住）
	crew.set("hired", {})
	var plain: Array = []
	for _i in 4:
		plain.append(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "struck", "count": 1}]}))
	crew.set("hired", {"zashi": "ye_shibo"})
	var lvl := int(crew.call("level_of", "zashi"))
	var spiced: Array = []
	for _i in 4:
		spiced.append(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "struck", "count": 1}]}))
	var plain_ok := true
	for g in plain:
		if int(g) < 150 or int(g) > 600:
			plain_ok = false
	var spiced_ok := true
	for g in spiced:
		if int(g) < 195 or int(g) > 780:
			spiced_ok = false
	_expect(lvl == 3 and plain_ok, "无杂事照原价（四抽 %s，须各 ∈ [150, 600]；杂事级 %d）" % [plain, lvl])
	_expect(spiced_ok, "三级杂事每级多一成（四抽 %s，须各 ∈ [195, 780]——不带糖到不了 195）" % [spiced])
	# 开关关掉：雇着杂事也不加糖（≤ 600 上限封）
	CS.set_on("crew_role_effects", false)
	var off_hi := -1
	for _i in 4:
		off_hi = maxi(off_hi, int(_win_gain(chart, gs, {"player_damage": 30.0,
			"fates": [{"type": "pirate_boat", "fate": "struck", "count": 1}]})))
	_expect(off_hi <= 600, "关 crew_role_effects 不加杂事糖（四抽最高 %d，应 ≤ 600）" % off_hi)
	CS.reset()
	chart.free()
	await process_frame
