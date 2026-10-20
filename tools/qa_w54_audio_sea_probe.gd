extends SceneTree
## lane w54-audio：海战补挂的声（SfxCues 表里标 added 的海战十行）。一段钉一条，回退即红。
##   一到六期加了火船、水与火、火药舱、桅倒、降幡、护航跳帮、号令，船沉、钩索落空、重弹落水这些事，画面上都有一下，
##   原先一声不出（AudioHooks 只挂了开炮、命中、接舷、入战、收战五样）。
##   一、表：十行都在、标 added、各带自己的 gap_ms；旗舰损伤事件认三样（起火 / 火药舱炸 / 桅倒）；CombatSwitches 有 sfx_cues、缺省开。
##   二、开关 sfx_cues 关：十行一处不响（发声账记 off）、原先那几行照响；开回来照响。
##   三、真起 WorldMap 海战（headless）逐处走真路：敌船起火（水火簿点着、走它自己的 _step_flood_fire）、敌船火药舱炸、
##       降幡（strike_colours → 敌将改打法 → WorldMap 收信号）、钩索落空（贴舷、按种子让钩牢骰掷输、走 _try_grapple）、
##       号令（WorldMap._on_combat_order，撤令不响）、重弹落水（Cannonball._splash_and_die；一排矢不响）、
##       旗舰起火 / 火药舱炸 / 桅倒（Ship._emit_damage_events；进水之类不响）、火船撞上点着（ignite_on，两层都响）、
##       敌船沉（take_damage 打到见底 → _explode，两层都响）；开关关时同一处真路记 off、不响。护航接舷 / 落空按源码钉。
##   四、补挂的行按自己的 gap_ms 节流：250 毫秒内连沉两条只响一声，过了再响；不与原先那几行抢锁（命中刚响过，沉船那层照响）。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_sea_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_SEA PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_SEA"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _SRC := preload("res://tools/src_probe.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

const SEA := [&"sea_fire_ship", &"sea_ignite", &"sea_blast", &"sea_mast", &"sea_sink", &"sea_strike", &"sea_hook_miss",
	&"sea_escort_board", &"sea_order", &"sea_splash"]
const BASE := [&"transition", &"sea_start", &"sea_fire", &"sea_fire_own", &"sea_hit", &"sea_board", &"sea_win",
	&"sea_lose", &"sea_flee"]

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _fleet: Node = null
var _gm: Node = null
var _gs: Node = null
var _rec: Array = []
var _seed := 5560
var _clock := 4_000_000


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
	print("== 二、开关 sfx_cues 关")
	await _sec_switch()
	print("== 三、真起海战逐处走真路")
	await _sec_sea()
	print("== 四、补挂的行按自己的 gap_ms 节流")
	await _sec_gap()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


# ── 发声账 ─────────────────────────────────────────────

## 拨钟十秒、清账：上一样的声都放完、补挂行的节流也过了
func _fresh() -> void:
	_clock += 10_000
	_AUDIO.clock_ms = _clock
	_AUDIO.journal.clear()


## 发声账里挂点 hook 的各笔 why
static func _whys(hook: StringName) -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if StringName(r.get("hook", &"")) == hook:
			out.append(str(r.get("why", "?")))
	return out


static func _sounded(hook: StringName) -> int:
	return _whys(hook).count("")


## 晚出的那几层（0.05–0.15 秒）到点再看账
func _settle() -> void:
	await create_timer(0.3).timeout


# ── 一、表 ─────────────────────────────────────────────

func _sec_table() -> void:
	var missing: PackedStringArray = []
	var no_gap: PackedStringArray = []
	for hook in SEA:
		var row: Dictionary = _SFX.HOOKS.get(hook, {})
		if row.is_empty() or not bool(row.get("added", false)):
			missing.append(String(hook))
		elif int(row.get("gap_ms", 0)) <= 0:
			no_gap.append(String(hook))
	_check(missing.is_empty(), "海战补挂十行都在、都标 added（缺 %s）" % ",".join(missing))
	_check(no_gap.is_empty(), "十行各带自己的 gap_ms（没带的 %s）" % ",".join(no_gap))
	var base_added: PackedStringArray = []
	for hook in BASE:
		if bool(_SFX.HOOKS.get(hook, {}).get("added", false)):
			base_added.append(String(hook))
	_check(base_added.is_empty(), "原先那几行不标 added（不归开关管：%s）" % ",".join(base_added))
	_check(str(_SFX.DAMAGE_HOOKS) == str({"fire": &"sea_ignite", "magazine": &"sea_blast", "mast_down": &"sea_mast"}),
		"旗舰损伤事件认三样：起火 / 火药舱炸 / 桅倒（%s）" % str(_SFX.DAMAGE_HOOKS))
	_check(_Switches.DEFAULTS.has(_SFX.SWITCH) and _Switches.on(_SFX.SWITCH),
		"CombatSwitches 有 %s 键、缺省开" % _SFX.SWITCH)


# ── 二、开关 ───────────────────────────────────────────

func _sec_switch() -> void:
	var host := Node.new()
	root.add_child(host)
	await process_frame
	_Switches.set_on(_SFX.SWITCH, false)
	_fresh()
	for hook in SEA + BASE:
		_one(host, hook)
	await _settle()
	var loud: PackedStringArray = []
	for hook in SEA:
		if _whys(hook) != ["off"]:
			loud.append("%s%s" % [hook, str(_whys(hook))])
	_check(loud.is_empty(), "开关关：海战补挂十行都记 off、一声不响（不对的 %s）" % ",".join(loud))
	var quiet: PackedStringArray = []
	for hook in BASE:
		if _sounded(hook) == 0:
			quiet.append("%s%s" % [hook, str(_whys(hook))])
	_check(quiet.is_empty(), "开关关：原先那几行照响（没响的 %s）" % ",".join(quiet))
	_Switches.reset()
	_fresh()
	for hook in SEA:
		_one(host, hook)
	await _settle()
	var off: PackedStringArray = []
	for hook in SEA:
		if _sounded(hook) == 0:
			off.append("%s%s" % [hook, str(_whys(hook))])
	_check(off.is_empty(), "开关开回：十行都响（没响的 %s）" % ",".join(off))
	host.queue_free()
	await process_frame


## 一声一个时刻：探针钟拨后两秒再放（上一声放完、声部空出来，免得一连十声撞上声部上限 6）
func _one(host: Node, hook: StringName) -> void:
	_clock += 2_000
	_AUDIO.clock_ms = _clock
	_SFX.play(host, hook)


# ── 三、真起海战 ───────────────────────────────────────

func _mk(t: String, nm: String, crew: int) -> Dictionary:
	var d: Dictionary = _fleet.call("ship_def", t)
	var dur := float(d.get("durability", 300))
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": dur, "max_durability": dur}


func _pb() -> Dictionary:
	return {"battle": true, "power": 300.0, "player_power": 1000.0, "enemy": [{"type": "pirate_boat", "count": 4}],
		"sea_name": "泉州外海", "sea_seed": 7_600_000 + _seed, "source": {"scene": "SeaChart", "event": "pirate"}}


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


static func _enemies(wm: Node) -> Array:
	var out: Array = []
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() and float(c.get("hull_hp")) > 0.0:
			out.append(c)
	return out


func _close(wm: Node) -> void:
	if is_instance_valid(wm) and wm.get("resolved") != true:
		wm.call("_battle_exit", "flee", {"flee_ok": true, "parted": true})
	for _i in 4:
		await process_frame


func _sec_sea() -> void:
	var wm := await _stage()
	_check(wm != null, "海战起得来（四条海寇快船：三条拿来试，一条留着别让仗收场——晚出那一层要场子还在）")
	if wm == null:
		return
	var ship: Node2D = wm.get("ship")
	var foes := _enemies(wm)
	_check(foes.size() == 4, "四条敌船都在（%d）" % foes.size())
	if foes.size() < 4:
		return
	var a: Node2D = foes[0]
	var b: Node2D = foes[1]
	var c: Node2D = foes[2]
	var d: Node2D = foes[3]
	# 敌船起火：水火簿点着舯部，走它自己的一步水火
	var ffa = a.get("flood_fire")
	_check(ffa != null, "敌船挂着水火簿（enemy_flood_fire 开）")
	if ffa != null:
		_fresh()
		ffa.get("ff").call("ignite", "mid", 0.5)
		a.call("_step_flood_fire", 0.016)
		_check(_sounded(&"sea_ignite") == 1, "敌船火起（_step_flood_fire → _sync_fire_look 火级由 0 起）记 sea_ignite（%s）" % str(_whys(&"sea_ignite")))
		_fresh()
		a.call("_step_flood_fire", 0.016)
		_check(_whys(&"sea_ignite").is_empty(), "火接着烧的下一步不再响")
		# 敌船火药舱炸：艉部火旺、火药受热到线
		var ff = ffa.get("ff")
		ff.set("powder", true)
		ff.set("magazine_gone", false)
		var fire: Dictionary = ff.get("fire")
		fire["stern"] = 1.0
		ff.set("magazine_heat", 5.999)
		_fresh()
		a.call("_step_flood_fire", 0.05)
		await _settle()
		_check(bool(ff.get("magazine_gone")) and _sounded(&"sea_blast") == 2, "敌船火药舱炸（FloodFire blast）记 sea_blast 两层（%s）" % str(_whys(&"sea_blast")))
	# 降幡：敌将改打法的信号在下一物理帧（PirateShip._note_state）发
	_fresh()
	b.call("strike_colours", "")
	for _i in 3:
		await physics_frame
	_check(_sounded(&"sea_strike") == 1, "敌船降幡（strike_colours → 敌将改打法 → WorldMap._on_captain_state_changed）记 sea_strike（%s）" % str(_whys(&"sea_strike")))
	# 钩索落空：c 贴到旗舰舷边，按种子让钩牢骰掷输
	c.position = ship.position + Vector2(70, 0)
	c.rotation = ship.rotation
	c.set("velocity", Vector2.ZERO)
	ship.set("velocity", Vector2.ZERO)
	var ap: Dictionary = wm.call("boarding_approach_of", c, ship)
	var odds := float(c.call("_grapple_odds"))
	_check(not ap.is_empty() and bool(ap.get("ok", false)) and odds < 0.995, "贴舷够距、钩牢机会 %.2f（够距 %s）" % [odds, str(ap.get("ok"))])
	var s := 1
	var peek := RandomNumberGenerator.new()
	while s < 3000:
		peek.seed = s
		if peek.randf() >= odds:
			break
		s += 1
	(c.get("_rng") as RandomNumberGenerator).seed = s
	_fresh()
	var hooked := bool(c.call("_try_grapple"))
	_check(not hooked and _sounded(&"sea_hook_miss") == 1, "钩牢骰掷输（_try_grapple）记 sea_hook_miss（钩上 %s；%s）" % [hooked, str(_whys(&"sea_hook_miss"))])
	c.position = ship.position + Vector2(1500, 0)  # 挪开，后面等帧时别自己再抛钩接舷
	# 号令：下令擂鼓、撤令不响
	_fresh()
	wm.call("_on_combat_order", "windward", {"on": true})
	_check(_sounded(&"sea_order") == 1, "号令：抢风（WorldMap._on_combat_order）记 sea_order")
	_fresh()
	wm.call("_on_combat_order", "windward", {"on": false})
	_check(_whys(&"sea_order").is_empty(), "撤令：抢风不响")
	# 重弹落水 / 一排矢落水
	for heavy in [true, false]:
		var cb: Node2D = (load("res://scenes/Cannonball.tscn") as PackedScene).instantiate()
		cb.position = ship.position + Vector2(0, 400)
		cb.set("direction", Vector2.DOWN)
		cb.set("shooter", ship)
		wm.add_child(cb)
		var shot: Dictionary = cb.get("shot")
		shot["heavy"] = heavy
		_fresh()
		cb.call("_splash_and_die")
		if heavy:
			_check(_sounded(&"sea_splash") == 1, "重弹落水（Cannonball._splash_and_die）记 sea_splash")
		else:
			_check(_whys(&"sea_splash").is_empty(), "一排矢落水只溅小花，不响")
	# 旗舰损伤事件：起火 / 火药舱炸 / 桅倒各一声，进水不响
	_fresh()
	ship.call("_emit_damage_events", [{"kind": "fire", "zone": "rig"}, {"kind": "magazine", "zone": "stern"},
		{"kind": "mast_down"}, {"kind": "leak", "comp": 1}])
	await _settle()
	_check(_sounded(&"sea_ignite") == 1 and _sounded(&"sea_blast") == 2 and _sounded(&"sea_mast") == 1,
		"旗舰损伤事件（Ship._emit_damage_events）：起火 / 火药舱炸两层 / 桅倒（%s / %s / %s）" % [
			_whys(&"sea_ignite"), _whys(&"sea_blast"), _whys(&"sea_mast")])
	var others := 0
	for r in _AUDIO.journal:
		if not (StringName(r.get("hook", &"")) in [&"sea_ignite", &"sea_blast", &"sea_mast"]):
			others += 1
	_check(others == 0, "进水那一条不响（账里别的挂点 %d 笔）" % others)
	# 火船撞上点着（b 已降，拿它摆成火船）
	b.call("set_fire_ship", 0.0)
	_fresh()
	b.call("ignite_on", ship)
	await _settle()
	_check(_sounded(&"sea_fire_ship") == 2, "火船撞上点着（PirateShip.ignite_on）记 sea_fire_ship 两层（%s）" % str(_whys(&"sea_fire_ship")))
	_fresh()
	b.call("ignite_on", ship)
	_check(_whys(&"sea_fire_ship").is_empty(), "点过的火船再碰不再响")
	# 敌船沉：c 打到见底
	_fresh()
	c.call("take_damage", float(c.get("hull_max")) * 3.0)
	await _settle()
	_check(_sounded(&"sea_sink") == 2, "敌船沉（take_damage 见底 → _explode）记 sea_sink 两层（%s）" % str(_whys(&"sea_sink")))
	# 开关关：同一处真路记 off（留着的那条 d）
	_Switches.set_on(_SFX.SWITCH, false)
	_fresh()
	d.call("take_damage", float(d.get("hull_max")) * 3.0)
	await _settle()
	_Switches.reset()
	_check(_whys(&"sea_sink") == ["off"], "开关关时敌船沉记 off、不响（%s）" % str(_whys(&"sea_sink")))
	await _close(wm)
	_src_checks()


## 护航接舷 / 落空要护航上阵、两船贴着钩，摆场太重，按源码钉
func _src_checks() -> void:
	var wing := FileAccess.get_file_as_string("res://scripts/combat/EscortWing.gd")
	var body := _SRC.func_body(wing, "ship_hooks")
	var miss_at := body.find("_SFX.play(self, &\"sea_hook_miss\")")
	var board_at := body.find("_SFX.play(self, &\"sea_escort_board\")")
	_check(miss_at >= 0 and miss_at < body.find("return false\n\tatt.call(\"_flash_tag\", \"抛钩接舷\")"),
		"护航那边钩索落空（EscortWing.ship_hooks 掷输那一支）走 sea_hook_miss")
	_check(board_at > body.find("att.call(\"_flash_tag\", \"抛钩接舷\")"), "护航与敌船钩住（EscortWing.ship_hooks 钩上那一支）走 sea_escort_board")


# ── 四、节流 ───────────────────────────────────────────

func _sec_gap() -> void:
	var host := Node.new()
	root.add_child(host)
	await process_frame
	_fresh()
	_SFX.play(host, &"sea_hit")
	_SFX.play(host, &"sea_sink")
	_check(_sounded(&"sea_hit") == 1 and _whys(&"sea_sink")[0] == "", "命中刚响过、同一刻沉船那层照响（不抢原先那几行的锁）")
	_AUDIO.clock_ms = _clock + 100
	_SFX.play(host, &"sea_sink")
	_AUDIO.clock_ms = _clock + 260
	_SFX.play(host, &"sea_sink")
	await _settle()
	var w := _whys(&"sea_sink")
	_check(w.count("gap") == 1 and w.count("") == 4, "0 / 100 / 260 毫秒连沉三条：中间那条记 gap，头尾两条各两层都响（%s）" % str(w))
	host.queue_free()
	await process_frame
