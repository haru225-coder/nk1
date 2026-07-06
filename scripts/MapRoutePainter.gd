class_name MapRoutePainter
extends RefCounted

const ROUTE_COLOR := Color(0.65, 0.15, 0.15, 0.75) # 朱砂红

const ROUTE_WIDTH_WORLD := 3.0
const ROUTE_DASH_WORLD := 1.0 # 不再需要虚线
const ROUTE_GAP_WORLD := 0.0

const ROUTE_WIDTH_MINIMAP := 1.5
const ROUTE_DASH_MINIMAP := 1.0
const ROUTE_GAP_MINIMAP := 0.0


static func route_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


static func river_route_keys() -> Dictionary:
	var keys: Dictionary = {}
	for port_data in MapLayout.get_ports_data():
		var from_id: String = port_data.get("id", "")
		if from_id == "":
			continue
		for r in port_data.get("river_routes", []):
			if not (r is Dictionary):
				continue
			var to_id := str(r.get("to", ""))
			if to_id == "":
				continue
			keys[route_key(from_id, to_id)] = true
	return keys


static func draw_world_routes(canvas: CanvasItem, port_nodes: Dictionary) -> void:
	var get_port_pos := func(port_id: String) -> Vector2:
		if not port_nodes.has(port_id):
			return Vector2.INF
		var node: Node2D = port_nodes[port_id]
		return node.position

	draw_routes(
		canvas,
		get_port_pos,
		ROUTE_WIDTH_WORLD,
		ROUTE_DASH_WORLD,
		ROUTE_GAP_WORLD
	)

	var get_world_uv := func(uv: Vector2) -> Vector2:
		return MapLayout.map_to_world(uv)

	draw_river_routes(
		canvas,
		get_port_pos,
		get_world_uv,
		ROUTE_WIDTH_WORLD,
		ROUTE_DASH_WORLD,
		ROUTE_GAP_WORLD
	)


static func draw_uv_routes(canvas: CanvasItem, map_rect: Rect2) -> void:
	var get_minimap_pos := func(port_id: String) -> Vector2:
		if not MapLayout.has_map_pos(port_id):
			return Vector2.INF
		var uv: Vector2 = MapLayout.get_map_pos(port_id)
		return MapLayout.uv_to_pixel(uv, map_rect.size) + map_rect.position

	draw_routes(
		canvas,
		get_minimap_pos,
		ROUTE_WIDTH_MINIMAP,
		ROUTE_DASH_MINIMAP,
		ROUTE_GAP_MINIMAP
	)

	var uv_to_pt := func(uv: Vector2) -> Vector2:
		return MapLayout.uv_to_pixel(uv, map_rect.size) + map_rect.position

	draw_river_routes(
		canvas,
		get_minimap_pos,
		uv_to_pt,
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
	var river_keys := river_route_keys()
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
			if river_keys.has(key):
				continue
			if drawn.has(key):
				continue
			var to_pt: Vector2 = point_for_port.call(conn_str)
			if to_pt == Vector2.INF:
				continue
			drawn[key] = true
			_draw_dashed_line(canvas, from_pt, to_pt, color, line_width, dash_length, gap_length)


static func draw_river_routes(
	canvas: CanvasItem,
	point_for_port: Callable,
	uv_to_point: Callable,
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
		for r in port_data.get("river_routes", []):
			if not (r is Dictionary):
				continue
			var to_id: String = str(r.get("to", ""))
			var key := route_key(from_id, to_id)
			if drawn.has(key):
				continue
			var to_pt: Vector2 = point_for_port.call(to_id)
			if to_pt == Vector2.INF:
				continue
			drawn[key] = true
			var prev: Vector2 = from_pt
			for wp in r.get("waypoints", []):
				if not (wp is Dictionary):
					continue
				var wp_uv := Vector2(float(wp.get("u", 0.0)), float(wp.get("v", 0.0)))
				var wpt: Vector2 = uv_to_point.call(wp_uv)
				_draw_dashed_line(canvas, prev, wpt, color, line_width, dash_length, gap_length)
				prev = wpt
			_draw_dashed_line(canvas, prev, to_pt, color, line_width, dash_length, gap_length)


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

	# 朱砂针路：传统海图使用实线绘制航线，不再使用跑马灯虚线
	canvas.draw_line(from, to, color, width)
