extends SceneTree
## lane w54-audio：音效挂点表（scripts/audio/SfxCues.gd）专项探针。一段钉一条，回退即红。
##   一、表：每个挂点至少一层声；声样只许 SfxSynth 现成的八样（不另做声音，八样都合得出来）、dB 都在 0 以下、
##       每行写明挂在哪；收战按 outcome 认挂点（胜 / 败 / 其余放风声）。
##   二、原先七处搬进表一字不差：墨幕过渡 −5、入战 −4、开炮 −7、命中 −8、接舷 −4、收战三样 −4（lane-s 起的具名口原值）。
##   三、无头不出声也不报错：headless 下放声只记发声账、不在根下建播放器；表里没有的挂点不响不报错；
##       总静音（AudioHooks.enabled = false）记 muted；节点不在树上记 no_tree；总音量 volume_db 加在每一行上。
##   四、真走挂点（真起 WorldMap 海战，headless）：入战、旗舰齐射、炮弹命中敌船、接舷、收战胜 / 败 / 撤离各记一笔对的挂点；
##       敌船开炮那一路与墨幕过渡（Main.play_transition）按源码钉调用点。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_cues_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_CUES PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红（tools/script_err_tally.gd）。

const TAG := "QA_W54_AUDIO_CUES"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _SRC := preload("res://tools/src_probe.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SYNTH := preload("res://scripts/audio/SfxSynth.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

## SfxSynth 现成的八样（AudioHooks.CUE_*）
const STOCK := [&"transition", &"combat_start", &"combat_fire", &"combat_hit", &"combat_board",
	&"combat_win", &"combat_lose", &"combat_flee"]
## 原先七处具名口的声样与音量（lane-s 9b2b1eb0 的 AudioHooks.transition / combat_* 原值；开炮那一口后来按谁开的分成两行，同声同量）
const BASE := {
	&"transition": [&"transition", -5.0], &"sea_start": [&"combat_start", -4.0], &"sea_fire": [&"combat_fire", -7.0],
	&"sea_fire_own": [&"combat_fire", -7.0], &"sea_hit": [&"combat_hit", -8.0], &"sea_board": [&"combat_board", -4.0], &"sea_win": [&"combat_win", -4.0],
	&"sea_lose": [&"combat_lose", -4.0], &"sea_flee": [&"combat_flee", -4.0],
}

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _fleet: Node = null
var _gm: Node = null
var _gs: Node = null
var _rec: Array = []
var _seed := 5440


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
	print("== 一、表：声样只用现成八样，dB 在 0 以下")
	_sec_table()
	print("== 二、原先七处搬进表一字不差")
	_sec_base()
	print("== 三、无头不出声也不报错")
	await _sec_headless()
	print("== 四、真走挂点（真起 WorldMap 海战）")
	await _sec_sea()
	_sec_src()
	_Switches.reset()
	_AUDIO.enabled = true
	_AUDIO.volume_db = 0.0
	_report()


# ── 发声账 ─────────────────────────────────────────────

## 发声账从 mark 起（含）往后、挂点为 hook 的各笔
static func _since(mark: int, hook: StringName) -> Array:
	var out: Array = []
	var j: Array = _AUDIO.journal
	for i in range(maxi(0, mark), j.size()):
		if StringName(j[i].get("hook", &"")) == hook:
			out.append(j[i])
	return out


## 发声账的「此刻」：下一笔会落在第几格（账满 64 条丢最旧的，用前先清空）
static func _mark() -> int:
	_AUDIO.journal.clear()
	return 0


static func _sounded(rows: Array) -> bool:
	for r in rows:
		if str(r.get("why", "?")) == "":
			return true
	return false


# ── 一、表 ─────────────────────────────────────────────

func _sec_table() -> void:
	var bad_cue: PackedStringArray = []
	var loud: PackedStringArray = []
	var empty: PackedStringArray = []
	var nowhere: PackedStringArray = []
	for hook in _SFX.HOOKS:
		var row: Dictionary = _SFX.HOOKS[hook]
		var layers: Array = row.get("layers", [])
		if layers.is_empty():
			empty.append(String(hook))
		if str(row.get("where", "")).strip_edges() == "":
			nowhere.append(String(hook))
		for layer in layers:
			if not (StringName(layer[0]) in STOCK):
				bad_cue.append("%s:%s" % [hook, layer[0]])
			if float(layer[1]) > 0.0:
				loud.append("%s:%s" % [hook, layer[1]])
	_check(_SFX.HOOKS.size() >= BASE.size() and empty.is_empty(), "每个挂点至少一层声（共 %d 个挂点；空的 %s）" % [_SFX.HOOKS.size(), ",".join(empty)])
	_check(bad_cue.is_empty(), "声样只许 SfxSynth 现成的八样，不另做声音（越出的 %s）" % ",".join(bad_cue))
	_check(loud.is_empty(), "每层 dB 都在 0 以下（超出的 %s）" % ",".join(loud))
	_check(nowhere.is_empty(), "每行写明挂在哪（没写的 %s）" % ",".join(nowhere))
	var synth_ok := true
	for cue in STOCK:
		if _SYNTH.stream_for(cue) == null or _AUDIO.stream_for(cue) == null:
			synth_ok = false
	_check(synth_ok, "现成八样都合得出来（SfxSynth.stream_for 非空）")
	_check(_SFX.result_hook("win") == &"sea_win" and _SFX.result_hook("lose") == &"sea_lose"
		and _SFX.result_hook("flee", {"flee_ok": true}) == &"sea_flee",
		"收战认挂点：胜 sea_win / 败 sea_lose / 撤离 sea_flee")


# ── 二、原先七处 ───────────────────────────────────────

func _sec_base() -> void:
	for hook in BASE:
		var row: Dictionary = _SFX.HOOKS.get(hook, {})
		var layers: Array = row.get("layers", [])
		var want: Array = BASE[hook]
		var ok: bool = layers.size() == 1 and StringName(layers[0][0]) == want[0] and is_equal_approx(float(layers[0][1]), want[1])
		_check(ok, "%s：%s %+.0f dB（表里是 %s）" % [hook, want[0], want[1], str(layers)])


# ── 三、无头 ───────────────────────────────────────────

func _sec_headless() -> void:
	var host := Node.new()
	host.name = "AudioProbeHost"
	root.add_child(host)
	await process_frame
	_check(DisplayServer.get_name() == "headless", "本段在 headless 下跑（DisplayServer = %s）" % DisplayServer.get_name())
	var m := _mark()
	_SFX.play(host, &"sea_fire")
	_SFX.play(host, &"sea_board")
	await process_frame
	await process_frame
	var players := 0
	for c in root.get_children():
		if c is AudioStreamPlayer or c.has_meta(&"nk1_sfx"):
			players += 1
	var fire := _since(m, &"sea_fire")
	_check(players == 0, "headless 下根下不建播放器（%d 个）" % players)
	_check(fire.size() == 1 and _sounded(fire) and StringName(fire[0]["cue"]) == &"combat_fire",
		"发声账照记：sea_fire → combat_fire 一笔（%s）" % str(fire))
	m = _mark()
	_SFX.play(host, &"no_such_hook")
	_check(_AUDIO.journal.size() == m, "表里没有的挂点不响、不记、不报错")
	_AUDIO.enabled = false
	_SFX.play(host, &"sea_hit")
	_AUDIO.enabled = true
	var hit := _since(m, &"sea_hit")
	_check(hit.size() == 1 and str(hit[0]["why"]) == "muted", "总静音时记 muted（%s）" % str(hit))
	var loose := Node.new()
	m = _mark()
	_SFX.play(loose, &"sea_start")
	loose.free()
	var st := _since(m, &"sea_start")
	_check(st.size() == 1 and str(st[0]["why"]) == "no_tree", "节点不在树上记 no_tree、不报错（%s）" % str(st))
	_AUDIO.volume_db = -6.0
	m = _mark()
	_SFX.play(host, &"sea_lose")
	_AUDIO.volume_db = 0.0
	var lose := _since(m, &"sea_lose")
	_check(lose.size() == 1 and is_equal_approx(float(lose[0]["db"]), -10.0),
		"总音量 volume_db −6 加在 sea_lose 的 −4 上 = −10（%s）" % str(lose))
	host.queue_free()
	await process_frame


# ── 四、真走挂点 ───────────────────────────────────────

func _mk(t: String, nm: String, crew: int) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": dur, "max_durability": dur}


func _pb() -> Dictionary:
	return {"battle": true, "power": 300.0, "player_power": 1000.0, "enemy": [{"type": "pirate_boat", "count": 2}],
		"sea_name": "泉州外海", "sea_seed": 7_300_000 + _seed, "source": {"scene": "SeaChart", "event": "pirate"}}


## 真起一场海战（撞上大风两散的种子换下一个重起）；起来后谁都不开炮，只由探针点名开火
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


func _sec_sea() -> void:
	var m := _mark()
	var wm := await _stage()
	_check(wm != null, "海战起得来（WorldMap.tscn，非大风两散的种子）")
	if wm == null:
		return
	_check(_sounded(_since(m, &"sea_start")), "入战：_setup_combat 记 sea_start")
	var ship: Node2D = wm.get("ship")
	# 旧口径齐射（player_gunnery 关）：不看射界里有没有敌船，保底一发——本段只验挂点
	_Switches.set_on("player_gunnery", false)
	m = _mark()
	ship.call("_fire_broadside", 1)
	_Switches.reset()
	_check(_sounded(_since(m, &"sea_fire_own")), "旗舰齐射（Ship._fire_broadside）记 sea_fire_own")
	var foe := _enemy(wm)
	var cb: Node2D = (load("res://scenes/Cannonball.tscn") as PackedScene).instantiate()
	cb.position = ship.position
	cb.set("direction", (foe.position - ship.position).normalized())
	cb.set("shooter", ship)
	wm.add_child(cb)
	m = _mark()
	cb.call("_strike", foe, foe.global_position)
	_check(_sounded(_since(m, &"sea_hit")), "炮弹落在敌船上（Cannonball._strike）记 sea_hit")
	await _finish(wm, "win", {})
	_check(_sounded(_since(_last_mark, &"sea_win")), "收战胜（WorldMap._battle_exit win）记 sea_win")
	for pair in [["lose", {"sunk": true}, &"sea_lose"], ["flee", {"flee_ok": true, "parted": true}, &"sea_flee"]]:
		var w2 := await _stage()
		if w2 == null:
			_check(false, "海战起得来（收战 %s）" % pair[0])
			continue
		await _finish(w2, pair[0], pair[1])
		_check(_sounded(_since(_last_mark, pair[2])), "收战 %s（WorldMap._battle_exit）记 %s" % [pair[0], pair[2]])
	# 接舷放最后：headless 下白刃当帧分胜负，可能顺手收战
	var w3 := await _stage()
	if w3 == null:
		_check(false, "海战起得来（接舷）")
		return
	m = _mark()
	w3.call("_board_enemy", _enemy(w3))
	_check(_sounded(_since(m, &"sea_board")), "接舷（WorldMap._board_enemy）记 sea_board")
	await _finish(w3, "flee", {"flee_ok": true, "parted": true})


var _last_mark := 0


func _finish(wm: Node, outcome: String, data: Dictionary) -> void:
	_last_mark = _mark()
	if is_instance_valid(wm) and wm.get("resolved") != true:
		wm.call("_battle_exit", outcome, data.duplicate(true))
	for _i in 6:
		await process_frame


## 敌船开炮、墨幕过渡两处不真起（敌将定打不打、Main 整页太重），按源码钉调用点
func _sec_src() -> void:
	var pirate := FileAccess.get_file_as_string("res://scripts/PirateShip.gd")
	var main := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_check(_SRC.func_body(pirate, "_process_firing").contains("_SFX.play(get_parent(), &\"sea_fire\")"),
		"敌船 / 护航开炮（PirateShip._process_firing）走挂点 sea_fire")
	_check(_SRC.func_body(main, "play_transition").contains("_SFX.play(self, &\"transition\")"),
		"墨幕过渡（Main.play_transition）走挂点 transition")
	var stale: PackedStringArray = []
	for path in ["res://scripts/Ship.gd", "res://scripts/PirateShip.gd", "res://scripts/Cannonball.gd",
			"res://scripts/WorldMap.gd", "res://scripts/Main.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for old in ["_AUDIO.combat_", "_AUDIO.transition("]:
			if src.contains(old):
				stale.append("%s 还在调 %s" % [path.get_file(), old])
	_check(stale.is_empty(), "各处不再绕过挂点表直调 AudioHooks 具名口（%s）" % "；".join(stale))
