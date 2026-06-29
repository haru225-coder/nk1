class_name MapLayout
extends RefCounted

const _DEFAULT_BOUNDS := Rect2(-15000.0, -9000.0, 31000.0, 30000.0)


static func get_ports_data() -> Array:
	return GameManager.ports_data.get("ports", [])


static func get_world_bounds() -> Rect2:
	var wb: Dictionary = GameManager.ports_data.get("meta", {}).get("map_layout", {}).get("world_bounds", {})
	if wb.is_empty():
		return _DEFAULT_BOUNDS
	var x_min := float(wb.get("x_min", _DEFAULT_BOUNDS.position.x))
	var y_min := float(wb.get("y_min", _DEFAULT_BOUNDS.position.y))
	var x_max := float(wb.get("x_max", _DEFAULT_BOUNDS.end.x))
	var y_max := float(wb.get("y_max", _DEFAULT_BOUNDS.end.y))
	return Rect2(x_min, y_min, x_max - x_min, y_max - y_min)


static func get_map_pos(port_id: String) -> Vector2:
	for port_data in get_ports_data():
		if port_data.get("id", "") != port_id:
			continue
		return _uv_from_port(port_data)
	return Vector2(-1.0, -1.0)


static func has_map_pos(port_id: String) -> bool:
	return get_map_pos(port_id).x >= 0.0


static func map_uv_to_world(uv: Vector2) -> Vector2:
	var bounds := get_world_bounds()
	return Vector2(
		bounds.position.x + uv.x * bounds.size.x,
		bounds.position.y + uv.y * bounds.size.y
	)


static func port_world_position(port_data: Dictionary) -> Vector2:
	var uv := _uv_from_port(port_data)
	if uv.x >= 0.0:
		return map_uv_to_world(uv)
	var pos_data: Dictionary = port_data.get("position", {"x": 0, "y": 0})
	return Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))


static func world_to_map_uv(world_pos: Vector2) -> Vector2:
	var bounds := get_world_bounds()
	var u := (world_pos.x - bounds.position.x) / bounds.size.x
	var v := (world_pos.y - bounds.position.y) / bounds.size.y
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


static func uv_to_pixel(uv: Vector2, map_size: Vector2) -> Vector2:
	return Vector2(uv.x * map_size.x, uv.y * map_size.y)


static func _uv_from_port(port_data: Dictionary) -> Vector2:
	var map_pos: Dictionary = port_data.get("map_pos", {})
	if map_pos.has("u") and map_pos.has("v"):
		return Vector2(float(map_pos.u), float(map_pos.v))
	return Vector2(-1.0, -1.0)