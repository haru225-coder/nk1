extends SceneTree
## lane w54-hunt 海战收尾记账探针（headless，经 glock 跑；真 WorldMap 海战 → 真 SeaChart 收战与战后收拾 → 真存读档）。
##   godot --headless --path . -s res://tools/qa_w54_hunt_battle_ledger_probe.gd
## 打法：船队三艘（旗舰 + 两艘护航，各带舱货）在泉州外海迎两条海寇快船，敌船不开炮（只验收尾记账）。
##   一、士气收场受降：两艘敌船都喊话劝降得手、竖了降幡、没接舷——船还浮在海上、不进船籍。
##       战后收拾卡不挂「押船」行（没有可押的船）；把卡上每一行都拣「放」的那一项（随它漂走 / 不救 / 放走 / 收队）收拾停当，
##       自家三艘、舱货一件不少，钱只多了受降的赏。
##       回退即红：押船行把这两艘没接舷的降船也算成「已在船籍的夺船」，随它漂走 / 人手不够时从船籍尾摘船——
##       摘掉的是自家的护航船连舱货（安济的茶、通济的米随船没了）。
##   二、一艘护航跳帮夺下（EscortWing 得手、入船籍）+ 一艘降了没接舷：押船行只算 1 艘；随它漂走只摘夺来的那一艘，
##       自家三艘照在；另一局分人押船，夺来的那艘留在船籍、自家三艘照在。
##   三、存读档往返：收拾停当后存档位 81 真存真读，船籍逐艘逐字段相等（名、船式、耐久、人手、帆甲、舱货）。
## 判词：末行 QA_W54_HUNT_BATTLE_LEDGER PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_HUNT_BATTLE_LEDGER"
const SLOT := 81
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

## AfterAction / SeaChart 直读 Fleet / GameState 等 autoload：-s 探针的 preload 在 autoload 挂上之前编，会编不过——_run 里再 load
var _AA = null
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


## _run 被脚本错半路掐断时收尾不会被调到——回到这里就地判红收尾
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
	_AA = load("res://scripts/combat/AfterAction.gd")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	_gs = root.get_node("GameState")
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	print("== 一、士气收场受降：降船没接舷、不进船籍，收拾停当后自家船一艘不少")
	await _sec_struck_afloat()
	print("== 二、一艘护航夺下 + 一艘降了没接舷：押船只算夺下的那一艘")
	await _sec_mixed("drift")
	await _sec_mixed("keep")
	_Switches.reset()
	_report()


# ── 摆场 ───────────────────────────────────────────────

func _mk(t: String, nm: String, crew: int, cargo := {}) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": cargo.duplicate(true),
		"durability": dur, "max_durability": dur}


## 自家三艘：旗舰（生丝 4）、安济（茶 5）、通济（米 10）
func _home_fleet() -> Array:
	return [
		_mk("fu_ship_medium", "旗舰", 60, {"raw_silk": {"qty": 4, "avg_cost": 90.0}}),
		_mk("keel_boat", "安济", 30, {"tea": {"qty": 5, "avg_cost": 20.0}}),
		_mk("fu_ship_medium", "通济", 40, {"grain": {"qty": 10, "avg_cost": 8.0}}),
	]


func _pb() -> Dictionary:
	return {"battle": true, "power": 400.0, "player_power": 1000.0, "enemy": [{"type": "pirate_boat", "count": 2}],
		"sea_name": "泉州外海", "sea_seed": 7_100_000 + _seed, "source": {"scene": "SeaChart", "event": "pirate"}}


## 真起一场海战：Fleet 换成 ships、pending_battle 写海寇两艘，挂 WorldMap（士气簿照接——本探针验的就是士气收场那一路）。
## 撞上「大风两散」的种子（WorldMap._ready 当帧收战）换下一个种子重起。
func _stage(ships: Array) -> Node:
	for _try in 8:
		_fleet.set("ships", ships)
		_fleet.set("morale", 60)
		_fleet.set("escorts_in_battle", [])
		_gs.set("martial", 50)
		_gs.set("money", 1000)
		_gs.set("berth_index", 0)
		_seed += 1
		seed(_seed)
		_gm.set("pending_battle", _pb())
		_rec = []
		var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
		wm.battle_finished.connect(func(o: String, data: Dictionary) -> void: _rec.append([o, data.duplicate(true)]))
		root.add_child(wm)
		await process_frame
		await process_frame
		if _rec.is_empty():
			return wm
		await process_frame
		ships = _home_fleet()
	return null


## 谁都不开炮（fire_timer = INF；船照常机动）：本探针只验收尾记账
func _freeze(wm: Node) -> void:
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") or String(c.name).begins_with("EscortShip"):
			c.set("fire_timer", INF)


static func _enemies(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() and float(c.get("hull_hp")) > 0.0:
			out.append(c)
	return out


func _await_finish(max_frames: int) -> void:
	for _i in max_frames:
		if not _rec.is_empty():
			return
		await physics_frame


## 收战后起一张真海图，走 _on_battle_result（札记、赏钱、战后收拾卡的判据），再把卡上每一行按 pick 拣好、
## 走 _on_after_action_done（headless 下卡不挂，探针替玩家按「收拾停当」——落账走的是同一支）
func _settle_on_chart(outcome: String, data: Dictionary, pick: Callable) -> Dictionary:
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	# 收尾的 _after_combat 见 remaining_li ≤ 0 当是到港（到港换场景）：留一段航程，船又没在走，_sail_next_day 当即返回
	sc.set("remaining_li", 50.0)
	sc.set("selected_port", "quanzhou")
	_gm.set("pending_battle", _pb())
	var money0 := int(_gs.get("money"))
	sc.call("_on_battle_result", outcome, data)
	var money_spoil := int(_gs.get("money")) - money0
	var choices: Array = _AA.choices_for(outcome, data)
	var chosen := {}
	for row in choices:
		chosen[str(row.get("key", ""))] = str(pick.call(row))
	sc.call("_on_after_action_done", chosen, choices, data)
	await process_frame
	var note := str(sc.get("_latest_note"))
	sc.queue_free()
	await process_frame
	return {"choices": choices, "spoil": money_spoil, "note": note}


## 「放」的那一项：押船随它漂走、救人不救、俘虏放走、追击收队——都是不往船队里添东西的那一项
static func _pick_let_go(row: Dictionary) -> String:
	match str(row.get("key", "")):
		"prize":
			return "drift"
		"rescue":
			return "leave"
		"captives":
			return "free"
		"pursue":
			return "hold"
	for o in row.get("options", []):
		if bool((o as Dictionary).get("default", false)):
			return str((o as Dictionary).get("id", ""))
	return ""


static func _pick_keep(row: Dictionary) -> String:
	if str(row.get("key", "")) == "prize":
		return "keep"
	return _pick_let_go(row)


func _names() -> Array:
	var out: Array = []
	for s in _fleet.get("ships"):
		out.append(str((s as Dictionary).get("name", "")))
	return out


func _qty(gid: String) -> int:
	return int(_fleet.call("cargo_qty", gid))


static func _prize_row(choices: Array) -> Dictionary:
	for row in choices:
		if str((row as Dictionary).get("key", "")) == "prize":
			return row
	return {}


static func _fates(data: Dictionary, fate: String) -> int:
	var n := 0
	for e in data.get("fates", []):
		if e is Dictionary and str(e.get("fate", "")) == fate:
			n += maxi(1, int(e.get("count", 1)))
	return n


# ── 一、士气收场受降 ──────────────────────────────────

func _sec_struck_afloat() -> void:
	_Switches.reset()
	var wm: Node = await _stage(_home_fleet())
	_check(wm != null, "海战起得来（WorldMap.tscn，非大风两散的种子）")
	if wm == null:
		return
	_freeze(wm)
	var foes := _enemies(wm)
	_check(foes.size() == 2, "对面两条海寇快船在场（%d）" % foes.size())
	for f in foes:
		f.call("strike_colours", "喊话劝降，降幡")
	await _await_finish(600)
	_check(not _rec.is_empty(), "两艘都降了：士气收场（battle_finished 在 600 物理帧内发出）")
	if _rec.is_empty():
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	var outcome := str(_rec[0][0])
	var data: Dictionary = _rec[0][1]
	_check(outcome == "win" and str(data.get("morale_verdict", "")) == "enemy_struck",
		"收战判受降（outcome=%s，morale_verdict=%s）" % [outcome, str(data.get("morale_verdict", ""))])
	_check(_fates(data, "struck") == 2 and _fates(data, "boarded") == 0,
		"下场明细：降 2、夺 0（%s）" % JSON.stringify(data.get("fates", [])))
	_check(_names() == ["旗舰", "安济", "通济"], "降船没接舷、不进船籍：船队仍是自家三艘（%s）" % str(_names()))
	var got := await _settle_on_chart(outcome, data, _pick_let_go)
	var choices: Array = got["choices"]
	_check(_prize_row(choices).is_empty(),
		"战后收拾卡不挂「押船」行——没接舷的降船不在船籍、无船可押（挂的行：%s）" % str(choices.map(func(r): return r.get("label", ""))))
	_check(_names() == ["旗舰", "安济", "通济"],
		"每一行都拣「放」收拾停当：自家三艘一艘不少（%s）" % str(_names()))
	_check(_qty("raw_silk") == 4 and _qty("tea") == 5 and _qty("grain") == 10,
		"舱货一件不少（生丝 %d・茶 %d・米 %d，应 4・5・10）" % [_qty("raw_silk"), _qty("tea"), _qty("grain")])
	_check(int(got["spoil"]) > 0, "受降照赏（钱匣 +%d）" % int(got["spoil"]))
	await _roundtrip("一")


# ── 二、一艘夺下 + 一艘降了没接舷 ───────────────────────

func _sec_mixed(how: String) -> void:
	_Switches.reset()
	var wm: Node = await _stage(_home_fleet())
	_check(wm != null, "（%s）海战起得来" % how)
	if wm == null:
		return
	_freeze(wm)
	var foes := _enemies(wm)
	if foes.size() < 2:
		_check(false, "（%s）对面两条在场（%d）" % [how, foes.size()])
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	# 护航跳帮得手那一支（WorldMap.escort_prize：入船籍、记「夺」、敌船离场）
	var taken := str(wm.call("escort_prize", foes[0]))
	await process_frame
	_check(_names().size() == 4 and _names()[3] == taken,
		"（%s）护航夺下「%s」入船籍、排在名册尾（%s）" % [how, taken, str(_names())])
	foes[1].call("strike_colours", "喊话劝降，降幡")
	await _await_finish(600)
	_check(not _rec.is_empty() and str(_rec[0][0]) == "win", "（%s）余下那艘降了：受降收战" % how)
	if _rec.is_empty():
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
		return
	var data: Dictionary = _rec[0][1]
	_check(_fates(data, "boarded") == 1 and _fates(data, "struck") == 1,
		"（%s）下场明细：夺 1、降 1（%s）" % [how, JSON.stringify(data.get("fates", []))])
	var got := await _settle_on_chart("win", data, _pick_let_go if how == "drift" else _pick_keep)
	var row := _prize_row(got["choices"])
	_check(str(row.get("label", "")).begins_with("押船（夺来 / 受降 1 艘"),
		"（%s）押船行只算真在船籍的那 1 艘（「%s」）" % [how, str(row.get("label", ""))])
	if how == "drift":
		_check(_names() == ["旗舰", "安济", "通济"],
			"随它漂走：只摘夺来的「%s」，自家三艘照在（%s）" % [taken, str(_names())])
	else:
		_check(_names() == ["旗舰", "安济", "通济", taken],
			"分人押船：夺来的「%s」留在船籍，自家三艘照在（%s）" % [taken, str(_names())])
	_check(_qty("raw_silk") == 4 and _qty("tea") == 5 and _qty("grain") == 10,
		"（%s）自家舱货一件不少（生丝 %d・茶 %d・米 %d）" % [how, _qty("raw_silk"), _qty("tea"), _qty("grain")])
	await _roundtrip("二（%s）" % how)


# ── 三、存读档往返 ─────────────────────────────────────

## 收拾停当后真存真读（存档位 81），船籍逐艘逐字段相等；坞位还指着船籍里的一艘
func _roundtrip(sec: String) -> void:
	var sl: Node = root.get_node("SaveLoad")
	var want: Array = (_fleet.get("ships") as Array).duplicate(true)
	var berth := int(_gs.get("berth_index"))
	_check(berth >= 0 and berth < want.size(), "%s：坞位 %d 指着船籍里的一艘（共 %d 艘）" % [sec, berth, want.size()])
	var saved: bool = sl.call("save_game", SLOT, "quanzhou")
	_fleet.set("ships", [_mk("sampan", "占位", 5)])
	var loaded: bool = sl.call("load_game", SLOT)
	var got: Array = _fleet.get("ships")
	var same := saved and loaded and got.size() == want.size()
	if same:
		for i in want.size():
			if not _ship_eq(want[i], got[i]):
				same = false
				print("    ✗ ships[%d] 存 %s 读 %s" % [i, JSON.stringify(want[i]), JSON.stringify(got[i])])
	_check(same, "%s：存档位 %d 真存真读，船籍 %d 艘逐字段相等（存 %s / 读 %s）" % [sec, SLOT, want.size(), saved, loaded])
	for ext in ["", ".bak", ".tmp"]:
		var p := str(sl.get("SAVE_DIR")) + "save_%d.json%s" % [SLOT, ext]
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## 一艘船逐字段比：数字按数值比（JSON 读回整数成浮点），舱货逐货比件数与均价
static func _ship_eq(a: Dictionary, b: Dictionary) -> bool:
	for k in ["type", "name"]:
		if str(a.get(k, "")) != str(b.get(k, "")):
			return false
	for k in ["durability", "max_durability", "crew", "sail_level", "armor_level"]:
		if not is_equal_approx(float(a.get(k, -1)), float(b.get(k, -2))):
			return false
	var ca: Dictionary = a.get("cargo", {})
	var cb: Dictionary = b.get("cargo", {})
	if ca.size() != cb.size():
		return false
	for gid in ca:
		if not cb.has(gid):
			return false
		if int((ca[gid] as Dictionary).get("qty", -1)) != int((cb[gid] as Dictionary).get("qty", -2)) \
				or not is_equal_approx(float((ca[gid] as Dictionary).get("avg_cost", -1)), float((cb[gid] as Dictionary).get("avg_cost", -2))):
			return false
	return true
