extends Node

signal data_loaded

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}
var events_data: Dictionary = {}
var world_events_data: Dictionary = {}
var factions_data: Dictionary = {}
var fleets_data: Dictionary = {}
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

func _ready() -> void:
	load_data()

func set_input_locked(locked: bool) -> void:
	input_locked = locked

func load_data() -> void:
	scenes_data = _load_scenes_from_directory("res://data/scenes/")
	if scenes_data.is_empty():
		# 向后兼容：如果分片目录不存在，回退到单文件
		scenes_data = _load_json("res://data/scenes.json")
	goods_data = _load_json("res://data/goods.json")
	ports_data = _load_json("res://data/ports.json")
	npcs_data = _load_json("res://data/npcs.json")
	events_data = _load_json("res://data/encounters.json")
	world_events_data = _load_json("res://data/events.json")
	factions_data = _load_json("res://data/factions.json")
	fleets_data = _load_json("res://data/fleets.json")
	localization_data = _load_json("res://data/localization/zh_cn.json")
	ui_commands_data = _load_json("res://data/ui_commands.json")
	
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
	var req: String = fac.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = fac.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	return true

func resolve_facility_scene(fac: Dictionary, port_location: String) -> String:
	var target_scene: String = fac.get("id", "")
	if target_scene.begins_with("city_"):
		var suffix := target_scene.replace("city_", "")
		target_scene = port_location + "_" + suffix
	return target_scene

func resolve_hotspot_scene(hotspot: Dictionary, fac: Dictionary, port_location: String) -> String:
	var explicit: String = hotspot.get("scene_id", "")
	if explicit != "":
		return explicit
	return resolve_facility_scene(fac, port_location)

func choice_available(choice: Dictionary) -> bool:
	var req: String = choice.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = choice.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	return true

func resolve_choice_style(choice: Dictionary) -> String:
	var style: String = choice.get("choice_style", "")
	if style != "":
		return style
	if choice.get("next", "") == "world_map":
		return "sail"
	return "default"

## 返回 { text, state }，state: default | quest | done
func resolve_facility_subtitle(fac: Dictionary) -> Dictionary:
	var subtitle = fac.get("subtitle", "点击进入")
	if subtitle is String:
		return {"text": subtitle, "state": "default"}
	if subtitle is Dictionary:
		var default_text: String = subtitle.get("default", "点击进入")
		for rule in subtitle.get("rules", []):
			if _subtitle_rule_matches(rule):
				return {
					"text": rule.get("text", default_text),
					"state": rule.get("state", "default"),
				}
		return {
			"text": default_text,
			"state": subtitle.get("state", "default"),
		}
	return {"text": str(subtitle), "state": "default"}

func _subtitle_rule_matches(rule: Dictionary) -> bool:
	var req: String = rule.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = rule.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	return true

const _FACILITY_ICON_THUMB_DIR := "res://assets/icons_128/"

func resolve_facility_icon(fac: Dictionary) -> Texture2D:
	var configured: String = fac.get("icon", "")
	if configured != "":
		var tex := AssetPlaceholder.load_texture(configured, "texture")
		if tex:
			return tex

	var fac_id: String = fac.get("id", "")
	var keys: Array[String] = []
	if fac_id.begins_with("city_"):
		keys.append(fac_id.replace("city_", ""))
	if fac_id.contains("exam") or fac_id.contains("school"):
		keys.append("exam")
	if fac_id.contains("temple"):
		keys.append("residence")
	if fac_id.contains("wharf") or fac_id.contains("ship") or fac_id.contains("canal"):
		keys.append("shipyard")
	if fac_id.contains("market"):
		keys.append("market")
	if fac_id.contains("inn"):
		keys.append("inn")
	if fac_id.contains("tavern") or fac_id.contains("tea"):
		keys.append("tavern")
	if fac_id.contains("guild"):
		keys.append("guild")
	if fac_id.contains("yamen"):
		keys.append("yamen")
	if fac_id.contains("taixue"):
		keys.append("exam")
	keys.append(fac_id)

	var seen: Dictionary = {}
	for key in keys:
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		for folder: String in [_FACILITY_ICON_THUMB_DIR, "res://assets/"]:
			var path: String = folder + "icon_" + key + "_koei.png"
			var tex := AssetPlaceholder.load_texture(path, "texture")
			if tex:
				return tex

	return AssetPlaceholder.load_texture("res://assets/icon_market_koei.png", "texture")

func get_port_data(port_id: String) -> Dictionary:
	return _ports_by_id.get(port_id, {})

func get_good_data(good_id: String) -> Dictionary:
	return _goods_by_id.get(good_id, {})

func get_good_by_name(good_name: String) -> Dictionary:
	return _goods_by_name.get(good_name, {})

func get_text(key: String, default_text: String = "") -> String:
	return localization_data.get(key, default_text)
