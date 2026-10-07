## 舷位装填与弹药（lane combat03）：一船一份。床子弩、砲分位各自装填，一舷两次齐射之间要等号令；
## 弓弩手不分舷，换舷得跑过甲板。弹药有定额：告急（余量不到四分之一）则慎发、装得慢；
## 用尽则改代用——箭尽拾石乱掷、大弩箭尽改兜寒鸦箭、石弹尽拆压舱石（只拆得出几块）；代用也没了的那一位就哑了。
## 不读 autoload：水手数、士气（与损伤的装填倍数）由调用方每帧喂进 tick()；火攻令、操帆 / 专力装填由指令改 fire_mode / emphasis。
## 用法见 Ballistics.gd 头注。AI / 士气 / 状态条读 ready_count / reload_left / ammo_state / ammo_frac / is_low / is_spent /
## status_line / combat_status（CombatStatusHud 的快照键）；只要一个数的调用方用 captain_reload_time / captain_volleys。
extends RefCounted

const Ballistics := preload("res://scripts/combat/Ballistics.gd")
## 本件自己（for_ship 的返回类型：调用方 `var battery := ReloadAmmo.for_ship(…)` 可推断，方法调用照样静态检查）
const _SELF := preload("res://scripts/combat/ReloadAmmo.gd")
## 船型表（captain_volleys 按船型 id 查，不经 GameManager）
const SHIPS_PATH := "res://data/ships.json"

const SIDE_PORT := -1
const SIDE_STARBOARD := 1
## 弓弩手一队几人：一队放一排矢，耗箭 = 人数（Ballistics 里弓弩 ammo_per 同数）
const SQUAD := 4
const SQUAD_MAX := 10
## 同一舷两次齐射至少隔几秒：放完要整队、报数、等令
const VOLLEY_GAP := 1.2
## 弓弩手从一舷跑到另一舷
const SHIFT_TIME := 2.0
## 余量低于这个比例算告急：慎发，装填 ×LOW_RELOAD_MULT
const LOW_RATIO := 0.25
const LOW_RELOAD_MULT := 1.35
## 人手分派：操帆掌舵留几成人（其余上炮位 / 弓弩）。balanced 常态；sail 抢风；guns 专力装填
const SAIL_SHARE := {"balanced": 0.3, "sail": 0.5, "guns": 0.15}
## 士气 0 时装填慢三成
const MORALE_RELOAD_K := 0.3
## 一队弓弩手不到半数人就成不了排
const MIN_MANNED := 0.5
## 配弹档（tier_of）：war 宋水军战船 / 官式大船——弓弩手多、带砲、弹药足；
## raider 海寇快船——弓弩手多，重器少、大箭石弹带得少，仗着跳帮；merchant 商船——护船的弓弩、几位床子弩
const ARCHER_SHARE := {"war": 0.35, "raider": 0.35, "merchant": 0.25}
## 弹药定额：每名弓弩手几支箭、每位床子弩几枝大箭、每位砲几颗石
const ARROWS_PER_ARCHER := {"war": 40, "raider": 30, "merchant": 25}
const BOLTS_PER_MOUNT := {"war": 16, "raider": 8, "merchant": 12}
const STONES_PER_MOUNT := {"war": 14, "raider": 6, "merchant": 10}
## 石弹抛完每位砲还拆得出几块压舱石（拆多了船不稳）
const BALLAST_PER_MOUNT := {"war": 6, "raider": 4, "merchant": 6}
## 代用弹：不按告急慎发，也不算进「远射弹药余量」
const SUBSTITUTE_AMMO := ["yacang"]
## 弹尽哑火时报哪位（原配武器）
const MOUNT_NAMES := {"gongnu": "弓弩", "chuangnu": "床子弩", "pao": "炮"}
## 一位也没放出去时，拒放原因按这个次序报
const REFUSAL_ORDER := ["舷角外", "射程不及", "太近", "弹尽", "未装毕", "换舷", "缺人手"]
## CombatStatusHud 快照的弹种键（combat08 的 AMMO_NAMES：arrow 矢 / bolt 弩 / stone 石 / gunpowder 药）
const HUD_AMMO_KEYS := {"jian": "arrow", "nujian": "bolt", "shi": "stone", "yacang": "stone", "huoyao": "gunpowder"}
## 状态条上「装不动」写成的秒数
const HUD_STALLED := 99.0

## 每位：{weapon 原配（gongnu / chuangnu / pao）, side -1 / +1（弓弩队 0，不分舷）, slot 船首 +1…船尾 -1,
##        t 余装填秒（0 = 已装毕）, hands 一位要几人, manned 本帧分到几成人手, at 弓弩队此刻在哪舷（0 = 甲板中）, move 换舷余秒}
var mounts: Array = []
## 现存弹药 {jian 支, nujian 枝, shi 颗, yacang 压舱石块, huoyao 两}；ammo_max 为定额（告急按它算比例）
var ammo: Dictionary = {}
var ammo_max: Dictionary = {}
## 火攻令：弓弩手改放火箭、砲改抛火砲（火药够才放，不够照常放箭抛石）
var fire_mode := false
## 人手侧重（SAIL_SHARE 的键）
var emphasis := "balanced"
var crew := 0
## 士气 0..1（调用方换算：玩家 Fleet.morale / 100，敌船 enemy_morale / 100）
var morale := 1.0
## 装填时长倍数（≥ 1）：船上火烟、倾侧、炮位伤损拖慢装填（combat04 DamageModel.reload_factor()，tick 喂进来）
var reload_mult := 1.0
var tier := "merchant"
## tier 不是 merchant（战船、海寇快船）
var warship := false
## 最近一次没放出去的原因（中文，可直接上状态条）；放出去了清空
var last_refusal := ""
var shots_fired := 0
var volleys := 0
## w53-2 二期：玩家船的弓弩手按人头折算威力（archer_scaling 由 Ship 写入；1.0 等价原状）。Cannonball._strike 把 quality 乘在杀伤上。
var volley_quality := 1.0
## w53-p3b：调用方刚放出去那一批弹的引火乘数（号令「火攻」的 ignite × 风位折算，Ship 发完一舷写在这里并当即盖到那一批
## Cannonball 的 shot["fire"] 上；缺省 1.0 = 不乘，与 wave53 开工前同）。簿自己不读它——谁放谁用
var last_volley_ignite := 1.0
var _gap := {-1: 0.0, 1: 0.0}
static var _ship_defs := {}


## 按船型出一份：ship_def 为 ships.json 的一条（Fleet.ship_def(type)），crew_n 为这船的水手数。
## opts（都可缺省）：heavy_per_side 每舷重器位数（敌船传 cannon_count，缺省 ceil(cannon_slots / 2)）、
##   pao_per_side 其中几位是砲、squads 弓弩队数、tier 配弹档（war / raider / merchant；旧键 warship: true 同 war）、
##   ammo_mult 定额倍数、ammo 现存弹药（续用上一仗的余量；缺的键按定额）。
static func for_ship(ship_def: Dictionary, crew_n: int, opts := {}) -> _SELF:
	var ra := _SELF.new()
	ra.setup(ship_def, crew_n, opts)
	return ra


func setup(ship_def: Dictionary, crew_n: int, opts := {}) -> void:
	mounts.clear()
	crew = maxi(0, crew_n)
	tier = str(opts.get("tier", "war" if bool(opts.get("warship", false)) else tier_of(ship_def)))
	if not ARCHER_SHARE.has(tier):
		tier = "merchant"
	warship = tier != "merchant"
	var slots := int(ship_def.get("cannon_slots", 0))
	var per_side := maxi(0, int(opts.get("heavy_per_side", ceili(float(slots) / 2.0))))
	var n_pao := clampi(int(opts.get("pao_per_side", _pao_per_side(ship_def, per_side, tier))), 0, per_side)
	var kinds: Array = []
	for i in range(per_side):
		kinds.append("chuangnu")
	# 砲立在舯部，床子弩分列首尾
	var start := floori((per_side - n_pao) / 2.0)
	for j in range(n_pao):
		kinds[start + j] = "pao"
	for sd in [SIDE_PORT, SIDE_STARBOARD]:
		for i in range(per_side):
			mounts.append(_mount(kinds[i], sd, _slot(i, per_side)))
	var squads := int(opts.get("squads", clampi(roundi(float(crew) * float(ARCHER_SHARE[tier]) / float(SQUAD)), 1, SQUAD_MAX)))
	for i in range(maxi(0, squads)):
		mounts.append(_mount("gongnu", 0, _slot(i, squads) * 0.8))
	ammo_max = _default_stock(ship_def, float(opts.get("ammo_mult", 1.0)))
	ammo = ammo_max.duplicate()
	var carried: Dictionary = opts.get("ammo", {})
	for k in carried:
		if ammo.has(k):
			ammo[k] = maxi(0, int(carried[k]))
			ammo_max[k] = maxi(int(ammo_max[k]), int(ammo[k]))
	_assign_hands()


## 配弹档：船种分类写「战」「官」的是 war；「快船」或不上架（for_sale false，只能夺来）的是 raider；其余 merchant。
static func tier_of(ship_def: Dictionary) -> String:
	var cls := str(ship_def.get("class", ""))
	if cls.find("战") >= 0 or cls.find("官") >= 0:
		return "war"
	if cls.find("快船") >= 0 or ship_def.get("for_sale", true) == false:
		return "raider"
	return "merchant"


## 战船或海寇快船（弓弩手多、弹药另按档配）。
static func is_warship(ship_def: Dictionary) -> bool:
	return tier_of(ship_def) != "merchant"


static func _pao_per_side(ship_def: Dictionary, per_side: int, p_tier: String) -> int:
	if per_side <= 0:
		return 0
	if p_tier == "war":
		return floori(per_side / 3.0)
	if p_tier == "raider":
		return floori(per_side / 4.0)
	return 1 if per_side >= 3 and float(ship_def.get("capacity", 0)) >= 1500.0 else 0


static func _slot(i: int, n: int) -> float:
	if n <= 1:
		return 0.0
	return lerpf(0.8, -0.8, float(i) / float(n - 1))


static func _mount(wid: String, side: int, slot: float) -> Dictionary:
	return {
		"weapon": wid, "side": side, "slot": slot, "t": 0.0,
		"hands": int(Ballistics.weapon(wid).get("hands", 4)), "manned": 1.0, "at": 0, "move": 0.0,
	}


func _default_stock(ship_def: Dictionary, mult: float) -> Dictionary:
	var n_cn := 0
	var n_pao := 0
	var n_sq := 0
	for m in mounts:
		match str(m["weapon"]):
			"chuangnu":
				n_cn += 1
			"pao":
				n_pao += 1
			_:
				n_sq += 1
	var powder := 16
	if tier == "war":
		powder = 96 + 24 * n_pao + 8 * n_sq
	elif tier == "raider":
		powder = 48 + 8 * n_sq
	elif float(ship_def.get("capacity", 0)) >= 800.0:
		powder = 48
	var m2 := maxf(0.0, mult)
	return {
		"jian": roundi(n_sq * SQUAD * int(ARROWS_PER_ARCHER[tier]) * m2),
		"nujian": roundi(n_cn * int(BOLTS_PER_MOUNT[tier]) * m2),
		"shi": roundi(n_pao * int(STONES_PER_MOUNT[tier]) * m2),
		"yacang": roundi(n_pao * int(BALLAST_PER_MOUNT[tier]) * m2),
		"huoyao": roundi(powder * m2),
	}


# ── 每帧 ──────────────────────────────────────────────

## 推进装填：crew_n / morale01 / p_reload_mult 给了就更新（< 0 表示沿用上一次）。
## 人手按 _assign_hands 分，分到几成人手按几成速度装；士气低、reload_mult 大（火烟倾侧）再慢。
func tick(delta: float, crew_n := -1, morale01 := -1.0, p_reload_mult := -1.0) -> void:
	if crew_n >= 0:
		crew = crew_n
	if morale01 >= 0.0:
		morale = clampf(morale01, 0.0, 1.0)
	if p_reload_mult >= 0.0:
		reload_mult = maxf(1.0, p_reload_mult)
	for k in _gap:
		_gap[k] = maxf(0.0, float(_gap[k]) - delta)
	_assign_hands()
	for m in mounts:
		if float(m["move"]) > 0.0:
			m["move"] = maxf(0.0, float(m["move"]) - delta)
		if float(m["t"]) > 0.0:
			m["t"] = maxf(0.0, float(m["t"]) - delta * _rate(m))


## 这一位此刻的装填速度（满员常态为 1）。
func _rate(m: Dictionary) -> float:
	return float(m["manned"]) * (1.0 - MORALE_RELOAD_K * (1.0 - morale)) / maxf(1.0, reload_mult)


func _hands_pool() -> float:
	return float(crew) * (1.0 - float(SAIL_SHARE.get(emphasis, SAIL_SHARE["balanced"])))


## 要人手的位：正在装的重器（绞弦、拽索离不开人）与各队弓弩手；已装毕的重器等着放，不占人手。
static func _needs_hands(m: Dictionary) -> bool:
	return not Ballistics.is_heavy(str(m["weapon"])) or float(m["t"]) > 0.0


## 人手不够时按比例分：要人手的位都慢下来（分到几成人手就按几成的速度装），弓弩队不到半数人成不了排。
func _assign_hands() -> void:
	var need := 0.0
	for m in mounts:
		if _needs_hands(m):
			need += float(m["hands"])
	var ratio := 1.0 if need <= 0.0 else clampf(_hands_pool() / need, 0.0, 1.0)
	for m in mounts:
		m["manned"] = ratio if _needs_hands(m) else 1.0


# ── 开火 ──────────────────────────────────────────────

## 这一舷放一轮：返回实放的每一位 [{weapon 实发武器, slot, mount 位号, side, quality}]，并扣弹药、起装填钟、记号令间隔。
## off_beam：目标舷角（弧度），dist：目标距离（< 0 = 盲射，不查射程），max_n > 0 只放前 N 位。
## 一位也没放出去返回 []，原因写进 last_refusal。
func fire(side: int, off_beam := 0.0, dist := -1.0, max_n := 0) -> Array:
	return _select(side, off_beam, dist, max_n, true)


## 同 fire 的判定但不动任何状态：此刻下令这一舷能不能放出至少一位。
func can_fire(side: int, off_beam := 0.0, dist := -1.0) -> bool:
	return not _select(side, off_beam, dist, 1, false).is_empty()


func _select(side: int, off_beam: float, dist: float, max_n: int, commit: bool) -> Array:
	var sd := SIDE_STARBOARD if side >= 0 else SIDE_PORT
	var out: Array = []
	if float(_gap[sd]) > 0.0:
		if commit:
			last_refusal = "%s号令未及" % side_name(sd)
		return out
	var why := {}
	var dry := {}
	var wait := INF
	for i in range(mounts.size()):
		var m: Dictionary = mounts[i]
		var ms := int(m["side"])
		if ms != 0 and ms != sd:
			continue
		if ms == 0:
			if float(m["move"]) > 0.0:
				why["换舷"] = int(why.get("换舷", 0)) + 1
				continue
			var at := int(m["at"])
			if at != 0 and at != sd:
				if commit:
					m["move"] = SHIFT_TIME
					m["at"] = sd
				why["换舷"] = int(why.get("换舷", 0)) + 1
				continue
			if float(m["manned"]) < MIN_MANNED:
				why["缺人手"] = int(why.get("缺人手", 0)) + 1
				continue
		if float(m["t"]) > 0.0:
			var r := _rate(m)
			if r > 0.0:
				wait = minf(wait, float(m["t"]) / r)
			why["未装毕"] = int(why.get("未装毕", 0)) + 1
			continue
		var wid := shot_weapon(m)
		if wid == "":
			why["弹尽"] = int(why.get("弹尽", 0)) + 1
			dry[str(MOUNT_NAMES.get(str(m["weapon"]), m["weapon"]))] = true
			continue
		if Ballistics.bearing_factor(wid, off_beam) <= 0.0:
			why["舷角外"] = int(why.get("舷角外", 0)) + 1
			continue
		if dist >= 0.0:
			if dist > Ballistics.max_reach(wid, off_beam):
				why["射程不及"] = int(why.get("射程不及", 0)) + 1
				continue
			if dist < float(Ballistics.weapon(wid).get("min_range", 0.0)) * 0.9:
				why["太近"] = int(why.get("太近", 0)) + 1
				continue
		if commit:
			_consume(wid)
			m["t"] = float(Ballistics.weapon(wid).get("reload", 5.0)) * shortage_mult(wid)
			if ms == 0:
				m["at"] = sd
		out.append({"weapon": wid, "slot": float(m["slot"]), "mount": i, "side": sd, "quality": clampf(volley_quality, 0.2, 2.0)})
		if max_n > 0 and out.size() >= max_n:
			break
	if commit:
		if out.is_empty():
			last_refusal = _refusal_text(sd, why, wait, dry.keys())
		else:
			_gap[sd] = VOLLEY_GAP
			shots_fired += out.size()
			volleys += 1
			last_refusal = ""
	return out


## 这一位此刻实发什么（按弹药余量与火攻令换代用）；什么都发不了返回 ""。
func shot_weapon(m: Dictionary) -> String:
	match str(m.get("weapon", "")):
		"gongnu":
			if fire_mode and has_ammo_for("huojian"):
				return "huojian"
			return "gongnu" if has_ammo_for("gongnu") else "paoshi"
		"chuangnu":
			if has_ammo_for("chuangnu"):
				return "chuangnu"
			return "hanya" if has_ammo_for("hanya") else ""
		"pao":
			if fire_mode and has_ammo_for("huopao"):
				return "huopao"
			if has_ammo_for("pao"):
				return "pao"
			return "pao_ballast" if has_ammo_for("pao_ballast") else ""
	var base := str(m.get("weapon", ""))
	return base if Ballistics.has_weapon(base) and has_ammo_for(base) else ""


## 现存弹药够不够这种武器放一发（火箭另要火药）。
func has_ammo_for(wid: String) -> bool:
	var w := Ballistics.weapon(wid)
	var kind := str(w.get("ammo", ""))
	if kind != "" and int(ammo.get(kind, 0)) < int(w.get("ammo_per", 0)):
		return false
	var powder := int(w.get("powder", 0))
	return powder <= 0 or int(ammo.get("huoyao", 0)) >= powder


func _consume(wid: String) -> void:
	var w := Ballistics.weapon(wid)
	var kind := str(w.get("ammo", ""))
	if kind != "":
		ammo[kind] = maxi(0, int(ammo.get(kind, 0)) - int(w.get("ammo_per", 0)))
	var powder := int(w.get("powder", 0))
	if powder > 0:
		ammo["huoyao"] = maxi(0, int(ammo.get("huoyao", 0)) - powder)


## 告急慎发：这种武器耗的弹余量不到定额的四分之一，装填 ×LOW_RELOAD_MULT；代用（抛石、压舱石）不另罚。
func shortage_mult(wid: String) -> float:
	var kind := str(Ballistics.weapon(wid).get("ammo", ""))
	if kind == "" or kind in SUBSTITUTE_AMMO or int(ammo_max.get(kind, 0)) <= 0:
		return 1.0
	return LOW_RELOAD_MULT if ammo_ratio(kind) < LOW_RATIO else 1.0


func _refusal_text(sd: int, why: Dictionary, wait: float, dry: Array = []) -> String:
	if why.is_empty():
		return "%s无可发之位" % side_name(sd)
	var bits := PackedStringArray()
	for k in REFUSAL_ORDER:
		if not why.has(k):
			continue
		if k == "未装毕" and wait < INF:
			bits.append("未装毕（尚需 %d 秒）" % ceili(wait))
		elif k == "弹尽" and not dry.is_empty():
			bits.append("%s弹尽" % "、".join(PackedStringArray(dry)))
		else:
			bits.append(k)
	return side_name(sd) + "，".join(bits)


# ── 查询 ──────────────────────────────────────────────

static func side_name(side: int) -> String:
	return "右舷" if side >= 0 else "左舷"


## 这一舷能出力的位数（重器 + 全部弓弩队；弓弩队不分舷）。
func mount_count(side: int) -> int:
	var sd := SIDE_STARBOARD if side >= 0 else SIDE_PORT
	var n := 0
	for m in mounts:
		if int(m["side"]) == 0 or int(m["side"]) == sd:
			n += 1
	return n


## 这一舷已装毕、有弹（含代用）的位数。不看舷角、射程与号令间隔。
func ready_count(side: int) -> int:
	var sd := SIDE_STARBOARD if side >= 0 else SIDE_PORT
	var n := 0
	for m in mounts:
		var ms := int(m["side"])
		if ms != 0 and ms != sd:
			continue
		if float(m["t"]) <= 0.0 and shot_weapon(m) != "":
			n += 1
	return n


## 这一舷下一位装毕还要几秒（按此刻人手、士气、reload_mult）；已有装毕的位为 0，分不到人手装不动为 INF。
func reload_left(side: int) -> float:
	var sd := SIDE_STARBOARD if side >= 0 else SIDE_PORT
	var best := INF
	for m in mounts:
		var ms := int(m["side"])
		if ms != 0 and ms != sd:
			continue
		if shot_weapon(m) == "":
			continue
		var t := float(m["t"])
		if t <= 0.0:
			return 0.0
		var r := _rate(m)
		if r > 0.0:
			best = minf(best, t / r)
	return best


func gap_left(side: int) -> float:
	return float(_gap[SIDE_STARBOARD if side >= 0 else SIDE_PORT])


func ammo_left(kind: String) -> int:
	return int(ammo.get(kind, 0))


## 余量占定额的比例；本船不带这种弹（定额 0）返回 0。
func ammo_ratio(kind: String) -> float:
	var mx := int(ammo_max.get(kind, 0))
	if mx <= 0:
		return 0.0
	return clampf(float(ammo.get(kind, 0)) / float(mx), 0.0, 1.0)


## 「无」（本船不带）/「足」/「少」（告急）/「尽」
func ammo_state(kind: String) -> String:
	if int(ammo_max.get(kind, 0)) <= 0:
		return "无"
	var left := int(ammo.get(kind, 0))
	if left <= 0:
		return "尽"
	return "少" if ammo_ratio(kind) < LOW_RATIO else "足"


## 远射弹药（箭按一排、大弩箭、石弹，火药不算）合计还剩定额的几成。
func supply_ratio() -> float:
	var left := float(ammo.get("jian", 0)) / float(SQUAD) + float(ammo.get("nujian", 0)) + float(ammo.get("shi", 0))
	var mx := float(ammo_max.get("jian", 0)) / float(SQUAD) + float(ammo_max.get("nujian", 0)) + float(ammo_max.get("shi", 0))
	return clampf(left / mx, 0.0, 1.0) if mx > 0.0 else 0.0


## 同 supply_ratio：CombatMorale / EnemyCaptainAI 认这个名字（0–1，矢石余量）。
func ammo_frac() -> float:
	return supply_ratio()


## 弹药告急（远射弹合计不到四分之一）：AI 可据此改求接舷，士气可据此动摇。
func is_low() -> bool:
	return supply_ratio() < LOW_RATIO


## 远射弹用尽（箭不够一排、大弩箭与石弹都没了），只剩抛石、压舱石这些代用——「弹药尽」。
func is_spent() -> bool:
	return int(ammo.get("jian", 0)) < SQUAD and int(ammo.get("nujian", 0)) <= 0 and int(ammo.get("shi", 0)) <= 0


func set_fire_mode(on: bool) -> void:
	fire_mode = on


func set_emphasis(e: String) -> void:
	emphasis = e if SAIL_SHARE.has(e) else "balanced"


## 补弹（缴获、补给）：最多补到定额，返回实补数。
func resupply(kind: String, n: int) -> int:
	if not ammo.has(kind) or n <= 0:
		return 0
	var room := maxi(0, int(ammo_max.get(kind, 0)) - int(ammo[kind]))
	var add := mini(room, n)
	ammo[kind] = int(ammo[kind]) + add
	return add


## 现存弹药副本（下一仗 for_ship(..., {"ammo": …}) 续用）。
func ammo_snapshot() -> Dictionary:
	return ammo.duplicate()


static func _powder_text(liang: int) -> String:
	if liang >= 16:
		var jin := floori(liang / 16.0)
		var rest := liang % 16
		return "%d 斤" % jin if rest == 0 else "%d 斤 %d 两" % [jin, rest]
	return "%d 两" % liang


## 一舷的状态短句：「左舷　就绪 3 / 5」或「左舷　装填 0 / 5，尚需 4 秒」。
func side_line(side: int) -> String:
	var ready_n := ready_count(side)
	var total := mount_count(side)
	var head := "%s　就绪 %d / %d" % [side_name(side), ready_n, total]
	if ready_n > 0 or total == 0:
		return head
	var left := reload_left(side)
	if left == INF:
		return "%s　缺人手" % side_name(side)
	return "%s　装填 0 / %d，尚需 %d 秒" % [side_name(side), total, ceili(left)]


## 弹药一行：「箭 212 支　弩箭 18 枝　石弹 9 颗（少）　火药 5 斤」；本船不带的那种不列。
func ammo_line() -> String:
	var bits := PackedStringArray()
	for kind in ["jian", "nujian", "shi", "yacang", "huoyao"]:
		if int(ammo_max.get(kind, 0)) <= 0:
			continue
		var n := int(ammo.get(kind, 0))
		var txt := _powder_text(n) if kind == "huoyao" else "%d %s" % [n, Ballistics.ammo_unit(kind)]
		var st := ammo_state(kind)
		var tag := "" if st == "足" else "（%s）" % st
		bits.append("%s %s%s" % [Ballistics.ammo_name(kind), txt, tag])
	return "　".join(bits)


## 状态条整句：两舷就绪 + 弹药，火攻令在时标出。
func status_line() -> String:
	var s := "%s　　%s　　%s" % [side_line(SIDE_PORT), side_line(SIDE_STARBOARD), ammo_line()]
	return s + "　　火攻" if fire_mode else s


## CombatStatusHud 的快照（combat08 SNAPSHOT_KEYS）：ammo / ammo_max 换成它认的弹种键，本船不带的那种不列（压舱石并进 stone）；
## reload 为两舷下一位装毕还要几秒，装不动记 HUD_STALLED。船节点写 `func combat_status(): return battery.combat_status()` 即接上。
func combat_status() -> Dictionary:
	var a := {}
	var mx := {}
	for k in ["jian", "nujian", "shi", "yacang", "huoyao"]:
		if int(ammo_max.get(k, 0)) <= 0:
			continue
		var hk: String = HUD_AMMO_KEYS[k]
		a[hk] = int(a.get(hk, 0)) + int(ammo.get(k, 0))
		mx[hk] = int(mx.get(hk, 0)) + int(ammo_max[k])
	var lp := reload_left(SIDE_PORT)
	var rp := reload_left(SIDE_STARBOARD)
	return {
		"ammo": a, "ammo_max": mx,
		"reload": {"port": HUD_STALLED if lp == INF else lp, "starboard": HUD_STALLED if rp == INF else rp},
	}


# ── 给只要一个数的调用方（EnemyCaptainAI 的可选钩子按名字与形参类型认静态方法）──

## 一舷整轮装填秒数：crew 水手数，guns 每舷重器位数（0 = 只有弓弩手，按一排矢算）。口径同实例：
## 留三成人操帆，余者按比例分给这一舷正在绞的重器与全船弓弩队（敌船按战船配弓弩手）；满员床子弩 13 秒，人少了按比例慢。
static func captain_reload_time(crew: int, guns: int) -> float:
	var n := maxi(0, guns)
	var c := maxi(0, crew)
	var squads := clampi(roundi(float(c) * float(ARCHER_SHARE["war"]) / float(SQUAD)), 1, SQUAD_MAX)
	var need := float(n * int(Ballistics.weapon("chuangnu").get("hands", 5)) + squads * SQUAD)
	var pool := float(c) * (1.0 - float(SAIL_SHARE["balanced"]))
	var ratio := clampf(pool / maxf(1.0, need), 0.05, 1.0)
	var base := float(Ballistics.weapon("chuangnu" if n > 0 else "gongnu").get("reload", 5.0))
	return base / ratio


## 按船型定额整舷一轮一轮放，重器弹药（大箭、石弹）先见底的那样能放几轮；没有重器的按弓弩手的箭算。
## ship_type 为 ships.json 的 id（按最少水手配弓弩队）；认不出的按空船型（一队弓弩手、商船定额）。
static func captain_volleys(ship_type: String) -> int:
	var def := ship_def_of(ship_type)
	var ra := for_ship(def, int(def.get("crew_min", 20)))
	var cn := 0
	var pao := 0
	var squads := 0
	for m in ra.mounts:
		if int(m["side"]) == 0:
			squads += 1
		elif int(m["side"]) == SIDE_STARBOARD:
			if str(m["weapon"]) == "pao":
				pao += 1
			else:
				cn += 1
	var rounds := []
	if cn > 0:
		rounds.append(floori(float(ra.ammo_max["nujian"]) / float(cn)))
	if pao > 0:
		rounds.append(floori(float(ra.ammo_max["shi"]) / float(pao)))
	if rounds.is_empty() and squads > 0:
		rounds.append(floori(float(ra.ammo_max["jian"]) / float(squads * SQUAD)))
	return int(rounds.min()) if not rounds.is_empty() else 0


## ships.json 里的一条（按 id；读一次缓存）。认不出返回 {}。
static func ship_def_of(type_id: String) -> Dictionary:
	if _ship_defs.is_empty() and FileAccess.file_exists(SHIPS_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SHIPS_PATH))
		if data is Dictionary:
			for s in data.get("ships", []):
				if s is Dictionary:
					_ship_defs[str(s.get("id", ""))] = s
	return _ship_defs.get(type_id, {})
