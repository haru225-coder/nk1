## 敌船进水与失火（lane w53-p3a，战斗系统方案 §十 三期「火与水」）：敌船只加挂 FloodFire 这一件，
## 不挂完整的伤损模型（DamageModel 那套帆 / 舵 / 损管令、人手分派表都在玩家船上，敌船不另起一套）。
## 每艘敌船（PirateShip）一份，RefCounted 不进树、不读 autoload，-s 探针可以直接 new。
##
## 口径照玩家侧同物件：
##   取数：FloodFire.setup 的船型档从 DamageModel.profile_for 拿（泉州宋船十三舱、海鹘稳性 1.5 ……同一张表），
##     舱容 = DamageModel.VOLUME_BASE + capacity；fire_resist 也在档里。有炮位（cannon_slots > 0）才 powder=true。
##   收弹：时级命中（PirateShip.take_damage 原来那套）照 DamageModel.KINDS.shot 的 leak 折率在水线下
##     加一处小漏；整份 hit（take_ballistic_hit 现矢）照弹种 KINDS 的水线下率、引火率各自开漏、点火。
##   逐帧：水手按险情分一小撮人去救火 / 堵漏戽水（人手从炮位抽——敌船齐射 cooldown × fire_outage_factor 拖慢，
##     火烟倾侧也在出膛那一轮按 fire_volley_shrink 折掉几发，不改 EnemyCaptainAI 任何文件）；
##     火会蔓延、烧船体（hull_dps 由 PirateShip 走 take_damage 同一路扣，不绕开击沉逻辑）、火场偶有伤亡（crew_cas 扣 crew）。
##   沉：settle 涨满 1 或倾覆 —— PirateShip 照 _explode 原路沉，赏钱照击沉算。
##   冻：已降（struck）、被钩住（grappled）、白刃进行中、已结算（resolution 关了）的船 step 直接返回空账，水火不长，
##     免得把要夺的船烧没了。PirateShip 在 take_damage / take_ballistic_hit 入口也拒，不在冻结帧新添漏洞火苗。
extends RefCounted

const _DM := preload("res://scripts/combat/DamageModel.gd")
const _FF := preload("res://scripts/combat/FloodFire.gd")

## 损管抽人（按现有水手计）：
##   火上门 = ceil（火势合计 × 每处满火摊几人）；漏上门 = ceil（未堵的漏流量 × 每 1 料/秒摊几人 + 舱水 / 每多少料摊一人）。
##   抽走的是与炮位分的那一小撮（封顶 REACH_CAP），险情没有那么大的人手不够再减。
##   敌船没有 DamageModel 那层「炮位 n × 2 人」的明账，这一份只用来拖 cooldown、折出膛数：抽 1 人也开火，
##   齐射间隔 ×1.15，往后多抽的人加到装填更慢（封顶 ×1.8）；出膛一发要几成(now = n+抽)凑整——现在舷侧 cannon_count
##   上限 2，抽走人后一枚折到 1（少发个三五成仍出 1 才印得出火烟拖慢敌船装填的门道）。
## 人手从炮位抽、烧船体、火场伤亡这三件的数都按 FloodFire 头注的比例给出，不在本簿另造口径。
const FIRE_MEN_PER := 8.0
const PLUG_MEN_PER_FLOW := 0.55
const BAIL_WATER_PER_MAN := 24.0
## 损管抽人占现有水手的上限：照玩家 fight 令的 0.15，九成的敌船自保有到两成
const REACH_CAP := 0.2
## 抽走的人压出膛：这一份 = volley_eta × fire_volley_shrink 的出膛数
## 折掉几成出膛当几发：出膛 1 发的船，每抽 full_draw 人折没那一发（按 COOLDOWN 顶格与 volley 再二折）
## 敌船 cannon_count ≤ 2：抽 4 人（2 门 × 2 人）折 1 发，抽 8 人两发全折——人手从炮位抽、人不够整舷哑掉
const DRAW_MEN_PER_GUN := 2

var ff = null   ## FloodFire
var rng := RandomNumberGenerator.new()
## 每发时级命中（take_damage）在上添水线下漏的 ingress 量（料/秒/船体伤点——照 DamageModel LEAK_PER_DMG × shot.leak 再二折，
## 敌船没挂全伤损，弹着处走量的旧账只让五分之一的进水量进账，不让水快得抢戏）
const LEAK_BALLISTIC_PER_DMG := 0.32 * 0.2


## p_def：ships.json 的船型条目（Fleet.ship_def）；p_seed != 0 定种（探针复现），0 随机
func setup(p_type: String, p_def: Dictionary, p_seed := 0) -> void:
	var profile := _DM.profile_for(p_type, p_def)
	var vol := _DM.VOLUME_BASE + float(p_def.get("capacity", _DM.CAPACITY_DEFAULT))
	ff = _FF.new()
	ff.setup(int(profile["compartments"]), vol, float(profile["reserve"]), float(profile["stability"]),
		float(profile["fire_resist"]), int(p_def.get("cannon_slots", 0)) > 0)
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()


## 时级命中账上加水：PirateShip.take_damage 的旧弹（玩家 player_gunnery 关、legacy_shot）没有弹种 / 引火账，
## 照 hull 命中的份有几率开一处小漏（进水口按伤点 × LEAK_BALLISTIC_PER_DMG），没有引火。
## 进水占这一发船体伤的三成几率，找到水线下哪一舷就贴哪一舷；关开关时本函数根本不会被调到。
func on_timed_hit(amount: float, hit_side := 0) -> void:
	if ff == null or amount < 5.0:
		return
	if rng.randf() < 0.30:
		var comp: int = rng.randi_range(0, ff.n - 1)
		ff.add_leak(comp, amount * LEAK_BALLISTIC_PER_DMG, hit_side)


## 整份命中（take_ballistic_hit 现矢）：按弹种 KINDS 的账——甲板上、带 fire 几率的按 ignite 点对应段；
## 水线下、重弹（heavy）按 leak 率加漏。撞不穿板的轻矢（arrow / bolt 半价）也照表，与玩家船同一个 KINDS 表。
## hit 键照 Cannonball._strike：kind / amount / local（本船坐标命中处 Vector2）/ heavy / fire。
func on_ballistic_hit(hit: Dictionary) -> void:
	if ff == null:
		return
	var kind := str(hit.get("kind", "shot"))
	if not _DM.KINDS.has(kind):
		kind = "shot"
	var k: Dictionary = _DM.KINDS[kind]
	var amount := maxf(0.0, float(hit.get("amount", 0.0)))
	if amount <= 0.0:
		return
	var scale := amount / 25.0
	var zone := "mid"
	var at = hit.get("local")
	if at is Vector2:
		if absf(at.y) > 12.0:
			zone = "bow" if at.y < 0.0 else "stern"
		elif absf(at.y) < 4.0 and absf(at.x) < 18.0:
			zone = "mid"
		else:
			zone = "bow" if rng.randf() < 0.5 else "stern"
	var side := 1 if at is Vector2 and (at as Vector2).x >= 0.0 else -1
	# 带 fire 几率的弹（fire / bomb / shot 的 6%）：按几率点着这一段；rig 段照 KINDS.rig 率中篷帆
	var fire_p := float(k["fire"])
	if fire_p > 0.0 and rng.randf() < fire_p:
		var fz := "rig" if rng.randf() < float(k["rig"]) else zone
		ff.ignite(fz, float(k["ignite"]) * scale)
	# 水线下、重弹：按几率开漏（轻矢水线率 0；stone / shot / bomb / ram 才有）
	if bool(hit.get("heavy", true)) and float(k["leak"]) > 0.0 and rng.randf() < float(k["waterline"]):
		var comps: PackedInt32Array = ff.zone_comps(zone)
		var comp: int = comps[rng.randi_range(0, comps.size() - 1)]
		ff.add_leak(comp, amount * float(k["leak"]) * _DM.LEAK_PER_DMG, side)


## 损管抽人：看险情分派救火 / 堵漏戽水的人头（不超 REACH_CAP 成），返回 [flood_crew, fire_crew]
func damage_crews(crew: int) -> Array:
	var fire_need := int(ceil(ff.fire_total() * FIRE_MEN_PER))
	var flood_need := int(ceil(ff.open_flow() * PLUG_MEN_PER_FLOW + ff.water_volume() / BAIL_WATER_PER_MAN))
	var reach := int(floor(float(crew) * REACH_CAP))
	# 有险情、船上又不止一人时至少派一个
	if fire_need + flood_need > 0 and reach == 0 and crew >= 2:
		reach = 1
	var fire_n := mini(fire_need, reach)
	var flood_n := mini(flood_need, reach - fire_n)
	return [flood_n, fire_n]


## 抽走的人把这一舷的出膛折几成（0–1）：两发满员 4 人；抽不到人恒 1（无水火照常齐射）
func fire_volley_shrink(crew: int, mounts: int) -> float:
	var crews := damage_crews(crew)
	var drawn := int(crews[0]) + int(crews[1])
	if drawn <= 0:
		return 1.0
	var full_draw := maxi(1, mounts) * DRAW_MEN_PER_GUN
	# 抽得再狠也留一成半的炮位：损伤簿没有 DamageModel「炮位 2 人/门」的明账，
	# 不让损管把整舷炮全抽空到哑掉——拖慢、折到一两发即可
	var eff_draw := minf(float(drawn), float(full_draw) * 0.85)
	return clampf(1.0 - eff_draw / float(full_draw), 0.15, 1.0)


## 逐帧推进。delta 秒、env 可带 wind / rain（PirateShip 从 target 船取）。返回：
##   hull_dps 火烧船体该扣的船体/秒（PirateShip 乘 delta 走 take_damage 扣，不绕开击沉逻辑）
##   crew_cas 本步火场伤亡（PirateShip 扣 crew）
##   founder "" / "flood" / "capsize"：满了 PirateShip 照 _explode 沉
##   fire_zones 此刻烧着的段（观感：PirateShip 挂 CombatFx 火点用）
func step(delta: float, crew: int, env: Dictionary) -> Dictionary:
	var out := {"hull_dps": 0.0, "crew_cas": 0, "founder": str(ff.foundered), "fire_zones": ff.burning()}
	if ff == null or str(ff.foundered) != "" or delta <= 0.0:
		return out
	var crews := damage_crews(crew)
	var r: Dictionary = ff.step(delta, int(crews[0]), int(crews[1]), env, rng)
	out["hull_dps"] = float(r["hull_burn"])
	out["crew_cas"] = int(r["crew_burn"]) + (1 if bool(r["blast"]) else 0)
	out["founder"] = str(r["founder"])
	out["fire_zones"] = ff.burning()
	return out


## 冻结：已降 / 被钩 / 白刃进行中 / 已结算的船——水火不长，也不收新漏新火
func frozen(flags: Dictionary) -> bool:
	return ff == null or bool(flags.get("struck", false)) or bool(flags.get("grappled", false)) \
		or bool(flags.get("boarding", false)) or bool(flags.get("resolved", false)) \
		or str(ff.foundered) != ""


## 给 p3c 敌情列的公开读口（契约固定）：火 0–1 / 进水 0–1 / 烧着的段 / 倾侧度 / 正下沉
func state() -> Dictionary:
	if ff == null:
		return {}
	return {"fire": float(ff.fire_total()), "flood": float(ff.flood_frac()), "burning": ff.burning(),
		"list_deg": float(ff.list_deg()), "sinking": ff.settle > 0.0}
