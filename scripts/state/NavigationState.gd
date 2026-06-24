class_name NavigationState extends RefCounted

## 航行位置管理模块

var last_port: String = "quanzhou"
var current_voyage_origin: String = "quanzhou"
var navigation_position: String = ""

signal departed_port(port_id: String)
signal returned_to_port(port_id: String)

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
	return {"last_port": last_port, "current_voyage_origin": current_voyage_origin, "navigation_position": navigation_position}

func from_dict(d: Dictionary) -> void:
	last_port = d.get("last_port", "quanzhou")
	current_voyage_origin = d.get("current_voyage_origin", "quanzhou")
	navigation_position = d.get("navigation_position", "")
