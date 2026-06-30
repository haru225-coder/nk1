class_name MapRoutePainter
extends RefCounted

const ROUTE_COLOR := Color(0.77, 0.66, 0.36, 0.55)

const ROUTE_WIDTH_WORLD := 4.0
const ROUTE_DASH_WORLD := 48.0
const ROUTE_GAP_WORLD := 32.0

const ROUTE_WIDTH_MINIMAP := 1.5
const ROUTE_DASH_MINIMAP := 8.0
const ROUTE_GAP_MINIMAP := 6.0


static func route_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func draw_world_routes(canvas: CanvasItem, port_nodes: Dictionary) -> void:
	draw_routes(
		canvas,
		func(port_id: String) -> Vector2:
			if not port_nodes.has(port_id):
				return Vector2.INF
			var node: Node2D = port_nodes[port_id]
			return node.position,
		ROUTE_WIDTH_WORLD,
		ROUTE_DASH_WORLD,
		ROUTE_GAP_WORLD
	)


static func draw_uv_routes(canvas: CanvasItem, map_rect: Rect2) -> void:
	draw_routes(
		canvas,
		func(port_id: String) -> Vector2:
			if not MapLayout.has_map_pos(port_id):
				return Vector2.INF
			var uv: Vector2 = MapLayout.get_map_pos(port_id)
			return MapLayout.uv_to_pixel(uv, map_rect.size) + map_rect.position,
		ROUTE_WIDTH_MINIMAP,
		ROUTE_DASH_MINIMAP,
		ROUTE_GAP_MINIMAP
	)


static func draw_routes(
	canvas: CanvasItem,
	point_for_port: Callable,
	line_width: float,
	dash_length: float,
	gap_length: float,
	color: Color = ROUTE_COLOR
) -> void:
	var drawn: Dictionary = {}
	for port_data in MapLayout.get_ports_data():
		var from_id: String = port_data.get("id", "")
		if from_id == "":
			continue
		var from_pt: Vector2 = point_for_port.call(from_id)
		if from_pt == Vector2.INF:
			continue
		for conn_id in port_data.get("connections", []):
			var conn_str := str(conn_id)
			var key := route_key(from_id, conn_str)
			if drawn.has(key):
				continue
			var to_pt: Vector2 = point_for_port.call(conn_str)
			if to_pt == Vector2.INF:
				continue
			drawn[key] = true
			_draw_dashed_line(canvas, from_pt, to_pt, color, line_width, dash_length, gap_length)


static func _draw_dashed_line(
	canvas: CanvasItem,
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	dash_length: float,
	gap_length: float
) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		return
	var dir := delta / length
	var pos := 0.0
	var drawing := true
	while pos < length:
		var seg := dash_length if drawing else gap_length
		seg = minf(seg, length - pos)
		if drawing:
			canvas.draw_line(from + dir * pos, from + dir * (pos + seg), color, width)
		pos += seg
		drawing = not drawing