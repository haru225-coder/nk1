extends SceneTree
## lane w54-audio：逃没逃掉不再放撤离的风声。一段钉一条，回退即红。
##   修前 SfxCues.result_hook / 原 AudioHooks.combat_result 只看 outcome：flee 一律放 combat_flee 风声——B 键弃战掷输、
##   我方溃逃没跑掉（flee_ok 假）时海图照败局记（船挨一顿、舱货被夺、札记「未能甩脱。被追上跳帮，货舱被夺。」），
##   耳朵里听到的却是「甩脱了」。
##   一、认挂点：flee_ok 假 / 缺 → sea_lose（与 SeaChart._on_battle_result 同读 data.get("flee_ok", false)）；
##       flee_ok 真的甩脱 / 两散 / 大风两散 / 崖山冲出照放 sea_flee；胜 sea_win、败 sea_lose 不动。
##   二、真按 B 键（真起 WorldMap 海战，headless）：追船贴在 400 px 以内、按种子让甩脱骰掷输——收战记 sea_lose、不记 sea_flee；
##       同一份战果喂真海图 _on_battle_result，札记写「未能甩脱」（声与字对得上）。
##   三、甩脱照旧：追船都在 escape_bu 外，B 键必脱——收战记 sea_flee，海图札记不写「未能甩脱」。
##   四、我方溃逃没跑掉（士气簿裁决 flee、flee_ok 假，WorldMap._on_morale_verdict）同样记 sea_lose。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_flee_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_FLEE PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_FLEE"
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
var _seed := 5480
## 探针钟（AudioHooks.clock_ms）：每量一样往后拨十秒，上一样的声放完、声部空出来
var _clock := 3_000_000


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
	print("== 一、认挂点")
	_sec_pick()
	print("== 二、真按 B 键、甩脱骰掷输")
	await _sec_caught()
	print("== 三、甩脱照旧放风声")
	await _sec_shook()
	print("== 四、我方溃逃没跑掉")
	await _sec_rout()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


## 拨钟、清账：下面这一下要的声单独记
func _fresh() -> void:
	_clock += 10_000
	_AUDIO.clock_ms = _clock
	_AUDIO.journal.clear()


func _sec_pick() -> void:
	var rows := [
		["flee", {"flee_ok": false, "player_damage": 12.0}, &"sea_lose", "B 键弃战掷输（flee_ok 假）"],
		["flee", {}, &"sea_lose", "flee 没带 flee_ok（海图照 false 读）"],
		["flee", {"flee_ok": true, "shook_off": true}, &"sea_flee", "甩脱"],
		["flee", {"flee_ok": true, "parted": true}, &"sea_flee", "限时两散"],
		["flee", {"flee_ok": true, "parted": true, "gale": true}, &"sea_flee", "大风两散"],
		["flee", {"flee_ok": true, "shook_off": true, "yashan_out": true}, &"sea_flee", "崖山冲出港嘴"],
		["win", {}, &"sea_win", "胜"],
		["lose", {"sunk": true}, &"sea_lose", "旗舰沉"],
		["lose", {"overrun": true}, &"sea_lose", "失守"],
	]
	for r in rows:
		var got: StringName = _SFX.result_hook(r[0], r[1])
		_check(got == r[2], "%s：%s %s → %s（实得 %s）" % [r[3], r[0], str(r[1]), r[2], got])


# ── 摆场 ───────────────────────────────────────────────

func _mk(t: String, nm: String, crew: int) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1,
		"cargo": {"tea": {"qty": 6, "avg_cost": 20.0}}, "durability": dur, "max_durability": dur}


func _pb() -> Dictionary:
	return {"battle": true, "power": 300.0, "player_power": 1000.0, "enemy": [{"type": "pirate_boat", "count": 1}],
		"sea_name": "泉州外海", "sea_seed": 7_400_000 + _seed, "source": {"scene": "SeaChart", "event": "pirate"}}


## 真起一场海战（撞上大风两散的种子换下一个）；谁都不开炮
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


static func _hooks() -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if str(r.get("why", "?")) == "":
			out.append(StringName(r.get("hook", &"")))
	return out


static func _press_b(wm: Node) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.pressed = true
	wm.call("_unhandled_input", ev)


## 收战后起一张真海图走 _on_battle_result，回札记全文
func _chart_log(outcome: String, data: Dictionary) -> String:
	var sc: Node = (load("res://scenes/SeaChart.tscn") as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	sc.set("remaining_li", 50.0)
	sc.set("selected_port", "quanzhou")
	_gm.set("pending_battle", _pb())
	sc.call("_on_battle_result", outcome, data)
	await process_frame
	var lbl = sc.get("log_label")
	var txt := str(lbl.get("text")) if lbl != null else ""
	sc.queue_free()
	await process_frame
	return txt


# ── 二、掷输 ───────────────────────────────────────────

func _sec_caught() -> void:
	var wm := await _stage()
	_check(wm != null, "海战起得来")
	if wm == null:
		return
	var ship: Node2D = wm.get("ship")
	var foe := _enemy(wm)
	foe.position = ship.position + Vector2(300, 0)  # 贴在 FLEE_NEAR（400 px）以内：甩脱只看船速
	var chance := float(wm.call("_flee_chance"))
	_check(chance < 1.0, "追船贴近，甩脱机会 %.2f < 1（要掷骰）" % chance)
	# 找一个让甩脱骰掷输的种子：同种子 randf 先看一眼，再从头播一次让 B 键那一掷落在同一个数上
	var s := 1
	while s < 500:
		seed(s)
		if randf() >= chance:
			break
		s += 1
	seed(s)
	_fresh()
	_press_b(wm)
	for _i in 4:
		await process_frame
	_check(_rec.size() == 1 and _rec[0][0] == "flee" and _rec[0][1].get("flee_ok") == false,
		"B 键弃战掷输：flee、flee_ok 假（%s）" % str(_rec))
	var hooks := _hooks()
	_check(hooks.has(&"sea_lose") and not hooks.has(&"sea_flee"),
		"收战放败局那一声 sea_lose、不放撤离风声 sea_flee（发声账 %s）" % str(hooks))
	if _rec.size() == 1:
		var txt := await _chart_log(_rec[0][0], _rec[0][1])
		_check(txt.contains("未能甩脱"), "同一份战果在海图上照败局记：札记写「未能甩脱」（声与字对得上）")


# ── 三、甩脱 ───────────────────────────────────────────

func _sec_shook() -> void:
	var wm := await _stage()
	_check(wm != null, "海战起得来")
	if wm == null:
		return
	var ship: Node2D = wm.get("ship")
	var foe := _enemy(wm)
	foe.position = ship.position + Vector2(float(wm.get("_escape_px")) + 400.0, 0)  # 追船在 escape_bu 外：必脱、不掷骰
	_check(float(wm.call("_flee_chance")) >= 1.0, "追船在 escape_bu 外，甩脱机会 1")
	_fresh()
	_press_b(wm)
	for _i in 4:
		await process_frame
	_check(_rec.size() == 1 and _rec[0][1].get("flee_ok") == true, "B 键甩脱：flee、flee_ok 真（%s）" % str(_rec))
	var hooks := _hooks()
	_check(hooks.has(&"sea_flee") and not hooks.has(&"sea_lose"), "甩脱照放撤离风声 sea_flee（发声账 %s）" % str(hooks))
	if _rec.size() == 1:
		var txt := await _chart_log(_rec[0][0], _rec[0][1])
		_check(not txt.contains("未能甩脱"), "海图札记不写「未能甩脱」")


# ── 四、溃逃没跑掉 ─────────────────────────────────────

func _sec_rout() -> void:
	var wm := await _stage()
	_check(wm != null, "海战起得来")
	if wm == null:
		return
	_fresh()
	wm.call("_on_morale_verdict", "flee", {"flee_ok": false, "routed": true})
	for _i in 4:
		await process_frame
	var hooks := _hooks()
	_check(hooks.has(&"sea_lose") and not hooks.has(&"sea_flee"),
		"士气簿裁决我方溃逃、没跑掉：放 sea_lose（发声账 %s）" % str(hooks))
