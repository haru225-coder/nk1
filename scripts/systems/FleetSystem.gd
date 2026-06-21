extends Node
# 注册为全局 Autoload: FleetSystem
# 逻辑舰队注册表 + 港口坐标缓存。
# 视觉遭遇已改由 WorldMap + MapFleetNode + FleetArchetypes 驱动；
# NPCFleetGenerator / EncounterSystem.resolve_encounter 为遗留接口，保留供数据化遭遇扩展。

var active_fleets: Array = []
var _initialized: bool = false

var _port_pos_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameManager.data_loaded.is_connected(_initialize_fleets):
		GameManager.data_loaded.connect(_initialize_fleets)
	if not GameManager.scenes_data.is_empty() or not GameManager.ports_data.is_empty():
		_initialize_fleets()

func _initialize_fleets() -> void:
	if _initialized:
		return
	_initialized = true
	var ports = GameManager.ports_data.get("ports", [])
	for p in ports:
		var p_id = p.get("id", "")
		var pos = p.get("position", {"x": 0, "y": 0})
		_port_pos_cache[p_id] = Vector2(pos.get("x", 0), pos.get("y", 0))
	active_fleets.clear()

func spawn_fleet(state: Dictionary) -> void:
	if not state.has("world_position") and state.get("route", []).size() > 0:
		state["world_position"] = _get_port_pos(state["route"][0])
	active_fleets.append(state)

func despawn_fleet(fleet: Dictionary) -> void:
	active_fleets.erase(fleet)

func _get_port_pos(port_id: String) -> Vector2:
	return _port_pos_cache.get(port_id, Vector2.ZERO)

func get_nearby_fleets(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for f in active_fleets:
		var pos: Vector2 = f.get("world_position", Vector2.ZERO)
		if pos.distance_to(center) <= radius:
			result.append(f)
	return result