extends Control

var ship: Node2D
var root: Node
var map_scale: float = 0.02
var radar_radius: float = 75.0

func _ready() -> void:
	# WorldMap 可能是 add_child 到 SeaChart 上的子场景（P4 海战），
	# current_scene 不是 WorldMap 根。沿父链找到含 Ship 的场景根。
	var n: Node = self
	while n:
		if n.has_node("Ship"):
			root = n
			ship = n.get_node("Ship")
			break
		n = n.get_parent()

func _process(delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not ship: return

	# Draw background
	draw_circle(Vector2(radar_radius, radar_radius), radar_radius, Color(0, 0.1, 0.2, 0.8))
	draw_arc(Vector2(radar_radius, radar_radius), radar_radius, 0, TAU, 32, Color(0.2, 0.5, 0.8, 1.0), 2.0)

	# Draw ship (center)
	var center = Vector2(radar_radius, radar_radius)
	draw_circle(center, 3.0, Color.WHITE)

	# Draw ports (Green) and pirates (Red)
	if not root: return

	# Draw Ports
	if root.has_node("Ports"):
		for port in root.get_node("Ports").get_children():
			if not port.visible: continue  # 战斗模式隐藏港口，雷达不画
			_draw_blip(port.global_position, Color.GREEN)

	# Draw Pirates
	for child in root.get_children():
		if child.name.begins_with("PirateShip"):
			_draw_blip(child.global_position, Color.RED)

func _draw_blip(world_pos: Vector2, color: Color) -> void:
	var rel_pos = world_pos - ship.global_position
	var map_pos = rel_pos * map_scale
	
	if map_pos.length() < radar_radius - 2.0:
		draw_circle(Vector2(radar_radius, radar_radius) + map_pos, 2.5, color)
