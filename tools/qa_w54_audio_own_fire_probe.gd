extends SceneTree
## lane w54-audio：自家齐射不再被别船的炮声吞掉。一段钉一条，回退即红。
##   修前开炮节流按声样一把锁（combat_fire 90 毫秒）：敌船 / 护航刚放过一排，玩家这一排按下去、弹也飞出去了，
##   就是没有声（发声账 why=gap）。几艘船对射时一成多的齐射是哑的。
##   一、表：旗舰齐射另起一行 sea_fire_own，声样、音量与敌船那行 sea_fire 一样（combat_fire −7），节流认自己那把锁。
##   二、真起 WorldMap 海战（headless，探针钟钉死同一毫秒）：敌船真放一排（PirateShip._process_firing，摆成正横、射程内），
##       旗舰随即齐射（Ship._fire_broadside）——两声都响。
##   三、反过来：旗舰先放、敌船随后，也都响。
##   四、同一把锁照旧节流：90 毫秒内敌船那行连两声，第二声记 gap；旗舰那行连两声同样记 gap；过了 90 毫秒再响。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_own_fire_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_OWN_FIRE PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_OWN_FIRE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _fleet: Node = null
var _gm: Node = null
var _gs: Node = null
var _rec: Array = []
var _seed := 5520
## 探针钟：每段从这里起，免得上一段的时戳压着下一段
var _clock := 1_000_000


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


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
	_Switches.reset()
	print("== 一、表")
	_sec_table()
	print("== 二、敌船先放、旗舰随即齐射")
	await _sec_order(true)
	print("== 三、旗舰先放、敌船随后")
	await _sec_order(false)
	print("== 四、同一把锁照旧节流")
	await _sec_gap()
	_AUDIO.clock_ms = -1
	_Switches.reset()
	_report()


func _tick(ms: int) -> void:
	_clock += ms
	_AUDIO.clock_ms = _clock


func _sec_table() -> void:
	var own: Dictionary = _SFX.HOOKS.get(&"sea_fire_own", {})
	var foe: Dictionary = _SFX.HOOKS.get(&"sea_fire", {})
	_check(not own.is_empty() and str(own.get("layers")) == str(foe.get("layers")) and str(foe.get("layers")) == str([[&"combat_fire", -7.0]]),
		"旗舰齐射 sea_fire_own 与敌船开炮 sea_fire 同声同量（%s / %s）" % [own.get("layers"), foe.get("layers")])
	_check(StringName(own.get("gap_key", &"combat_fire")) != StringName(foe.get("gap_key", &"combat_fire")),
		"两行节流各认一把锁（旗舰 %s / 敌船 %s）" % [own.get("gap_key", "（缺省按声样）"), foe.get("gap_key", "（缺省按声样）")])


# ── 摆场 ───────────────────────────────────────────────

func _mk(t: String, nm: String, crew: int) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": dur, "max_durability": dur}


func _pb() -> Dictionary:
	return {"battle": true, "power": 300.0, "player_power": 1000.0, "enemy": [{"type": "pirate_boat", "count": 1}],
		"sea_name": "泉州外海", "sea_seed": 7_500_000 + _seed, "source": {"scene": "SeaChart", "event": "pirate"}}


func _stage() -> Node:
	for _try in 8:
		_fleet.set("ships", [_mk("fu_ship_medium", "旗舰", 60)])
		_fleet.set("morale", 60)
		_fleet.set("escorts_in_battle", [])
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
			for c in wm.get_children():
				if String(c.name).begins_with("PirateShip"):
					c.set("fire_timer", INF)
			return wm
		await process_frame
	return null


static func _enemy(wm: Node) -> Node2D:
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() and float(c.get("hull_hp")) > 0.0:
			return c as Node2D
	return null


## 敌船真放一排：船首朝北、旗舰摆在它正东 300 px（正横、射程内），两舷清装填、开炮计时归零，走它自己的 _process_firing
static func _enemy_volley(foe: Node2D, ship: Node2D) -> void:
	foe.rotation = 0.0
	ship.position = foe.position + Vector2(300, 0)
	var cap = foe.get("captain")
	if cap != null:
		cap.set("_side_reload", {-1: 0.0, 1: 0.0})
	foe.set("fire_timer", 0.0)
	var angle_diff := Vector2.UP.angle_to((ship.position - foe.position).normalized())
	foe.call("_process_firing", 0.016, angle_diff, foe.position.distance_to(ship.position))
	foe.set("fire_timer", INF)


## 发声账里 hook 的各笔 why（按先后）
static func _whys(hook: StringName) -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if StringName(r.get("hook", &"")) == hook:
			out.append(str(r.get("why", "?")))
	return out


func _sec_order(enemy_first: bool) -> void:
	var wm := await _stage()
	_check(wm != null, "海战起得来")
	if wm == null:
		return
	var ship: Node2D = wm.get("ship")
	var foe := _enemy(wm)
	_tick(10_000)
	_AUDIO.journal.clear()
	# 旧口径齐射（player_gunnery 关）：不看射界、保底一发，只验声
	_Switches.set_on("player_gunnery", false)
	if enemy_first:
		_enemy_volley(foe, ship)
		ship.call("_fire_broadside", 1)
	else:
		ship.call("_fire_broadside", 1)
		_enemy_volley(foe, ship)
	_Switches.reset()
	var foe_w := _whys(&"sea_fire")
	var own_w := _whys(&"sea_fire_own")
	var label := "敌船先、旗舰后" if enemy_first else "旗舰先、敌船后"
	_check(foe_w == [""], "%s（同一毫秒）：敌船那一排响了（%s）" % [label, str(foe_w)])
	_check(own_w == [""], "%s（同一毫秒）：旗舰那一排也响了，没被吞（%s）" % [label, str(own_w)])
	await _close(wm)


func _close(wm: Node) -> void:
	if is_instance_valid(wm) and wm.get("resolved") != true:
		wm.call("_battle_exit", "flee", {"flee_ok": true, "parted": true})
	for _i in 4:
		await process_frame


func _sec_gap() -> void:
	var host := Node.new()
	root.add_child(host)
	await process_frame
	_tick(10_000)
	_AUDIO.journal.clear()
	_SFX.play(host, &"sea_fire")
	_tick(40)
	_SFX.play(host, &"sea_fire")
	_tick(60)
	_SFX.play(host, &"sea_fire")
	_check(_whys(&"sea_fire") == ["", "gap", ""], "敌船那行：0 / 40 / 100 毫秒三声 → 响 / 节流 / 响（%s）" % str(_whys(&"sea_fire")))
	_tick(10_000)
	_AUDIO.journal.clear()
	_SFX.play(host, &"sea_fire_own")
	_tick(40)
	_SFX.play(host, &"sea_fire_own")
	_tick(60)
	_SFX.play(host, &"sea_fire_own")
	_check(_whys(&"sea_fire_own") == ["", "gap", ""], "旗舰那行：0 / 40 / 100 毫秒三声 → 响 / 节流 / 响（%s）" % str(_whys(&"sea_fire_own")))
	host.queue_free()
	await process_frame
