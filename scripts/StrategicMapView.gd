extends Control
class_name StrategicMapView

signal port_clicked(port_id: String)

const PORT_ICON: Texture2D = preload("res://assets/icons_128/icon_shipyard_koei.png")

const _INSET := 12.0
const _PORT_HIT_RADIUS := 18.0
const _SHIP_COLOR := Color(0.75, 0.18, 0.18, 1.0) # 朱砂红
const _DEST_COLOR := Color(0.8, 0.2, 0.2, 0.9) # 深朱砂红
const _BG_COLOR := Color(0.85, 0.78, 0.65, 1.0) # 羊皮纸底色

var ship: Node2D
var destination_port_id: String = ""


func _draw() -> void:
	var rect := _map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	draw_rect(rect, _BG_COLOR)
	var tex := MapLayout.get_map_texture()  # 数据驱动，跟随 meta.map_layout.texture
	if tex:
		# ponytail: 拉伸填满 rect；后续 rect 改 0.808 竖向比例可无畸变
		draw_texture_rect(tex, rect, false)
	MapRoutePainter.draw_uv_routes(self, rect)
	_draw_destination_marker(rect)
	_draw_port_icons(rect)
	_draw_ship_marker(rect)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var port_id := _port_at_position(event.position)
		if port_id != "":
			port_clicked.emit(port_id)
			accept_event()


func _map_rect() -> Rect2:
	return Rect2(
		Vector2(_INSET, _INSET),
		size - Vector2(_INSET * 2.0, _INSET * 2.0)
	)


func _draw_port_icons(rect: Rect2) -> void:
	var icon_size := Vector2(22.0, 22.0)
	for port_data in MapLayout.get_ports_data():
		var port_id: String = port_data.get("id", "")
		if not MapLayout.has_map_pos(port_id):
			continue
		var uv: Vector2 = MapLayout.get_map_pos(port_id)
		var center := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
		var status: String = port_data.get("status", "")
		var tint := MapPortStyle.port_modulate(status)
		if PORT_ICON:
			var top_left := center - icon_size * 0.5
			draw_texture_rect(PORT_ICON, Rect2(top_left, icon_size), false, tint)


func _draw_ship_marker(rect: Rect2) -> void:
	if not is_instance_valid(ship):
		return
	var uv := MapLayout.world_to_map_uv(ship.global_position)
	var center := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
	var hull_id := _player_hull_id()
	var hull_pts := ShipModelLibrary.get_minimap_hull(hull_id)
	var outline: PackedVector2Array = []
	for p in hull_pts:
		outline.append(center + p.rotated(ship.rotation) * 1.4)
	if outline.size() < 3:
		draw_circle(center, 6.0, _SHIP_COLOR)
		return
	draw_colored_polygon(outline, _SHIP_COLOR)
	draw_polyline(outline + PackedVector2Array([outline[0]]), Color(0.25, 0.18, 0.08, 0.9), 1.5, true)


func _draw_destination_marker(rect: Rect2) -> void:
	if destination_port_id == "" or not MapLayout.has_map_pos(destination_port_id):
		return
	var uv: Vector2 = MapLayout.get_map_pos(destination_port_id)
	var center := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
	draw_arc(center, 16.0, 0.0, TAU, 32, _DEST_COLOR, 2.5, true)


func _port_at_position(local_pos: Vector2) -> String:
	var rect := _map_rect()
	var best_id := ""
	var best_dist := _PORT_HIT_RADIUS
	for port_data in MapLayout.get_ports_data():
		var port_id: String = port_data.get("id", "")
		if not MapLayout.has_map_pos(port_id):
			continue
		var uv: Vector2 = MapLayout.get_map_pos(port_id)
		var center := MapLayout.uv_to_pixel(uv, rect.size) + rect.position
		var dist := local_pos.distance_to(center)
		if dist <= best_dist:
			best_dist = dist
			best_id = port_id
	return best_id


func _player_hull_id() -> String:
	var flagship := GameState.fleet.get_flagship()
	return flagship.hull_id if flagship else ShipSystem.DEFAULT_HULL_ID