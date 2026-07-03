class_name SceneBackgroundLoader extends RefCounted

const MAX_CACHE_SIZE := 10

var _cache: Dictionary = {}
var _cache_order: Array[String] = []

func apply_background(target: TextureRect, scene_data: Dictionary) -> void:
	if target == null:
		return
	var tex := get_scene_texture(scene_data)
	if tex != null:
		target.texture = tex

func get_scene_texture(scene_data: Dictionary) -> Texture2D:
	var bg_path := resolve_scene_background_path(scene_data)
	if _cache.has(bg_path):
		_touch(bg_path)
		return _cache[bg_path] as Texture2D
	var tex := AssetPlaceholder.load_texture(bg_path, "bg")
	if tex != null:
		_cache[bg_path] = tex
		_touch(bg_path)
		_evict_extra()
	return tex

func resolve_scene_background_path(scene_data: Dictionary) -> String:
	var bg_path := str(scene_data.get("bg", ResourcePaths.BG_DEFAULT))
	if str(scene_data.get("type", "")) == "port":
		bg_path = AssetPlaceholder.pick_background_path(bg_path)
	return bg_path

func _touch(bg_path: String) -> void:
	var idx := _cache_order.find(bg_path)
	if idx >= 0:
		_cache_order.remove_at(idx)
	_cache_order.append(bg_path)

func _evict_extra() -> void:
	while _cache_order.size() > MAX_CACHE_SIZE:
		var evict: String = _cache_order.pop_front()
		_cache.erase(evict)
