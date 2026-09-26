extends Control

var ship: Node2D
var root: Node
var map_scale: float = 0.02
var radar_radius: float = 75.0
var _pulse_phase: float = 0.0

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
	_pulse_phase = fmod(_pulse_phase + delta, TAU)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(ship):
		return

	var center := Vector2(radar_radius, radar_radius)
	# 熟漆圆盘、泥金圈。本船朱砂，港口泥金，敌船更亮的朱砂。
	draw_circle(center, radar_radius, Color(0.10, 0.07, 0.04, 0.90))
	draw_arc(center, radar_radius - 1.0, 0, TAU, 48, UiTheme.GOLD, 1.5)
	# 两道淡刻线和十字定位，让无目标时也有稳定的航海仪器感。
	draw_arc(center, radar_radius * 0.52, 0, TAU, 40, Color(UiTheme.GOLD, 0.22), 1.0)
	draw_arc(center, radar_radius * 0.78, 0, TAU, 40, Color(UiTheme.GOLD, 0.18), 1.0)
	draw_line(center + Vector2(-radar_radius + 8.0, 0), center + Vector2(radar_radius - 8.0, 0), Color(UiTheme.GOLD, 0.14), 1.0)
	draw_line(center + Vector2(0, -radar_radius + 8.0), center + Vector2(0, radar_radius - 8.0), Color(UiTheme.GOLD, 0.14), 1.0)

	# 本船脉动一圈，保留朱砂实心点作为视觉锚点。
	var pulse := 0.5 + 0.5 * sin(_pulse_phase * 2.0)
	draw_circle(center, 6.0 + pulse * 3.0, Color(UiTheme.CINNABAR, 0.14 + pulse * 0.10))
	draw_circle(center, 3.5, UiTheme.CINNABAR)

	# Draw ports (Green) and pirates (Red)
	if not is_instance_valid(root):
		return

	# Draw Ports
	if root.has_node("Ports"):
		for port in root.get_node("Ports").get_children():
			if not port.visible: continue  # 战斗模式隐藏港口，雷达不画
			_draw_blip(port.global_position, UiTheme.GOLD)

	# Draw Pirates
	for child in root.get_children():
		if child.name.begins_with("PirateShip"):
			_draw_blip(child.global_position, UiTheme.SEAL_HI)

func _draw_blip(world_pos: Vector2, color: Color) -> void:
	var rel_pos := world_pos - ship.global_position
	var map_pos := rel_pos * map_scale
	var center := Vector2(radar_radius, radar_radius)
	var edge_radius := radar_radius - 8.0
	var dist := map_pos.length()
	if dist < 0.001:
		return
	if dist <= edge_radius:
		var alpha := clampf(1.0 - dist / (radar_radius * 2.0), 0.55, 1.0)
		var blip_color := color
		blip_color.a = alpha
		draw_circle(center + map_pos, 2.5, blip_color)
		return

	# Off-screen contacts stay legible as small edge chevrons instead of
	# disappearing, while the arrow direction still points toward their bearing.
	var dir := map_pos.normalized()
	var pos := center + dir * edge_radius
	var tangent := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 4.5
	var left := pos - dir * 3.0 + tangent * 3.2
	var right := pos - dir * 3.0 - tangent * 3.2
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
