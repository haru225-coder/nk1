extends SceneTree
## lane w54-hunt 海战战损统计探针（headless，经 glock 跑；真 WorldMap 海战场）。
##   godot --headless --path . -s res://tools/qa_w54_hunt_roster_damage_probe.gd
## 口径（docs/combat_realism_verify.md「战损只按开战在册船」）：player_damage = 开战在册各船的总耐久 − 收战那一刻各船的总耐久，
## 夺来入列的船不算（既不抵战损，也不让战损变负）。
##   一、护航沉 + 夺下一艘、仗还接着打：收在 flee。开战在册三艘（旗舰 300 / 安济 240 / 通济 300 = 840），
##       安济沉（−240）、夺来的快船 260 入列——战损须恰 240。回退即红：按「名册前 N 艘」点船时，沉了的安济还占着一格、
##       夺来的船正好顶进空位，战损少算一整艘报 0；末一艘夺下即收战时夺来的船在战损拍定之后才入列，才碰巧对。
##   二、没有护航沉、只夺下一艘：战损照旧按自家那几艘算（夺来的船不进账）。
##   三、按船认不按序号（与收战时机无关的直测）：摆一场开战三艘，中途把「安济」摘出名册（护航沉了收战才摘，这里直接摘）、
##       夺来一艘排在尾——战损须只认还在册的那两艘。回退即红：按「前 3 艘」点，摘掉一艘后快船顶进空位，战损反成负数。
## 判词：末行 QA_W54_HUNT_ROSTER_DAMAGE PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_HUNT_ROSTER_DAMAGE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _fleet: Node = null
var _gm: Node = null
var _gs: Node = null
var _rec: Array = []
var _seed := 5400
var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	_gs = root.get_node("GameState")
	print("== 一、护航沉 + 夺下一艘、仗接着打：战损恰是沉掉那一艘")
	await _sec_sink_and_prize()
	print("== 二、只夺下一艘：夺来的船不进战损账")
	await _sec_prize_only()
	print("== 三、按船认不按序号：中途摘掉一艘、夺来一艘排在尾")
	await _sec_by_identity()
	_report()


func _ship(nm: String, t: String, crew: int, dur: float) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": dur, "max_durability": float(d.get("durability", 300))}


static func _enemies(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() and float(c.get("hull_hp")) > 0.0:
			out.append(c)
	return out


static func _escort(wm: Node, nm: String) -> Node:
	for c in wm.get_children():
		if String(c.name).begins_with("EscortShip") and str(c.get("ship_name")) == nm:
			return c
	return null


## 真起一场：舰队三艘、对面两艘海寇；敌船不开炮（只验记账）。撞上大风两散的种子（开战当帧收战）换种子重起
func _stage(enemies: int) -> Node:
	for _try in 8:
		_fleet.set("ships", [_ship("旗舰", "fu_ship_medium", 60, 300.0), _ship("安济", "keel_boat", 30, 240.0),
			_ship("通济", "fu_ship_medium", 40, 300.0)])
		_fleet.set("morale", 60)
		_fleet.set("escorts_in_battle", [])
		_gs.set("martial", 50)
		_seed += 1
		seed(_seed)
		_gm.set("pending_battle", {"battle": true, "power": 400.0, "player_power": 1000.0,
			"enemy": [{"type": "pirate_boat", "count": enemies}], "sea_name": "泉州外海", "sea_seed": 7_500_000 + _seed,
			"source": {"scene": "SeaChart", "event": "pirate"}})
		_rec = []
		var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
		wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: _rec.append([o, d.duplicate(true)]))
		root.add_child(wm)
		await process_frame
		await process_frame
		if _rec.is_empty():
			for c in wm.get_children():
				if String(c.name).begins_with("PirateShip") or String(c.name).begins_with("EscortShip"):
					c.set("fire_timer", INF)
			return wm
		wm.queue_free()
		await process_frame
	return null


func _sec_sink_and_prize() -> void:
	var wm: Node = await _stage(2)
	_check(wm != null, "海战起得来（WorldMap.tscn，非大风两散的种子）")
	if wm == null:
		return
	var start := float(wm.get("combat_start_durability"))
	_check(is_equal_approx(start, 840.0), "开战在册三艘合计耐久 840（%0.0f）" % start)
	var foes := _enemies(wm)
	_check(foes.size() == 2, "对面两条海寇快船（%d）" % foes.size())
	var keep := _escort(wm, "安济")
	_check(keep != null, "护航「安济」上阵")
	if keep == null or foes.size() < 2:
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	keep.call("take_damage", 99999.0)
	for _i in 6:
		await physics_frame
	# 夺下一艘（入船籍排在名册尾）；对面还剩一艘，仗不因此收
	var taken := str(wm.call("escort_prize", foes[0]))
	_check(taken != "" and (_fleet.get("ships") as Array).size() == 4,
		"夺下「%s」入船籍（在册 %d 艘）" % [taken, (_fleet.get("ships") as Array).size()])
	_check(_rec.is_empty(), "夺下一艘、对面还有一艘：仗接着打（没收战）")
	if is_instance_valid(wm):
		wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	_check(not _rec.is_empty(), "收战（flee）")
	if _rec.is_empty():
		return
	var data: Dictionary = _rec[0][1]
	var dmg := float(data.get("player_damage", -1.0))
	_check(is_equal_approx(dmg, 240.0),
		"战损 = 沉掉的「安济」整船 240；夺来的「%s」整船 260 不抵、不顶位（得 %.0f）" % [taken, dmg])


func _sec_prize_only() -> void:
	var wm: Node = await _stage(2)
	_check(wm != null, "第二局海战起得来")
	if wm == null:
		return
	var foes := _enemies(wm)
	if foes.size() < 2:
		_check(false, "第二局对面两条在场（%d）" % foes.size())
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	var taken := str(wm.call("escort_prize", foes[0]))
	var own := 0.0
	for s in _fleet.get("ships"):
		own += float((s as Dictionary).get("durability", 0))
	var start := float(wm.get("combat_start_durability"))
	if is_instance_valid(wm):
		wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	_check(not _rec.is_empty(), "第二局收战（夺下「%s」后照打）" % taken)
	if _rec.is_empty():
		return
	var data: Dictionary = _rec[0][1]
	var dmg := float(data.get("player_damage", -1.0))
	# 只少了一艘夺来的船？不：夺来的船仍在册，自家三艘一点没损——战损应是 0，不是负 260
	_check(is_equal_approx(dmg, 0.0) and own >= start - 0.01,
		"只夺下一艘、自家没挨打：战损 0（得 %.0f；开战 %.0f / 此刻含夺来那艘 %.0f）" % [dmg, start, own])

# ── 三、按船认不按序号 ─────────────────────────────────

func _sec_by_identity() -> void:
	var wm: Node = await _stage(2)
	_check(wm != null, "第三局海战起得来")
	if wm == null:
		return
	var foes := _enemies(wm)
	if foes.size() < 2:
		_check(false, "第三局对面两条在场（%d）" % foes.size())
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	var ships: Array = _fleet.get("ships")
	var anji: Dictionary = ships[1]
	# 夺来一艘排在名册尾，再把「安济」摘出名册（等价于护航沉了收战摘船那一刻的名册）
	var taken := str(wm.call("escort_prize", foes[0]))
	ships.remove_at(1)
	_check(_fleet.get("ships").size() == 3 and str((_fleet.get("ships") as Array)[2].get("name", "")) == taken,
		"名册：旗舰、通济、夺来的「%s」（安济已摘）" % taken)
	var want := 300.0 + 300.0
	var got := float(wm.call("_roster_durability"))
	_check(is_equal_approx(got, want),
		"开战在册且还在名册的只有旗舰与通济：现总耐久 %.0f（应 %.0f；安济 240 已不认、夺来的「%s」260 不算）" % [got, want, taken])
	_check(not ships.has(anji), "「安济」那一格确已摘出名册")
	if is_instance_valid(wm):
		wm.call("_battle_exit", "flee", {"flee_ok": true})
	await process_frame
	if not _rec.is_empty():
		var dmg := float((_rec[0][1] as Dictionary).get("player_damage", 999.0))
		_check(is_equal_approx(dmg, 240.0),
			"收战的战损 = 840 − 600 = 240（沉掉的安济那一份；得 %.0f）" % dmg)
