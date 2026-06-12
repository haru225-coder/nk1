extends Node

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	scenes_data = _load_json("res://data/scenes.json")
	goods_data = _load_json("res://data/goods.json")
	ports_data = _load_json("res://data/ports.json")
	npcs_data = _load_json("res://data/npcs.json")
	
	if scenes_data.has("scenes"):
		print("Data loaded successfully. Scenes:", scenes_data.get("scenes", []).size())

func _load_json(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		var parse_result = json.parse(file.get_as_text())
		if parse_result == OK:
			return json.data
		else:
			print("JSON Parse Error in ", path, ": ", json.get_error_message())
	else:
		print("Error: Could not find ", path)
	return {}

func get_scene_by_id(scene_id: String) -> Dictionary:
	var scenes = scenes_data.get("scenes", [])
	for s in scenes:
		if s.get("id") == scene_id:
			return s
	return {}
