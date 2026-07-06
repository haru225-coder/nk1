extends RefCounted
class_name AStarGraph

var _astar: AStar2D = AStar2D.new()
var _port_id_to_idx: Dictionary = {}
var _idx_to_port_id: Dictionary = {}

func build_graph(ports_data: Array) -> void:
	_astar.clear()
	_port_id_to_idx.clear()
	_idx_to_port_id.clear()

	var idx = 0
	# First pass: add all ports as points
	for p in ports_data:
		var pid = p.get("id", "")
		if pid == "": continue

		var pos = MapLayout.port_world_position(p)
		_astar.add_point(idx, pos)
		_port_id_to_idx[pid] = idx
		_idx_to_port_id[idx] = pid
		idx += 1

	# Second pass: add connections
	for p in ports_data:
		var pid = p.get("id", "")
		if pid == "": continue
		var p_idx = _port_id_to_idx[pid]

		var conns = p.get("connections", [])
		for c in conns:
			if _port_id_to_idx.has(c):
				var c_idx = _port_id_to_idx[c]
				# connect_points is bidirectional, weight is euclidean distance
				_astar.connect_points(p_idx, c_idx)

func get_path_between_ports(from_port_id: String, to_port_id: String) -> PackedVector2Array:
	if not _port_id_to_idx.has(from_port_id) or not _port_id_to_idx.has(to_port_id):
		return PackedVector2Array()
	return _astar.get_point_path(_port_id_to_idx[from_port_id], _port_id_to_idx[to_port_id])

func get_path_from_pos(world_pos: Vector2, to_port_id: String) -> PackedVector2Array:
	if not _port_id_to_idx.has(to_port_id):
		return PackedVector2Array()

	var to_idx = _port_id_to_idx[to_port_id]
	var closest_idx = _astar.get_closest_point(world_pos)

	if closest_idx < 0:
		return PackedVector2Array()

	var path = _astar.get_point_path(closest_idx, to_idx)

	# Insert current position at the beginning of the path
	var final_path = PackedVector2Array()
	final_path.append(world_pos)
	final_path.append_array(path)

	return final_path
