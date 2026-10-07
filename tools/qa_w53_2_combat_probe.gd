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
##       真起号令面板逐令 issue，浮字须是「号令：抢风 / 撤令：抢风 / 号令：专力装填 / 均装 / 救火 / 备接舷」、不含拉丁字母
##       （火攻回到轮换归三期 lane w53-p3b：fire_attack_load 开时轮换三档，本节按 wave53 开工前账关那枚开关验两档）。
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
##       ④ B 弃战挑首掷 > 0.95 的种子（照掷必败）：追船尽在 1400 px 外须 flee_ok、不掷骰；追船在 600 px 同种子照掷（flee_ok 假）；
##       ⑤ 弃战越远越易脱（待拍板 13b）：挑首掷落在「船速底数」与「底数 + 五成余量」之间的种子——追船在 900 px 须脱（随距离抬过了这一掷），
##          在 300 px（近身只看船速）照判没脱。修复前只看船速，900 px 也没脱。
##   十三、号令效力接上旗舰（抢风 / 装填侧重）：号令面板「效力」一行（帆力、贴风、装填……）修复前没有一处消费，下令只改签面。四格：
##       ① ManeuverModel 认号令两键：mods.trim 1.09 的船横风满帆两秒后对水航速比不带的快、mods.pinch_delta −6 时船首离来风 45°
##          不再「顶风」（福船顶风区 48°）；② 海战场下抢风令：旗舰这一帧的机动乘数带 trim / pinch_delta，读数里顶风区少 6°；
##       ③ 专力装填：旗舰一放齐射，装填冷却 = 2 秒 × 损伤装填倍数 × 0.7；④ 装填侧重只在均装 ⇄ 专力装填间轮换
##       （火攻回到轮换归三期 lane w53-p3b：fire_attack_load 开时三档，本节按 wave53 开工前账关那枚开关验两档）。
##   十四、号令「备接舷」的效力接上（钩距、白刃、伤亡）：修复前聚齐了甲士，钩距、白刃、伤亡一样不变。下令、聚队进度直设满：
##       ① 本船去钩的够距底数 = 140 × 钩距效力（约 175），敌船钩本船仍 140；② 白刃两方里本队的将领系数 = 不下令时 × 白刃效力
##       （本队先钩作攻方、敌船先钩作守方都算）；③ 伤亡效力约 1.33：旗舰挨三发各折 3 人记成 4 + 4 + 4（带余数），撤令后照记原数。
##   十五、海战浮字不压本船、接踵的几条都看得到：修复前只有一枚居中的 Label——字从屏心往右写，正压在本船帆上；同一两帧里来的几条
##       （喊降那一下：「号令：降幡劝降」「敌将改打法：降幡（…）」「敌船「快船」落帆乞降」）只剩最后一条。等号令面板、状态条摆好位后：
##       ① 同一帧来三条：浮字条里三行依次在屏、_notice 是最后一行；② 再来第四条：最旧的那行让掉，仍三行；③ 同一句接着来不另起一行，
##       出这几条不报引擎错（get_meta 缺键这类 ERROR_TYPE_ERROR，「本进程无 SCRIPT ERROR」那格看不见）；
##       ④ 浮字条在画布内，不碰本船（船心屏上位置 ±130 × ±90）、号令面板、小地图、状态条、顶匾，底边在出战墨边下边之上。
## 用法：godot --headless --path . -s res://tools/qa_w53_2_combat_probe.gd
##   十七、旗舰接上装填与弹道（player_gunnery，w53-2 二期矢石一条线）：关时是原来的两秒一串直线铁球；开时战斗按 ReloadAmmo 装、
##       放出的发数记在弹药与 shots_fired 上。四格：① 开时旗舰 battery 在、各舷有床子弩；② 开时放一舷 shots_fired > 0、弹药少了几发；
##       ③ 关后 battery 为 null、回旧路；④ Ship.combat_status() 挂到状态条（弹药按舱、两舷装填）。
## 判词：QA_W53_2_COMBAT_PROBE PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。只改内存里的 Fleet / GameState / pending_battle，跑完还原。

const TAG := "QA_W53_2_COMBAT_PROBE"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

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
	print("== 十四、号令「备接舷」的效力接上（钩距、白刃、伤亡）")
	await _sec_board_order_effects(fleet)
	print("== 十五、海战浮字不压本船、接踵的几条都看得到")
	await _sec_notice_stack(fleet)
	print("== 十七、旗舰接上装填与弹道（player_gunnery）")
	await _sec_player_gunnery(fleet)

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
	# 火攻回到轮换归三期 lane w53-p3b：本节验 wave53 开工前的中文化账，关掉 fire_attack_load 按两档轮换走
	_Switches.set_on("fire_attack_load", false)
	var wm := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	if panel == null:
		_check(false, "海战场挂上号令面板")
		await _close(wm)
		_Switches.reset()
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
	_Switches.reset()


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
	# 战斗方案一期「劝降钮挂敌船」上线后 parley_on_ship 默认开：本探六个 parley 段钉的是 wave53 开工前的
	# 喊话动作自身（roll 定 0 必降、簿上/节点两处记降幡）——走开关对照的旧玩法 lane 看，联络薄与 struck 账跟着
	_Switches.set_on("parley_on_ship", false)
	var res: Dictionary = panel.call("issue", "parley", 0.0)
	_Switches.reset()
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
	var whole := (log_label as RichTextLabel).get_parsed_text()
	# w53-16 一期起札记首行先垫战后单子（「敌船三艘，击沉三艘。」），账目原句在后——
	# 判「账目句开头不是海盗」：拿到账目那一句（去掉单子垫头）再断言开头与里头都不带「海盗」。
	var body := whole
	var mut := whole.find("。敌船已退。")
	if mut >= 0:
		body = whole.substr(mut + 1)
	_check(body.begins_with("敌船已退。") and body.find("海盗") < 0,
		"八 打赢元军哨船，札记账目句不写「海盗」（得「%s」）" % body.get_slice("\n", 0))
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
	_Switches.set_on("parley_on_ship", false)
	var res: Dictionary = panel.call("issue", "parley", 0.0)
	_Switches.reset()
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
	# ⑤ 越远越易脱：底数按本节的福船现算（Voyage.flee_success_chance），首掷落在底数之上、底数 + 五成余量之下
	var base := float(root.get_node("Voyage").call("flee_success_chance"))
	var lo := base + 0.05 * (1.0 - base)
	var hi := base + 0.5 * (1.0 - base)
	var sd2 := 1
	var r2 := -1.0
	while sd2 < 20000:
		seed(sd2)
		r2 = randf()
		if r2 > lo and r2 < hi:
			break
		sd2 += 1
	var got2: Array = []
	for dist in [900.0, 300.0]:
		var wm2 := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
		var foes2 := _foes(wm2)
		if foes2.size() != 1:
			got2.append("刷船 %d 艘" % foes2.size())
			await _close(wm2)
			continue
		var rec2: Array = []
		wm2.battle_finished.connect(func(o: String, dd: Dictionary) -> void: rec2.append(bool(dd.get("flee_ok", false))))
		(foes2[0] as Node).set_physics_process(false)
		(foes2[0] as Node2D).position = (wm2.get("ship") as Node2D).position + Vector2(dist, 0)
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_B
		ev2.pressed = true
		seed(sd2)
		wm2.call("_unhandled_input", ev2)
		got2.append(str(rec2[0]) if rec2.size() == 1 else "未收战")
		await _close(wm2)
	_check(got2.size() == 2 and got2[0] == "true" and got2[1] == "false",
		"十二⑤ 越远越易脱（船速底数 %.2f，种子 %d 首掷 %.3f）：追船在 900 px 脱 flee_ok=%s、在 300 px 照船速 flee_ok=%s" % [
			base, sd2, r2, got2[0] if got2.size() > 0 else "无", got2[1] if got2.size() > 1 else "无"])



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
	# 火攻回到轮换归三期 lane w53-p3b：fire_attack_load 开时轮换三档，本节钉 wave53 开工前的两档账，关开关验
	_Switches.set_on("fire_attack_load", false)
	var seen := PackedStringArray([str(panel.call("state_text", "load"))])
	for _i in 3:
		panel.call("issue", "load")
		seen.append(str(panel.call("state_text", "load")))
	_check(seen.find("火攻") < 0 and seen[1] == "均装" and seen[2] == "专力装填",
		"十三④ fire_attack_load 关时装填侧重只在均装、专力装填间轮换（%s）" % " → ".join(seen))
	_Switches.reset()
	await _close(wm)



# ══ 十四、号令「备接舷」的效力接上（钩距、白刃、伤亡） ══════════════════════════

func _sec_board_order_effects(fleet: Node) -> void:
	var wm := await _battle(fleet, "fu_ship_medium", 60, {"type": "pirate_boat", "count": 1})
	var foes := _foes(wm)
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	var own: Node2D = wm.get("ship")
	if panel == null or foes.size() != 1 or own == null:
		_check(false, "十四 挂上号令面板、刷出一艘快船")
		await _close(wm)
		return
	var foe: Node2D = foes[0]
	foe.set_physics_process(false)
	var base_cap := clampf(float(fleet.call("captain_power")), 0.5, 2.0)
	panel.call("issue", "board")
	panel.set("muster", 1.0)
	var m: Dictionary = panel.call("current_modifiers")
	# ① 钩距
	var mine: Dictionary = wm.call("boarding_approach_of", own, foe)
	var theirs: Dictionary = wm.call("boarding_approach_of", foe, own)
	var want_reach := 140.0 * float(m["board_range"])
	_check(absf(float(mine.get("base_reach", -1.0)) - want_reach) < 0.01 and absf(float(theirs.get("base_reach", -1.0)) - 140.0) < 0.01,
		"十四① 聚齐了钩拒手：本船去钩够距底数 %s（须 140 × %.2f = %.0f），敌船钩本船 %s（须 140）" % [
			str(mine.get("base_reach", "无")), float(m["board_range"]), want_reach, str(theirs.get("base_reach", "无"))])
	# ② 白刃
	var has_sides := wm.has_method("_melee_sides")
	var want_cap := clampf(base_cap * float(m["board_bonus"]), 0.5, 2.0)
	var att_cap := -1.0
	var def_cap := -1.0
	if has_sides:
		var s1: Array = wm.call("_melee_sides", foe, false)
		var s2: Array = wm.call("_melee_sides", foe, true)
		att_cap = clampf(float((s1[0] as Dictionary).get("captain", -1.0)), 0.5, 2.0)
		def_cap = clampf(float((s2[1] as Dictionary).get("captain", -1.0)), 0.5, 2.0)
	_check(has_sides and absf(att_cap - want_cap) < 0.001 and absf(def_cap - want_cap) < 0.001,
		"十四② 本队白刃将领系数 = %.3f × 白刃 %.2f = %.3f：本队先钩作攻方 %.3f、敌船先钩作守方 %.3f" % [
			base_cap, float(m["board_bonus"]), want_cap, att_cap, def_cap])
	# ③ 伤亡
	var has_exp := own.has_method("_exposed")
	var got := PackedStringArray()
	if has_exp:
		for _i in 3:
			got.append(str(own.call("_exposed", 3)))
	panel.call("issue", "board")  # 撤令
	panel.set("muster", 0.0)
	var plain := int(own.call("_exposed", 3)) if has_exp else -1
	_check(has_exp and "+".join(got) == "4+4+4" and plain == 3,
		"十四③ 伤亡效力 %.2f：三发各折 3 人记成 %s（须 4+4+4），撤令后记 %d（须 3）" % [
			float(m["exposure"]), "+".join(got) if not got.is_empty() else "无", plain])
	await _close(wm)



# ══ 十五、海战浮字不压本船、接踵的几条都看得到 ══════════════════════════════

## 浮字条里此刻在屏的各行字（没有浮字条时退回读 _notice 一枚）
func _notice_lines(wm: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var box = wm.get("_notice_box")
	if box is Node and is_instance_valid(box):
		for c in (box as Node).get_children():
			if c is Label and (c as Label).visible:
				out.append((c as Label).text)
	return out


func _sec_notice_stack(fleet: Node) -> void:
	var size0: Vector2i = root.size
	root.size = Vector2i(1280, 720)  # 照实机 16:9 量摆位（headless 缺省视窗不是 1280×720）；节末还原
	var wm := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	for f in _foes(wm):
		(f as Node).set_physics_process(false)
	var tracker = wm.get("_morale")
	if tracker is Node:
		(tracker as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for _i in 4:
		await process_frame  # 号令面板、状态条的摆位是 call_deferred
	var e0: int = _errlog.engine_lines.size()
	var three := ["号令：降幡劝降", "敌将改打法：降幡（喊话劝降，落帆乞降）", "敌船「快船」落帆乞降"]
	for t in three:
		wm.call("_show_combat_notice", t)
	var got1 := _notice_lines(wm)
	var newest: Label = wm.get("_notice")
	_check(got1 == PackedStringArray(three) and newest != null and newest.text == three[2],
		"十五① 同一帧来三条：三行依次在屏（得 %s；_notice「%s」）" % [" / ".join(got1) if not got1.is_empty() else "无浮字条",
			newest.text if newest != null else "无"])
	wm.call("_show_combat_notice", "敌船上喊声乱了。")
	var got2 := _notice_lines(wm)
	_check(got2 == PackedStringArray([three[1], three[2], "敌船上喊声乱了。"]),
		"十五② 第四条来：最旧一行让掉，仍三行（得 %s）" % " / ".join(got2))
	wm.call("_show_combat_notice", "敌船上喊声乱了。")
	var got3 := _notice_lines(wm)
	_check(got3 == got2 and not got3.is_empty(), "十五③ 同一句接着来不另起一行（得 %d 行）" % got3.size())
	var errs: Array = _errlog.engine_lines.slice(e0)
	_check(errs.is_empty(), "十五③ 出浮字不报引擎错（得 %d 条%s）" % [errs.size(), "：" + str(errs[0]) if not errs.is_empty() else ""])
	# ④ 摆位
	var cv: Vector2 = root.get_visible_rect().size
	print("    （画布 %s，root.size %s）" % [str(cv), str(root.size)])
	var box = wm.get("_notice_box")
	var rect := Rect2()
	if box is Control:
		rect = (box as Control).get_global_rect()
	elif wm.get("_notice") is Control:
		rect = (wm.get("_notice") as Control).get_global_rect()
	var own: Node2D = wm.get("ship")
	var sp: Vector2 = own.get_global_transform_with_canvas().origin
	var ship_rect := Rect2(sp - Vector2(130, 90), Vector2(260, 180))
	var bad := PackedStringArray()
	if not Rect2(Vector2.ZERO, cv).encloses(rect):
		bad.append("出了画布")
	if rect.intersects(ship_rect):
		bad.append("压在本船上（船心 %s）" % str(sp.round()))
	if rect.end.y > cv.y * 0.875 + 0.5:
		bad.append("底边 %.0f 进了出战墨边下边（%.0f）" % [rect.end.y, cv.y * 0.875])
	var others := {}
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders") and n.get("_card") is Control:
			others["号令面板"] = (n.get("_card") as Control).get_global_rect()
		elif n.is_in_group("nk1_combat_status") and n.get("_strip") is Control:
			others["状态条"] = (n.get("_strip") as Control).get_global_rect()
	for path in [["小地图", "CanvasLayer/HUD/MinimapPanel"], ["顶匾", "CanvasLayer/HUD/TideBar"]]:
		var c := wm.get_node_or_null(path[1]) as Control
		if c != null:
			others[path[0]] = c.get_global_rect()
	for k in others:
		if rect.intersects(others[k]):
			bad.append("碰到%s %s" % [k, str(others[k])])
	_check(rect.size.x > 0.0 and bad.is_empty() and others.size() == 4,
		"十五④ 浮字条 %s 在画布内、不碰本船与号令面板 / 状态条 / 小地图 / 顶匾（量到 %d 件）%s" % [
			str(rect), others.size(), "" if bad.is_empty() else "——" + "；".join(bad)])
	await _close(wm)
	root.size = size0


# ══ 十七、旗舰接上装填与弹道（player_gunnery） ══════════════════════════════

func _sec_player_gunnery(fleet: Node) -> void:
	var quality_row := 0
	var sw: GDScript = load("res://scripts/combat/CombatSwitches.gd")
	sw.call("set_on", "player_gunnery", true)
	var wm := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	var own: Node2D = wm.get("ship")
	var bat = own.get("battery")
	_check(bat != null, "十七① 开时旗舰装填簿在（battery %s）" % str(bat))
	var has_side := false
	var n_m := 0
	if bat != null:
		n_m = ((bat as Object).get("mounts") as Array).size()
		for m in (bat as Object).get("mounts"):
			var mm: Dictionary = m
			if str(mm.get("weapon", "")) == "chuangnu" and int(mm.get("side", 0)) != 0:
				has_side = true
	_check(has_side, "十七① 开时各舷有床子弩（mounts %d）" % n_m)
	var am0: Dictionary = ((bat as Object).get("ammo") as Dictionary).duplicate() if bat != null else {}
	for _i in 30:
		await physics_frame
	var snap0: Dictionary = (load("res://scripts/ui/CombatStatusHud.gd") as GDScript).call("snapshot_of", wm, own)
	var reload0: Dictionary = snap0.get("reload", {}) if snap0 is Dictionary else {}
	var ammo0: Dictionary = snap0.get("ammo", {}) if snap0 is Dictionary else {}
	var stow0 := int(ammo0.get("bolt", 0)) + int(ammo0.get("arrow", 0)) + int(ammo0.get("stone", 0)) + int(ammo0.get("gunpowder", 0))
	own.set("fire_cooldown", 0.0)
	own.call("_fire_broadside", 1)
	var am1: Dictionary = ((bat as Object).get("ammo") as Dictionary) if bat != null else {}
	if bat != null:
		quality_row = int(roundf(float((bat as Object).get("volley_quality")) * 100.0))
	var used := false
	var shots := -1
	if bat != null:
		shots = int((bat as Object).get("shots_fired"))
		for k in am1:
			if int(am1[k]) < int(am0.get(k, 0)):
				used = true
	_check(quality_row > 0, "十七②a archer_scaling 按人头折算：volley_quality 跟上水手数（40 人 / 5·7 位，得 %d%%）" % quality_row)
	_check(shots > 0 and used, "十七② 开时放一舷：shots_fired %d、弹药用掉一些（%s → %s，冷却 %.2f）" % [
		shots, str(am0), str(am1), float(own.get("fire_cooldown"))])
	var after_hud: Dictionary = (load("res://scripts/ui/CombatStatusHud.gd") as GDScript).call("snapshot_of", wm, own)
	var ammo_after: Dictionary = after_hud.get("ammo", {}) if after_hud is Dictionary else {}
	var reload_after: Dictionary = after_hud.get("reload", {}) if after_hud is Dictionary else {}
	var ammo_after_n := int(ammo_after.get("bolt", 0)) + int(ammo_after.get("arrow", 0)) + int(ammo_after.get("stone", 0)) + int(ammo_after.get("gunpowder", 0))
	var reload_after_n := float(reload_after.get("port", -1.0)) + float(reload_after.get("starboard", -1.0))
	_check(stow0 > 0 and ammo_after_n < stow0 and reload_after_n >= 0.0,
		"十七④ 快照 / 状态条接：弹药上屏 %d → %d、两舷装填读数在（%s → %s）" % [
			stow0, ammo_after_n, str(reload0), str(reload_after)])
	await _close(wm)
	sw.call("set_on", "player_gunnery", false)
	var wm2 := await _battle(fleet, "fu_ship_medium", 40, {"type": "pirate_boat", "count": 1})
	var own2: Node2D = wm2.get("ship")
	_check(own2.get("battery") == null, "十七③ 关后旗舰没有装填簿（battery %s）" % str(own2.get("battery")))
	# 状态条快照真拼一次：并到 _duck(ship) 的弹药与两舷装填数据得在格子里出得来
	var hud: GDScript = load("res://scripts/ui/CombatStatusHud.gd")
	var snap2: Dictionary = (hud.call("snapshot_of", wm2, own2) as Dictionary) if hud.has_method("snapshot_of") else {}
	var scr: GDScript = load("res://scripts/Ship.gd")
	var has_fn := false
	for m in scr.get_script_method_list():
		if str(m.get("name", "")) == "combat_status":
			has_fn = true
	_check(has_fn, "十七④ Ship.combat_status() 在（状态条快照接弹药 / 两舷装填；has_fn %s）" % str(has_fn))
	await _close(wm2)
	sw.call("reset")


class _ScriptErrLog extends Logger:
	var lines: Array = []
	## 引擎错（ERROR_TYPE_ERROR，如 get_meta 缺键）另记一本：不入「本进程无 SCRIPT ERROR」那格，由各节自己前后对数
	var engine_lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		elif error_type == ERROR_TYPE_ERROR:
			engine_lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
