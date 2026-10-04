## 船体·帆装·舵·水手分系统损伤（lane combat04）。一船一份，是 RefCounted，不进树、不读 autoload。旗舰那份挂在 Ship.damage_model；
## PirateShip、探针要用，就 new 一份再 setup。浸水与失火的逐帧推进在 FloodFire。
##
## 为什么要拆：原先中弹只扣一根 hull_hp（铁子 25 × 甲），血条见底才沉。南宋末、元初的近海船战里，木船很少是被矢石「打散」的。
## 要命的是水线下的漏、船上的火、甲板上被扫倒的人，还有打烂的篷帆和舵：船走不动、转不过来，就只能等人跳帮。
## 所以一次命中（apply_hit）按弹种与落点拆成下面几样：
##   船体 hull：结构吃掉的那份，照旧由调用方扣 hull_hp 与舰队耐久，见底解体。从篷帆间穿过的弹，只有三成半落在船体上。
##   漏 leak：水线下中弹，在该段某舱开一处漏（FloodFire）。进水多少看破口大小、木质（广船铁力木小）、船壳厚薄、船体已经松了几成。
##   隔舱板 breach：重击可能打穿隔舱板，水过邻舱。隔舱板做得好（福船）就不容易破。
##   帆 sail：竹篾席帆中弹只多几个洞，不大伤，怕的是火。帆剩不到五成五就挂不起满帆，剩三成以下就是桅折。
##   舵 rudder：艉部中弹有机会伤舵。舵剩不到两成五就失灵，船往一边偏；有闲手就以橹代舵，救回三成五。
##   水手 crew：伤亡按弹种算，甲板上人多挨得也多（按人数开方缩放）。由调用方记进舰队（Ship 走 Fleet.lose_crew_random，旗舰先扣）。
##   火 fire：甲板以上中弹有机会引火（铁子少，火箭、火球多），着在该段或篷帆上。
## 这些伤会反过来拖慢机动、削弱火力。本文件只给乘数，不改别人的文件。Ship 自己的航行、齐射乘上这些数；
## ManeuverModel、Ballistics、EnemyCaptainAI 等要用，就读同名查询：speed_factor / turn_factor / yaw_drift / gear_cap /
## reload_factor / volley_factor / spread_factor / side_ready / boarding_crew。
## 损管令 set_mode 有四种：均衡 auto（火先救、水后戽，按险情派人）、救火 fire、戽水 flood、迎敌 fight（只留一成半人损管）。
## 事件在 apply_hit / step 返回值的 events 里：kind + text（中文短注，纪实，不用叹号）+ severity 0–3，另带定位（comp / zone / n 等）。
## 调用方先把船体、伤亡落了账再往外发（Ship 发 damage_event 信号），士气、状态条、观感从那里接。kind 全表见 EVENT_SEVERITY。
## 本仗的损伤只在战术场景里有：出了 WorldMap，舱水戽干、漏补上、火灭掉，留下的只有记进舰队的耐久与伤亡。
extends RefCounted

const FloodFire := preload("res://scripts/combat/FloodFire.gd")

## 船型损伤口径，按 ships.json 的 id 取；表外的 id（探针里的 fuchuan 等）用 DEFAULT_PROFILE。
## ships.json 的船型条目里写了同名键，就以数据为准（profile_for）。
##   compartments 水密隔舱数：泉州湾宋船十三舱，福船（大）取 13；福船（中）8；客舟《宣和奉使高丽图经》说「分为三处」，取 4；小艍 3。
##   reserve 储备浮力，灌到几成就沉：舱多、干舷高的大；小艍 0.34，两舱灌满就沉。
##   stability 稳性：海鹘「舷下左右置浮板…虽风涛涨天，无有倾侧」取 1.5；广船坚重 1.25；快船狭长 0.85；小艍 0.7。
##   timber 同一处破口的进水倍数：广船铁力木 0.7，福船 0.9。
##   frame 船体结构吃伤的倍数：小艍板薄 1.3，客舟 1.1，广船铁力木 0.85。
##   bulkhead 隔舱板的坚牢（0–1），越高越难打穿。
##   fire_resist 防火（0–0.9）：船身涂泥、备湿毡之类；缺省只有官式大船带一点。
##   oars 帆毁之后还剩几成走力（摇橹、划桨）：海鹘有桨 0.3，小艍有橹 0.25。
## 船壳厚薄不另列：由耐久 ÷ 舱容折出（planking），同一发弹打在厚壳的战船上洞小、打在薄壳的大商船上洞大。
const PROFILES := {
	"sampan": {"compartments": 3, "reserve": 0.34, "stability": 0.7, "timber": 1.0, "frame": 1.3, "bulkhead": 0.6,
		"fire_resist": 0.0, "oars": 0.25},
	"keel_boat": {"compartments": 4, "reserve": 0.4, "stability": 0.9, "timber": 1.0, "frame": 1.1, "bulkhead": 0.75,
		"fire_resist": 0.0, "oars": 0.12},
	"fu_ship_medium": {"compartments": 8, "reserve": 0.5, "stability": 1.1, "timber": 0.9, "frame": 1.0, "bulkhead": 0.9,
		"fire_resist": 0.05, "oars": 0.1},
	"canton_ship": {"compartments": 9, "reserve": 0.52, "stability": 1.25, "timber": 0.7, "frame": 0.85, "bulkhead": 0.9,
		"fire_resist": 0.1, "oars": 0.1},
	"sea_falcon": {"compartments": 6, "reserve": 0.45, "stability": 1.5, "timber": 0.9, "frame": 1.0, "bulkhead": 0.85,
		"fire_resist": 0.05, "oars": 0.3},
	# 快船（V0928-7 定 A，lane w53-14）：狭长轻造（weapons.json build=light、五舱），多桨——帆毁了桨手还划得动六成（同 EnemyCaptainAI.OARS）
	"pirate_boat": {"compartments": 5, "reserve": 0.4, "stability": 0.85, "timber": 1.0, "frame": 1.15, "bulkhead": 0.7,
		"fire_resist": 0.0, "oars": 0.62},
	"fu_ship_large": {"compartments": 13, "reserve": 0.55, "stability": 1.2, "timber": 0.85, "frame": 0.95, "bulkhead": 0.95,
		"fire_resist": 0.05, "oars": 0.06},
	"divine_ship": {"compartments": 14, "reserve": 0.58, "stability": 1.35, "timber": 0.8, "frame": 0.9, "bulkhead": 0.95,
		"fire_resist": 0.1, "oars": 0.05},
}
const DEFAULT_PROFILE := {"compartments": 8, "reserve": 0.5, "stability": 1.1, "timber": 0.9, "frame": 1.0, "bulkhead": 0.9,
	"fire_resist": 0.05, "oars": 0.1}

## 弹种口径（hit.kind；缺省、不认识的都按 shot）。数都按「每 25 点命中」给：
##   hull 船体结构吃几成；waterline 落在水线下的机会；leak 水线下破口的进水倍数；breach 打穿隔舱板的倍数；
##   crew 伤亡（按 40 人的甲板算）；rig 从篷帆间穿过的机会（打帆不打船）；sail 帆损；
##   rudder 打在艉部时伤舵的机会，rudder_dmg 舵损；fire 甲板以上引火的机会，ignite 起火的火势。
##   shot 铁子、实心弹（现在的 Cannonball）；stone 砲石；arrow 箭矢（伤人不伤船）；bolt 床子弩大箭；
##   fire 火箭、火球、火油（以引火为主）；bomb 火药包、霹雳砲（伤人、引火、破船）；ram 冲撞（水线下开大口子）。
const KINDS := {
	"shot": {"hull": 0.7, "waterline": 0.4, "leak": 1.0, "breach": 0.3, "crew": 0.6, "rig": 0.18, "sail": 0.07,
		"rudder": 0.35, "rudder_dmg": 0.35, "fire": 0.06, "ignite": 0.18},
	"stone": {"hull": 0.9, "waterline": 0.25, "leak": 0.9, "breach": 0.35, "crew": 0.7, "rig": 0.2, "sail": 0.08,
		"rudder": 0.35, "rudder_dmg": 0.4, "fire": 0.0, "ignite": 0.0},
	"arrow": {"hull": 0.05, "waterline": 0.0, "leak": 0.0, "breach": 0.0, "crew": 1.8, "rig": 0.3, "sail": 0.01,
		"rudder": 0.1, "rudder_dmg": 0.02, "fire": 0.0, "ignite": 0.0},
	"bolt": {"hull": 0.35, "waterline": 0.1, "leak": 0.4, "breach": 0.1, "crew": 1.5, "rig": 0.25, "sail": 0.05,
		"rudder": 0.25, "rudder_dmg": 0.2, "fire": 0.0, "ignite": 0.0},
	"fire": {"hull": 0.1, "waterline": 0.0, "leak": 0.0, "breach": 0.0, "crew": 0.4, "rig": 0.45, "sail": 0.04,
		"rudder": 0.1, "rudder_dmg": 0.05, "fire": 0.8, "ignite": 0.3},
	"bomb": {"hull": 0.6, "waterline": 0.1, "leak": 0.6, "breach": 0.5, "crew": 2.2, "rig": 0.2, "sail": 0.1,
		"rudder": 0.3, "rudder_dmg": 0.35, "fire": 0.45, "ignite": 0.3},
	"ram": {"hull": 1.0, "waterline": 0.9, "leak": 1.6, "breach": 1.2, "crew": 0.5, "rig": 0.0, "sail": 0.0,
		"rudder": 0.2, "rudder_dmg": 0.3, "fire": 0.0, "ignite": 0.0},
}
## 船分三段（落点、分舱用）；火另有篷帆一处（FloodFire.ZONES）
const HULL_ZONES := ["bow", "mid", "stern"]
const ZONE_NAMES := {"bow": "艏部", "mid": "舯部", "stern": "艉楼", "rig": "篷帆"}

const MODES := ["auto", "fire", "flood", "fight"]
const MODE_NAMES := {"auto": "均衡", "fire": "救火", "flood": "戽水", "fight": "迎敌"}
## 各令下损管最多动用几成人：[救火, 戽水堵漏, 两样合计]
const MODE_CAPS := {"auto": [0.45, 0.45, 0.6], "fire": [0.7, 0.2, 0.8], "flood": [0.2, 0.7, 0.8], "fight": [0.15, 0.15, 0.15]}

## 事件种类 → 轻重：0 转好 / 1 轻 / 2 重 / 3 危。伤亡一次 5 人以上算重。
const EVENT_SEVERITY := {
	"leak": 2, "compartment_full": 1, "bulkhead_breach": 2, "leak_stopped": 0,
	"settling": 3, "settle_stop": 0, "list": 2,
	"fire": 2, "fire_spread": 2, "fire_out": 0, "sail_cut": 1, "magazine": 3,
	"sail_damage": 1, "mast_down": 2, "rudder_damage": 1, "rudder_lost": 2, "jury_rudder": 0,
	"casualties": 1, "founder": 3, "capsize": 3,
}

## 总舱容 = 船型 capacity（料）+ 这份底数；capacity 缺了按 800
const VOLUME_BASE := 150.0
const CAPACITY_DEFAULT := 800.0
## 每点命中在水线下开多大的漏（料/秒）
const LEAK_PER_DMG := 0.32
## 船体越松，新漏越大、隔舱板越容易破：船体打光时 ×(1 + HULL_LOOSE)
const HULL_LOOSE := 0.8
## 船壳厚薄：planking = sqrt(PLANK_REF ÷ (耐久 ÷ 舱容))，夹在 PLANK_MIN–PLANK_MAX；福船（中）约 1，海鹘战船约 0.55
const PLANK_REF := 0.32
const PLANK_MIN := 0.5
const PLANK_MAX := 1.4
## 从篷帆间穿过的弹，落在船体上的份
const RIG_HULL_SHARE := 0.35
## 伤亡按这么多人的甲板算
const CREW_REF := 40.0
## 帆：剩多少挂不起满帆；剩多少算桅折；每掉几成报一次
const SAIL_FULL_MIN := 0.55
const MAST_DOWN_BELOW := 0.3
const SAIL_TELL_STEP := 0.25
## 舵：剩多少算失灵；以橹代舵救回多少、要几人、几秒
const RUDDER_LOST_BELOW := 0.25
const JURY_RUDDER := 0.35
const JURY_MEN := 2
const JURY_TIME := 20.0
## 舵失灵后满速时每秒自偏的弧度上限
const YAW_DRIFT := 0.4
## 走力乘数到这以下算失去机动（is_immobile）
const IMMOBILE_SPEED := 0.25
## 倾向一舷过这个度数，这一舷就打不出去（低舷入水，站不住人）
const SIDE_AWASH_DEG := 18.0
## 倾侧提醒：过 12 度、24 度各报一次，回到 8 度、18 度以下再重新计
const LIST_WARN := [12.0, 24.0]
const LIST_REARM := [8.0, 18.0]
## 火药舱爆燃伤几成人
const BLAST_CREW := 0.1
## 一处满火要几人来救；每 1 料/秒的漏要几人堵；每多少料的水要一人戽（险情那份，先于炮位派）
const FIRE_MEN_PER := 8.0
const PLUG_MEN_PER_FLOW := 0.55
const BAIL_WATER_PER_MAN := 24.0
## 炮位派满之后还有闲手、舱里还有水：每多少料的水再添一人戽（不占炮位，只占闲手），至少两人
const IDLE_BAIL_PER_MAN := 3.0
const IDLE_BAIL_MIN := 2

var type_id := ""
var profile: Dictionary = {}
var ff: FloodFire = FloodFire.new()
var rng := RandomNumberGenerator.new()
var hull := 100.0
var hull_max := 100.0
var sail := 1.0
var rudder := 1.0
## 号令「张湿毡」（战斗方案二期，order_wet_felt）：舷边张过水的厚毡，中弹引火机会与火攻伤亡都折半 +
## 减两成；Under 关时之象世工变：默认 false、一切照旧。号令面板 apply_to_ship 走鸭子型写入
var wet_felt := false
## 舵失灵后船往哪边偏（-1 左 … 1 右）
var rudder_jam := 0.0
var jury_rudder := false
var jury_progress := 0.0
var mast_down := false
var crew := 20
var crew_min := 10
var weapons := 1
var oars := 0.1
## 船壳厚薄折出的漏口倍数（setup 按耐久 ÷ 舱容算）
var planking := 1.0
var mode := "auto"
## 本仗伤亡（中弹、火场、爆燃；接舷白刃的不在内）
var casualties := 0
var hits := 0
## "" / "flood"（灌沉）/ "capsize"（倾覆）
var sunk := ""
var _split := {}
var _wind_heel := 0.0
var _list_armed := [true, true]
var _sail_told := 1.0


## def 是 ships.json 的船型条目（Fleet.ship_def），缺了就按表外口径。p_crew / p_hull / p_hull_max 取这艘船此刻的数。
## p_seed 不为 0 时伤害随机数定种（探针复现用），为 0 则随机。
func setup(p_type: String, def: Dictionary, p_crew: int, p_hull: float, p_hull_max: float, p_seed := 0) -> void:
	type_id = p_type
	profile = profile_for(p_type, def)
	hull_max = maxf(1.0, p_hull_max)
	hull = clampf(p_hull, 0.0, hull_max)
	crew = maxi(0, p_crew)
	crew_min = maxi(2, int(def.get("crew_min", maxi(4, int(crew / 3.0)))))
	var slots := int(def.get("cannon_slots", 0))
	weapons = maxi(1, slots)
	oars = clampf(float(profile["oars"]), 0.0, 0.9)
	var vol := VOLUME_BASE + float(def.get("capacity", CAPACITY_DEFAULT))
	planking = clampf(sqrt(PLANK_REF / (hull_max / vol)), PLANK_MIN, PLANK_MAX)
	ff = FloodFire.new()
	ff.setup(int(profile["compartments"]), vol, float(profile["reserve"]), float(profile["stability"]),
		float(profile["fire_resist"]), slots > 0)
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()
	sail = 1.0
	rudder = 1.0
	rudder_jam = 0.0
	jury_rudder = false
	jury_progress = 0.0
	mast_down = false
	mode = "auto"
	casualties = 0
	hits = 0
	sunk = ""
	_wind_heel = 0.0
	_list_armed = [true, true]
	_sail_told = 1.0
	set_hull(hull)
	_reallocate()


## 船型损伤口径：PROFILES[p_type]（表外用 DEFAULT_PROFILE）；def（ships.json 条目）里写了同名键就以数据为准
static func profile_for(p_type: String, def: Dictionary = {}) -> Dictionary:
	var base: Dictionary = PROFILES.get(p_type, DEFAULT_PROFILE)
	var out := base.duplicate()
	for k in DEFAULT_PROFILE:
		if def.has(k):
			out[k] = def[k]
	return out


## 一次命中。hit 的键：amount（命中点数，已乘甲）；kind（KINDS 的键，缺省、不认识都按 shot）；
## local（命中处在本船坐标里的位置，y 负为艏、x 正为右舷，有它就按它定段与舷）；zone（bow / mid / stern）、side（-1 / 1）、
## high（true 甲板以上 / false 水线下）三样缺了就按 local 或随机。
## 返回 {hull: 船体该扣多少, crew: 伤亡人数, zone, side, high, rig, kind, events}。船体、伤亡由调用方落账（Ship 记进 hull_hp 与 Fleet）。
func apply_hit(hit: Dictionary) -> Dictionary:
	var events: Array = []
	var out := {"hull": 0.0, "crew": 0, "zone": "", "side": 0, "high": true, "rig": false, "kind": "", "events": events}
	var amount := maxf(0.0, float(hit.get("amount", 0.0)))
	if sunk != "" or amount <= 0.0:
		return out
	var kind := str(hit.get("kind", "shot"))
	if not KINDS.has(kind):
		kind = "shot"
	var k: Dictionary = KINDS[kind]
	hits += 1
	var scale := amount / 25.0
	var zone := str(hit.get("zone", ""))
	var side := int(hit.get("side", 0))
	if hit.get("local") is Vector2:
		var at: Vector2 = hit["local"]
		if zone == "":
			zone = _zone_of(at)
		if side == 0:
			side = 1 if at.x >= 0.0 else -1
	if not (zone in HULL_ZONES):
		zone = _roll_zone()
	if side == 0:
		side = 1 if rng.randf() < 0.5 else -1
	side = signi(side)
	var high: bool
	if hit.has("high"):
		high = bool(hit["high"])
	else:
		high = rng.randf() >= float(k["waterline"])
	var rig := high and rng.randf() < float(k["rig"])
	var loose := 1.0 + HULL_LOOSE * (1.0 - hull / hull_max)
	# 水线下：该段某舱开漏，重击可能打穿隔舱板
	if not high and float(k["leak"]) > 0.0:
		var comps := ff.zone_comps(zone)
		var comp: int = comps[rng.randi_range(0, comps.size() - 1)]
		ff.add_leak(comp, amount * float(k["leak"]) * float(profile["timber"]) * planking * loose * LEAK_PER_DMG, side)
		_push(events, "leak", {"comp": comp, "zone": zone, "side": side})
		if rng.randf() < float(k["breach"]) * scale * (1.0 - float(profile["bulkhead"])) * loose:
			var dir := 1 if rng.randf() < 0.5 else -1
			if ff.breach_bulkhead(comp, dir) or ff.breach_bulkhead(comp, -dir):
				_push(events, "bulkhead_breach", {"comp": comp, "zone": zone})
	if rig:
		_hurt_sail(float(k["sail"]) * scale, events)
	if zone == "stern" and rng.randf() < float(k["rudder"]):
		_hurt_rudder(float(k["rudder_dmg"]) * scale, side, events)
	# 张湿毡：舷边张过水的厚毡——中弹引火机会折半（wet_screens.fire_ignite_mul 0.5）
	if high and rng.randf() < float(k["fire"]) * fire_effects_mul():
		var fz := "rig" if rig else zone
		if ff.ignite(fz, float(k["ignite"])):
			_push(events, "fire", {"zone": fz})
	# 张湿毡：船上受矢石伤也减（wet_screens.flat_casualty_mul 0.7）
	var expect := float(k["crew"]) * scale * sqrt(clampf(float(crew) / CREW_REF, 0.05, 4.0)) * casualty_mul()
	var dead := int(floor(expect))
	if rng.randf() < expect - float(dead):
		dead += 1
	dead = mini(dead, maxi(0, crew - 1))
	if dead > 0:
		crew -= dead
		casualties += dead
		_push(events, "casualties", {"n": dead, "total": casualties, "cause": "hit"})
	out["hull"] = amount * float(k["hull"]) * float(profile["frame"]) * (RIG_HULL_SHARE if rig else 1.0)
	out["crew"] = dead
	out["zone"] = zone
	out["side"] = side
	out["high"] = high
	out["rig"] = rig
	out["kind"] = kind
	_reallocate()
	return out


## 推进一步（Ship 每个物理帧调一次）。env：wind（风力，80 是常风）、rain（bool）、heel（风压横倾度数，右倾为正）。
## 返回 {hull: 本步火烧、爆燃该扣的船体, crew: 本步伤亡, founder: "" / "flood" / "capsize", events}。
func step(delta: float, env: Dictionary = {}) -> Dictionary:
	var events: Array = []
	var out := {"hull": 0.0, "crew": 0, "founder": sunk, "events": events}
	if sunk != "" or delta <= 0.0:
		return out
	_wind_heel = float(env.get("heel", 0.0))
	_reallocate()
	var r: Dictionary = ff.step(delta, int(_split["flood"]), int(_split["fire"]), env, rng, _wind_heel)
	for e in r["events"]:
		var ev: Dictionary = e
		_push(events, str(ev["kind"]), ev)
	# 张湿毡：烧到船身 / 烧人 / 烧帆都按 fire_effects_mul 对折（与 apply_hit 里中弹引火呼应；off 时与 wave53 开工前一致）
	var burn_mul := fire_effects_mul()
	if float(r["sail_burn"]) > 0.0:
		_hurt_sail(float(r["sail_burn"]) * burn_mul, events)
	var blast := bool(r["blast"])
	var dead := int(ceil(float(r["crew_burn"]) * burn_mul)) + (int(ceil(float(crew) * BLAST_CREW)) if blast else 0)
	dead = mini(dead, maxi(0, crew - 1))
	if dead > 0:
		crew -= dead
		casualties += dead
		_push(events, "casualties", {"n": dead, "total": casualties, "cause": "blast" if blast else "fire"})
	_step_jury(delta, events)
	_check_list(events)
	var founder := str(r["founder"])
	if founder != "":
		sunk = founder
		_push(events, "capsize" if founder == "capsize" else "founder", {})
	out["hull"] = hull_max * float(r["hull_burn"]) * burn_mul
	out["crew"] = dead
	out["founder"] = founder
	_reallocate()
	return out


## 张湿毡开 / 撤（开关 order_wet_felt 在号令面板那一侧把值写来；本簿只管折算）。
## 战斗方案 wet_screens：fire_ignite_mul 0.5 / flat_casualty_mul 0.7 / own_flat_missile_mul 0.8
func set_wet_felt(on: bool) -> void:
	wet_felt = on


## 扳回 Offset 前先两枚折扣的纯函数（apply_hit / step 与探针都走这里，回退即红直接判这两行）：
## 张湿毡：中弹引火机会与火势各烧项（船身 / 帆 / 人手）对折；受矢石伤亡 ×0.7（combat_phases.json wet_screens）。
## off 时恒 1.0——与 wave53 开工前同一本账
func fire_effects_mul() -> float:
	return 0.5 if wet_felt else 1.0


func casualty_mul() -> float:
	return 0.7 if wet_felt else 1.0


## 损管令：auto 均衡 / fire 救火 / flood 戽水 / fight 迎敌。不认识的令返回 false，原令不变。
func set_mode(p_mode: String) -> bool:
	if not (p_mode in MODES):
		return false
	mode = p_mode
	_reallocate()
	return true


## 与舰队对齐人数（接舷白刃等别处减员之后）
func set_crew(n: int) -> void:
	if n == crew:
		return
	crew = maxi(0, n)
	_reallocate()


## 与船体对齐（调用方扣完 hull_hp 之后）。船体挨得越多，船身越松，储备浮力跟着往下打（FloodFire.strain）。
func set_hull(v: float) -> void:
	hull = clampf(v, 0.0, hull_max)
	ff.strain = 1.0 - hull / hull_max


## 人手分派：sail 操帆掌舵 / weapons 矢石炮位 / fire 救火 / flood 戽水堵漏 / jury 以橹代舵 / spare 闲手，及 sail_need / weapons_need
func crew_split() -> Dictionary:
	_reallocate()
	return _split.duplicate()


func sail_manned() -> float:
	return clampf(float(_split["sail"]) / float(maxi(1, int(_split["sail_need"]))), 0.0, 1.0)


func weapons_manned() -> float:
	return clampf(float(_split["weapons"]) / float(maxi(1, int(_split["weapons_need"]))), 0.0, 1.0)


## 帆装还挂得起几档（0 收帆 / 1 半帆 / 2 满帆）：帆剩不到五成五、或桅折，只挂得起半帆；帆全毁也还能摇橹划桨，所以最少是 1
func gear_cap() -> int:
	if mast_down or sail < SAIL_FULL_MIN:
		return 1
	return 2


## 航速乘数 = 帆推 × 船身拖累（两项见 sail_drive / hull_drag），封在 0.08–1
func speed_factor() -> float:
	return clampf(sail_drive() * hull_drag(), 0.08, 1.0)


## 帆推：帆剩几成（帆毁时有橹桨兜底）× 操帆的人够不够
func sail_drive() -> float:
	return clampf(maxf(oars, 0.15 + 0.85 * sail) * (0.55 + 0.45 * sail_manned()), 0.0, 1.0)


## 船身拖累：舱水压低干舷、船身倾侧
func hull_drag() -> float:
	return clampf((1.0 - 0.9 * ff.flood_frac()) * (1.0 - minf(0.5, absf(list_deg()) / 60.0)), 0.1, 1.0)


## ManeuverModel.step 的 mods（lane combat02 口径，键见其头注释）：sail 帆推、hull 船身拖累、rudder 舵效（= turn_factor）、
## yaw_drift、gear_cap。WorldMap 对旗舰优先取船节点的 maneuver_mods()，帆与船身分开乘，比合成的 speed 细。
func maneuver_mods() -> Dictionary:
	return {"sail": sail_drive(), "hull": hull_drag(), "rudder": turn_factor(), "yaw_drift": yaw_drift(), "gear_cap": gear_cap()}


## 转向乘数：舵、掌舵的人、舱水（船重了转不动）
func turn_factor() -> float:
	var rudder_k := 0.25 + 0.75 * rudder
	var helm_k := 0.6 + 0.4 * sail_manned()
	var flood_k := 1.0 - 0.6 * ff.flood_frac()
	return clampf(rudder_k * helm_k * flood_k, 0.1, 1.0)


## 舵失灵时满速下每秒往一边偏的弧度（右偏为正；舵剩五成以上为 0）。调用方再乘航速占比。
func yaw_drift() -> float:
	if rudder >= 0.5:
		return 0.0
	return rudder_jam * (0.5 - rudder) * YAW_DRIFT


## 装填时长倍数（≥1）：炮位缺人、船上有火烟、倾侧
func reload_factor() -> float:
	var smoke := minf(1.0, ff.fire_total())
	var k := (1.0 / maxf(0.3, weapons_manned())) * (1.0 + 0.5 * smoke) * (1.0 + absf(list_deg()) / 40.0)
	return clampf(k, 1.0, 4.0)


## 一轮能放几成（0–1）：有人的炮位，再被火烟压掉一些
func volley_factor() -> float:
	return clampf(weapons_manned() * (1.0 - 0.3 * minf(1.0, ff.fire_total())), 0.0, 1.0)


## 散布倍数（≥1）：倾侧、火烟、生手顶位
func spread_factor() -> float:
	return 1.0 + absf(list_deg()) / 15.0 + 0.5 * minf(1.0, ff.fire_total()) + 0.5 * (1.0 - weapons_manned())


## side -1 左舷 / 1 右舷：船往这一舷倾过 SIDE_AWASH_DEG 就打不出去
func side_ready(p_side: int) -> bool:
	var l := list_deg()
	return not (absf(l) >= SIDE_AWASH_DEG and signf(l) == signf(float(p_side)))


## 失去机动：舵失灵又还没以橹代舵，或者走力只剩 IMMOBILE_SPEED 以下（帆毁又无橹桨、舱水压得走不动）
func is_immobile() -> bool:
	return (rudder < RUDDER_LOST_BELOW and not jury_rudder) or speed_factor() <= IMMOBILE_SPEED


## 接舷能上的人：去掉正在救火、戽水、以橹代舵的
func boarding_crew() -> int:
	return maxi(0, crew - int(_split["fire"]) - int(_split["flood"]) - int(_split["jury"]))


func list_deg() -> float:
	return ff.list_deg(_wind_heel)


func stability() -> float:
	return ff.stability()


func flood_frac() -> float:
	return ff.flood_frac()


func fire_total() -> float:
	return ff.fire_total()


func zone_fire(zone: String) -> float:
	return ff.zone_fire(zone)


## 此刻有人在戽水（观感：船边喷水花）
func bailing() -> bool:
	return ff.bailing_now > 0.0


## 快照，给状态条、探针、士气用。键：
##   type / hull / hull_max / sail / rudder / mast_down / jury_rudder / crew / crew_min / casualties / hits /
##   flood（浸水几成）/ reserve（储备浮力）/ settle（缓沉进度）/ sinking / list（度，右倾为正）/ stability（剩余稳性）/
##   compartments / flooded（进水舱数）/ leaks（未堵的漏）/ breached（打穿的隔舱板）/ water（各舱水位）/
##   fire（火势合计）/ fires（{bow, mid, stern, rig}）/ mode / mode_name / crew_split /
##   speed / turn / yaw_drift / gear_cap / reload / volley / spread / port_ready / starboard_ready / boarding_crew / immobile /
##   sunk（"" / flood / capsize）/ status（一行中文短注）/ bits（分项短注）
func summary() -> Dictionary:
	_reallocate()
	return {
		"type": type_id, "hull": hull, "hull_max": hull_max, "sail": sail, "rudder": rudder,
		"mast_down": mast_down, "jury_rudder": jury_rudder,
		"crew": crew, "crew_min": crew_min, "casualties": casualties, "hits": hits,
		"flood": ff.flood_frac(), "reserve": ff.reserve_now(), "settle": ff.settle, "sinking": ff.settle > 0.0,
		"list": list_deg(), "stability": ff.stability(),
		"compartments": ff.n, "flooded": ff.flooded_comps(), "leaks": ff.open_leaks(),
		"breached": ff.breached_bulkheads(), "water": Array(ff.water),
		"fire": ff.fire_total(), "fires": ff.fire.duplicate(),
		"mode": mode, "mode_name": str(MODE_NAMES.get(mode, "")), "crew_split": crew_split(),
		"speed": speed_factor(), "turn": turn_factor(), "yaw_drift": yaw_drift(), "gear_cap": gear_cap(),
		"reload": reload_factor(), "volley": volley_factor(), "spread": spread_factor(),
		"port_ready": side_ready(-1), "starboard_ready": side_ready(1), "boarding_crew": boarding_crew(),
		"immobile": is_immobile(),
		"sunk": sunk, "status": status_line(), "bits": status_bits(),
	}


## 分项短注：火、浸水、下沉、倾侧、舵、帆、伤亡，没事的项不写
func status_bits() -> PackedStringArray:
	var bits := PackedStringArray()
	if sunk != "":
		bits.append("船翻" if sunk == "capsize" else "船沉")
		return bits
	var fz := ff.burning()
	if not fz.is_empty():
		var names := PackedStringArray()
		for z in fz:
			names.append(str(ZONE_NAMES[z]))
		bits.append("%s火" % "、".join(names))
	var f := ff.flood_frac()
	var leaks := ff.open_leaks()
	if f >= 0.02:
		bits.append("进水%s" % cheng(f) + ("（漏 %d）" % leaks if leaks > 0 else ""))
	elif leaks > 0:
		bits.append("漏 %d 处" % leaks)
	if ff.settle > 0.0:
		bits.append("下沉")
	var l := list_deg()
	if absf(l) >= 5.0:
		bits.append("%s倾 %d 度" % ["右" if l > 0.0 else "左", int(round(absf(l)))])
	if rudder < RUDDER_LOST_BELOW:
		bits.append("舵失灵")
	elif jury_rudder:
		bits.append("以橹代舵")
	elif rudder < 0.95:
		bits.append("舵损%s" % cheng(1.0 - rudder))
	if mast_down:
		bits.append("桅折")
	elif sail < 0.95:
		bits.append("帆损%s" % cheng(1.0 - sail))
	if casualties > 0:
		bits.append("伤亡 %d" % casualties)
	return bits


func status_line() -> String:
	return "　".join(status_bits())


## 几成：0.3 →「三成」；不足半成 →「不足一成」；九成半以上 →「殆尽」
static func cheng(x: float) -> String:
	if x < 0.05:
		return "不足一成"
	if x >= 0.95:
		return "殆尽"
	return "%s成" % FloodFire.cn_num(clampi(int(round(x * 10.0)), 1, 9), true)


## 事件短注（纪实，不用叹号）
func event_text(kind: String, info: Dictionary) -> String:
	var comp := int(info.get("comp", -1))
	var cname := ff.comp_name(comp) if comp >= 0 else "舱"
	var zname := str(ZONE_NAMES.get(str(info.get("zone", "")), "船上"))
	match kind:
		"leak":
			return "%s中弹进水" % cname
		"compartment_full":
			return ("%s灌满，隔舱挡住" if bool(info.get("sealed", true)) else "%s灌满") % cname
		"bulkhead_breach":
			return "%s隔舱板打穿，水过邻舱" % cname
		"leak_stopped":
			return "%s漏已堵住" % cname
		"settling":
			return "吃水过深，船在下沉"
		"settle_stop":
			return "舱水戽下，船身稳住"
		"list":
			var d := float(info.get("deg", 0.0))
			return "船身%s倾 %d 度" % ["右" if d >= 0.0 else "左", int(round(absf(d)))]
		"fire":
			return "%s起火" % zname
		"fire_spread":
			return "火延到%s" % zname
		"fire_out":
			return "%s火已扑灭" % zname
		"sail_cut":
			return "斩断篷索，火篷落海"
		"magazine":
			return "火药舱爆燃"
		"sail_damage":
			return "篷帆破损%s" % cheng(1.0 - float(info.get("sail", sail)))
		"mast_down":
			return "桅折篷落"
		"rudder_damage":
			return "舵叶受创"
		"rudder_lost":
			return "舵杆折断，船不受舵"
		"jury_rudder":
			return "以橹代舵"
		"casualties":
			return "伤亡 %d 人" % int(info.get("n", 0))
		"founder":
			return "水漫上甲板，船沉"
		"capsize":
			return "倾侧过甚，船翻"
	return ""


# ── 内部 ──────────────────────────────────────────────

## 按令分派人手：先留一半操帆掌舵的底子，再派损管（看险情、按令封顶），舵失灵时派人以橹代舵，
## 再补足操帆，再上矢石炮位；还有闲手就去戽水、救火，余下的是接舷可上的人
func _reallocate() -> void:
	var c := crew
	var sail_need := maxi(2, int(ceil(float(crew_min) * 0.5)))
	var weap_need := weapons * 2
	var skeleton := mini(c, int(ceil(float(sail_need) * 0.5)))
	var avail := c - skeleton
	var caps: Array = MODE_CAPS.get(mode, MODE_CAPS["auto"])
	var fire_need := int(ceil(ff.fire_total() * FIRE_MEN_PER))
	var flood_need := int(ceil(ff.open_flow() * PLUG_MEN_PER_FLOW + ff.water_volume() / BAIL_WATER_PER_MAN))
	var fire_n := mini(fire_need, _cap_men(c, float(caps[0]), fire_need))
	var flood_n := mini(flood_need, _cap_men(c, float(caps[1]), flood_need))
	var total_cap := _cap_men(c, float(caps[2]), fire_need + flood_need)
	# 超了合计上限：戽水令先保戽水，别的令先保救火（火会蔓延，水有隔舱挡着）
	if fire_n + flood_n > total_cap:
		if mode == "flood":
			flood_n = mini(flood_n, total_cap)
			fire_n = total_cap - flood_n
		else:
			fire_n = mini(fire_n, total_cap)
			flood_n = total_cap - fire_n
	fire_n = mini(fire_n, avail)
	flood_n = mini(flood_n, avail - fire_n)
	var rest := avail - fire_n - flood_n
	var jury := 0
	if rudder < RUDDER_LOST_BELOW and not jury_rudder:
		jury = mini(JURY_MEN, rest)
		rest -= jury
	var sail_fill := mini(rest, sail_need - skeleton)
	rest -= sail_fill
	var weap_n := mini(rest, weap_need)
	rest -= weap_n
	# 闲手：舱里有水就去戽（至少两人一班，戽到见底），还有火就去救
	if rest > 0 and ff.water_volume() > 0.0:
		var idle_bail := mini(rest, maxi(IDLE_BAIL_MIN, int(ceil(ff.water_volume() / IDLE_BAIL_PER_MAN))))
		flood_n += idle_bail
		rest -= idle_bail
	if rest > 0 and fire_need > fire_n:
		var idle_fire := mini(rest, fire_need - fire_n)
		fire_n += idle_fire
		rest -= idle_fire
	_split = {"sail": skeleton + sail_fill, "sail_need": sail_need, "weapons": weap_n, "weapons_need": weap_need,
		"fire": fire_n, "flood": flood_n, "jury": jury, "spare": rest}


## 按令的比例封顶；有险情、船上又不止一人时至少派一个
static func _cap_men(c: int, frac: float, need: int) -> int:
	var m := int(floor(float(c) * frac))
	if need > 0 and m == 0 and c >= 2:
		m = 1
	return m


## 本船坐标里的命中点落在哪一段：正前方来的打在艏，正后方来的打在艉，舷侧来的顺着船长随机落
func _zone_of(at: Vector2) -> String:
	if at.length() < 0.01:
		return _roll_zone()
	var a := absf(atan2(at.x, -at.y))
	if a < 0.9:
		return "bow"
	if a > PI - 0.9:
		return "stern"
	return _roll_zone()


## 舷侧中弹顺船长落点：艏、艉各两成五，舯五成
func _roll_zone() -> String:
	var r := rng.randf()
	if r < 0.25:
		return "bow"
	if r < 0.75:
		return "mid"
	return "stern"


func _hurt_sail(amount: float, events: Array) -> void:
	if amount <= 0.0 or sail <= 0.0:
		return
	sail = maxf(0.0, sail - amount)
	if not mast_down and sail < MAST_DOWN_BELOW:
		mast_down = true
		_push(events, "mast_down", {"zone": "rig"})
	elif sail <= _sail_told - SAIL_TELL_STEP:
		_sail_told = sail
		_push(events, "sail_damage", {"zone": "rig", "sail": sail})


func _hurt_rudder(amount: float, p_side: int, events: Array) -> void:
	if amount <= 0.0:
		return
	var was := rudder
	rudder = maxf(0.0, rudder - amount)
	if was >= RUDDER_LOST_BELOW and rudder < RUDDER_LOST_BELOW:
		rudder_jam = float(signi(p_side)) * rng.randf_range(0.5, 1.0)
		_push(events, "rudder_lost", {"zone": "stern"})
	else:
		_push(events, "rudder_damage", {"zone": "stern", "rudder": rudder})


## 舵失灵：派到的人（_split.jury）以橹代舵，JURY_TIME 秒后救回 JURY_RUDDER；每仗一次
func _step_jury(delta: float, events: Array) -> void:
	if jury_rudder or rudder >= RUDDER_LOST_BELOW:
		return
	var men := int(_split["jury"])
	if men <= 0:
		return
	jury_progress += delta * float(men) / float(JURY_MEN) / JURY_TIME
	if jury_progress >= 1.0:
		jury_rudder = true
		rudder = maxf(rudder, JURY_RUDDER)
		rudder_jam = 0.0
		_push(events, "jury_rudder", {"zone": "stern"})


func _check_list(events: Array) -> void:
	var l := list_deg()
	for j in LIST_WARN.size():
		if _list_armed[j] and absf(l) >= float(LIST_WARN[j]):
			_list_armed[j] = false
			_push(events, "list", {"deg": l})
		elif not _list_armed[j] and absf(l) < float(LIST_REARM[j]):
			_list_armed[j] = true


func _push(events: Array, kind: String, info: Dictionary) -> void:
	var e := info.duplicate()
	e["kind"] = kind
	var sev := int(EVENT_SEVERITY.get(kind, 1))
	if kind == "casualties" and int(e.get("n", 0)) >= 5:
		sev = 2
	e["severity"] = sev
	e["text"] = event_text(kind, e)
	events.append(e)
