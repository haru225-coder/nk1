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

