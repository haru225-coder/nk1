## 浸水与失火（lane combat04）：DamageModel 的时间步一半，一船一份。纯逻辑，不进树、不读 autoload，-s 探针可以直接 new。
## 损管派多少人由 DamageModel 按令算好传进 step；本文件只管水怎么进、怎么出，火怎么涨、怎么灭。
##
## 浸水，按水密隔舱算（宋船实物：1974 年泉州湾出土的宋代海船十三舱十二道隔舱板）：
##   舱从艏到艉排成一列，comp 0 是头舱。water[i] 是该舱灌了几成（0–1）。水线下中弹，在某舱开一处漏 flow[i]（料/秒），
##   只灌这一舱；灌满以后舱里水面与舱外海面齐平，不再进水。隔舱板不破，水就不过舱。
##   隔舱板被打穿（breach[b]，b 是 b 舱与 b+1 舱之间那道）以后，两舱的水位才慢慢拉平。
##   总浸水 flood_frac = Σwater / 舱数。舱越多，一舱灌满占的份越小：福船（大）十三舱，一舱约 7.7%；小艍三舱，一舱就是三成三。
##   过了储备浮力就是「缓沉」：settle 按超出的量往上涨，涨满 1 就沉；甲板边缘开始上浪，各舱都跟着进水。
##   储备浮力 = 船型 reserve × (1 - RESERVE_STRAIN × strain)：船体挨得越多，船身越松，吃不住原先那么多水。
##   戽到线下，settle 慢慢退回去，船还救得回来。
##   稳性：半满的舱自由液面最伤稳性（每舱按 4w(1-w) 计），总水量又压低干舷。stability() 给的是剩余稳性。
##   list_deg() 是倾侧度数：漏在哪一舷水就偏哪一舷，加上风压横倾，再除以剩余稳性。倾过 CAPSIZE_DEG，或者稳性见底，就倾覆。
##   损管：堵漏（麻絮、桐油灰塞漏）按人头把 flow 往下压，戽水按人头把水戽出舷外。还有漏没堵住时，六成人堵、四成人戽。
##
## 失火，分四处：艏部 bow / 舯部 mid / 艉楼 stern（灶、火油、火药多放在艉）/ 篷帆 rig（竹篾席帆，最容易着）。
##   火势 fire[z] 0–1。火会自己涨（近似 logistic，风大火更旺），过了 SPREAD_AT 会烧到邻处。
##   救火的人按各处火势大小分派，把火往下压；压到 OUT_BELOW 以下算扑灭。下雨另有一份压火。
##   篷帆火大、又有人手时「斩篷」：砍断篷索，把着火的篷弃入海里。火当即灭掉，帆也去掉三成半。
##   火烧船体按船体上限的比例掉（一处满火每秒掉 0.35%），篷帆火烧帆，火场里偶有伤亡。
##   船上带火药（有炮位）时，艉楼火势 ≥ MAGAZINE_AT 持续 MAGAZINE_FUSE 秒，火药舱爆燃：
##   船体去掉四分之一，各处起火，尾舱开一处大漏、隔舱板破。伤亡由 DamageModel 按人头另算。
##
## step 返回的 events 只带 kind 与定位（comp / zone / n），中文短注由 DamageModel.event_text 统一写。
extends RefCounted

const ZONES := ["bow", "mid", "stern", "rig"]
## 火往哪里烧：桅在舯部，篷帆烧起来火星落到舯部甲板
const NEIGHBORS := {"bow": ["mid"], "mid": ["bow", "stern", "rig"], "stern": ["mid"], "rig": ["mid"]}
## 各处火势自涨速率（/秒）：艉楼有灶和火油，篷帆最快
const GROW := {"bow": 0.08, "mid": 0.09, "stern": 0.10, "rig": 0.16}
## 每名救火手每秒压下的火势（水桶、湿毡、泥浆）
const DOUSE_PER_MAN := 0.03
## 下雨每秒另压的火势
const RAIN_DOUSE := 0.06
## 火势过这条线才往邻处烧；每秒蔓延机会 = SPREAD_RATE × 火势 × 风
const SPREAD_AT := 0.45
const SPREAD_RATE := 0.05
## 刚烧过去的邻处从这点火势起
const SPREAD_SEED := 0.12
## 压到这条线以下算扑灭
const OUT_BELOW := 0.02
## 一处满火每秒烧掉船体上限的几分；篷帆火只烧三成到船体
const BURN_HULL := 0.0035
const RIG_HULL_SHARE := 0.3
## 篷帆满火每秒烧掉几分帆
const BURN_SAIL := 0.05
## 一处满火每秒伤一人的机会
const BURN_CREW := 0.03
## 篷帆火到这条线、救火手够两人，就斩篷
const CUT_SAIL_AT := 0.55
const CUT_SAIL_MEN := 2.0
const CUT_SAIL_LOSS := 0.35
## 火药舱：艉楼火势过线、持续几秒爆燃；爆燃掉船体上限的几分
const MAGAZINE_AT := 0.8
const MAGAZINE_FUSE := 6.0
const MAGAZINE_HULL := 0.25
const MAGAZINE_IGNITE := 0.5

## 每名堵漏手每秒压下的漏（料/秒²）；每名戽水手每秒戽出的水（料/秒）
const PLUG_PER_MAN := 0.2
const BAIL_PER_MAN := 0.4
## 漏压到这以下算堵住
const PLUGGED_BELOW := 0.05
## 灌满过的舱戽到这以下再灌满，才再报一次「灌满」（戽一瓢又灌回去不算）
const REFILL_BELOW := 0.9
## 破了隔舱板的相邻两舱，每秒拉平水位差的几分
const EQUALIZE := 0.25
## 船身打松（strain 0 完好 … 1 船体打光）吃不住水：储备浮力按 1 - RESERVE_STRAIN × strain 往下打
const RESERVE_STRAIN := 0.7
## 缓沉：超出储备浮力的量每秒推进 settle 的倍数；回到线下每秒退多少；过线后甲板上浪，每秒灌进（舱容 × 超出量 × AWASH）
const SETTLE_GAIN := 0.9
const SETTLE_DECAY := 0.08
const AWASH := 0.08
## 倾侧：一边偏的水每占一成总舱容，约倾 LIST_ASYM/10 度（再除以剩余稳性）；倾过 CAPSIZE_DEG 或稳性低于 STABILITY_FLOOR 即倾覆
const LIST_ASYM := 70.0
const CAPSIZE_DEG := 38.0
const STABILITY_FLOOR := 0.08
## 一舷的漏最多把该舱的水带偏几成：船里只有横向隔舱板，水会漫过整个船宽，不会全堆在一舷
const LEAK_SIDE := 0.45

var n := 8
var volume := 950.0
var reserve := 0.5
## 船身打松了几成（DamageModel 按船体余量写：1 - hull / hull_max）
var strain := 0.0
var stab := 1.1
var fire_resist := 0.0
var powder := false

## 各舱水位（0–1）、未堵的漏（料/秒）、水偏哪一舷（-LEAK_SIDE 左 … +LEAK_SIDE 右）
var water := PackedFloat64Array()
var flow := PackedFloat64Array()
var side := PackedFloat64Array()
## breach[b] == 1：b 舱与 b+1 舱之间的隔舱板已破
var breach := PackedByteArray()
var fire := {"bow": 0.0, "mid": 0.0, "stern": 0.0, "rig": 0.0}
## 缓沉进度 0–1
var settle := 0.0
var magazine_heat := 0.0
var magazine_gone := false
## "" / "flood"（灌沉）/ "capsize"（倾覆）
var foundered := ""
## 本步戽水、堵漏用上的人（观感：有人在戽水才喷水花）
var bailing_now := 0.0
var _full_told := PackedByteArray()


## compartments 舱数、p_volume 总舱容（料）、p_reserve 储备浮力、p_stability 稳性、p_fire_resist 防火（涂泥等，0–0.9）、p_powder 带不带火药
func setup(compartments: int, p_volume: float, p_reserve: float, p_stability: float, p_fire_resist := 0.0, p_powder := false) -> void:
	n = clampi(compartments, 1, 24)
	volume = maxf(50.0, p_volume)
	reserve = clampf(p_reserve, 0.1, 0.9)
	stab = maxf(0.2, p_stability)
	fire_resist = clampf(p_fire_resist, 0.0, 0.9)
	powder = p_powder
	water = PackedFloat64Array()
	water.resize(n)
	water.fill(0.0)
	flow = PackedFloat64Array()
	flow.resize(n)
	flow.fill(0.0)
	side = PackedFloat64Array()
	side.resize(n)
	side.fill(0.0)
	breach = PackedByteArray()
	breach.resize(maxi(0, n - 1))
	breach.fill(0)
	_full_told = PackedByteArray()
	_full_told.resize(n)
	_full_told.fill(0)
	for z in ZONES:
		fire[z] = 0.0
	strain = 0.0
	settle = 0.0
	magazine_heat = 0.0
	magazine_gone = false
	foundered = ""
	bailing_now = 0.0


func comp_volume() -> float:
	return volume / float(n)


## 舱名：头舱、二舱 … 尾舱；只有一舱的小船就叫「舱」
func comp_name(i: int) -> String:
	if n <= 1:
		return "舱"
	if i <= 0:
		return "头舱"
	if i >= n - 1:
		return "尾舱"
	return "%s舱" % cn_num(i + 1)


static func cn_num(v: int) -> String:
	var digits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	if v < 0:
		return str(v)
	if v < 10:
		return digits[v]
	if v < 20:
		return "十" + ("" if v == 10 else digits[v - 10])
	if v < 100:
		return digits[int(v / 10.0)] + "十" + ("" if v % 10 == 0 else digits[v % 10])
	return str(v)


## 舱在船的哪一段：前三分之一 bow、中 mid、后 stern
func comp_zone(i: int) -> String:
	var t := (float(i) + 0.5) / float(n)
	if t < 1.0 / 3.0:
		return "bow"
	if t > 2.0 / 3.0:
		return "stern"
	return "mid"


## 某一段（bow / mid / stern）有哪些舱；舱少时某段可能没有自己的舱，就给离它最近的那舱
func zone_comps(zone: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in n:
		if comp_zone(i) == zone:
			out.append(i)
	if out.is_empty():
		if zone == "bow":
			out.append(0)
		elif zone == "stern":
			out.append(n - 1)
		else:
			out.append(int(n / 2.0))
	return out


## i 舱开一处漏，rate 料/秒，hit_side -1 左舷 / 1 右舷 / 0 不偏。水偏哪一舷按水量与新漏的量加权。
func add_leak(i: int, rate: float, hit_side: int) -> void:
	if i < 0 or i >= n or rate <= 0.0:
		return
	var old_w := water[i] * comp_volume() + flow[i] * 10.0
	var new_w := rate * 10.0
	side[i] = clampf((side[i] * old_w + float(signi(hit_side)) * LEAK_SIDE * new_w) / (old_w + new_w), -LEAK_SIDE, LEAK_SIDE)
	flow[i] += rate
	if water[i] < REFILL_BELOW:
		_full_told[i] = 0


## 打穿 i 舱朝 dir（1 往艉 / -1 往艏）那道隔舱板。已破、或那边没有舱，返回 false。
func breach_bulkhead(i: int, dir: int) -> bool:
	var b := i if dir > 0 else i - 1
	if b < 0 or b >= breach.size() or breach[b] == 1:
		return false
	breach[b] = 1
	return true


## i 舱两侧的隔舱板都还完好
func sealed(i: int) -> bool:
	var fore_ok := i <= 0 or breach[i - 1] == 0
	var aft_ok := i >= n - 1 or breach[i] == 0
	return fore_ok and aft_ok


## zone 起火（或火上加火）。防火（涂泥）按比例减点火势。原先没火、点着了，返回 true。
func ignite(zone: String, intensity: float) -> bool:
	if not fire.has(zone) or intensity <= 0.0:
		return false
	var was: float = fire[zone]
	fire[zone] = clampf(was + intensity * (1.0 - fire_resist), 0.0, 1.0)
	return was < OUT_BELOW and float(fire[zone]) >= OUT_BELOW


func zone_fire(zone: String) -> float:
	return float(fire.get(zone, 0.0))


func fire_total() -> float:
	var t := 0.0
	for z in ZONES:
		t += float(fire[z])
	return t


## 正在烧的几处（按 ZONES 顺序）
func burning() -> PackedStringArray:
	var out := PackedStringArray()
	for z in ZONES:
		if float(fire[z]) >= OUT_BELOW:
			out.append(z)
	return out


## 此刻的储备浮力：船身打松了就吃不住原先那么多水
func reserve_now() -> float:
	return reserve * (1.0 - RESERVE_STRAIN * clampf(strain, 0.0, 1.0))


func flood_frac() -> float:
	var t := 0.0
	for i in n:
		t += water[i]
	return t / float(n)


## 舱里现有的水（料）
func water_volume() -> float:
	return flood_frac() * volume


## 自由液面：半满的舱最伤稳性。所有舱都半满时为 1。
func free_surface() -> float:
	var t := 0.0
	for i in n:
		t += 4.0 * water[i] * (1.0 - water[i])
	return t / float(n)


## 水偏一舷的量（-1 左 … 1 右，按总舱容计）
func asym() -> float:
	var t := 0.0
	for i in n:
		t += water[i] * side[i]
	return t / float(n)


func open_flow() -> float:
	var t := 0.0
	for i in n:
		t += flow[i]
	return t


func open_leaks() -> int:
	var c := 0
	for i in n:
		if flow[i] > 0.0:
			c += 1
	return c


## 进了水的舱数（过半成才算）
func flooded_comps() -> int:
	var c := 0
	for i in n:
		if water[i] >= 0.05:
			c += 1
	return c


func breached_bulkheads() -> int:
	var c := 0
	for b in breach.size():
		if breach[b] == 1:
			c += 1
	return c


## 剩余稳性（完好时就是船型稳性，自由液面与总水量把它往下压；≤ STABILITY_FLOOR 即倾覆）
func stability() -> float:
	return maxf(0.0, stab * (1.0 - 0.5 * free_surface() - 0.5 * flood_frac()))


## 倾侧度数（右倾为正）。wind_heel 是风压横倾（度），同样除以剩余稳性：船灌了水，风一压倾得更凶。
func list_deg(wind_heel := 0.0) -> float:
	return (asym() * LIST_ASYM + wind_heel) / maxf(stability(), STABILITY_FLOOR)


## 推进一步。flood_crew / fire_crew 是本步分到戽水堵漏、救火的人数。env 可带 wind（风力，80 是常风）、rain（bool）。
## wind_heel 是风压横倾（度）。返回：hull_burn（船体上限的几分，调用方乘上限落账）、sail_burn（帆去几分）、
## crew_burn（火场伤亡人数）、blast（本步爆燃）、cut_sail（本步斩篷）、founder（"" / "flood" / "capsize"）、events。
func step(delta: float, flood_crew: int, fire_crew: int, env: Dictionary, rng: RandomNumberGenerator, wind_heel := 0.0) -> Dictionary:
	var out := {"hull_burn": 0.0, "sail_burn": 0.0, "crew_burn": 0, "blast": false, "cut_sail": false,
		"founder": "", "events": []}
	if foundered != "" or delta <= 0.0:
		out["founder"] = foundered
		return out
	_step_fire(delta, maxi(0, fire_crew), env, rng, out)
	_step_flood(delta, maxi(0, flood_crew), out)
	var f := flood_frac()
	var res := reserve_now()
	if f > res:
		if settle <= 0.0:
			(out["events"] as Array).append({"kind": "settling"})
		settle = minf(1.0, settle + (f - res + 0.02) * SETTLE_GAIN * delta)
	elif settle > 0.0:
		settle = maxf(0.0, settle - SETTLE_DECAY * delta)
		if settle <= 0.0:
			(out["events"] as Array).append({"kind": "settle_stop"})
	if absf(list_deg(wind_heel)) >= CAPSIZE_DEG or stability() <= STABILITY_FLOOR:
		foundered = "capsize"
	elif settle >= 1.0 or f >= 0.98:
		foundered = "flood"
	out["founder"] = foundered
	return out


func _step_fire(delta: float, fire_crew: int, env: Dictionary, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var events: Array = out["events"]
	var total := fire_total()
	if total <= 0.0:
		magazine_heat = maxf(0.0, magazine_heat - delta)
		return
	var wind_k := clampf(0.7 + 0.3 * float(env.get("wind", 80.0)) / 80.0, 0.5, 1.6)
	var rain := bool(env.get("rain", false))
	# 救火手按火势大小分派到各处
	var men := {}
	for z in ZONES:
		men[z] = float(fire_crew) * float(fire[z]) / total
	# 斩篷：砍断篷索，着火的篷弃入海
	if float(fire["rig"]) >= CUT_SAIL_AT and float(men["rig"]) >= CUT_SAIL_MEN:
		fire["rig"] = 0.0
		out["sail_burn"] = float(out["sail_burn"]) + CUT_SAIL_LOSS
		out["cut_sail"] = true
		events.append({"kind": "sail_cut", "zone": "rig"})
	for z in ZONES:
		var i: float = fire[z]
		if i <= 0.0:
			continue
		var grow: float = float(GROW[z]) * (1.0 - fire_resist) * wind_k * i * (1.15 - i)
		var douse: float = DOUSE_PER_MAN * float(men[z]) + (RAIN_DOUSE if rain else 0.0)
		i = clampf(i + (grow - douse) * delta, 0.0, 1.0)
		if i < OUT_BELOW:
			i = 0.0
			events.append({"kind": "fire_out", "zone": z})
		fire[z] = i
		var hull_share := RIG_HULL_SHARE if z == "rig" else 1.0
		out["hull_burn"] = float(out["hull_burn"]) + BURN_HULL * hull_share * i * delta
		if z == "rig":
			out["sail_burn"] = float(out["sail_burn"]) + BURN_SAIL * i * delta
		if i > 0.0 and rng.randf() < BURN_CREW * i * delta:
			out["crew_burn"] = int(out["crew_burn"]) + 1
	# 蔓延：先照本步开头的火势定下烧到哪，再一起点，免得同一步里一路烧穿
	var catch := PackedStringArray()
	for z in ZONES:
		var i: float = fire[z]
		if i < SPREAD_AT:
			continue
		for nb in NEIGHBORS[z]:
			if float(fire[nb]) >= OUT_BELOW or catch.has(nb):
				continue
			if rng.randf() < SPREAD_RATE * i * wind_k * delta:
				catch.append(nb)
	for nb in catch:
		fire[nb] = SPREAD_SEED * (1.0 - fire_resist)
		events.append({"kind": "fire_spread", "zone": nb})
	# 火药舱
	if powder and not magazine_gone:
		if float(fire["stern"]) >= MAGAZINE_AT:
			magazine_heat += delta
		else:
			magazine_heat = maxf(0.0, magazine_heat - 0.5 * delta)
		if magazine_heat >= MAGAZINE_FUSE:
			magazine_gone = true
			magazine_heat = 0.0
			out["blast"] = true
			out["hull_burn"] = float(out["hull_burn"]) + MAGAZINE_HULL
			for z in ZONES:
				fire[z] = maxf(float(fire[z]), MAGAZINE_IGNITE * (1.0 - fire_resist))
			add_leak(n - 1, comp_volume() * 0.06, 0)
			breach_bulkhead(n - 1, -1)
			events.append({"kind": "magazine", "zone": "stern", "comp": n - 1})


func _step_flood(delta: float, flood_crew: int, out: Dictionary) -> void:
	var events: Array = out["events"]
	var cv := comp_volume()
	var awash := maxf(0.0, flood_frac() - reserve_now()) * AWASH * cv
	# 进水：灌满就与海面齐平，不再进
	for i in n:
		var inflow := flow[i] + awash
		if inflow <= 0.0 or water[i] >= 1.0:
			continue
		water[i] = minf(1.0, water[i] + inflow * delta / cv)
		if water[i] >= 1.0 and _full_told[i] == 0:
			_full_told[i] = 1
			events.append({"kind": "compartment_full", "comp": i, "sealed": sealed(i)})
	# 破了隔舱板的相邻两舱，水位往平里走
	for b in breach.size():
		if breach[b] == 0:
			continue
		var d := (water[b] - water[b + 1]) * minf(1.0, EQUALIZE * delta)
		water[b] -= d
		water[b + 1] += d
	# 损管：有漏先堵（六成人），其余戽水
	bailing_now = 0.0
	if flood_crew <= 0:
		return
	var leaks := open_leaks()
	var pluggers := float(flood_crew) * (0.6 if leaks > 0 else 0.0)
	var bailers := float(flood_crew) - pluggers
	if pluggers > 0.0:
		var cap := pluggers * PLUG_PER_MAN * delta
		# 先堵最大的漏
		while cap > 0.0:
			var worst := -1
			for i in n:
				if flow[i] > 0.0 and (worst < 0 or flow[i] > flow[worst]):
					worst = i
			if worst < 0:
				break
			var take := minf(cap, flow[worst])
			flow[worst] -= take
			cap -= take
			if flow[worst] < PLUGGED_BELOW:
				flow[worst] = 0.0
				events.append({"kind": "leak_stopped", "comp": worst})
	if bailers > 0.0 and flood_frac() > 0.0:
		bailing_now = bailers
		var cap_b := bailers * BAIL_PER_MAN * delta
		# 先戽已经堵住的舱（漏还开着，戽了又进），同类里水多的先戽
		while cap_b > 1e-6:
			var pick := -1
			for i in n:
				if water[i] <= 0.0:
					continue
				if pick < 0:
					pick = i
					continue
				var a_open := flow[i] > 0.0
				var p_open := flow[pick] > 0.0
				if (p_open and not a_open) or (a_open == p_open and water[i] > water[pick]):
					pick = i
			if pick < 0:
				break
			var take_w := minf(cap_b, water[pick] * cv)
			water[pick] -= take_w / cv
			if water[pick] < 1e-4:
				water[pick] = 0.0
			cap_b -= take_w
			if water[pick] < REFILL_BELOW:
				_full_told[pick] = 0
