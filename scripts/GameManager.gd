extends Node

signal data_loaded

const FacilityResolverScript := preload(ResourcePaths.SCRIPT_FACILITY_RESOLVER)

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}
var items_data: Dictionary = {}
var events_data: Dictionary = {}
var world_events_data: Dictionary = {}
var factions_data: Dictionary = {}
var fleets_data: Dictionary = {}
var ships_data: Dictionary = {}
var localization_data: Dictionary = {}
var ui_commands_data: Dictionary = {}
var input_locked: bool = false

## 兼容旧引用：GameManager.state → GameState autoload
var state:
	get: return GameState

# O(1) 查找缓存字典
var _scenes_by_id: Dictionary = {}
var _ports_by_id: Dictionary = {}
var _goods_by_id: Dictionary = {}
var _goods_by_name: Dictionary = {}
var _npcs_by_id: Dictionary = {}
var _items_by_id: Dictionary = {}

func _ready() -> void:
	load_data()

func set_input_locked(locked: bool) -> void:
	input_locked = locked

func load_data() -> void:
	scenes_data = _load_scenes_from_directory(ResourcePaths.DIR_DATA_SCENES)
	if scenes_data.is_empty():
		# 向后兼容：如果分片目录不存在，回退到单文件
		scenes_data = _load_json(ResourcePaths.DATA_SCENES)
	goods_data = _load_json(ResourcePaths.DATA_GOODS)
	ports_data = _load_json(ResourcePaths.DATA_PORTS)
	npcs_data = _load_json(ResourcePaths.DATA_NPCS)
	items_data = _load_json(ResourcePaths.DATA_ITEMS)
	events_data = _load_json(ResourcePaths.DATA_ENCOUNTERS)
	world_events_data = _load_json(ResourcePaths.DATA_WORLD_EVENTS)
	factions_data = _load_json(ResourcePaths.DATA_FACTIONS)
	fleets_data = _load_json(ResourcePaths.DATA_FLEETS)
	ships_data = _load_json(ResourcePaths.DATA_SHIPS)
	localization_data = _load_json(ResourcePaths.DATA_LOCALIZATION_ZH_CN)
	ui_commands_data = _load_json(ResourcePaths.DATA_UI_COMMANDS)
	
	_build_lookup_dictionaries()
	
	if GameState.market:
		GameState.market.init_from_ports(ports_data.get("ports", []), goods_data.get("goods", []))
	data_loaded.emit()

func _build_lookup_dictionaries() -> void:
	_scenes_by_id.clear()
	for s in scenes_data.get("scenes", []):
		var sid = s.get("id", "")
		if sid != "":
			_scenes_by_id[sid] = s
	
	_ports_by_id.clear()
	for p in ports_data.get("ports", []):
		var pid = p.get("id", "")
		if pid != "":
			_ports_by_id[pid] = p
	
	_goods_by_id.clear()
	_goods_by_name.clear()
	for g in goods_data.get("goods", []):
		var gid = g.get("id", "")
		var gname = g.get("name", "")
		if gid != "":
			_goods_by_id[gid] = g
		if gname != "":
			_goods_by_name[gname] = g

	_npcs_by_id.clear()
	for n in npcs_data.get("npcs", []):
		var nid = n.get("id", "")
		if nid != "":
			_npcs_by_id[nid] = n

	_items_by_id.clear()
	for item in items_data.get("items", []):
		var iid = item.get("id", "")
		if iid != "":
			_items_by_id[iid] = item

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[GameManager] Could not find " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[GameManager] Could not open " + path + " (error: " + str(FileAccess.get_open_error()) + ")")
		return {}
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	if parse_result == OK:
		return json.data
	else:
		push_error("[GameManager] JSON Parse Error in " + path + ": " + json.get_error_message())
	return {}

## 从分片目录 data/scenes/ 加载并合并所有场景 JSON
func _load_scenes_from_directory(dir_path: String) -> Dictionary:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return {}
	var all_scenes: Array = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var file_path := dir_path + file_name
			var chunk := _load_json(file_path)
			if chunk.has("scenes"):
				all_scenes.append_array(chunk["scenes"])
			else:
				push_warning("[GameManager] scenes chunk missing 'scenes' key: " + file_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	if all_scenes.is_empty():
		return {}
	var result := {"start_scene": "cg_title", "scenes": all_scenes}
	print("[GameManager] Loaded %d scenes from %s" % [all_scenes.size(), dir_path])
	return result

func get_scene_by_id(scene_id: String) -> Dictionary:
	return _scenes_by_id.get(scene_id, {})

## 将 ports.json 的 location id（如 quanzhou）解析为 scenes.json 的港口场景 id（如 port_quanzhou）
func get_port_scene_id(port_id: String) -> String:
	if port_id.begins_with("port_"):
		return port_id
	var candidate := "port_" + port_id
	if _scenes_by_id.has(candidate):
		return candidate
	return port_id

func facility_available(fac: Dictionary) -> bool:
	return FacilityResolverScript.facility_available(fac)

func resolve_facility_scene(fac: Dictionary, port_location: String) -> String:
	return FacilityResolverScript.resolve_facility_scene(fac, port_location)

func resolve_hotspot_scene(hotspot: Dictionary, fac: Dictionary, port_location: String) -> String:
	return FacilityResolverScript.resolve_hotspot_scene(hotspot, fac, port_location)

func choice_available(choice: Dictionary) -> bool:
	return FacilityResolverScript.choice_available(choice)

func resolve_choice_style(choice: Dictionary) -> String:
	return FacilityResolverScript.resolve_choice_style(choice)

## 返回 { text, state }，state: default | quest | done
func resolve_facility_subtitle(fac: Dictionary) -> Dictionary:
	return FacilityResolverScript.resolve_facility_subtitle(fac)

func resolve_facility_icon(fac: Dictionary) -> Texture2D:
	return FacilityResolverScript.resolve_facility_icon(fac)

func get_port_data(port_id: String) -> Dictionary:
	return _ports_by_id.get(port_id, {})

func get_good_data(good_id: String) -> Dictionary:
	return _goods_by_id.get(good_id, {})

func get_npc_data(npc_id: String) -> Dictionary:
	return _npcs_by_id.get(npc_id, {})

func get_item_data(item_id: String) -> Dictionary:
	return _items_by_id.get(item_id, {})

func get_good_by_name(good_name: String) -> Dictionary:
	return _goods_by_name.get(good_name, {})

func get_text(key: String, default_text: String = "") -> String:
	return localization_data.get(key, default_text)

func get_npc_name(npc_id: String, fallback: String = "神秘人物") -> String:
	var npc: Dictionary = _npcs_by_id.get(npc_id, {})
	if not npc.is_empty():
		return npc.get("name", fallback)
	# 子串兜底：npc_id 可能是 "lin_boyuan_ship" 等变体
	for nid in _npcs_by_id:
		if nid in npc_id:
			return _npcs_by_id[nid].get("name", fallback)
	return fallback
