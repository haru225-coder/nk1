extends SceneTree
## lane w53-p6-escort 护航船上阵与三道将令专项探针（headless，经 glock 跑；真 WorldMap 海战场 + pending_battle，泉州外海）。
##   godot --headless --path . -s res://tools/qa_w53_p6_escort_probe.gd
## 一段钉一条、回退即红：
##   一、上阵船数：舰队旗舰以外能上阵的船（船体在、有人）至多三艘，旗舰 + 护航 + 敌船 + 火船同屏不过八艘（火船按
##       pending_battle.yashan.fire_ships 数）、崖山那一场的 no_escort 一艘不上；护航是 EscortShip_ 前缀、
##       进 nk1_escort_ships 不进 nk1_enemy_ships（WorldMap 不把它数成敌船）；船体、人手、船名照 Fleet 那一格，素帆，风读旗舰。
##   二、三道将令：布置期护航跟站位、签亮，过了 ORDER_WINDOW_S 照列队（timeout）、下了就定不再改；键盘 9、鼠标点签、触屏点签
##       各下一道；曳敌——近到 LURE_PX 那艘敌船改打护航、护航沉了它当即回头找旗舰、_pursuit 不算它；夺舱——待命装填慢 1.25 倍，
##       旗舰一钩上护航改钩第二艘（不挑旗舰钩着的那艘），护航白刃得手夺船入船籍记「夺」、不得手折人退开，抛钩挂上两船并住 MELEE_HOLD_S；
##       列队——旗舰开船八秒，护航都在站位近处，敌船照旧都冲旗舰。
##   三、结算记账不重：护航挨一发，Fleet 那一格耐久照扣、人数照节点；旗舰白刃只算旗舰（与没上阵的船）上的人，折损不扣护航；
##       敌船按旗舰算接舷比；护航沉了收战才摘出 Fleet，player_damage 含它整船耐久一遍、losses.crew = 开战水手 − 收战水手，
##       舱货另记 data.escort（不算颠落）；敌船血量缩放扣掉上阵护航那份战力。
##   四、旗舰沉接任（13c）：护航沉一艘、旗舰再沉，lose{sunk} 收战，SeaChart._flagship_handoff 把还浮着的护航顶成旗舰（带着这一场的伤）；
##       护航全沉、旗舰再沉——无人接任，全队耐久见底。
##   五、关态回旧：escort_battle 关——一艘不刷、白刃照全队人数、敌船血量照全队战力、收战不写 data.escort、Fleet 各船一字不动；
##       escort_orders 关——护航照刷、将令照列队（auto）、签不出、按键不下。
## 判词：末行 QA_W53_P6_ESCORT PASS|FAIL cases=N fails=K；有失败退 1。

const TAG := "QA_W53_P6_ESCORT"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

## EscortWing / SeaChart 直读 Fleet / GameState 等 autoload：-s 探针的 preload 在 autoload 挂上之前编，会编不过——_run 里再 load
var _Wing = null
var _SeaChart = null

var _fleet: Node = null
var _gm: Node = null
var _rec: Array = []
var _seed := 6100
var _cases := 0
var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _run() -> void:
	await process_frame
	_Wing = load("res://scripts/combat/EscortWing.gd")
	_SeaChart = load("res://scripts/SeaChart.gd")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (_fleet.get("ships") as Array).duplicate(true), "morale": _fleet.get("morale"),
		"pb": (_gm.get("pending_battle") as Dictionary).duplicate(true), "berth": gs.get("berth_index"),
		"martial": gs.get("martial")}
	await _sec_deploy()
	await _sec_orders()
	await _sec_ledger()
	await _sec_handoff()
	await _sec_off()
	_fleet.set("ships", saved["ships"])
	_fleet.set("morale", saved["morale"])
	_fleet.set("escorts_in_battle", [])
	_gm.set("pending_battle", saved["pb"])
	gs.set("berth_index", saved["berth"])
	gs.set("martial", saved["martial"])
	_Switches.reset()
	await process_frame
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(0 if _fails == 0 else 1)


# ── 布景 ──────────────────────────────────────────────

func _mk(t: String, nm: String, crew: int, cargo := {}) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": cargo.duplicate(true),
		"durability": dur, "max_durability": dur}


## 真起一场：Fleet 换成 ships、pending_battle 写敌阵（extra 并进 pending_battle），挂 WorldMap；士气簿裁决不接（探针自己收战，布景不被半路收走）
func _stage(ships: Array, enemy: Array, ppower := 1000.0, power := 400.0, extra := {}) -> Node:
	_fleet.set("ships", ships)
	_fleet.set("morale", 60)
	_fleet.set("escorts_in_battle", [])
	root.get_node("GameState").set("martial", 50)
	_seed += 1
	seed(_seed)
	var pb := {"battle": true, "power": power, "player_power": ppower, "enemy": enemy,
		"sea_name": "泉州外海", "sea_seed": 7_000_000 + _seed, "source": {"scene": "qa_w53_p6_escort"}}
	pb.merge(extra, true)
	_gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	seed(_seed)
	_rec = []
	wm.battle_finished.connect(func(o: String, data: Dictionary) -> void: _rec.append([o, data.duplicate(true)]))
	var mo = wm.get("_morale")
	if mo != null and mo.verdict.is_connected(Callable(wm, "_on_morale_verdict")):
		mo.verdict.disconnect(Callable(wm, "_on_morale_verdict"))
	await process_frame
	await process_frame
	return wm


## 布景里谁都不开炮、不抛钩、不离场（fire_timer = INF 即冻结，船照常机动）：只验走法与记账
func _freeze(wm: Node) -> void:
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") or String(c.name).begins_with("EscortShip"):
			c.set("fire_timer", INF)


func _teardown(wm) -> void:
	if wm != null and is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	await process_frame
	_Switches.reset()


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


static func _escorts(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("EscortShip") and not c.is_queued_for_deletion():
			out.append(c)
	return out


static func _enemies(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() and float(c.get("hull_hp")) > 0.0:
			out.append(c)
	return out


static func _panel(wm: Node) -> Node:
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			return n
	return null


func _key(wm: Node, code: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = pressed
		root.push_input(k)
	await process_frame


func _fleet_names() -> Array:
	var out: Array = []
	for s in _fleet.get("ships"):
		out.append(str((s as Dictionary).get("name", "")))
	return out


# ── 一、上阵船数 ───────────────────────────────────────

func _sec_deploy() -> void:
	print("== 一、上阵船数")
	_Switches.reset()
	var five := [_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40),
		_mk("canton_ship", "利涉", 50), _mk("keel_boat", "怀远", 20)]
	var wm: Node = await _stage(five, [{"type": "pirate_boat", "count": 2}])
	var esc := _escorts(wm)
	_check(esc.size() == 3, "四艘能上阵、敌船两艘：上阵三艘（护航封顶 3，得 %d）" % esc.size())
	var groups_ok := true
	var mirror_ok := true
	var look_ok := true
	for i in esc.size():
		var p: Node2D = esc[i]
		var s: Dictionary = (_fleet.get("ships") as Array)[i + 1]
		groups_ok = groups_ok and p.is_in_group("nk1_escort_ships") and not p.is_in_group("nk1_enemy_ships") \
			and String(p.name) == "EscortShip_%d" % (i + 1)
		mirror_ok = mirror_ok and is_equal_approx(float(p.get("hull_hp")), float(s["durability"])) \
			and is_equal_approx(float(p.get("hull_max")), float(s["max_durability"])) and int(p.get("crew")) == int(s["crew"]) \
			and str(p.get("ship_name")) == str(s["name"]) and str(p.get("ship_type")) == str(s["type"])
		var rig := p.get_node_or_null("HullRig")
		look_ok = look_ok and p.get("is_escort") == true and rig != null and rig.get("sail_crimson") == false \
			and p.get("wind_source") == wm.get("ship")
	_check(groups_ok, "护航节点 EscortShip_1..3、进 nk1_escort_ships、不进 nk1_enemy_ships")
	_check(mirror_ok, "护航船体 / 船体上限 / 人手 / 船名 / 船型照 Fleet 第 2–4 艘")
	_check(look_ok, "护航立 is_escort、素帆（HullRig.sail_crimson 关）、风读旗舰（wind_source）")
	_check(int(wm.call("_enemies_alive")) == 2 and int(wm.get("total_enemies")) == 2,
		"WorldMap 只数敌船（存活 %d、总数 %d）" % [int(wm.call("_enemies_alive")), int(wm.get("total_enemies"))])
	_check((_fleet.get("escorts_in_battle") as Array).size() == 3 and int(_fleet.call("battle_crew")) == 60 + 20,
		"Fleet 登记三艘上阵；白刃人手只算旗舰与没上阵的「怀远」（得 %d）" % int(_fleet.call("battle_crew")))
	await _teardown(wm)
	_check((_fleet.get("escorts_in_battle") as Array).is_empty(), "布景拆了（没走收战）登记照样清掉")

	for case in [[4, 3], [5, 2]]:
		var ships := [_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40),
			_mk("canton_ship", "利涉", 50)]
		wm = await _stage(ships, [{"type": "pirate_boat", "count": int(case[0])}])
		var n_esc := _escorts(wm).size()
		var n_foe := _enemies(wm).size()
		_check(n_esc == int(case[1]) and 1 + n_esc + n_foe <= _Wing.MAX_ON_FIELD,
			"敌船 %d 艘：上阵 %d 艘（得 %d），同屏 %d 艘 ≤ %d" % [int(case[0]), int(case[1]), n_esc, 1 + n_esc + n_foe, _Wing.MAX_ON_FIELD])
		await _teardown(wm)

	# 火船也占同屏格（pending_battle.yashan.fire_ships，崖山那一场的写法）：敌两艘 + 火船四艘，旗舰外只剩一格
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40),
		_mk("canton_ship", "利涉", 50)], [{"type": "pirate_boat", "count": 2}], 1000.0, 400.0, {"yashan": {"fire_ships": 4}})
	_check(_escorts(wm).size() == 1, "敌两艘 + 火船四艘：护航只上一艘（1 + 1 + 2 + 4 = 8，得 %d）" % _escorts(wm).size())
	await _teardown(wm)
	# 敌阵两条以上（闯封锁、崖山都是海鹘一条 + 快船一条）：敌船按全场序号起名，PirateShip_1..3 不撞名、WorldMap 三艘都数得到
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30)],
		[{"type": "sea_falcon", "count": 1, "sprite": "yuan_patrol"}, {"type": "pirate_boat", "count": 2}])
	var foe_names: Array = _enemies(wm).map(func(x): return String(x.name))
	foe_names.sort()
	_check(foe_names == ["PirateShip_1", "PirateShip_2", "PirateShip_3"] and int(wm.call("_enemies_alive")) == 3,
		"敌阵两条：敌船 PirateShip_1..3 不撞名、存活数 3（得 %s / %d）" % [str(foe_names), int(wm.call("_enemies_alive"))])
	await _teardown(wm)
	# 崖山突围那一场写 no_escort：护航一艘不上、不登记
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30)], [{"type": "pirate_boat", "count": 1}],
		1000.0, 400.0, {"no_escort": true})
	_check(_Wing.of(wm) == null and _escorts(wm).is_empty() and (_fleet.get("escorts_in_battle") as Array).is_empty() \
		and int(_fleet.call("battle_crew")) == 90, "pending_battle.no_escort：护航不上阵、不登记，白刃照全队 90 人")
	await _teardown(wm)

	var wreck := _mk("keel_boat", "安济", 30)
	wreck["durability"] = 0.0
	var empty := _mk("fu_ship_medium", "通济", 0)
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), wreck, empty, _mk("canton_ship", "利涉", 50)],
		[{"type": "pirate_boat", "count": 2}])
	esc = _escorts(wm)
	_check(esc.size() == 1 and str(esc[0].get("ship_name")) == "利涉",
		"船体见底的「安济」、没人的「通济」不上阵，只上「利涉」（得 %s）" % str(esc.map(func(x): return str(x.get("ship_name")))))
	await _teardown(wm)


# ── 二、三道将令 ───────────────────────────────────────

func _sec_orders() -> void:
	print("== 二、三道将令")
	_Switches.reset()
	# ① 布置期与过时照列队
	var wm: Node = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40)],
		[{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	var wing: Node = _Wing.of(wm)
	var panel: Node = _panel(wm)
	var box = panel.get("_escort_box") if panel != null else null
	var chips: Dictionary = panel.get("_escort_chips") if panel != null else {}
	_check(wing != null and wing.get("order_locked") == false and box is Control and (box as Control).visible \
		and chips.size() == 3 and not (chips["line"] as Button).disabled,
		"开战布置：将令未定、面板「护航将令」一节在、三枚签亮")
	var tips_ok := true
	for id in _Wing.ORDERS:
		tips_ok = tips_ok and str((chips[id] as Button).tooltip_text).contains("代价")
	_check(tips_ok and str((panel.get("_escort_costs") as Label).text).contains("代价"), "三枚签的提示与面板代价行都写明代价")
	var station_ok := true
	for p in _escorts(wm):
		station_ok = station_ok and p.get("escort_station_on") == true
	_check(station_ok, "未定将令时护航照列队跟站位")
	wing.set("_t", _Wing.ORDER_WINDOW_S - 0.05)
	await _frames(6)
	_check(wing.get("order_locked") == true and str(wing.get("order")) == "line" and str(wing.get("order_by")) == "timeout",
		"布置 %.0f 秒过了没下令：照列队（%s / %s）" % [_Wing.ORDER_WINDOW_S, str(wing.get("order")), str(wing.get("order_by"))])
	_check(wing.call("lock_order", "lure", "player") == false and str(wing.get("order")) == "line", "定了不再改（整场不变）")
	panel.call("refresh")
	_check((chips["lure"] as Button).disabled and not (chips["line"] as Button).disabled \
		and str((panel.get("_escort_state") as Label).text).contains("已定：列队") \
		and not (panel.get("_escort_costs") as Label).visible,
		"定了别的签灭、定下的「列队」留着、题头写「已定：列队」、代价行收起")
	await _teardown(wm)

	# ② 键盘 9 → 曳敌；曳敌的行为
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40)],
		[{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	wing = _Wing.of(wm)
	await _key(wm, KEY_9)
	_check(str(wing.get("order")) == "lure" and str(wing.get("order_by")) == "player", "键盘 9：曳敌（玩家下的）")
	await _key(wm, KEY_8)
	_check(str(wing.get("order")) == "lure", "再按 8 不改（整场不变）")
	var own: Node2D = wm.get("ship")
	await _frames(2)
	# 各艘护航缠哪艘由一翼自己挑（离得最近、不重挑）：把它缠的那艘摆到它跟前（LURE_PX 以内），看敌船掉头
	var pairs: Array = []
	for e in (wing.get("escorts") as Array):
		var foe = e["lure"]
		if foe != null and is_instance_valid(foe):
			(foe as Node2D).position = (e["node"] as Node2D).position + Vector2(420.0, 0.0).rotated(float(pairs.size()) * PI)
			pairs.append([e["node"], foe])
	await _frames(4)
	var lured := 0
	var paired := pairs.size() == 2
	for pr in pairs:
		if pr[1].get("target") == pr[0] and pr[1].get("wing") == wing and pr[1].get("wind_source") == own:
			lured += 1
		paired = paired and pr[0].get("target") == pr[1] and pr[0].get("escort_station_on") == false
	_check(paired, "曳敌：两艘护航各缠一艘不同的敌船（target 是那艘），不再跟站位")
	_check(lured == 2, "曳敌：护航近到 %.0f 内，两艘敌船都改打护航、风读旗舰、白刃交护航一翼（%d/2）" % [_Wing.LURE_PX, lured])
	var pu: Dictionary = wm.call("_pursuit")
	_check(int(pu["n"]) == 0, "被曳走的敌船不算追旗舰（_pursuit 追船 %d）" % int(pu["n"]))
	var foe0: Node2D = pairs[0][1]
	(pairs[0][0] as Node).call("take_damage", 99999.0)
	await _frames(3)
	_check(is_instance_valid(foe0) and foe0.get("target") == own and foe0.get("wind_source") == null \
		and foe0.get("wing") == null,
		"缠它的护航沉了：那艘敌船当即回头找旗舰（风读回 target、白刃回旗舰那一路）")
	await _teardown(wm)

	# ③ 鼠标点签 → 夺舱；夺舱的行为（敌四艘：旗舰钩一艘、护航夺一艘、再钩一艘，场上仍有敌船，不收战）
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40)],
		[{"type": "pirate_boat", "count": 4}])
	_freeze(wm)
	wing = _Wing.of(wm)
	panel = _panel(wm)
	((panel.get("_escort_chips") as Dictionary)["board"] as Button).pressed.emit()
	await _frames(2)
	_check(str(wing.get("order")) == "board" and str(wing.get("order_by")) == "player", "鼠标点「0 夺舱」：夺舱（玩家下的）")
	var esc := _escorts(wm)
	var wait_ok := true
	for p in esc:
		wait_ok = wait_ok and p.get("escort_station_on") == true and is_equal_approx(float(p.get("captain").get("reload_mul")), _Wing.BOARD_RELOAD_MUL)
	_check(wait_ok, "夺舱待命：旗舰没钩上前跟站位、装填慢 %.2f 倍" % _Wing.BOARD_RELOAD_MUL)
	var foes := _enemies(wm)
	var a: Node2D = foes[0]
	var a_id := a.get_instance_id()
	a.set("crew", 1)  # 旗舰这一钩稳拿：只验扳机，不验旗舰白刃
	wm.call("_board_enemy", a)
	await _frames(3)
	var second_ok := true
	for p in _escorts(wm):
		var t = p.get("target")
		second_ok = second_ok and t != null and is_instance_valid(t) and (t as Node).get_instance_id() != a_id \
			and String((t as Node).name).begins_with("PirateShip") \
			and p.get("captain").get("force_board") == true and p.get("escort_station_on") == false
	_check(wing.get("flag_hooked") == true and second_ok, "旗舰一钩上：护航改钩第二艘（不挑旗舰钩着的那艘），敌将径直接舷企图")
	esc = _escorts(wm)
	var b: Node2D = esc[1].get("target")
	var b_id := b.get_instance_id()
	esc[1].set("crew", 80)
	b.set("crew", 1)
	var n_before := (_fleet.get("ships") as Array).size()
	var r: Dictionary = wing.call("resolve_melee", esc[1], b)
	await _frames(2)
	var fates: Dictionary = wm.get("_enemy_fates")
	var b_fate := str((fates.get(b_id, {}) as Dictionary).get("fate", ""))
	var ships_after: Array = _fleet.get("ships")
	_check(str(r.get("legacy", "")) == "win" and ships_after.size() == n_before + 1 \
		and str((ships_after[ships_after.size() - 1] as Dictionary).get("type", "")) == "pirate_boat" \
		and int(wing.get("prizes_taken")) == 1 and (not is_instance_valid(b) or b.is_queued_for_deletion()) and b_fate == "boarded",
		"护航白刃得手：敌船入船籍（%d → %d 艘）、下场记「夺」（%s）、护航夺船 %d 艘" % [n_before, ships_after.size(), b_fate, int(wing.get("prizes_taken"))])
	foes = _enemies(wm)
	var c: Node2D = null
	for f in foes:
		if f.get_instance_id() != a_id and c == null:
			c = f
	var e0: Node2D = esc[0]
	e0.set("crew", 3)
	c.set("crew", 70)
	r = wing.call("resolve_melee", e0, c)
	await _frames(2)
	var e0_ref: Dictionary = (_fleet.get("ships") as Array)[1]
	_check(str(r.get("legacy", "")) == "lose" and is_instance_valid(c) and float(c.get("hull_hp")) > 0.0 \
		and int(e0_ref["crew"]) == maxi(1, int(e0.get("crew"))) and int(wing.get("prizes_taken")) == 1,
		"护航白刃不得手：敌船还在、护航折人（Fleet 那一格 %d 人照节点）、夺船数不变" % int(e0_ref["crew"]))
	# 抛钩挂上：两船并住 MELEE_HOLD_S 秒再分胜负
	e0.set("crew", 40)
	c.position = e0.position + Vector2(60.0, 0.0).rotated(e0.rotation)
	c.rotation = e0.rotation
	c.set("velocity", Vector2.ZERO)
	e0.set("velocity", Vector2.ZERO)
	var hooked := false
	for k in 30:
		seed(9100 + k)
		if bool(wing.call("ship_hooks", e0, c)):
			hooked = true
			break
	_check(hooked and e0.get("escort_locked") == true and c.get("escort_locked") == true and c.get("grappled") == false,
		"护航抛钩挂上：两船 escort_locked 并住（不碰 grappled，士气挂件不当旗舰钩舷算）")
	await _frames(int(ceil((_Wing.MELEE_HOLD_S + 0.3) * 60.0)))
	var released: bool = (not is_instance_valid(e0) or e0.get("escort_locked") == false) and (not is_instance_valid(c) or c.get("escort_locked") == false)
	_check(released and is_instance_valid(wing) and (wing.get("_melees") as Array).is_empty(), "并住 %.1f 秒后分出胜负、两船解开" % _Wing.MELEE_HOLD_S)
	await _teardown(wm)

	# ④ 触屏点签 → 列队；列队的行为
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30), _mk("fu_ship_medium", "通济", 40)],
		[{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	wing = _Wing.of(wm)
	panel = _panel(wm)
	await _frames(2)
	var chip := (panel.get("_escort_chips") as Dictionary)["line"] as Button
	# 触点按窗口坐标给（headless 窗口 64×64、内容缩放 0.05）：画布上签心经 root 的最终变换换过去；引擎把触点模拟成一次左键
	var at: Vector2 = root.get_final_transform() * chip.get_global_rect().get_center()
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.pressed = pressed
		t.position = at
		Input.parse_input_event(t)
		await process_frame
		await process_frame
	_check(str(wing.get("order")) == "line" and str(wing.get("order_by")) == "player",
		"触屏点「8 列队」：列队（玩家下的；%s / %s）" % [str(wing.get("order")), str(wing.get("order_by"))])
	own = wm.get("ship")
	own.set("sail_gear", 1)
	foes = _enemies(wm)
	for i in foes.size():
		(foes[i] as Node2D).position = own.position + Vector2(0.0, -1100.0).rotated(float(i) * 0.6)
	await _frames(480)
	var near_ok := true
	var worst := 0.0
	var e_list: Array = wing.get("escorts")
	for e in e_list:
		var p = e["node"]
		if not is_instance_valid(p):
			near_ok = false
			continue
		var st: Vector2 = p.get("escort_station")
		worst = maxf(worst, (p as Node2D).position.distance_to(st))
	near_ok = near_ok and worst <= 220.0
	_check(near_ok, "列队：旗舰开船八秒，护航都在站位 220 以内（最远 %.0f）" % worst)
	var chase_flag := true
	for f in _enemies(wm):
		chase_flag = chase_flag and f.get("target") == own
	_check(chase_flag, "列队：敌船照旧都冲旗舰来")
	await _teardown(wm)


# ── 三、结算记账不重 ───────────────────────────────────

func _sec_ledger() -> void:
	print("== 三、结算记账不重")
	_Switches.reset()
	var keel := _mk("keel_boat", "安济", 30, {"tea": {"qty": 5, "avg_cost": 20.0}})
	var fu := _mk("fu_ship_medium", "通济", 40)
	var wm: Node = await _stage([_mk("fu_ship_medium", "旗舰", 60), keel, fu], [{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	var wing: Node = _Wing.of(wm)
	var esc := _escorts(wm)
	# 敌船血量：扣掉上阵护航那一份战力（SeaChart._fleet_power 口径）再算比
	var share := float(wing.call("power_share"))
	var want_hull := 100.0 * clampf(400.0 / maxf(1.0, 1000.0 - share), 0.8, 3.0)
	var foe0: Node = _enemies(wm)[0]
	_check(is_equal_approx(float(foe0.get("hull_hp")), want_hull),
		"敌船血量按扣掉护航战力 %.0f 后的比缩放（得 %.2f，应 %.2f）" % [share, float(foe0.get("hull_hp")), want_hull])
	var crew0 := int(_fleet.call("total_crew"))
	# ① 护航挨一发：Fleet 那一格照扣
	esc[1].call("take_damage", 40.0)
	await _frames(2)
	_check(is_equal_approx(float(fu["durability"]), 300.0 - 40.0) and int(fu["crew"]) == maxi(1, int(esc[1].get("crew"))),
		"护航挨 40：Fleet「通济」耐久 300 → %.0f、人数照节点（%d）" % [float(fu["durability"]), int(fu["crew"])])
	# ② 旗舰白刃只算旗舰上的人；折损不扣护航；敌船按旗舰算接舷比
	var sides: Array = wm.call("_melee_sides", foe0, false)
	_check(int((sides[0] as Dictionary).get("crew", 0)) == 60 and int(_fleet.call("total_crew")) > 60,
		"旗舰白刃本队人手只算旗舰 60（全队 %d）" % int(_fleet.call("total_crew")))
	var keel_crew := int(keel["crew"])
	var fu_crew := int(fu["crew"])
	_fleet.call("lose_battle_crew", 5)
	var flag: Dictionary = (_fleet.get("ships") as Array)[0]
	_check(int(flag["crew"]) == 55 and int(keel["crew"]) == keel_crew and int(fu["crew"]) == fu_crew,
		"旗舰白刃折 5：只扣旗舰（60 → %d），护航人数不动" % int(flag["crew"]))
	var mf := float(_fleet.call("morale_factor"))
	var cp := float(_fleet.call("captain_power"))
	_check(is_equal_approx(float(foe0.call("_target_strength")), 55.0 * mf * cp),
		"敌船掂量旗舰接舷：只算旗舰上的人（%.1f）" % float(foe0.call("_target_strength")))
	# ③ 护航沉：收战才摘出 Fleet
	esc[0].call("take_damage", 99999.0)
	await _frames(3)
	_check(str(((wing.get("escorts") as Array)[0] as Dictionary)["fate"]) == "sunk" and float(keel["durability"]) == 0.0 \
		and _fleet_names().has("安济"), "护航「安济」沉了：记下场、耐久写 0，收战前还在册")
	wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	var data: Dictionary = _rec[0][1] if not _rec.is_empty() else {}
	var esc_rec: Dictionary = data.get("escort", {})
	var sunk: Array = esc_rec.get("sunk", [])
	_check(not _fleet_names().has("安济") and _fleet_names().has("通济"), "收战摘掉沉了的「安济」，「通济」照在（%s）" % str(_fleet_names()))
	_check(is_equal_approx(float(data.get("player_damage", -1.0)), 40.0 + 240.0),
		"player_damage = 通济挨的 40 + 安济整船 240，各算一遍（得 %.1f）" % float(data.get("player_damage", -1.0)))
	var lost := int((data.get("losses", {}) as Dictionary).get("crew", 0))
	_check(lost == crew0 - int(_fleet.call("total_crew")),
		"losses.crew = 开战水手 − 收战水手（%d = %d − %d），沉船上的人只记一遍" % [lost, crew0, int(_fleet.call("total_crew"))])
	_check(sunk.size() == 1 and str((sunk[0] as Dictionary).get("name", "")) == "安济" \
		and int(((sunk[0] as Dictionary).get("cargo", {}) as Dictionary).get("tea", 0)) == 5 \
		and int((data.get("losses", {}) as Dictionary).get("cargo", 0)) == 0,
		"沉船舱货另记 data.escort（茶 5），不算颠落舱面货")
	var note: String = _Wing.settle_note(data)
	_check(note.contains("「安济」沉没，该船货物随船（茶叶 5）") and note.contains("「通济」船体受损 40") and note.ends_with("。"),
		"札记一句交代护航下场（%s）" % note)
	_check((_fleet.get("escorts_in_battle") as Array).is_empty(), "收战清掉上阵登记")
	await _teardown(wm)


# ── 四、旗舰沉接任（13c）────────────────────────────────

func _sec_handoff() -> void:
	print("== 四、旗舰沉接任")
	_Switches.reset()
	var gs: Node = root.get_node("GameState")
	var fu := _mk("fu_ship_medium", "通济", 40)
	var wm: Node = await _stage([_mk("fu_ship_medium", "旗舰", 60, {"raw_silk": {"qty": 4, "avg_cost": 90.0}}),
		_mk("keel_boat", "安济", 30), fu], [{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	var esc := _escorts(wm)
	esc[1].call("take_damage", 25.0)
	esc[0].call("take_damage", 99999.0)
	await _frames(3)
	var own: Node2D = wm.get("ship")
	own.call("_hull_loss", float(own.get("hull_hp")) + 10.0)
	await process_frame
	var ok_lose: bool = not _rec.is_empty() and str(_rec[0][0]) == "lose" and bool((_rec[0][1] as Dictionary).get("sunk", false))
	_check(ok_lose, "旗舰沉：照旧 lose{sunk} 收战")
	_check(_fleet_names() == ["旗舰", "通济"], "沉了的护航收战已摘，名册剩旗舰（耐久 0）与「通济」（%s）" % str(_fleet_names()))
	gs.set("berth_index", 0)
	var line: String = _SeaChart._flagship_handoff()
	var top: Dictionary = (_fleet.get("ships") as Array)[0]
	_check(line.contains("「通济」接任旗舰") and (_fleet.get("ships") as Array).size() == 1 and str(top["name"]) == "通济" \
		and is_equal_approx(float(top["durability"]), 275.0),
		"13c 接任：还浮着的「通济」顶成旗舰、带着这一场的伤（耐久 %.0f）——%s" % [float(top["durability"]), line])
	await _teardown(wm)

	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30)], [{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	_escorts(wm)[0].call("take_damage", 99999.0)
	await _frames(3)
	own = wm.get("ship")
	own.call("_hull_loss", float(own.get("hull_hp")) + 10.0)
	await process_frame
	var none: String = _SeaChart._flagship_handoff()
	_check(none == "" and float(_fleet.call("total_durability")) <= 0.0,
		"护航全沉、旗舰再沉：无人接任，全队耐久见底（SeaChart 照全队沉没收尾）")
	await _teardown(wm)


# ── 五、关态回旧 ───────────────────────────────────────

func _sec_off() -> void:
	print("== 五、关态回旧")
	_Switches.reset()
	_Switches.set_on("escort_battle", false)
	var keel := _mk("keel_boat", "安济", 30)
	var fu := _mk("fu_ship_medium", "通济", 40)
	var before := [keel.duplicate(true), fu.duplicate(true)]
	var wm: Node = await _stage([_mk("fu_ship_medium", "旗舰", 60), keel, fu], [{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	_check(_Wing.of(wm) == null and _escorts(wm).is_empty() and (_fleet.get("escorts_in_battle") as Array).is_empty(),
		"escort_battle 关：一艘不刷、不登记")
	var foe0: Node = _enemies(wm)[0]
	_check(is_equal_approx(float(foe0.get("hull_hp")), 100.0 * clampf(400.0 / 1000.0, 0.8, 3.0)),
		"关：敌船血量照全队战力缩放（%.1f）" % float(foe0.get("hull_hp")))
	var sides: Array = wm.call("_melee_sides", foe0, false)
	_check(int((sides[0] as Dictionary).get("crew", 0)) == 130 and int(_fleet.call("battle_crew")) == 130,
		"关：旗舰白刃照全队人数 130")
	var plain := true
	for f in _enemies(wm):
		var cap = f.get("captain")
		plain = plain and f.get("is_escort") == false and is_equal_approx(float(f.get("armor_mul")), 1.0) \
			and f.get("wind_source") == null and f.get("wing") == null and cap.get("no_strike") == false \
			and cap.get("no_board") == false and cap.get("force_board") == false and is_equal_approx(float(cap.get("reload_mul")), 1.0)
	_check(plain, "关：敌船身上护航那几样全是缺省（is_escort / armor_mul / wind_source / wing / 敌将四旗）")
	var panel: Node = _panel(wm)
	_check(panel != null and panel.get("_escort_box") == null, "关：号令面板没有将令一节")
	await _key(wm, KEY_9)
	wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	var data: Dictionary = _rec[0][1] if not _rec.is_empty() else {}
	_check(not data.has("escort") and _Wing.settle_note(data) == "", "关：收战不写 data.escort、札记无护航句")
	_check(keel == before[0] and fu == before[1], "关：Fleet 两艘护航一字不动")
	await _teardown(wm)

	_Switches.set_on("escort_orders", false)
	wm = await _stage([_mk("fu_ship_medium", "旗舰", 60), _mk("keel_boat", "安济", 30)], [{"type": "pirate_boat", "count": 2}])
	_freeze(wm)
	var wing: Node = _Wing.of(wm)
	panel = _panel(wm)
	var box = panel.get("_escort_box") if panel != null else null
	_check(wing != null and _escorts(wm).size() == 1 and wing.get("order_locked") == true and str(wing.get("order")) == "line" \
		and str(wing.get("order_by")) == "auto", "escort_orders 关：护航照刷、将令照列队（auto）")
	await _key(wm, KEY_9)
	_check(panel.call("issue_escort", "lure") == false and str(wing.get("order")) == "line" \
		and (box == null or not (box as Control).visible), "escort_orders 关：签不出、按键不下")
	await _teardown(wm)
