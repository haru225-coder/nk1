extends Control

var ship: Node2D
var map_scale: float = 0.02
var radar_radius: float = 75.0

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
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(ship):
		return
	
	# Draw background
	draw_circle(Vector2(radar_radius, radar_radius), radar_radius, Color(0, 0.1, 0.2, 0.8))
	draw_arc(Vector2(radar_radius, radar_radius), radar_radius, 0, TAU, 32, Color(0.2, 0.5, 0.8, 1.0), 2.0)
	
	# Draw ship (center)
	var center = Vector2(radar_radius, radar_radius)
	draw_circle(center, 3.0, Color.WHITE)
	
	var root = get_tree().current_scene

	if root.has_node("Ports"):
		for port in root.get_node("Ports").get_children():
			_draw_blip(port.global_position, Color.GREEN)

	for fleet in get_tree().get_nodes_in_group("map_fleet"):
		if fleet is Node2D:
			_draw_blip(fleet.global_position, Color(1.0, 0.35, 0.35))

func _draw_blip(world_pos: Vector2, color: Color) -> void:
	var rel_pos = world_pos - ship.global_position
	var map_pos = rel_pos * map_scale
	
	if map_pos.length() < radar_radius - 2.0:
		draw_circle(Vector2(radar_radius, radar_radius) + map_pos, 2.5, color)
