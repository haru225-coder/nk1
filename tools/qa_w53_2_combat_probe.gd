extends SceneTree
## lane-w53-2 海战 / 接舷专项探针（headless）：真起 WorldMap 海战场（pending_battle），直调接舷 / 号令 / 收战那几支，
## 对账「题签上写的」与「船队 / 敌船身上真记的」。逐节：
##   一、白刃两边伤亡入账（本队先钩、白刃失利）：MeleeResolve 给的守方阵亡 def_dead 要从敌船水手里扣掉——
##       修复前只扣本队 att_dead，敌船人数一个不少，跳帮再败几回对面照样满员（回退即红：敌船水手 ≠ 开打前 − def_dead）。
##   二、敌船先抛钩 = 敌攻我守（PirateShip.boarding_initiator；combat_phases.json 转移 t_deck_lost / t_deck_held）：
##       修复前 WorldMap 一律按本队跳帮结算——敌船钩上来，记事却写「我 N 人跃过舷墙」「我退回本船」「敌斧手砍断钩缆」，
##       本队人少守不住也收不了战（敌船永远赢不了接舷），人多反倒把钩上来的敌船夺了。三格：
##       ① 6 人对 200 人：敌攻我守、敌胜 → 以 lose{overrun} 收战（失船面），本队不得船、守方阵亡从本队扣；
##       ② 200 人对 20 人：敌攻我守、我守住 → 不收战、敌船放钩仍在场、本队不得船，敌船扣攻方阵亡，敌将记「跳帮受挫」；
##       ③ 士气挂件：敌船先钩时敌簿记攻方、本队簿记守方；守住后本队簿提士气（旧口径反过来按我攻败记、压士气）。
##   三、号令浮字写中文名：按 1–5 下令，海战场中央浮字修复前是「号令：windward」「号令：load」——内部 id 直接上屏。
##       真起号令面板逐令 issue，浮字须是「号令：抢风 / 撤令：抢风 / 号令：专力装填 / 均装 / 救火 / 备接舷」、不含拉丁字母（火攻第十三节起撤出轮换）。
##   四、收战带本场折损：矢石 / 白刃折的水手、中弹颠落的舱面货，修复前收战 data 里一字不记（CombatLetterbox.loss_note 留着
##       「折水手 N 人」那一格没人填，SeaChart 札记也不提），出战墨边只写日期与敌船下场。折 7 人、颠落 4 件、中途夺船并入 40 人，
##       收战 data.losses 须恰为 {crew: 7, cargo: 4}（夺来的人不抵折损），墨边副题写「折水手七人，颠落舱面货四件」。
##   五、中弹只颠挨打那条船的舱面货：货分船装，海战里挨打的只有旗舰；修复前 Ship.take_hit 按全队合并的货随手挑一件、
##       remove_cargo 跨船依次扣——旗舰舱空、护航船装着生丝，旗舰每挨一发重击就颠掉护航船一件生丝。真走 take_hit 打旗舰四发：
##       ① 旗舰空舱、护航生丝 10 → 生丝一件不少；② 旗舰茶 5、护航生丝 10 → 每发船体伤 ≥ 5 颠旗舰一件茶，生丝仍 10。
##   六、喊话劝降得手的船接舷即收：降幡劝降走 PirateShip.strike_colours，敌将降了（节点 struck），士气簿原先不知道（第十一节起簿上同记）；
##       修复前 _board_enemy 只认簿上的 yields_to_boarding，竖着降幡的船一接舷照打满员白刃（实打 300 人：本队被击退）。
##       真起号令面板喊话（roll 定 0 必降）→ 接舷：须免白刃（_last_melee 空）、船入列、下场记受降 struck。
##       另验号令签面：喊降得手、冷却过后「降幡劝降」那格写「可喊 敌已降」（修复前照士气簿写「可喊 约 N 成 / 难成」，劝人降一艘已降的船）。
##   七、救火令随险情改损管令：面板只在下令那一刻按险情挑「戽水（只进水）/ 救火（有火或无险）」，之后一成不变——
##       只进水时下的救火令，后来起火仍按戽水派人（救火手封两成，比不下令的均衡四成五还少）。旗舰舱里先灌水、下救火令（戽水），
##       再点一处火：两帧内损管令须改成救火；把火扑灭、水还在：须改回戽水。
##   八、胜局札记不把元军哨船叫成海盗：SeaChart 打赢哪路敌船都用 CombatFx.sea_win_note，修复前那句写死「海盗已退」——
##       打赢元军哨船（_on_fight_patrol，source.event=yuan_patrol）札记也写「海盗已退。获财货…」。真起海图按哨船战果结算，
##       札记首行须以「敌船已退。」起头、不含「海盗」。
##   九、接踵的浮字不被上一条的淡出补间吃掉：海战场中央浮字（_show_combat_notice）每条停满 1.5 秒再淡，修复前上一条的补间不收——
##       它照旧在上一条出字后 1.5 s 起淡、2.5 s 藏字，隔 1.5–2.5 秒来的下一条（敌将改打法、士气纪实、抛钩、号令常这样接踵）只见一闪或看不到。
##       关掉别的浮字源，先出「甲」、隔 2 秒出「乙」：乙出字后 0.8 / 1.3 秒须仍满墨在屏（甲 1.3 秒时满墨，判据判得出）。
##   十、敌将状态机自检：EnemyCaptainAI.self_check（假局势逐条过接近 / 抢风 / 舷炮 / 接舷 / 脱离 / 降幡）原先没有一支探针调它，本节接上、一条不合即红。
##       其中一条：矢石将尽（≤ 两成五）又不够拼接舷时，舷炮守的射距带收进惜弹射距（SAVE_RANGE 内才放），相距 400 要往敌船靠——
##       修复前照旧守 260–540，多半兜在惜弹射距外：实打哨船一战，余弹那一两分钟在 360 内的只有几秒，到限时两散还剩一到六轮没放。
##       又一条：矢石打光时白刃比够得上本档案拼接舷的线（desperate）就贴、够不上就走——修复前走线写死 0.85（海寇那档），
##       哨船（线 1.3）比在 [0.85, 1.3) 的弹尽船既不贴也不走，兜着空舷直到限时两散（实打两场各兜 35 / 74 秒）。
##   十一、喊话劝降得手的末艘敌船按受降收战：修复前士气簿不知道敌将降了，在场敌船个个竖着降幡也不收战——
##       降船漂满 35 秒乘隙遁去，记成半赏的「敌船遁走」。一艘快船，喊话（roll 0 必降）：数帧内须以 win 收战一次、
##       morale_verdict = enemy_struck、下场记受降，海图 win_kind 判受降（全赏）；士气簿那页同记降幡。
##   十二、甩脱：修复前本船拉开了也收不了战——敌船出 2500 px 即休眠不动，只能空等 300 秒限时两散；按 B 弃战照掷航速骰，
##       敌船一屏开外休眠也会「未能甩脱，被追上跳帮」。现阶段图 t_outsailed：还在追打的敌船（没降、没在脱离）全在 escape_bu 外
##       满 shake_off_s 秒即按脱战 flee{flee_ok, shook_off} 收战；B 弃战时追船已尽在外不掷骰。四格：
##       ① 开战读阶段表：_escape_px = escape_bu × px_per_bu、_shake_off_s = shake_off_s；
##       ② 两艘快船停住，一艘在 1000 px 时等过时限不收战，挪到 1450 px 再等过时限须收战一次 flee{flee_ok, shook_off}；
##       ③ 唯一一艘在 1500 px 但在脱离（溃走）：等过时限不收战（归士气簿收场，不记成本船脱战）；
##       ④ B 弃战挑首掷 > 0.95 的种子（照掷必败）：追船尽在 1400 px 外须 flee_ok、不掷骰；追船在 600 px 同种子照掷（flee_ok 假）。
##   十三、号令效力接上旗舰（抢风 / 装填侧重）：号令面板「效力」一行（帆力、贴风、装填……）修复前没有一处消费，下令只改签面。四格：
##       ① ManeuverModel 认号令两键：mods.trim 1.09 的船横风满帆两秒后对水航速比不带的快、mods.pinch_delta −6 时船首离来风 45°
##          不再「顶风」（福船顶风区 48°）；② 海战场下抢风令：旗舰这一帧的机动乘数带 trim / pinch_delta，读数里顶风区少 6°；
##       ③ 专力装填：旗舰一放齐射，装填冷却 = 2 秒 × 损伤装填倍数 × 0.7；④ 装填侧重只在均装 ⇄ 专力装填间轮换，不再轮到落不了地的火攻。
## 用法：godot --headless --path . -s res://tools/qa_w53_2_combat_probe.gd
## 判词：QA_W53_2_COMBAT_PROBE PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。只改内存里的 Fleet / GameState / pending_battle，跑完还原。

const TAG := "QA_W53_2_COMBAT_PROBE"

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
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true), "martial": gs.get("martial"), "money": gs.get("money"),
		"fame": gs.get("fame")}

	print("== 一、白刃两边伤亡入账（本队先钩、白刃失利）")
	await _sec_melee_casualties(fleet)
	print("== 二、敌船先抛钩：敌攻我守")
	await _sec_enemy_overrun(fleet)
	await _sec_enemy_repelled(fleet)
	await _sec_enemy_first_morale(fleet)
	print("== 三、号令浮字写中文名")
	await _sec_order_notice(fleet)
	print("== 四、收战带本场折损")
	await _sec_battle_losses(fleet)
	print("== 五、中弹只颠挨打那条船的舱面货")
	await _sec_knock_own_hold(fleet, {}, "①")
	await _sec_knock_own_hold(fleet, {"tea": {"qty": 5, "avg_cost": 20.0}}, "②")
	print("== 六、喊话劝降得手的船接舷即收")
	await _sec_parley_struck_boarding(fleet)
	print("== 七、救火令随险情改损管令")
	await _sec_damage_order_follows_hazard(fleet)
	print("== 八、胜局札记不把元军哨船叫成海盗")
	await _sec_patrol_win_note()
	print("== 九、接踵的浮字不被上一条的淡出补间吃掉")
	await _sec_notice_overlap(fleet)
	print("== 十、敌将状态机自检")
	_sec_captain_self_check()
	print("== 十一、喊话劝降得手的末艘敌船按受降收战")
	await _sec_parley_last_ends_battle(fleet)
	print("== 十二、甩脱：追打的敌船尽在逃出距离外，本船即算甩开")
	await _sec_outsailed(fleet)
	await _sec_flee_key_far(fleet)
	print("== 十三、号令效力接上旗舰（抢风 / 装填侧重）")
	_sec_maneuver_order_keys()
	await _sec_orders_reach_flagship(fleet)

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	await process_frame
	OS.remove_logger(_errlog)
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


## 开一场海战：一艘本队船（type / crew 由调用方定）对 enemy 条目；敌炮冻住（布景不自己结算）。返回 WorldMap
func _battle(fleet: Node, ship_type: String, crew: int, enemy: Dictionary, cargo := {}) -> Node:
	var d: Dictionary = fleet.call("ship_def", ship_type)
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": ship_type, "name": "试船", "crew": crew, "sail_level": 1, "armor_level": 1,
		"cargo": cargo.duplicate(true), "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [enemy], "sea_name": "泉州外海", "source": {"scene": "qa_w53_2"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in _foes(wm):
		f.set("fire_timer", INF)
	return wm


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


## 形参不写类型：收了战的海战场（_battle_exit 自己 queue_free）等过几帧已释放，带类型的形参收到已释放实例当场报错
func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)  # 拆布景不收战（不发 battle_finished）
		wm.queue_free()
	await process_frame


# ══ 一、白刃两边伤亡入账 ══════════════════════════════════════════

## 本队 80 人钩一艘 400 人的快船（敌披满甲）：白刃必不利（击退 / 脱钩），敌船留在场上。逐回对账：
## 敌船水手 = 开打前 − def_dead；本队水手 = 开打前 − att_dead。最多打 8 回，须至少一回 def_dead > 0（不然判不了，照红）
func _sec_melee_casualties(fleet: Node) -> void:
	var wm := await _battle(fleet, "canton_ship", 80, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	_check(foes.size() == 1, "海战刷出一艘快船（得 %d 艘）" % foes.size())
	if foes.is_empty():
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	var bad: Array = []
	var bled := 0
	var lost_rounds := 0
	for i in 8:
		if not is_instance_valid(foe) or bool(wm.get("resolved")):
			break
		foe.set("crew", 400)
		foe.set("melee_armor", 0.9)
		(fleet.get("ships") as Array)[0]["crew"] = 80
		var foe_before := int(foe.get("crew"))
		var ours_before := int(fleet.call("total_crew"))
		wm.call("_board_enemy", foe)
		var r: Dictionary = wm.get("_last_melee")
		if r.is_empty() or str(r.get("legacy", "")) == "win" or not is_instance_valid(foe):
			bad.append("第 %d 回没打成白刃失利（%s）" % [i + 1, str(r.get("outcome", "无结果"))])
			continue
		lost_rounds += 1
		var dd := int(r.get("def_dead", 0))
		var ad := int(r.get("att_dead", 0))
		if dd > 0:
			bled += 1
		if int(foe.get("crew")) != foe_before - dd:
			bad.append("第 %d 回 %s：敌船水手 %d → %d，守方阵亡 def_dead=%d 应扣到 %d" % [
				i + 1, str(r.get("outcome", "")), foe_before, int(foe.get("crew")), dd, foe_before - dd])
		if int(fleet.call("total_crew")) != ours_before - ad:
			bad.append("第 %d 回：本队水手 %d → %d，攻方阵亡 att_dead=%d 应扣到 %d" % [
				i + 1, ours_before, int(fleet.call("total_crew")), ad, ours_before - ad])
	_check(lost_rounds > 0 and bad.is_empty(), "白刃失利 %d 回：敌船水手逐回扣守方阵亡、本队逐回扣攻方阵亡%s" % [
		lost_rounds, "" if bad.is_empty() else "——" + "；".join(bad)])
	_check(bled > 0, "其中 %d 回守方确有阵亡（def_dead > 0），上一格才判得出「没扣」" % bled)
	await _close(wm)


# ══ 二、敌船先抛钩：敌攻我守 ══════════════════════════════════════

## 敌船自己抛钩接上来（_try_grapple 设 boarding_initiator 再请 _board_enemy），这里直设标记再直调，同一条路
func _enemy_boards(wm: Node, foe: Node) -> void:
	foe.set("boarding_initiator", true)
	wm.call("_board_enemy", foe)


## ① 小艍 6 人对快船 200 人：敌攻我守、敌夺下本船甲板 → lose{overrun} 收战一次；本队不得船，守方阵亡从本队扣
func _sec_enemy_overrun(fleet: Node) -> void:
	var wm := await _battle(fleet, "sampan", 6, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	if foes.is_empty():
		_check(false, "① 海战刷出一艘快船")
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	foe.set("crew", 200)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	var ships_before := (fleet.get("ships") as Array).size()
	var ours_before := int(fleet.call("total_crew"))
	await _enemy_boards(wm, foe)
	var r: Dictionary = wm.get("_last_melee")
	_check(not r.is_empty() and r.get("att_is_player") == false and r.get("def_is_player") == true,
		"① 敌船先钩：白刃按敌攻我守结算（攻方是我 = %s，守方是我 = %s）" % [r.get("att_is_player"), r.get("def_is_player")])
	_check(rec.size() == 1 and rec[0][0] == "lose" and bool((rec[0][1] as Dictionary).get("overrun", false)),
		"① 敌攻我守、敌胜（%s）→ 以 lose{overrun} 收战一次（得 %s）" % [str(r.get("outcome", "")), str(rec)])
	_check((fleet.get("ships") as Array).size() == ships_before,
		"① 本船失守不得船：船队仍 %d 条（得 %d）" % [ships_before, (fleet.get("ships") as Array).size()])
	var dd := int(r.get("def_dead", 0))
	var want := ours_before - mini(dd, ours_before - 1)  # lose_crew_random 每船至少留 1 人
	_check(int(fleet.call("total_crew")) == want,
		"① 守方阵亡从本队扣：%d − def_dead %d → %d（得 %d）" % [ours_before, dd, want, int(fleet.call("total_crew"))])
	var lb: GDScript = load("res://scripts/ui/CombatLetterbox.gd")
	var bs: GDScript = load("res://scripts/combat/BoardingStage.gd")
	_check(str(lb.call("outcome_key", "lose", {"overrun": true})) == "lose" and str(bs.call("title_for", "overrun")) == "失守",
		"① 接舷题签「失守」、出战题签 lose「败退」（得 %s / %s）" % [
			bs.call("title_for", "overrun"), lb.call("outcome_key", "lose", {"overrun": true})])
	await _close(wm)


## ② 广船 200 人对快船 20 人：敌攻我守、我守住 → 不收战、敌船放钩仍在场、本队不得船；敌船扣攻方阵亡、本队扣守方阵亡；
## 敌将记「跳帮受挫」（旧口径按我攻敌守：200 人跳过去把钩上来的敌船夺了，末船夺下即收战）
func _sec_enemy_repelled(fleet: Node) -> void:
	var wm := await _battle(fleet, "canton_ship", 200, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	if foes.is_empty():
		_check(false, "② 海战刷出一艘快船")
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	foe.set("crew", 20)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	var ships_before := (fleet.get("ships") as Array).size()
	var ours_before := int(fleet.call("total_crew"))
	await _enemy_boards(wm, foe)
	var r: Dictionary = wm.get("_last_melee")
	var alive := is_instance_valid(foe) and not foe.is_queued_for_deletion()
	_check(not r.is_empty() and r.get("att_is_player") == false and str(r.get("legacy", "")) == "lose",
		"② 敌船先钩：敌攻我守、攻方没拿下（了局 %s，攻方是我 = %s）" % [str(r.get("outcome", "")), r.get("att_is_player")])
	_check(rec.is_empty() and not bool(wm.get("resolved")) and alive and (fleet.get("ships") as Array).size() == ships_before,
		"② 守住了不收战、敌船仍在场、本队不得船（收战 %s · 敌在场 %s · 船队 %d 条）" % [
			str(rec), alive, (fleet.get("ships") as Array).size()])
	if not alive or r.is_empty():
		await _close(wm)
		return
	_check(foe.get("grappled") == false and foe.get("boarding_initiator") == false and not bool(wm.get("boarding")),
		"② 敌船放钩退开：grappled / boarding_initiator 都清、本队不在白刃中")
	var ad := int(r.get("att_dead", 0))
	var dd := int(r.get("def_dead", 0))
	_check(int(foe.get("crew")) == 20 - ad and int(fleet.call("total_crew")) == ours_before - dd,
		"② 两边伤亡各归各：敌船 20 − att_dead %d = %d（得 %d）、本队 %d − def_dead %d = %d（得 %d）" % [
			ad, 20 - ad, int(foe.get("crew")), ours_before, dd, ours_before - dd, int(fleet.call("total_crew"))])
	var cap = foe.get("captain")
	var why := str(cap.get("_cd_reason")) if cap != null else ""
	_check(cap != null and why == "跳帮受挫，退回炮战" and float(cap.get("_reboard_cd")) > 0.0,
		"② 敌将记跳帮受挫、歇一阵再贴（得「%s」）" % why)
	var note: Label = wm.get("_notice")
	var head := str(r.get("summary_head", ""))
	var txt := note.text if note != null else ""
	_check(head != "" and txt.begins_with(head) and txt.find("我退回本船") < 0 and txt.find("敌斧手") < 0,
		"② 记事按守方写（headless 浮字兜底：「%s」）" % txt)
	await _close(wm)


## ③ 士气挂件：敌船先钩那一刻敌簿记攻方、本队簿记守方；放钩（守住）后本队簿提士气。直设 grappled 让挂件逐帧看到钩上、放开
func _sec_enemy_first_morale(fleet: Node) -> void:
	var wm := await _battle(fleet, "canton_ship", 100, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	var tracker = wm.get("_morale")
	if foes.is_empty() or tracker == null:
		_check(false, "③ 海战刷出快船、挂上士气挂件")
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	for _i in 3:
		await physics_frame
	var es = tracker.call("sheet_of", foe)
	var ps = tracker.call("player_sheet")
	if es == null or ps == null:
		_check(false, "③ 士气挂件登记了敌船与本队两页")
		await _close(wm)
		return
	foe.set("boarding_initiator", true)
	foe.set("grappled", true)
	for _i in 2:
		await physics_frame
	_check(es.get("grappled_as_attacker") == true and ps.get("grappled") == true and ps.get("grappled_as_attacker") == false,
		"③ 敌船先钩：敌簿记攻方、本队簿记被钩的守方（敌攻 = %s，我攻 = %s）" % [
			es.get("grappled_as_attacker"), ps.get("grappled_as_attacker")])
	var v_hooked := float(ps.get("value"))
	foe.set("grappled", false)
	for _i in 2:
		await physics_frame
	var v_held := float(ps.get("value"))
	_check(v_held > v_hooked, "③ 守住白刃本队簿提士气（%.1f → %.1f）" % [v_hooked, v_held])
	await _close(wm)


# ══ 三、号令浮字写中文名 ══════════════════════════════════════════

## 真起海战场的号令面板（CombatShoreHook.mount_combat_ui 挂、order_issued 接到 WorldMap._on_combat_order），逐令 issue 读中央浮字
func _sec_order_notice(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	if panel == null:
		_check(false, "海战场挂上号令面板")
		await _close(wm)
		return
	var latin := RegEx.create_from_string("[A-Za-z]")
	var bad: Array = []
	var seen: Array = []
	for step in [["windward", "号令：抢风"], ["windward", "撤令：抢风"], ["load", "号令：专力装填"],
			["load", "号令：均装"], ["damage", "号令：救火"], ["board", "号令：备接舷"]]:
		var payload: Dictionary = panel.call("issue", step[0])
		var note: Label = wm.get("_notice")
		var txt := note.text if note != null else ""
		seen.append(txt)
		if payload.is_empty() or txt != str(step[1]) or latin.search(txt) != null:
			bad.append("下「%s」浮字应是「%s」，得「%s」" % [step[0], step[1], txt])
	_check(bad.is_empty(), "号令浮字逐令写中文名、不带内部 id（%s）%s" % ["／".join(seen), "" if bad.is_empty() else "——" + "；".join(bad)])
	var op: GDScript = load("res://scripts/ui/CombatOrdersPanel.gd")
	var has_fn := op.has_method("notice_for")  # 资源上 has_method 认 static func；缺了不硬调，免得一行 SCRIPT ERROR 截断探针
	_check(has_fn and str(op.call("notice_for", "parley", {"result": "refuse"})) == "号令：降幡劝降"
		and str(op.call("notice_for", "nope", {})) == "", "劝降令浮字「号令：降幡劝降」、认不得的令不上屏（notice_for 在 = %s）" % has_fn)
	await _close(wm)


# ══ 四、收战带本场折损 ══════════════════════════════════════════

## 福船 60 人、舱里生丝 20 茶 5 对两艘快船：战中折 7 人（同矢石伤亡走 Fleet.lose_crew_random）、颠落生丝 3 茶 1（同 Ship.take_hit
## 颠货走 Fleet.remove_cargo），夺下一艘无人快船（并入 crew_min 人），再弃战收战——data.losses 恰 {crew: 7, cargo: 4}
func _sec_battle_losses(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 2},
		{"raw_silk": {"qty": 20, "avg_cost": 50.0}, "tea": {"qty": 5, "avg_cost": 20.0}})
	var foes := _foes(wm)
	if foes.size() < 2:
		_check(false, "四 海战刷出两艘快船（得 %d 艘）" % foes.size())
		await _close(wm)
		return
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate(true)]))
	fleet.call("lose_crew_random", 7)
	fleet.call("remove_cargo", "raw_silk", 3)
	fleet.call("remove_cargo", "tea", 1)
	var foe: Node2D = foes[0]
	foe.set("crew", 0)  # 无人拒守：登船即得、本队不折人
	var ships_before := (fleet.get("ships") as Array).size()
	wm.call("_board_enemy", foe)
	var got_prize := (fleet.get("ships") as Array).size() == ships_before + 1
	var prize_crew := int((fleet.get("ships") as Array)[-1].get("crew", 0)) if got_prize else 0
	_check(got_prize and prize_crew > 0 and rec.is_empty(), "四 中途夺下一艘（并入 %d 人）、还剩一艘不收战" % prize_crew)
	wm.call("_battle_exit", "flee", {"flee_ok": true})
	var data: Dictionary = rec[0][1] if rec.size() == 1 else {}
	var losses = data.get("losses", {})
	_check(losses is Dictionary and int(losses.get("crew", -1)) == 7 and int(losses.get("cargo", -1)) == 4 and (losses as Dictionary).size() == 2,
		"四 收战 data.losses 恰 {crew: 7, cargo: 4}：夺来的 %d 人不抵折损（得 %s）" % [prize_crew, str(data.get("losses", "无此键"))])
	var lb: GDScript = load("res://scripts/ui/CombatLetterbox.gd")
	var sub := str(lb.call("exit_subtitle", "", [], losses if losses is Dictionary else {}))
	_check(sub == "折水手七人，颠落舱面货四件", "四 出战墨边副题写本场折损（得「%s」）" % sub)
	await _close(wm)


# ══ 五、中弹只颠挨打那条船的舱面货 ══════════════════════════════════

## 旗舰福船（舱里 flag_hold）＋护航客舟（生丝 10）：真走 Ship.take_hit 打旗舰四发砲石（每发量旗舰耐久掉了多少，
## 船体伤 ≥ 5 才颠货），护航船生丝须一件不少；旗舰舱里的货按重击发数少
func _sec_knock_own_hold(fleet: Node, flag_hold: Dictionary, tag: String) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1}, flag_hold)
	fleet.call("add_ship", "keel_boat", "护航")
	var escort: Dictionary = (fleet.get("ships") as Array)[1]
	escort["cargo"] = {"raw_silk": {"qty": 10, "avg_cost": 50.0}}
	var own: Node = wm.get("ship")
	var flag: Dictionary = (fleet.get("ships") as Array)[0]
	var flag_units := func() -> int:
		var n := 0
		for g in (flag.get("cargo", {}) as Dictionary):
			n += int(((flag["cargo"] as Dictionary)[g] as Dictionary).get("qty", 0))
		return n
	var start_units: int = flag_units.call()
	var heavy := 0
	for i in 4:
		var dur0 := float(flag.get("durability", 0.0))
		own.call("take_hit", {"amount": 40.0, "kind": "stone", "high": true, "zone": "mid"})
		if dur0 - float(flag.get("durability", 0.0)) >= 5.0:
			heavy += 1
	var silk := int((escort.get("cargo", {}) as Dictionary).get("raw_silk", {}).get("qty", 0))
	var want_flag := maxi(0, start_units - heavy)
	_check(heavy > 0 and silk == 10 and int(flag_units.call()) == want_flag,
		"五%s 旗舰挨 %d 发重击：护航船生丝仍 10（得 %d）、旗舰舱 %d → %d 件（得 %d）" % [
			tag, heavy, silk, start_units, want_flag, int(flag_units.call())])
	await _close(wm)


# ══ 六、喊话劝降得手的船接舷即收 ══════════════════════════════════

## 两艘快船，一艘挪到喊话距离内停住；真起号令面板下「降幡劝降」（roll 0 必降）→ 敌将降幡、节点 struck，士气簿仍不降；
## 把它的水手抬到 300（真打白刃本队必败）再接舷：须免白刃收船、船入列、下场记 struck、海战不收（还剩一艘）
func _sec_parley_struck_boarding(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 2})
	var foes := _foes(wm)
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	if foes.size() < 2 or panel == null:
		_check(false, "六 海战刷出两艘快船、挂上号令面板")
		await _close(wm)
		return
	var own: Node2D = wm.get("ship")
	var foe: Node2D = foes[0]
	(foes[1] as Node2D).position = own.position + Vector2(-900, 0)  # 另一艘挪远：喊话只喊得到这一艘
	for _i in 3:
		await physics_frame  # PirateShip._wire_parley 首个物理帧接上面板的 parley_resolved
	foe.set_physics_process(false)
	foe.position = own.position + Vector2(200, 0)
	var res: Dictionary = panel.call("issue", "parley", 0.0)
	foe.set_physics_process(true)
	for _i in 3:
		await physics_frame  # 敌将降幡后下一物理帧 PirateShip._note_state 立 struck
	var sheet = (wm.get("_morale") as Object).call("sheet_of", foe) if wm.get("_morale") != null else null
	_check(str(res.get("result", "")) == "surrender" and foe.get("struck") == true,
		"六 喊话劝降得手：敌将降幡、船节点 struck（喊话 %s；簿上降了 = %s）" % [
			str(res.get("result", "无")), str(sheet.call("has_struck")) if sheet != null else "无簿"])
	panel.set("parley_cd", 0.0)  # 喊过即进 20 秒冷却：清掉冷却看签面怎么写这艘已降的船
	var hint := str(panel.call("state_text", "parley"))
	_check(hint == "可喊 敌已降", "六 喊降得手后号令签面写「可喊 敌已降」（得「%s」）" % hint)
	foe.set("crew", 300)
	var ships_before := (fleet.get("ships") as Array).size()
	var id := foe.get_instance_id()
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	wm.call("_board_enemy", foe)
	var r: Dictionary = wm.get("_last_melee")
	var fates: Dictionary = wm.get("_enemy_fates")
	var fate := str((fates.get(id, {}) as Dictionary).get("fate", "无"))
	_check(r.is_empty() and (fleet.get("ships") as Array).size() == ships_before + 1 and fate == "struck" and rec.is_empty(),
		"六 接舷竖降幡的船：免白刃收船入列、下场记受降、还剩一艘不收战（白刃 %s · 船队 %d → %d · 下场 %s）" % [
			str(r.get("outcome", "未打")), ships_before, (fleet.get("ships") as Array).size(), fate])
	await _close(wm)


# ══ 七、救火令随险情改损管令 ══════════════════════════════════════

## 旗舰（福船 60 人）一舱灌六成水、没火 → 下救火令：损管令戽水；艏部点火 → 两帧内改救火；火扑灭、水还在 → 改回戽水
func _sec_damage_order_follows_hazard(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	var own: Node = wm.get("ship")
	var dm = own.call("get_damage_model") if own != null else null
	if panel == null or dm == null:
		_check(false, "七 挂上号令面板、旗舰有损伤簿")
		await _close(wm)
		return
	var ff = dm.get("ff")
	var water: PackedFloat64Array = ff.get("water")
	water[0] = 0.6
	ff.set("water", water)
	panel.call("issue", "damage")
	var mode_flood := str(dm.get("mode"))
	ff.call("ignite", "bow", 0.6)
	for _i in 2:
		await process_frame
	var mode_fire := str(dm.get("mode"))
	var fires: Dictionary = ff.get("fire")
	for z in fires:
		fires[z] = 0.0
	ff.set("fire", fires)
	for _i in 2:
		await process_frame
	var mode_back := str(dm.get("mode"))
	_check(mode_flood == "flood" and mode_fire == "fire" and mode_back == "flood",
		"七 只进水时下救火令 → 戽水；起火 → 改救火；火灭水在 → 改回戽水（得 %s → %s → %s）" % [mode_flood, mode_fire, mode_back])
	await _close(wm)


# ══ 八、胜局札记不把元军哨船叫成海盗 ══════════════════════════════════

## 海图起在 root 下（同 combat_realism_probe 的 _spawn_chart：remaining_li 留路、sailing 仍假，战后不抵港不续航），
## pending_battle 摆成元军哨船那一战，喂 _on_battle_result("win")：札记首行须「敌船已退。」起头、不含「海盗」
func _sec_patrol_win_note() -> void:
	var gm: Node = root.get_node("GameManager")
	var chart: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(chart)
	for _i in 4:
		await process_frame
	var log_label = chart.get("log_label")
	if log_label == null:
		_check(false, "八 SeaChart 在 headless 下起得来（航海札记栏在）")
		chart.free()
		return
	chart.set("remaining_li", 50.0)
	(log_label as RichTextLabel).text = ""
	gm.set("pending_battle", {"battle": true, "power": 500.0, "player_power": 600.0,
		"enemy": [{"type": "sea_falcon", "sprite": "yuan_patrol", "count": 3}], "sea_name": "泉州外海",
		"source": {"scene": "SeaChart", "event": "yuan_patrol"}})
	chart.call("_on_battle_result", "win", {"player_damage": 12.0, "fates": [{"type": "sea_falcon", "fate": "sunk", "count": 3}]})
	var first := (log_label as RichTextLabel).get_parsed_text().get_slice("\n", 0)
	_check(first.begins_with("敌船已退。") and first.find("海盗") < 0,
		"八 打赢元军哨船，札记首行不写「海盗」（得「%s」）" % first)
	chart.free()


# ══ 九、接踵的浮字不被上一条的淡出补间吃掉 ══════════════════════════════

## 敌船停物理帧（敌将不换打法、不抛钩）、士气簿停（不出纪实），中央浮字只剩本节直调的两条；计时走 SceneTree 计时器（同补间吃处理帧时长）。
## 甲出字 1.3 秒时满墨（单条停满 1.5 秒，判据判得出）；隔 2 秒出乙，乙出字后 0.8 / 1.3 秒须仍满墨——修复前此时甲的补间已把乙藏掉
func _sec_notice_overlap(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	for f in _foes(wm):
		(f as Node).set_physics_process(false)
	var tracker = wm.get("_morale")
	if tracker is Node:
		(tracker as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var look := func(want: String) -> Array:
		var n: Label = wm.get("_notice")
		if n == null:
			return [false, "无浮字"]
		return [n.visible and n.text == want and n.modulate.a >= 0.99,
			"「%s」%s a=%.2f" % [n.text, "在屏" if n.visible else "已藏", n.modulate.a]]
	wm.call("_show_combat_notice", "甲")
	await create_timer(1.3).timeout
	var s0: Array = look.call("甲")
	await create_timer(0.7).timeout
	wm.call("_show_combat_notice", "乙")
	await create_timer(0.8).timeout
	var s1: Array = look.call("乙")
	await create_timer(0.5).timeout
	var s2: Array = look.call("乙")
	_check(bool(s0[0]), "九 单出一条浮字 1.3 秒时满墨在屏（得 %s）" % s0[1])
	_check(bool(s1[0]) and bool(s2[0]),
		"九 甲出字 2 秒后来乙：乙出字后 0.8 / 1.3 秒仍满墨在屏，不被甲的淡出补间藏掉（得 %s / %s）" % [s1[1], s2[1]])
	await _close(wm)


# ══ 十、敌将状态机自检 ══════════════════════════════════════════

## EnemyCaptainAI.self_check 返回不合的条目（空即全对）；资源上 has_method 认 static func，缺了不硬调
func _sec_captain_self_check() -> void:
	var ai: GDScript = load("res://scripts/combat/EnemyCaptainAI.gd")
	var has_fn := ai != null and ai.has_method("self_check")
	var bad: Array = ai.call("self_check") if has_fn else ["EnemyCaptainAI.self_check 不在"]
	_check(bad.is_empty(), "十 敌将状态机自检全过（%s）" % ("0 条不合" if bad.is_empty() else "；".join(bad)))


# ══ 十一、喊话劝降得手的末艘敌船按受降收战 ══════════════════════════════

## 一艘快船挪到喊话距离内停住，真起号令面板下「降幡劝降」（roll 0 必降）；之后放它照常走物理帧（敌炮仍冻），等十个物理帧：
## 须收战一次 win、morale_verdict = enemy_struck、fates 记受降，SeaChart.win_kind 判 surrender；士气簿那页 has_struck
func _sec_parley_last_ends_battle(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	if foes.size() != 1 or panel == null:
		_check(false, "十一 海战刷出一艘快船、挂上号令面板")
		await _close(wm)
		return
	var own: Node2D = wm.get("ship")
	var foe: Node2D = foes[0]
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate(true)]))
	for _i in 3:
		await physics_frame  # PirateShip._wire_parley 首个物理帧接上面板的 parley_resolved
	foe.set_physics_process(false)
	foe.position = own.position + Vector2(200, 0)
	var res: Dictionary = panel.call("issue", "parley", 0.0)
	var sheet = (wm.get("_morale") as Object).call("sheet_of", foe) if wm.get("_morale") != null else null
	foe.set_physics_process(true)
	for _i in 10:
		if not rec.is_empty():
			break
		await physics_frame
	var struck_sheet: bool = sheet != null and bool(sheet.call("has_struck"))
	var out := str(rec[0][0]) if rec.size() == 1 else "未收战"
	var data: Dictionary = rec[0][1] if rec.size() == 1 else {}
	var fates := str(data.get("fates", []))
	var sc: GDScript = load("res://scripts/SeaChart.gd")
	var kind := str(sc.call("win_kind", data)) if rec.size() == 1 else ""
	_check(str(res.get("result", "")) == "surrender" and struck_sheet,
		"十一 喊话劝降得手：敌将降幡、士气簿那页同记降幡（喊话 %s；簿上降了 = %s）" % [str(res.get("result", "无")), struck_sheet])
	_check(rec.size() == 1 and out == "win" and str(data.get("morale_verdict", "")) == "enemy_struck"
		and fates.find("struck") >= 0 and kind == "surrender",
		"十一 末艘喊降：十帧内按受降收战（得 %s · morale_verdict %s · fates %s · win_kind %s）" % [
			out, str(data.get("morale_verdict", "无")), fates, kind if kind != "" else "无"])
	await _close(wm)


# ══ 十二、甩脱：追打的敌船尽在逃出距离外，本船即算甩开 ══════════════════════════

## 两艘快船关物理帧停在指定处（敌炮已冻）；时限读过阶段表后压到 1 秒省时（① 先验读进来的数）
func _sec_outsailed(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 2})
	var foes := _foes(wm)
	if foes.size() != 2:
		_check(false, "十二 海战刷出两艘快船（得 %d 艘）" % foes.size())
		await _close(wm)
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_phases.json"))
	var want_px := float(d["thresholds"]["escape_bu"]["v"]) * float(d["scale"]["px_per_bu"])
	var want_s := float(d["thresholds"].get("shake_off_s", {}).get("v", -1.0))
	var got_px = wm.get("_escape_px")
	var got_s = wm.get("_shake_off_s")
	_check(got_px is float and is_equal_approx(float(got_px), want_px) and got_s is float and is_equal_approx(float(got_s), want_s),
		"十二① 开战读阶段表：逃出距离 %s px（表 %.0f）、甩脱时限 %s 秒（表 %s）" % [str(got_px), want_px, str(got_s), str(want_s)])
	wm.set("_shake_off_s", 1.0)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, dd: Dictionary) -> void: rec.append([o, dd.duplicate(true)]))
	var own: Node2D = wm.get("ship")
	var a: Node2D = foes[0]
	var b: Node2D = foes[1]
	for f in foes:
		(f as Node).set_physics_process(false)
	a.position = own.position + Vector2(1000, 0)
	b.position = own.position + Vector2(-1500, 200)
	await create_timer(1.6).timeout
	var held := rec.is_empty()
	var held_rec := str(rec)
	a.position = own.position + Vector2(1450, 0)
	await create_timer(1.6).timeout
	var data: Dictionary = rec[0][1] if rec.size() == 1 else {}
	_check(held, "十二② 一艘还在逃出距离内（1000 px）：等过时限不收战（得 %s）" % held_rec)
	_check(rec.size() == 1 and str(rec[0][0]) == "flee" and bool(data.get("flee_ok", false)) and bool(data.get("shook_off", false))
		and not bool(data.get("parted", false)),
		"十二② 两艘都在 1450 px 外满时限：按脱战收战 flee{flee_ok, shook_off}（得 %s）" % str(rec))
	await _close(wm)
	# ③ 唯一一艘在脱离（溃走）：不算追船，不记成本船脱战
	wm = await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
	foes = _foes(wm)
	if foes.size() != 1:
		_check(false, "十二③ 海战刷出一艘快船")
		await _close(wm)
		return
	wm.set("_shake_off_s", 1.0)
	var rec3: Array = []
	wm.battle_finished.connect(func(o: String, dd: Dictionary) -> void: rec3.append(o))
	var c: Node2D = foes[0]
	c.set_physics_process(false)
	c.position = (wm.get("ship") as Node2D).position + Vector2(1500, 0)
	var cap = c.get("captain")
	if cap != null:
		cap.set("state", &"disengage")
	await create_timer(1.6).timeout
	_check(cap != null and rec3.is_empty(), "十二③ 唯一一艘在脱离（1500 px）：不算追船，等过时限不收战（得 %s）" % str(rec3))
	await _close(wm)


## B 弃战：挑首掷 randf() > 0.95 的种子（Voyage.flee_success_chance 封顶 0.9，照掷必败）。追船尽在 1400 px 外：flee_ok 须真（不掷骰）；
## 同种子追船在 600 px：照掷，flee_ok 假
func _sec_flee_key_far(fleet: Node) -> void:
	var sd := 1
	while sd < 5000:
		seed(sd)
		if randf() > 0.95:
			break
		sd += 1
	var got: Array = []
	for dist in [1400.0, 600.0]:
		var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
		var foes := _foes(wm)
		if foes.size() != 1:
			got.append("刷船 %d 艘" % foes.size())
			await _close(wm)
			continue
		var rec: Array = []
		wm.battle_finished.connect(func(o: String, dd: Dictionary) -> void: rec.append([o, bool(dd.get("flee_ok", false))]))
		(foes[0] as Node).set_physics_process(false)
		(foes[0] as Node2D).position = (wm.get("ship") as Node2D).position + Vector2(dist, 0)
		var ev := InputEventKey.new()
		ev.keycode = KEY_B
		ev.pressed = true
		seed(sd)
		wm.call("_unhandled_input", ev)
		got.append(str(rec[0][1]) if rec.size() == 1 else "未收战")
		await _close(wm)
	_check(got.size() == 2 and got[0] == "true" and got[1] == "false",
		"十二④ B 弃战（种子 %d 首掷 > 0.95）：追船在 1400 px 外不掷骰即脱 flee_ok=%s；在 600 px 照掷 flee_ok=%s" % [
			sd, got[0] if got.size() > 0 else "无", got[1] if got.size() > 1 else "无"])



# ══ 十三、号令效力接上旗舰（抢风 / 装填侧重） ══════════════════════════════

## ① 纯函数：两份福船机动模型同输入（北风 80、满帆）各走两秒，只差 mods；横风比航速，离来风 45° 比帆向
func _sec_maneuver_order_keys() -> void:
	var mm: GDScript = load("res://scripts/combat/ManeuverModel.gd")
	var wt := Vector2(0, 1)
	var dt := 1.0 / 60.0
	var plain = mm.new("fu_ship_medium", 1, 0)
	var trimmed = mm.new("fu_ship_medium", 1, 0)
	for _i in 120:
		plain.step(Vector2.RIGHT, 0.0, 2, wt, 80.0, Vector2.ZERO, dt)
		trimmed.step(Vector2.RIGHT, 0.0, 2, wt, 80.0, Vector2.ZERO, dt, {"trim": 1.09})
	var v0 := float(plain.get("v_fwd"))
	var v1 := float(trimmed.get("v_fwd"))
	var close_hauled := Vector2(sin(deg_to_rad(45.0)), -cos(deg_to_rad(45.0)))
	var base = mm.new("fu_ship_medium", 1, 0)
	var pointed = mm.new("fu_ship_medium", 1, 0)
	base.step(close_hauled, 0.0, 2, wt, 80.0, Vector2.ZERO, dt)
	pointed.step(close_hauled, 0.0, 2, wt, 80.0, Vector2.ZERO, dt, {"pinch_delta": -6.0})
	var s0 := str(base.get("sail_state"))
	var s1 := str(pointed.get("sail_state"))
	var p1 = (pointed.call("snapshot") as Dictionary).get("pinch", -1.0)
	_check(v1 > v0 * 1.05, "十三① mods.trim 1.09：横风满帆两秒对水航速 %.1f → %.1f px/s（须快 5%% 以上）" % [v0, v1])
	_check(s0 == "顶风" and s1 != "顶风" and is_equal_approx(float(p1), float(base.call("pinch_deg")) - 6.0),
		"十三① mods.pinch_delta −6：离来风 45° 不带 %s、带 %s，读数顶风区 %s°（本船 %.0f°）" % [s0, s1, str(p1), float(base.call("pinch_deg"))])


## ②–④ 真起海战场与号令面板：抢风令进旗舰机动，专力装填进齐射冷却，装填侧重的轮换
func _sec_orders_reach_flagship(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	var own: Node = wm.get("ship")
	if panel == null or own == null:
		_check(false, "十三 挂上号令面板、旗舰在场")
		await _close(wm)
		return
	panel.call("issue", "windward")
	var has_mods := wm.has_method("_flagship_mods")
	var mods: Dictionary = wm.call("_flagship_mods") if has_mods else {}
	for _i in 3:
		await physics_frame
	var helm = wm.get("_helm")
	var want_pinch := maxf(40.0, float(helm.call("pinch_deg")) - 6.0) if helm != null else -1.0
	var snap_pinch := float(wm.call("maneuver_snapshot").get("pinch", -1.0))
	_check(has_mods and float(mods.get("trim", 1.0)) > 1.05 and is_equal_approx(float(mods.get("pinch_delta", 0.0)), -6.0)
		and is_equal_approx(snap_pinch, want_pinch),
		"十三② 抢风令进旗舰机动：帆力 %s、贴风 %s°；读数顶风区 %.0f°（须 %.0f°）" % [
			str(mods.get("trim", "无")), str(mods.get("pinch_delta", "无")), snap_pinch, want_pinch])
	panel.call("issue", "windward")  # 撤抢风
	panel.call("issue", "load")  # 专力装填
	var dm = own.call("get_damage_model")
	own.set("fire_cooldown", 0.0)
	own.call("_fire_broadside", 1)
	var want_cd := 2.0 * float(dm.call("reload_factor")) * 0.7
	var cd := float(own.get("fire_cooldown"))
	_check(str(panel.call("state_text", "load")) == "专力装填" and absf(cd - want_cd) < 0.001,
		"十三③ 专力装填：齐射后装填冷却 %.3f 秒（须 2 × 损伤倍数 × 0.7 = %.3f）" % [cd, want_cd])
	var seen := PackedStringArray([str(panel.call("state_text", "load"))])
	for _i in 3:
		panel.call("issue", "load")
		seen.append(str(panel.call("state_text", "load")))
	_check(seen.find("火攻") < 0 and seen[1] == "均装" and seen[2] == "专力装填",
		"十三④ 装填侧重只在均装、专力装填间轮换（%s）" % " → ".join(seen))
	await _close(wm)


class _ScriptErrLog extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
