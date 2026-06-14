extends Node
# 注册为全局 Autoload: FleetSystem
# 负责所有 AI 舰队的逻辑坐标系更新，独立于 WorldMap

var active_fleets: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 需要延迟初始化，等待 GameManager 读取数据完成
	call_deferred("_initialize_fleets")
	
func _initialize_fleets() -> void:
	# 阶段一：保留 fleets.json 作为初始配置（如果有）
	var fleets_data = GameManager.fleets_data.get("fleets", [])
	for fd in fleets_data:
		spawn_fleet(fd)

func spawn_fleet(state: Dictionary) -> void:
	if not state.has("world_position") and state.get("route", []).size() > 0:
		state["world_position"] = _get_port_pos(state["route"][0])
	active_fleets.append(state)

func despawn_fleet(fleet: Dictionary) -> void:
	active_fleets.erase(fleet)

func _process(delta: float) -> void:
	if GameState.flags.has("navigation_locked"): return
	
	# 生态系统介入，补充舰队配额
	NPCFleetGenerator.process_ecology(delta)
	
	# 全局沙盘推演：只要游戏运行，舰队就在移动
	var to_despawn = []
	for fleet in active_fleets:
		if _update_fleet_position(fleet, delta):
			to_despawn.append(fleet)
			
	for fleet in to_despawn:
		despawn_fleet(fleet)

# 返回 true 表示舰队已经抵达终点需要销毁
func _update_fleet_position(fleet: Dictionary, delta: float) -> bool:
	var route = fleet.get("route", [])
	if route.size() < 2: return false
	
	var next_idx = fleet.get("current_node_idx", 0) + 1
	if next_idx >= route.size():
		return true # 抵达终点，通知销毁
		
	var start_id = route[fleet["current_node_idx"]]
	var target_id = route[next_idx]
	
	var start_pos = _get_port_pos(start_id)
	var target_pos = _get_port_pos(target_id)
	
	var dist = start_pos.distance_to(target_pos)
	if dist < 1.0: return false
	
	var speed = fleet.get("speed", 50.0)
	var progress = fleet.get("progress", 0.0) + (speed * delta) / dist
	if progress >= 1.0:
		fleet["current_node_idx"] += 1
		fleet["progress"] = 0.0
		fleet["world_position"] = target_pos
		if fleet["current_node_idx"] + 1 >= route.size():
			return true
	else:
		fleet["progress"] = progress
		fleet["world_position"] = start_pos.lerp(target_pos, progress)
		
	return false

func _get_port_pos(port_id: String) -> Vector2:
	var ports = GameManager.ports_data.get("ports", [])
	for p in ports:
		if p.get("id") == port_id:
			var pos = p.get("position", {"x":0, "y":0})
			return Vector2(pos.get("x", 0), pos.get("y", 0))
	return Vector2.ZERO

func get_nearby_fleets(center: Vector2, radius: float) -> Array:
	var result = []
	for f in active_fleets:
		if f["world_position"].distance_to(center) <= radius:
			result.append(f)
	return result
