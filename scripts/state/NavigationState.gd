class_name NavigationState extends RefCounted

## 航行位置管理模块

var last_port: String = "quanzhou"
var current_voyage_origin: String = "quanzhou"
var navigation_position: String = ""
var world_map_pose_saved: bool = false
var world_map_position: Vector2 = Vector2.ZERO
var world_map_rotation: float = 0.0
var voyage_destination_id: String = ""

signal departed_port(port_id: String)
signal returned_to_port(port_id: String)


func save_world_map_pose(pos: Vector2, rot: float) -> void:
	world_map_position = pos
	world_map_rotation = rot
	world_map_pose_saved = true


func clear_world_map_pose() -> void:
	world_map_pose_saved = false
	world_map_position = Vector2.ZERO
	world_map_rotation = 0.0


func set_voyage_destination(port_id: String) -> bool:
	if port_id == "" or not MapLayout.has_map_pos(port_id):
		return false
	voyage_destination_id = port_id
	return true


func clear_voyage_destination() -> void:
	voyage_destination_id = ""


func depart_port(can_depart_result: Dictionary) -> Dictionary:
	if not can_depart_result["success"]:
		return can_depart_result
	current_voyage_origin = last_port
	departed_port.emit(last_port)
	return {"success": true, "msg": "【大航海】文牒验讫，扬帆起航！"}

func return_port(port_id: String) -> void:
	last_port = port_id
	returned_to_port.emit(port_id)

func to_dict() -> Dictionary:
	return {
		"last_port": last_port,
		"current_voyage_origin": current_voyage_origin,
		"navigation_position": navigation_position,
		"world_map_pose_saved": world_map_pose_saved,
		"world_map_position": {"x": world_map_position.x, "y": world_map_position.y},
		"world_map_rotation": world_map_rotation,
		"voyage_destination_id": voyage_destination_id,
	}

func from_dict(d: Dictionary) -> void:
	last_port = d.get("last_port", "quanzhou")
	current_voyage_origin = d.get("current_voyage_origin", "quanzhou")
	navigation_position = d.get("navigation_position", "")
	world_map_pose_saved = d.get("world_map_pose_saved", false)
	var pos = d.get("world_map_position", {})
	if pos is Dictionary:
		world_map_position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	world_map_rotation = float(d.get("world_map_rotation", 0.0))
	voyage_destination_id = d.get("voyage_destination_id", "")
