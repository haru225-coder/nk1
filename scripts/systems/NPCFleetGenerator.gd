class_name NPCFleetGenerator extends RefCounted

# 遗留逻辑舰队生态生成器。当前海上视觉遭遇由 WorldMap._maintain_fleet_spawns 负责；
# 本模块保留供日后将 NPCFleetGenerator 与 FleetSystem 逻辑坐标系重新接线。

const MAX_MERCHANTS = 5
const MAX_PATROLS = 2
const MAX_PIRATES = 3

static func process_ecology(delta: float) -> void:
	# 检查各类型舰队数量并补充
	var merchant_count = 0
	var patrol_count = 0
	var pirate_count = 0
	
	for fleet in FleetSystem.active_fleets:
		var faction_id = fleet.get("faction", "")
		var faction_data = FactionSystem.get_faction_data(faction_id)
		var b = faction_data.get("behavior", [])
		if "trade" in b: merchant_count += 1
		elif "inspect" in b: patrol_count += 1
		elif "raid" in b: pirate_count += 1
		
	if merchant_count < MAX_MERCHANTS:
		_spawn_merchant()
		
	if patrol_count < MAX_PATROLS:
		_spawn_patrol()
		
	if pirate_count < MAX_PIRATES:
		_spawn_pirate()

static func _spawn_merchant() -> void:
	var routes = [
		["quanzhou", "ryukyu"],
		["ryukyu", "quanzhou"],
		["quanzhou", "penghu"],
		["penghu", "quanzhou"]
	]
	var r = routes[randi() % routes.size()]
	var fleet_id = "merchant_" + str(randi() % 10000)
	
	var state = {
		"id": fleet_id,
		"faction": "pu_family_trade",
		"name": "蒲氏商队 " + str(randi() % 100),
		"route": r,
		"speed": randf_range(30.0, 50.0),
		"state": "sailing",
		"hostility": false,
		"current_node_idx": 0,
		"world_position": Vector2.ZERO,
		"progress": 0.0
	}
	FleetSystem.spawn_fleet(state)

static func _spawn_patrol() -> void:
	var routes = [
		["quanzhou", "penghu", "quanzhou"]
	]
	var r = routes[randi() % routes.size()]
	var fleet_id = "patrol_" + str(randi() % 10000)
	
	var state = {
		"id": fleet_id,
		"faction": "song_maritime_office",
		"name": "大宋水师巡防营",
		"route": r,
		"speed": randf_range(40.0, 60.0),
		"state": "sailing",
		"hostility": false,
		"current_node_idx": 0,
		"world_position": Vector2.ZERO,
		"progress": 0.0
	}
	FleetSystem.spawn_fleet(state)

static func _spawn_pirate() -> void:
	var routes = [
		["penghu", "ryukyu", "penghu"],
		["ryukyu", "penghu", "ryukyu"]
	]
	var r = routes[randi() % routes.size()]
	var fleet_id = "pirate_" + str(randi() % 10000)
	
	var state = {
		"id": fleet_id,
		"faction": "lin_pirates",
		"name": "林氏海贼船",
		"route": r,
		"speed": randf_range(45.0, 65.0),
		"state": "sailing",
		"hostility": true,
		"current_node_idx": 0,
		"world_position": Vector2.ZERO,
		"progress": 0.0
	}
	FleetSystem.spawn_fleet(state)
