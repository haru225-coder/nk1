extends Control

const MAP_TEXTURE := preload(ResourcePaths.TEX_MAP_NANHAI)

var ship: Node2D
var _last_ship_pos := Vector2.INF
var _last_ship_rot := INF
var _last_nearest_port := ""
var _last_map_size := Vector2.ZERO
var _last_hull_id := ""

const _INSET := 6.0
const _SHIP_COLOR := Color(1.0, 0.94, 0.58, 1.0)


func _ready() -> void:
	_bind_ship()


func _bind_ship() -> bool:
	if is_instance_valid(ship):
		return true
	var nodes: Array = get_tree().get_nodes_in_group("player_ship")
	if nodes.is_empty():
		return false
	var node: Node = nodes[0]
	if node is Node2D:
		ship = node
		return true
	return false


func _process(_delta: float) -> void:
	if not is_instance_valid(ship):
		_bind_ship()
	if _needs_redraw():
		queue_redraw()


func _needs_redraw() -> bool:
	if size != _last_map_size:
		return true
	var nearest := _nearest_port_id()
	if nearest != _last_nearest_port:
		return true
	if not is_instance_valid(ship):
		return _last_ship_pos != Vector2.INF
	if ship.global_position.distance_squared_to(_last_ship_pos) > 4.0:
		return true
	if not is_equal_approx(ship.rotation, _last_ship_rot):
		return true
	if _player_hull_id() != _last_hull_id:
		return true
	return false


func _cache_draw_state() -> void:
	_last_map_size = size
	_last_nearest_port = _nearest_port_id()
	if is_instance_valid(ship):
		_last_ship_pos = ship.global_position
		_last_ship_rot = ship.rotation
	else:
		_last_ship_pos = Vector2.INF
		_last_ship_rot = INF
	_last_hull_id = _player_hull_id()


func _player_hull_id() -> String:
	var flagship := GameState.fleet.get_flagship()
	return flagship.hull_id if flagship else ShipSystem.DEFAULT_HULL_ID


func _map_rect() -> Rect2:
	return Rect2(
		Vector2(_INSET, _INSET),
		size - Vector2(_INSET * 2.0, _INSET * 2.0)
	)


func _draw() -> void:
	_cache_draw_state()
	var rect := _map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return

	draw_rect(rect, Color(0.1, 0.16, 0.22, 1.0))
	if MAP_TEXTURE:
		draw_texture_rect(MAP_TEXTURE, rect, false)

	MapRoutePainter.draw_uv_routes(self, rect)
	_draw_ports(rect)

	if is_instance_valid(ship):
		var uv := MapLayout.world_to_map_uv(ship.global_position)
		var ship_px := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
		_draw_ship_icon(ship_px, ship.rotation, _player_hull_id())


func _draw_ship_icon(center: Vector2, rot: float, hull_id: String) -> void:
	var hull_pts := ShipModelLibrary.get_minimap_hull(hull_id)
	var outline: PackedVector2Array = []
	for p in hull_pts:
		outline.append(center + p.rotated(rot))
	if outline.size() < 3:
		draw_circle(center, 4.0, _SHIP_COLOR)
		return
	var shadow: PackedVector2Array = []
	for p in hull_pts:
		shadow.append(center + Vector2(0.6, 0.8) + p.rotated(rot))
	draw_colored_polygon(shadow, Color(0.05, 0.05, 0.08, 0.5))
	draw_colored_polygon(outline, _SHIP_COLOR)
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0.25, 0.18, 0.08, 0.85), 1.0, true)


func _draw_ports(rect: Rect2) -> void:
	var nearest := _nearest_port_id()
	for port_data in MapLayout.get_ports_data():
		var port_id: String = port_data.get("id", "")
		if not MapLayout.has_map_pos(port_id):
			continue
		var uv: Vector2 = MapLayout.get_map_pos(port_id)
		var px := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
		var status: String = port_data.get("status", "")
		var radius := MapPortStyle.dot_radius(status)
		var color := MapPortStyle.port_color(status)
		if port_id == nearest:
			draw_circle(px, radius + 2.0, Color(color.r, color.g, color.b, 0.35))
		draw_circle(px, radius, color)
		if port_id == nearest:
			var label: String = port_data.get("name", port_id)
			var font := ThemeDB.fallback_font
			var font_size := 11
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var label_pos := px + Vector2(-text_size.x * 0.5, -radius - text_size.y - 2.0)
			draw_rect(
				Rect2(label_pos - Vector2(2, 1), text_size + Vector2(4, 2)),
				MapPortStyle.LABEL_BG
			)
			draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MapPortStyle.LABEL_COLOR)


func _nearest_port_id() -> String:
	if not is_instance_valid(ship):
		return ""
	var root = get_tree().current_scene
	if root == null or not root.has_node("Ports"):
		return ""
	var best_id := ""
	var best_dist := INF
	for port in root.get_node("Ports").get_children():
		if not (port is Node2D):
			continue
		var dist := ship.global_position.distance_to(port.global_position)
		if dist < best_dist:
			best_dist = dist
			best_id = port.port_id
	return best_id