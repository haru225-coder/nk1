## 接舷白刃结算（lane combat05）：抛钩 → 接舷 → 矢石 → 跳帮 → 甲板多合 → 夺船 / 俘获 / 击退 / 脱钩 / 落空。
## 纯静态：不碰 autoload、不建节点；读节点的几支（side_from_* / approach_from_nodes / from_battle）只读传进来的对象。
## ctx.seed 非 0 则整场逐合可复现（探针、演示、回放用）；0 或缺省随机。
##
## 宋元近海口径（按《武经总要》水战篇与崖山、唐岛诸役记载归纳，数值是游戏折算）：
##   抛钩：挠钩手掷钩索，至少 HOOKS_TO_HOLD 具咬住船舷才算钩牢。每具的咬舷率按相对速度、舷距、风力、浪、
##         上下风、往高舷上抛、守方拒竿（钩拒之「拒」）逐项折算——所以并舷同速、居上风、风平浪静最好钩。
##   矢石：跳帮前弓弩对射，居高者俯射占便宜；灰瓶（石灰迷目）顺风才好使，逆风反扑自家。火器稀少，不当主力。
##   跳帮：攻方留一成半人手（至少 KEEP_MIN）看帆掌舵，其余跳帮；往高舷上攀先折人手，浪大落水多。
##   甲板：守船上分四段 舷边 → 舷腰 → 桅下（帅旗）→ 舵楼。守方倚女墙、居舵楼有地利，敌首在舵楼督战；
##         斩旗敌气大挫，攻上舵楼即夺舵、夺船。攻方被反推过舷边算「战至攻方舷边」（front = -1）。
##   了局：夺船（攻上舵楼；或帅旗已被斩落、守众随后溃散，余众或降或跳海）·
##         俘获（帅旗还在守方就气尽人少，自己降幡弃械，多俘）· 击退（攻方气尽人少，退回本船砍缆）·
##         脱钩（守方仍据舷边时砍缆脱身，或斗满合数两下罢手）· 落空（钩没挂牢）。
##   同一套对攻守双方都成立：敌船来接玩家时把玩家那方当 def 传进来，题签里的「我 / 敌」按 is_player 自动换位。
##
## 接线（WorldMap._board_enemy 归 combat02，本 lane 不改）：
##   var r := MeleeResolve.from_battle(Fleet, ship, enemy)              # 或 resolve(side, side, ctx) 自拼
##   var stage := BoardingStage.play(self, ship, enemy, r)              # 整场题签；旧两拍 begin / resolve 照旧可用
##   Fleet.lose_crew_random(r["att_dead"]); Fleet.morale += r["att_morale_delta"]
##   if r["legacy"] == "win": Fleet.add_ship(...)                       # legacy 按攻方算，折回旧 "win" / "lose"
extends RefCounted

const OUTCOME_CAPTURE := "capture"
const OUTCOME_SURRENDER := "surrender"
const OUTCOME_REPELLED := "repelled"
const OUTCOME_CUT_LOOSE := "cut_loose"
const OUTCOME_HOOK_MISS := "hook_miss"

## 了局题签（BoardingStage 用；两字，同旧「夺船」「脱钩」）
const TITLES := {
	"capture": "夺船",
	"surrender": "俘获",
	"repelled": "击退",
	"cut_loose": "脱钩",
	"hook_miss": "落空",
}

## 守船甲板四段。front = 攻方推到第几段；-1 = 被反推回攻方自家舷边；ZONE_TAKEN = 舵楼已夺
## 逐合记事里 -1 那段按攻方写成「我船舷边」/「敌船舷边」，zone_name() 不分你我给 ZONE_OWN
const ZONES: PackedStringArray = ["舷边", "舷腰", "桅下", "舵楼"]
const ZONE_OWN := "攻方舷边"
const ZONE_FLAG := 2
const ZONE_HELM := 3
const ZONE_TAKEN := 4

## 舷高（尺）与舷上护具，按 ships.json 的 type；表外按 DEFAULT_HULL。
## screen：舷上张生牛皮 / 竹笆为城（海鹘「覆背上左右张生牛皮为城」），挡矢石、拒跳帮，0–1。
const HULLS := {
	"sampan": {"freeboard": 4.0, "screen": 0.0},
	"keel_boat": {"freeboard": 7.0, "screen": 0.0},
	"fu_ship_medium": {"freeboard": 10.0, "screen": 0.1},
	"canton_ship": {"freeboard": 11.0, "screen": 0.1},
	"sea_falcon": {"freeboard": 8.0, "screen": 0.3},
	"pirate_boat": {"freeboard": 5.0, "screen": 0.0},
	"fu_ship_large": {"freeboard": 13.0, "screen": 0.15},
	"divine_ship": {"freeboard": 16.0, "screen": 0.2},
}
const DEFAULT_HULL := {"freeboard": 8.0, "screen": 0.05}

# ── 抛钩 ──
## 每具挠钩的咬舷基率；挠钩手按人头 CREW_PER_HOOK 一具，夹在 HOOKS_MIN–HOOKS_MAX
const HOOK_BASE := 0.5
const HOOKS_MIN := 3
const HOOKS_MAX := 8
const CREW_PER_HOOK := 10
const HOOKS_TO_HOLD := 2
## 相对速度到此（WorldMap 像素 / 秒，满帆约 300）咬舷率折半：钩得住的前提是两船同速并舷
const REL_SPEED_HALF := 260.0
## 同 WorldMap.BOARD_DISTANCE：再远钩索够不着
const BOARD_REACH := 140.0
## 风力过此帆船横摇、帆索乱摆，抛钩渐难（WorldMap 常风 80，骤雨 160–280）
const WIND_CALM := 100.0
## 海况 0 平 / 1 微浪 / 2 中浪 / 3 大浪 / 4 狂涛
const SEA_HOOK := [1.0, 0.95, 0.8, 0.6, 0.4]
const SEA_NAMES: PackedStringArray = ["平", "微浪", "中浪", "大浪", "狂涛"]

# ── 矢石 ──
const VOLLEY_HIT := 0.07
const POTS_PER_VOLLEY := 2
const POT_HIT := 0.5

# ── 跳帮与甲板 ──
const KEEP_BACK := 0.15
const KEEP_MIN := 2
const DEF_KEEP := 0.1
const LEAP_LOSS := 0.03
const ROUNDS_DEFAULT := 6
const ROUNDS_MAX := 10
## 每合伤亡 ≈ 对面有效战力 × LETHALITY（再乘 0.75–1.25 的运气）
const LETHALITY := 0.12
## 一合之内的战阵运气：双方战力各乘 1 ± ROUND_LUCK（人挤在窄甲板上，一刀一枪的偶然比野战大）
const ROUND_LUCK := 0.15
## 一仗的时运：双方战力各乘 exp(N(0, BATTLE_LUCK))，夹在 0.5–2（均势约五五开、强一倍约九成胜）
const BATTLE_LUCK := 0.3
## 跳帮之锐：第一合攻方挑的时机
const SHOCK := 1.15
## 一合折了本段人手的一成，士气掉 MORALE_PER_LOSS / 10；战力占比每高出对面一成，对面再掉 MORALE_OVERMATCH / 10（见势不敌）
const MORALE_PER_LOSS := 60.0
const MORALE_OVERMATCH := 20.0
const MORALE_LOSE_GROUND := 8.0
const MORALE_GAIN_GROUND := 4.0
const MORALE_FLAG := 15.0
## 士气低于此即崩：守方帅旗未落则降幡、已落则溃散（夺舵），攻方退舷
const BREAK_DEF := 22.0
const BREAK_ATT := 24.0
## 人手折到开打时的这一成以下也崩
const BREAK_DEF_FRAC := 0.2
const BREAK_ATT_FRAC := 0.25
## 本合攻方战力占比（加 ±FRONT_LUCK）过 ADVANCE_AT 推进一段，低于 FALLBACK_AT 被反推一段
const ADVANCE_AT := 0.53
const FALLBACK_AT := 0.45
const FRONT_LUCK := 0.06
## 守方砍缆：每合基率（还乘守方剩余人手比、除以咬住的钩数 / 2）；只在守方仍据舷边（front = 0）且吃紧时
const CUT_BASE := 0.15
const RETREAT_LOSS := 0.15
## 伤亡里阵亡 / 重伤不起的份额（其余轻伤，战后归队）
const DEAD_SHARE_MIN := 0.45
const DEAD_SHARE_MAX := 0.65

const ORD: PackedStringArray = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

## combat02 的机动 / 海况模型（入库了才读）：ManeuverModel.boarding_approach 给接近态势，SeaState.active() 给这一场的风
const MANEUVER_PATH := "res://scripts/combat/ManeuverModel.gd"
const MANEUVER_FUNC := "boarding_approach"
const SEA_STATE_PATH := "res://scripts/combat/SeaState.gd"


# ══ 双方与接敌态势 ══

## 拼一方。extra 可带 name / armor（披甲比例 0–1）/ archers（弓弩手比例 0–1）/ pots（灰瓶数）/ is_player /
## freeboard / screen（不给按 type 查 HULLS）。
static func make_side(crew: int, morale := 60, captain := 1.0, type_id := "", extra := {}) -> Dictionary:
	var s := {"crew": crew, "morale": morale, "captain": captain, "type": type_id}
	for k in extra:
		s[k] = extra[k]
	return s


## 读玩家船队（传 Fleet autoload 或同形对象）：总水手、士气、将领系数、旗舰船型与船名。
static func side_from_fleet(fleet: Object) -> Dictionary:
	var s := {"is_player": true, "name": "我船", "archers": 0.2, "armor": 0.25, "pots": 2}
	if fleet == null:
		return _norm_side(s, true)
	if fleet.has_method("total_crew"):
		s["crew"] = int(fleet.call("total_crew"))
	var m = fleet.get("morale")
	if m != null:
		s["morale"] = int(m)
	if fleet.has_method("captain_power"):
		s["captain"] = float(fleet.call("captain_power"))
	if fleet.has_method("flagship"):
		var fs = fleet.call("flagship")
		if fs is Dictionary:
			s["type"] = str(fs.get("type", ""))
			var nm := str(fs.get("name", "")).strip_edges()
			if nm != "":
				s["name"] = nm
	return _norm_side(s, true)


## 读敌船节点（PirateShip：crew / enemy_morale / captain_force / ship_type / ship_name；可选 melee_armor / melee_archers / melee_pots）。
static func side_from_enemy(enemy: Object) -> Dictionary:
	var s := {"is_player": false, "name": "敌船", "archers": 0.15, "armor": 0.1, "pots": 1}
	if enemy == null:
		return _norm_side(s, false)
	# melee_* 是敌船可选的白刃装备（官军披甲多、海寇少），PirateShip 没有就按上面的海寇默认
	for pair in [["crew", "crew"], ["enemy_morale", "morale"], ["captain_force", "captain"],
			["ship_type", "type"], ["ship_name", "name"],
			["melee_armor", "armor"], ["melee_archers", "archers"], ["melee_pots", "pots"]]:
		var v = enemy.get(pair[0])
		if v != null:
			s[pair[1]] = v
	return _norm_side(s, false)


## 两船节点 → ctx（相对速度、舷距、风力、上下风）。wind_vector 指风的去向（同 WorldMap / SeaState.wind_to：y>0 为北风）。
## 风的来处依次：传进来的 → SeaState.active()（combat02，开战才有）→ 攻方、守方身上的 wind_vector / wind_strength → 常风 80。
## ManeuverModel 已入库时再并进它的接舷接近（覆盖同名键，另带 reach 够距、approach_ok / approach_note）。
## att_type / def_type 是 ships.json 船型（算风压差用；节点上有 ship_type 就不必传）。
static func approach_from_nodes(att: Node2D, def: Node2D, wind_vector := Vector2.ZERO, wind := -1.0,
		att_type := "", def_type := "") -> Dictionary:
	var ctx := {"distance": 60.0, "rel_speed": 0.0, "wind": 80.0, "windward": 0, "sea": 1}
	if att == null or def == null or not is_instance_valid(att) or not is_instance_valid(def):
		return ctx
	ctx["distance"] = att.global_position.distance_to(def.global_position)
	ctx["rel_speed"] = (_vec(att, "velocity") - _vec(def, "velocity")).length()
	var wv := wind_vector
	var ws := wind
	var sea_wind := active_sea_wind()
	if wv == Vector2.ZERO and not sea_wind.is_empty():
		wv = sea_wind[0]
	if ws < 0.0 and not sea_wind.is_empty():
		ws = sea_wind[1]
	if wv == Vector2.ZERO:
		wv = _vec(att, "wind_vector")
	if wv == Vector2.ZERO:
		wv = _vec(def, "wind_vector")
	if ws < 0.0:
		var a = att.get("wind_strength")
		var b = def.get("wind_strength")
		ws = float(a) if a != null else (float(b) if b != null else 80.0)
	ctx["wind"] = ws
	ctx["windward"] = windward_of(att.global_position, def.global_position, wv)
	var mm := maneuver_approach(ship_state(att, att_type), ship_state(def, def_type), wv, ws)
	for k in mm:
		ctx[k] = mm[k]
	return ctx


## 船节点 → ManeuverModel 要的 {pos, vel, heading, type, gear}（船首 = Vector2.UP 转 rotation，同 Ship / PirateShip）。
static func ship_state(n: Node2D, type_id := "") -> Dictionary:
	if n == null or not is_instance_valid(n):
		return {}
	var t := type_id
	if t == "":
		var st = n.get("ship_type")
		t = str(st) if st != null else ""
	var gear = n.get("sail_gear")
	return {"pos": n.global_position, "vel": _vec(n, "velocity"), "heading": Vector2.UP.rotated(n.global_rotation),
		"type": t, "gear": int(gear) if gear != null else 1}


## 这一场海况的风 [wind_to, wind_speed]（combat02 SeaState.active()；没入库 / 没开战返回 []）。
static func active_sea_wind() -> Array:
	if not ResourceLoader.exists(SEA_STATE_PATH):
		return []
	var ss = load(SEA_STATE_PATH)
	if not (ss is Script) or not ss.has_method("active"):
		return []
	var sea = ss.call("active")
	if sea == null or not (sea is Object):
		return []
	var wt = sea.get("wind_to")
	var wsp = sea.get("wind_speed")
	if not (wt is Vector2) or wsp == null:
		return []
	return [wt, float(wsp)]


## 攻方相对守方居上风 +1 / 横风 0 / 居下风 -1。wind_vector 指风的去向：风从攻方吹向守方即攻方在上风。
static func windward_of(att_pos: Vector2, def_pos: Vector2, wind_vector: Vector2) -> int:
	if wind_vector == Vector2.ZERO or att_pos == def_pos:
		return 0
	var d := (def_pos - att_pos).normalized().dot(wind_vector.normalized())
	if d > 0.35:
		return 1
	if d < -0.35:
		return -1
	return 0


## 读 combat02 的 ManeuverModel.boarding_approach（若已入库）。a / b 是 ship_state() 拼的两船，wind_to / wind_speed 是风。
## 按它的形参个数调：≥4 个即 (a, b, wind_to, wind_speed[, base_reach])（combat02 现口径），2 个即 (a, b)。
## 返回键归一成 rel_speed / windward / distance / reach / approach_ok / approach_note（见 _norm_approach）；没有返回 {}。
static func maneuver_approach(a: Dictionary, b: Dictionary, wind_to := Vector2(0, 1), wind_speed := 80.0) -> Dictionary:
	if a.is_empty() or b.is_empty() or not ResourceLoader.exists(MANEUVER_PATH):
		return {}
	var mm = load(MANEUVER_PATH)
	# GDScript 资源上 has_method 只认 static func（4.6.3 实测；Script 没有 has_script_method）
	if not (mm is Script) or not mm.has_method(MANEUVER_FUNC):
		return {}
	var argc := 2
	for m in (mm as Script).get_script_method_list():
		if str(m.get("name", "")) == MANEUVER_FUNC:
			argc = (m.get("args", []) as Array).size()
			break
	var got
	if argc >= 5:
		got = mm.call(MANEUVER_FUNC, a, b, wind_to, wind_speed, BOARD_REACH)
	elif argc == 4:
		got = mm.call(MANEUVER_FUNC, a, b, wind_to, wind_speed)
	else:
		got = mm.call(MANEUVER_FUNC, a, b)
	return _norm_approach(got) if got is Dictionary else {}


## 一步到位：玩家船队（fleet）接敌船（enemy）。player_ship / enemy 是战场节点，取态势用；ctx_extra 覆盖同名键。
static func from_battle(fleet: Object, player_ship: Node2D, enemy: Node2D, ctx_extra := {}) -> Dictionary:
	var us := side_from_fleet(fleet)
	var foe := side_from_enemy(enemy)
	var ctx := approach_from_nodes(player_ship, enemy, Vector2.ZERO, -1.0, str(us["type"]), str(foe["type"]))
	for k in ctx_extra:
		ctx[k] = ctx_extra[k]
	return resolve(us, foe, ctx)


# ══ 抛钩 ══

## 钩索各项折算与合成钩牢率。返回 {q 每具咬舷率, hooks 挠钩数, chance 钩牢率, factors {项: 乘数},
## notes 不利的缘由, boons 有利的缘由}（中文短语，不分你我：写「对舷」）。
static func grapple_factors(att_in: Dictionary, def_in: Dictionary, ctx := {}) -> Dictionary:
	var att := _norm_side(att_in, true)
	var def := _norm_side(def_in, false)
	var rel := maxf(0.0, float(ctx.get("rel_speed", 0.0)))
	var dist := maxf(0.0, float(ctx.get("distance", 60.0)))
	# 够距：ManeuverModel 给了就用它的（已折进相对航速、上风、风压差），它判「钩不住」就直接不给钩
	var reach := maxf(1.0, float(ctx.get("reach", BOARD_REACH)))
	var blocked := ctx.has("approach_ok") and not bool(ctx["approach_ok"])
	var wind := maxf(0.0, float(ctx.get("wind", 80.0)))
	var sea := clampi(int(ctx.get("sea", 1)), 0, SEA_HOOK.size() - 1)
	var ww := clampi(int(ctx.get("windward", 0)), -1, 1)
	var up := maxf(0.0, float(def["freeboard"]) - float(att["freeboard"]))
	var f := {}
	f["speed"] = 1.0 / (1.0 + pow(rel / REL_SPEED_HALF, 2.0))
	f["reach"] = 0.0 if dist > reach or blocked else clampf(1.1 - 0.5 * dist / reach, 0.55, 1.0)
	f["wind"] = 1.0 - clampf((wind - WIND_CALM) / 300.0, 0.0, 0.5)
	f["sea"] = float(SEA_HOOK[sea])
	f["windward"] = 1.0 + 0.1 * ww
	f["height"] = clampf(1.0 - 0.035 * up, 0.6, 1.0)
	# 守方拒竿：人多气盛才撑得开来船
	f["fend"] = 1.0 - 0.2 * clampf(float(def["morale"]) / 100.0, 0.0, 1.0) * clampf(float(def["crew"]) / 60.0, 0.0, 1.0)
	var q := HOOK_BASE
	for k in f:
		q *= float(f[k])
	q = clampf(q, 0.0, 0.95)
	var hooks := hooks_for(int(att["crew"]))
	var notes := PackedStringArray()
	var boons := PackedStringArray()
	if blocked:
		var why := str(ctx.get("approach_note", "")).strip_edges()
		notes.append(why if why != "" else "机动态势钩不住")
	elif dist > reach:
		notes.append("舷距太远，钩索够不着")
	if float(f["speed"]) < 0.8:
		if not blocked:
			notes.append("两船相对太快")
	elif float(f["speed"]) > 0.95:
		boons.append("并舷同速")
	if float(f["wind"]) < 0.9:
		notes.append("风急帆横")
	if float(f["sea"]) < 0.9:
		notes.append("%s船颠" % SEA_NAMES[sea])
	if ww < 0:
		notes.append("居下风")
	elif ww > 0:
		boons.append("居上风")
	if float(f["height"]) < 0.9:
		notes.append("对舷高出 %d 尺" % roundi(up))
	elif float(att["freeboard"]) - float(def["freeboard"]) >= 3.0:
		boons.append("居高下钩")
	if float(f["fend"]) < 0.9:
		notes.append("对舷持竿拒船")
	return {"q": q, "hooks": hooks, "chance": at_least(hooks, HOOKS_TO_HOLD, q), "factors": f,
		"notes": notes, "boons": boons}


## 钩牢率（0–1）：hooks 具里至少 HOOKS_TO_HOLD 具咬舷。
static func grapple_chance(att: Dictionary, def: Dictionary, ctx := {}) -> float:
	return float(grapple_factors(att, def, ctx)["chance"])


## 掷一次钩：逐具掷咬舷，返回 grapple_factors 的内容 + ok / bit（咬住几具）。rng 缺省按 ctx.seed 起。
static func grapple(att: Dictionary, def: Dictionary, ctx := {}, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = _rng(ctx)
	var g := grapple_factors(att, def, ctx)
	var bit := 0
	for i in range(int(g["hooks"])):
		if rng.randf() < float(g["q"]):
			bit += 1
	g["bit"] = bit
	g["ok"] = bit >= HOOKS_TO_HOLD
	return g


## 按人头出挠钩手。
static func hooks_for(crew: int) -> int:
	return clampi(roundi(float(maxi(crew, 0)) / CREW_PER_HOOK), HOOKS_MIN, HOOKS_MAX)


## 二项分布：n 次各 q 的试验里至少成 k 次的概率。
static func at_least(n: int, k: int, q: float) -> float:
	if k <= 0:
		return 1.0
	if n < k:
		return 0.0
	var p := 0.0
	for i in range(k, n + 1):
		p += _choose(n, i) * pow(q, i) * pow(1.0 - q, n - i)
	return clampf(p, 0.0, 1.0)


# ══ 整场 ══

## 一场接舷白刃。att / def 是 make_side / side_from_* 拼的一方（缺的键按默认补），ctx 键（全可缺省）：
##   rel_speed 两船相对速度（像素 / 秒）· distance 抛钩时舷距（像素）· wind 风力 · windward 攻方上风 +1 / 横 0 / 下风 -1 ·
##   sea 海况 0–4 · seed 非 0 可复现 · max_rounds 甲板最多几合（缺省 6，至多 10）· hooked 已钩牢（跳过抛钩）
## 返回键见 _blank；逐合 rounds[i] = {n, front, zone, moved, event, att, def, att_loss, def_loss, att_morale, def_morale, share, text}。
static func resolve(att_in: Dictionary, def_in: Dictionary, ctx := {}) -> Dictionary:
	var rng := _rng(ctx)
	var att := _norm_side(att_in, true)
	var def := _norm_side(def_in, false)
	var out := _blank(att, def, rng.seed)
	var a: String = out["a_word"]
	var d: String = out["d_word"]
	var ww := clampi(int(ctx.get("windward", 0)), -1, 1)
	var sea := clampi(int(ctx.get("sea", 1)), 0, SEA_HOOK.size() - 1)
	var fb_a := float(att["freeboard"])
	var fb_d := float(def["freeboard"])
	var up := maxf(0.0, fb_d - fb_a)

	# 一、抛钩
	var g: Dictionary
	if bool(ctx.get("hooked", false)):
		g = {"q": 1.0, "hooks": 0, "bit": HOOKS_TO_HOLD, "chance": 1.0, "ok": true, "factors": {},
			"notes": PackedStringArray(), "boons": PackedStringArray(), "preset": true, "text": "钩缆已挂牢，两船并靠"}
	else:
		g = grapple(att, def, ctx, rng)
		var hooks_n := int(g["hooks"])
		var bit_n := int(g["bit"])
		if bool(g["ok"]):
			g["text"] = "%s挠钩 %d 具齐出，咬住 %d 具" % [a, hooks_n, bit_n]
		elif bit_n == 0:
			g["text"] = "%s挠钩 %d 具一具也没咬住" % [a, hooks_n]
		else:
			g["text"] = "%s挠钩 %d 具只咬住 %d 具" % [a, hooks_n, bit_n]
	out["grapple"] = g
	if not bool(g["ok"]):
		var why := "、".join(g["notes"])
		out["summary"] = "%s，钩索落空%s。" % [g["text"], "（%s）" % why if why != "" else ""]
		return _conclude(out, OUTCOME_HOOK_MISS, rng, 0, 0, 0, 0)

	var crew_a := int(att["crew"])
	var crew_d := int(def["crew"])
	var cas_a := 0
	var cas_d := 0

	# 二、矢石：弓弩对射，灰瓶顺风才好使
	var sh_a := 1.0 + 0.04 * clampf(fb_a - fb_d, -6.0, 6.0)
	var sh_d := 1.0 + 0.04 * clampf(fb_d - fb_a, -6.0, 6.0)
	var arrows_d := roundi(crew_a * float(att["archers"]) * VOLLEY_HIT * sh_a
		* (1.0 - 0.6 * float(def["screen"])) * (1.0 - 0.4 * float(def["armor"])) * rng.randf_range(0.6, 1.4))
	var arrows_a := roundi(crew_d * float(def["archers"]) * VOLLEY_HIT * sh_d
		* (1.0 - 0.6 * float(att["screen"])) * (1.0 - 0.4 * float(att["armor"])) * rng.randf_range(0.6, 1.4))
	var pots_hit_d := 0
	var pots_hit_a := 0
	var pots_a := mini(int(att["pots"]), POTS_PER_VOLLEY) if crew_a > 0 else 0
	var pots_d := mini(int(def["pots"]), POTS_PER_VOLLEY) if crew_d > 0 else 0
	for i in range(pots_a):
		if rng.randf() < clampf(POT_HIT + 0.15 * ww, 0.1, 0.9):
			pots_hit_d += 1
	for i in range(pots_d):
		if rng.randf() < clampf(POT_HIT - 0.15 * ww, 0.1, 0.9):
			pots_hit_a += 1
	var v_d := mini(crew_d, arrows_d + pots_hit_d * rng.randi_range(1, 2))
	var v_a := mini(crew_a, arrows_a + pots_hit_a * rng.randi_range(1, 2))
	crew_a -= v_a
	crew_d -= v_d
	cas_a += v_a
	cas_d += v_d
	var disorder_d := maxf(0.7, 1.0 - 0.1 * pots_hit_d)
	var disorder_a := maxf(0.7, 1.0 - 0.1 * pots_hit_a)
	var vt := "弓弩对射"
	if pots_hit_d > 0:
		vt += "，灰瓶 %d 枚落%s舷" % [pots_hit_d, d]
	if pots_hit_a > 0:
		vt += "，%s灰瓶 %d 枚迷了%s眼" % [d, pots_hit_a, a]
	vt += "。%s伤 %d，%s伤 %d" % [a, v_a, d, v_d]
	out["volley"] = {"att_loss": v_a, "def_loss": v_d, "pots_hit_def": pots_hit_d, "pots_hit_att": pots_hit_a,
		"att_pots_used": pots_a, "def_pots_used": pots_d, "text": vt}

	# 三、跳帮：留人看帆掌舵，其余过舷
	if crew_d <= 0:
		out["leap"] = {"boarders": 0, "leap_loss": 0, "text": "%s舷上已无人拒守" % d}
		out["summary"] = "%s船上无人拒守，登船即得。" % d
		return _conclude(out, OUTCOME_CAPTURE, rng, cas_a, cas_d, 0, 0)
	var keep := mini(crew_a, maxi(KEEP_MIN, ceili(crew_a * KEEP_BACK)))
	var fa := crew_a - keep
	if fa <= 0:
		out["leap"] = {"boarders": 0, "leap_loss": 0, "text": "人手只够看帆掌舵，无人可跳帮"}
		out["cut_by"] = "att"
		out["summary"] = "%s人手不足，无人可跳帮，砍缆脱开。" % a
		return _conclude(out, OUTCOME_CUT_LOOSE, rng, cas_a, cas_d, crew_d, 0)
	var dkeep := mini(crew_d, maxi(1, ceili(crew_d * DEF_KEEP)))
	var fd := crew_d - dkeep
	var leap_loss := mini(fa, roundi(fa * (LEAP_LOSS + 0.012 * up + 0.01 * sea) * rng.randf_range(0.5, 1.5)))
	fa -= leap_loss
	cas_a += leap_loss
	var lt := "%s %d 人跃过舷墙" % [a, fa + leap_loss]
	if leap_loss > 0:
		lt += "，%s %d 人" % ["攀高舷被刺落" if up >= 3.0 else "失足落水", leap_loss]
	out["leap"] = {"boarders": fa + leap_loss, "leap_loss": leap_loss, "keep": keep, "def_keep": dkeep, "text": lt}
	out["boarders"] = fa + leap_loss
	out["defenders"] = fd
	if fd <= 0:
		# 守船上只剩掌舵的几个人：见跳帮即降
		out["summary"] = "%s船上只剩掌舵的 %d 人，见%s跳帮即降。" % [d, dkeep, a]
		return _conclude(out, OUTCOME_SURRENDER, rng, cas_a, cas_d, dkeep, 2)

	# 四、甲板多合
	var fa0 := maxi(fa, 1)
	var fd0 := maxi(fd, 1)
	var ma := float(att["morale"])
	var md := float(def["morale"])
	var front := 0
	var flag_cut := false
	var max_rounds := clampi(int(ctx.get("max_rounds", ROUNDS_DEFAULT)), 1, ROUNDS_MAX)
	var rounds: Array = []
	var outcome := ""
	# 这一仗的时运：双方各抽一回（对数正态），管的是模型外的偶然——谁先登、谁手软、谁的头目中了流矢
	var luck_a := clampf(exp(rng.randfn(0.0, BATTLE_LUCK)), 0.5, 2.0)
	var luck_d := clampf(exp(rng.randfn(0.0, BATTLE_LUCK)), 0.5, 2.0)
	for n in range(1, max_rounds + 1):
		var cap_d := float(def["captain"]) if front >= ZONE_FLAG else 1.0 + (float(def["captain"]) - 1.0) * 0.5
		var pa := fa * _mfac(ma) * float(att["captain"]) * _armor(att) * disorder_a * luck_a * (SHOCK if n == 1 else 1.0)
		var pd := fd * _mfac(md) * cap_d * _armor(def) * _zone_def(front, up, float(def["screen"])) * disorder_d * luck_d
		disorder_a = 1.0
		disorder_d = 1.0
		pa *= rng.randf_range(1.0 - ROUND_LUCK, 1.0 + ROUND_LUCK)
		pd *= rng.randf_range(1.0 - ROUND_LUCK, 1.0 + ROUND_LUCK)
		var share := pa / maxf(pa + pd, 0.001)
		var loss_d := mini(fd, roundi(pa * LETHALITY * rng.randf_range(0.75, 1.25)))
		var loss_a := mini(fa, roundi(pd * LETHALITY * rng.randf_range(0.75, 1.25)))
		fa -= loss_a
		fd -= loss_d
		cas_a += loss_a
		cas_d += loss_d
		ma = clampf(ma - float(loss_a) / fa0 * MORALE_PER_LOSS - maxf(0.0, 0.5 - share) * MORALE_OVERMATCH, 0.0, 100.0)
		md = clampf(md - float(loss_d) / fd0 * MORALE_PER_LOSS - maxf(0.0, share - 0.5) * MORALE_OVERMATCH, 0.0, 100.0)
		var moved := 0
		var ev := "hold"
		# 先看这一合打完谁先崩：守方帅旗还在就自己降幡（俘获），旗已被斩则是溃散（夺船）；再看攻方
		if md < BREAK_DEF or fd <= maxi(1, roundi(fd0 * BREAK_DEF_FRAC)):
			outcome = OUTCOME_CAPTURE if flag_cut else OUTCOME_SURRENDER
			ev = "rout" if flag_cut else "break_def"
		elif ma < BREAK_ATT or fa <= maxi(1, roundi(fa0 * BREAK_ATT_FRAC)):
			outcome = OUTCOME_REPELLED
			ev = "break_att"
		else:
			var roll := share + rng.randf_range(-FRONT_LUCK, FRONT_LUCK)
			if roll > ADVANCE_AT:
				moved = 1
			elif roll < FALLBACK_AT:
				moved = -1
			front = clampi(front + moved, -1, ZONE_TAKEN)
			if moved > 0:
				ev = "advance"
				md = clampf(md - MORALE_LOSE_GROUND, 0.0, 100.0)
				ma = clampf(ma + MORALE_GAIN_GROUND, 0.0, 100.0)
			elif moved < 0:
				ev = "fallback"
				ma = clampf(ma - MORALE_LOSE_GROUND, 0.0, 100.0)
				md = clampf(md + MORALE_GAIN_GROUND, 0.0, 100.0)
			if front >= ZONE_TAKEN:
				outcome = OUTCOME_CAPTURE
				ev = "helm"
			elif front >= ZONE_FLAG and not flag_cut:
				flag_cut = true
				md = clampf(md - MORALE_FLAG, 0.0, 100.0)
				ev = "flag"
				if md < BREAK_DEF:
					outcome = OUTCOME_CAPTURE
					ev = "flag_rout"
			elif front == 0 and share >= 0.45:
				# 守方仍据舷边、又吃紧：抢砍钩缆脱身。咬住的钩越多越难砍尽，人手越少越砍不动
				var cut_p := CUT_BASE * clampf(float(fd) / fd0, 0.0, 1.0) * 2.0 / maxf(float(g["bit"]), 2.0)
				if rng.randf() < cut_p:
					outcome = OUTCOME_CUT_LOOSE
					ev = "cut"
					out["cut_by"] = "def"
		var rd := {"n": n, "front": front, "zone": _zone_word(front, a), "moved": moved, "event": ev,
			"att": fa, "def": fd, "att_loss": loss_a, "def_loss": loss_d,
			"att_morale": roundi(ma), "def_morale": roundi(md), "share": snappedf(share, 0.01)}
		rd["text"] = _round_text(rd, a, d, posmod(int(out["seed"]) + n, 3))
		rounds.append(rd)
		if outcome != "":
			break
	out["rounds"] = rounds
	out["rounds_fought"] = rounds.size()
	out["front"] = front
	out["front_name"] = _zone_word(front, a)
	out["flag_cut"] = flag_cut
	out["att_morale"] = roundi(ma)
	out["def_morale"] = roundi(md)
	var nr := rounds.size()
	var left_d := fd + dkeep
	match outcome:
		OUTCOME_CAPTURE:
			out["summary"] = "斗 %d 合，%s攻上舵楼夺舵，%s船归%s。" % [nr, a, d, a]
			return _conclude(out, OUTCOME_CAPTURE, rng, cas_a, cas_d, left_d, 1)
		OUTCOME_SURRENDER:
			out["summary"] = "斗 %d 合，%s降幡弃械。" % [nr, d]
			return _conclude(out, OUTCOME_SURRENDER, rng, cas_a, cas_d, left_d, 2)
		OUTCOME_REPELLED:
			var extra := 0
			if front >= 1:
				extra = mini(fa, roundi(fa * RETREAT_LOSS * rng.randf_range(0.6, 1.4)))
			cas_a += extra
			out["retreat_loss"] = extra
			out["cut_by"] = "att"
			out["summary"] = "斗 %d 合不利，%s退回本船，砍缆脱钩%s。" % [nr, a, "，退舷时又折 %d 人" % extra if extra > 0 else ""]
			return _conclude(out, OUTCOME_REPELLED, rng, cas_a, cas_d, left_d, 0)
		OUTCOME_CUT_LOOSE:
			out["summary"] = "斗 %d 合，%s斧手砍断钩缆，两船分开。" % [nr, d]
			return _conclude(out, OUTCOME_CUT_LOOSE, rng, cas_a, cas_d, left_d, 0)
	out["cut_by"] = "both"
	out["summary"] = "斗满 %d 合，两下罢手，各自砍缆。" % nr
	return _conclude(out, OUTCOME_CUT_LOOSE, rng, cas_a, cas_d, left_d, 0)


## 折回旧两拍契约（BoardingStage.resolve / WorldMap 现口径）：夺船、俘获 = "win"，其余 = "lose"。按攻方算。
static func legacy_outcome(result: Dictionary) -> String:
	var o := str(result.get("outcome", ""))
	return "win" if o == OUTCOME_CAPTURE or o == OUTCOME_SURRENDER else "lose"


## 了局题签；不认得的键给「白刃」（同 BoardingStage 旧口径）。
static func outcome_title(outcome: String) -> String:
	return str(TITLES.get(outcome, "白刃"))


## 甲板段名：-1 攻方舷边，0–3 四段，4 舵楼已夺（不分你我；逐合记事用 _zone_word）。
static func zone_name(front: int) -> String:
	if front < 0:
		return ZONE_OWN
	if front >= ZONE_TAKEN:
		return "舵楼已夺"
	return ZONES[front]


## 蒙特卡洛：同一对阵跑 runs 场（种子 base_seed 起逐场 +1），返回各了局场数、攻方得船率、平均合数与阵亡。
static func simulate(att: Dictionary, def: Dictionary, ctx := {}, runs := 400, base_seed := 1) -> Dictionary:
	var counts := {}
	for k in TITLES:
		counts[k] = 0
	var wins := 0
	var rounds := 0
	var dead := 0
	var n := maxi(runs, 1)
	for i in range(n):
		var c: Dictionary = ctx.duplicate()
		c["seed"] = base_seed + i
		var r := resolve(att, def, c)
		counts[r["outcome"]] = int(counts[r["outcome"]]) + 1
		if legacy_outcome(r) == "win":
			wins += 1
		rounds += int(r["rounds_fought"])
		dead += int(r["att_dead"])
	return {"runs": n, "counts": counts, "win_rate": float(wins) / n,
		"rounds_avg": float(rounds) / n, "att_dead_avg": float(dead) / n}


## 自检（探针调）：可复现、钩索随速度 / 风浪 / 上下风 / 舷距单调、人多士气高得船率高、了局键与计数自洽、边界不崩。
## 返回问题清单；空 = 全过。
static func self_check() -> PackedStringArray:
	var bad := PackedStringArray()
	var us := make_side(80, 70, 1.15, "fu_ship_medium", {"is_player": true})
	var foe := make_side(70, 62, 0.95, "pirate_boat")
	var calm := {"rel_speed": 0.0, "distance": 60.0, "wind": 80.0, "windward": 0, "sea": 1}
	var r1 := resolve(us, foe, _with(calm, "seed", 7))
	var r2 := resolve(us, foe, _with(calm, "seed", 7))
	if str(r1) != str(r2):
		bad.append("同种子两场结果不同")
	var g0 := grapple_chance(us, foe, calm)
	if not (g0 > grapple_chance(us, foe, _with(calm, "rel_speed", 300.0))
			and grapple_chance(us, foe, _with(calm, "rel_speed", 300.0)) > grapple_chance(us, foe, _with(calm, "rel_speed", 600.0))):
		bad.append("钩牢率没随相对速度下降")
	if not (g0 > grapple_chance(us, foe, _with(calm, "sea", 3))):
		bad.append("钩牢率没随浪高下降")
	if not (g0 > grapple_chance(us, foe, _with(calm, "wind", 260.0))):
		bad.append("钩牢率没随风急下降")
	if not (grapple_chance(us, foe, _with(calm, "windward", 1)) > grapple_chance(us, foe, _with(calm, "windward", -1))):
		bad.append("上风钩牢率不高于下风")
	if grapple_chance(us, foe, _with(calm, "distance", BOARD_REACH + 1.0)) != 0.0:
		bad.append("舷距出了钩索够得着的范围仍有钩牢率")
	if not (grapple_chance(make_side(80, 70, 1.0, "sampan"), make_side(80, 70, 1.0, "fu_ship_large"), calm)
			< grapple_chance(make_side(80, 70, 1.0, "fu_ship_large"), make_side(80, 70, 1.0, "sampan"), calm)):
		bad.append("往高舷上抛钩不比往低舷上难")
	var hooked := _with(calm, "hooked", true)
	var weak := simulate(make_side(40, 60, 1.0, "keel_boat"), foe, hooked, 300)
	var even := simulate(make_side(70, 62, 1.0, "keel_boat"), foe, hooked, 300)
	var strong := simulate(make_side(140, 75, 1.2, "keel_boat"), foe, hooked, 300)
	# 定标带（lane combat05 调定：约 0.03 / 0.41 / 0.99）：只查单调会漏掉「攻方战力不看人数」这类变异
	# （伤亡、崩线都随人数走，照样单调——实测 0.35 / 0.45 / 0.71）。改数值时连这三条带一起改
	if not (float(weak["win_rate"]) < float(even["win_rate"]) and float(even["win_rate"]) < float(strong["win_rate"])
			and float(weak["win_rate"]) <= 0.15 and float(even["win_rate"]) >= 0.25 and float(even["win_rate"]) <= 0.65
			and float(strong["win_rate"]) >= 0.9):
		bad.append("人多气盛得船率不对（40 / 70 / 140 人对 70 人）：%.2f / %.2f / %.2f，应 ≤0.15 / 0.25–0.65 / ≥0.9" % [
			weak["win_rate"], even["win_rate"], strong["win_rate"]])
	# 白刃要见血、要几合见分晓：均势那组平均阵亡与合数也有带（实测约 11 人 / 3 合），伤亡被抹掉会拖满合数
	if not (float(even["att_dead_avg"]) >= 4.0 and float(even["att_dead_avg"]) <= 20.0
			and float(even["rounds_avg"]) >= 1.5 and float(even["rounds_avg"]) <= 4.5):
		bad.append("均势白刃的阵亡 / 合数出带：平均阵亡 %.1f（应 4–20）、平均 %.2f 合（应 1.5–4.5）" % [
			even["att_dead_avg"], even["rounds_avg"]])
	var low := simulate(make_side(70, 25, 1.0, "keel_boat"), foe, hooked, 300)
	if not (float(low["win_rate"]) < float(even["win_rate"])):
		bad.append("士气低得船率不降")
	for i in range(60):
		var r := resolve(make_side(20 + i * 3, 30 + i, 1.0 + 0.005 * i, "keel_boat", {"is_player": true}),
			make_side(90 - i, 80 - floori(i * 0.5), 1.1, "pirate_boat"), _with(calm, "seed", 100 + i))
		bad.append_array(_result_problems(r, "第 %d 场" % i))
	var miss := resolve(us, foe, _with(calm, "distance", BOARD_REACH + 10.0))
	if str(miss["outcome"]) != OUTCOME_HOOK_MISS or int(miss["att_cas"]) != 0 or not (miss["rounds"] as Array).is_empty():
		bad.append("钩索落空却开了打或有伤亡")
	var skip := resolve(us, foe, _with(hooked, "seed", 3))
	if not bool((skip["grapple"] as Dictionary).get("preset", false)):
		bad.append("hooked 没跳过抛钩")
	var empty := resolve(us, make_side(0, 50), _with(hooked, "seed", 5))
	if str(empty["outcome"]) != OUTCOME_CAPTURE:
		bad.append("敌船无人不是登船即得")
	var nobody := resolve(make_side(2, 70), foe, _with(hooked, "seed", 5))
	if str(nobody["outcome"]) != OUTCOME_CUT_LOOSE or int(nobody["boarders"]) != 0:
		bad.append("攻方人手只够看帆却跳了帮")
	for o in TITLES:
		if outcome_title(o).length() != 2:
			bad.append("了局题签不是两字：%s" % o)
	if windward_of(Vector2.ZERO, Vector2(100, 0), Vector2(1, 0)) != 1 or windward_of(Vector2.ZERO, Vector2(100, 0), Vector2(-1, 0)) != -1 \
			or windward_of(Vector2.ZERO, Vector2(100, 0), Vector2(0, 1)) != 0:
		bad.append("上下风判反了（wind_vector 指风的去向）")
	var norm := _norm_approach({"relative_speed": 123.0, "weather_gauge": 0.6, "distance": 90.0, "reach": 150.0,
		"ok": false, "reason": "身处下风　靠不上", "junk": 1})
	if str(norm) != str({"rel_speed": 123.0, "windward": 1, "distance": 90.0, "reach": 150.0, "approach_ok": false,
			"approach_note": "身处下风"}):
		bad.append("ManeuverModel 返回键没归一：%s" % str(norm))
	if grapple_chance(us, foe, _with(_with(calm, "approach_ok", false), "approach_note", "对冲太快")) != 0.0:
		bad.append("ManeuverModel 判钩不住仍有钩牢率")
	if not (grapple_chance(us, foe, _with(_with(calm, "distance", 150.0), "reach", 180.0)) > 0.0
			and grapple_chance(us, foe, _with(_with(calm, "distance", 120.0), "reach", 100.0)) == 0.0):
		bad.append("没按 ManeuverModel 的够距 reach 判钩索够不够得着")
	return bad


# ══ 内部 ══

static func _rng(ctx: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var s := int(ctx.get("seed", 0))
	if s != 0:
		rng.seed = s
	else:
		rng.randomize()
	return rng


static func _norm_side(s: Dictionary, attacker: bool) -> Dictionary:
	var type_id := str(s.get("type", ""))
	var hull: Dictionary = HULLS.get(type_id, DEFAULT_HULL)
	var player := bool(s.get("is_player", false))
	var n := {
		"crew": maxi(0, int(s.get("crew", 0))),
		"morale": clampi(int(s.get("morale", 60)), 0, 100),
		"captain": clampf(float(s.get("captain", 1.0)), 0.5, 2.0),
		"type": type_id,
		"name": str(s.get("name", "我船" if player else ("来船" if attacker else "敌船"))),
		"armor": clampf(float(s.get("armor", 0.2)), 0.0, 1.0),
		"archers": clampf(float(s.get("archers", 0.18)), 0.0, 1.0),
		"pots": maxi(0, int(s.get("pots", 1))),
		"is_player": player,
		"freeboard": maxf(1.0, float(s.get("freeboard", hull["freeboard"]))),
		"screen": clampf(float(s.get("screen", hull["screen"])), 0.0, 1.0),
	}
	return n


## ManeuverModel 回来的键归一（combat02 现口径：relative_speed / weather_gauge（-1–1）/ distance / reach / ok / reason）。
static func _norm_approach(got: Dictionary) -> Dictionary:
	var out := {}
	for pair in [["rel_speed", "rel_speed"], ["relative_speed", "rel_speed"],
			["windward", "windward"], ["upwind", "windward"], ["weather_gauge", "windward"],
			["wind", "wind"], ["wind_strength", "wind"], ["sea", "sea"], ["sea_state", "sea"], ["sea_level", "sea"],
			["distance", "distance"], ["reach", "reach"], ["ok", "approach_ok"]]:
		if got.has(pair[0]) and not out.has(pair[1]):
			out[pair[1]] = got[pair[0]]
	# reason 是顶匾短语「对冲太快　钩不住」：只取前半截的缘由，拼进钩索注记
	var why := str(got.get("reason", "")).strip_edges()
	if why != "":
		out["approach_note"] = why.split("　")[0]
	if out.has("windward"):
		var w = out["windward"]
		if w is bool:
			out["windward"] = 1 if w else -1
		else:
			var wf := float(w)
			out["windward"] = 1 if wf > 0.35 else (-1 if wf < -0.35 else 0)
	return out


static func _blank(att: Dictionary, def: Dictionary, used_seed: int) -> Dictionary:
	var a := "我" if bool(att["is_player"]) else ("敌" if bool(def["is_player"]) else str(att["name"]))
	var d := "敌" if bool(att["is_player"]) else ("我" if bool(def["is_player"]) else str(def["name"]))
	return {
		"outcome": "", "title": "", "legacy": "lose", "summary": "", "summary_head": "", "summary_tail": "", "seed": used_seed,
		"att_is_player": att["is_player"], "def_is_player": def["is_player"],
		"att_name": att["name"], "def_name": def["name"], "att_type": att["type"], "def_type": def["type"],
		"att_crew": att["crew"], "def_crew": def["crew"], "a_word": a, "d_word": d,
		"grapple": {}, "volley": {}, "leap": {}, "rounds": [], "rounds_fought": 0,
		"boarders": 0, "defenders": 0, "front": 0, "front_name": ZONES[0], "flag_cut": false,
		"att_morale": att["morale"], "def_morale": def["morale"], "cut_by": "", "retreat_loss": 0,
		"att_cas": 0, "def_cas": 0, "att_dead": 0, "att_hurt": 0, "def_dead": 0, "def_hurt": 0,
		"prisoners": 0, "overboard": 0, "att_morale_delta": 0,
	}


## 收尾：记了局、分阵亡轻伤、算俘获跳海、补伤亡注。take = 0 不夺船 / 1 力夺（余众三到五成降）/ 2 降幡（七到九成降）。
static func _conclude(out: Dictionary, outcome: String, rng: RandomNumberGenerator,
		cas_a: int, cas_d: int, left_d: int, take: int) -> Dictionary:
	out["outcome"] = outcome
	out["title"] = outcome_title(outcome)
	out["legacy"] = legacy_outcome(out)
	out["att_cas"] = cas_a
	out["def_cas"] = cas_d
	var dead_a := roundi(cas_a * rng.randf_range(DEAD_SHARE_MIN, DEAD_SHARE_MAX))
	var dead_d := roundi(cas_d * rng.randf_range(DEAD_SHARE_MIN, DEAD_SHARE_MAX))
	out["att_dead"] = dead_a
	out["att_hurt"] = cas_a - dead_a
	out["def_dead"] = dead_d
	out["def_hurt"] = cas_d - dead_d
	if take > 0 and left_d > 0:
		var share := rng.randf_range(0.3, 0.5) if take == 1 else rng.randf_range(0.7, 0.9)
		out["prisoners"] = roundi(left_d * share)
		out["overboard"] = left_d - int(out["prisoners"])
	match outcome:
		OUTCOME_CAPTURE:
			out["front"] = ZONE_TAKEN
			out["front_name"] = zone_name(ZONE_TAKEN)
			out["att_morale_delta"] = 4
		OUTCOME_SURRENDER:
			out["att_morale_delta"] = 5
		OUTCOME_REPELLED:
			out["att_morale_delta"] = -10
		OUTCOME_CUT_LOOSE:
			out["att_morale_delta"] = -4 if cas_a > 0 else -2
		_:
			out["att_morale_delta"] = -2
	var a: String = out["a_word"]
	var tail := ""
	if int(out["prisoners"]) > 0 or int(out["overboard"]) > 0:
		tail += "俘 %d 人" % int(out["prisoners"])
		if int(out["overboard"]) > 0:
			tail += "，跳海 %d 人" % int(out["overboard"])
		tail += "。"
	if cas_a > 0:
		tail += "%s阵亡 %d、轻伤 %d。" % [a, dead_a, cas_a - dead_a]
	out["summary_head"] = str(out["summary"])
	out["summary_tail"] = tail
	out["summary"] = str(out["summary"]) + tail
	return out


## 一合的记事。vary（0–2）只挑相持时的说法，免得连着几合一个字不差。
static func _round_text(rd: Dictionary, a: String, d: String, vary := 0) -> String:
	var zone: String = rd["zone"]
	var head := "第%s合" % ORD[clampi(int(rd["n"]) - 1, 0, ORD.size() - 1)]
	var body := ""
	var v := posmod(vary, 3)
	match str(rd["event"]):
		"helm":
			body = "%s攻上舵楼，夺舵" % a
		"rout":
			body = "%s众溃散，%s攻上舵楼夺舵" % [d, a]
		"flag_rout":
			body = "斩断旗绳，%s帅旗落，%s众溃散" % [d, d]
		"flag":
			body = "逼至桅下，斩断旗绳，%s帅旗落" % d
		"break_def":
			body = "%s众气沮，纷纷弃械" % d
		"break_att":
			body = "%s众气沮，且战且退" % a
		"cut":
			body = "%s斧手抢砍钩缆" % d
		"advance":
			match int(rd["front"]):
				0:
					body = "%s把%s众压回对舷" % [a, d]
				1:
					body = "%s抢上舷边，杀入舷腰" % a
				2:
					body = "%s再逼桅下" % a
				3:
					body = "%s攻至舵楼下，%s首居高督战" % [a, d]
				_:
					body = "%s向前推进" % a
		"fallback":
			if int(rd["front"]) < 0:
				body = "%s反扑，战至%s舷" % [d, a]
			else:
				body = "%s反扑，%s退到%s" % [d, a, zone]
		_:
			match int(rd["front"]):
				-1:
					body = ["%s舷边死战" % a, "%s在本船舷边堵住%s众" % [a, d], "两下在%s船舷边绞杀" % a][v]
				0:
					body = ["%s倚女墙拒舷，%s未得立足" % [d, a], "%s攀舷再上，%s长枪攒刺" % [a, d], "舷边刀牌相格，寸步难进"][v]
				1:
					body = ["舷腰短兵相接", "舷腰人挤人，刀枪施展不开", "两下在舷腰绞杀"][v]
				2:
					body = ["桅下死战", "%s围着桅杆死守" % d, "桅下刀牌相格"][v]
				_:
					body = ["%s据舵楼死守" % d, "%s从舵楼上掷石" % d, "舵楼梯口反复争夺"][v]
	return "%s　%s：%s。%s伤 %d，%s伤 %d" % [head, zone, body, a, int(rd["att_loss"]), d, int(rd["def_loss"])]


## 守方地利：舷边倚女墙（高舷、牛皮城再加），舵楼居高；被反推到攻方舷边时守方失地利。
static func _zone_word(front: int, a: String) -> String:
	return "%s船舷边" % a if front < 0 else zone_name(front)


static func _zone_def(front: int, up: float, screen: float) -> float:
	match front:
		-1:
			return 0.9
		0:
			return minf(1.5, 1.1 + 0.03 * up + 0.4 * screen)
		1:
			return 1.0
		2:
			return 1.05
	return 1.3


static func _mfac(m: float) -> float:
	return 0.55 + 0.45 * clampf(m, 0.0, 100.0) / 100.0


static func _armor(s: Dictionary) -> float:
	return 1.0 + 0.35 * float(s["armor"])


static func _vec(n: Object, prop: String) -> Vector2:
	var v = n.get(prop) if n != null else null
	return v if v is Vector2 else Vector2.ZERO


static func _choose(n: int, k: int) -> float:
	var c := 1.0
	for i in range(1, k + 1):
		c = c * (n - k + i) / i
	return c


static func _with(ctx: Dictionary, key: String, value) -> Dictionary:
	var c := ctx.duplicate()
	c[key] = value
	return c


static func _result_problems(r: Dictionary, label: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var o := str(r.get("outcome", ""))
	if not TITLES.has(o):
		bad.append("%s 了局键不认得：%s" % [label, o])
		return bad
	if str(r["title"]) != outcome_title(o) or str(r["legacy"]) != legacy_outcome(r):
		bad.append("%s 题签 / legacy 与了局不符" % label)
	var cas_a := int(r["att_cas"])
	if cas_a < 0 or int(r["def_cas"]) < 0 or cas_a > int(r["att_crew"]) or int(r["def_cas"]) > int(r["def_crew"]):
		bad.append("%s 伤亡出界：攻 %d / %d，守 %d / %d" % [label, cas_a, r["att_crew"], r["def_cas"], r["def_crew"]])
	if int(r["att_dead"]) + int(r["att_hurt"]) != cas_a or int(r["att_dead"]) < 0 or int(r["att_hurt"]) < 0:
		bad.append("%s 阵亡 + 轻伤 ≠ 伤亡" % label)
	if int(r["prisoners"]) + int(r["overboard"]) + int(r["def_cas"]) > int(r["def_crew"]):
		bad.append("%s 俘获 + 跳海 + 伤亡超过敌船人数" % label)
	if int(r["prisoners"]) > 0 and legacy_outcome(r) != "win":
		bad.append("%s 没夺船却有俘获" % label)
	var rounds: Array = r["rounds"]
	if rounds.size() != int(r["rounds_fought"]) or rounds.size() > ROUNDS_MAX:
		bad.append("%s 合数记账不符" % label)
	for rd in rounds:
		if str(rd.get("text", "")) == "" or int(rd["att"]) < 0 or int(rd["def"]) < 0:
			bad.append("%s 第 %d 合记录不全或人数为负" % [label, int(rd.get("n", 0))])
	if str(r["summary"]).strip_edges() == "" or str(r["summary"]).find("！") >= 0:
		bad.append("%s 了局注记空或带叹号" % label)
	return bad
