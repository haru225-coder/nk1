class_name MapGridPainter
extends Node2D

const GRID_SIZE := 512.0
const GRID_COLOR := Color(0.15, 0.1, 0.05, 0.15) # Faint sepia ink

func _ready() -> void:
	z_index = 1 # 确保绘制在海洋和陆地贴图之上，但在港口和商线之下
	queue_redraw()

func grid_rect() -> Rect2:
	return MapLayout.get_world_bounds()

func _draw() -> void:
	var rect := grid_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	# 计里画方：绘制传统中式地图的方格网
	var curr_x := rect.position.x
	while curr_x <= rect.end.x:
		draw_line(Vector2(curr_x, rect.position.y), Vector2(curr_x, rect.end.y), GRID_COLOR, 3.0)
		curr_x += GRID_SIZE

	var curr_y := rect.position.y
	while curr_y <= rect.end.y:
		draw_line(Vector2(rect.position.x, curr_y), Vector2(rect.end.x, curr_y), GRID_COLOR, 3.0)
		curr_y += GRID_SIZE
