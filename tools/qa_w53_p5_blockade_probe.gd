extends SceneTree
## lane-w53-p5-blockade 拦港（待拍板 20b）专项探针（战斗系统方案 §七「封港与围城真的拦」，一条一节、回退即红）：
##   一、晨潮三向不发封着的港（开关 port_blockade）：封港 / 围城七个月份（博多唐房、萨摩 1274-10 至 1275-04 封港，
##       福州 1276-10、兴化与兴化海口与广州 1276-11、兴化与兴化海口 1277-09 / 10 围城）× 全部已解锁起点 × 八手盐位，
##       发出封着的港即红；对己封港（泉州连夜出港那条 port_bans）同判。
##       关态 = 逐字回旧：同一批手牌里封着的港照旧发得出，HeadingDraft.pool 与旧口径（已解锁、depth>0、非起点）逐一相等。
##   二、海图上点封着的港只给「港已封」：真起 SeaChart，_on_map_port_clicked 点围城 / 封港 / 对己封港三样，
##       札记首行「港已封」打头写封因、去处不选上；没封、只是风不放的港照旧「今日风不放这一向。」；
##       图上封着的港打朱砂叉（MapView.sealed 与此刻封着的港相等）。关态：不出「港已封」、图上不打叉。
##   三、剧情要去的港放行（HeadingDraft.story_pass）：士人线守城（改名文龙、1276 年兴化被围）、涵江海口（1277 年九、十月
##       兴化再围、复核过旧避风澳）兴化与兴化海口都进三向；在身委办的交货港放行；别的封着的港照旧拦。
##       与 Main 卡判据逐月对账：1276-08 至 1277-12 × 身份 / 发现 / 终局各样，story_pass(兴化海口) 恰等于海口挂出
##       「入城」或「涵江海口」卡，story_pass(兴化) 恰等于 Main._siege_due() 或城里挂出涵江卡——两边判据漂了即红。
##       章目的亲至港不放行、也不卡死：第二章要亲至博多唐房，1274-11 封港时三向里没有它，1275-05 解封后照旧钉第一席。
##   四、闯封锁（开关 blockade_run，战斗系统方案 §七）：
##       到港外撞上哨船的机会——固定种子 1..N 逐个掷 Voyage.blockade_patrol_met，命中率落在四成上下；
##       图上点被围的港、舱里有米粮：挂「闯封锁」一面（写收粮价、四成撞上哨船、输了的下场），选了才设去处，开航钮改写「闯封锁」；
##       没米粮只给「港已封」（带一句「舱里带上米粮，可以闯封锁」）；
##       没撞上：照围城米价卖粮（Economy.blockade_grain_unit = 平年米价 × war_price_factor，没有那个函数退回 1.8）、
##       城里一趟只收 Economy.blockade_grain_cap（本港行情深浅 depth）件、多的留在舱里，名声每百件一点（至多五点），
##       照常进港；撞上：挂「哨船拦港」一面（迎战 / 掉头回航）；
##       迎战走现成 pending_battle → WorldMap（海鹘一艘 + 快船两艘、都挂 yuan_patrol、战力 320–760、source.event=blockade），真开一场、收战赢，
##       照价卖粮进港；输了 / 没逃成 / 逃了（弃战、甩脱）/ 掉头：米粮一件不剩，船折回起锚港（起讫对调、照常一日日走回去）；
##       大风 / 天黑两散算闯过去；全队沉了不对调，沉船那条路送回起锚港；到港时围已解：不卖粮、照常进港；
##       这一程途中撞上的海寇那一仗不算拦港（只认 source.event）。
##   五、开关关态：blockade_run 关 = 被围的港照 20b 只给「港已封」、不挂闯封锁一面；port_blockade 关 = 被围的港不封、
##       也就无从闯（旧玩法）；剧情放行的港照常走，不算闯封锁。
##   六、期望净利（印数不判红绿的 EV 表 + 三条不成摇钱树的界）：兴化、福州是产米地，围城价仍不及消费地平年米价；
##       广州（平常地）围城价不超消费地平年米价 1.25 倍；一趟收量封顶在本港 depth（舱再大也多卖不了）。
## 用法：godot --headless --path . -s res://tools/qa_w53_p5_blockade_probe.gd
## 判词：QA_W53_P5_BLOCKADE cases=N fails=M；fails>0 退 1。本进程有 SCRIPT ERROR 即红。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const CS := preload("res://scripts/combat/CombatSwitches.gd")
const HD_PATH := "res://scripts/core/HeadingDraft.gd"
const MAIN_PATH := "res://scripts/Main.gd"

const TAG := "QA_W53_P5_BLOCKADE"
## 封港 / 围城的月份（data/ports.json war 表现表）：每月至少封着一港
const SEALED_MONTHS := [[1274, 10], [1275, 1], [1275, 4], [1276, 10], [1276, 11], [1277, 9], [1277, 10]]
const SALTS := 8

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false
var _hd: GDScript
var _gs: Node
var _cal: Node
var _eco: Node
var _gm: Node


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
	_hd = load(HD_PATH) as GDScript
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_eco = root.get_node("Economy")
	_gm = root.get_node("GameManager")
	var cal_keep: Dictionary = _cal.call("to_dict")

	print("== 一、晨潮三向不发封着的港（port_blockade）")
	_sec_draft()
	print("== 二、海图上点封着的港只给「港已封」")
	await _sec_click()
	print("== 三、剧情要去的港放行（与 Main 卡判据逐月对账）")
	_sec_story()
	var fleet: Node = root.get_node("Fleet")
	var fleet_keep := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"water": fleet.get("water"), "food": fleet.get("food")}
	print("== 四、闯封锁（blockade_run）")
	_sec_run_odds()
	await _sec_run_offer(fleet)
	await _sec_run_paths(fleet)
	print("== 五、开关关态 / 剧情港不算闯")
	await _sec_run_off(fleet)
	print("== 六、期望净利（不成摇钱树）")
	_sec_run_ev()
	fleet.set("ships", fleet_keep["ships"])
	fleet.set("morale", fleet_keep["morale"])
	fleet.set("water", fleet_keep["water"])
	fleet.set("food", fleet_keep["food"])
	fleet.set("at_sea", false)

	CS.reset()
	_gs.call("from_dict", {})
	_cal.call("from_dict", cal_keep)
	await _report()


# ── 造局 ─────────────────────────────────────────────

## 白板一局：第四章（十四港全解锁）、人在 port、日子 y-m-d、无旗无委办无对己封港
func _stage(y: int, m: int, port := "quanzhou", d := 5) -> void:
	_gs.call("from_dict", {})
	_gs.set("chapter", 4)
	_gs.set("last_port", port)
	_cal.call("from_dict", {"year": y, "month": m, "day": d})


## 此刻按数据表封着的港（只看战况 closed / besieged 与对己封港，不经 HeadingDraft——探针自己的口径）
func _sealed_now() -> Array:
	var out: Array = []
	for p in _gm.call("unlocked_ports"):
		var pid := str(p.get("id", ""))
		var st := str(_eco.call("war_status", pid))
		if st in ["closed", "besieged"] or bool(_gs.call("is_port_banned", pid)):
			out.append(pid)
	return out


## 能起锚的港（已解锁、depth>0）
func _origins() -> Array:
	var out: Array = []
	for p in _gm.call("unlocked_ports"):
		if int(p.get("depth", 0)) > 0:
			out.append(str(p.get("id", "")))
	return out


## 旧口径的池（改前 HeadingDraft.pool）：已解锁、depth>0、非起点
func _old_pool_ids(origin: String) -> Array:
	var out: Array = []
	for pid in _origins():
		if pid != origin:
			out.append(pid)
	return out


## 全部起点 × SALTS 手盐位里，发出 sealed 里的港几手；返回 [手数, 命中手数]
func _scan_hands(sealed: Array) -> Array:
	var hands := 0
	var hits := 0
	for origin in _origins():
		for salt in SALTS:
			var hand: PackedStringArray = _hd.call("deal", origin, salt)
			hands += 1
			for pid in hand:
				if str(pid) in sealed:
					hits += 1
					break
	return [hands, hits]


# ── 一、晨潮三向 ─────────────────────────────────────

func _sec_draft() -> void:
	var on_hands := 0
	var on_hits := 0
	var off_hits := 0
	var pool_same := true
	var pool_bad := ""
	for ym in SEALED_MONTHS:
		_stage(int(ym[0]), int(ym[1]))
		var sealed := _sealed_now()
		_expect(not sealed.is_empty(), "%d-%02d 数据表里封着港：%s" % [ym[0], ym[1], str(sealed)])
		CS.reset()
		var r: Array = _scan_hands(sealed)
		on_hands += int(r[0])
		on_hits += int(r[1])
		CS.set_on("port_blockade", false)
		off_hits += int(_scan_hands(sealed)[1])
		for origin in _origins():
			var ids: Array = []
			for p in _hd.call("pool", origin):
				ids.append(str(p.get("id", "")))
			if ids != _old_pool_ids(origin):
				pool_same = false
				pool_bad = "%d-%02d 起点 %s：%s" % [ym[0], ym[1], origin, str(ids)]
		CS.reset()
	_expect(on_hands > 0 and on_hits == 0,
		"开：七个封港 / 围城月 × 全部起点 × %d 手，%d 手里一手也不发封着的港（命中 %d）" % [SALTS, on_hands, on_hits])
	_expect(off_hits > 0, "关 = 回旧：同一批手牌里封着的港照旧发得出（%d 手）" % off_hits)
	_expect(pool_same, "关 = 回旧：HeadingDraft.pool 与旧口径（已解锁、depth>0、非起点）逐一相等%s" % (
		"" if pool_same else "（" + pool_bad + "）"))

	# 对己封港：1276-06 泉州连夜出港，泉州对你封港至 1276-11（port_bans 现成写法 GameState.ban_port）
	_stage(1276, 7, "zhangzhou")
	_gs.call("ban_port", "quanzhou", "1276-11")
	var r2: Array = _scan_hands(["quanzhou"])
	_expect(int(r2[1]) == 0, "对己封港：1276-07 泉州对你封港，%d 手里不发泉州（命中 %d）" % [int(r2[0]), int(r2[1])])
	_expect(str(_hd.call("seal_of", "quanzhou")) == "banned", "对己封港的封因是 banned（实得 %s）" % str(_hd.call("seal_of", "quanzhou")))
	CS.set_on("port_blockade", false)
	_expect(int(_scan_hands(["quanzhou"])[1]) > 0, "关 = 回旧：对己封港照旧发得出泉州")
	CS.reset()
	# 封因三样：封港 closed、围城 besieged；没封的空串
	_stage(1274, 11)
	_expect(str(_hd.call("seal_of", "hakata")) == "closed", "1274-11 博多唐房封因 closed")
	_stage(1276, 11)
	_expect(str(_hd.call("seal_of", "xinghua")) == "besieged" and str(_hd.call("seal_of", "guangzhou")) == "besieged",
		"1276-11 兴化、广州封因 besieged")
	_expect(str(_hd.call("seal_of", "penghu")) == "" and str(_hd.call("seal_of", "fuzhou")) == "",
		"1276-11 澎湖（无战况）、福州（已降元，牙行开着）不封")


# ── 二、海图上点 ─────────────────────────────────────

func _chart() -> Node:
	var sc = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	return sc


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _note(sc: Node) -> String:
	return str(sc.get("_latest_note"))


## 起锚港 origin 的手牌里没有、也没封的一港（点它该是「风不放」）
func _unoffered_open(sc: Node, origin: String) -> String:
	var hand: PackedStringArray = sc.get("_hand")
	for pid in _origins():
		if pid != origin and not (pid in hand) and str(_hd.call("seal_of", pid)) == "":
			return pid
	return ""


func _sec_click() -> void:
	_stage(1276, 11)
	var sc := _chart()
	await _frames(3)
	var hand: PackedStringArray = sc.get("_hand")
	_expect(not ("xinghua" in hand) and not ("guangzhou" in hand), "1276-11 泉州起锚：三向里没有兴化、广州（%s）" % str(hand))
	sc.call("_on_map_port_clicked", "xinghua")
	_expect(_note(sc).begins_with("港已封") and _note(sc).contains("兴化被围") and str(sc.get("selected_port")) == "",
		"点围城的兴化：「%s」，去处没选上" % _note(sc))
	var open_pid := _unoffered_open(sc, "quanzhou")
	if open_pid != "":
		sc.call("_on_map_port_clicked", open_pid)
		_expect(_note(sc) == "今日风不放这一向。", "点没封、只是风不放的 %s：照旧「今日风不放这一向。」（实得「%s」）" % [open_pid, _note(sc)])
	sc.call("_sync_map")
	var map: Node = sc.get("map")
	var want := _sealed_now()
	var got: Array = (map.get("sealed") as Array).duplicate()
	want.sort()
	got.sort()
	_expect(got == want, "图上打朱砂叉的港 = 此刻封着的港（%s）" % str(got))
	# 封港：1274-11 博多唐房
	_cal.call("from_dict", {"year": 1274, "month": 11, "day": 5})
	sc.call("_on_map_port_clicked", "hakata")
	_expect(_note(sc) == "港已封。博多唐房封港，海路不通。", "点封港的博多唐房：「%s」" % _note(sc))
	# 对己封港：1276-07 泉州
	_cal.call("from_dict", {"year": 1276, "month": 7, "day": 5})
	_gs.call("ban_port", "quanzhou", "1276-11")
	sc.set("origin_port", "zhangzhou")
	sc.call("_refresh_hand")
	sc.call("_on_map_port_clicked", "quanzhou")
	_expect(_note(sc) == "港已封。泉州对你封港，船进不去。" and str(sc.get("selected_port")) == "",
		"点对己封港的泉州：「%s」" % _note(sc))
	# 关态：不出「港已封」，图上不打叉
	CS.set_on("port_blockade", false)
	_cal.call("from_dict", {"year": 1276, "month": 11, "day": 5})
	sc.set("origin_port", "quanzhou")
	sc.call("_refresh_hand")
	var hand_off: PackedStringArray = sc.get("_hand")
	sc.call("_on_map_port_clicked", "xinghua")
	if "xinghua" in hand_off:
		_expect(str(sc.get("selected_port")) == "xinghua", "关：兴化在这一手里，点它照旧选上")
	else:
		_expect(_note(sc) == "今日风不放这一向。", "关：点兴化照旧「今日风不放这一向。」（实得「%s」）" % _note(sc))
	_expect((map.get("sealed") as Array).is_empty(), "关：图上不打叉")
	CS.reset()
	sc.queue_free()
	await _frames(2)


# ── 三、剧情放行 ─────────────────────────────────────

func _pool_ids(origin: String) -> Array:
	var ids: Array = []
	for p in _hd.call("pool", origin):
		ids.append(str(p.get("id", "")))
	return ids


func _sec_story() -> void:
	# 士人线守城
	_stage(1276, 11)
	_gs.call("set_flag", "renamed_wenlong")
	var ids := _pool_ids("quanzhou")
	_expect("xinghua" in ids and "xinghua_harbor" in ids and not ("guangzhou" in ids),
		"士人线 1276-11：兴化、兴化海口进三向的池，广州照旧拦（池 %s）" % str(ids))
	_stage(1276, 11)
	ids = _pool_ids("quanzhou")
	_expect(not ("xinghua" in ids) and not ("xinghua_harbor" in ids), "反向基：没改名的 1276-11 兴化两处都拦")
	# 涵江海口
	_stage(1277, 9)
	_gs.call("record_discovery", "nameless_shelter_bay")
	ids = _pool_ids("quanzhou")
	_expect("xinghua" in ids and "xinghua_harbor" in ids, "涵江：1277-09 复核过旧避风澳，兴化两处放行")
	_gs.call("set_flag", "ending_root_sea")
	_expect(not ("xinghua_harbor" in _pool_ids("quanzhou")), "涵江：已走过这条路（ending_root_sea），不再放行")
	_stage(1277, 10)
	_expect(not ("xinghua_harbor" in _pool_ids("quanzhou")), "涵江反向基：没复核旧避风澳，1277-10 照拦")
	# 在身委办
	_stage(1276, 10)
	_gs.set("contract", {"good_id": "tea", "qty": 10, "remaining": 10, "dest": "fuzhou", "from": "quanzhou"})
	ids = _pool_ids("quanzhou")
	_expect("fuzhou" in ids, "在身委办送福州：1276-10 福州被围照样放行（侧门交货）")
	_stage(1276, 10)
	_expect(not ("fuzhou" in _pool_ids("quanzhou")), "反向基：没有委办，1276-10 福州照拦")

	# 与 Main 卡判据逐月对账
	var consts: Dictionary = (load(MAIN_PATH) as GDScript).get_script_constant_map()
	var card_siege := str(consts.get("CARD_SIEGE_ENTER", ""))
	var card_hj := str(consts.get("CARD_HANJIANG", ""))
	_expect(card_siege != "" and card_hj != "", "Main 的入城 / 涵江卡 id 取得到（%s / %s）" % [card_siege, card_hj])
	var main: Node = (load(MAIN_PATH) as GDScript).new()
	var variants := [
		{"wenlong": true, "found": false, "root": false, "ended": false},
		{"wenlong": true, "found": false, "root": false, "ended": true},
		{"wenlong": false, "found": true, "root": false, "ended": false},
		{"wenlong": false, "found": true, "root": true, "ended": false},
		{"wenlong": false, "found": false, "root": false, "ended": false},
		{"wenlong": true, "found": true, "root": false, "ended": false},
	]
	var checked := 0
	var drift: Array = []
	var passes := 0
	for v in variants:
		for k in 17:
			var y: int = 1276 + int((7 + int(k)) / 12)
			var m: int = (7 + int(k)) % 12 + 1
			_stage(y, m)
			if bool(v["wenlong"]):
				_gs.call("set_flag", "renamed_wenlong")
			if bool(v["found"]):
				_gs.call("record_discovery", "nameless_shelter_bay")
			if bool(v["root"]):
				_gs.call("set_flag", "ending_root_sea")
			if bool(v["ended"]):
				_gs.set("ended", "忠肃")
			main.set("current_scene_id", "xinghua_harbor")
			var harbor_cards := _card_ids(main.call("_special_cards"))
			var want_harbor: bool = card_siege in harbor_cards or card_hj in harbor_cards
			main.set("current_scene_id", "xinghua")
			var city_cards := _card_ids(main.call("_special_cards"))
			var want_city: bool = bool(main.call("_siege_due")) or card_hj in city_cards
			var got_harbor := bool(_hd.call("story_pass", "xinghua_harbor"))
			var got_city := bool(_hd.call("story_pass", "xinghua"))
			checked += 2
			if got_harbor:
				passes += 1
			if got_harbor != want_harbor or got_city != want_city:
				drift.append("%d-%02d %s 海口 %s/%s 城 %s/%s" % [y, m, str(v), got_harbor, want_harbor, got_city, want_city])
	main.free()
	_expect(drift.is_empty() and passes > 0,
		"story_pass 与 Main 卡判据逐月相等：%d 格（放行 %d 格）%s" % [checked, passes, "" if drift.is_empty() else "；漂移 " + str(drift)])

	# 章目亲至港不放行、也不卡死
	_stage(1274, 11, "jeju")
	_gs.set("chapter", 2)
	var firsts_closed: Array = []
	for salt in SALTS:
		firsts_closed.append(str((_hd.call("deal", "jeju", salt) as PackedStringArray)[0]))
	_expect(not ("hakata" in firsts_closed) and not ("hakata" in _pool_ids("jeju")),
		"第二章要亲至博多唐房：1274-11 封港时不进三向（首席 %s）" % str(firsts_closed))
	_cal.call("from_dict", {"year": 1275, "month": 5, "day": 5})
	var firsts_open: Array = []
	for salt in SALTS:
		firsts_open.append(str((_hd.call("deal", "jeju", salt) as PackedStringArray)[0]))
	_expect(firsts_open.count("hakata") == SALTS, "1275-05 解封：八手首席都是博多唐房（%s）" % str(firsts_open))


func _card_ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		if c is Dictionary:
			out.append(str((c as Dictionary).get("id", "")))
	return out


# ── 四、闯封锁 ───────────────────────────────────────

const RUN_SEEDS := 2000
const GRAIN := 300


## 一条福船（中）60 人、舱里米粮 grain 件（进价 8）、水粮足
func _fleet_with_grain(fleet: Node, grain: int) -> void:
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	var cargo := {}
	if grain > 0:
		cargo["grain"] = {"qty": grain, "avg_cost": 8.0}
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": cargo, "durability": float(d.get("durability", 300)), "max_durability": float(d.get("durability", 300))}])
	fleet.set("morale", 70)
	fleet.set("water", 200)
	fleet.set("food", 200)


## 一个种子：掷第一发 blockade_patrol_met 撞上（met=true）或没撞上的
func _seed_for(met: bool) -> int:
	var voy: Node = root.get_node("Voyage")
	for k in range(1, 500):
		seed(k)
		if bool(voy.call("blockade_patrol_met")) == met:
			return k
	return -1


func _sec_run_odds() -> void:
	var voy: Node = root.get_node("Voyage")
	var hits := 0
	for k in range(1, RUN_SEEDS + 1):
		seed(k)
		if bool(voy.call("blockade_patrol_met")):
			hits += 1
	var rate := float(hits) / float(RUN_SEEDS)
	print("  QA_W53_P5_BLOCKADE_ODDS seeds=1..%d met=%d rate=%.3f" % [RUN_SEEDS, hits, rate])
	_expect(rate >= 0.37 and rate <= 0.43, "固定种子 1..%d 逐个掷：撞上哨船 %d 次（%.1f%%），落在四成上下" % [RUN_SEEDS, hits, rate * 100.0])
	var again := 0
	for k in range(1, RUN_SEEDS + 1):
		seed(k)
		if bool(voy.call("blockade_patrol_met")):
			again += 1
	_expect(again == hits, "同一串种子复掷一字不差（%d）" % again)


## 起一张 1276-11 泉州起锚的海图，舱里 grain 件米粮
func _run_chart(fleet: Node, grain: int, y := 1276, m := 11) -> Node:
	_stage(y, m)
	_fleet_with_grain(fleet, grain)
	return _chart()


func _sec_run_offer(fleet: Node) -> void:
	var sc := _run_chart(fleet, GRAIN)
	await _frames(3)
	var panel: Control = sc.get("event_panel")
	sc.call("_on_map_port_clicked", "xinghua")
	var title := str((sc.get("event_title") as Label).text)
	var body := str((sc.get("event_text") as RichTextLabel).text)
	var acts: Array = _action_texts(sc)
	_expect(panel.visible and title == "闯封锁・兴化" and acts == ["闯封锁", "不去了"],
		"有米粮点围城的兴化：挂「%s」一面，钮 %s" % [title, str(acts)])
	var unit_f := float(_eco.call("blockade_grain_unit", "xinghua"))
	var unit := int(round(unit_f))
	var cap := int(_eco.call("blockade_grain_cap", "xinghua"))
	_expect(body.contains("米粮 %d 件" % GRAIN) and body.contains("每件约 %d 钱" % unit) and body.contains("四成")
		and body.contains("海鹘一艘、快船两艘") and body.contains("折回泉州")
		and body.contains("这一趟城里只收得下 %d 件" % cap) and body.contains("约得 %d 钱" % int(round(unit_f * cap))),
		"那一面写清件数、收粮价、城里只收得下 %d 件、约得多少、四成撞上哨船与输了折回泉州" % cap)
	_expect(str(sc.get("selected_port")) == "" and str(sc.get("_run_port")) == "", "没按「闯封锁」之前去处不设")
	sc.call("_choose_run", "xinghua")
	var sail: Button = sc.get("sail_button")
	_expect(str(sc.get("_run_port")) == "xinghua" and str(sc.get("selected_port")) == "xinghua" and sail.text == "闯封锁"
		and not sail.disabled and not panel.visible,
		"按「闯封锁」：去处设成兴化、开航钮改写「%s」可按" % sail.text)
	var detail := str((sc.get("status_label") as RichTextLabel).text)
	_expect(detail.contains("闯封锁　四成撞上哨船"), "船况面板航段下写一行闯封锁")
	var hand: PackedStringArray = sc.get("_hand")
	if hand.size() > 0:
		sc.call("_select_heading", str(hand[0]))
		_expect(str(sc.get("_run_port")) == "" and sail.text == "就这一向", "改选三向里的一张牌：闯封锁作罢，钮回「就这一向」")
	sc.queue_free()
	await _frames(2)
	# 没米粮：只给港已封，带一句提示
	sc = _run_chart(fleet, 0)
	await _frames(3)
	sc.call("_on_map_port_clicked", "xinghua")
	_expect(not (sc.get("event_panel") as Control).visible and _note(sc) == "港已封。兴化被围，港外都是元军的哨船。舱里带上米粮，可以闯封锁。",
		"舱里没米粮点兴化：「%s」" % _note(sc))
	sc.queue_free()
	await _frames(2)


func _action_texts(sc: Node) -> Array:
	var out: Array = []
	for c in (sc.get("event_actions") as Node).get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


## 把海图摆到「闯封锁这一程刚到港外」：泉州 → port，余程 0
func _at_port_mouth(sc: Node, port: String) -> void:
	sc.call("_choose_run", port)
	sc.set("total_li", float(root.get_node("Voyage").call("distance_li", "quanzhou", port)))
	sc.set("remaining_li", 0.0)
	sc.set("days_elapsed", 4)
	sc.set("sailing", true)
	sc.set("voyage_started", true)
	root.get_node("Fleet").set("at_sea", true)


## 札记里含 needle 的那一条（新的在前）；没有返回 ""
func _log_has(sc: Node, needle: String) -> String:
	for line in (sc.get("_log_lines") as PackedStringArray):
		if str(line).contains(needle):
			return str(line)
	return ""


func _stop(sc: Node) -> void:
	sc.set("sailing", false)
	sc.set("_sail_serial", int(sc.get("_sail_serial")) + 1)
	sc.call("_cancel_marker")
	sc.queue_free()
	root.get_node("GameManager").set("pending_battle", {})


func _sec_run_paths(fleet: Node) -> void:
	var unit := float(_eco.call("blockade_grain_unit", "xinghua"))
	var cap := int(_eco.call("blockade_grain_cap", "xinghua"))
	var sold := mini(GRAIN, cap)
	var want_gold := int(round(unit * sold))
	var want_fame := mini(5, int(sold / 100))
	_expect(cap == 120 and sold < GRAIN, "兴化一趟只收 %d 件（= 兴化行情深浅 depth 120），舱里 %d 件收不完" % [cap, GRAIN])
	# 没撞上：照价卖粮、照常进港
	var sc := _run_chart(fleet, GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	var money0 := int(_gs.get("money"))
	var fame0 := int(_gs.get("fame"))
	seed(_seed_for(false))
	sc.call("_arrive")
	_expect(int(fleet.call("cargo_qty", "grain")) == GRAIN - sold and int(_gs.get("money")) - money0 == want_gold
		and int(_gs.get("fame")) - fame0 == want_fame,
		"没撞上：城里照围城米价收 %d 件、得 %d 钱（实得 %d），名声加 %d（实得 %d），余下 %d 件留在舱里" % [
			sold, want_gold, int(_gs.get("money")) - money0, want_fame, int(_gs.get("fame")) - fame0,
			int(fleet.call("cargo_qty", "grain"))])
	_expect(_log_has(sc, "城里按围城米价收粮：米粮 %d 件，得 %d 钱。余下 %d 件城里收不下，留在舱里。名声加 %d。" % [
			sold, want_gold, GRAIN - sold, want_fame]) != ""
		and _log_has(sc, "趁潮进了港") != "", "札记写「趁潮进了港」与收粮账（收多少、余下多少、名声）")
	_expect(str(_gs.get("last_port")) == "xinghua" and not bool(sc.get("sailing")) and str(sc.get("_run_port")) == ""
		and str((sc.get("event_title") as Label).text) == "到　港", "照常进港：抵兴化、出「到港」一面")
	_stop(sc)
	await _frames(2)

	# 撞上 → 迎战 → 真开 WorldMap 一场 → 收战赢：卖粮进港
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	seed(_seed_for(true))
	sc.call("_arrive")
	var ev: Dictionary = sc.get("pending_event")
	_expect(int(ev.get("kind", -1)) == int(root.get_node("Voyage").get("EventKind")["BLOCKADE"])
		and _action_texts(sc) == ["迎战", "掉头回航（米粮扣下）"] and bool(sc.get("sailing"))
		and str((sc.get("event_title") as Label).text) == "第 4 日・哨船拦港",
		"撞上：挂「哨船拦港」一面，钮 %s，还没进港" % str(_action_texts(sc)))
	money0 = int(_gs.get("money"))
	sc.call("_on_fight_blockade")
	var pb: Dictionary = root.get_node("GameManager").get("pending_battle")
	var foes: Array = pb.get("enemy", [])
	var foe_s := ""
	var yuan_all := not foes.is_empty()
	for e in foes:
		foe_s += "%s×%d " % [str(e.get("type", "")), int(e.get("count", 0))]
		yuan_all = yuan_all and str(e.get("sprite", "")) == "yuan_patrol"
	_expect(foe_s == "sea_falcon×1 pirate_boat×2 " and float(pb.get("power", 0.0)) >= 320.0 and float(pb.get("power", 0.0)) <= 760.0
		and str((pb.get("source", {}) as Dictionary).get("event", "")) == "blockade" and str(pb.get("sea_name", "")) == "兴化外海",
		"迎战走 pending_battle：%s战力 %.0f、%s、source=blockade" % [foe_s, float(pb.get("power", 0.0)), str(pb.get("sea_name", ""))])
	_expect(yuan_all, "拦港三条都挂 yuan_patrol（敌将按元军哨船档案打，快船不成海寇）")
	var wm: Node = null
	for c in sc.get_children():
		if c.has_signal("battle_finished"):
			wm = c
	_expect(wm != null, "海战场 WorldMap 真起来了（挂在海图下）")
	if wm != null:
		await _frames(2)
		wm.call("_battle_exit", "win", {})
		await _frames(2)
		_expect(int(fleet.call("cargo_qty", "grain")) == GRAIN - sold and _log_has(sc, "得 %d 钱" % want_gold) != ""
			and int(_gs.get("money")) - money0 >= want_gold and str(_gs.get("last_port")) == "xinghua",
			"收战赢：米粮照价卖得 %d 钱、进了兴化（钱另有赏，实增 %d）" % [want_gold, int(_gs.get("money")) - money0])
	_stop(sc)
	await _frames(2)

	# 输了 / 没逃成 / 逃了 / 掉头：米粮一件不剩、船折回泉州
	for how in ["lose", "flee_fail", "flee", "yield"]:
		sc = _run_chart(fleet, GRAIN)
		await _frames(3)
		_at_port_mouth(sc, "xinghua")
		money0 = int(_gs.get("money"))
		root.get_node("GameManager").set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "blockade"}})
		match how:
			"lose":
				sc.call("_on_battle_result", "lose", {"player_damage": 12.0})
			"flee_fail":
				sc.call("_on_battle_result", "flee", {"flee_ok": false, "player_damage": 0.0})
			"flee":
				sc.call("_on_battle_result", "flee", {"flee_ok": true, "shook_off": true, "player_damage": 0.0})
			_:
				root.get_node("GameManager").set("pending_battle", {})
				sc.call("_on_run_yield")
		var word: String = {"lose": "被哨船扣下", "flee_fail": "被哨船扣下", "flee": "抛下了海", "yield": "都扣下了"}[how]
		_expect(int(fleet.call("cargo_qty", "grain")) == 0 and int(_gs.get("money")) == money0
			and _log_has(sc, word) != "" and _log_has(sc, "只得折回泉州") != "",
			"%s：米粮一件不剩、不得钱，札记「%s」「只得折回泉州」" % [how, word])
		_expect(str(sc.get("origin_port")) == "xinghua" and str(sc.get("selected_port")) == "quanzhou"
			and bool(sc.get("sailing")) and float(sc.get("remaining_li")) > 0.0 and str(sc.get("_run_port")) == "",
			"%s：起讫对调，从兴化港外往泉州照常走回去（余程 %d 里）" % [how, int(float(sc.get("remaining_li")))])
		_stop(sc)
		await _frames(2)

	# 天黑两散：算闯过去
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	root.get_node("GameManager").set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "blockade"}})
	sc.call("_on_battle_result", "flee", {"flee_ok": true, "parted": true, "player_damage": 0.0})
	_expect(int(fleet.call("cargo_qty", "grain")) == GRAIN - sold and _log_has(sc, "得 %d 钱" % want_gold) != ""
		and str(_gs.get("last_port")) == "xinghua", "天黑两散：算闯过去，照价卖粮、进了兴化")
	_stop(sc)
	await _frames(2)

	# 全队沉了：不对调，沉船那条路送回起锚港
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	var ships: Array = fleet.get("ships")
	(ships[0] as Dictionary)["durability"] = 0.0
	root.get_node("GameManager").set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "blockade"}})
	sc.call("_on_battle_result", "lose", {"sunk": true, "player_damage": 300.0})
	_expect(str(sc.get("origin_port")) == "quanzhou" and _log_has(sc, "折回") == ""
		and str((sc.get("event_title") as Label).text) == "沉　没", "全队沉了：起讫不对调，走沉船那一面（回泉州）")
	_stop(sc)
	await _frames(2)

	# 到港时围已解（1276-12 兴化陷落）：不卖粮、照常进港
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	_at_port_mouth(sc, "xinghua")
	_cal.call("from_dict", {"year": 1276, "month": 12, "day": 2})
	money0 = int(_gs.get("money"))
	sc.call("_arrive")
	_expect(int(fleet.call("cargo_qty", "grain")) == GRAIN and int(_gs.get("money")) == money0
		and _log_has(sc, "已经不在围中") != "" and str(_gs.get("last_port")) == "xinghua",
		"到港时围已解：不掷哨船、不卖粮，米粮留在舱里，照常进港")
	_stop(sc)
	await _frames(2)

	# 这一程途中撞上海寇那一仗：不算拦港
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	sc.call("_choose_run", "xinghua")
	# 余程放长：甩脱后照常续航一日，别让这一日就到了港外（那是 _run_gate 的事）
	sc.set("sailing", true)
	sc.set("remaining_li", 5000.0)
	sc.set("total_li", 6000.0)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "source": {"scene": "SeaChart", "event": "pirate"}})
	sc.call("_on_battle_result", "flee", {"flee_ok": true, "shook_off": true, "player_damage": 0.0})
	# 甩脱后照常续航一日：米粮每天每船至多坏一件（待拍板 18），所以只认「没被扣、没抛」——至多少一件
	_expect(str(sc.get("_run_port")) == "xinghua" and int(fleet.call("cargo_qty", "grain")) >= GRAIN - 1
		and str(sc.get("origin_port")) == "quanzhou",
		"途中海寇那一仗甩脱：闯封锁照旧挂着、米粮没被扣（续航一日至多坏一件）、不折回（去处 %s、米粮 %d、起点 %s）" % [
			str(sc.get("_run_port")), int(fleet.call("cargo_qty", "grain")), str(sc.get("origin_port"))])
	_stop(sc)
	await _frames(2)


# ── 五、关态 ─────────────────────────────────────────

func _sec_run_off(fleet: Node) -> void:
	CS.set_on("blockade_run", false)
	var sc := _run_chart(fleet, GRAIN)
	await _frames(3)
	sc.call("_on_map_port_clicked", "xinghua")
	_expect(not (sc.get("event_panel") as Control).visible and _note(sc) == "港已封。兴化被围，港外都是元军的哨船。"
		and str(sc.get("_run_port")) == "", "blockade_run 关：有米粮点兴化也只给「%s」（20b 原句，不挂闯封锁）" % _note(sc))
	sc.call("_choose_run", "xinghua")
	_expect(str(sc.get("_run_port")) == "" and str(sc.get("selected_port")) == "", "blockade_run 关：硬调 _choose_run 也设不上去处")
	sc.queue_free()
	await _frames(2)
	CS.reset()
	CS.set_on("port_blockade", false)
	sc = _run_chart(fleet, GRAIN)
	await _frames(3)
	var hand: PackedStringArray = sc.get("_hand")
	sc.call("_on_map_port_clicked", "xinghua")
	_expect(not (sc.get("event_panel") as Control).visible and str(sc.get("_run_port")) == ""
		and (str(sc.get("selected_port")) == "xinghua" if "xinghua" in hand else _note(sc) == "今日风不放这一向。"),
		"port_blockade 关：兴化不封，照旧按三向走（%s），无从闯封锁" % ("在这一手里、点了就选上" if "xinghua" in hand else "风不放"))
	sc.queue_free()
	await _frames(2)
	CS.reset()
	# 剧情放行的港照常走，不算闯
	sc = _run_chart(fleet, GRAIN)
	_gs.call("set_flag", "renamed_wenlong")
	await _frames(3)
	sc.call("_refresh_hand")
	sc.call("_on_map_port_clicked", "xinghua")
	_expect(not bool(sc.call("_run_offerable", "xinghua")) and str(sc.get("_run_port")) == ""
		and not (sc.get("event_panel") as Control).visible, "士人线 1276-11 兴化放行：照常走，不挂闯封锁一面")
	sc.queue_free()
	await _frames(2)


# ── 六、期望净利 ─────────────────────────────────────

func _sec_run_ev() -> void:
	_stage(1276, 11)
	# 行情钉平年 1.0（开局各港有 ±15% 扰动），数才逐次一样
	var rates: Dictionary = _eco.get("rates")
	for pid in rates.keys():
		for gid in (rates[pid] as Dictionary).keys():
			rates[pid][gid] = 1.0
	var best_consumer := 0.0
	for pid in _origins():
		if str(_eco.call("get_role", pid, "grain")) == "consumer":
			best_consumer = maxf(best_consumer, float(_eco.call("blockade_grain_base", pid)))
	for pid in ["xinghua", "fuzhou"]:
		var u := float(_eco.call("blockade_grain_unit", pid))
		_expect(u < best_consumer, "%s（产米地）围城价每件 %.2f 钱，不及消费地平年米价 %.2f——闯进去不比寻常运粮划算" % [pid, u, best_consumer])
	var gz := float(_eco.call("blockade_grain_unit", "guangzhou"))
	_expect(gz <= best_consumer * 1.25, "广州围城价每件 %.2f 钱，不超消费地平年米价 %.2f 的 1.25 倍" % [gz, best_consumer])
	var has_factor := bool(_eco.has_method("war_price_factor"))
	var mul := float(_eco.call("war_price_factor", "xinghua", "grain")) if has_factor else 1.8
	_expect(is_equal_approx(float(_eco.call("blockade_grain_unit", "xinghua")), float(_eco.call("blockade_grain_base", "xinghua")) * mul)
		and is_equal_approx(float(_eco.call("blockade_grain_base", "xinghua")), 8.0 * 0.65),
		"收粮价 = 平年米价（兴化 8×0.65）× %s %.2f" % ["war_price_factor" if has_factor else "退回常量", mul])
	var caps_ok := true
	var caps_s := ""
	for pid in ["xinghua", "xinghua_harbor", "fuzhou", "guangzhou"]:
		var depth := int((_gm.call("get_port_by_id", pid) as Dictionary).get("depth", 0))
		var cap := int(_eco.call("blockade_grain_cap", pid))
		caps_ok = caps_ok and cap == depth and cap > 0
		caps_s += "%s %d　" % [pid, cap]
	_expect(caps_ok, "一趟收量封顶 = 本港 depth（%s）——舱再大也多卖不了" % caps_s.strip_edges())
	# 一趟账（城里收满一趟的量）：泉州买进（逐件涨价），① 平年运漳州（消费地）卖（逐件压价）；
	# ② 闯封锁：进港概率 P进 = 0.6 + 0.4 × P胜，进了按围城米价收，没进米粮全没——期望净利 = P进 × 收粮钱 − 买价
	for pid in ["xinghua", "fuzhou", "guangzhou"]:
		var qty := int(_eco.call("blockade_grain_cap", pid))
		var cost := int(_eco.call("estimate_buy_cost", "quanzhou", "grain", qty))
		var normal := int(_eco.call("estimate_sell_revenue", "zhangzhou", "grain", qty)) - cost
		var sale := int(round(float(_eco.call("blockade_grain_unit", pid)) * qty))
		var row := "  QA_W53_P5_BLOCKADE_EV 闯%s 收 %d 件：泉州买 %d 钱 / 城里收 %d 钱（平年运漳州卖 净 %+d）" % [pid, qty, cost, sale, normal]
		for pw in [0.3, 0.5, 0.7, 0.9, 1.0]:
			var p_in: float = 0.6 + 0.4 * float(pw)
			row += "　P胜%.1f 净 %+d" % [pw, int(round(p_in * sale)) - cost]
		print(row)
