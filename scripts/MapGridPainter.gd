class_name MapGridPainter
extends Node2D

const GRID_SIZE := 512.0
const GRID_COLOR := Color(0.15, 0.1, 0.05, 0.15) # Faint sepia ink

func _ready() -> void:
	z_index = 1 # 确保绘制在海洋和陆地贴图之上，但在港口和商线之下
	queue_redraw()

func _draw() -> void:
	var map_size := 8192.0
	var half_size := map_size / 2.0

	# 计里画方：绘制传统中式地图的方格网
	var curr_x := -half_size
	while curr_x <= half_size:
		draw_line(Vector2(curr_x, -half_size), Vector2(curr_x, half_size), GRID_COLOR, 3.0)
		curr_x += GRID_SIZE

	var curr_y := -half_size
	while curr_y <= half_size:
		draw_line(Vector2(-half_size, curr_y), Vector2(half_size, curr_y), GRID_COLOR, 3.0)
		curr_y += GRID_SIZE
