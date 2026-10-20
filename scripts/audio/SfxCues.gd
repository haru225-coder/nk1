## 音效挂点表（lane w54-audio）：游戏里每一处发声都在这张表里登记一行——挂点叫什么、挂在哪、放哪一样声、多响。
## 各处只写一句 `SfxCues.play(节点, &"挂点")`，声样与音量都在表里改，不散在各个文件里。
##
## 声样只用 SfxSynth 现成的八样（transition 一声轻磬带风 / combat_start 两记战鼓 / combat_fire 炮声 / combat_hit 船板碎裂 /
## combat_board 钩索闷撞带两下金铁 / combat_win 三记磬音上行 / combat_lose 两记下行 / combat_flee 掠过的风声），
## 不另做声音（qa_w54_audio_cues_probe 逐行查）。播放、静音、节流、声部上限都在 AudioHooks：
## 总静音 AudioHooks.enabled（或启动时 NK1_SFX=0）、总音量 AudioHooks.volume_db 加在每一行的 dB 上。
## headless 不出声也不报错（AudioHooks 不建播放器，只在发声账 journal 里记一笔）。
##
## 本波补挂的行标 added：总开关 CombatSwitches.sfx_cues 关着时一处不响（发声账记 off），原先那几处照旧。
##
## 本件不直读 autoload（Fleet / GameState …）：Ship / PirateShip / Cannonball 都 preload 它，-s 工具 preload 那几件时照样编得过。
extends RefCounted

const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

## 补挂那些行的总开关（CombatSwitches 表末那一键）
const SWITCH := "sfx_cues"

## 挂点 → {layers: 声层, where: 挂在哪, gap_key: 节流认哪把锁（可缺）, group: 收声组（可缺）, added: 本波补挂（可缺）, gap_ms}。
## 声层一行 [声样, dB, 晚几秒出（可缺，缺 = 当下）, 音高（可缺，缺 = 1；低于 1 声更沉、也更长）]（dB 在 AudioHooks.volume_db
## 之上再加；全表都在 0 以下）。晚出的那一层到点时发声那一处已不在树上（收了战、换了场景）就不补。
## 原先那几行同一样声多快能再响按 AudioHooks._MIN_GAP_MS（开炮 90 毫秒、命中 60 毫秒），锁缺省按声样——
## 旗舰齐射另起一把锁（gap_key），敌船 / 护航刚放过一排也吞不掉玩家自己按下去的那一排。补挂的行各按自己的 gap_ms 节流
## （同一挂点隔这么久才许再响，几艘船同一帧沉、四条火船接连撞上，听着是一声），不与原先那几行抢锁。
## 收声组（group）：同组的新声一响，还在响的旧声当场收掉——墨幕被新墨幕顶掉时（晋升翻页全黑时排守城 / 终局岸带头一回，
## 又起一幕题签），旧幕那声磬跟着收，不叠成两声。
## 原先就有的七处（lane-s 起的 AudioHooks 具名口）搬进表里，声样、音量一字不差。
const HOOKS := {
	&"transition": {"layers": [[&"transition", -5.0]], "group": &"bell", "where": "Main.play_transition（墨幕过渡）"},
	&"sea_start": {"layers": [[&"combat_start", -4.0]], "where": "WorldMap._setup_combat（入战）"},
	&"sea_fire": {"layers": [[&"combat_fire", -7.0]], "where": "PirateShip._process_firing（敌船 / 护航开炮）"},
	&"sea_fire_own": {"layers": [[&"combat_fire", -7.0]], "gap_key": &"combat_fire_own", "where": "Ship 齐射两路（旗舰开炮）"},
	&"sea_hit": {"layers": [[&"combat_hit", -8.0]], "where": "Cannonball 命中"},
	&"sea_board": {"layers": [[&"combat_board", -4.0]], "where": "WorldMap._board_enemy（接舷）"},
	&"sea_win": {"layers": [[&"combat_win", -4.0]], "where": "WorldMap._battle_exit（胜）"},
	&"sea_lose": {"layers": [[&"combat_lose", -4.0]], "where": "WorldMap._battle_exit（败）"},
	&"sea_flee": {"layers": [[&"combat_flee", -4.0]], "where": "WorldMap._battle_exit（两散 / 撤离）"},
	# ── 本波补挂 · 海战（一到六期的船上事）──
	&"sea_fire_ship": {"layers": [[&"combat_hit", -3.0, 0.0, 0.85], [&"combat_flee", -2.0, 0.05]], "added": true, "gap_ms": 150,
		"where": "PirateShip.ignite_on（崖山火船撞上、点着）"},
	&"sea_ignite": {"layers": [[&"combat_flee", -10.0, 0.0, 0.8]], "added": true, "gap_ms": 1200,
		"where": "Ship._emit_damage_events fire（旗舰起火）/ PirateShip._sync_fire_look（敌船火起）"},
	&"sea_blast": {"layers": [[&"combat_fire", -1.0, 0.0, 0.75], [&"combat_hit", -5.0, 0.04]], "added": true, "gap_ms": 400,
		"where": "Ship._emit_damage_events magazine / PirateShip._step_flood_fire（火药舱炸）"},
	&"sea_mast": {"layers": [[&"combat_hit", -4.0, 0.0, 0.6]], "added": true, "gap_ms": 600,
		"where": "Ship._emit_damage_events mast_down（旗舰桅倒）"},
	&"sea_sink": {"layers": [[&"combat_hit", -5.0, 0.0, 0.7], [&"combat_flee", -6.0, 0.15, 0.6]], "added": true, "gap_ms": 250,
		"where": "PirateShip._explode（敌船 / 护航 / 火船沉）"},
	&"sea_strike": {"layers": [[&"combat_flee", -12.0, 0.0, 0.7]], "added": true, "gap_ms": 400,
		"where": "WorldMap._on_captain_state_changed strike（敌船降幡，幡落的那一下）"},
	&"sea_hook_miss": {"layers": [[&"combat_flee", -15.0, 0.0, 1.4]], "added": true, "gap_ms": 400,
		"where": "PirateShip._try_grapple / EscortWing.ship_hooks（钩索落空、垂进水里）"},
	&"sea_escort_board": {"layers": [[&"combat_board", -10.0]], "added": true, "gap_ms": 400,
		"where": "EscortWing.ship_hooks（护航与敌船钩住跳帮）"},
	&"sea_order": {"layers": [[&"combat_start", -13.0]], "added": true, "gap_ms": 800,
		"where": "WorldMap._on_combat_order（号令擂鼓；撤令不响）"},
	&"sea_splash": {"layers": [[&"combat_flee", -17.0, 0.0, 1.7]], "added": true, "gap_ms": 150,
		"where": "Cannonball._splash_and_die（重弹落水；一排矢只溅小花不响）"},
	# ── 本波补挂 · 海图与港口 ──
	&"chart_depart": {"layers": [[&"combat_flee", -11.0, 0.0, 0.75]], "added": true, "gap_ms": 1000,
		"where": "SeaChart._on_sail_pressed（启程：帆吃满风、船头破浪）"},
	&"chart_storm": {"layers": [[&"combat_flee", -3.0, 0.0, 0.6], [&"combat_flee", -7.0, 0.35, 0.8]], "added": true, "gap_ms": 1500,
		"where": "SeaChart._show_event 风涛（浪头一个高过一个，两下）"},
	&"chart_shoal": {"layers": [[&"combat_hit", -6.0, 0.0, 0.5]], "added": true, "gap_ms": 1500,
		"where": "SeaChart._show_event 浅滩（船底擦过沙脊）"},
	&"chart_arrive": {"layers": [[&"transition", -6.0, 0.0, 0.75]], "added": true, "gap_ms": 1500, "group": &"bell",
		"where": "SeaChart._arrive（靠港钟：比墨幕那声沉，同在收声组 bell）"},
	&"chart_sink": {"layers": [[&"combat_hit", -3.0, 0.0, 0.6], [&"combat_lose", -6.0, 0.3]], "added": true, "gap_ms": 1500,
		"where": "SeaChart._sink（海上沉没：船身裂开，随后两记下行磬音）"},
}

## 旗舰损伤事件（Ship.damage_event 的 kind）→ 挂点；表外的 kind 不响
const DAMAGE_HOOKS := {"fire": &"sea_ignite", "magazine": &"sea_blast", "mast_down": &"sea_mast"}

## 补挂那些行上一回响在何时（毫秒，AudioHooks.now_ms 那只钟）
static var _hook_ms: Dictionary = {}


## 放一个挂点的声（表里没有这个挂点就不响）。host 是发声那一处的节点，AudioHooks 拿它找场景树根。
static func play(host: Node, hook: StringName) -> void:
	var row: Dictionary = HOOKS.get(hook, {})
	if row.is_empty():
		return
	var added := bool(row.get("added", false))
	if added:
		if not _Switches.on(SWITCH):
			_AUDIO.skip(hook, "off")
			return
		var now := _AUDIO.now_ms()
		var last := int(_hook_ms.get(hook, -100000))
		if now >= last and now - last < int(row.get("gap_ms", 0)):  # last 在 now 之后 = 探针钟往回拨过
			_AUDIO.skip(hook, "gap")
			return
		_hook_ms[hook] = now
	var layers: Array = row.get("layers", [])
	for i in layers.size():
		var layer: Array = layers[i]
		var opts := {"hook": hook}
		for k in ["gap_key", "group"]:
			if row.has(k):
				opts[k] = row[k]
		if added:
			# 补挂的行在上面整行节流过了：每层自己一把锁、不再另挡，也不压原先那几行的锁
			opts["gap_key"] = StringName("%s#%d" % [hook, i])
			opts["gap_ms"] = 0
		if layer.size() > 3:
			opts["pitch"] = float(layer[3])
		var at := float(layer[2]) if layer.size() > 2 else 0.0
		if at > 0.0:
			_later(host, at, StringName(layer[0]), float(layer[1]), opts)
		else:
			_AUDIO.play_cue(host, StringName(layer[0]), float(layer[1]), opts)


## 晚 at 秒出的那一层：到点时发声那一处已不在树上（收了战、换了场景）就不补
static func _later(host: Node, at: float, cue: StringName, db: float, opts: Dictionary) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var ref: WeakRef = weakref(host)
	host.get_tree().create_timer(at).timeout.connect(func() -> void:
		var h = ref.get_ref()
		if h != null and (h as Node).is_inside_tree():
			_AUDIO.play_cue(h, cue, db, opts))


## 旗舰损伤事件：Ship._emit_damage_events 逐条调
static func damage_event(host: Node, kind: String) -> void:
	var hook: StringName = DAMAGE_HOOKS.get(kind, &"")
	if hook != &"":
		play(host, hook)


## 收战那一声认哪个挂点：胜 / 败各一样，两散、甩脱放风声。data 是 battle_finished 的那份。
## 逃没逃掉（flee 而 flee_ok 不真：B 键弃战掷输、我方溃逃没跑掉）海图照败局记——船挨一顿、舱货被夺，札记写「未能甩脱」，
## 放败局那一声；判法与 SeaChart._on_battle_result 同一口径（data.get("flee_ok", false)）。原先这一支照放撤离的风声。
static func result_hook(outcome: String, data := {}) -> StringName:
	if outcome == "win":
		return &"sea_win"
	if outcome == "lose" or (outcome == "flee" and not bool(data.get("flee_ok", false))):
		return &"sea_lose"
	return &"sea_flee"


## 收战：WorldMap._battle_exit 调
static func battle_result(host: Node, outcome: String, data := {}) -> void:
	play(host, result_hook(outcome, data))
