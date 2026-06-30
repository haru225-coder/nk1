extends Node2D
class_name RouteLayer

var port_nodes: Dictionary = {}


func set_port_nodes(nodes: Dictionary) -> void:
	port_nodes = nodes
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if port_nodes.is_empty():
		return
	MapRoutePainter.draw_world_routes(self, port_nodes)