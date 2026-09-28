extends RefCounted
## 机动模型（lane combat02）：船首向 × 风向 → 帆向（顶风 / 抢风 / 侧风 / 顺风）→ 对水航速；侧风 → 风压差横漂；
## 舵效随对水航速、转向半径按船型；海流叠成对地航速。另附开火舷角、接舷接近、上风位、抢风航向几组静态查询。
## 纯计算：不碰节点、不读 autoload。船型参数按 data/ships.json 的 id 写在 PROFILES（缺型按 DEFAULT_PROFILE）。
##
## 口径（宋元近海帆船）：
## - 篾篷硬帆受风八面，唯当头不可行（徐兢《宣和奉使高丽图经》客舟条）：船首进到风来向两侧 pinch 度以内帆就不吃风，
##   只剩惯性，船身受风还往回顶，船速往下掉、舵效跟着没了——过风掉头（调戗）要趁船还有速。
## - 顺风最快在斜顺风（风从船尾一侧来），正顺风略慢，侧风次之，抢风（贴着 pinch 走）最慢、横漂最大。
## - 风压差：侧风把船往下风推，船走的航迹偏离船首向；帆越满、船身越高越轻，偏得越多。
## - 舵效：舵要有水流过才管用，转向角速度 ≈ 对水航速 / 转向半径，封顶 yaw_max；无速时只剩橹桨拨头（oar_yaw）。
##   满帆转向半径放大（船身吃风侧倾、舵压重），半帆转得最紧。舵工每级多贴风 2°、转向半径小 5%。
## - 海流：整片水在动，对地速度 = 对水速度 + 流速；帆向、舵效都按对水算，流只改航迹（流压差）。
##
## 逐帧（一船一份实例；本件不挂 class_name，调用方 const ManeuverModel := preload("res://scripts/combat/ManeuverModel.gd")）：
##   var helm = ManeuverModel.new("fu_ship_medium", sail_level, helmsman_level)
##   var v: Vector2 = helm.step(heading, helm_input, gear, sea.wind_to, sea.wind_speed, sea.current_at(pos), dt, mods)
##   rotation += helm.yaw_rate * dt        # v 为对地速度（px/s），helm.snapshot() 取帆向 / 风压差角 / 转向半径
## mods（可选；缺键时 sail / rudder / hull / oar 按 1、row 按 0）：sail 帆完好度 · rudder 舵完好度 ·
##   hull 船体（进水 / 破损拖慢）· oar 橹桨人手 · row 摇橹划桨出力（多桨船抢上风、无风时用）。都是 0–1 的乘数，
##   给损伤模型、敌船 AI 接；WorldMap 对旗舰取船节点的 maneuver_mods()（有就用）。

## 满帆、最佳帆向、参考风力下的对水航速（px/s）：与旧式 Ship 满帆顺风约 280–310 同量级，不改海战节奏
const V_REF := 285.0
const WIND_REF := 80.0
## 帆档（0 收帆 / 1 半帆 / 2 满帆）→ 吃风比例；→ 转向半径放大（满帆侧倾舵重）
const GEAR_SAIL := [0.0, 0.6, 1.0]
const GEAR_TURN := [1.0, 1.0, 1.25]
## 帆向分档（θ = 船首与风来向夹角，度）：θ < pinch 顶风 · < BEAM_FROM 抢风 · < RUN_FROM 侧风 · 其余顺风
const BEAM_FROM := 80.0
const RUN_FROM := 135.0
## 帆速曲线（θ → 吃风比例）：首点 θ 由 pinch 代入；pinch 以内 PINCH_SOFT 度里从 0 爬到首点，再往里为 0
const POLAR := [[0.0, 0.30], [72.0, 0.58], [90.0, 0.82], [120.0, 0.97], [140.0, 1.0], [160.0, 0.96], [180.0, 0.90]]
const PINCH_SOFT := 6.0
const PINCH_MIN := 40.0
## 转向掉速：舵压满时目标航速打的折扣
const TURN_BLEED := 0.25
## 减速相对加速的快慢：船重有惯性，松帆后滑行一段
const COAST := 0.55
## 调戗过风：船首在顶风区里、帆还挂着时，舵工拨帆把船首往过推（硬帆可以反吃风），比光靠舵快；
## 可用的转向角速度 = TACK_YAW × 吃风比例 × 风力乘数 × 本船 yaw_max
const TACK_YAW := 0.35
## 舵的响应、横漂的响应（1/s）；钩住敌船后停航的衰减（1/s）
const YAW_RESPONSE := 3.5
const LAT_RESPONSE := 1.6
const HOLD_DECAY := 4.0
## 舵工每级：多贴风 2°、转向半径小 5%；帆改装每级：航速 +6%、多贴风 1°
const HELMSMAN_PINCH := 2.0
const HELMSMAN_RADIUS := 0.05
const SAIL_LV_SPEED := 0.06
const SAIL_LV_PINCH := 1.0

## 开火射界缺省半宽：正横前后各 30°（床子弩、砲、火箭都架在两舷，船首船尾打不出齐射）
const ARC_HALF := 30.0
## 顺风射远、逆风射近的幅度（参考风力、正顺 / 正逆时）
const DOWNWIND_RANGE := 0.15
## 满帆正横风、参考风力时的侧倾（度）
const HEEL_MAX := 12.0
## 接舷：钩索抛出到两船拉拢的工夫（秒），风压差在这段里把两船压近或推开
const GRAPPLE_TIME := 2.0
## 上风抛钩 / 下风抛钩对够距的增减（参考风力、正上 / 正下风时）
const WEATHER_REACH := 0.18
## 相对航速超过它：两船对冲或擦舷而过，钩索挂不住（px/s）
const GRAPPLE_REL_MAX := 420.0
## 相对航速压够距：1.1 − 相对航速 / GRAPPLE_REL_SOFT，夹在 0.55–1.1
const GRAPPLE_REL_SOFT := 650.0

## 船型机动参数（id 同 data/ships.json）：
##   hull 船速系数（× V_REF）· radius 半帆时的最小转向半径 px · yaw_max 最大转向角速度 rad/s ·
##   pinch 顶风区半角（度，比这更贴风帆就不吃风）· leeway 帆面横推系数 · windage 船身受风系数（收帆也有）·
##   accel 加速响应 1/s（船越重越慢；减速按它乘 COAST）· oar 橹桨推进 px/s（mods.row 时才用）· oar_yaw 无速时橹桨拨头 rad/s
const PROFILES := {
	# 小艍船：尖底小船，转身快，船轻吃风偏得多
	"sampan": {"hull": 0.82, "radius": 170.0, "yaw_max": 1.30, "pinch": 52.0, "leeway": 0.24, "windage": 0.10,
		"accel": 1.30, "oar": 55.0, "oar_yaw": 0.40},
	"keel_boat": {"hull": 0.95, "radius": 255.0, "yaw_max": 0.95, "pinch": 50.0, "leeway": 0.20, "windage": 0.11,
		"accel": 0.95, "oar": 30.0, "oar_yaw": 0.22},
	# 福船：尖底高舷、龙骨深，贴风好、横漂小，身重转得慢
	"fu_ship_medium": {"hull": 0.97, "radius": 280.0, "yaw_max": 0.90, "pinch": 48.0, "leeway": 0.16, "windage": 0.12,
		"accel": 0.85, "oar": 25.0, "oar_yaw": 0.18},
	"canton_ship": {"hull": 0.95, "radius": 305.0, "yaw_max": 0.82, "pinch": 48.0, "leeway": 0.16, "windage": 0.12,
		"accel": 0.72, "oar": 22.0, "oar_yaw": 0.15},
	# 海鹘：两舷浮板，遇风涛不易倾侧，战船灵便
	"sea_falcon": {"hull": 1.05, "radius": 220.0, "yaw_max": 1.10, "pinch": 50.0, "leeway": 0.15, "windage": 0.10,
		"accel": 1.05, "oar": 70.0, "oar_yaw": 0.30},
	# 快船：狭长多桨，一面席帆贴不了风，靠桨手抢上风
	"pirate_boat": {"hull": 1.02, "radius": 190.0, "yaw_max": 1.20, "pinch": 58.0, "leeway": 0.26, "windage": 0.08,
		"accel": 1.25, "oar": 120.0, "oar_yaw": 0.50},
	"fu_ship_large": {"hull": 0.92, "radius": 365.0, "yaw_max": 0.68, "pinch": 48.0, "leeway": 0.15, "windage": 0.14,
		"accel": 0.60, "oar": 16.0, "oar_yaw": 0.10},
	# 神舟：巍如山岳，受风大，掉头要半个海面
	"divine_ship": {"hull": 0.85, "radius": 460.0, "yaw_max": 0.55, "pinch": 50.0, "leeway": 0.15, "windage": 0.16,
		"accel": 0.45, "oar": 12.0, "oar_yaw": 0.07},
}
const DEFAULT_PROFILE := {"hull": 0.95, "radius": 270.0, "yaw_max": 0.90, "pinch": 50.0, "leeway": 0.18,
	"windage": 0.12, "accel": 0.85, "oar": 25.0, "oar_yaw": 0.18}

## 船型（ships.json id）与其机动参数
var hull_type := ""
var profile: Dictionary = DEFAULT_PROFILE
var sail_level := 1
var helmsman := 0
## 对水速度（船身坐标：fwd 沿船首，lat 向右舷为正）与转向角速度（rad/s，正为右转，即屏幕顺时针）
var v_fwd := 0.0
var v_lat := 0.0
var yaw_rate := 0.0
## 上一步的读数：船首与风来向夹角（度）、帆向字、船首向、对地速度（含流）、当时的流
var theta := 180.0
var sail_state := "顺风"
var facing := Vector2.UP
var ground := Vector2.ZERO
var drift := Vector2.ZERO


func _init(ship_type_id := "", sail_lv := 1, helmsman_level := 0) -> void:
	hull_type = ship_type_id
	profile = profile_of(ship_type_id)
	sail_level = maxi(1, sail_lv)
	helmsman = clampi(helmsman_level, 0, 3)


## 本船此刻的顶风区半角（度）
func pinch_deg() -> float:
	return pinch_of(profile, sail_level, helmsman)


## 本船某帆档下的最小转向半径（px）
func turn_radius_min(gear: int) -> float:
	return float(profile["radius"]) * float(GEAR_TURN[clampi(gear, 0, 2)]) * (1.0 - HELMSMAN_RADIUS * helmsman)


## 本船在某对水航速、帆档下能转多快（rad/s）：舵效 = 航速 / 转向半径，封顶 yaw_max，无速时剩橹桨拨头
func turn_rate_cap(speed: float, gear: int, oar_mod := 1.0) -> float:
	var by_rudder := absf(speed) / maxf(turn_radius_min(gear), 1.0)
	return minf(float(profile["yaw_max"]), maxf(by_rudder, float(profile["oar_yaw"]) * oar_mod))


## 推进一帧。heading：船首单位向量（Vector2.UP.rotated(rotation)）；helm_input：−1 左舵 … 1 右舵；
## gear：0 收帆 / 1 半帆 / 2 满帆；wind_to / wind_speed / current：SeaState 读数；mods 见头注释。
## 返回对地速度（px/s）；yaw_rate 同步更新，调用方按它转船首。
func step(heading: Vector2, helm_input: float, gear: int, wind_to: Vector2, wind_speed: float,
		current: Vector2, dt: float, mods := {}) -> Vector2:
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2.UP
	facing = h
	var r := Vector2(-h.y, h.x)
	var g := clampi(gear, 0, 2)
	var sail_mod := clampf(float(mods.get("sail", 1.0)), 0.0, 1.0)
	var rudder_mod := clampf(float(mods.get("rudder", 1.0)), 0.0, 1.0)
	var hull_mod := clampf(float(mods.get("hull", 1.0)), 0.1, 1.0)
	var oar_mod := clampf(float(mods.get("oar", 1.0)), 0.0, 1.0)
	var row := clampf(float(mods.get("row", 0.0)), 0.0, 1.0) * oar_mod
	var w := maxf(wind_speed, 0.0)
	var wt := wind_to.normalized() if wind_to.length_squared() > 0.0 else Vector2.ZERO
	theta = angle_off_wind(h, wt)
	var pinch := pinch_deg()
	sail_state = sail_word(theta, pinch)
	# 帆推：帆向曲线 × 帆档 × 风力（开方：风大一倍船速多四成）；摇橹划桨与帆推取大的
	var drive := V_REF * float(profile["hull"]) * (1.0 + SAIL_LV_SPEED * (sail_level - 1)) * polar(theta, pinch) \
			* float(GEAR_SAIL[g]) * sail_mod * wind_mul(w)
	var fwd_target := maxf(drive, float(profile["oar"]) * row)
	# 船身受风：顺风往前推，顶风往回顶（帆不吃风时船会倒退）
	fwd_target += float(profile["windage"]) * w * wt.dot(h)
	fwd_target *= hull_mod
	# 舵压重时掉速
	var yaw_max := maxf(float(profile["yaw_max"]), 0.01)
	fwd_target *= 1.0 - TURN_BLEED * clampf(absf(yaw_rate) / yaw_max, 0.0, 1.0)
	# 加速按 accel；松帆 / 顶风时船靠惯性往前冲一段才停（减速按 COAST 放慢），调戗过风靠的就是这股余速
	var k := float(profile["accel"]) * (1.0 if fwd_target > v_fwd else COAST)
	v_fwd += (fwd_target - v_fwd) * (1.0 - exp(-k * dt))
	# 风压差：帆面横推（随帆档）+ 船身受风，推向下风一舷
	var lat_target := (float(profile["leeway"]) * float(GEAR_SAIL[g]) * sail_mod + float(profile["windage"])) * w * wt.dot(r)
	v_lat += (lat_target - v_lat) * (1.0 - exp(-LAT_RESPONSE * dt))
	# 舵效：对水航速 / 转向半径，封顶 yaw_max；无速时橹桨拨头；顶风区里挂着帆还能拨帆过风
	var yaw_cap := turn_rate_cap(v_fwd, g, oar_mod)
	if theta < pinch and g > 0:
		yaw_cap = maxf(yaw_cap, TACK_YAW * float(GEAR_SAIL[g]) * sail_mod * wind_mul(w) * float(profile["yaw_max"]))
	var yaw_target := clampf(helm_input, -1.0, 1.0) * yaw_cap * rudder_mod
	yaw_rate += (yaw_target - yaw_rate) * (1.0 - exp(-YAW_RESPONSE * dt))
	drift = current
	ground = h * v_fwd + r * v_lat + current
	return ground


## 钩住敌船（两船绑在一处）：航速、横漂、转向都衰减到 0，也不随流走开；返回对地速度
func hold(heading: Vector2, dt: float) -> Vector2:
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2.UP
	facing = h
	var a := 1.0 - exp(-HOLD_DECAY * dt)
	v_fwd -= v_fwd * a
	v_lat -= v_lat * a
	yaw_rate -= yaw_rate * a
	drift = Vector2.ZERO
	ground = h * v_fwd + Vector2(-h.y, h.x) * v_lat
	return ground


## 读数（HUD / AI / 探针）：帆向、对水 / 对地航速、风压差角（对水航迹偏船首几度）、流压差角（对地航迹再偏对水航迹几度）、
## 对地航向方位、此刻转向半径。两个偏角都是正为偏右舷
func snapshot() -> Dictionary:
	var through := sqrt(v_fwd * v_fwd + v_lat * v_lat)
	var water := facing * v_fwd + Vector2(-facing.y, facing.x) * v_lat
	var drift_deg := 0.0
	if water.length_squared() > 1.0 and ground.length_squared() > 1.0:
		drift_deg = rad_to_deg(water.angle_to(ground))
	return {
		"type": hull_type,
		"theta": theta,
		"sail_state": sail_state,
		"pinch": pinch_deg(),
		"v_fwd": v_fwd,
		"v_lat": v_lat,
		"speed_water": through,
		"leeway_deg": rad_to_deg(atan2(v_lat, maxf(absf(v_fwd), 1.0))),
		"drift_deg": drift_deg,
		"course_deg": fposmod(rad_to_deg(atan2(ground.x, -ground.y)), 360.0),
		"yaw_rate": yaw_rate,
		"turn_radius": absf(v_fwd) / absf(yaw_rate) if absf(yaw_rate) > 0.001 else INF,
		"turn_radius_min": turn_radius_min(1),
		"ground": ground,
		"speed_ground": ground.length(),
		"current": drift,
	}


# ── 静态查询（不需要实例）──────────────────────────────────

## 船型参数（缺型、缺键按 DEFAULT_PROFILE 补齐）
static func profile_of(type_id: String) -> Dictionary:
	var p: Dictionary = DEFAULT_PROFILE.duplicate()
	p.merge(PROFILES.get(type_id, {}), true)
	return p


## 顶风区半角（度）：船型基准 − 舵工 − 帆改装，不低于 PINCH_MIN
static func pinch_of(p: Dictionary, sail_lv := 1, helmsman_level := 0) -> float:
	var base := float(p.get("pinch", DEFAULT_PROFILE["pinch"]))
	return maxf(PINCH_MIN, base - HELMSMAN_PINCH * clampi(helmsman_level, 0, 3) - SAIL_LV_PINCH * (maxi(1, sail_lv) - 1))


## 船首与风来向的夹角（度，0–180）：0 = 船首正对来风（当头），180 = 风从正船尾来
static func angle_off_wind(heading: Vector2, wind_to: Vector2) -> float:
	if wind_to.length_squared() == 0.0 or heading.length_squared() == 0.0:
		return 180.0
	return absf(rad_to_deg(heading.angle_to(-wind_to)))


## 帆向字：顶风 / 抢风 / 侧风 / 顺风
static func sail_word(theta_deg: float, pinch := 50.0) -> String:
	if theta_deg < pinch:
		return "顶风"
	if theta_deg < BEAM_FROM:
		return "抢风"
	if theta_deg < RUN_FROM:
		return "侧风"
	return "顺风"


## 帆速曲线：某帆向下帆能吃到几成风（0–1）
static func polar(theta_deg: float, pinch := 50.0) -> float:
	var first := float(POLAR[0][1])
	if theta_deg <= pinch - PINCH_SOFT:
		return 0.0
	if theta_deg < pinch:
		return first * (theta_deg - (pinch - PINCH_SOFT)) / PINCH_SOFT
	var prev_t := pinch
	var prev_f := first
	for i in range(1, POLAR.size()):
		var t := float(POLAR[i][0])
		var f := float(POLAR[i][1])
		if theta_deg <= t:
			return lerpf(prev_f, f, (theta_deg - prev_t) / maxf(t - prev_t, 0.001))
		prev_t = t
		prev_f = f
	return prev_f


## 风力对帆速的乘数：开方（风大一倍船速多四成），参考风力为 1，封顶 1.2
static func wind_mul(wind_speed: float) -> float:
	return clampf(sqrt(maxf(wind_speed, 0.0) / WIND_REF), 0.0, 1.2)


## 某船型在某帆向、帆档、风力下的定常对水航速（px/s，不计转向掉速与流）：AI 挑航向、探针对照用
static func sail_speed(type_id: String, theta_deg: float, gear: int, wind_speed: float, sail_lv := 1, helmsman_level := 0) -> float:
	var p := profile_of(type_id)
	var pinch := pinch_of(p, sail_lv, helmsman_level)
	var drive := V_REF * float(p["hull"]) * (1.0 + SAIL_LV_SPEED * (maxi(1, sail_lv) - 1)) * polar(theta_deg, pinch) \
			* float(GEAR_SAIL[clampi(gear, 0, 2)]) * wind_mul(wind_speed)
	# 船身受风：θ = 180 顺推、θ = 0 顶推
	return drive - float(p["windage"]) * maxf(wind_speed, 0.0) * cos(deg_to_rad(theta_deg))


## 某船型在此航速、帆档下的转向半径（px）：低速按最小半径（再慢就是原地拨头），高速被 yaw_max 封住、半径随航速放大
static func turn_radius_of(type_id: String, speed: float, gear := 1, helmsman_level := 0) -> float:
	var p := profile_of(type_id)
	var r_min := float(p["radius"]) * float(GEAR_TURN[clampi(gear, 0, 2)]) * (1.0 - HELMSMAN_RADIUS * clampi(helmsman_level, 0, 3))
	var w := minf(float(p["yaw_max"]), maxf(absf(speed) / maxf(r_min, 1.0), float(p["oar_yaw"])))
	return absf(speed) / maxf(w, 0.001)


## 风压差横漂（对水，px/s 向量）：帆面横推（随帆档）+ 船身受风，推向下风一舷。
## boarding_approach 拿两船之差算谁被风压向谁。
static func leeway_drift(type_id: String, heading: Vector2, gear: int, wind_to: Vector2, wind_speed: float) -> Vector2:
	var p := profile_of(type_id)
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2.UP
	var r := Vector2(-h.y, h.x)
	var wt := wind_to.normalized() if wind_to.length_squared() > 0.0 else Vector2.ZERO
	var coef := float(p["leeway"]) * float(GEAR_SAIL[clampi(gear, 0, 2)]) + float(p["windage"])
	return r * coef * maxf(wind_speed, 0.0) * wt.dot(r)


## a 相对 b 的上风程度（−1–1）：1 = b 在 a 的正下风（a 占上风），−1 = a 在 b 的正下风
static func weather_gauge(a_pos: Vector2, b_pos: Vector2, wind_to: Vector2) -> float:
	var d := b_pos - a_pos
	if d.length_squared() < 0.000001 or wind_to.length_squared() == 0.0:
		return 0.0
	return d.normalized().dot(wind_to.normalized())


## 上风位字：占上风 / 处下风 / 风位相当
static func gauge_word(gauge: float) -> String:
	if gauge > 0.35:
		return "占上风"
	if gauge < -0.35:
		return "处下风"
	return "风位相当"


## 往 to 去该走的船首向（单位向量）：直线不在顶风区就直走；目标在上风 pinch 以内就走贴风的一舷（抢风调戗），
## 取离直线近的那一舷。margin_deg 为贴风留的余量。
static func heading_toward(from: Vector2, to: Vector2, wind_to: Vector2, pinch_deg := 50.0, margin_deg := 4.0) -> Vector2:
	var want := (to - from).normalized() if (to - from).length_squared() > 0.0 else Vector2.UP
	if wind_to.length_squared() == 0.0:
		return want
	var wind_from := -wind_to.normalized()
	if absf(rad_to_deg(want.angle_to(wind_from))) >= pinch_deg + margin_deg:
		return want
	var off := deg_to_rad(pinch_deg + margin_deg)
	var port_tack := wind_from.rotated(off)
	var starboard_tack := wind_from.rotated(-off)
	return port_tack if port_tack.dot(want) >= starboard_tack.dot(want) else starboard_tack


## 开火舷角：target 在 shooter 的哪一舷、离正横几度、在不在两舷射界里，顺逆风、侧倾对射程与准头的修正。
## heading 为船首单位向量；gear 为 shooter 帆档（算侧倾）；arc_half_deg 为射界半宽（正横前后各几度）。返回：
##   distance · bearing_deg 目标舷角（−180–180，正为右舷）· side 1 右舷 / −1 左舷 / 0 不在两舷射界 ·
##   side_name「右舷」「左舷」「船首」「船尾」· off_beam_deg 离正横几度 · in_arc · quality 射界内 1（正横）→ 0（边）·
##   downwind 顺风射为正（已乘风力比）· range_mul 射程乘数（0.75–1.25）· heel_deg 侧倾 · lee_side 射向下风舷 ·
##   accuracy_mul 准头乘数（侧倾越大越差，0.75–1）
static func fire_arc(shooter_pos: Vector2, heading: Vector2, target_pos: Vector2, wind_to: Vector2, wind_speed: float,
		gear := 1, arc_half_deg := ARC_HALF) -> Dictionary:
	var h := heading.normalized() if heading.length_squared() > 0.0 else Vector2.UP
	var r := Vector2(-h.y, h.x)
	var to := target_pos - shooter_pos
	var dist := to.length()
	var u := to / dist if dist > 0.001 else h
	var bearing := rad_to_deg(h.angle_to(u))
	var off_beam := absf(absf(bearing) - 90.0)
	var in_arc := off_beam <= arc_half_deg
	var side := 0
	var side_name := "船首" if absf(bearing) < 90.0 else "船尾"
	if in_arc:
		side = 1 if bearing > 0.0 else -1
		side_name = "右舷" if side > 0 else "左舷"
	var wt := wind_to.normalized() if wind_to.length_squared() > 0.0 else Vector2.ZERO
	var wr := clampf(maxf(wind_speed, 0.0) / WIND_REF, 0.0, 1.6)
	var downwind := u.dot(wt) * wr
	# 侧倾：风往右舷吹（cross > 0）船就向右倾，右舷是下风舷——下风舷压低射近，上风舷翘起射远些
	var cross := wt.dot(r)
	var heel := HEEL_MAX * float(GEAR_SAIL[clampi(gear, 0, 2)]) * absf(cross) * minf(wr, 1.5)
	var heel_n := heel / HEEL_MAX
	var lee_side := side != 0 and absf(cross) > 0.05 and signf(cross) == float(side)
	var range_mul := 1.0 + DOWNWIND_RANGE * clampf(downwind, -1.3, 1.3)
	if side != 0:
		range_mul += (-0.06 if lee_side else 0.04) * heel_n
	return {
		"distance": dist,
		"bearing_deg": bearing,
		"side": side,
		"side_name": side_name,
		"off_beam_deg": off_beam,
		"in_arc": in_arc,
		"quality": clampf(1.0 - off_beam / maxf(arc_half_deg, 1.0), 0.0, 1.0),
		"downwind": downwind,
		"range_mul": clampf(range_mul, 0.75, 1.25),
		"heel_deg": heel,
		"lee_side": lee_side,
		"accuracy_mul": clampf(1.0 - 0.15 * heel_n, 0.75, 1.0),
	}


## 接舷接近：a 想钩 b。a / b 各是 {pos, vel, heading, type, gear}（vel 取对地速度即可：两船同在一股流里，相对速度里流抵消）。
## 够距 = base_reach × 相对航速折扣 × 上风增减 + 风压差（两船横漂之差把 a 压向 b 的分量 × 抛钩拉拢的工夫）。返回：
##   distance · closing_speed 接近速度（正为在靠拢）· relative_speed · weather_gauge / gauge_word（a 的上风位）·
##   drift_closing 风压差压拢速度（px/s，正为风把 a 压向 b）· speed_mod · wind_mod · reach · base_reach ·
##   ok 够得着且不对冲 · reason 顶匾短语 / note 浮字整句（只在旧口径够得着、新口径被风或航速挡下时才写，其余为空）
static func boarding_approach(a: Dictionary, b: Dictionary, wind_to: Vector2, wind_speed: float, base_reach := 140.0) -> Dictionary:
	var pa: Vector2 = a.get("pos", Vector2.ZERO)
	var pb: Vector2 = b.get("pos", Vector2.ZERO)
	var va: Vector2 = a.get("vel", Vector2.ZERO)
	var vb: Vector2 = b.get("vel", Vector2.ZERO)
	var d := pa.distance_to(pb)
	var u := (pb - pa) / d if d > 0.001 else Vector2.ZERO
	var rel := va - vb
	var rel_speed := rel.length()
	var ws := maxf(wind_speed, 0.0)
	var wr := clampf(ws / WIND_REF, 0.0, 1.3)
	var gauge := weather_gauge(pa, pb, wind_to)
	var ha: Vector2 = a.get("heading", Vector2.UP)
	var hb: Vector2 = b.get("heading", Vector2.UP)
	var drift_a := leeway_drift(str(a.get("type", "")), ha, int(a.get("gear", 1)), wind_to, ws)
	var drift_b := leeway_drift(str(b.get("type", "")), hb, int(b.get("gear", 1)), wind_to, ws)
	var drift_closing := (drift_a - drift_b).dot(u)
	var speed_mod := clampf(1.1 - rel_speed / GRAPPLE_REL_SOFT, 0.55, 1.1)
	var wind_mod := 1.0 + WEATHER_REACH * gauge * wr
	var drift_reach := clampf(drift_closing * GRAPPLE_TIME, -0.25 * base_reach, 0.25 * base_reach)
	var reach := clampf(base_reach * speed_mod * wind_mod + drift_reach, 0.5 * base_reach, 1.4 * base_reach)
	var too_fast := rel_speed > GRAPPLE_REL_MAX
	var ok := d <= reach and not too_fast
	var reason := ""
	var note := ""
	if not ok and d <= base_reach:
		var speed_loss := base_reach * (1.0 - speed_mod)
		var wind_loss := base_reach * speed_mod * (1.0 - wind_mod) - drift_reach
		if too_fast:
			reason = "对冲太快　钩不住"
			note = "两船对冲太快，钩索挂不住。"
		elif speed_loss >= wind_loss:
			reason = "航速悬殊　钩不住"
			note = "两船航速相差太大，钩索挂不住。"
		elif gauge < -0.2:
			reason = "身处下风　靠不上"
			note = "身处下风，风压把船推开，钩索够不着。"
		else:
			reason = "风压推开　靠不上"
			note = "风压把两船推开，钩索够不着。"
	return {
		"distance": d,
		"closing_speed": rel.dot(u),
		"relative_speed": rel_speed,
		"weather_gauge": gauge,
		"gauge_word": gauge_word(gauge),
		"drift_closing": drift_closing,
		"speed_mod": speed_mod,
		"wind_mod": wind_mod,
		"reach": reach,
		"base_reach": base_reach,
		"ok": ok,
		"reason": reason,
		"note": note,
	}
