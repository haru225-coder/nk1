class_name FleetState extends RefCounted

## ═══════════════════════════════════════════════════════════
## FleetState — 多船舰队数据模型
## 维护一组 ShipState，提供全舰队属性的聚合计算与资源分配。
## ═══════════════════════════════════════════════════════════

var ships: Array[ShipState] = []

func _init() -> void:
	# 默认初始有一艘旗舰
	var flagship = ShipState.new()
	flagship.name = "旗舰"
	ships.append(flagship)

func get_flagship() -> ShipState:
	if ships.is_empty():
		return null
	return ships[0]

func get_total_crew() -> int:
	return ships.reduce(func(acc, s): return acc + s.crew, 0)

func get_max_crew() -> int:
	return ships.reduce(func(acc, s): return acc + s.max_crew, 0)

func get_total_artillery() -> int:
	return ships.reduce(func(acc, s): return acc + s.artillery, 0)

func get_avg_maneuverability() -> int:
	if ships.is_empty(): return 1
	return ships.reduce(func(acc, s): return acc + s.maneuverability, 0) / ships.size()

## 水手变动分配逻辑
func modify_crew(amount: int) -> void:
	var rem = abs(amount)
	var is_add = amount > 0
	for s in ships:
		if rem <= 0: break
		var diff = mini(s.max_crew - s.crew if is_add else s.crew, rem)
		s.crew += diff if is_add else -diff
		rem -= diff

func to_dict() -> Dictionary:
	return {"ships": ships.map(func(s): return s.to_dict())}

func from_dict(d: Dictionary) -> void:
	ships.clear()
	for sd in d.get("ships", []):
		var s = ShipState.new()
		s.from_dict(sd)
		ships.append(s)
