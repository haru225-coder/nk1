## 舷战弹道（lane combat03）：宋元近海的矢、石、床子弩与少量火器——飞有时、落有散、射界随舷角。
## 不是近代舰炮：弓弩手倚舷攒射、床子弩发大箭钉船板、砲（旋风砲）抛石越顶而落、火箭 / 火砲只在有火药时放。
## 纯数据 + 静态函数，不读 autoload（-s 探针可直接 preload）；Cannonball 按本件出的「一发」飞，
## ReloadAmmo 按本件的武器表管装填与弹药。调用方 duck-type 接，最短写法：
##   const _Ballistics := preload("res://scripts/combat/Ballistics.gd")
##   const _ReloadAmmo := preload("res://scripts/combat/ReloadAmmo.gd")
##   battery = _ReloadAmmo.for_ship(ship_def, crew)            # 开战时一船一份
##   battery.tick(delta, crew, morale01)                          # 每帧（_physics_process）
##   var n: int = _Ballistics.fire_volley(self, battery, side, target)   # 开一舷；0 = 没放出去，原因 battery.last_refusal
## 旧调用方（Ship / PirateShip 只写 position / direction / shooter）不必改：Cannonball 按床子弩补成一发（legacy_shot）。
## 别的 lane 的件在就读、不在不读（都按名字 duck-type，不 preload）：射手的 damage_model（combat04）给散布 / 一轮几成 / 此舷倾没倾；
## 当场 SeaState.active()（combat02）给风——射手自己带 wind_vector / wind_strength（Ship）时先用自己的。
##
## 坐标口径同 Ship.gd：船首 = Vector2.UP.rotated(rotation)；side = -1 左舷（Vector2.LEFT.rotated）/ +1 右舷（RIGHT）。
## 「舷角」off_beam = 目标方位偏离本舷正横的角度（0 = 正横，PI/2 = 正船首或正船尾）。
## 尺度是战术压缩后的像素（船长约 280 px），各武器之间的远近快慢、散布、装填才是要守的比例。
extends RefCounted

const PATH_DIRECT := "direct"  ## 平射：逐帧扫线段，先碰到哪条船算哪条
const PATH_LOB := "lob"  ## 抛射：越过中间的船，只在落点判

## 武器表。speed：平射为飞行速度、抛射为地面行进速度（px/s）；eff_range 以内不衰减，到 max_range 杀伤降到 far_mult；
## min_range 只对抛射有意义（砲抛不近）。spread：横向散布（弧度，每 px 射距的标准差），range_err：纵向散布（射距的比例）。
## arc_full / arc_max：离正横多少度以内全效 / 多少度以外够不着（床子弩架在舷边、转不开；砲立柱可转；弓弩手能挤到船头船尾）。
## reload：满员装填秒数；hands：一位（一队）要几个人手。hull / crew / sail：每中一发对船体 / 人员（期望伤亡人数）/ 帆索的杀伤，
## fire：引火几率；splash：抛射落点的溅及半径（px）；wind_k：受风偏的程度。ammo / ammo_per：每发耗哪种弹、耗多少。
## kind / amount：交给 DamageModel.apply_hit 的弹种（shot / stone / arrow / bolt / fire / bomb）与命中点数（它按「每 25 点」配伤）。
## fx：命中时 CombatFx.on_missile_hit 的观感（stone 木屑尘烟 / bolt 木屑少 / fire 火星焦烟 / bomb 一闪火药烟）；空 = 一排矢、几块抛石，不出命中观感。
const WEAPONS := {
	"gongnu": {
		"name": "弓弩", "note": "弓弩手一队四人倚舷齐发一排矢。宋军以弩为长技。",
		"path": PATH_DIRECT, "ammo": "jian", "ammo_per": 4,
		"speed": 520.0, "min_range": 0.0, "eff_range": 300.0, "max_range": 500.0, "far_mult": 0.3,
		"spread": 0.045, "range_err": 0.07, "arc_full": 60.0, "arc_max": 115.0,
		"reload": 4.5, "hands": 4, "hull": 0.5, "crew": 0.8, "sail": 0.4, "fire": 0.0,
		"splash": 0.0, "wind_k": 0.10, "heavy": false,
		"kind": "arrow", "amount": 12.0, "fx": "",
	},
	"huojian": {
		"name": "火箭", "note": "箭杆缚火药筒，射帆索、舱面。火攻令下、有火药才放。",
		"path": PATH_DIRECT, "ammo": "jian", "ammo_per": 4, "powder": 4,
		"speed": 470.0, "min_range": 0.0, "eff_range": 260.0, "max_range": 440.0, "far_mult": 0.35,
		"spread": 0.055, "range_err": 0.08, "arc_full": 60.0, "arc_max": 115.0,
		"reload": 5.5, "hands": 4, "hull": 0.6, "crew": 0.4, "sail": 1.0, "fire": 0.18,
		"splash": 0.0, "wind_k": 0.12, "heavy": false,
		"kind": "fire", "amount": 12.0, "fx": "fire",
	},
	"chuangnu": {
		"name": "床子弩", "note": "绞车张弦，发大箭可钉入船板。架在舷边，射界窄。",
		"path": PATH_DIRECT, "ammo": "nujian", "ammo_per": 1,
		"speed": 640.0, "min_range": 0.0, "eff_range": 520.0, "max_range": 820.0, "far_mult": 0.5,
		"spread": 0.020, "range_err": 0.04, "arc_full": 30.0, "arc_max": 62.0,
		"reload": 13.0, "hands": 5, "hull": 22.0, "crew": 0.6, "sail": 1.5, "fire": 0.0,
		"splash": 0.0, "wind_k": 0.03, "heavy": true,
		"kind": "bolt", "amount": 25.0, "fx": "bolt",
	},
	"hanya": {
		"name": "寒鸦箭", "note": "大弩箭用尽，床子弩改兜一簇小箭齐发，杀人不破船。",
		"path": PATH_DIRECT, "ammo": "jian", "ammo_per": 8,
		"speed": 560.0, "min_range": 0.0, "eff_range": 400.0, "max_range": 640.0, "far_mult": 0.3,
		"spread": 0.060, "range_err": 0.06, "arc_full": 30.0, "arc_max": 62.0,
		"reload": 14.0, "hands": 5, "hull": 2.0, "crew": 1.6, "sail": 0.8, "fire": 0.0,
		"splash": 0.0, "wind_k": 0.08, "heavy": true,
		"kind": "arrow", "amount": 22.0, "fx": "bolt",
	},
	"pao": {
		"name": "砲", "note": "旋风砲立柱可转，拽索抛石，越顶而落。抛不近。",
		"path": PATH_LOB, "ammo": "shi", "ammo_per": 1,
		"speed": 300.0, "min_range": 160.0, "eff_range": 440.0, "max_range": 620.0, "far_mult": 0.9,
		"spread": 0.050, "range_err": 0.10, "arc_full": 75.0, "arc_max": 110.0,
		"reload": 11.0, "hands": 8, "hull": 30.0, "crew": 1.2, "sail": 0.8, "fire": 0.0,
		"splash": 20.0, "wind_k": 0.05, "heavy": true,
		"kind": "stone", "amount": 30.0, "fx": "stone",
	},
	"huopao": {
		"name": "火砲", "note": "砲抛火药弹（火毬、铁壳火砲），引信燃着飞去，落处起火。火攻令下、火药够才抛。",
		"path": PATH_LOB, "ammo": "huoyao", "ammo_per": 24,
		"speed": 280.0, "min_range": 160.0, "eff_range": 400.0, "max_range": 560.0, "far_mult": 0.9,
		"spread": 0.060, "range_err": 0.12, "arc_full": 75.0, "arc_max": 110.0,
		"reload": 12.0, "hands": 8, "hull": 8.0, "crew": 1.0, "sail": 2.0, "fire": 0.55,
		"splash": 30.0, "wind_k": 0.06, "heavy": true,
		"kind": "bomb", "amount": 20.0, "fx": "bomb",
	},
	"pao_ballast": {
		"name": "砲·压舱石", "note": "石弹抛完，拆压舱石硬抛：石小形杂，准头差、装得慢；拆多了船不稳，只拆得出几块。",
		"path": PATH_LOB, "ammo": "yacang", "ammo_per": 1,
		"speed": 290.0, "min_range": 160.0, "eff_range": 380.0, "max_range": 540.0, "far_mult": 0.9,
		"spread": 0.070, "range_err": 0.14, "arc_full": 75.0, "arc_max": 110.0,
		"reload": 14.0, "hands": 8, "hull": 16.0, "crew": 0.8, "sail": 0.5, "fire": 0.0,
		"splash": 16.0, "wind_k": 0.05, "heavy": true,
		"kind": "stone", "amount": 16.0, "fx": "stone",
	},
	"paoshi": {
		"name": "抛石", "note": "箭尽，弓弩手拾石、灰罐乱掷，只够得着贴舷的船。",
		"path": PATH_LOB, "ammo": "", "ammo_per": 0,
		"speed": 220.0, "min_range": 0.0, "eff_range": 110.0, "max_range": 180.0, "far_mult": 1.0,
		"spread": 0.120, "range_err": 0.20, "arc_full": 80.0, "arc_max": 130.0,
		"reload": 3.0, "hands": 4, "hull": 1.0, "crew": 0.4, "sail": 0.0, "fire": 0.0,
		"splash": 8.0, "wind_k": 0.05, "heavy": false,
		"kind": "stone", "amount": 3.0, "fx": "",
	},
}

## 弹药名与计数单位（ReloadAmmo.ammo 的键）。火药以两计，十六两为一斤。压舱石是石弹抛完后的代用，只拆得出几块。
const AMMO := {
	"jian": {"name": "箭", "unit": "支"},
	"nujian": {"name": "弩箭", "unit": "枝"},
	"shi": {"name": "石弹", "unit": "颗"},
	"yacang": {"name": "压舱石", "unit": "块"},
	"huoyao": {"name": "火药", "unit": "两"},
}

## 旧调用方（只给 direction 的 Cannonball）按这种武器补成一发。
const LEGACY_WEAPON := "chuangnu"
## 船体椭圆（半长 × 半宽）按船图量：Ship / PirateShip 的 512² 船图 ×0.62，船身约长 280、宽 100 px。
## 目标自己有 hull_footprint() -> Vector2(半长, 半宽) 的以它为准（DamageModel / 新船型可自带）。
const HULL_LEN_K := 0.44
const HULL_BEAM_K := 0.16
const HULL_DEFAULT := Vector2(24.0, 24.0)
## 平射落近这么多（px）照样钉在船舷上：船舷有高，矢是斜着扎下去的。Cannonball 落水前按它再判一次。
const FREEBOARD := 14.0
## 平射也有弧：射得越近越平，一路都低得能扎进船身；射到最大射程，矢在半空高过船舷，只有落下来那一段（至少 15%）才打得着船。
## plan_shot 记 low_from = 落距 ×（1 − 低飞段比例），Cannonball 飞过 low_from 之前越顶而过（中间挡着的船不挨）。
const DIRECT_LOW_K := 0.85
const DIRECT_LOW_MIN := 0.15
## 抛射的视觉拱高（落距的比例）；只画，不参与判定。
const LOB_APEX_K := 0.28
## 装填手估提前量的误差（目标速度 × 飞行时间的比例）。
const LEAD_ERR_K := 0.15
## 风偏基准：风力 160 算作 1 档（WorldMap 海战固定 80，风暴 160–280）。
const WIND_REF := 160.0
## 本船航速带来的平台晃动：到 300 px/s（满帆）散布再加 35%。
const PLATFORM_SPEED_REF := 300.0
const PLATFORM_SPREAD_K := 0.35
## 士气低的散布放大（士气 0 时 +40%）。
const MORALE_SPREAD_K := 0.4

## 风大浪高船摇：风力 60 以下不算，到 200 散布放大到 1.6 倍（volley_mods 的 sea_roll 缺省按风力折）。
const ROLL_WIND_LO := 60.0
const ROLL_WIND_HI := 200.0
const ROLL_SPREAD_K := 0.6

const CANNONBALL_SCENE := "res://scenes/Cannonball.tscn"
const SEA_STATE_PATH := "res://scripts/combat/SeaState.gd"
const SQRT2 := 1.4142135623730951


## 武器条目（未知 id 回落床子弩，免得拼错一个 id 整舷哑火）。
static func weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS[LEGACY_WEAPON])


static func has_weapon(id: String) -> bool:
	return WEAPONS.has(id)


static func weapon_name(id: String) -> String:
	return str(weapon(id).get("name", id))


static func ammo_name(kind: String) -> String:
	return str(AMMO.get(kind, {}).get("name", kind))


static func ammo_unit(kind: String) -> String:
	return str(AMMO.get(kind, {}).get("unit", ""))


static func is_lob(id: String) -> bool:
	return str(weapon(id).get("path", PATH_DIRECT)) == PATH_LOB


static func is_heavy(id: String) -> bool:
	return bool(weapon(id).get("heavy", false))


# ── 舷角 ──────────────────────────────────────────────

## 本舷正横方向（单位向量）。
static func beam_dir(rot: float, side: int) -> Vector2:
	return Vector2.RIGHT.rotated(rot) * (1.0 if side >= 0 else -1.0)


## 目标在哪一舷：+1 右舷，-1 左舷（正前正后算右舷）。
static func side_of(rot: float, from: Vector2, to: Vector2) -> int:
	return 1 if (to - from).dot(Vector2.RIGHT.rotated(rot)) >= 0.0 else -1


## 目标偏离本舷正横的角度，0..PI。目标在另一舷时大于 PI/2。
static func off_beam(rot: float, side: int, from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length_squared() < 0.0001:
		return 0.0
	return absf(beam_dir(rot, side).angle_to(d))


## 这种武器在这个舷角还能发挥几成：全效弧内 1，过了全效弧按余弦收到射界边上为 0。
static func bearing_factor(id: String, off_beam_rad: float) -> float:
	var w := weapon(id)
	var full := deg_to_rad(float(w.get("arc_full", 30.0)))
	var lim := deg_to_rad(float(w.get("arc_max", 60.0)))
	var off := absf(off_beam_rad)
	if off <= full:
		return 1.0
	if off >= lim or lim <= full:
		return 0.0
	return 0.5 * (1.0 + cos(PI * (off - full) / (lim - full)))


## 有效射程随舷角：正横最远，偏向船首船尾缩到六成（舷角外为 0）。
static func effective_range(id: String, off_beam_rad := 0.0) -> float:
	var bf := bearing_factor(id, off_beam_rad)
	if bf <= 0.0:
		return 0.0
	return float(weapon(id).get("eff_range", 300.0)) * (0.6 + 0.4 * bf)


## 最远够得着的射距（同上随舷角缩）。
static func max_reach(id: String, off_beam_rad := 0.0) -> float:
	var bf := bearing_factor(id, off_beam_rad)
	if bf <= 0.0:
		return 0.0
	return float(weapon(id).get("max_range", 500.0)) * (0.6 + 0.4 * bf)


## 远距衰减：有效射程以内 1，到最大射程降到 far_mult，再远按 far_mult。
static func falloff(id: String, dist: float) -> float:
	var w := weapon(id)
	var eff := float(w.get("eff_range", 300.0))
	var mx := float(w.get("max_range", 500.0))
	var far := float(w.get("far_mult", 0.5))
	if dist <= eff or mx <= eff:
		return 1.0
	return lerpf(1.0, far, clampf((dist - eff) / (mx - eff), 0.0, 1.0))


## 平射飞过多远之后才低得能扎进船身（见 DIRECT_LOW_K 注）：落距越接近最大射程，前面越顶的那段越长。
static func direct_low_from(id: String, land_dist: float) -> float:
	var mx := maxf(1.0, float(weapon(id).get("max_range", 500.0)))
	var arc := clampf(land_dist / mx, 0.0, 1.0)
	var low := clampf(1.0 - DIRECT_LOW_K * arc * arc, DIRECT_LOW_MIN, 1.0)
	return maxf(0.0, land_dist) * (1.0 - low)


static func flight_time(id: String, dist: float) -> float:
	return maxf(0.0, dist) / maxf(1.0, float(weapon(id).get("speed", 500.0)))


## 提前量：目标以 target_vel 匀速走，弹以 speed 飞，求相遇点；解不出（追不上）就按直线飞时估。
static func lead_point(origin: Vector2, target_pos: Vector2, target_vel: Vector2, speed: float) -> Vector2:
	var r := target_pos - origin
	var t := -1.0
	var a := target_vel.dot(target_vel) - speed * speed
	var b := 2.0 * r.dot(target_vel)
	var c := r.dot(r)
	if absf(a) < 0.000001:
		if absf(b) > 0.000001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var s := sqrt(disc)
			var t1 := (-b - s) / (2.0 * a)
			var t2 := (-b + s) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2
	if t <= 0.0:
		t = r.length() / maxf(1.0, speed)
	return target_pos + target_vel * t


# ── 一发 ──────────────────────────────────────────────

## 按瞄点出一发：够不着的抬到最远处（落近），抛射抛不近的落在最近处；再按散布抽落点。
## 返回 Cannonball.configure 吃的字典：
##   weapon / name / path / origin / landing（全局坐标）/ flight_time / speed / apex / range（落距）/ reach
##   hull / crew / sail / fire（基数，未乘远距衰减与甲）/ kind / amount（DamageModel 口径）/ fx（命中观感）/ splash / quality /
##   short（够不着）/ heavy
##   low_from（平射飞过多远才低得能扎进船身）
## mods（都可缺省）：bear 舷角系数 0..1、spread_mult、range_mult、lead_err（px，提前量误差）、
##   wind（风向 × 风力档，Vector2）、quality（代用弹等的杀伤成数）、side / slot（记账用）。
static func plan_shot(id: String, origin: Vector2, aim: Vector2, mods := {}, rng: RandomNumberGenerator = null) -> Dictionary:
	var w := weapon(id)
	var wid := id if WEAPONS.has(id) else LEGACY_WEAPON
	var to := aim - origin
	var d_req := to.length()
	var dir := to / d_req if d_req > 0.001 else Vector2.RIGHT
	var perp := dir.orthogonal()
	var bear := clampf(float(mods.get("bear", 1.0)), 0.0, 1.0)
	var range_mult := float(mods.get("range_mult", 1.0))
	var wind: Vector2 = mods.get("wind", Vector2.ZERO)
	var wind_k := float(w.get("wind_k", 0.0))
	# 顺风远、顶风近；横风把矢往下风推
	range_mult *= 1.0 + wind_k * dir.dot(wind)
	var reach := float(w.get("max_range", 500.0)) * (0.6 + 0.4 * bear) * maxf(0.2, range_mult)
	var min_r := float(w.get("min_range", 0.0))
	var short := d_req > reach
	var d_aim := clampf(d_req, min_r, maxf(min_r, reach))
	var spread_mult := maxf(0.1, float(mods.get("spread_mult", 1.0))) * (1.0 + 0.75 * (1.0 - bear))
	var sig_lat := float(w.get("spread", 0.03)) * d_aim * spread_mult
	var sig_rng := float(w.get("range_err", 0.05)) * d_aim * sqrt(spread_mult)
	var lead_err := maxf(0.0, float(mods.get("lead_err", 0.0)))
	var e_rng := _gauss(sig_rng, rng)
	var e_lat := _gauss(sqrt(sig_lat * sig_lat + lead_err * lead_err), rng)
	e_lat += wind_k * 0.5 * d_aim * perp.dot(wind)
	var d_land := clampf(d_aim + e_rng, maxf(0.0, min_r * 0.8), maxf(min_r, reach) * 1.05)
	var landing := origin + dir * d_land + perp * e_lat
	var dist := origin.distance_to(landing)
	var lob := str(w.get("path", PATH_DIRECT)) == PATH_LOB
	return {
		"weapon": wid, "name": str(w.get("name", wid)), "path": PATH_LOB if lob else PATH_DIRECT,
		"origin": origin, "landing": landing, "range": dist, "reach": reach, "short": short,
		"low_from": 0.0 if lob else direct_low_from(wid, dist),
		"speed": float(w.get("speed", 500.0)), "flight_time": flight_time(wid, dist),
		"apex": dist * LOB_APEX_K if lob else 0.0,
		"hull": float(w.get("hull", 0.0)), "crew": float(w.get("crew", 0.0)),
		"sail": float(w.get("sail", 0.0)), "fire": float(w.get("fire", 0.0)),
		"splash": float(w.get("splash", 0.0)), "heavy": bool(w.get("heavy", false)),
		"kind": str(w.get("kind", "shot")), "amount": float(w.get("amount", 25.0)), "fx": str(w.get("fx", "")),
		"quality": clampf(float(mods.get("quality", 1.0)), 0.0, 2.0),
		"side": int(mods.get("side", 0)), "slot": float(mods.get("slot", 0.0)),
	}


## 旧调用方的一发：只知道出膛点、方向与 Cannonball 的 speed / damage / lifetime。
## 按床子弩平射，飞到最远处落水（最远 = min(speed × lifetime, 床子弩最大射程)，落点前后略有参差）；
## 不给目标就没法定仰角，一路低飞（low_from = 0），先碰到哪条船算哪条；船体杀伤取 damage（原 25），远距照样衰减。
static func legacy_shot(origin: Vector2, dir: Vector2, speed: float, damage: float, lifetime: float,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var w := weapon(LEGACY_WEAPON)
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	var spd := speed if speed > 1.0 else float(w.get("speed", 640.0))
	var reach := float(w.get("max_range", 820.0))
	if lifetime > 0.0:
		reach = minf(reach, spd * lifetime)
	var d_land := maxf(1.0, reach * (1.0 + _gauss(float(w.get("range_err", 0.04)) * 0.5, rng)))
	var landing := origin + d * d_land
	return {
		"weapon": LEGACY_WEAPON, "name": str(w.get("name", "")), "path": PATH_DIRECT,
		"origin": origin, "landing": landing, "range": d_land, "reach": reach, "short": false,
		"low_from": 0.0,  # 旧调用方不给目标距离，没法定仰角：按平射，一路低飞、先碰到哪条算哪条（同原先）
		"speed": spd, "flight_time": d_land / spd, "apex": 0.0,
		"hull": damage, "crew": float(w.get("crew", 0.0)), "sail": float(w.get("sail", 0.0)),
		"fire": 0.0, "splash": 0.0, "heavy": true, "quality": 1.0, "side": 0, "slot": 0.0,
		"kind": str(w.get("kind", "bolt")), "amount": damage, "fx": str(w.get("fx", "bolt")),
		"legacy": true,
	}


# ── 船体椭圆 ──────────────────────────────────────────

## 目标船体椭圆 Vector2(半长, 半宽)：目标自带 hull_footprint() 的用它；否则按 Sprite2D 船图量；
## 再没有就退回碰撞圆半径（原先只认这 24 px 的圆，船身两头挨了矢也不算）。
static func hull_footprint(node: Node) -> Vector2:
	if node == null or not is_instance_valid(node):
		return HULL_DEFAULT
	if node.has_method("hull_footprint"):
		var v = node.call("hull_footprint")
		if v is Vector2 and v.x > 0.0 and v.y > 0.0:
			return v
	var n2 := node as Node2D
	var body_scale := n2.scale.abs() if n2 != null else Vector2.ONE
	var spr := node.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null and spr.texture != null:
		var sz := spr.texture.get_size() * spr.scale.abs() * body_scale
		return Vector2(sz.y * HULL_LEN_K, sz.x * HULL_BEAM_K)
	var cs := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		var r := (cs.shape as CircleShape2D).radius * maxf(body_scale.x, body_scale.y)
		return Vector2(r, r)
	return HULL_DEFAULT


## 全局坐标 p 换到船体局部并按椭圆归一：船首为 -y（同 Vector2.UP），船宽为 x。
static func _hull_unit(node: Node2D, p: Vector2, ab: Vector2) -> Vector2:
	var local := (p - node.global_position).rotated(-node.global_rotation)
	return Vector2(local.x / maxf(0.001, ab.y), local.y / maxf(0.001, ab.x))


## 点落在船体椭圆里（外扩 margin px）。
static func point_in_hull(node: Node2D, p: Vector2, margin := 0.0) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var ab := hull_footprint(node) + Vector2(margin, margin)
	return _hull_unit(node, p, ab).length_squared() <= 1.0


## 线段 p0→p1 与船体椭圆（外扩 margin px）的首个交点参数 t ∈ [0, 1]；p0 已在船里为 0；不交为 -1。
static func segment_hits_hull(node: Node2D, p0: Vector2, p1: Vector2, margin := 0.0) -> float:
	if node == null or not is_instance_valid(node):
		return -1.0
	var ab := hull_footprint(node) + Vector2(margin, margin)
	var u0 := _hull_unit(node, p0, ab)
	if u0.length_squared() <= 1.0:
		return 0.0
	var dv := _hull_unit(node, p1, ab) - u0
	var a := dv.dot(dv)
	if a < 0.0000001:
		return -1.0
	var b := 2.0 * u0.dot(dv)
	var c := u0.dot(u0) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var t1 := (-b - sqrt(disc)) / (2.0 * a)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	return -1.0


# ── 估算（给 AI / 状态条用，不抽随机数）────────────────

## 一发命中目标船体的估计几率。aspect = 射线与目标船长轴的夹角（0 = 对着船首船尾、PI/2 = 目标横着），
## target_ab 为目标船体 Vector2(半长, 半宽)。平射：打远了照样穿过船身，只怕落近（落近 FREEBOARD 以内钉在船舷上）；
## 抛射：前后左右都得落在船上。纵散大于横散，所以顺着船长打（目标对着船首船尾）反比打横着的船易中。
static func hit_chance(id: String, dist: float, off_beam_rad := 0.0, target_ab := Vector2(139.0, 51.0),
		aspect := PI / 2.0, mods := {}) -> float:
	var w := weapon(id)
	var bear := bearing_factor(id, off_beam_rad)
	if bear <= 0.0 or dist <= 0.0:
		return 0.0
	var reach := float(w.get("max_range", 500.0)) * (0.6 + 0.4 * bear) * float(mods.get("range_mult", 1.0))
	var sa := absf(sin(aspect))
	var ca := absf(cos(aspect))
	var half_w := sqrt(pow(target_ab.x * sa, 2.0) + pow(target_ab.y * ca, 2.0))
	var half_d := sqrt(pow(target_ab.x * ca, 2.0) + pow(target_ab.y * sa, 2.0))
	if dist > reach + half_d:
		return 0.0
	var d_aim := minf(dist, reach)
	var spread_mult := maxf(0.1, float(mods.get("spread_mult", 1.0))) * (1.0 + 0.75 * (1.0 - bear))
	var sig_lat := maxf(0.5, float(w.get("spread", 0.03)) * d_aim * spread_mult)
	var lead_err := float(mods.get("lead_err", 0.0))
	sig_lat = sqrt(sig_lat * sig_lat + lead_err * lead_err)
	var sig_rng := maxf(0.5, float(w.get("range_err", 0.05)) * d_aim * sqrt(spread_mult))
	var short_by := dist - d_aim  # 够不着时瞄点比目标近这么多
	var splash := float(w.get("splash", 0.0))
	var p_lat := _erf((half_w + splash) / (sig_lat * SQRT2))
	var p_rng := 0.0
	if str(w.get("path", PATH_DIRECT)) == PATH_LOB:
		var lo := -half_d - splash + short_by
		var hi := half_d + splash + short_by
		p_rng = 0.5 * (_erf(hi / (sig_rng * SQRT2)) - _erf(lo / (sig_rng * SQRT2)))
	else:
		# 落近不过 FREEBOARD 钉在船舷上；打远了，只要低飞段（low_from 之后）还压着船身就算中
		var lo2 := -half_d - FREEBOARD + short_by
		var low_span := d_aim - direct_low_from(id, d_aim)
		var hi2 := maxf(lo2, half_d + low_span + short_by)
		p_rng = 0.5 * (_erf(hi2 / (sig_rng * SQRT2)) - _erf(lo2 / (sig_rng * SQRT2)))
	return clampf(p_lat * p_rng, 0.0, 1.0)


## 误差函数（Abramowitz–Stegun 7.1.26，误差 < 1.5e-7）。
static func _erf(x: float) -> float:
	var s := 1.0 if x >= 0.0 else -1.0
	var ax := absf(x)
	var t := 1.0 / (1.0 + 0.3275911 * ax)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-ax * ax)
	return s * y


static func _gauss(sigma: float, rng: RandomNumberGenerator) -> float:
	if sigma <= 0.0:
		return 0.0
	return rng.randfn(0.0, sigma) if rng != null else randfn(0.0, sigma)


# ── 开一舷 ────────────────────────────────────────────

## 默认的散布 / 风偏修正（extra 里给了的键覆盖默认）：
##   spread_mult = 本船航速晃动 × 士气（battery.morale 0..1）× 风浪横摇（sea_roll 0..1，缺省按风力折）× 射手 damage_model.spread_factor()；
##   wind = 风向 × 风力档：射手的 wind_vector × wind_strength（Ship 有），没有就读 SeaState.active().wind_velocity()。
static func volley_mods(shooter: Node, battery = null, extra := {}) -> Dictionary:
	var mods := {}
	var spread_mult := 1.0
	var vel = shooter.get("velocity") if shooter != null else null
	if vel is Vector2:
		spread_mult *= 1.0 + PLATFORM_SPREAD_K * clampf((vel as Vector2).length() / PLATFORM_SPEED_REF, 0.0, 1.0)
	if battery != null:
		var m = battery.get("morale")
		if m != null:
			spread_mult *= 1.0 + MORALE_SPREAD_K * (1.0 - clampf(float(m), 0.0, 1.0))
	var wind_vel := _wind_of(shooter)
	if wind_vel.length_squared() > 0.0001:
		mods["wind"] = wind_vel.normalized() * clampf(wind_vel.length() / WIND_REF, 0.0, 1.5)
	var roll := float(extra.get("sea_roll", clampf((wind_vel.length() - ROLL_WIND_LO) / (ROLL_WIND_HI - ROLL_WIND_LO), 0.0, 1.0)))
	spread_mult *= 1.0 + ROLL_SPREAD_K * clampf(roll, 0.0, 1.0)
	var dm := damage_model_of(shooter)
	if dm != null and dm.has_method("spread_factor"):
		spread_mult *= maxf(1.0, float(dm.call("spread_factor")))
	mods["spread_mult"] = spread_mult
	for k in extra:
		mods[k] = extra[k]
	return mods


## 射手身上的风（吹向 × 风力）：自己带 wind_vector / wind_strength 的用自己的，否则读当场 SeaState；都没有为零。
static func _wind_of(shooter: Node) -> Vector2:
	var wv = shooter.get("wind_vector") if shooter != null else null
	var ws = shooter.get("wind_strength") if shooter != null else null
	if wv is Vector2 and ws != null and (wv as Vector2).length_squared() > 0.0001:
		return (wv as Vector2).normalized() * float(ws)
	var ss := sea_state()
	if ss != null and ss.has_method("wind_velocity"):
		var v = ss.call("wind_velocity")
		if v is Vector2:
			return v
	return Vector2.ZERO


## 当场海况（combat02 SeaState.active()）；脚本不在或没开战为 null。
static func sea_state() -> Object:
	if not ResourceLoader.exists(SEA_STATE_PATH):
		return null
	var scr = load(SEA_STATE_PATH)
	if not (scr is Script):
		return null
	for m in (scr as Script).get_script_method_list():
		if str(m.get("name", "")) == "active" and (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) != 0 and (m.get("args", []) as Array).is_empty():
			var ss = scr.call("active")
			return ss if ss is Object else null
	return null


## 射手的分系统损伤（combat04 挂在 Ship.damage_model，RefCounted）；没有为 null。
static func damage_model_of(shooter: Node) -> Object:
	if shooter == null or not is_instance_valid(shooter):
		return null
	var dm = shooter.get("damage_model")
	return dm if dm is Object else null


## 开一舷：向 battery（ReloadAmmo 实例，duck-type）要这一舷已装毕、舷角与射程够得着的位，逐位出一发，
## 生 Cannonball 挂到 shooter 的父节点下，返回实发数。0 = 没放出去（号令未及 / 未装毕 / 舷角外 / 射程不及 / 弹尽 /
## 缺人手），原因在 battery.last_refusal（中文，可直接上状态条）。
## target 为 Node2D 时按它的位置与 velocity 算提前量；为 null 时向本舷正横有效射程处盲射（不查射程）。
## mods：volley_mods 的键 + max_mounts（只放前 N 位，逐位轮放用）+ aim_point（Vector2，指定瞄点，不给 target 时用）。
## 射手带 damage_model 的：side_ready(side) 为假（船往这舷倾进水）不放；volley_factor() 不到 1 只放那几成位。
## target 故意不写类型：已释放的船传进带类型的形参当场 SCRIPT ERROR（同 tools/combat_probe_stage.gd 末注）。
static func fire_volley(shooter: Node2D, battery, side: int, target = null, mods := {}) -> int:
	if shooter == null or not is_instance_valid(shooter) or not shooter.is_inside_tree() or battery == null:
		return 0
	var world := shooter.get_parent()
	if world == null:
		return 0
	var sd := 1 if side >= 0 else -1
	var rot := shooter.global_rotation
	var pos := shooter.global_position
	var has_target: bool = is_instance_valid(target) and target is Node2D and (target as Node2D).is_inside_tree()
	var aim_default: Vector2 = mods.get("aim_point", Vector2.INF)
	var tpos := pos
	var tvel := Vector2.ZERO
	var off := 0.0
	var dist := -1.0
	if has_target:
		tpos = (target as Node2D).global_position
		var tv = target.get("velocity")
		if tv is Vector2:
			tvel = tv
		off = off_beam(rot, sd, pos, tpos)
		dist = pos.distance_to(tpos)
	elif aim_default != Vector2.INF:
		tpos = aim_default
		off = off_beam(rot, sd, pos, tpos)
		dist = pos.distance_to(tpos)
	var max_n := int(mods.get("max_mounts", 0))
	var dm := damage_model_of(shooter)
	if dm != null:
		# 船往这一舷倾进了水 / 炮位缺人、火烟呛人：打不出去，或一轮只放得出几成
		if dm.has_method("side_ready") and not bool(dm.call("side_ready", sd)):
			battery.set("last_refusal", "%s倾侧，打不出去" % ("右舷" if sd > 0 else "左舷"))
			return 0
		if dm.has_method("volley_factor"):
			var vf := clampf(float(dm.call("volley_factor")), 0.0, 1.0)
			if vf <= 0.0:
				battery.set("last_refusal", "%s炮位无人" % ("右舷" if sd > 0 else "左舷"))
				return 0
			if vf < 1.0 and battery.has_method("mount_count"):
				var cap := maxi(1, ceili(float(battery.call("mount_count", sd)) * vf))
				max_n = cap if max_n <= 0 else mini(max_n, cap)
	var picked: Array = battery.fire(sd, off, dist, max_n)
	if picked.is_empty():
		return 0
	var packed := load(CANNONBALL_SCENE) as PackedScene
	if packed == null:
		return 0
	var m := volley_mods(shooter, battery, mods)
	var ab := hull_footprint(shooter)
	var fwd := Vector2.UP.rotated(rot)
	var beam := beam_dir(rot, sd)
	var n := 0
	for e in picked:
		var wid := str(e.get("weapon", LEGACY_WEAPON))
		var slot := float(e.get("slot", 0.0))
		var origin := pos + fwd * (slot * ab.x * 0.75) + beam * (ab.y * 0.85)
		var spd := float(weapon(wid).get("speed", 500.0))
		var aim := origin + beam * effective_range(wid, 0.0)
		var lead_err := 0.0
		if has_target or aim_default != Vector2.INF:
			aim = lead_point(origin, tpos, tvel, spd)
			lead_err = tvel.length() * flight_time(wid, origin.distance_to(aim)) * LEAD_ERR_K
		var sm := m.duplicate()
		sm["bear"] = bearing_factor(wid, off_beam(rot, sd, origin, aim))
		sm["lead_err"] = lead_err
		sm["side"] = sd
		sm["slot"] = slot
		sm["quality"] = float(e.get("quality", 1.0))
		var shot := plan_shot(wid, origin, aim, sm)
		var cb := packed.instantiate()
		if cb.has_method("configure"):
			cb.configure(shot)
		cb.set("shooter", shooter)
		cb.set("direction", (shot["landing"] - origin).normalized())
		world.add_child(cb)
		n += 1
	return n
