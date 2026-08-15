extends Node
## 舰队：船只、舱位、货物、补给、士气。
## 货分船、补给全队——每条船独立货舱，水/粮仍全队共用占全队总舱。

## 每条船：{type, name, durability, max_durability, crew, sail_level, armor_level, cargo}
## 其中 cargo 为该船独立货舱：{good_id: {"qty": int, "avg_cost": float}}
var ships: Array = []

## 全队货舱的只读聚合视图（遍历各船 cargo 合并）。
## 数据源在 ships[i]["cargo"]；本属性供存量读取调用点零改动使用，禁止赋值。
var cargo: Dictionary:
	get:
		var agg := {}
		for s in ships:
			var sc: Dictionary = s.get("cargo", {})
			for gid in sc:
				var e: Dictionary = sc[gid]
				var q: int = e.get("qty", 0)
				if q <= 0:
					continue
				if agg.has(gid):
					var a: Dictionary = agg[gid]
					var old_q: int = a["qty"]
					var new_q: int = old_q + q
					a["avg_cost"] = (a["avg_cost"] * old_q + float(e.get("avg_cost", 0.0)) * q) / float(new_q)
					a["qty"] = new_q
				else:
					agg[gid] = {"qty": q, "avg_cost": float(e.get("avg_cost", 0.0))}
		return agg

## 补给（各占舱位 1.0/单位）
var water: int = 0
var food: int = 0

## 士气 0-100
var morale: int = 70

## 是否在海上。停泊港内时水手上岸就食，不吃船上存粮——否则在港候风会把全船饿死。
var at_sea: bool = false

const MORALE_MAX := 100
## 一份水或粮所占舱位。压得太重会让远洋在数学上不可能——半舱补给必须够跑一趟博多。
const SUPPLY_BULK := 0.25
## 一份水/粮可供几人日。设为 1 时补给开销会吞掉近海跑商的全部利润，形成衰竭螺旋。
const CREW_DAYS_PER_SUPPLY := 2.0

## 改装上限。sail 满级航速 ×1.24，再高会架空季风候风；甲满级船体伤 ×0.80，风涛仍要命。
const SAIL_LEVEL_MAX := 3
const ARMOR_LEVEL_MAX := 3
## 升级成本 = ceil(船价 × 本比例 × 级数递增系数 × (甲则 ×1.25))，与每级 10% 加成同量级
const UPGRADE_BASE_RATIO := 0.10


## 当前船员每日消耗的水（或粮）份数
func daily_supply_use() -> int:
	return int(ceil(float(total_crew()) / CREW_DAYS_PER_SUPPLY))


func _ready() -> void:
	if ships.is_empty():
		_grant_starter_ship()


func _grant_starter_ship() -> void:
	add_ship("sampan", "无名小艍")
	water = 60
	food = 60


# ── 船种数据 ──────────────────────────────────────────

func ship_def(type_id: String) -> Dictionary:
	for s in GameManager.ships_data.get("ships", []):
		if s.get("id") == type_id:
			return s
	return {}


func add_ship(type_id: String, ship_name: String = "") -> bool:
	var d := ship_def(type_id)
	if d.is_empty():
		return false
	ships.append({
		"type": type_id,
		"name": ship_name if ship_name != "" else d.get("name", "海船"),
		"durability": float(d.get("durability", 100)),
		"max_durability": float(d.get("durability", 100)),
		"crew": int(d.get("crew_min", 5)),
		"sail_level": 1,
		"armor_level": 1,
		"cargo": {},
	})
	return true


func flagship() -> Dictionary:
	return ships[0] if not ships.is_empty() else {}


# ── 载重 ──────────────────────────────────────────────

func total_capacity() -> float:
	var cap := 0.0
	for s in ships:
		cap += float(ship_def(s.get("type", "")).get("capacity", 0))
	return cap


func ship_capacity(i: int) -> float:
	if i < 0 or i >= ships.size():
		return 0.0
	return float(ship_def(ships[i].get("type", "")).get("capacity", 0))


## 单船货物占用（料）
func ship_cargo_bulk(i: int) -> float:
	if i < 0 or i >= ships.size():
		return 0.0
	var used := 0.0
	var sc: Dictionary = ships[i].get("cargo", {})
	for gid in sc:
		used += float(sc[gid].get("qty", 0)) * _bulk(gid)
	return used


func used_capacity() -> float:
	var used := float(water + food) * SUPPLY_BULK
	for i in range(ships.size()):
		used += ship_cargo_bulk(i)
	return used


func free_capacity() -> float:
	return maxf(0.0, total_capacity() - used_capacity())


## 单船空舱（料）。水粮是全队池，按该船载重占全队比例分摊，
## 保证 Σ_i ship_free_capacity(i) == free_capacity() 恒成立——否则每船塞满货
## 会让 used_capacity() 越过 total_capacity()，账目溢出。
func ship_free_capacity(i: int) -> float:
	if i < 0 or i >= ships.size():
		return 0.0
	var tc := total_capacity()
	var wf := float(water + food) * SUPPLY_BULK
	var share := 0.0
	if tc > 0.0:
		share = wf * (ship_capacity(i) / tc)
	else:
		share = wf / float(ships.size())
	return maxf(0.0, ship_capacity(i) - ship_cargo_bulk(i) - share)


func _bulk(good_id: String) -> float:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return float(g.get("bulk", 1.0))
	return 1.0


## 以指定船（或全队）空舱还能装多少单位此货
## ship_index >= 0：查该船空舱；== -1：查全队空舱（旧语义）
func max_loadable(good_id: String, ship_index: int = -1) -> int:
	var b := _bulk(good_id)
	if b <= 0.0:
		return 9999
	var space := ship_free_capacity(ship_index) if ship_index >= 0 else free_capacity()
	return int(floor(space / b))


# ── 货物 ──────────────────────────────────────────────

## 返回船 dict 的 cargo 字典（数据源）。越界返回空字典。
func _ship_cargo(ship_index: int) -> Dictionary:
	if ship_index < 0 or ship_index >= ships.size():
		return {}
	var s: Dictionary = ships[ship_index]
	if not s.has("cargo") or not (s["cargo"] is Dictionary):
		s["cargo"] = {}
	return s["cargo"]


## 第一艘还有空舱能装下 qty 单位此货的船；没有则返回 -1
func _first_ship_with_room(good_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var need := float(qty) * _bulk(good_id)
	for i in range(ships.size()):
		if ship_free_capacity(i) >= need - 0.001:
			return i
	return -1


## 装入指定船（ship_index >= 0）或自动挑第一艘有空舱的船（== -1）。
## 都装不下返回 false。
func add_cargo(good_id: String, qty: int, unit_cost: float, ship_index: int = -1) -> bool:
	if qty <= 0:
		return false
	var idx := ship_index
	if idx < 0:
		idx = _first_ship_with_room(good_id, qty)
		if idx < 0:
			return false
	if float(qty) * _bulk(good_id) > ship_free_capacity(idx) + 0.001:
		return false
	var sc: Dictionary = _ship_cargo(idx)
	if sc.has(good_id):
		var e: Dictionary = sc[good_id]
		var old_qty: int = e["qty"]
		var old_cost: float = e["avg_cost"]
		var new_qty := old_qty + qty
		e["avg_cost"] = (old_cost * old_qty + unit_cost * qty) / float(new_qty)
		e["qty"] = new_qty
	else:
		sc[good_id] = {"qty": qty, "avg_cost": unit_cost}
	return true


## 从指定船扣（ship_index >= 0），或跨船依次扣减（== -1）。总量不足返回 false。
func remove_cargo(good_id: String, qty: int, ship_index: int = -1) -> bool:
	if qty <= 0:
		return false
	if ship_index >= 0:
		var sc := _ship_cargo(ship_index)
		if not sc.has(good_id):
			return false
		var e: Dictionary = sc[good_id]
		if e["qty"] < qty:
			return false
		e["qty"] -= qty
		if e["qty"] <= 0:
			sc.erase(good_id)
		return true
	# 跨船依次扣
	if cargo_qty(good_id) < qty:
		return false
	var left := qty
	for i in range(ships.size()):
		if left <= 0:
			break
		var sc := _ship_cargo(i)
		if not sc.has(good_id):
			continue
		var e: Dictionary = sc[good_id]
		var take: int = mini(left, e["qty"])
		e["qty"] -= take
		left -= take
		if e["qty"] <= 0:
			sc.erase(good_id)
	return true


## 指定船（ship_index >= 0）或全队（== -1）此货数量
func cargo_qty(good_id: String, ship_index: int = -1) -> int:
	if ship_index >= 0:
		return _ship_cargo(ship_index).get(good_id, {}).get("qty", 0)
	var n := 0
	for i in range(ships.size()):
		n += _ship_cargo(i).get(good_id, {}).get("qty", 0)
	return n


## 指定船（ship_index >= 0）或全队（== -1）此货按数量加权的均价
func cargo_cost(good_id: String, ship_index: int = -1) -> float:
	if ship_index >= 0:
		return _ship_cargo(ship_index).get(good_id, {}).get("avg_cost", 0.0)
	var total_q := 0
	var weighted := 0.0
	for i in range(ships.size()):
		var e: Dictionary = _ship_cargo(i).get(good_id, {})
		var q: int = e.get("qty", 0)
		if q <= 0:
			continue
		total_q += q
		weighted += float(e.get("avg_cost", 0.0)) * float(q)
	if total_q <= 0:
		return 0.0
	return weighted / float(total_q)


## 随机丢弃一定比例货物（暴风、中弹、查扣）。遍历各船，返回 {gid: 全队损失合计}
func lose_cargo_ratio(ratio: float) -> Dictionary:
	var lost := {}
	for i in range(ships.size()):
		var sc: Dictionary = _ship_cargo(i)
		for gid in sc.keys().duplicate():
			var q: int = sc[gid]["qty"]
			var l := mini(int(ceil(q * ratio)), q)
			if l > 0:
				remove_cargo(gid, l, i)
				lost[gid] = lost.get(gid, 0) + l
	return lost


func clear_cargo() -> void:
	for i in range(ships.size()):
		_ship_cargo(i).clear()


# ── 船员与补给 ────────────────────────────────────────

func total_crew() -> int:
	var c := 0
	for i in range(ships.size()):
		c += ship_crew(i)
	return c


func crew_min_required() -> int:
	var m := 0
	for i in range(ships.size()):
		m += ship_crew_min(i)
	return m


func crew_max() -> int:
	var m := 0
	for i in range(ships.size()):
		m += ship_crew_max(i)
	return m


# ── 分船水手 ──────────────────────────────────────────

## 指定船现有水手（越界返回 0）
func ship_crew(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return int(ships[i].get("crew", 0))


## 指定船最低水手（低于此数无法出海）
func ship_crew_min(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return int(ship_def(ships[i].get("type", "")).get("crew_min", 0))


## 指定船满编水手
func ship_crew_max(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return int(ship_def(ships[i].get("type", "")).get("crew_max", 0))


## 指定船还可雇几人（crew_max - 现有，负数钳 0）
func ship_crew_room(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return maxi(0, ship_crew_max(i) - ship_crew(i))


## 全队距离「各船 crew_min」还缺多少人（已达/超标计 0）
func crew_to_min_needed() -> int:
	var need := 0
	for i in range(ships.size()):
		need += maxi(0, ship_crew_min(i) - ship_crew(i))
	return need


## 把每艘低于 crew_min 的船补到 crew_min。返回补入人数。费用由调用方计算。
func hire_to_min() -> int:
	var total := 0
	for i in range(ships.size()):
		var need := ship_crew_min(i) - ship_crew(i)
		if need > 0:
			ships[i]["crew"] = ship_crew(i) + need
			total += need
	return total


## 缺员船列表：[{index, name, crew, crew_min}, ...]，供出海拦截提示
func crew_shortfall() -> Array:
	var bad := []
	for i in range(ships.size()):
		if ship_crew(i) < ship_crew_min(i):
			bad.append({
				"index": i,
				"name": ships[i].get("name", ""),
				"crew": ship_crew(i),
				"crew_min": ship_crew_min(i),
			})
	return bad


## 每船都必须达到各自 crew_min 才能出海（不能全队够数但某船空船）
func can_sail() -> bool:
	if ships.is_empty():
		return false
	for i in range(ships.size()):
		if ship_crew(i) < ship_crew_min(i):
			return false
	return true


## 雇水手。ship_index >= 0：只雇进指定船（上限该船 crew_max）；
## == -1：按数组顺序逐船填满（旧聚合语义）。返回实际雇到人数。
func hire_crew(n: int, ship_index: int = -1) -> int:
	if n <= 0:
		return 0
	if ship_index >= 0:
		if ship_index >= ships.size():
			return 0
		var take := mini(n, ship_crew_room(ship_index))
		if take > 0:
			ships[ship_index]["crew"] = ship_crew(ship_index) + take
		return take
	# 聚合：逐船填满
	var actual := mini(n, crew_max() - total_crew())
	var left := actual
	for i in range(ships.size()):
		if left <= 0:
			break
		var take := mini(left, ship_crew_room(i))
		ships[i]["crew"] = ship_crew(i) + take
		left -= take
	return actual


## 按当前船员数，现有补给还够几日
func supply_days() -> int:
	if total_crew() <= 0:
		return 999
	var per_day := daily_supply_use()
	if per_day <= 0:
		return 999
	return int(floor(minf(float(water), float(food)) / float(per_day)))


## 每日结算：消耗水粮、货物损耗、士气变动
func on_day_passed() -> void:
	var crew := total_crew()
	if crew <= 0:
		return

	if not at_sea:
		# 泊港期间水手上岸，船上水粮不动；士气缓慢回升
		if morale < 75:
			morale = mini(MORALE_MAX, morale + 1 + Crew.morale_bonus())
		_apply_perishable()
		return

	var use := daily_supply_use()
	water = maxi(0, water - use)
	food = maxi(0, food - use)

	var starving := water <= 0 or food <= 0
	if starving:
		morale = maxi(0, morale - 6)
		# 断水断粮开始死人；医人能压住一部分
		if randf() < 0.4 * Crew.crew_loss_factor():
			_lose_crew(maxi(1, int(crew * 0.03)))
	else:
		if morale < 70:
			morale = mini(MORALE_MAX, morale + 1 + Crew.morale_bonus())

	_apply_perishable()


## 断粮减员跨船分摊：每船至少留 1 人（保留火种），与 simulate_run.lose_crew 一致。
## 否则一艘船被扣到 0 人会永久卡死该船出海。
func _lose_crew(n: int) -> void:
	var left := n
	for s in ships:
		if left <= 0:
			break
		var c := int(s.get("crew", 0))
		if c > 1:
			var take := mini(left, c - 1)
			s["crew"] = c - take
			left -= take
		# c <= 1：不扣（至少留 1 人）


## 白刃战等随机减员：跨船摊扣（每船至少留 1 人保火种），返回实际死亡数。
## 与 _lose_crew 同口径，但由战斗场景显式调用（不再走 randf 概率）。
func lose_crew_random(n: int) -> int:
	var before := total_crew()
	_lose_crew(n)
	return before - total_crew()


func _apply_perishable() -> void:
	for i in range(ships.size()):
		var sc: Dictionary = _ship_cargo(i)
		for gid in sc.keys().duplicate():
			var rate := 0.0
			for g in GameManager.goods_data.get("goods", []):
				if g.get("id") == gid:
					rate = float(g.get("perishable", 0.0))
					break
			if rate <= 0.0:
				continue
			var q: int = sc[gid]["qty"]
			# 概率化，避免小批量货物永远不腐；总管理货可减损。
			# 期望损失 = Σ rate×q_i = rate×总量，与分船前一致。
			if randf() < rate * q * Crew.cargo_loss_factor():
				remove_cargo(gid, 1, i)


## 士气系数，影响航速与白刃战
func morale_factor() -> float:
	return 0.6 + 0.4 * (float(morale) / float(MORALE_MAX))


## 将领系数（主角武力）：白刃战判定输入之一。满值 100 → ×1.5，越高越强。
func captain_power() -> float:
	return 1.0 + 0.5 * (float(GameState.martial) / 100.0)


# ── 船体 ──────────────────────────────────────────────

func total_durability() -> float:
	var d := 0.0
	for s in ships:
		d += float(s.get("durability", 0))
	return d


func total_max_durability() -> float:
	var d := 0.0
	for s in ships:
		d += float(s.get("max_durability", 0))
	return d


func damage_fleet(amount: float) -> void:
	if ships.is_empty():
		return
	# 优先打旗舰
	var s: Dictionary = ships[0]
	s["durability"] = maxf(0.0, float(s.get("durability", 0)) - amount)


func repair_cost() -> int:
	return int((total_max_durability() - total_durability()) * 2.0)


func repair_all() -> void:
	for s in ships:
		s["durability"] = s["max_durability"]


# ── 改装 ──────────────────────────────────────────────

## 指定船帆等级（越界返回 0）
func sail_level(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return int(ships[i].get("sail_level", 1))


## 指定船甲等级（越界返回 0）
func armor_level(i: int) -> int:
	if i < 0 or i >= ships.size():
		return 0
	return int(ships[i].get("armor_level", 1))


func is_sail_max(i: int) -> bool:
	return i < 0 or i >= ships.size() or sail_level(i) >= SAIL_LEVEL_MAX


func is_armor_max(i: int) -> bool:
	return i < 0 or i >= ships.size() or armor_level(i) >= ARMOR_LEVEL_MAX


## 指定船升级指定项到下一级的花费。满级返回 0（防御——调用方应先看 is_*_max）。
func upgrade_cost(i: int, kind: String) -> int:
	if i < 0 or i >= ships.size():
		return 0
	var lv := armor_level(i) if kind == "armor" else sail_level(i)
	var mx := ARMOR_LEVEL_MAX if kind == "armor" else SAIL_LEVEL_MAX
	if lv >= mx:
		return 0
	var price := float(ship_def(ships[i].get("type", "")).get("price", 0))
	var armor_mult := 1.25 if kind == "armor" else 1.0
	return int(ceil(price * UPGRADE_BASE_RATIO * (1.0 + 0.5 * float(lv - 1)) * armor_mult))


## 升帆。满级返回 false；只改等级不碰钱（钱由调用方先扣）。
func upgrade_sail(i: int) -> bool:
	if is_sail_max(i):
		return false
	ships[i]["sail_level"] = sail_level(i) + 1
	return true


## 升甲。满级返回 false；只改等级不碰钱。
func upgrade_armor(i: int) -> bool:
	if is_armor_max(i):
		return false
	ships[i]["armor_level"] = armor_level(i) + 1
	return true


## 全队甲等级按 max_durability 加权的均值（≥1），供战力计算用。
## 加权避免「旗舰满甲 + 一群小艍」被简单平均稀释；空舰队返回 1。
func fleet_armor_level() -> int:
	var num := 0.0
	var den := 0.0
	for s in ships:
		var w := float(s.get("max_durability", 1.0))
		num += w * float(int(s.get("armor_level", 1)) - 1)
		den += w
	if den <= 0.0:
		return 1
	return 1 + int(round(num / den))


## 全队船体伤害系数：满甲 0.80（最多减 20% 船体伤），Lv1 为 1.0。
## 风暴与海盗船体伤都乘此系数。加权口径同上，防除零。
func armor_damage_reduction() -> float:
	var num := 0.0
	var den := 0.0
	for s in ships:
		var w := float(s.get("max_durability", 1.0))
		num += w * float(int(s.get("armor_level", 1)) - 1)
		den += w
	if den <= 0.0:
		return 1.0
	var avg := num / den
	return clampf(1.0 - 0.10 * avg, 0.0, 1.0)


## 舰队日速（里/日），取最慢一艘，计入士气与火长
func fleet_speed() -> float:
	if ships.is_empty():
		return 0.0
	var slowest := 99999.0
	for s in ships:
		var d := ship_def(s.get("type", ""))
		var spd := float(d.get("base_speed", 100)) * (1.0 + 0.12 * (int(s.get("sail_level", 1)) - 1))
		slowest = minf(slowest, spd)
	return slowest * morale_factor() * Crew.speed_factor()


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"ships": ships,
		"water": water,
		"food": food,
		"morale": morale,
	}


func from_dict(d: Dictionary) -> void:
	ships = d.get("ships", [])
	# 逐船兜底：旧档（或手改档）的船可能缺 cargo 字段
	var legacy_cargo: Dictionary = d.get("cargo", {})
	var any_ship_cargo := false
	for s in ships:
		if not s.has("cargo") or not (s["cargo"] is Dictionary):
			s["cargo"] = {}
		if not (s["cargo"] as Dictionary).is_empty():
			any_ship_cargo = true
	# VERSION 1 旧档：全队货在顶层 cargo，各船皆空 → 迁入旗舰
	if not legacy_cargo.is_empty() and not any_ship_cargo and not ships.is_empty():
		ships[0]["cargo"] = legacy_cargo
	water = d.get("water", 0)
	food = d.get("food", 0)
	morale = d.get("morale", 70)
	at_sea = false  # 只在港内存档，读档必定停泊
