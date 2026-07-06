class_name MapLayout
extends RefCounted

const _DEFAULT_BOUNDS := Rect2(-13000.0, -5000.0, 26000.0, 32200.0)
const _TERRAIN_SHADER = preload("res://assets/map_terrain_detail.gdshader")
const TEXTURE_ASPECT_TOLERANCE := 0.02
const _PORTS_JSON := "res://data/ports.json"

static var _ports_data_cache: Dictionary = {}
static var _cached_astar_graph: AStarGraph = null


static func _ports_root() -> Dictionary:
	if not _ports_data_cache.is_empty():
		return _ports_data_cache
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var gm: Node = tree.root.get_node_or_null("GameManager")
		if gm != null:
			var live: Variant = gm.get("ports_data")
			if live is Dictionary and not live.is_empty():
				_ports_data_cache = live
				return _ports_data_cache
	var text := FileAccess.get_file_as_string(_PORTS_JSON)
	if text != "":
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_ports_data_cache = parsed
	return _ports_data_cache


static func get_ports_data() -> Array:
	return _ports_root().get("ports", [])


static func get_astar_graph() -> AStarGraph:
	if _cached_astar_graph == null:
		_cached_astar_graph = AStarGraph.new()
		_cached_astar_graph.build_graph(get_ports_data())
	return _cached_astar_graph


static func get_map_layout() -> Dictionary:
	return _ports_root().get("meta", {}).get("map_layout", {})


static func get_map_texture_path() -> String:
	return str(get_map_layout().get("texture", ResourcePaths.TEX_MAP_EAST_ASIA))


static func get_map_texture() -> Texture2D:
	return _load_texture(get_map_texture_path())


static func get_sea_mask_path() -> String:
	return str(get_map_layout().get("sea_mask", ResourcePaths.TEX_MAP_EAST_ASIA_SEA_MASK))


static func get_sea_mask_texture() -> Texture2D:
	return _load_texture(get_sea_mask_path())


static func _load_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


static func get_world_bounds() -> Rect2:
	var wb: Dictionary = get_map_layout().get("world_bounds", {})
	if wb.is_empty():
		return _DEFAULT_BOUNDS
	var x_min := float(wb.get("x_min", _DEFAULT_BOUNDS.position.x))
	var y_min := float(wb.get("y_min", _DEFAULT_BOUNDS.position.y))
	var x_max := float(wb.get("x_max", _DEFAULT_BOUNDS.end.x))
	var y_max := float(wb.get("y_max", _DEFAULT_BOUNDS.end.y))
	return Rect2(x_min, y_min, x_max - x_min, y_max - y_min)


static func map_world_rect() -> Rect2:
	return get_world_bounds()


static func world_bounds_aspect() -> float:
	var rect := get_world_bounds()
	if rect.size.y <= 0.0:
		return 1.0
	return rect.size.x / rect.size.y


static func texture_aspect(tex_size: Vector2) -> float:
	if tex_size.y <= 0.0:
		return 1.0
	return tex_size.x / tex_size.y


static func texture_matches_world_bounds(tex_size: Vector2, tolerance: float = TEXTURE_ASPECT_TOLERANCE) -> bool:
	return absf(texture_aspect(tex_size) - world_bounds_aspect()) <= tolerance


static func map_sprite_transform(tex_size: Vector2) -> Transform2D:
	var rect := get_world_bounds()
	var scale := Vector2(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	return Transform2D(0.0, scale, 0.0, rect.get_center())


static func apply_strategic_map_layer(sprite: Sprite2D, texture: Texture2D) -> void:
	sprite.texture = texture
	sprite.centered = true
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var tex_size := Vector2(texture.get_width(), texture.get_height())
	sprite.transform = map_sprite_transform(tex_size)


static func apply_strategic_map_sprite(sprite: Sprite2D) -> bool:
	var tex := get_map_texture()
	if tex == null:
		return false
	apply_strategic_map_layer(sprite, tex)

	var mat := ShaderMaterial.new()
	mat.shader = _TERRAIN_SHADER
	sprite.material = mat

	return true


static func apply_ocean_overlay(sprite: Sprite2D, ocean_texture: Texture2D, material: ShaderMaterial) -> bool:
	var mask := get_sea_mask_texture()
	if mask == null or ocean_texture == null or material == null:
		return false
	apply_strategic_map_layer(sprite, ocean_texture)
	var mat := material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("sea_mask", mask)
	sprite.material = mat
	return true


static func get_map_pos(port_id: String) -> Vector2:
	for port_data in get_ports_data():
		if port_data.get("id", "") != port_id:
			continue
		return _uv_from_port(port_data)
	return Vector2(-1.0, -1.0)


static func has_map_pos(port_id: String) -> bool:
	return get_map_pos(port_id).x >= 0.0


static func map_uv_to_world(uv: Vector2) -> Vector2:
	return map_to_world(uv)


static func map_to_world(uv: Vector2) -> Vector2:
	var bounds := get_world_bounds()
	return Vector2(
		bounds.position.x + uv.x * bounds.size.x,
		bounds.position.y + uv.y * bounds.size.y
	)


static func port_world_position(port_data: Dictionary) -> Vector2:
	var uv := _uv_from_port(port_data)
	if uv.x >= 0.0:
		return map_uv_to_world(uv)
	var pos_data: Dictionary = port_data.get("position", {"x": 0, "y": 0})
	return Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))


static func world_to_map_uv(world_pos: Vector2) -> Vector2:
	return world_to_map(world_pos)


static func world_to_map(world_pos: Vector2) -> Vector2:
	var bounds := get_world_bounds()
	var u := (world_pos.x - bounds.position.x) / bounds.size.x
	var v := (world_pos.y - bounds.position.y) / bounds.size.y
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


static func uv_to_pixel(uv: Vector2, map_size: Vector2) -> Vector2:
	return Vector2(uv.x * map_size.x, uv.y * map_size.y)


static func _uv_from_port(port_data: Dictionary) -> Vector2:
	var map_pos: Dictionary = port_data.get("map_pos", {})
	if map_pos.has("u") and map_pos.has("v"):
		return Vector2(float(map_pos.u), float(map_pos.v))
	return Vector2(-1.0, -1.0)
