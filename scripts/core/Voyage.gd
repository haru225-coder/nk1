extends Node
## 航海：里程、方位、季风修正、航段推演与逐日事件。
## 航行以「日」为单位推进，每一日抽一次事件。

## 1 宋里约 576 米
const KM_PER_LI := 0.576
const EARTH_R_KM := 6371.0

## 逆风/顺风对日速的乘数区间
const WIND_MIN := 0.40
const WIND_MAX := 1.60

enum EventKind { NONE, CALM, CURRENT, STORM, PIRATE, MERCHANT, DISCOVERY }


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

## 当前季风对给定航向的日速乘数
func wind_factor(course_bearing: float) -> float:
	var wind := Calendar.get_wind_bearing()
	if wind < 0.0:
		# 转换期：无稳定季风，略微不利
		return 0.85
	var diff := absf(angle_difference(deg_to_rad(course_bearing), deg_to_rad(wind)))
	# diff=0 完全顺风；diff=PI 完全逆风
	var t := cos(diff)  # 1 → -1
	var raw := 1.0 + t * 0.6
	# 季风强度弱时向 1.0 收敛
	var strength := Calendar.get_monsoon_strength()
	raw = 1.0 + (raw - 1.0) * strength
	return clampf(raw, WIND_MIN, WIND_MAX)


func wind_desc(course_bearing: float) -> String:
	var wind := Calendar.get_wind_bearing()
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

## 返回 {distance, bearing, wind_factor, wind_desc, speed, days, supply_ok}
func plan(from_id: String, to_id: String) -> Dictionary:
	var dist := distance_li(from_id, to_id)
	var brg := bearing(from_id, to_id)
	var wf := wind_factor(brg)
	var spd := Fleet.fleet_speed() * wf
	var days := 999
	if spd > 1.0:
		days = int(ceil(dist / spd))
	return {
		"from": from_id,
		"to": to_id,
		"distance": dist,
		"bearing": brg,
		"wind_factor": wf,
		"wind_desc": wind_desc(brg),
		"speed": spd,
		"days": days,
		"supply_days": Fleet.supply_days(),
		"supply_ok": Fleet.supply_days() >= days,
	}


## 两港是否有已知航路（不相连也可直航，但有迷航风险）
func is_known_route(from_id: String, to_id: String) -> bool:
	var conns: Array = port_def(from_id).get("connections", [])
	return to_id in conns


# ── 逐日事件 ──────────────────────────────────────────

## 推演一日，返回事件字典 {kind, title, text, ...}
func roll_day_event(course_bearing: float) -> Dictionary:
	var r := randf()
	var monsoon_strength := Calendar.get_monsoon_strength()

	# 季风盛期暴风概率更高
	var storm_chance := 0.06 + 0.06 * monsoon_strength

	if r < storm_chance:
		return _storm_event()
	elif r < storm_chance + 0.06:
		return _pirate_event()
	elif r < storm_chance + 0.12:
		return _calm_event()
	elif r < storm_chance + 0.17:
		return _current_event()
	elif r < storm_chance + 0.21:
		return _merchant_event()
	elif r < storm_chance + 0.24:
		return _discovery_event()
	return {"kind": EventKind.NONE}


func _storm_event() -> Dictionary:
	var severity := randf_range(0.3, 1.0)
	var hull_dmg := 12.0 * severity * Fleet.ships.size()
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
		var l := mini(int(ceil(q * frag * severity * 0.5)), q)
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


func _merchant_event() -> Dictionary:
	var goods: Array = GameManager.goods_data.get("goods", [])
	var tradable := goods.filter(func(g): return g.get("tradable", false))
	var hint := ""
	if not tradable.is_empty():
		var g = tradable[randi() % tradable.size()]
		hint = "对方压舱的是%s，说是从北边空手回来的，那边这货价钱正好。" % g.get("name", "杂货")
	return {
		"kind": EventKind.MERCHANT,
		"title": "海上相逢",
		"text": "迎面来了一条福船，对方降下半帆示意无恶意。两船靠近后交换了些淡水与消息。\n" + hint,
	}


func _discovery_event() -> Dictionary:
	var discoveries: Array = GameManager.discoveries_data.get("discoveries", [])
	if discoveries.is_empty():
		return {"kind": EventKind.NONE}
	var d = discoveries[randi() % discoveries.size()]
	return {
		"kind": EventKind.DISCOVERY,
		"title": "岸影",
		"text": "左舷远处露出一线陆影，海图上此处应是空白。舵手说，那可能就是老辈人讲的%s。" % d.get("name", "旧泊地"),
		"discovery_id": d.get("id", ""),
	}


func _good_name(good_id: String) -> String:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g.get("name", good_id)
	return good_id
