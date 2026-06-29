class_name ShipSystem
extends RefCounted

## 船只系统 — 船型数据、性能结算、航行步进（不依赖 GameState，避免循环引用）。

const DEFAULT_HULL_ID := "fujian_merchant"
const SPEED_PER_SAIL_LEVEL := 50.0
const TURN_PER_SAIL_LEVEL := 0.2

const TURN_EFFICIENCY_FULL_SAIL := 0.45
const TURN_EFFICIENCY_HALF_SAIL := 0.75
const TURN_EFFICIENCY_NO_SAIL := 0.20
const TURN_EFFICIENCY_NO_CREW := 0.2

const STORM_WIND_THRESHOLD := 150.0
const STORM_DAMAGE_PER_SEC := 5.0
const SHIPS_DATA_PATH := "res://data/ships.json"

static var _ships_data_cache: Dictionary = {}


static func _fallback_hull() -> Dictionary:
	return {
		"id": DEFAULT_HULL_ID,
		"name": "福船",
		"max_hp": 100,
		"max_crew": 50,
		"base_max_speed": 280.0,
		"base_turn_speed": 1.9,
		"max_sail_gear": 2,
		"sail_type": "square",
		"sail_level": 1,
		"armor_level": 1,
		"artillery": 2,
		"swordplay": 2,
		"maneuverability": 5,
		"speed_per_sail_level": SPEED_PER_SAIL_LEVEL,
		"turn_per_sail_level": TURN_PER_SAIL_LEVEL,
	}


static func _ships_data() -> Dictionary:
	if not _ships_data_cache.is_empty():
		return _ships_data_cache
	if FileAccess.file_exists(SHIPS_DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SHIPS_DATA_PATH))
		if parsed is Dictionary:
			_ships_data_cache = parsed
	return _ships_data_cache


static func get_hull(hull_id: String) -> Dictionary:
	var hulls: Array = _ships_data().get("hulls", [])
	for hull in hulls:
		if hull.get("id", "") == hull_id:
			return hull
	if hull_id == DEFAULT_HULL_ID or hull_id.is_empty():
		return _fallback_hull()
	return {}


static func get_hull_change_cost(hull_id: String) -> int:
	var hull := get_hull(hull_id)
	if hull.is_empty():
		return 0
	return int(hull.get("change_cost", 0))


static func is_hull_unlocked(
	hull: Dictionary,
	fame: int,
	has_story_flag: Callable = Callable()
) -> bool:
	var unlock: Dictionary = hull.get("unlock", {})
	if unlock.is_empty():
		return bool(hull.get("shipyard_available", true))
	if fame < int(unlock.get("fame_min", 0)):
		return false
	var req_flag := str(unlock.get("requires_story_flag", ""))
	if not req_flag.is_empty():
		if not has_story_flag.is_valid() or not bool(has_story_flag.call(req_flag)):
			return false
	return true


static func get_hull_unlock_hint(hull: Dictionary) -> String:
	var hint := str(hull.get("unlock_hint", ""))
	if not hint.is_empty():
		return hint
	var unlock: Dictionary = hull.get("unlock", {})
	var parts: Array[String] = []
	if unlock.has("fame_min"):
		parts.append("名声≥%d" % int(unlock.fame_min))
	if unlock.has("requires_story_flag"):
		parts.append("需完成前置剧情")
	return "，".join(parts)


static func _is_shipyard_candidate(hull: Dictionary) -> bool:
	if bool(hull.get("shipyard_available", false)):
		return true
	return not hull.get("unlock", {}).is_empty()


static func list_shipyard_hull_offers(
	current_hull_id: String,
	fame: int,
	has_story_flag: Callable = Callable()
) -> Array:
	var offers: Array = []
	for hull in _ships_data().get("hulls", []):
		if not hull is Dictionary:
			continue
		var hull_id := str(hull.get("id", ""))
		if hull_id.is_empty() or hull_id == current_hull_id:
			continue
		if not _is_shipyard_candidate(hull):
			continue
		var locked := not is_hull_unlocked(hull, fame, has_story_flag)
		offers.append({
			"hull": hull,
			"locked": locked,
			"unlock_hint": get_hull_unlock_hint(hull) if locked else "",
		})
	return offers


static func list_shipyard_hulls(
	current_hull_id: String,
	fame: int,
	has_story_flag: Callable = Callable()
) -> Array:
	var options: Array = []
	for offer in list_shipyard_hull_offers(current_hull_id, fame, has_story_flag):
		if offer.get("locked", false):
			continue
		options.append(offer.get("hull", {}))
	return options


static func apply_hull_to_flagship(flagship: ShipState, hull_id: String, preserve_ratios: bool = true) -> bool:
	if flagship == null:
		return false
	var hull := get_hull(hull_id)
	if hull.is_empty():
		return false

	var hp_ratio := flagship.hp / flagship.max_hp if flagship.max_hp > 0.0 else 1.0
	var crew_ratio := float(flagship.crew) / float(flagship.max_crew) if flagship.max_crew > 0 else 1.0
	var sail_level := flagship.sail_level

	flagship.hull_id = hull.get("id", DEFAULT_HULL_ID)
	flagship.name = hull.get("name", flagship.name)
	flagship.max_hp = float(hull.get("max_hp", 100))
	flagship.max_crew = int(hull.get("max_crew", 50))
	flagship.sail_type = hull.get("sail_type", "square")
	flagship.armor_level = int(hull.get("armor_level", 1))
	flagship.artillery = int(hull.get("artillery", 2))
	flagship.swordplay = int(hull.get("swordplay", 2))
	flagship.maneuverability = int(hull.get("maneuverability", 5))

	if preserve_ratios:
		flagship.hp = flagship.max_hp * hp_ratio
		flagship.crew = ceili(flagship.max_crew * crew_ratio)
	else:
		flagship.hp = flagship.max_hp
	flagship.crew = mini(flagship.crew, flagship.max_crew)
	flagship.sail_level = sail_level
	return true


static func create_ship_state(hull_id: String = DEFAULT_HULL_ID) -> ShipState:
	var hull := get_hull(hull_id)
	if hull.is_empty():
		hull = _fallback_hull()
	var ship := ShipState.new()
	ship.hull_id = hull.get("id", DEFAULT_HULL_ID)
	ship.name = hull.get("name", "旗舰")
	ship.max_hp = float(hull.get("max_hp", 100))
	ship.hp = ship.max_hp
	ship.max_crew = int(hull.get("max_crew", 50))
	ship.crew = mini(ship.max_crew, 30)
	ship.sail_type = hull.get("sail_type", "square")
	ship.sail_level = int(hull.get("sail_level", 1))
	ship.armor_level = int(hull.get("armor_level", 1))
	ship.artillery = int(hull.get("artillery", 2))
	ship.swordplay = int(hull.get("swordplay", 2))
	ship.maneuverability = int(hull.get("maneuverability", 5))
	return ship


static func sail_type_label(sail_type: String) -> String:
	return "纵帆" if sail_type == "lateen" else "横帆"


static func format_ship_summary(ship: ShipState) -> String:
	if ship == null:
		return ""
	var perf := compute_performance(ship)
	return "旗舰：%s · %s · 耐久 %d/%d · 航速 %d · 机动 %d" % [
		ship.name,
		sail_type_label(ship.sail_type),
		int(ship.hp),
		int(ship.max_hp),
		int(perf.max_speed),
		ship.maneuverability,
	]


static func format_hull_change_delta(ship: ShipState, target_hull_id: String) -> String:
	if ship == null:
		return ""
	var target := get_hull(target_hull_id)
	if target.is_empty():
		return ""
	var parts: Array[String] = []
	_append_stat_delta(parts, "耐久", int(ship.max_hp), int(target.get("max_hp", 0)))
	_append_stat_delta(parts, "载员", ship.max_crew, int(target.get("max_crew", 0)))
	var current_speed := int(compute_performance(ship).max_speed)
	var target_speed := int(
		float(target.get("base_max_speed", 0))
		+ float(ship.sail_level - 1) * float(target.get("speed_per_sail_level", SPEED_PER_SAIL_LEVEL))
	)
	_append_stat_delta(parts, "航速", current_speed, target_speed)
	_append_stat_delta(parts, "机动", ship.maneuverability, int(target.get("maneuverability", 0)))
	var target_sail := str(target.get("sail_type", "square"))
	if target_sail != ship.sail_type:
		parts.append("帆→%s" % sail_type_label(target_sail))
	return "，".join(parts)


static func _append_stat_delta(parts: Array[String], label: String, current: int, target: int) -> void:
	var diff := target - current
	if diff == 0:
		return
	parts.append("%s%+d" % [label, diff])


static func compute_performance(ship: ShipState) -> Dictionary:
	var hull := get_hull(ship.hull_id)
	var speed_step := float(hull.get("speed_per_sail_level", SPEED_PER_SAIL_LEVEL))
	var turn_step := float(hull.get("turn_per_sail_level", TURN_PER_SAIL_LEVEL))
	var base_speed := float(hull.get("base_max_speed", 280.0))
	var base_turn := float(hull.get("base_turn_speed", 1.9))
	return {
		"max_speed": base_speed + float(ship.sail_level - 1) * speed_step,
		"base_turn_speed": base_turn + float(ship.sail_level - 1) * turn_step,
		"max_gear": int(hull.get("max_sail_gear", 2)),
		"sail_type": ship.sail_type,
	}


static func sync_runtime_from_state(ship_node: Node, flagship: ShipState) -> void:
	if ship_node == null or not is_instance_valid(ship_node) or flagship == null:
		return
	var perf := compute_performance(flagship)
	if "hull_hp" in ship_node:
		ship_node.hull_hp = flagship.hp
	if "max_hp" in ship_node:
		ship_node.max_hp = flagship.max_hp
	if "max_speed" in ship_node:
		ship_node.max_speed = perf.max_speed
	if "base_turn_speed" in ship_node:
		ship_node.base_turn_speed = perf.base_turn_speed
	if "max_gear" in ship_node:
		ship_node.max_gear = perf.max_gear


static func apply_damage(ship_node: Node, flagship: ShipState, amount: float) -> void:
	if flagship == null:
		return
	flagship.hp = maxf(0.0, flagship.hp - amount)
	sync_runtime_from_state(ship_node, flagship)


static func handle_sail_input(event: InputEvent, sail_gear: int, max_gear: int) -> int:
	if event.is_action_pressed("ui_up"):
		return mini(sail_gear + 1, max_gear)
	if event.is_action_pressed("ui_down"):
		return maxi(sail_gear - 1, 0)
	return sail_gear


static func step_sailing(
	ship_node: Node,
	delta: float,
	crew_count: int,
	sail_type: String,
	on_crew_loss: Callable
) -> Dictionary:
	var turn_input := Input.get_axis("ui_left", "ui_right")
	var sail_gear: int = ship_node.sail_gear
	var max_gear: int = ship_node.max_gear
	var stats_changed := false

	var turn_efficiency := 1.0
	if sail_gear == 2:
		turn_efficiency = TURN_EFFICIENCY_FULL_SAIL
	elif sail_gear == 1:
		turn_efficiency = TURN_EFFICIENCY_HALF_SAIL
	elif sail_gear == 0:
		turn_efficiency = TURN_EFFICIENCY_NO_SAIL

	if crew_count <= 0:
		turn_efficiency *= TURN_EFFICIENCY_NO_CREW
		if sail_gear != 0:
			sail_gear = 0
			stats_changed = true

	ship_node.rotation += turn_input * ship_node.base_turn_speed * turn_efficiency * delta

	var heading := Vector2.UP.rotated(ship_node.rotation)
	var phys := SailPhysicsEngine.calculate(
		ship_node.velocity,
		heading,
		ship_node.wind_vector,
		ship_node.wind_strength,
		sail_gear,
		ship_node.max_speed,
		sail_type,
		delta
	)
	ship_node.velocity = phys.new_velocity

	if phys.is_dead_wind and sail_gear > 0 and randf() < 0.2 * delta:
		if on_crew_loss.is_valid():
			on_crew_loss.call()
		stats_changed = true

	ship_node.sail_gear = sail_gear
	return {
		"sail_gear": sail_gear,
		"stats_changed": stats_changed,
		"efficiency": phys.efficiency,
		"is_dead_wind": phys.is_dead_wind,
		"speed": ship_node.velocity.length(),
	}


static func should_storm_damage(wind_strength: float, sail_gear: int) -> bool:
	return wind_strength > STORM_WIND_THRESHOLD and sail_gear == 2


static func storm_damage_amount(delta: float) -> float:
	return STORM_DAMAGE_PER_SEC * delta