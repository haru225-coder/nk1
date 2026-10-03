## 海战士气（lane combat06）：伤亡、失火、被钩舷、船体受创、主将倒下、僚船沉降压士气；过线溃逃、降幡；士气低了不肯接舷。
## 数值全在 data/combat_morale.json（头部 meta 写了口径与史料）；数据读不到或不合规时整套停用：系数 1、不溃不降、
## 白刃系数照 Fleet.morale_factor 同式，推一行 WARNING——接线方不必先判模块在不在，旧手感原样。
##
## 一、士气簿（本脚本的实例，RefCounted）：一船一页，开战时建、战中只在簿上加减。
##   我方一页记全队：底数读 Fleet.morale（只读，不回写），水手读 Fleet.total_crew()，船体读旗舰。
##   敌船一船一页：底数读 enemy_morale，水手 crew，船体 hull_hp，号令按 captain_force 折。
##   建：create(opts) / for_player(fleet, ship, martial, yiren) / for_enemy(ship, lead)
##   事件：hit_hull(伤) lose_crew(人) set_fire(0–1) set_ammo(0–1) grapple(是否进攻方) release()
##         boarding_result(胜否, 是否进攻方) fall_captain() witness(别船出事的 kind) mark_escaped() shock / lift（直接加减）
##   每帧：tick(delta, ctx)，ctx 可带 surrounded / nearest_foe / ammo_frac / fire_level / immobile。
##   查询：state（steady 如常 / shaken 动摇 / wavering 思退 / routing 溃逃 / struck 降幡）、label()、hud_text()、
##         fire_factor()（射速 / 准头）、melee_factor()（白刃，与 Fleet.morale_factor 同量纲）、sail_factor()（溃逃满篷、降幡落帆）、
##         pressure() / pressure_causes()（降幡压力）、board_chance() / try_board(roll)（拒接舷）、cut_grapple_chance()、
##         yields_to_boarding()（降船接舷即得）、take_notes()（状态转折与要事的纪实短句）、snapshot()、carry_to_voyage(战前航行士气)。
## 二、判定（纯函数，不碰场景）：captain_verdict(ctx) 给敌将 AI（combat07 EnemyCaptainAI 的 morale_verdict 钩子）一句 strike / rout / ""。
##   battle_outcome(我方簿, 在场敌簿) → {} 或 {outcome, data}，outcome 同 WorldMap._battle_exit
##   的 win / lose / flee；data 带 morale_verdict（enemy_struck 敌降 / enemy_fled 敌遁 / enemy_broken 降遁皆有 /
##   player_rout 我方溃逃 / player_struck 我方降幡）与 enemy_struck / enemy_fled / struck_types / rout / struck。
##   is_surrounded(位置, 敌位置, 友位置)：半径内两敌分处两舷（方位夹角够大）或三敌以上即算被围，有友船在侧则不算。
## 三、观战挂件 Tracker（内部类，Node）：attach(WorldMap) 挂上后每个物理帧只读轮询——旗舰 / 敌船 hull_hp、crew、grappled（钩上那一刻看 boarding_initiator 定谁攻谁守），
##   Fleet.total_crew()，敌我位置——差值即事件，喂进各页士气簿；敌船降、沉、被夺、溃逃互相传染。
##   写出：各船节点 meta「nk1_combat_morale」= snapshot()；敌船 enemy_morale 改写成战中士气（PirateShip.combat_strength
##   白刃判定读它，write_enemy_morale 关得掉）；信号 state_changed / noted / verdict。不改 WorldMap / Ship / PirateShip 的行为。
##   接线（本 lane 不改这些文件，留给各自的 lane）：
##   - WorldMap._setup_combat 末尾：var m = _CombatMorale.attach(self); m.verdict.connect(_battle_exit)——敌全降 / 遁、我方溃逃 / 降幡即结算。
##   - WorldMap._unhandled_input 的 G：var why: String = m.player_boarding_check()；why 非空则 _show_combat_notice(why)、不接舷（拒接舷）。
##   - WorldMap._board_enemy：Fleet.morale_factor() 换 m.player_sheet().melee_factor()；敌簿 yields_to_boarding() 则免白刃直接夺船。
##   - PirateShip / EnemyCaptainAI：读自己节点的 meta，state == "routing" 转篷离开、"struck" 停船停炮；炮 / 矢乘 fire。
##   - 失火 / 矢石 / 舵篷：船节点上有 fire_level（0–1）或 on_fire、ammo_frac（0–1）或 ammo + ammo_max、immobile 就自动读；
##     没有这些属性的，调 m.report(船, "fire_level" | "ammo_frac" | "immobile" | "captain_down", 值) 推进来。
##   - HUD：group「nk1_combat_morale」取挂件，hud_line() 一行；CombatLetterbox 按 verdict 的 morale_verdict 分「敌降」「我方溃逃」。
## 不直接写 autoload 名字（同 CombatFx，-s 探针可 preload）：挂件运行时按 /root/Fleet 等取节点、按方法名调。
extends RefCounted

const _SELF := preload("res://scripts/combat/CombatMorale.gd")
const DATA_PATH := "res://data/combat_morale.json"
## 船节点 meta 键（挂件写 snapshot()）；挂件自己进的 group
const META_KEY := &"nk1_combat_morale"
const GROUP := "nk1_combat_morale"

const STEADY := "steady"
const SHAKEN := "shaken"
const WAVERING := "wavering"
const ROUTING := "routing"
const STRUCK := "struck"
## 由好到坏；_rank 按下标比
const STATES := [STEADY, SHAKEN, WAVERING, ROUTING, STRUCK]
const SIDE_PLAYER := "player"
const SIDE_ENEMY := "enemy"
## 降幡压力的来由（data pressure / causes 两节逐项对应）
const CAUSES := ["surrounded", "ammo_out", "captain_down", "grappled", "hull_critical", "heavy_losses", "on_fire", "immobile"]
## 数据各数值节须有的键（只列键名，数在 json；缺一个即整套停用）
const NUMERIC := {
	"bands": ["steady", "shaken", "wavering", "hysteresis"],
	"rout": ["rally_line", "rally_distance", "escape_distance", "panic_shock", "panic_line", "player_grace_s", "flee_factor"],
	"strike": ["line", "collapse_line", "pressure_need", "board_lost_line", "hull_critical_frac", "heavy_losses_frac"],
	"pressure": CAUSES,
	"shock": ["casualty_per_pct", "casualty_quarter", "casualty_half", "hull_per_pct", "hull_half", "hull_quarter",
		"fire_start", "grappled", "boarding_lost", "boarding_refused"],
	"lift": ["boarding_won", "boarder_elan", "fire_out"],
	"contagion": ["ally_sunk", "ally_struck", "ally_routed", "ally_captured", "lead_hurt", "lead_sunk", "lead_struck", "lead_captured"],
	"cheer": ["foe_sunk", "foe_struck", "foe_routed", "foe_captured"],
	"drain_per_s": ["fire", "surrounded", "ammo_out", "ammo_low", "ammo_low_frac", "grappled", "immobile"],
	"rally": ["per_s", "calm_seconds", "command_base"],
	"command": ["shock_relief", "captain_down_shock", "captain_down_base", "captain_down_command", "after_down",
		"down_casualty_frac", "enemy_base", "enemy_per_force"],
	"officers": ["yiren_casualty_relief"],
	"surround": ["radius", "spread_deg", "crowd"],
	"melee": ["base", "span"],
	"boarding": ["willing_floor", "willing_full", "cut_grapple_floor", "cut_grapple_max"],
	"carry": ["ratio", "routed", "struck"],
}
const TEMPER_KEYS := ["shock_mult", "rout_offset", "strike_offset", "elan", "captain_mult"]
const FACTOR_KEYS := ["fire", "melee", "sail"]
## 纪实短句：两边都要的，和只有敌船才用得上的（recover 是思退回动摇这类半程回升，不出句子，只发 state_changed）
const NOTE_KINDS := ["to_shaken", "to_wavering", "to_routing", "panic", "to_struck", "rally", "steady_again",
	"boarding_refused", "captain_down"]
const NOTE_KINDS_ENEMY := ["escaped", "lead_lost"]
## 矢石尽：ammo_frac 到这以下
const AMMO_OUT_EPS := 0.001
## 停用时的白刃系数，与 Fleet.morale_factor() 同式（0.6 + 0.4 × 士气 / 100），旧手感原样
const INERT_MELEE_BASE := 0.6
const INERT_MELEE_SPAN := 0.4

static var _data: Dictionary = {}
static var _problems: PackedStringArray = PackedStringArray()
static var _loaded := false

var side := SIDE_ENEMY
var ship_name := ""
var ship_type := ""
var temper := ""
## 头船：敌方第一艘 / 我方旗舰。它出事，僚船按 lead_* 吃传染
var lead := false
## 号令 0–1：我方 = 武力 / 100，敌船按 captain_force 折；压惊、重整都看它，主将倒下后压到 command.after_down
var command := 0.5
var start_value := 60.0
var value := 60.0
var state := STEADY
var crew_start := 0
var crew := 0
var hull_max := 0.0
var hull := 0.0
var captain_down := false
var fire_level := 0.0
var grappled := false
var grappled_as_attacker := false
## -1 = 不知道（不计矢石尽）
var ammo_frac := -1.0
var immobile := false
var surrounded := false
var nearest_foe := INF
## 溃逃中已拉出 rout.escape_distance（挂件判；battle_outcome 按「已退出战斗」算）
var escaped := false
## 本次溃逃已持续的秒数（我方溃逃要满 rout.player_grace_s 才结算）
var routed_for := 0.0
var ever_routed := false
## 医人等级：伤亡压惊
var yiren := 0

var _d: Dictionary = {}
var _live := false
## 距上次压惊或持续消耗（火、陷围…）过了几秒：满 rally.calm_seconds 才回升
var _calm_for := 999.0
var _once_done: Dictionary = {}
var _notes: Array = []


## opts：side（player / enemy）、name、type（ships.json 船型，定风气）、temper（直接指定风气）、morale、crew、
## hull、hull_max（缺省 = hull）、command（0–1）、lead、yiren
func _init(opts: Dictionary = {}) -> void:
	_d = data()
	_live = is_live()
	side = SIDE_PLAYER if str(opts.get("side", SIDE_ENEMY)) == SIDE_PLAYER else SIDE_ENEMY
	ship_name = str(opts.get("name", ""))
	ship_type = str(opts.get("type", ""))
	temper = temper_for(ship_type, str(opts.get("temper", "")))
	lead = bool(opts.get("lead", false))
	command = clampf(float(opts.get("command", 0.5)), 0.0, 1.0)
	start_value = clampf(float(opts.get("morale", 60.0)), 0.0, 100.0)
	value = start_value
	crew_start = maxi(0, int(opts.get("crew", 0)))
	crew = crew_start
	hull = maxf(0.0, float(opts.get("hull", 0.0)))
	hull_max = maxf(hull, float(opts.get("hull_max", hull)))
	yiren = maxi(0, int(opts.get("yiren", 0)))
	# 开战那一刻最差也只是思退：航行士气本就见底的船，挨了第一下才溃，不开局就跑
	state = _band_state(value) if _live else STEADY


# ── 数据 ──────────────────────────────────────────────

static func data() -> Dictionary:
	if not _loaded:
		reload_data()
	return _data


## 重读 json（探针换数据后用）。返回问题清单；非空即整套停用，并各推一行 WARNING。
static func reload_data(path := DATA_PATH) -> PackedStringArray:
	var d: Dictionary = {}
	var errs := PackedStringArray()
	if not FileAccess.file_exists(path):
		errs.append("找不到 %s" % path)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
		else:
			errs.append("%s 不是 JSON 对象" % path)
	return use_data(d, errs)


## 换一份数据（探针喂变异数据用；已建的士气簿不跟着换）。
static func use_data(d: Dictionary, extra := PackedStringArray()) -> PackedStringArray:
	_loaded = true
	_data = d
	_problems = extra.duplicate()
	if extra.is_empty():
		_problems.append_array(data_problems(d))
	for p in _problems:
		push_warning("CombatMorale：%s——海战士气停用（系数 1、不溃不降）" % p)
	return _problems


static func problems() -> PackedStringArray:
	data()
	return _problems


static func is_live() -> bool:
	return not data().is_empty() and _problems.is_empty()


## 数据合规检查（纯函数）：各节键齐、是数、档位由高到低、风气 / 标签 / 短句齐全。
static func data_problems(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if d.is_empty():
		out.append("数据为空")
		return out
	for sec: String in NUMERIC:
		var s: Variant = d.get(sec)
		if not (s is Dictionary):
			out.append("缺 %s 节" % sec)
			continue
		for k: String in NUMERIC[sec]:
			if not _is_num(s.get(k)):
				out.append("%s.%s 缺或不是数" % [sec, k])
	if not out.is_empty():
		return out
	var b: Dictionary = d["bands"]
	var st: Dictionary = d["strike"]
	if not (float(b["steady"]) <= 100.0 and float(b["steady"]) > float(b["shaken"]) and float(b["shaken"]) > float(b["wavering"])
			and float(b["wavering"]) > float(st["line"]) and float(st["line"]) > float(st["collapse_line"])
			and float(st["collapse_line"]) >= 0.0):
		out.append("档位须 100 ≥ bands.steady > shaken > wavering > strike.line > collapse_line ≥ 0")
	if float(d["rout"]["rally_line"]) <= float(b["wavering"]):
		out.append("rout.rally_line 须高于 bands.wavering（否则溃了立刻又整）")
	var fac: Variant = d.get("factors")
	for s: String in STATES:
		var f: Variant = fac.get(s) if fac is Dictionary else null
		for k: String in FACTOR_KEYS:
			if not (f is Dictionary and _is_num(f.get(k))):
				out.append("factors.%s.%s 缺或不是数" % [s, k])
	var tempers: Variant = d.get("tempers")
	if not (tempers is Dictionary) or (tempers as Dictionary).is_empty():
		out.append("缺 tempers 节")
	else:
		for t: String in tempers:
			var tv: Variant = tempers[t]
			for k: String in TEMPER_KEYS:
				if not (tv is Dictionary and _is_num(tv.get(k))):
					out.append("tempers.%s.%s 缺或不是数" % [t, k])
		if not tempers.has(str(d.get("temper_default", ""))):
			out.append("temper_default 不在 tempers 里")
		var tt: Variant = d.get("type_temper")
		if tt is Dictionary:
			for ty: String in tt:
				if not tempers.has(str(tt[ty])):
					out.append("type_temper.%s → %s 不在 tempers 里" % [ty, str(tt[ty])])
		else:
			out.append("缺 type_temper 节")
		var at: Variant = d.get("ai_profile_temper", {})
		if at is Dictionary:
			for prof: String in at:
				if not tempers.has(str(at[prof])):
					out.append("ai_profile_temper.%s → %s 不在 tempers 里" % [prof, str(at[prof])])
		else:
			out.append("ai_profile_temper 须是字典")
	var sides: Variant = d.get("sides")
	for sd: String in [SIDE_PLAYER, SIDE_ENEMY]:
		var sv: Variant = sides.get(sd) if sides is Dictionary else null
		if not (sv is Dictionary and _is_num(sv.get("strike_offset")) and sv.get("captain_can_fall") is bool):
			out.append("sides.%s 须有 strike_offset（数）与 captain_can_fall（真假）" % sd)
	for pair: Array in [["labels", STATES], ["causes", CAUSES]]:
		var tbl: Variant = d.get(pair[0])
		for k: String in pair[1]:
			if not (tbl is Dictionary and str(tbl.get(k, "")).strip_edges() != ""):
				out.append("%s.%s 缺文案" % [pair[0], k])
	var hud: Variant = d.get("hud")
	if not (hud is Dictionary and str(hud.get("prefix", "")).strip_edges() != ""):
		out.append("hud.prefix 缺文案")
	var notes: Variant = d.get("notes")
	for sd: String in [SIDE_PLAYER, SIDE_ENEMY]:
		var nv: Variant = notes.get(sd) if notes is Dictionary else null
		var kinds: Array = NOTE_KINDS + (NOTE_KINDS_ENEMY if sd == SIDE_ENEMY else [])
		for k: String in kinds:
			if not (nv is Dictionary and str(nv.get(k, "")).strip_edges() != ""):
				out.append("notes.%s.%s 缺文案" % [sd, k])
	return out


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and not is_nan(float(v)) and not is_inf(float(v))


static func _num(sec: String, key: String, fallback := 0.0) -> float:
	var s: Variant = data().get(sec)
	if s is Dictionary and _is_num(s.get(key)):
		return float(s[key])
	return fallback


static func _text(sec: String, key: String) -> String:
	var s: Variant = data().get(sec)
	return str(s.get(key, "")) if s is Dictionary else ""


## 船型 → 风气（商船水手 / 海寇 / 水军）；explicit 在 tempers 里就用它
static func temper_for(type_id: String, explicit := "") -> String:
	var tempers: Variant = data().get("tempers")
	if not (tempers is Dictionary):
		return explicit
	if explicit != "" and tempers.has(explicit):
		return explicit
	var tt: Variant = data().get("type_temper")
	if tt is Dictionary and tempers.has(str(tt.get(type_id, ""))):
		return str(tt[type_id])
	return str(data().get("temper_default", ""))


static func temper_name(t: String) -> String:
	var tempers: Variant = data().get("tempers")
	if tempers is Dictionary and tempers.get(t) is Dictionary:
		return str(tempers[t].get("name", t))
	return t


static func state_label(s: String) -> String:
	var t := _text("labels", s)
	return t if t != "" else s


static func cause_label(c: String) -> String:
	var t := _text("causes", c)
	return t if t != "" else c


## 敌将号令：captain_force 1.0 → command.enemy_base，每高 1.0 加 enemy_per_force
static func enemy_command(captain_force: float) -> float:
	return clampf(_num("command", "enemy_base", 0.35) + _num("command", "enemy_per_force", 0.5) * (captain_force - 1.0), 0.0, 1.0)


# ── 建簿 ──────────────────────────────────────────────

static func create(opts: Dictionary = {}) -> _SELF:
	return new(opts)


## 我方一页：fleet 是 Fleet autoload（或同形对象），ship 是海战场景的旗舰（Ship），可空。只读不写。
static func for_player(fleet: Object, ship: Object = null, martial := 50.0, yiren_level := 0) -> _SELF:
	var fs: Dictionary = {}
	if fleet != null and fleet.has_method("flagship"):
		var v: Variant = fleet.call("flagship")
		if v is Dictionary:
			fs = v
	var crew_n := 0
	if fleet != null and fleet.has_method("total_crew"):
		crew_n = int(fleet.call("total_crew"))
	var h := _prop_f(ship, "hull_hp", float(fs.get("durability", 100.0)))
	var hm := _prop_f(ship, "max_hp", float(fs.get("max_durability", h)))
	return new({
		"side": SIDE_PLAYER, "name": str(fs.get("name", "")), "type": str(fs.get("type", "")),
		"morale": _prop_f(fleet, "morale", 60.0), "crew": crew_n, "hull": h, "hull_max": hm,
		"command": clampf(martial / 100.0, 0.0, 1.0), "lead": true, "yiren": yiren_level,
	})


## 敌船一页：ship 是 PirateShip（或同形对象），读 ship_type / ship_name / enemy_morale / crew / hull_hp / captain_force。
static func for_enemy(ship: Object, is_lead := false) -> _SELF:
	return new({
		"side": SIDE_ENEMY, "name": _prop_s(ship, "ship_name", ""), "type": _prop_s(ship, "ship_type", "pirate_boat"),
		"morale": _prop_f(ship, "enemy_morale", 60.0), "crew": int(_prop_f(ship, "crew", 0.0)),
		"hull": _prop_f(ship, "hull_hp", 0.0), "command": enemy_command(_prop_f(ship, "captain_force", 1.0)),
		"lead": is_lead,
	})


## Object.get 在 4.6 只收属性名，缺属性得 null；float(null) 运行期报错——统一走判空
static func _prop_f(o: Object, prop: String, fallback: float) -> float:
	if o == null:
		return fallback
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else fallback


static func _prop_s(o: Object, prop: String, fallback: String) -> String:
	if o == null:
		return fallback
	var v: Variant = o.get(prop)
	return fallback if v == null or str(v).strip_edges() == "" else str(v)


# ── 事件 ──────────────────────────────────────────────

## 压士气。风气（shock_mult）与号令（shock_relief）打折；返回实扣。
func shock(amount: float, _cause := "") -> float:
	if not _live or state == STRUCK or amount <= 0.0:
		return 0.0
	var before := value
	value = clampf(value - amount * _stress_mult(), 0.0, 100.0)
	_calm_for = 0.0
	_evaluate(before - value)
	return before - value


## 提士气（胜报、扑灭火、钩上敌船）。不打折；返回实加。
func lift(amount: float, _cause := "") -> float:
	if not _live or state == STRUCK or amount <= 0.0:
		return 0.0
	var before := value
	value = clampf(value + amount, 0.0, 100.0)
	_evaluate(0.0)
	return value - before


## 船体受创：每 1% 船体 shock.hull_per_pct（按实剩封顶，过量的一炮不多算），过半、剩 strike.hull_critical_frac 各再压一次。
## 头船过半 / 过船将沉线另由挂件传给僚船（lead_hurt）。
func hit_hull(amount: float) -> void:
	var dealt := minf(amount, hull)
	if dealt <= 0.0 or hull_max <= 0.0:
		return
	hull -= dealt
	var amt := dealt / hull_max * 100.0 * _n("shock", "hull_per_pct")
	var left := hull / hull_max
	if left <= 0.5 and _once("hull_half"):
		amt += _n("shock", "hull_half")
	if left <= _n("strike", "hull_critical_frac") and _once("hull_quarter"):
		amt += _n("shock", "hull_quarter")
	shock(amt, "hull")


## 伤亡：每 1% 开战人数 shock.casualty_per_pct（医人每级减 officers.yiren_casualty_relief），折四一、过 strike.heavy_losses_frac
## 各再压一次；折到 command.down_casualty_frac 按主将阵亡代理（将佐死伤殆尽，号令断了）。
func lose_crew(n: int) -> void:
	var dead := mini(n, crew)
	if dead <= 0:
		return
	crew -= dead
	if crew_start <= 0:
		return
	var relief := clampf(1.0 - _n("officers", "yiren_casualty_relief") * float(yiren), 0.2, 1.0)
	var amt := float(dead) / float(crew_start) * 100.0 * _n("shock", "casualty_per_pct") * relief
	var lost := 1.0 - float(crew) / float(crew_start)
	if lost >= 0.25 and _once("casualty_quarter"):
		amt += _n("shock", "casualty_quarter")
	if lost >= _n("strike", "heavy_losses_frac") and _once("casualty_half"):
		amt += _n("shock", "casualty_half")
	shock(amt, "casualties")
	if lost >= _n("command", "down_casualty_frac"):
		fall_captain()


## 失火 0–1：起火压一次，烧着按 drain_per_s.fire × 火势逐秒压，扑灭提一次。
func set_fire(level: float) -> void:
	var lv := clampf(level, 0.0, 1.0)
	var was := fire_level
	fire_level = lv
	if lv > 0.0 and was <= 0.0:
		shock(_n("shock", "fire_start"), "fire")
	elif lv <= 0.0 and was > 0.0:
		lift(_n("lift", "fire_out"), "fire_out")


## 矢石余量 0–1（负数 = 不知道）
func set_ammo(frac: float) -> void:
	ammo_frac = -1.0 if frac < 0.0 else clampf(frac, 0.0, 1.0)
	_evaluate(0.0)


## 钩舷：被钩的一方压一次、钩着逐秒压、算降幡压力；钩人的一方按风气 elan 提一次（跳帮争先）。
func grapple(as_attacker := false) -> void:
	if grappled:
		return
	grappled = true
	grappled_as_attacker = as_attacker
	if as_attacker:
		lift(_n("lift", "boarder_elan") * _temper_n("elan", 1.0), "board")
	else:
		shock(_n("shock", "grappled"), "grappled")


func release() -> void:
	grappled = false
	grappled_as_attacker = false
	_evaluate(0.0)


## 一场白刃分出胜负：胜提、败压；守方丢了甲板（败且非进攻方）按主将阵亡代理，士气低于 strike.board_lost_line 当场降幡。
func boarding_result(won: bool, as_attacker: bool) -> void:
	grappled = false
	grappled_as_attacker = false
	if won:
		lift(_n("lift", "boarding_won"), "board_won")
		return
	shock(_n("shock", "boarding_lost"), "board_lost")
	if not as_attacker:
		fall_captain()
		if _live and state != STRUCK and value < _n("strike", "board_lost_line"):
			_set_state(STRUCK)


## 主将倒下（实有主将模型的接线方直接调；没有的由伤亡 / 失甲板代理）。我方默认不倒（sides.player.captain_can_fall）。
func fall_captain() -> void:
	if not _live or captain_down or not _side_bool("captain_can_fall") or state == STRUCK:
		return
	captain_down = true
	var amt := _n("command", "captain_down_shock") * _temper_n("captain_mult", 1.0) \
		* (_n("command", "captain_down_base") + _n("command", "captain_down_command") * command)
	command = minf(command, _n("command", "after_down"))
	_note("captain_down")
	shock(amt, "captain_down")


## 看见别船出事：contagion 节的 kind 压（僚船沉 / 降 / 溃 / 被夺，头船出事更重），cheer 节的 kind 提（敌船沉 / 降 / 溃 / 被夺）。
func witness(kind: String) -> void:
	if not _live or state == STRUCK:
		return
	var bad: Variant = _d.get("contagion")
	var good: Variant = _d.get("cheer")
	if bad is Dictionary and bad.has(kind):
		shock(float(bad[kind]), kind)
		if kind.begins_with("lead_") and kind != "lead_hurt":
			_note("lead_lost")
	elif good is Dictionary and good.has(kind):
		lift(float(good[kind]), kind)


## 溃逃中拉出了 rout.escape_distance：记一句，battle_outcome 按已退出战斗算
func mark_escaped() -> void:
	if escaped or not is_routing():
		return
	escaped = true
	_note("escaped")


## 每帧：更新情势，逐秒压（火、陷围、矢石尽 / 将尽、被钩、舵篷毁）；既无压惊、又无这些消耗满 rally.calm_seconds，才按号令回升到开战时的底数。
## 溃逃中的要离最近的敌船 rout.rally_distance 以外才回升。
func tick(delta: float, ctx: Dictionary = {}) -> void:
	if not _live or state == STRUCK or delta <= 0.0:
		return
	if ctx.has("surrounded"):
		surrounded = bool(ctx["surrounded"])
	if ctx.has("nearest_foe"):
		nearest_foe = float(ctx["nearest_foe"])
	if ctx.has("immobile"):
		immobile = bool(ctx["immobile"])
	if ctx.has("ammo_frac"):
		ammo_frac = -1.0 if float(ctx["ammo_frac"]) < 0.0 else clampf(float(ctx["ammo_frac"]), 0.0, 1.0)
	if ctx.has("fire_level") and float(ctx["fire_level"]) >= 0.0:
		set_fire(float(ctx["fire_level"]))
		if state == STRUCK:
			return
	if state == ROUTING:
		routed_for += delta
	var drain := _n("drain_per_s", "fire") * fire_level
	if surrounded:
		drain += _n("drain_per_s", "surrounded")
	if ammo_frac >= 0.0:
		if ammo_frac <= AMMO_OUT_EPS:
			drain += _n("drain_per_s", "ammo_out")
		elif ammo_frac < _n("drain_per_s", "ammo_low_frac"):
			drain += _n("drain_per_s", "ammo_low")
	if grappled and not grappled_as_attacker:
		drain += _n("drain_per_s", "grappled")
	if immobile:
		drain += _n("drain_per_s", "immobile")
	if drain > 0.0:
		value = clampf(value - drain * _stress_mult() * delta, 0.0, 100.0)
		_calm_for = 0.0
	else:
		_calm_for += delta
	if drain <= 0.0 and _calm_for >= _n("rally", "calm_seconds") and value < start_value \
			and (state != ROUTING or nearest_foe >= _n("rout", "rally_distance")):
		var rate := _n("rally", "per_s") * (_n("rally", "command_base") + command)
		value = minf(start_value, value + rate * delta)
	_evaluate(0.0)


# ── 判定 ──────────────────────────────────────────────

## 溃逃线：bands.wavering + 风气 rout_offset，夹在降幡线与动摇线之间
func rout_line() -> float:
	var ln := _n("bands", "wavering") + _temper_n("rout_offset", 0.0)
	return clampf(ln, _n("strike", "line") + 1.0, _n("bands", "shaken") - 1.0)


func strike_line() -> float:
	return _n("strike", "line")


## 降幡要凑够的压力：基数 + 风气（海寇怕降了也是死，要多一分）+ 阵营（主角在船，擅降者少）
func strike_need() -> float:
	return _n("strike", "pressure_need") + _temper_n("strike_offset", 0.0) + _side_n("strike_offset")


func pressure_causes() -> PackedStringArray:
	var out := PackedStringArray()
	if surrounded:
		out.append("surrounded")
	if ammo_frac >= 0.0 and ammo_frac <= AMMO_OUT_EPS:
		out.append("ammo_out")
	if captain_down:
		out.append("captain_down")
	if grappled and not grappled_as_attacker:
		out.append("grappled")
	if hull_max > 0.0 and hull / hull_max <= _n("strike", "hull_critical_frac"):
		out.append("hull_critical")
	if crew_start > 0 and float(crew) / float(crew_start) <= 1.0 - _n("strike", "heavy_losses_frac"):
		out.append("heavy_losses")
	if fire_level > 0.0:
		out.append("on_fire")
	if immobile:
		out.append("immobile")
	return out


func pressure() -> float:
	var p := 0.0
	for c in pressure_causes():
		p += _n("pressure", c)
	return p


## 还走得了：没被钩、舵篷没毁。陷围只算降幡压力与逐秒消耗——两面受敌仍可转篷夺路
func can_flee() -> bool:
	return not grappled and not immobile


func _evaluate(last_shock: float) -> void:
	if not _live or state == STRUCK:
		return
	if value <= _n("strike", "collapse_line") and not can_flee():
		_set_state(STRUCK)
	elif value < strike_line() and pressure() >= strike_need():
		_set_state(STRUCK)
	elif state == ROUTING:
		if value >= _n("rout", "rally_line") and nearest_foe >= _n("rout", "rally_distance"):
			_set_state(WAVERING, "rally")
	elif value < rout_line():
		_set_state(ROUTING)
	elif last_shock >= _n("rout", "panic_shock") and value < _n("rout", "panic_line"):
		_set_state(ROUTING, "panic")
	else:
		var target := _band_state(value)
		if _rank(target) > _rank(state):
			_set_state(target)
		elif _rank(target) < _rank(state):
			# 往好里走要多过 bands.hysteresis 才算，免得在线上来回跳
			var up: String = STATES[_rank(state) - 1]
			var hy := _n("bands", "hysteresis")
			if value >= _band_floor(up) + hy:
				_set_state(_band_state(value - hy))


## 按士气落如常 / 动摇 / 思退（溃逃、降幡另判）
func _band_state(v: float) -> String:
	if v >= _n("bands", "steady"):
		return STEADY
	if v >= _n("bands", "shaken"):
		return SHAKEN
	return WAVERING


func _band_floor(s: String) -> float:
	if s == STEADY:
		return _n("bands", "steady")
	if s == SHAKEN:
		return _n("bands", "shaken")
	return rout_line()


static func _rank(s: String) -> int:
	return maxi(0, STATES.find(s))


func _set_state(s: String, kind := "") -> void:
	if s == state:
		return
	var old := state
	state = s
	if s == ROUTING:
		ever_routed = true
		routed_for = 0.0
	var k := kind
	if k == "":
		if _rank(s) > _rank(old):
			k = "to_" + s
		elif s == STEADY:
			k = "steady_again"
		else:
			k = "recover"
	_note(k, old)


## 记一笔：state_changed 看 from / to，noted 看 text（recover 没有句子）
func _note(kind: String, old := "") -> void:
	var notes: Variant = _d.get("notes")
	var nv: Variant = notes.get(side) if notes is Dictionary else null
	var text := str(nv.get(kind, "")) if nv is Dictionary else ""
	_notes.append({"kind": kind, "from": old if old != "" else state, "to": state, "text": text, "value": value})


# ── 查询 ──────────────────────────────────────────────

func is_routing() -> bool:
	return state == ROUTING


func has_struck() -> bool:
	return state == STRUCK


## 溃了或降了：不再算在打的船
func is_broken() -> bool:
	return state == ROUTING or state == STRUCK


func label() -> String:
	return state_label(state)


func factor(kind: String) -> float:
	if not _live:
		return 1.0
	var fac: Variant = _d.get("factors")
	var f: Variant = fac.get(state) if fac is Dictionary else null
	return float(f.get(kind, 1.0)) if f is Dictionary else 1.0


## 射速 / 准头倍率（装填时间除以它）
func fire_factor() -> float:
	return factor("fire")


## 白刃倍率，与 Fleet.morale_factor() 同量纲：(melee.base + melee.span × 士气 / 100) × 本档 melee
func melee_factor() -> float:
	if not _live:
		return INERT_MELEE_BASE + INERT_MELEE_SPAN * value / 100.0
	return (_n("melee", "base") + _n("melee", "span") * value / 100.0) * factor("melee")


## 帆力倍率：溃逃满篷而走，降幡落帆停船
func sail_factor() -> float:
	return factor("sail")


## 作进攻方肯不肯跳帮：boarding.willing_floor 以下 0、willing_full 以上 1；溃逃 / 降幡 0
func board_chance() -> float:
	if not _live:
		return 1.0
	if is_broken():
		return 0.0
	var lo := _n("boarding", "willing_floor")
	var hi := maxf(lo + 1.0, _n("boarding", "willing_full"))
	return clampf((value - lo) / (hi - lo), 0.0, 1.0)


## roll ∈ [0, 1)。过了返回 true；不肯时记一句「拒接舷」、号令不行再挫一点，返回 false。
func try_board(roll: float) -> bool:
	if roll < board_chance():
		return true
	_note("boarding_refused")
	shock(_n("shock", "boarding_refused"), "boarding_refused")
	return false


## 被钩时砍缆脱钩的机会（每次尝试）：士气过 boarding.cut_grapple_floor 才有，满士气到 cut_grapple_max；溃兵、降船不砍
func cut_grapple_chance() -> float:
	if not _live or is_broken():
		return 0.0
	var lo := _n("boarding", "cut_grapple_floor")
	return clampf((value - lo) / maxf(1.0, 100.0 - lo), 0.0, 1.0) * _n("boarding", "cut_grapple_max")


## 降了的船接舷即得，不必白刃
func yields_to_boarding() -> bool:
	return state == STRUCK


func take_notes() -> Array:
	var out := _notes
	_notes = []
	return out


func hud_text() -> String:
	var prefix := _text("hud", "prefix")
	var s := "%s　%d　%s" % [prefix if prefix != "" else "士气", int(round(value)), label()]
	var bits := PackedStringArray()
	for c in pressure_causes():
		bits.append(cause_label(c))
	return s if bits.is_empty() else s + "　" + "·".join(bits)


func snapshot() -> Dictionary:
	return {
		"side": side, "name": ship_name, "temper": temper, "value": int(round(value)), "start": int(round(start_value)),
		"state": state, "label": label(), "fire": fire_factor(), "melee": melee_factor(), "sail": sail_factor(),
		"pressure": pressure(), "causes": pressure_causes(), "board_chance": board_chance(),
		"routing": is_routing(), "struck": has_struck(), "escaped": escaped, "captain_down": captain_down, "live": _live,
	}


## 战后回写航行士气的建议值（调用方决定写不写 Fleet.morale）：战中涨落按 carry.ratio 带回，溃过、降过另扣
func carry_to_voyage(voyage_before: int) -> int:
	if not _live:
		return voyage_before
	var dv := (value - start_value) * _n("carry", "ratio")
	if ever_routed:
		dv -= _n("carry", "routed")
	if state == STRUCK:
		dv -= _n("carry", "struck")
	return clampi(voyage_before + int(round(dv)), 0, 100)


# ── 内部取数 ──────────────────────────────────────────

func _n(sec: String, key: String) -> float:
	var s: Variant = _d.get(sec)
	if s is Dictionary and _is_num(s.get(key)):
		return float(s[key])
	return 0.0


func _temper_n(key: String, fallback: float) -> float:
	var tempers: Variant = _d.get("tempers")
	var t: Variant = tempers.get(temper) if tempers is Dictionary else null
	if t is Dictionary and _is_num(t.get(key)):
		return float(t[key])
	return fallback


func _side_n(key: String) -> float:
	var sides: Variant = _d.get("sides")
	var s: Variant = sides.get(side) if sides is Dictionary else null
	if s is Dictionary and _is_num(s.get(key)):
		return float(s[key])
	return 0.0


func _side_bool(key: String) -> bool:
	var sides: Variant = _d.get("sides")
	var s: Variant = sides.get(side) if sides is Dictionary else null
	return s is Dictionary and s.get(key) == true


## 惊扰打折：风气 shock_mult ×（1 − command.shock_relief × 号令）
func _stress_mult() -> float:
	return maxf(0.0, _temper_n("shock_mult", 1.0) * (1.0 - _n("command", "shock_relief") * command))


func _once(key: String) -> bool:
	if _once_done.has(key):
		return false
	_once_done[key] = true
	return true


# ── 判定（纯函数）─────────────────────────────────────

## at 处的船算不算被围：surround.radius 内有 crowd 艘以上敌船，或两艘分处两舷（方位夹角 ≥ spread_deg）；
## 半径内有友船且敌船不比友船多两艘以上，不算（有僚船策应）。
static func is_surrounded(at: Vector2, foes: Array, friends: Array = []) -> bool:
	var r := _num("surround", "radius", 0.0)
	if r <= 0.0:
		return false
	var near: Array = []
	for f in foes:
		if f is Vector2 and (f as Vector2).distance_to(at) <= r:
			near.append(f)
	var allies := 0
	for f in friends:
		if f is Vector2 and (f as Vector2).distance_to(at) <= r:
			allies += 1
	if allies > 0 and near.size() < allies + 2:
		return false
	if near.size() >= int(_num("surround", "crowd", 3.0)):
		return true
	if near.size() < 2:
		return false
	var spread := deg_to_rad(_num("surround", "spread_deg", 180.0))
	for i in range(near.size()):
		for j in range(i + 1, near.size()):
			var a := ((near[i] as Vector2) - at).angle()
			var b := ((near[j] as Vector2) - at).angle()
			if absf(angle_difference(a, b)) >= spread:
				return true
	return false


## 海战该不该因士气收场。player 可空（不判我方）；enemies 是还在场的敌船士气簿（沉了、被夺走的不放进来）。
## 我方降幡 → lose；我方溃逃满 rout.player_grace_s → flee（flee_ok 由调用方掷）；在场敌船个个降了或遁出 → win。其余 {}。
static func battle_outcome(player: _SELF, enemies: Array) -> Dictionary:
	if player != null and player.has_struck():
		return {"outcome": "lose", "data": {"struck": true, "morale_verdict": "player_struck"}}
	if player != null and player.is_routing() and player.routed_for >= _num("rout", "player_grace_s", 0.0):
		return {"outcome": "flee", "data": {"rout": true, "morale_verdict": "player_rout"}}
	var n_struck := 0
	var n_fled := 0
	var types: Array = []
	for e in enemies:
		if e == null:
			continue
		if e.has_struck():
			n_struck += 1
			types.append(e.ship_type)
		elif e.is_routing() and e.escaped:
			n_fled += 1
		else:
			return {}
	if n_struck + n_fled == 0:
		return {}
	var v := "enemy_broken"
	if n_fled == 0:
		v = "enemy_struck"
	elif n_struck == 0:
		v = "enemy_fled"
	return {"outcome": "win", "data": {"enemy_struck": n_struck, "enemy_fled": n_fled, "struck_types": types, "morale_verdict": v}}


## 敌将 AI 的士气裁决钩子（lane combat07 EnemyCaptainAI.HOOKS.morale_verdict：静态、一个 Dictionary 形参、回字符串）。
## ctx：morale（0–100）、hull（船体余比）、crew_frac（人数余比）、ammo（矢石余比，负数 / 缺 = 不知道）、can_escape（走得脱）、
## state（AI 当前状态）、profile（AI 档案 pirate / patrol / default，按 data ai_profile_temper 折风气）。
## 按本件同一套线判：降幡 → "strike"；溃逃 → "rout"（已在脱离、士气没回到 rout.rally_line 也算）；都不是返回 ""，AI 照它自带的判。
## 走不脱（can_escape 假）按「陷围」计降幡压力、也按走不了计崩溃线。停用时一律 ""。
static func captain_verdict(ctx: Dictionary) -> String:
	if not is_live():
		return ""
	var state_now := str(ctx.get("state", ""))
	if state_now == "strike":
		return "strike"
	var map: Variant = data().get("ai_profile_temper")
	var t := str(map.get(str(ctx.get("profile", "default")), "")) if map is Dictionary else ""
	var s := create({"side": SIDE_ENEMY, "temper": t, "morale": float(ctx.get("morale", 60.0)), "hull": 100.0, "crew": 100})
	s.hull = 100.0 * clampf(float(ctx.get("hull", 1.0)), 0.0, 1.0)
	s.crew = int(round(100.0 * clampf(float(ctx.get("crew_frac", 1.0)), 0.0, 1.0)))
	var ammo := float(ctx.get("ammo", -1.0))
	s.ammo_frac = -1.0 if ammo < 0.0 else clampf(ammo, 0.0, 1.0)
	var trapped: bool = ctx.get("can_escape", true) == false
	s.surrounded = trapped
	if s.value <= _num("strike", "collapse_line") and trapped:
		return "strike"
	if s.value < s.strike_line() and s.pressure() >= s.strike_need():
		return "strike"
	if s.value < s.rout_line() or (state_now == "disengage" and s.value < _num("rout", "rally_line")):
		return "rout"
	return ""


## 挂到海战场景（WorldMap）下，返回挂件；host 为空或已释放返回 null。
static func attach(host: Node) -> Tracker:
	if host == null or not is_instance_valid(host):
		return null
	var t := Tracker.new()
	t.name = "CombatMorale"
	t.host = host
	host.add_child(t)
	return t


# ── 观战挂件 ──────────────────────────────────────────

## 只读轮询的观战挂件：见头注「三」。节点名、属性名的口径同 WorldMap（敌船节点名 PirateShip 前缀、hull_hp > 0 算在场）。
class Tracker extends Node:
	signal state_changed(who: Node, old_state: String, new_state: String)
	signal noted(who: Node, kind: String, text: String)
	signal verdict(outcome: String, data: Dictionary)

	## 敌船 enemy_morale 改写成战中士气（PirateShip.combat_strength 读它）
	var write_enemy_morale := true
	## 我方溃逃 / 降幡也出 verdict
	var decide_player := true
	## 我方溃逃弃战的甩脱机会 = /root/Voyage.flee_success_chance() × rout.flee_factor，用它掷；探针可在挂上前设 seed
	var rng := RandomNumberGenerator.new()
	var host: Node = null
	var fleet: Object = null
	var _player: _SELF = null
	var _player_ref: WeakRef = null
	var _last_hull := -1.0
	var _last_crew := -1
	## instance_id → {ref, sheet, hull, crew, grappled, node_name}
	var _enemies: Dictionary = {}
	var _order: Array = []
	var _reports: Dictionary = {}
	## 离场的敌船：{sheet, how（sunk / captured / fled / removed）, node_name}
	var gone: Array = []
	var _verdict_sent := false

	func _ready() -> void:
		if host == null:
			host = get_parent()
		add_to_group(_SELF.GROUP)

	func _physics_process(delta: float) -> void:
		if host == null or not is_instance_valid(host) or host.get("resolved") == true:
			return
		if host.get("combat_mode") == false:
			return
		_scan()
		_update(delta)
		_publish()
		_check_verdict()

	## 我方那页（旗舰还没进场时为空）
	func player_sheet() -> _SELF:
		return _player

	## 某船那页：敌船节点或我方旗舰节点
	func sheet_of(node: Object) -> _SELF:
		if node == null:
			return null
		if _player_ref != null and _player_ref.get_ref() == node:
			return _player
		var e: Variant = _enemies.get(node.get_instance_id())
		return e["sheet"] if e is Dictionary else null

	## 还在场的敌船士气簿（登记顺序）
	func enemy_sheets() -> Array:
		var out: Array = []
		for id in _order:
			out.append(_enemies[id]["sheet"])
		return out

	## 推入船节点上没有的情势：fire_level（0–1）、ammo_frac（0–1）、immobile（真假）、captain_down（真即倒）
	func report(node: Object, key: String, v: Variant) -> void:
		if node == null:
			return
		if key == "captain_down":
			var s := sheet_of(node)
			if s != null and v == true:
				s.fall_captain()
			return
		var id := node.get_instance_id()
		if not _reports.has(id):
			_reports[id] = {}
		_reports[id][key] = v

	## 我方按 G 之前问一声：肯跳帮返回 ""；不肯返回拒接舷的纪实句（已记挫，noted 也发了）。
	func player_boarding_check() -> String:
		if _player == null or _player.try_board(rng.randf()):
			return ""
		var why := ""
		for n in _player.take_notes():
			_emit_note(_player_node(), n)
			if n["kind"] == "boarding_refused":
				why = str(n["text"])
		return why

	func hud_line() -> String:
		return _player.hud_text() if _player != null else ""

	## 当前该不该收场（不发信号）
	func outcome() -> Dictionary:
		return _SELF.battle_outcome(_player if decide_player else null, enemy_sheets())

	func _player_node() -> Node:
		return _player_ref.get_ref() as Node if _player_ref != null else null

	func _root_node(n: String) -> Node:
		return get_node_or_null("/root/" + n) if is_inside_tree() else null

	func _scan() -> void:
		if fleet == null:
			fleet = _root_node("Fleet")
		var ship: Variant = host.get("ship")
		if not (ship is Node2D):
			ship = host.get_node_or_null("Ship")
		if _player == null and ship is Node2D and is_instance_valid(ship):
			var crew_node := _root_node("Crew")
			var yiren_lv := 0
			if crew_node != null and crew_node.has_method("level_of"):
				yiren_lv = int(crew_node.call("level_of", "yiren"))
			_player = _SELF.for_player(fleet, ship, _SELF._prop_f(_root_node("GameState"), "martial", 50.0), yiren_lv)
			_player_ref = weakref(ship)
			_last_hull = _SELF._prop_f(ship, "hull_hp", 0.0)
			_last_crew = _fleet_crew()
		var fresh: Array = []
		for c in host.get_children():
			if c is Node2D and String(c.name).begins_with("PirateShip") and not _enemies.has(c.get_instance_id()) \
					and not c.is_queued_for_deletion() and _SELF._prop_f(c, "hull_hp", 0.0) > 0.0:
				fresh.append(c)
		fresh.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		for c: Node2D in fresh:
			# 头船 = 第一艘登记的敌船（WorldMap 刷船名 PirateShip_1 起）
			var sheet := _SELF.for_enemy(c, _order.is_empty() and gone.is_empty())
			var id := c.get_instance_id()
			_enemies[id] = {"ref": weakref(c), "sheet": sheet, "hull": sheet.hull, "crew": sheet.crew,
				"grappled": c.get("grappled") == true, "node_name": String(c.name)}
			_order.append(id)
			# 击沉的船多在挂件下一帧前就释放了：离树那一刻记下船体与钩舷，才分得清沉、被夺、收走（绑 id，不捕获节点）
			c.tree_exiting.connect(_on_enemy_exiting.bind(id))

	func _fleet_crew() -> int:
		if fleet != null and fleet.has_method("total_crew"):
			return int(fleet.call("total_crew"))
		return -1

	func _update(delta: float) -> void:
		var ship: Node2D = null
		if _player_ref != null:
			ship = _player_ref.get_ref() as Node2D
		var foes: Array = []
		var nearest := INF
		# 敌船：离场的先结（沉 / 被夺 / 遁出后被收走），在场的逐船喂差值
		for id in _order.duplicate():
			var e: Dictionary = _enemies[id]
			var n: Node2D = e["ref"].get_ref() as Node2D
			var sheet: _SELF = e["sheet"]
			var hp := _SELF._prop_f(n, "hull_hp", 0.0) if n != null else 0.0
			if n == null or n.is_queued_for_deletion() or hp <= 0.0:
				if n != null:
					_on_enemy_exiting(id)
				_retire(id, e, _how_gone(e, sheet))
				continue
			if hp < float(e["hull"]):
				var before: float = sheet.hull / sheet.hull_max if sheet.hull_max > 0.0 else 1.0
				sheet.hit_hull(float(e["hull"]) - hp)
				var after: float = sheet.hull / sheet.hull_max if sheet.hull_max > 0.0 else 1.0
				var crit := _SELF._num("strike", "hull_critical_frac", 0.25)
				if sheet.lead and ((before > 0.5 and after <= 0.5) or (before > crit and after <= crit)):
					_broadcast_allies(id, "lead_hurt")
			e["hull"] = hp
			var cn := int(_SELF._prop_f(n, "crew", float(e["crew"])))
			if cn < int(e["crew"]):
				sheet.lose_crew(int(e["crew"]) - cn)
			elif cn > int(e["crew"]):
				sheet.crew += cn - int(e["crew"])
			e["crew"] = cn
			var g: bool = n.get("grappled") == true
			if g and not bool(e["grappled"]):
				# 谁先抛钩谁作攻方（lane w53-2，同 WorldMap._board_enemy）：敌船先钩（boarding_initiator）敌攻我守，本队按 G 钩上我攻敌守
				var enemy_first: bool = n.get("boarding_initiator") == true
				e["enemy_first"] = enemy_first
				sheet.grapple(enemy_first)
				if _player != null:
					_player.grapple(not enemy_first)
			elif not g and bool(e["grappled"]):
				# 钩着的船还在、钩却松了：攻方白刃不利、两船分开（WorldMap._board_enemy 攻方败的那一支）——
				# 本队先钩是我败敌守住，敌船先钩是敌败我守住
				var ef := bool(e.get("enemy_first", false))
				sheet.boarding_result(not ef, ef)
				if _player != null:
					_player.boarding_result(ef, not ef)
			e["grappled"] = g
			var d := n.global_position.distance_to(ship.global_position) if ship != null else INF
			var ctx := {"nearest_foe": d, "surrounded": false}
			_merge_inputs(n, ctx)
			sheet.tick(delta, ctx)
			if sheet.is_routing() and d >= _SELF._num("rout", "escape_distance", INF):
				sheet.mark_escaped()
			if not sheet.is_broken():
				foes.append(n.global_position)
				nearest = minf(nearest, d)
		# 我方
		if _player != null and ship != null:
			var hp := _SELF._prop_f(ship, "hull_hp", _last_hull)
			if hp < _last_hull:
				_player.hit_hull(_last_hull - hp)
			_last_hull = hp
			var cn := _fleet_crew()
			if cn >= 0 and _last_crew >= 0:
				if cn < _last_crew:
					_player.lose_crew(_last_crew - cn)
				elif cn > _last_crew:
					_player.crew += cn - _last_crew  # 夺来的船带着水手并入，不算提振
			_last_crew = cn
			var ctx := {"nearest_foe": nearest, "surrounded": _SELF.is_surrounded(ship.global_position, foes, [])}
			_merge_inputs(ship, ctx)
			_player.tick(delta, ctx)
		_drain_notes()

	func _on_enemy_exiting(id: int) -> void:
		var e: Variant = _enemies.get(id)
		if not (e is Dictionary):
			return
		var n: Object = e["ref"].get_ref()
		if n != null:
			e["final_hull"] = _SELF._prop_f(n, "hull_hp", 0.0)
			e["final_grappled"] = n.get("grappled") == true

	## 离场缘由：船体见底 = 沉；钩着时收走 = 被夺（WorldMap 白刃胜后 queue_free，船体仍在）；遁出后收走 = 遁；其余 = 移除
	func _how_gone(e: Dictionary, sheet: _SELF) -> String:
		if float(e.get("final_hull", e["hull"])) <= 0.0:
			return "sunk"
		if e.get("final_grappled", e["grappled"]) == true:
			return "captured"
		return "fled" if sheet.escaped else "removed"

	## 船节点上的情势属性 + report 推进来的，并进 ctx
	func _merge_inputs(n: Object, ctx: Dictionary) -> void:
		var fl: Variant = n.get("fire_level")
		if fl is float or fl is int:
			ctx["fire_level"] = float(fl)
		elif n.get("on_fire") is bool:
			ctx["fire_level"] = 1.0 if n.get("on_fire") == true else 0.0
		var af: Variant = n.get("ammo_frac")
		if af is float or af is int:
			ctx["ammo_frac"] = float(af)
		else:
			var a: Variant = n.get("ammo")
			var am: Variant = n.get("ammo_max")
			if (a is float or a is int) and (am is float or am is int) and float(am) > 0.0:
				ctx["ammo_frac"] = float(a) / float(am)
		if n.get("immobile") is bool:
			ctx["immobile"] = n.get("immobile") == true
		var r: Variant = _reports.get(n.get_instance_id())
		if r is Dictionary:
			for k in r:
				ctx[k] = r[k]

	## 敌船离场（how 见 _how_gone）：沉、被夺传给僚船与我方；遁、移除在溃逃那一刻已传过；
	## 降过的船那一刻也已传过，再被夺 / 击沉不重传（我方收降船另记 foe_captured）
	func _retire(id: int, e: Dictionary, how: String) -> void:
		var sheet: _SELF = e["sheet"]
		var was_struck := sheet.has_struck()
		_enemies.erase(id)
		_order.erase(id)
		gone.append({"sheet": sheet, "how": how, "node_name": e["node_name"]})
		if _player != null:
			if e.get("final_grappled", e["grappled"]) == true:
				if how == "captured" and not was_struck:
					_player.boarding_result(true, true)
				else:
					_player.release()
			if how == "captured" and was_struck:
				_player.witness("foe_captured")
		if (how == "sunk" or how == "captured") and not was_struck:
			_broadcast_allies(id, ("lead_" if sheet.lead else "ally_") + how)
			if _player != null and how == "sunk":
				_player.witness("foe_sunk")

	func _broadcast_allies(from_id: int, kind: String) -> void:
		for id in _order:
			if id != from_id:
				_enemies[id]["sheet"].witness(kind)

	func _drain_notes() -> void:
		for id in _order.duplicate():
			if not _enemies.has(id):
				continue
			var e: Dictionary = _enemies[id]
			var sheet: _SELF = e["sheet"]
			for n in sheet.take_notes():
				_emit_note(e["ref"].get_ref(), n)
				if n["from"] != n["to"] and n["to"] in [_SELF.ROUTING, _SELF.STRUCK]:
					var bad := "struck" if n["to"] == _SELF.STRUCK else "routed"
					_broadcast_allies(id, ("lead_" if sheet.lead and bad == "struck" else "ally_") + bad)
					if _player != null:
						_player.witness("foe_" + bad)
		if _player != null:
			for n in _player.take_notes():
				_emit_note(_player_node(), n)
		# 传染带出的新转折：排在后面的船当帧发，排在前面的下一帧发

	func _emit_note(who: Variant, n: Dictionary) -> void:
		var node: Node = who as Node if who is Node else null
		if n["from"] != n["to"]:
			state_changed.emit(node, str(n["from"]), str(n["to"]))
		if str(n["text"]) != "":
			noted.emit(node, str(n["kind"]), str(n["text"]))

	func _publish() -> void:
		for id in _order:
			var e: Dictionary = _enemies[id]
			var n: Node = e["ref"].get_ref() as Node
			if n == null:
				continue
			var sheet: _SELF = e["sheet"]
			n.set_meta(_SELF.META_KEY, sheet.snapshot())
			if write_enemy_morale and n.get("enemy_morale") is int:
				n.set("enemy_morale", int(round(sheet.value)))
		var ship := _player_node()
		if _player != null and ship != null:
			ship.set_meta(_SELF.META_KEY, _player.snapshot())

	func _check_verdict() -> void:
		if _verdict_sent:
			return
		var out := outcome()
		if out.is_empty():
			return
		var dat: Dictionary = out["data"]
		if str(out["outcome"]) == "flee":
			var chance := 0.5
			var voyage := _root_node("Voyage")
			if voyage != null and voyage.has_method("flee_success_chance"):
				chance = float(voyage.call("flee_success_chance"))
			dat["flee_ok"] = rng.randf() < chance * _SELF._num("rout", "flee_factor", 1.0)
		_verdict_sent = true
		verdict.emit(str(out["outcome"]), dat)
