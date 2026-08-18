class_name ShipState extends RefCounted

## 船只状态管理模块

var hull_id: String = "fujian_merchant"
var name: String = "未命名船只"
var hp: float = 100.0
var max_hp: float = 100.0
var crew: int = 30
var max_crew: int = 50
var armor_level: int = 1
var sail_level: int = 1
var sail_type: String = "square"

## ── 战斗属性 (Phase 3) ──────────────────────────────────
## 武装评分：火炮数量与威力系数，影响炮击伤害
var artillery: int = 3
## 剑术/肉搏：提督或冲锋队长战斗力，影响白刃战胜损比与单挑胜率
var swordplay: int = 2
## 机动性：船只操控能力，影响T字战法判定与撤退成功率
var maneuverability: int = 5

func to_dict() -> Dictionary:
	return {
		"hull_id": hull_id, "name": name, "hp": hp, "max_hp": max_hp,
		"crew": crew, "max_crew": max_crew,
		"armor_level": armor_level, "sail_level": sail_level, "sail_type": sail_type,
		"artillery": artillery, "swordplay": swordplay, "maneuverability": maneuverability,
	}

func from_dict(d: Dictionary) -> void:
	hull_id = str(d.get("hull_id", "fujian_merchant"))
	if hull_id.is_empty():
		hull_id = "fujian_merchant"
	name = str(d.get("name", "未命名船只"))
	if name.is_empty():
		name = "未命名船只"
	max_hp = maxf(1.0, _as_finite(d.get("max_hp", 100.0), 100.0))
	hp = clampf(_as_finite(d.get("hp", max_hp), max_hp), 0.0, max_hp)
	max_crew = maxi(1, int(d.get("max_crew", 50)))
	crew = clampi(int(d.get("crew", 30)), 0, max_crew)
	armor_level = maxi(0, int(d.get("armor_level", 1)))
	sail_level = maxi(0, int(d.get("sail_level", 1)))
	sail_type = str(d.get("sail_type", "square"))
	if sail_type != "lateen":
		sail_type = "square"
	artillery = maxi(0, int(d.get("artillery", 3)))
	swordplay = maxi(0, int(d.get("swordplay", 2)))
	maneuverability = maxi(0, int(d.get("maneuverability", 5)))

static func _as_finite(value, fallback: float) -> float:
	var n := float(value)
	if is_nan(n) or is_inf(n):
		return fallback
	return n
