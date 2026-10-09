extends SceneTree
## lane-w53-p4-after 战后取舍专项探针（战斗系统方案 §三「战后」、§九「战后单子」，一条一节、回退即红）：
##   一、押船（waa_prize）：夺来 / 受降的船要分人看守，每艘至少 after_action.prize.min_crew 人；
##       人手够全押（并入船队照旧在册），人手不够差几艘漂几艘（从名册尾摘掉）；
##       drift = 全放漂。开关关 = 没有这一行、名册不动。
##   二、救人（waa_rescue）：救 = 加名声（after_action.rescue.fame）、救上来愿留下的编入船队
##       （上限 rescue.enlist_cap，受船队总人数上限管）；不救 = 什么都不动。
##       战败落水按战沉水手半数捞回（AfterAction.LOSE_RESCUE_DIV=2，仅开关开时）。
##   三、俘虏（waa_captives）：收编（hire_crew 聚合逐船填，受 crew_max 上限，填不下的遣散）；
##       卖掉（得钱 = 俘虏数 × captives.sell_price、掉名声）；放走（加名声）。
##   四、索赎（waa_ransom）：放船换赎金——当场折价兑付 = 俘虏数 × ransom.each 钱；
##       方案「30 天后在对方港口兑付」要跨场记账、不做（不改存档格式）；作罢 = 不动。
##   五、追击（waa_pursue）：敌船逃了可选追——按我速 / 敌速（敌船 base_speed × pursue.enemy_speed_ratio）
##       掷一次，追上比照夺船并入船队（Fleet.add_ship 原路 + settle_prize）；没追上挨一顿舷炮
##       （after_action.pursue.broadside_hits 门 × 战后一发船体伤 × 敌船体 / 300）；收队 = 不动。
##   六、开关全关 = 逐字回旧（win 分支没有「战后收拾」小卡、札记不缀选择句、名册 / 钱 / 名声 / 水手不动）。
##   七、默认项不更赚：win 时全部走 default（押船 keep / 救人 save / 俘虏收编 / 索赎作罢 / 追击收队），
##       账与「什么都不挂」对得上——默认项不会让玩家长期多拿钱 / 人 / 船。
## 用法：godot --headless --path . -s res://tools/qa_w53_p4_after_choices_probe.gd
## 判词：QA_W53_P4_AFTER_CHOICES cases=N fails=M；fails>0 退 1。本进程有 SCRIPT ERROR 即红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CS := preload("res://scripts/combat/CombatSwitches.gd")
const AA := preload("res://scripts/combat/AfterAction.gd")
const LB := preload("res://scripts/ui/CombatLetterbox.gd")

const TAG := "QA_W53_P4_AFTER_CHOICES"

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
		print("%s cases=%d fails=0" % [TAG, cases])
		quit(0)
		return
	print("%s cases=%d fails=%d" % [TAG, cases, fails])
	quit(1)


func _run() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gs: Node = root.get_node("GameState")
	var saved := {
		"ships": (fleet.get("ships") as Array).duplicate(true),
		"morale": fleet.get("morale"),
		"money": gs.get("money"),
		"fame": gs.get("fame"),
	}

	print("== 一、押船（waa_prize）")
	_sec_prize(fleet)
	print("== 二、救人（waa_rescue）")
	_sec_rescue(fleet, gs)
	print("== 三、俘虏（waa_captives）")
	_sec_captives(fleet, gs)
	print("== 四、索赎（waa_ransom）")
	_sec_ransom(fleet, gs)
	print("== 五、追击（waa_pursue）")
	_sec_pursue(fleet)
	print("== 六、开关全关 = 逐字回旧")
	_sec_off(fleet, gs)
	print("== 七、默认项不更赚")
	_sec_default(fleet, gs)

	CS.reset()
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	await _report()


# ── 造局 ─────────────────────────────────────────────

## 造一张船队：主船 fu_ship_medium 满编 crew 人，夺来的船照 WorldMap 附加在名册尾、所载水手 crew_min 半数。
## main_crew 是主船水手——人手账照「名册全员」走（押船那几艘也占 headcount，凑不齐 6 就漂）；
## 返回起名册船数
func _fleet_at(fleet: Node, main_crew: int, prize_count := 0, prize_crew_each := -1) -> int:
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	var arr: Array = [{"type": "fu_ship_medium", "name": "旗舰", "crew": main_crew, "sail_level": 1,
		"armor_level": 1, "cargo": {}, "durability": float(d.get("durability", 300)),
		"max_durability": float(d.get("durability", 300))}]
	var pd: Dictionary = fleet.call("ship_def", "pirate_boat")
	var pc_each := prize_crew_each if prize_crew_each >= 0 else maxi(1, int(int(pd.get("crew_min", 8)) / 2))
	for i in prize_count:
		arr.append({"type": "pirate_boat", "name": "快船", "crew": pc_each,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": float(pd.get("durability", 120)),
			"max_durability": float(pd.get("durability", 120))})
	fleet.set("ships", arr)
	return 1 + prize_count


## 夺一降一的胜局 data（fates 两条：boarded 一 + struck 一）
func _win_board_struck() -> Dictionary:
	return {"player_damage": 8.0, "boarded": true,
		"fates": [{"type": "pirate_boat", "fate": "boarded", "count": 1},
			{"type": "sea_falcon", "fate": "struck", "count": 1}]}


## 击沉一 + 受降一（有落水可救、有俘虏）
func _win_sunk_struck() -> Dictionary:
	return {"player_damage": 10.0,
		"fates": [{"type": "pirate_boat", "fate": "sunk", "count": 1},
			{"type": "sea_falcon", "fate": "struck", "count": 1}]}


## 敌遁一（可追）：夺一 + 遁一
func _win_board_fled() -> Dictionary:
	return {"player_damage": 6.0, "boarded": true,
		"fates": [{"type": "pirate_boat", "fate": "boarded", "count": 1},
			{"type": "pirate_boat", "fate": "fled", "count": 1}]}


# ── 一、押船 ─────────────────────────────────────────

func _sec_prize(fleet: Node) -> void:
	# 人手够（主船满编 40 + 名册 3 艘、两艘夺来）——keep 全押，一艘不漂
	_fleet_at(fleet, 40, 2)
	CS.set_on("waa_prize", true)
	var data := _win_board_struck()
	var choices := AA.choices_for("win", data)
	var prize_row := _row_of(choices, "prize")
	_expect(not prize_row.is_empty(), "开：押船行挂上（夺一降一）")
	var r: Dictionary = AA.apply(_chosen_row(prize_row, "keep"), "win", data)
	_expect(bool(r.get("ok", false)), "keep：落账 ok")
	_expect(int(r.get("boarded_added", -1)) == 2, "keep：人手够全押 2 艘（得 %d）" % int(r.get("boarded_added", -1)))
	_expect(int(r.get("boarded_drifted", -1)) == 0, "keep：一艘不漂（得 %d）" % int(r.get("boarded_drifted", -1)))
	_expect(str(r.get("note", "")).contains("押定"), "keep：注记句写分人押定（得「%s」）" % str(r.get("note", "")))

	# 人手不够：名册全员只留 7 个（主船 5 + 夺来两艘各 1）——keep 一艘要 6 人，押得下 1 艘，漂 1 艘
	_fleet_at(fleet, 5, 2, 1)
	var r2: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "prize"), "keep"), "win", data)
	_expect(int(r2.get("boarded_added", -1)) == 1, "keep：人手 7 只押 1 艘（得 %d）" % int(r2.get("boarded_added", -1)))
	_expect(int(r2.get("boarded_drifted", -1)) == 1, "keep：人手 7 漂 1 艘（得 %d）" % int(r2.get("boarded_drifted", -1)))
	_expect(str(r2.get("note", "")).contains("漂走"), "keep：注记句写漂走（得「%s」）" % str(r2.get("note", "")))

	# drift：全放漂
	_fleet_at(fleet, 40, 2)
	var r3: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "prize"), "drift"), "win", data)
	_expect(int(r3.get("boarded_added", -1)) == 0, "drift：一艘不留（得 %d）" % int(r3.get("boarded_added", -1)))
	_expect(int(r3.get("boarded_drifted", -1)) == 2, "drift：全 2 艘漂走（得 %d）" % int(r3.get("boarded_drifted", -1)))

	# 开关关：没有押船行
	CS.set_on("waa_prize", false)
	var c_off := AA.choices_for("win", data)
	_expect(_row_of(c_off, "prize").is_empty(), "关：押船行不挂（得 rows=%s）" % [c_off.map(func(x): return str(x.get("key", "")))])
	CS.set_on("waa_prize", true)


# ── 二、救人 ─────────────────────────────────────────

func _sec_rescue(fleet: Node, gs: Node) -> void:
	_fleet_at(fleet, 40)
	CS.set_on("waa_rescue", true)
	var data := _win_sunk_struck()
	var pool := AA._rescue_pool(data)
	_expect(pool > 0, "开：落水可救 pool > 0（得 %d）" % pool)
	var fame0 := int(gs.get("fame"))
	gs.set("fame", 0)
	var r: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "rescue"), "save"), "win", data)
	_expect(bool(r.get("ok", false)), "save：落账 ok")
	_expect(int(r.get("crew_enlisted", -1)) == mini(pool, 4), "save：收编入伍 %d = min(pool %d, cap 4)" % [
		int(r.get("crew_enlisted", -1)), pool])
	_expect(int(r.get("fame_gained", -1)) == 2, "save：名声 +2（得 %d）" % int(r.get("fame_gained", -1)))
	_expect(str(r.get("note", "")).contains("救起水手"), "save：注记句写救起（得「%s」）" % str(r.get("note", "")))
	gs.set("fame", fame0)

	# 不救：不动（leave 那一格 crew_enlisted 留默认 0，不落「编入」）
	var r2: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "rescue"), "leave"), "win", data)
	_expect(bool(r2.get("ok", false)) and str(r2.get("note", "")).contains("没下水"), "leave：注记句写没下水救人（得「%s」）" % str(r2.get("note", "")))
	_expect(int(r2.get("fame_gained", -1)) == 0, "leave：不加名声（得 %d）" % int(r2.get("fame_gained", -1)))

	# 战败落水捞回：战沉水手 14，开关开 = 7；关 = 0
	CS.set_on("waa_rescue", true)
	var lr: Dictionary = AA.apply_lose({"losses": {"crew": 14}})
	_expect(int(lr.get("rescued", -1)) == 7, "战败：战沉 14 捞回 7（得 %d）" % int(lr.get("rescued", -1)))
	CS.set_on("waa_rescue", false)
	_expect(AA.lose_rescue_of({"losses": {"crew": 14}}) == 0, "关：不捞（得 0）")
	CS.set_on("waa_rescue", true)


# ── 三、俘虏 ─────────────────────────────────────────

func _sec_captives(fleet: Node, gs: Node) -> void:
	_fleet_at(fleet, 40)
	CS.set_on("waa_captives", true)
	var data := _win_board_struck()
	var n := AA._prisoner_count(data)
	_expect(n > 0, "开：俘虏 %d > 0" % n)

	# 收编：crew_max 还有位就补进去
	var crew0 := int(fleet.call("total_crew"))
	var max0 := int(fleet.call("crew_max"))
	var room := max0 - crew0
	var r: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "captives"), "enlist"), "win", data)
	_expect(int(r.get("crew_delta", -1)) == mini(n, maxi(0, room)), "enlist：受上限收 %d（房间 %d、俘虏 %d）" % [
		int(r.get("crew_delta", -1)), room, n])
	_expect(str(r.get("note", "")).contains("收编"), "enlist：注记句写收编（得「%s」）" % str(r.get("note", "")))

	# 卖掉
	gs.set("money", 0)
	var fame0 := int(gs.get("fame"))
	var r2: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "captives"), "sell"), "win", data)
	_expect(int(r2.get("money", -1)) == n * 25, "sell：得钱 %d（得 %d）" % [n * 25, int(r2.get("money", -1))])
	_expect(int(r2.get("fame_gained", -1)) == -2, "sell：掉名声 −2（得 %d）" % int(r2.get("fame_gained", -1)))

	# 放走
	var r3: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "captives"), "free"), "win", data)
	_expect(int(r3.get("fame_gained", -1)) == 2, "free：名声 +2（得 %d）" % int(r3.get("fame_gained", -1)))
	gs.set("fame", fame0)


# ── 四、索赎 ─────────────────────────────────────────

func _sec_ransom(fleet: Node, gs: Node) -> void:
	_fleet_at(fleet, 40)
	CS.set_on("waa_ransom", true)
	var data := _win_board_struck()
	var n := AA._prisoner_count(data)
	gs.set("money", 0)
	var r: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "ransom"), "ransom"), "win", data)
	_expect(int(r.get("money", -1)) == n * 40, "ransom：当场兑付 %d（得 %d）" % [n * 40, int(r.get("money", -1))])
	_expect(str(r.get("note", "")).contains("兑付"), "ransom：注记句写当场折价兑付（得「%s」）" % str(r.get("note", "")))
	# 作罢
	var r2: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "ransom"), "skip"), "win", data)
	_expect(int(r2.get("money", -1)) == 0, "skip：不得钱（得 %d）" % int(r2.get("money", -1)))


# ── 五、追击 ─────────────────────────────────────────

func _sec_pursue(fleet: Node) -> void:
	CS.set_on("waa_pursue", true)
	var data := _win_board_fled()
	var fled := AA._fled_ships(data)
	_expect(not fled.is_empty(), "开：有船遁走")
	# 我速（fu_ship_medium base_speed 145 × 帆 / 士气 / Crew.speed_factor）——探针梭子型舰队，追 pirate_boat（160 × 0.95 = 152）：
	# 掷 0.05..0.95 区间，能追上也能挨炮。这里不跑随机分布——只验两式账都落：
	# 追上 = ship_added 有字 + boarded_added +1；收队 = 空。
	_fleet_at(fleet, 40)
	var hold: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "pursue"), "hold"), "win", data)
	_expect(str(hold.get("ship_added", "x")) == "", "hold：不追、没夺（得「%s」）" % str(hold.get("ship_added", "x")))
	_expect(str(hold.get("note", "")).contains("收队"), "hold：注记句写收队（得「%s」）" % str(hold.get("note", "")))

	# 追：不判随机结果（速度比掷出来哪面都有），只判账自洽——
	# 追上 ship_added=船种 / boarded_added+1 / 注记句写夺下；没追上 / 没了 pursuit_roll=missed / 注记句写挨炮。
	var chase: Dictionary = AA.apply(_chosen_row(_row_of(AA.choices_for("win", data), "pursue"), "chase"), "win", data)
	var roll := str(chase.get("pursuit_roll", ""))
	_expect(roll == "caught" or roll == "missed", "chase：掷出 caught / missed（得「%s」）" % roll)
	if roll == "caught":
		_expect(str(chase.get("ship_added", "")) == str(fled[0].get("type", "")),
			"chase 追上：ship_added = %s" % str(fled[0].get("type", "")))
		_expect(int(chase.get("boarded_added", -1)) >= 1, "chase 追上：boarded_added+1（得 %d）" % int(chase.get("boarded_added", -1)))
	else:
		_expect(str(chase.get("ship_added", "x")) == "", "chase 没追上：没夺（得「%s」）" % str(chase.get("ship_added", "x")))
		_expect(str(chase.get("note", "")).contains("舷炮"), "chase 没追上：注记句写挨舷炮（得「%s」）" % str(chase.get("note", "")))
		# 挨舷炮的实数（pursuit_damage）：broadside_hits × 一发 × 敌体/300
		var dmg := AA.pursuit_damage(data, 5.0)
		_expect(dmg > 5.0, "chase 没追上：pursuit_damage 一舷 > 一发（得 %.1f）" % dmg)

	# 开关关：没有追击行
	CS.set_on("waa_pursue", false)
	_expect(_row_of(AA.choices_for("win", data), "pursue").is_empty(), "关：追击行不挂")
	CS.set_on("waa_pursue", true)


# ── 六、开关全关 ─────────────────────────────────────

func _sec_off(fleet: Node, gs: Node) -> void:
	_fleet_at(fleet, 40)
	gs.set("money", 0)
	var fame0 := int(gs.get("fame"))
	CS.set_on("waa_prize", false)
	CS.set_on("waa_rescue", false)
	CS.set_on("waa_captives", false)
	CS.set_on("waa_ransom", false)
	CS.set_on("waa_pursue", false)
	var data := _win_board_struck()
	var choices := AA.choices_for("win", data)
	_expect(choices.is_empty(), "全关：一行不挂（得 %d 行）" % choices.size())
	# 战败也不捞
	_expect(AA.lose_rescue_of({"losses": {"crew": 14}}) == 0, "全关：战败不捞")
	gs.set("fame", fame0)


# ── 七、默认项不更赚 ──────────────────────────────────

func _sec_default(fleet: Node, gs: Node) -> void:
	_fleet_at(fleet, 40, 2)
	gs.set("money", 0)
	var fame0 := int(gs.get("fame"))
	var data := _win_board_struck()
	CS.reset()  # 全开
	var choices := AA.choices_for("win", data)
	# 玩家什么都不点 = 全走 default：逐项落账、统计账
	var money_sum := 0
	var fame_sum := 0
	var ships_added := 0
	var crew_sum := 0
	for row in choices:
		var opts = row.get("options", [])
		var def_id := ""
		for o in opts:
			if bool(o.get("default", false)):
				def_id = str(o.get("id", ""))
				break
		if def_id == "":
			def_id = str(opts[0].get("id", ""))
		var c := (row as Dictionary).duplicate()
		c["chosen"] = def_id
		var r: Dictionary = AA.apply(c, "win", data)
		money_sum += int(r.get("money", 0))
		fame_sum += int(r.get("fame_gained", 0))
		ships_added += 1 if str(r.get("ship_added", "")) != "" else 0
		crew_sum += int(r.get("crew_delta", 0))
	# 默认账 vs 旧玩法（赏钱 spoil 由 win 分支原路给，本探针不算）：
	# 押船 keep = 已在册的旧账（WorldMap 夺船时就并入）——名船只数不变（0）；旧玩法没有赎金这一笔（索赎作罢 = 0）；
	# 收编 = min(俘虏数, 上限)——上限拥紧时填不进、不白拿；旧玩法没有这一项，默认项也不该稳拿钱 / 船。
	_expect(ships_added == 0, "默认：追击收队，没多夺船（得 %d）" % ships_added)
	_expect(money_sum == 0, "默认：索赎作罢，没多拿钱（得 %d 钱）" % money_sum)
	_expect(fame_sum >= 0, "默认：名声不亏（得 %+d）" % fame_sum)
	# 默认收编俘虏 / 救起各按上限——受 crew_max 拥紧管：俘虏收编 mini(n, 房间)，救起 mini(pool, cap 4)
	_fleet_at(fleet, 40, 2)
	var data2 := _win_board_struck()
	var n_cap := AA._prisoner_count(data2)
	var room2 := int(fleet.call("crew_max")) - int(fleet.call("total_crew"))
	var crew_expect := mini(n_cap, maxi(0, room2)) + 4  # 俘虏 enlist mini(n, 房间) + 救起 mini(pool, cap)
	_expect(crew_sum <= crew_expect + 0, "默认：收编 / 救起合计 ≤ 账面 %d（得 %d）" % [crew_expect, crew_sum])
	gs.set("fame", fame0)


# ── 小工具 ──────────────────────────────────────────

## choices 里 key 那一行（没有返回 {}）
func _row_of(choices: Array, key: String) -> Dictionary:
	for row in choices:
		if row is Dictionary and str(row.get("key", "")) == key:
			return row
	return {}


## 挂上 chosen 后的行（探针直接喂 AA.apply 的那份）
func _chosen_row(row: Dictionary, chosen_id: String) -> Dictionary:
	if row.is_empty():
		return {}
	var c := row.duplicate()
	c["chosen"] = chosen_id
	return c
