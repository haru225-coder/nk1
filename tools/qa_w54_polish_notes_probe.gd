extends SceneTree
## lane w54-polish 旁注小笺专项探针（headless，经门锁跑）：
##   godot --headless --path . -s res://tools/qa_w54_polish_notes_probe.gd
## 一段钉一条、回退即红：
##   一、表与文案：data/combat_notes.json 条目齐（EXPECT_IDS 逐个在、不多不少），小题两到五字、正文二十到八十字、句号收尾，
##       不夹半角标点、不用叹号、四种括号配对；各条挂的开关键都在 CombatSwitches 表里，总开关 combat_notes 默认开；
##       一到六期的每个开关键都清点到一条小笺（KEY_NOTE）；停留秒数夹在上下限里。
##   二、已读与开关：排一张 → 下一帧出、记旗 combat_note_<id>、再排不上；排着的照先后一张张出；点掉 / 停满收起再出下一张；
##       总开关关 = 一张不排、观察件不挂；那一样自己的开关关（字串、字串表两种）= 那一张不出；排着时开关关了 = 跳过不出、不记旗；
##       旗标过 SaveLoad._harden_state + JSON 来回仍在（不另立存档字段）。
##   三、海战观察件：真起一场（WorldMap.tscn + pending_battle），开场按序排风与潮 → 号令 → 炮位与装填 → 敌情 → 职事，
##       有护航时将令排第一、崖山那一场崖山排第二；其后贴舷、拍板层、敌船动摇、我方士气、敌将接舷企图、敌船起火、
##       我船起火、装填侧重离开均装、敌将脱离各排对应那张；poll 不碰全局随机流；小笺摆在画布右缘、敌情列之下、小地图之上。
##   四、岸上挂点：海图收战（真走 _on_battle_result）排赏钱与人心、两散排大风两散、旗舰沉护航在排接任旗舰、
##       小卡几行排战后取舍与登岸剿寨、点封着的港排封港、闯封锁那一面排闯封锁；港页守城排守城与元军行事、外援一节排守城外援、
##       牙行战时短注排战时物价。
## 判词：末行 QA_W54_POLISH_NOTES PASS|FAIL cases=N fails=K；有失败退 1。

const TAG := "QA_W54_POLISH_NOTES"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
## 小笺件与观察件不读 autoload 标识符，可 preload；WorldMap / SeaChart / Main 直读 autoload，_run 里现 load
const N := preload("res://scripts/ui/CombatNotes.gd")
const W := preload("res://scripts/combat/CombatNoteWatch.gd")

const EXPECT_IDS := ["escort", "yashan", "sea", "orders", "gunnery", "intel", "roles", "boarding", "melee_decision",
	"parley", "morale", "cut_grapple", "flood_fire", "wet_felt", "fire_load", "pursue", "bounty", "after_choices",
	"landing", "morale_carry", "gale", "handoff", "blockade", "blockade_run", "war_prices", "siege", "siege_schedule",
	"siege_relief",
	# lane tut2（w57）：城区与牙行四张引导旁注，不挂分开关、只认总开关 combat_notes（触发与读旗归 qa_w57_tut_probe）
	"districts", "invest_shop", "flag_chain", "seasonal_price"]
## 一到六期的开关键 → 讲它的那一张（清点表：方案分期一览逐项；没有开关的底子玩法 sea / orders / boarding / morale / siege 另立）
const KEY_NOTE := {
	"enemy_intel": "intel", "parley_on_ship": "parley", "after_action": "bounty", "bounty_by_outcome": "bounty",
	"flagship_handoff": "handoff", "morale_carry": "morale_carry", "gale_parting": "gale",
	"player_gunnery": "gunnery", "archer_scaling": "gunnery", "crew_role_effects": "roles",
	"order_cut_grapple": "cut_grapple", "order_wet_felt": "wet_felt",
	"enemy_flood_fire": "flood_fire", "fire_attack_load": "fire_load",
	"waa_prize": "after_choices", "waa_rescue": "after_choices", "waa_captives": "after_choices",
	"waa_ransom": "after_choices", "waa_pursue": "after_choices",
	"melee_decision": "melee_decision", "pursue_window": "pursue", "war_prices": "war_prices",
	"port_blockade": "blockade", "blockade_run": "blockade_run", "siege_schedule": "siege_schedule",
	"siege_relief": "siege_relief", "landing_raid": "landing", "escort_battle": "escort", "escort_orders": "escort",
	"yashan_breakout": "yashan", "yashan_fire_ship": "yashan",
}
## 清点表里各键在正文里点到的字样（一张讲两样的，两样都得写到）
const KEY_WORD := {
	"archer_scaling": "每五人", "after_action": "赏钱", "waa_prize": "押", "waa_rescue": "落水", "waa_captives": "俘虏",
	"waa_ransom": "索赎", "waa_pursue": "追", "yashan_fire_ship": "火船", "escort_battle": "上阵", "escort_orders": "将令",
}

var _gs: Node = null
var _fleet: Node = null
var _gm: Node = null
var _cal: Node = null
var _crew: Node = null
var _cases := 0
var _fails := 0
var _seed := 5400


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
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_gs = root.get_node("GameState")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	_cal = root.get_node("Calendar")
	_crew = root.get_node("Crew")
	var keep := {"gs": _gs.call("to_dict"), "fleet": _fleet.call("to_dict"), "cal": _cal.call("to_dict"),
		"crew": _crew.call("to_dict"), "pb": (_gm.get("pending_battle") as Dictionary).duplicate(true)}
	_Switches.reset()
	print("== 一、表与文案")
	_sec_table()
	print("== 二、已读与开关")
	await _sec_read()
	print("== 三、海战观察件")
	await _sec_battle()
	print("== 四、岸上挂点")
	await _sec_shore()
	_Switches.reset()
	_gs.call("from_dict", keep["gs"])
	_fleet.call("from_dict", keep["fleet"])
	_cal.call("from_dict", keep["cal"])
	_crew.call("from_dict", keep["crew"])
	_gm.set("pending_battle", keep["pb"])
	await process_frame
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(0 if _fails == 0 else 1)


# ── 共用 ──────────────────────────────────────────────

func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## 把小笺旗全擦掉（各节从「一张没看过」起）
func _clear_read() -> void:
	var flags: Dictionary = _gs.get("flags")
	for k in flags.keys():
		if str(k).begins_with(N.FLAG_PREFIX):
			flags.erase(k)


## host 下的小笺层：正出着的那张 + 排着的，按先后
func _seen(host: Node) -> Array:
	var lay = N.layer_of(host)
	if lay == null:
		return []
	var out: Array = []
	if str(lay.call("current")) != "":
		out.append(str(lay.call("current")))
	for id in lay.call("pending"):
		out.append(str(id))
	return out


## 只看开场那几张（敌船开场士气随机落在 50–75，55 以下一开场就是动摇，劝降那张会跟着排上——开场排序不比它）
func _seen_start(host: Node) -> Array:
	return _seen(host).filter(func(i): return W.START_ORDER.has(i))


func _host() -> Node:
	var h := Node.new()
	h.name = "NotesHost"
	root.add_child(h)
	return h


# ── 一、表与文案 ──────────────────────────────────────

func _sec_table() -> void:
	var tab: Dictionary = N.table()
	var ids: Array = tab.keys()
	ids.sort()
	var want := EXPECT_IDS.duplicate()
	want.sort()
	_check(ids == want, "小笺 %d 条，条目与清点表一致（多出 %s，缺 %s）" % [ids.size(),
		ids.filter(func(i): return not want.has(i)), want.filter(func(i): return not ids.has(i))])
	var bad := []
	var half := RegEx.create_from_string("[,.!?;:]|！")
	for id in ids:
		var e: Dictionary = tab[id]
		var t := str(e.get("title", ""))
		var x := str(e.get("text", ""))
		if t.length() < 2 or t.length() > 5:
			bad.append("%s 小题「%s」字数" % [id, t])
		if x.length() < 20 or x.length() > 80 or not x.ends_with("。"):
			bad.append("%s 正文 %d 字、收尾「%s」" % [id, x.length(), x.right(1)])
		if half.search(t + x) != null:
			bad.append("%s 夹了半角标点或叹号" % id)
		for pair in [["「", "」"], ["『", "』"], ["（", "）"], ["《", "》"]]:
			if x.count(pair[0]) != x.count(pair[1]):
				bad.append("%s %s%s 不齐" % [id, pair[0], pair[1]])
		for k in N.switch_keys(e):
			if not _Switches.DEFAULTS.has(k):
				bad.append("%s 挂的开关键 %s 不在 CombatSwitches 表里" % [id, k])
	_check(bad.is_empty(), "各条小题 / 正文 / 标点 / 开关键合规（%s）" % [bad])
	_check(_Switches.DEFAULTS.get(N.SWITCH) == true, "总开关 %s 在 CombatSwitches 表里、默认开" % N.SWITCH)
	var miss := []
	for k in KEY_NOTE:
		var nid := str(KEY_NOTE[k])
		var e: Dictionary = tab.get(nid, {})
		if not _Switches.DEFAULTS.has(k) or e.is_empty():
			miss.append(k)
		elif KEY_WORD.has(k) and str(e.get("text", "")).find(str(KEY_WORD[k])) < 0:
			miss.append("%s（%s 没写到「%s」）" % [k, nid, KEY_WORD[k]])
	_check(miss.is_empty(), "一到六期 %d 个开关键各有一张讲它（没着落：%s）" % [KEY_NOTE.size(), miss])
	_check(is_equal_approx(N.hold_s(""), N.HOLD_MIN) and is_equal_approx(N.hold_s("字".repeat(200)), N.HOLD_MAX)
		and N.hold_s("字".repeat(40)) > N.HOLD_MIN, "停留秒数夹在 %.0f–%.0f 秒（四十字 %.1f 秒）" % [N.HOLD_MIN, N.HOLD_MAX, N.hold_s("字".repeat(40))])


# ── 二、已读与开关 ────────────────────────────────────

func _sec_read() -> void:
	_clear_read()
	var h := _host()
	_check(N.want("sea") and N.offer(h, "sea"), "没看过的「风与潮」排得上")
	_check(not N.offer(h, "sea"), "同一张排着时不重排")
	_check(N.offer(h, "orders") and _seen(h) == ["sea", "orders"], "再排一张接在后面（%s）" % [_seen(h)])
	await _frames(2)
	var lay = N.layer_of(h)
	var slip = lay.call("slip") if lay != null else null
	_check(lay != null and str(lay.call("current")) == "sea" and slip != null, "下一帧出头一张")
	_check(bool(_gs.call("has_flag", "combat_note_sea")) and not bool(_gs.call("has_flag", "combat_note_orders")),
		"出了的记旗 combat_note_sea，排着没出的不记")
	var txt: Label = slip.find_child("NoteText", true, false) if slip != null else null
	var ttl: Label = slip.find_child("NoteTitle", true, false) if slip != null else null
	_check(txt != null and ttl != null and txt.text == str(N.entry("sea")["text"]) and ttl.text == "风与潮",
		"小笺上是那一条的小题与正文")
	_check(lay != null and lay.layer == N.LAYER_INDEX, "小笺层号 %d（白刃拍板层之上、出战墨边之下）" % N.LAYER_INDEX)
	_check(not N.want("sea") and not N.offer(h, "sea"), "看过的不再排")
	lay.call("dismiss")
	await _wait(N.T_OUT + N.BETWEEN + 0.2)
	await _frames(2)
	_check(str(lay.call("current")) == "orders" and bool(_gs.call("has_flag", "combat_note_orders")),
		"点掉一张，空一拍出下一张（%s）" % str(lay.call("current")))
	# 停满自己收起：把剩余秒数拨到零
	lay.set("_left", 0.0)
	await _wait(N.T_OUT + 0.15)
	_check(str(lay.call("current")) == "" and lay.call("slip") == null, "停满了自己收起")
	# 排着时那一样的开关关了：跳过不出、不记旗
	_check(N.offer(h, "intel"), "排一张「敌情」")
	_Switches.set_on("enemy_intel", false)
	await _wait(N.BETWEEN + 0.2)
	await _frames(2)
	_check(str(lay.call("current")) == "" and not bool(_gs.call("has_flag", "combat_note_intel")),
		"排着时 enemy_intel 关了：跳过不出、不记旗")
	_check(not N.want("intel"), "enemy_intel 关：「敌情」不该出")
	_Switches.reset()
	_Switches.set_on("enemy_flood_fire", false)
	_check(N.switches_on("wet_felt") and not N.switches_on("fire_load"),
		"字串表开关：火攻挂 fire_attack_load + enemy_flood_fire，后者关就不出；张湿毡不受累")
	_Switches.reset()
	_Switches.set_on(N.SWITCH, false)
	var h2 := _host()
	_check(not N.want("boarding") and not N.offer(h2, "boarding") and N.layer_of(h2) == null,
		"总开关关：一张不排、不挂小笺层")
	var w := Node2D.new()
	root.add_child(w)
	_check(W.attach(w) == null and w.get_node_or_null(W.NODE_NAME) == null, "总开关关：海战观察件不挂")
	_Switches.reset()
	_check(W.attach(w) != null and w.get_node_or_null(W.NODE_NAME) != null, "总开关开：观察件挂上")
	w.queue_free()
	# 旗标随档：过 SaveLoad 的旗标清洗与 JSON 来回
	var sl: Node = root.get_node("SaveLoad")
	var st: Dictionary = sl.call("_harden_state", _gs.call("to_dict"))
	var back = JSON.parse_string(JSON.stringify(st))
	var keep: Dictionary = _gs.call("to_dict")
	_gs.call("from_dict", {})
	var gone := not bool(_gs.call("has_flag", "combat_note_sea"))
	_gs.call("from_dict", back)
	_check(gone and bool(_gs.call("has_flag", "combat_note_sea")) and bool(_gs.call("has_flag", "combat_note_orders"))
		and not bool(_gs.call("has_flag", "combat_note_intel")), "已读旗过存档清洗与 JSON 来回仍在，没看过的仍没看过")
	_gs.call("from_dict", keep)
	h.queue_free()
	h2.queue_free()
	await _frames(2)


# ── 三、海战观察件 ────────────────────────────────────

func _mk(t: String, nm: String, crew: int) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": dur, "max_durability": dur}


## 真起一场（同 qa_w53_p6_escort_probe 的布景）：士气簿裁决不接，敌船冻住炮与钩
func _stage(ships: Array, extra := {}) -> Node:
	_fleet.set("ships", ships)
	_fleet.set("morale", 60)
	_fleet.set("escorts_in_battle", [])
	_seed += 1
	seed(_seed)
	var pb := {"battle": true, "power": 300.0, "player_power": 600.0, "enemy": [{"type": "pirate_boat", "count": 2}],
		"sea_name": "泉州外海", "sea_seed": 7_100_000 + _seed, "battle_seed": 7_300_000 + _seed, "source": {"scene": "qa_w54_polish_notes"}}
	pb.merge(extra, true)
	_gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var mo = wm.get("_morale")
	if mo != null and mo.verdict.is_connected(Callable(wm, "_on_morale_verdict")):
		mo.verdict.disconnect(Callable(wm, "_on_morale_verdict"))
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	await _frames(2)
	return wm


func _teardown(wm) -> void:
	if wm != null and is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await _frames(2)


func _foes(wm: Node) -> Array:
	var w = wm.get_node_or_null(W.NODE_NAME)
	return w.call("live_enemies") if w != null else []


func _sec_battle() -> void:
	_clear_read()
	_crew.call("from_dict", {})
	# 1. 单船一场：开场按序
	var wm := await _stage([_mk("fu_ship_medium", "福船", 60)])
	var watch = wm.get_node_or_null(W.NODE_NAME)
	_check(watch != null, "开战即挂观察件（WorldMap._setup_combat）")
	_check(_seen(wm).is_empty(), "开场墨边揭开前一张不出（%s）" % [_seen(wm)])
	# 开战就把敌船钉远处、士气钉稳，免 START_S 窗口漂近误排接舷・劝降
	var _ship0 = wm.get("ship")
	for _e in _foes(wm):
		if _e is Node2D and _ship0 is Node2D:
			(_e as Node2D).global_position = (_ship0 as Node2D).global_position + Vector2(900, 0)
			(_e as Object).set_meta(W.MORALE_META, {"state": "steady"})
	if _ship0 is Object:
		(_ship0 as Object).set_meta(W.MORALE_META, {"state": "steady"})
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(_seen_start(wm) == ["sea", "orders", "gunnery", "intel"],
		"开场按序：风与潮 → 号令 → 炮位与装填 → 敌情（没有护航、不是崖山、没雇职事：%s）" % [_seen(wm)])
	await _frames(2)
	var lay = N.layer_of(wm)
	var slip: Control = lay.call("slip") if lay != null else null
	if slip != null:
		var cv: Vector2 = root.get_visible_rect().size
		var r := slip.get_global_rect()
		var hud = null
		for n in wm.get_children():
			if n.is_in_group("nk1_combat_status"):
				hud = n
		var intel: Control = hud.get("_intel") if hud != null else null
		var mini := wm.get_node_or_null("CanvasLayer/HUD/MinimapPanel") as Control
		_check(r.end.x <= cv.x and r.position.x >= 0.0 and r.position.y >= 0.0, "小笺不出画布（%s，画布 %s）" % [r, cv])
		_check(intel == null or not intel.is_visible_in_tree() or absf(r.end.x - intel.get_global_rect().end.x) < 0.5,
			"小笺右缘与敌情列对齐（%.0f / %.0f）" % [r.end.x, intel.get_global_rect().end.x if intel != null else -1.0])
		_check(intel == null or not intel.is_visible_in_tree() or r.position.y >= intel.get_global_rect().end.y + N.GAP - 0.5,
			"小笺在敌情列之下（敌情列底 %.0f，小笺顶 %.0f）" % [intel.get_global_rect().end.y if intel != null else -1.0, r.position.y])
		_check(mini == null or not mini.is_visible_in_tree() or r.end.y <= mini.get_global_rect().position.y - N.GAP + 0.5,
			"小笺在小地图之上（小地图顶 %.0f，小笺底 %.0f）" % [mini.get_global_rect().position.y if mini != null else -1.0, r.end.y])
	else:
		_check(false, "开场那一张出来了")
	# 2. 逐样第一次露面（poll 直调；布景改了就看那一张排没排上）
	var ship: Node2D = wm.get("ship")
	var foes := _foes(wm)
	_check(foes.size() == 2, "场上两艘敌船")
	if foes.size() < 2 or watch == null:
		await _teardown(wm)
		return
	var e0: Node2D = foes[0]
	var e1: Node2D = foes[1]
	e0.global_position = ship.global_position + Vector2(900, 0)
	e1.global_position = ship.global_position + Vector2(-900, 200)
	# 钉死远处与士气，免 START_S 窗口里船漂近 / 阵脚抖触发接舷・劝降（整合树约四成抖红）
	e0.set_meta(W.MORALE_META, {"state": "steady"})
	e1.set_meta(W.MORALE_META, {"state": "steady"})
	if ship != null:
		ship.set_meta(W.MORALE_META, {"state": "steady"})
	var rng_a := _rng_after(func() -> void: watch.call("poll"))
	var rng_b := _rng_after(func() -> void: pass)
	_check(rng_a == rng_b, "poll 不碰全局随机流（同种子下一发相同）")
	watch.call("poll")
	_check(not _seen(wm).has("boarding") and not _seen(wm).has("parley"), "敌船在远处、阵脚稳：接舷 / 劝降不排")
	e0.global_position = ship.global_position + Vector2(180, 0)
	watch.call("poll")
	_check(_seen(wm).has("boarding"), "敌船贴到舷边 1.5 倍够距内：排「接舷」")
	e1.set_meta(W.MORALE_META, {"state": "shaken"})
	watch.call("poll")
	_check(_seen(wm).has("parley"), "敌船阵脚动摇：排「劝降」")
	ship.set_meta(W.MORALE_META, {"state": "shaken"})
	watch.call("poll")
	_check(_seen(wm).has("morale"), "我方士气掉出稳：排「士气」")
	var cap = e1.get("captain")
	if cap != null:
		cap.set("state", &"board")
	watch.call("poll")
	_check(_seen(wm).has("cut_grapple"), "敌将改打法接舷企图：排「砍钩」")
	var eff = e1.get("flood_fire")
	if eff != null and eff.get("ff") != null:
		(eff.get("ff").get("fire") as Dictionary)["mid"] = 0.4
	watch.call("poll")
	_check(_seen(wm).has("flood_fire"), "敌船起火：排「水与火」")
	var dm = ship.get("damage_model")
	if dm != null and dm.get("ff") != null:
		(dm.get("ff").get("fire") as Dictionary)["bow"] = 0.3
	watch.call("poll")
	_check(_seen(wm).has("wet_felt"), "我船起火：排「张湿毡」")
	var orders = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			orders = n
	watch.call("poll")
	_check(not _seen(wm).has("fire_load"), "装填侧重还在均装：火攻不排")
	if orders != null:
		orders.set("load_mode", "focus")
	watch.call("poll")
	_check(_seen(wm).has("fire_load"), "装填侧重离开均装、火攻在轮换里：排「火攻」")
	if cap != null:
		cap.set("state", &"disengage")
	watch.call("poll")
	_check(_seen(wm).has("pursue"), "敌将转脱离：排「追击」")
	var panel: CanvasLayer = (load("res://scripts/ui/MeleeDecisionPanel.gd") as GDScript).new()
	panel.add_to_group("nk1_melee_decision")
	wm.add_child(panel)
	watch.call("poll")
	_check(not _seen(wm).has("melee_decision"), "拍板层挂着没在等：三决断不排")
	panel.set("_ask", true)
	watch.call("poll")
	_check(_seen(wm).has("melee_decision"), "拍板层在等人拍：排「白刃三决断」")
	panel.queue_free()
	await _teardown(wm)
	# 3. 再开一场：上一场真出过的（只有头一张风与潮）不再排，排着没出过的照排
	wm = await _stage([_mk("fu_ship_medium", "福船", 60)])
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(_seen_start(wm) == ["orders", "gunnery", "intel"], "再开一场：出过的风与潮不再排，排着没出的照排（%s）" % [_seen(wm)])
	await _teardown(wm)
	for id in ["orders", "gunnery", "intel"]:
		_gs.call("set_flag", N.flag_of(id))
	wm = await _stage([_mk("fu_ship_medium", "福船", 60)])
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(_seen_start(wm).is_empty(), "开场几张都看过：一张不排（%s）" % [_seen(wm)])
	await _teardown(wm)
	# 4. 护航上阵 + 崖山 + 职事：将令排第一、崖山第二、职事排末
	_clear_read()
	_crew.call("from_dict", {"hired": {"tongshi": _first_cand("tongshi")}})
	wm = await _stage([_mk("fu_ship_medium", "福船", 60), _mk("keel_boat", "安济", 30)])
	wm.set("_yashan_on", true)
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(_seen_start(wm) == ["escort", "yashan", "sea", "orders", "gunnery", "intel", "roles"],
		"有护航、崖山那一场、雇着通事：将令 → 崖山 → 风与潮 → 号令 → 炮位 → 敌情 → 职事（%s）" % [_seen(wm)])
	wm.set("_yashan_on", false)
	await _teardown(wm)
	_crew.call("from_dict", {})
	# 5. 那一样关着：开场不排它
	_clear_read()
	_Switches.set_on("player_gunnery", false)
	_Switches.set_on("enemy_intel", false)
	wm = await _stage([_mk("fu_ship_medium", "福船", 60)])
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(_seen_start(wm) == ["sea", "orders"], "player_gunnery / enemy_intel 关：开场只排风与潮、号令（%s）" % [_seen(wm)])
	await _teardown(wm)
	_Switches.reset()
	_Switches.set_on(N.SWITCH, false)
	wm = await _stage([_mk("fu_ship_medium", "福船", 60)])
	await _wait(W.START_S + W.POLL_S + 0.3)
	_check(wm.get_node_or_null(W.NODE_NAME) == null and wm.get_node_or_null(N.NODE_NAME) == null,
		"总开关关：海战里不挂观察件、不挂小笺层（逐字回旧）")
	await _teardown(wm)
	_Switches.reset()


## 跑一下 f 之后全局随机流的下一发（先钉种子）
func _rng_after(f: Callable) -> int:
	seed(424242)
	f.call()
	return randi()


## 名册里某职事的头一个候选 id
func _first_cand(role: String) -> String:
	var f := FileAccess.open("res://data/crew.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else {}
	if not (d is Dictionary):
		return ""
	for c in (d as Dictionary).get("candidates", []):
		if str(c.get("role", "")) == role:
			return str(c.get("id", ""))
	return ""


# ── 四、岸上挂点 ──────────────────────────────────────

func _sec_shore() -> void:
	_clear_read()
	# 海图：收战真走 _on_battle_result
	_cal.call("from_dict", {"year": 1260, "month": 5, "day": 1})
	_fleet.set("ships", [_mk("fu_ship_medium", "福船", 60)])
	_gs.call("ban_port", "mingzhou", "1300-01")
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await _frames(3)
	sc.set("remaining_li", 50.0)
	_gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海", "source": {"scene": "SeaChart", "event": "pirate"}})
	sc.call("_on_battle_result", "win", {"player_damage": 5.0, "morale_carry": 58,
		"fates": [{"type": "pirate_boat", "fate": "sunk"}, {"type": "pirate_boat", "fate": "sunk"}]})
	var got := _seen(sc)
	_check(got.slice(0, 2) == ["bounty", "morale_carry"], "海图收战胜局：排赏钱、人心（%s）" % [got])
	sc.call("_battle_notes", "flee", {"parted": true, "gale": true})
	_check(_seen(sc).has("gale"), "大风两散：排「大风两散」")
	_fleet.set("ships", [_mk("fu_ship_medium", "福船", 60), _mk("keel_boat", "安济", 30)])
	(_fleet.get("ships")[0] as Dictionary)["durability"] = 0.0
	sc.call("_battle_notes", "lose", {"sunk": true})
	_check(_seen(sc).has("handoff"), "旗舰沉了、护航还浮着：排「接任旗舰」")
	sc.call("_card_notes", [{"key": "prize"}, {"key": "rescue"}, {"key": "landing"}])
	_check(_seen(sc).has("after_choices") and _seen(sc).has("landing"), "战后小卡几行：排战后取舍、登岸剿寨")
	# 点封着的港：对己封港的明州（起图前封上）
	sc.set("sailing", false)
	sc.call("_on_map_port_clicked", "mingzhou")
	_check(_seen(sc).has("blockade"), "点到封着的港：排「封港」（%s）" % [_seen(sc)])
	sc.call("_offer_run", "xinghua")
	_check(_seen(sc).has("blockade_run"), "闯封锁那一面：排「闯封锁」")
	sc.queue_free()
	await _frames(2)
	# 港页：守城（兴化 1276-11）、外援、牙行战时价
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(6)
	# 布景照 qa_w53_p5_siege_probe._stage_siege（兴化首守，冬月初三）
	_gs.call("from_dict", {})
	_gs.call("set_flag", "renamed_wenlong")
	_gs.set("identity", "scholar")
	_gs.set("money", 20000)
	_gs.set("fame", 30)
	_gs.set("last_port", "xinghua")
	_cal.call("from_dict", {"year": 1276, "month": 11, "day": 3})
	_crew.call("from_dict", {})
	_fleet.set("ships", [])
	_fleet.call("add_ship", "sampan", "无名小艍")
	_fleet.set("water", 60)
	_fleet.set("food", 60)
	_fleet.set("morale", 70)
	main.call("load_scene", "xinghua")
	await _frames(3)
	var sm := _seen(main)
	_check(sm.slice(0, 2) == ["siege", "siege_schedule"], "守城页：排守城、元军行事（%s）" % [sm])
	main.call("_siege_page_foot", "siege_grain")
	_check(_seen(main).has("siege_relief"), "外援一节露面：排「守城外援」")
	_cal.call("from_dict", {"year": 1276, "month": 2, "day": 1})
	var info := VBoxContainer.new()
	var price := Label.new()
	root.add_child(info)
	main.call("_mount_price_row", info, price, "mingzhou", "korean_ginseng")
	_check(_seen(main).has("war_prices"), "牙行挂战时短注：排「战时物价」")
	info.queue_free()
	main.queue_free()
	await _frames(2)
