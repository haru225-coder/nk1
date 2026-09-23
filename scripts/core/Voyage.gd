extends Node
## 航海：里程、方位、季风修正、航段推演与逐日事件。
## 航行以「日」为单位推进，每一日抽一次事件。
## 发舶前选定航法（针路 / 外洋 / 傍岸），改变日速与事件分布；生路另有迷航。

## 1 宋里约 576 米
const KM_PER_LI := 0.576
const EARTH_R_KM := 6371.0

## 逆风/顺风对日速的乘数区间。航法乘在这之后，不得把顶头逆风乘成顺风。
const WIND_MIN := 0.40
const WIND_MAX := 1.60

## 航法日速倍率。外洋不超过 1.20，否则会架空候风；傍岸不低于 0.70，否则远洋数学上走不完。
const ORDER_SPEED_OFFSHORE := 1.18
const ORDER_SPEED_COAST := 0.78

## 针路 + 熟路的事件权重与改航法之前的表一致。其余航法只改这些数。
const W_STORM_BASE := 0.06
const W_STORM_WIND := 0.06
const W_PIRATE := 0.06
const W_CALM := 0.06
const W_CURRENT := 0.05
const W_MERCHANT := 0.04
const W_DISCOVERY := 0.03
const OFFSHORE_STORM_MUL := 1.55
const OFFSHORE_PIRATE_MUL := 1.65
const OFFSHORE_CALM := 0.04
const OFFSHORE_CURRENT := 0.07
const OFFSHORE_MERCHANT := 0.03
const OFFSHORE_DISCOVERY := 0.008
const COAST_STORM_MUL := 0.65
const COAST_PIRATE_MUL := 0.40
const COAST_CALM := 0.07
const COAST_CURRENT := 0.03
const COAST_MERCHANT := 0.05
const COAST_DISCOVERY := 0.08
const COAST_SHOAL := 0.07
## 生路迷航。外洋没有岸影可对，最高；傍岸靠岸影修正，最低。
const LOST_RUMB := 0.08
const LOST_OFFSHORE := 0.12
const LOST_COAST := 0.05
const MAX_EVENT_MASS := 0.90

## 浅滩只蹭掉当日大部分行程；迷航则把船送回去一截。
const SHOAL_HULL := 5.0
const SHOAL_PROGRESS := 0.35
const LOST_PROGRESS := -0.55
## 标准正态 80% 分位。八成日数≈十次航行有八次不迟于它。
const SAFE_Z := 0.8416

## 海上买货不得便宜过「普通口岸、行情 1.0」的买价。卖货不得高于最佳消费地卖价的九二折。
const SEA_BUY_MARKUP := 1.12
const SEA_SELL_CAP := 0.92
const SEA_SELL_JITTER_MIN := 0.82
const SEA_SELL_JITTER_MAX := 1.02

enum CourseOrder { RUMB, OFFSHORE, COAST }
enum EventKind { NONE, CALM, CURRENT, STORM, PIRATE, MERCHANT, DISCOVERY, SHOAL, LOST }


func port_def(port_id: String) -> Dictionary:
	for p in GameManager.ports_data.get("ports", []):
		if p.get("id") == port_id:
			return p
	return {}


# ── 几何 ──────────────────────────────────────────────

func distance_li(from_id: String, to_id: String) -> float:
	var a := port_def(from_id)
	var b := port_def(to_id)
	if a.is_empty() or b.is_empty():
		return 0.0
	var lat1 := deg_to_rad(float(a.get("lat", 0.0)))
	var lon1 := deg_to_rad(float(a.get("lon", 0.0)))
	var lat2 := deg_to_rad(float(b.get("lat", 0.0)))
	var lon2 := deg_to_rad(float(b.get("lon", 0.0)))
	var dlat := lat2 - lat1
	var dlon := lon2 - lon1
	var h := sin(dlat / 2.0) * sin(dlat / 2.0) + cos(lat1) * cos(lat2) * sin(dlon / 2.0) * sin(dlon / 2.0)
	var c := 2.0 * atan2(sqrt(h), sqrt(1.0 - h))
	return (EARTH_R_KM * c) / KM_PER_LI


## 航向方位角（度，0=正北 顺时针）
func bearing(from_id: String, to_id: String) -> float:
	var a := port_def(from_id)
	var b := port_def(to_id)
	if a.is_empty() or b.is_empty():
		return 0.0
	var lat1 := deg_to_rad(float(a.get("lat", 0.0)))
	var lat2 := deg_to_rad(float(b.get("lat", 0.0)))
	var dlon := deg_to_rad(float(b.get("lon", 0.0)) - float(a.get("lon", 0.0)))
	var y := sin(dlon) * cos(lat2)
	var x := cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


# ── 季风修正 ──────────────────────────────────────────

## 季风对给定航向的日速乘数。at_month < 1 时用当前月，否则用那一个月的风。
func wind_factor(course_bearing: float, at_month: int = -1) -> float:
	var wind := Calendar.get_wind_bearing()
	var strength := Calendar.get_monsoon_strength()
	if at_month >= 1:
		wind = Calendar.wind_bearing_of(at_month)
		strength = Calendar.monsoon_strength_of(at_month)
	if wind < 0.0:
		# 转换期：无稳定季风，略微不利
		return 0.85
	var diff := absf(angle_difference(deg_to_rad(course_bearing), deg_to_rad(wind)))
	# diff=0 完全顺风；diff=PI 完全逆风
	var t := cos(diff)  # 1 → -1
	var raw := 1.0 + t * 0.6
	# 季风强度弱时向 1.0 收敛
	raw = 1.0 + (raw - 1.0) * strength
	# 舵工抢风，抬高逆风时的下限
	return clampf(raw, Crew.wind_floor(), WIND_MAX)


func wind_desc(course_bearing: float, at_month: int = -1) -> String:
	var wind := Calendar.get_wind_bearing()
	if at_month >= 1:
		wind = Calendar.wind_bearing_of(at_month)
	if wind < 0.0:
		return "无定向风"
	var diff := absf(rad_to_deg(angle_difference(deg_to_rad(course_bearing), deg_to_rad(wind))))
	if diff < 45.0:
		return "顺风"
	elif diff < 100.0:
		return "侧风"
	elif diff < 140.0:
		return "斜逆风"
	return "顶头逆风"


# ── 航段推演 ──────────────────────────────────────────

func order_speed_mult(order: int) -> float:
	if order == CourseOrder.OFFSHORE:
		return ORDER_SPEED_OFFSHORE
	if order == CourseOrder.COAST:
		return ORDER_SPEED_COAST
	return 1.0


func order_name(order: int) -> String:
	if order == CourseOrder.OFFSHORE:
		return "外洋"
	if order == CourseOrder.COAST:
		return "傍岸"
	return "针路"


func order_blurb(order: int) -> String:
	if order == CourseOrder.OFFSHORE:
		return "外洋：日速 ×%.2f。风暴与海盗更密，几乎碰不到岸影。逆风也不会因此变成顺风。" % ORDER_SPEED_OFFSHORE
	if order == CourseOrder.COAST:
		return "傍岸：日速 ×%.2f。海盗少、岸影多，但会擦到浅滩。生路上靠岸影，反而不容易迷航。" % ORDER_SPEED_COAST
	return "针路：按熟路的针位走。速度、风涛、海盗都是寻常概率。"


## 当日行程倍率的均值和方差。风暴、海盗、商船、岸影进度都是 1；无风归零，顺流 1.5，浅滩与迷航按系数。
## 季风强度几乎不进均值——那些权重不随风势变，除非事件总质量被压到上限。
func progress_moments(order: int, known: bool, discoveries_open: bool = true, at_month: int = -1) -> Dictionary:
	var strength := Calendar.get_monsoon_strength()
	if at_month >= 1:
		strength = Calendar.monsoon_strength_of(at_month)
	var w := event_weights(order, strength, known, discoveries_open)
	var calm := float(w["calm"])
	var current := float(w["current"])
	var shoal := float(w["shoal"])
	var lost := float(w["lost"])
	var mean := 1.0
	mean += calm * (0.0 - 1.0)
	mean += current * (1.5 - 1.0)
	mean += shoal * (SHOAL_PROGRESS - 1.0)
	mean += lost * (LOST_PROGRESS - 1.0)
	var rest := 1.0 - calm - current - shoal - lost
	var second := rest * 1.0 + current * 2.25 + shoal * SHOAL_PROGRESS * SHOAL_PROGRESS + lost * LOST_PROGRESS * LOST_PROGRESS
	return {"mean": mean, "variance": maxf(0.0, second - mean * mean)}


func progress_expectation(order: int, known: bool, discoveries_open: bool = true, at_month: int = -1) -> float:
	return float(progress_moments(order, known, discoveries_open, at_month).get("mean", 1.0))


## 日期往前推 n 日，不改动历法本身。每月 30 日。
func _shift_date(year: int, month: int, day: int, n: int) -> Vector3i:
	for _step in n:
		day += 1
		if day > Calendar.DAYS_PER_MONTH:
			day = 1
			month += 1
			if month > Calendar.MONTHS_PER_YEAR:
				month = 1
				year += 1
	return Vector3i(year, month, day)


## 从明日启航起逐日扣里程。航行当天先过一日，所以第一日的风不是看海图这一天的风。
## drag_days > 0 时，把每日期望进度再减去 SAFE_Z 倍标准差 / sqrt(平均日数)，用来走「八成能到」的那条偏慢路径。
func _walk_days(dist: float, course_bearing: float, order: int, known: bool, discoveries_open: bool, use_expectation: bool, drag_days: int = 0) -> Dictionary:
	var cursor := _shift_date(Calendar.year, Calendar.month, Calendar.day, 1)
	var rem := dist
	var n := 0
	var first_wf := -1.0
	var changed := false
	var drag_scale := 0.0
	if drag_days > 0:
		drag_scale = SAFE_Z / sqrt(float(drag_days))
	while rem > 0.0 and n < 900:
		var month_now := cursor.y
		var wf := wind_factor(course_bearing, month_now)
		if first_wf < 0.0:
			first_wf = wf
		elif absf(wf - first_wf) > 0.001:
			changed = true
		var gain := Fleet.fleet_speed() * wf * order_speed_mult(order)
		if use_expectation:
			var mom := progress_moments(order, known, discoveries_open, month_now)
			var ex := float(mom.get("mean", 1.0))
			if drag_scale > 0.0:
				ex = maxf(0.05, ex - drag_scale * sqrt(float(mom.get("variance", 0.0))))
			gain *= ex
		if gain <= 1.0:
			n = 999
			break
		rem -= gain
		n += 1
		cursor = _shift_date(cursor.x, cursor.y, cursor.z, 1)
	return {"days": n, "changed": changed}


## 扬帆逃走的成功率。与海图上的「扬帆逃走」、海战里弃战是同一条：
## 航速除以 220，低于二成五按二成五，高于九成按九成。保货用的是它的反面。
func flee_success_chance() -> float:
	return clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)


## 一路逃走、海盗一次都没抢到货的概率。按遇事日数逐日连乘当日的海盗权重。
## 绕路会把航程拉长，沉船和腐烂也不在这数里；界面取十分位下整，所以写「至少」。
func cargo_hold_chance(order: int, known: bool, discoveries_open: bool, days: int) -> float:
	if days <= 0 or days >= 900:
		return 0.0
	var fail := 1.0 - flee_success_chance()
	var cursor := _shift_date(Calendar.year, Calendar.month, Calendar.day, 1)
	var keep := 1.0
	for _i in days:
		var w := event_weights(order, Calendar.monsoon_strength_of(cursor.y), known, discoveries_open)
		keep *= 1.0 - float(w.get("pirate", 0.0)) * fail
		cursor = _shift_date(cursor.x, cursor.y, cursor.z, 1)
	return keep


func cargo_hold_tenths(chance: float) -> int:
	return clampi(int(floor(chance * 10.0)), 0, 10)


## 返回航程。days 是逐日静风日数，委办期限仍用它。
## expected_days 是同一条日期上的平均遇事日数。safe_days 是八成能到的日数。
## hold_tenths 是保货：十次里至少有几次整舱没被海盗抢走。日数赶得上，不代表货还在。
## 平均数卡进期限，不代表十次里有八次赶得上。月末换季时，不把今天的风套到全程。
func plan(from_id: String, to_id: String, order: int = CourseOrder.RUMB) -> Dictionary:
	var dist := distance_li(from_id, to_id)
	var brg := bearing(from_id, to_id)
	var known := is_known_route(from_id, to_id)
	var open := not _discovery_candidates(from_id, to_id).is_empty()
	var calm: Dictionary = _walk_days(dist, brg, order, known, open, false)
	var rough: Dictionary = _walk_days(dist, brg, order, known, open, true)
	var days := int(calm.get("days", 999))
	var expected := int(rough.get("days", 999))
	if days < 900 and expected < days:
		expected = days
	var safe := expected
	var safe_changed := false
	if expected > 0 and expected < 900:
		var cautious: Dictionary = _walk_days(dist, brg, order, known, open, true, expected)
		safe = int(cautious.get("days", expected))
		safe_changed = bool(cautious.get("changed", false))
		if safe < expected:
			safe = expected
	var hold := cargo_hold_chance(order, known, open, expected)
	var start := _shift_date(Calendar.year, Calendar.month, Calendar.day, 1)
	var wf := wind_factor(brg, start.y)
	var spd := Fleet.fleet_speed() * wf * order_speed_mult(order)
	var changed := bool(calm.get("changed", false)) or bool(rough.get("changed", false)) or safe_changed
	return {
		"from": from_id,
		"to": to_id,
		"order": order,
		"distance": dist,
		"bearing": brg,
		"wind_factor": wf,
		"wind_desc": wind_desc(brg, start.y),
		"speed": spd,
		"days": days,
		"expected_days": expected,
		"safe_days": safe,
		"hold_tenths": cargo_hold_tenths(hold),
		"wind_changes": changed,
		"departs_on_new_wind": absf(wind_factor(brg) - wf) > 0.001,
		"supply_days": Fleet.supply_days(),
		"supply_ok": Fleet.supply_days() >= safe,
	}


## 两港是否有已知航路。连线是无向的：图上只要有一条线，往返都是熟路。
## 不相连也可直航，但算生路，会迷航。
func is_known_route(from_id: String, to_id: String) -> bool:
	if to_id in port_def(from_id).get("connections", []):
		return true
	return from_id in port_def(to_id).get("connections", [])


# ── 逐日事件 ──────────────────────────────────────────

## 当日事件权重。针路且熟路、岸影还在时，与旧表逐项相同。
## 岸影抽空后把这一档按比例摊回其余事件，总质量不变，傍岸不会因此变快。
func event_weights(order: int, monsoon_strength: float, known: bool, discoveries_open: bool = true) -> Dictionary:
	var storm := W_STORM_BASE + W_STORM_WIND * monsoon_strength
	var pirate := W_PIRATE
	var calm := W_CALM
	var current := W_CURRENT
	var merchant := W_MERCHANT
	var discovery := W_DISCOVERY
	var shoal := 0.0
	var lost := 0.0
	if order == CourseOrder.OFFSHORE:
		storm *= OFFSHORE_STORM_MUL
		pirate *= OFFSHORE_PIRATE_MUL
		calm = OFFSHORE_CALM
		current = OFFSHORE_CURRENT
		merchant = OFFSHORE_MERCHANT
		discovery = OFFSHORE_DISCOVERY
	elif order == CourseOrder.COAST:
		storm *= COAST_STORM_MUL
		pirate *= COAST_PIRATE_MUL
		calm = COAST_CALM
		current = COAST_CURRENT
		merchant = COAST_MERCHANT
		discovery = COAST_DISCOVERY
		shoal = COAST_SHOAL
	if not known:
		if order == CourseOrder.OFFSHORE:
			lost = LOST_OFFSHORE
		elif order == CourseOrder.COAST:
			lost = LOST_COAST
		else:
			lost = LOST_RUMB
	var mass := storm + pirate + calm + current + merchant + discovery + shoal + lost
	if mass > MAX_EVENT_MASS:
		var k := MAX_EVENT_MASS / mass
		storm *= k
		pirate *= k
		calm *= k
		current *= k
		merchant *= k
		discovery *= k
		shoal *= k
		lost *= k
		mass = MAX_EVENT_MASS
	if not discoveries_open and discovery > 0.0:
		var kept := mass - discovery
		if kept > 0.0:
			var scale := mass / kept
			storm *= scale
			pirate *= scale
			calm *= scale
			current *= scale
			merchant *= scale
			shoal *= scale
			lost *= scale
		discovery = 0.0
	return {
		"storm": storm,
		"pirate": pirate,
		"calm": calm,
		"current": current,
		"merchant": merchant,
		"discovery": discovery,
		"shoal": shoal,
		"lost": lost,
	}


## 推演一日，返回事件字典 {kind, title, text, ...}
## from_id / to_id 用于发现物与生路判定；order 为当日航法。
func roll_day_event(_course_bearing: float, from_id: String = "", to_id: String = "", order: int = CourseOrder.RUMB) -> Dictionary:
	var known := true
	if from_id != "" and to_id != "":
		known = is_known_route(from_id, to_id)
	var open := not _discovery_candidates(from_id, to_id).is_empty()
	var w := event_weights(order, Calendar.get_monsoon_strength(), known, open)
	var r := randf()
	var t := 0.0
	t += float(w["storm"])
	if r < t:
		return _storm_event()
	t += float(w["pirate"])
	if r < t:
		return _pirate_event()
	t += float(w["calm"])
	if r < t:
		return _calm_event()
	t += float(w["current"])
	if r < t:
		return _current_event()
	t += float(w["merchant"])
	if r < t:
		return _merchant_event(from_id)
	t += float(w["discovery"])
	if r < t:
		return _discovery_event(from_id, to_id)
	t += float(w["shoal"])
	if r < t:
		return _shoal_event()
	t += float(w["lost"])
	if r < t:
		return _lost_event()
	return {"kind": EventKind.NONE}


func _storm_event() -> Dictionary:
	var severity := randf_range(0.3, 1.0)
	var hull_dmg := 12.0 * severity * Fleet.ships.size() * Fleet.armor_damage_reduction()
	Fleet.damage_fleet(hull_dmg)
	# 易碎货按 fragile 系数受损
	var lost := {}
	for gid in Fleet.cargo.keys().duplicate():
		var frag := 0.0
		for g in GameManager.goods_data.get("goods", []):
			if g.get("id") == gid:
				frag = float(g.get("fragile", 0.0))
				break
		if frag <= 0.0:
			continue
		var q: int = Fleet.cargo[gid]["qty"]
		# 总管分舱理货，风涛中的折损随之减轻
		var l := mini(int(ceil(q * frag * severity * 0.5 * Crew.cargo_loss_factor())), q)
		if l > 0:
			Fleet.remove_cargo(gid, l)
			lost[gid] = l
	Fleet.morale = maxi(0, Fleet.morale - int(8 * severity))

	var txt := "风起于西北，浪头一个高过一个。舵工死命抵住舵杆，桅上帆索绷得发白。"
	if not lost.is_empty():
		var parts := []
		for gid in lost.keys():
			parts.append("%s %d" % [_good_name(gid), lost[gid]])
		txt += "\n舱内货物翻倒，损折：" + "、".join(parts) + "。"
	txt += "\n船体受损 %d。" % int(hull_dmg)
	return {"kind": EventKind.STORM, "title": "风涛", "text": txt, "severity": severity}


func _calm_event() -> Dictionary:
	Fleet.morale = maxi(0, Fleet.morale - 2)
	return {
		"kind": EventKind.CALM,
		"title": "无风带",
		"text": "海面平得像一张铺开的绢。帆垂着不动，船在原处打转。水手们开始盘算舱里还剩多少水。",
		"delay": 1,
	}


func _current_event() -> Dictionary:
	return {
		"kind": EventKind.CURRENT,
		"title": "顺流",
		"text": "撞上一股南下的暖流，船身轻快了许多，舵手说这一日能多走几十里。",
		"bonus": 1,
	}


func _pirate_event() -> Dictionary:
	return {
		"kind": EventKind.PIRATE,
		"title": "不明船影",
		"text": "桅斗上的了望手忽然压低嗓子喊了一声。右舷后方跟着两条快船，不挂旗，桨手比商船多出一倍。",
	}


## 海上卖出价：围绕成本价小幅浮动，并封顶在最佳消费地卖价的九二折之下。
## 这是变现，不是第二条商路。
func sea_sell_unit(good_id: String, avg_cost: float, jitter: float) -> int:
	var raw := int(round(maxf(avg_cost, 1.0) * jitter))
	var best := _best_consumer_sell(good_id)
	if best > 0:
		var cap := int(float(best) * SEA_SELL_CAP)
		raw = mini(raw, maxi(1, cap))
	return maxi(1, raw)


## 已解锁港口里，这货现在最便宜的买价。没有在卖的港口则返回 0。
func _cheapest_port_buy(good_id: String) -> int:
	var cheapest := 0
	for p in GameManager.unlocked_ports():
		if int(p.get("depth", 0)) <= 0:
			continue
		var pid: String = p.get("id", "")
		if not Economy.is_traded(pid, good_id):
			continue
		var b := Economy.buy_price(pid, good_id)
		if b <= 0:
			continue
		if cheapest == 0 or b < cheapest:
			cheapest = b
	return cheapest


## 海上买入价：至少是「普通口岸、行情 1.0、不含职事议价」再加一成二。
## 出发港或任一已解锁港口的现价若更高，取更高的那个再加价。
## 产地低价、被砸低的行情，都不会把海上买价拉下来。
func sea_buy_unit(good_id: String, from_port: String) -> int:
	var base := float(GameManager.get_good_by_id(good_id).get("base_value", 0))
	if base <= 0.0:
		return 0
	var normal := int(round(base * (1.0 + Economy.tariff_rate)))
	var floor_p := normal
	if from_port != "" and Economy.is_traded(from_port, good_id):
		floor_p = maxi(floor_p, Economy.buy_price(from_port, good_id))
	floor_p = maxi(floor_p, _cheapest_port_buy(good_id))
	return int(ceil(float(floor_p) * SEA_BUY_MARKUP))


func _best_consumer_sell(good_id: String) -> int:
	var best := 0
	var any_sell := 0
	for p in GameManager.unlocked_ports():
		if int(p.get("depth", 0)) <= 0:
			continue
		var pid: String = p.get("id", "")
		if not Economy.is_traded(pid, good_id):
			continue
		var s := Economy.sell_price(pid, good_id)
		any_sell = maxi(any_sell, s)
		if Economy.get_role(pid, good_id) == "consumer":
			best = maxi(best, s)
	return best if best > 0 else any_sell


func _merchant_event(from_id: String) -> Dictionary:
	var rumor := _pick_rumor()
	var ev := {
		"kind": EventKind.MERCHANT,
		"title": "海上相逢",
		"offer": "rumor",
		"rumor_port": str(rumor.get("port", "")),
		"rumor_good": str(rumor.get("good", "")),
		"rumor_rate": float(rumor.get("rate", 1.0)),
	}
	var rumor_line := _rumor_sentence(rumor)
	var held: Array = Fleet.cargo.keys()
	var roll := randf()
	if roll < 0.50 and not held.is_empty():
		var gid: String = held[randi() % held.size()]
		var have := Fleet.cargo_qty(gid)
		var qty := mini(have, randi_range(1, 4))
		if qty > 0:
			var jitter := randf_range(SEA_SELL_JITTER_MIN, SEA_SELL_JITTER_MAX)
			var unit := sea_sell_unit(gid, Fleet.cargo_cost(gid), jitter)
			ev["offer"] = "sell"
			ev["good_id"] = gid
			ev["qty"] = qty
			ev["unit"] = unit
			ev["text"] = "右舷靠来一条空舱的船。对方指着你的%s，愿以每件 %d 钱收下 %d 件——比港里的好价钱差一截，银子却是当下就能到手。\n%s" % [
				GameManager.get_good_name(gid), unit, qty, rumor_line,
			]
			return ev
	elif roll < 0.82:
		var lot := _sea_buy_lot(from_id)
		if not lot.is_empty():
			ev["offer"] = "buy"
			ev["good_id"] = lot["good_id"]
			ev["qty"] = lot["qty"]
			ev["unit"] = lot["unit"]
			ev["text"] = "对方压舱的是%s，开口每件 %d 钱，肯割 %d 件。这价比普通口岸还贵，只是省得靠岸。\n%s" % [
				GameManager.get_good_name(lot["good_id"]), int(lot["unit"]), int(lot["qty"]), rumor_line,
			]
			return ev
	ev["text"] = "迎面来了一条福船，降下半帆。两船靠近，换了些淡水，没谈成买卖。\n" + rumor_line
	return ev


func _sea_buy_lot(from_id: String) -> Dictionary:
	var pool: Array = []
	for g in GameManager.goods_data.get("goods", []):
		if not g.get("tradable", false) or g.get("contraband", false):
			continue
		if float(g.get("base_value", 0)) <= 0.0 or float(g.get("bulk", 0)) <= 0.0:
			continue
		pool.append(g)
	if pool.is_empty():
		return {}
	var g: Dictionary = pool[randi() % pool.size()]
	var gid: String = g.get("id", "")
	var unit := sea_buy_unit(gid, from_id)
	if unit <= 0:
		return {}
	var qty := mini(randi_range(1, 3), Fleet.max_loadable(gid))
	if qty <= 0:
		return {}
	return {"good_id": gid, "qty": qty, "unit": unit}


func _pick_rumor() -> Dictionary:
	var sea: Array = []
	for p in GameManager.unlocked_ports():
		if int(p.get("depth", 0)) <= 0:
			continue
		sea.append(p)
	if sea.is_empty():
		return {}
	var p: Dictionary = sea[randi() % sea.size()]
	var pid: String = p.get("id", "")
	var goods: Array = Economy.goods_at(pid)
	if goods.is_empty():
		return {}
	var gid: String = str(goods[randi() % goods.size()])
	var rate := clampf(Economy.get_rate(pid, gid) * randf_range(0.92, 1.08), Economy.RATE_MIN, Economy.RATE_MAX)
	return {"port": pid, "good": gid, "rate": rate}


func _rumor_sentence(rumor: Dictionary) -> String:
	if rumor.is_empty():
		return ""
	var sell := Economy.price_at_rate(str(rumor["port"]), str(rumor["good"]), float(rumor["rate"]), false)
	return "对方说%s的%s，眼下大约能卖到 %d 钱一件。" % [
		GameManager.get_port_name(str(rumor["port"])),
		GameManager.get_good_name(str(rumor["good"])),
		sell,
	]


func _shoal_event() -> Dictionary:
	var hull := SHOAL_HULL * float(maxi(1, Fleet.ships.size())) * Fleet.armor_damage_reduction()
	Fleet.damage_fleet(hull)
	Fleet.morale = maxi(0, Fleet.morale - 3)
	return {
		"kind": EventKind.SHOAL,
		"title": "浅滩",
		"text": "傍着岸走，船底忽然擦过一片沙脊。桅上的人喊了一声，舵工把船扳开，这一日只蹭出去一截。\n船体受损 %d。" % int(hull),
		"progress_mult": SHOAL_PROGRESS,
	}


func _lost_event() -> Dictionary:
	Fleet.morale = maxi(0, Fleet.morale - 3)
	return {
		"kind": EventKind.LOST,
		"title": "迷航",
		"text": "海图上这一段是空白。火长把罗盘转了两圈，承认针位对不上岸影——这一日白走了，还退回去一截。",
		"progress_mult": LOST_PROGRESS,
	}


## 当前航段沿途可能有的、且尚未勘见的发现物。未标注海域的算通用。
func _discovery_candidates(from_id: String, to_id: String) -> Array:
	var pool := []
	for d in GameManager.discoveries_data.get("discoveries", []):
		var did: String = d.get("id", "")
		if GameState.has_found(did):
			continue
		var near: Array = d.get("near_ports", [])
		if near.is_empty() or from_id in near or to_id in near:
			pool.append(d)
	return pool


## 只抽当前航段沿途可能有的、且尚未勘见的发现物
func _discovery_event(from_id: String = "", to_id: String = "") -> Dictionary:
	var pool := _discovery_candidates(from_id, to_id)
	if pool.is_empty():
		return {"kind": EventKind.NONE}

	var d = pool[randi() % pool.size()]
	return {
		"kind": EventKind.DISCOVERY,
		"title": "岸影",
		"text": "左舷远处露出一线陆影，海图上此处应是空白。舵手眯眼看了半晌，说那多半就是老辈人讲的%s。" % d.get("name", "旧泊地"),
		"discovery_id": d.get("id", ""),
	}


func _good_name(good_id: String) -> String:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g.get("name", good_id)
	return good_id
