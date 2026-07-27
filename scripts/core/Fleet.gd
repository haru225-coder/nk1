extends Node
## 舰队：船只、舱位、货物、补给、士气。
## 货舱为全队共用，载重上限是各船之和——简化自大航海时代的分船装载。

signal cargo_changed()
signal supplies_critical(kind: String)

## 每条船：{type, name, durability, max_durability, crew, sail_level, armor_level}
var ships: Array = []

## 全队货舱：{good_id: {"qty": int, "avg_cost": float}}
var cargo: Dictionary = {}

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
	})
	return true


func remove_ship(index: int) -> void:
	if index >= 0 and index < ships.size() and ships.size() > 1:
		ships.remove_at(index)


func flagship() -> Dictionary:
	return ships[0] if not ships.is_empty() else {}


# ── 载重 ──────────────────────────────────────────────

func total_capacity() -> float:
	var cap := 0.0
	for s in ships:
		cap += float(ship_def(s.get("type", "")).get("capacity", 0))
	return cap


func used_capacity() -> float:
	var used := float(water + food) * SUPPLY_BULK
	for gid in cargo.keys():
		used += float(cargo[gid].get("qty", 0)) * _bulk(gid)
	return used


func free_capacity() -> float:
	return maxf(0.0, total_capacity() - used_capacity())


func _bulk(good_id: String) -> float:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return float(g.get("bulk", 1.0))
	return 1.0


## 以当前空舱还能装多少单位此货
func max_loadable(good_id: String) -> int:
	var b := _bulk(good_id)
	if b <= 0.0:
		return 9999
	return int(floor(free_capacity() / b))


# ── 货物 ──────────────────────────────────────────────

func add_cargo(good_id: String, qty: int, unit_cost: float) -> bool:
	if qty <= 0:
		return false
	if float(qty) * _bulk(good_id) > free_capacity() + 0.001:
		return false
	if cargo.has(good_id):
		var e: Dictionary = cargo[good_id]
		var old_qty: int = e["qty"]
		var old_cost: float = e["avg_cost"]
		var new_qty := old_qty + qty
		e["avg_cost"] = (old_cost * old_qty + unit_cost * qty) / float(new_qty)
		e["qty"] = new_qty
	else:
		cargo[good_id] = {"qty": qty, "avg_cost": unit_cost}
	cargo_changed.emit()
	return true


func remove_cargo(good_id: String, qty: int) -> bool:
	if not cargo.has(good_id):
		return false
	var e: Dictionary = cargo[good_id]
	if e["qty"] < qty:
		return false
	e["qty"] -= qty
	if e["qty"] <= 0:
		cargo.erase(good_id)
	cargo_changed.emit()
	return true


func cargo_qty(good_id: String) -> int:
	return cargo.get(good_id, {}).get("qty", 0)


func cargo_cost(good_id: String) -> float:
	return cargo.get(good_id, {}).get("avg_cost", 0.0)


## 随机丢弃一定比例货物（暴风、中弹、查扣）
func lose_cargo_ratio(ratio: float) -> Dictionary:
	var lost := {}
	for gid in cargo.keys().duplicate():
		var q: int = cargo[gid]["qty"]
		var l := mini(int(ceil(q * ratio)), q)
		if l > 0:
			remove_cargo(gid, l)
			lost[gid] = l
	return lost


func clear_cargo() -> void:
	cargo.clear()
	cargo_changed.emit()


# ── 船员与补给 ────────────────────────────────────────

func total_crew() -> int:
	var c := 0
	for s in ships:
		c += int(s.get("crew", 0))
	return c


func crew_min_required() -> int:
	var m := 0
	for s in ships:
		m += int(ship_def(s.get("type", "")).get("crew_min", 0))
	return m


func crew_max() -> int:
	var m := 0
	for s in ships:
		m += int(ship_def(s.get("type", "")).get("crew_max", 0))
	return m


func can_sail() -> bool:
	return total_crew() >= crew_min_required() and not ships.is_empty()


## 按当前船员数，现有补给还够几日
func supply_days() -> int:
	if total_crew() <= 0:
		return 999
	var per_day := daily_supply_use()
	if per_day <= 0:
		return 999
	return int(floor(minf(float(water), float(food)) / float(per_day)))


func hire_crew(n: int) -> int:
	var room := crew_max() - total_crew()
	var actual := mini(n, room)
	var left := actual
	for s in ships:
		var cap: int = int(ship_def(s.get("type", "")).get("crew_max", 0)) - int(s.get("crew", 0))
		var take: int = mini(left, cap)
		s["crew"] = int(s.get("crew", 0)) + take
		left -= take
		if left <= 0:
			break
	return actual


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
		if water <= 0:
			supplies_critical.emit("water")
		if food <= 0:
			supplies_critical.emit("food")
		# 断水断粮开始死人；医人能压住一部分
		if randf() < 0.4 * Crew.crew_loss_factor():
			_lose_crew(maxi(1, int(crew * 0.03)))
	else:
		if morale < 70:
			morale = mini(MORALE_MAX, morale + 1 + Crew.morale_bonus())

	_apply_perishable()


func _lose_crew(n: int) -> void:
	var left := n
	for s in ships:
		var c: int = int(s.get("crew", 0))
		var take: int = mini(left, c)
		s["crew"] = c - take
		left -= take
		if left <= 0:
			break


func _apply_perishable() -> void:
	for gid in cargo.keys().duplicate():
		var rate := 0.0
		for g in GameManager.goods_data.get("goods", []):
			if g.get("id") == gid:
				rate = float(g.get("perishable", 0.0))
				break
		if rate <= 0.0:
			continue
		var q: int = cargo[gid]["qty"]
		# 概率化，避免小批量货物永远不腐；总管理货可减损
		if randf() < rate * q * Crew.cargo_loss_factor():
			remove_cargo(gid, 1)


## 士气系数，影响航速与白刃战
func morale_factor() -> float:
	return 0.6 + 0.4 * (float(morale) / float(MORALE_MAX))


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
		"cargo": cargo,
		"water": water,
		"food": food,
		"morale": morale,
	}


func from_dict(d: Dictionary) -> void:
	ships = d.get("ships", [])
	cargo = d.get("cargo", {})
	water = d.get("water", 0)
	food = d.get("food", 0)
	morale = d.get("morale", 70)
	at_sea = false  # 只在港内存档，读档必定停泊
	cargo_changed.emit()
