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
## 有绕岸折线时，船沿折线走，里程是各段大圆之和。
## 没有折线（开阔洋面、兴化陆路）时仍是两港大圆。
## 每一段的风向用恒向线方位：海图是墨卡托，船在一段上保持罗经航向。

func _haversine_li(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var rlat1 := deg_to_rad(lat1)
	var rlat2 := deg_to_rad(lat2)
	var dlat := rlat2 - rlat1
	var dlon := deg_to_rad(lon2 - lon1)
	var h := sin(dlat / 2.0) * sin(dlat / 2.0) + cos(rlat1) * cos(rlat2) * sin(dlon / 2.0) * sin(dlon / 2.0)
	var c := 2.0 * atan2(sqrt(h), sqrt(maxf(0.0, 1.0 - h)))
	return (EARTH_R_KM * c) / KM_PER_LI


## 恒向线方位（度，0=正北 顺时针）
func _rhumb_bearing(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var phi1 := deg_to_rad(lat1)
	var phi2 := deg_to_rad(lat2)
	var dlon := deg_to_rad(lon2 - lon1)
	dlon = fposmod(dlon + PI, TAU) - PI
	var dpsi := log(tan(PI * 0.25 + phi2 * 0.5)) - log(tan(PI * 0.25 + phi1 * 0.5))
	if absf(dpsi) < 0.0000001 and absf(dlon) < 0.0000001:
		return 0.0
	return fposmod(rad_to_deg(atan2(dlon, dpsi)), 360.0)


## [[lon, lat], ...] 含两端港口。折线 key 按港口 id 字母序，方向从 from 到 to。
func track_lonlat(from_id: String, to_id: String) -> Array:
	var a := port_def(from_id)
	var b := port_def(to_id)
	var pts: Array = []
	if a.is_empty() or b.is_empty():
		return pts
	pts.append([float(a.get("lon", 0.0)), float(a.get("lat", 0.0))])
	var lo := from_id
	var hi := to_id
	var reverse := false
	if hi < lo:
		lo = to_id
		hi = from_id
		reverse = true
	var lanes: Dictionary = GameManager.sealanes_data.get("lanes", {})
	var lane: Array = lanes.get("%s|%s" % [lo, hi], [])
	if reverse:
		lane = lane.duplicate()
		lane.reverse()
	for w in lane:
		pts.append([float(w[0]), float(w[1])])
	pts.append([float(b.get("lon", 0.0)), float(b.get("lat", 0.0))])
	return pts


func distance_li(from_id: String, to_id: String) -> float:
	var pts := track_lonlat(from_id, to_id)
	if pts.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(pts.size() - 1):
		total += _haversine_li(float(pts[i][0]), float(pts[i][1]), float(pts[i + 1][0]), float(pts[i + 1][1]))
	return total


## 出发时的方位：第一段恒向线。开阔洋面只有一段，就是整段航向。
func bearing(from_id: String, to_id: String) -> float:
	return bearing_at(from_id, to_id, 0.0)


## 已航行 traveled_li 里时所在那一段的恒向线方位
func bearing_at(from_id: String, to_id: String, traveled_li: float) -> float:
	var pts := track_lonlat(from_id, to_id)
	if pts.size() < 2:
		return 0.0
	var walked := 0.0
	var last := 0.0
	for i in range(pts.size() - 1):
		var lon1 := float(pts[i][0])
		var lat1 := float(pts[i][1])
		var lon2 := float(pts[i + 1][0])
		var lat2 := float(pts[i + 1][1])
		var seg := _haversine_li(lon1, lat1, lon2, lat2)
		if seg < 0.05:
			continue
		last = _rhumb_bearing(lon1, lat1, lon2, lat2)
		if traveled_li <= walked + seg:
			return last
		walked += seg
	return last


## 沿航迹走到 traveled_li 里的经纬度（段内按恒向线线性内插）
func point_along_track(from_id: String, to_id: String, traveled_li: float) -> Dictionary:
	var pts := track_lonlat(from_id, to_id)
	if pts.is_empty():
		return {"lon": 0.0, "lat": 0.0}
	if traveled_li <= 0.0 or pts.size() == 1:
		return {"lon": float(pts[0][0]), "lat": float(pts[0][1])}
	var walked := 0.0
	for i in range(pts.size() - 1):
		var lon1 := float(pts[i][0])
		var lat1 := float(pts[i][1])
		var lon2 := float(pts[i + 1][0])
		var lat2 := float(pts[i + 1][1])
		var seg := _haversine_li(lon1, lat1, lon2, lat2)
		if seg < 0.001:
			continue
		if traveled_li <= walked + seg or i == pts.size() - 2:
			var t := clampf((traveled_li - walked) / seg, 0.0, 1.0)
			return {"lon": lon1 + (lon2 - lon1) * t, "lat": lat1 + (lat2 - lat1) * t}
		walked += seg
	return {"lon": float(pts[pts.size() - 1][0]), "lat": float(pts[pts.size() - 1][1])}


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
	# 舵工抢风，抬高逆风时的下限
	return clampf(raw, Crew.wind_floor(), WIND_MAX)


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
## 方位与风信取第一段（出港时的罗经）。天数按每一段各自的风向累加。
func plan(from_id: String, to_id: String) -> Dictionary:
	var pts := track_lonlat(from_id, to_id)
	var dist := 0.0
	var days_f := 0.0
	var brg := 0.0
	var wf := 1.0
	var have := false
	var fleet := Fleet.fleet_speed()
	for i in range(max(0, pts.size() - 1)):
		var lon1 := float(pts[i][0])
		var lat1 := float(pts[i][1])
		var lon2 := float(pts[i + 1][0])
		var lat2 := float(pts[i + 1][1])
		var seg := _haversine_li(lon1, lat1, lon2, lat2)
		if seg < 0.05:
			continue
		var seg_brg := _rhumb_bearing(lon1, lat1, lon2, lat2)
		if not have:
			brg = seg_brg
			wf = wind_factor(brg)
			have = true
		dist += seg
		var seg_spd := fleet * wind_factor(seg_brg)
		if seg_spd > 1.0:
			days_f += seg / seg_spd
		else:
			days_f = 999.0
			break
	var days := 999
	if days_f < 900.0:
		days = int(ceil(days_f))
	var spd := fleet * wf
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
## from_id / to_id 用于把发现物限定在本航段沿途
func roll_day_event(course_bearing: float, from_id: String = "", to_id: String = "") -> Dictionary:
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
		return _discovery_event(from_id, to_id)
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


## 只抽当前航段沿途可能有的、且尚未勘见的发现物
func _discovery_event(from_id: String = "", to_id: String = "") -> Dictionary:
	var pool := []
	for d in GameManager.discoveries_data.get("discoveries", []):
		var did: String = d.get("id", "")
		if GameState.has_found(did):
			continue
		var near: Array = d.get("near_ports", [])
		# 未标注海域的算通用；标注了则须与本航段两端有交集
		if near.is_empty() or from_id in near or to_id in near:
			pool.append(d)
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
