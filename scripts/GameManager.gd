extends Node
## 数据加载与全局时间推进中枢。
## 时间推进走 advance_days() 这一个入口，避免各系统各自监听信号导致结算顺序不确定。

signal day_advanced(y: int, m: int, d: int)

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}
var discoveries_data: Dictionary = {}
var ships_data: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	scenes_data = _load_json("res://data/scenes.json")
	goods_data = _load_json("res://data/goods.json")
	ports_data = _load_json("res://data/ports.json")
	npcs_data = _load_json("res://data/npcs.json")
	discoveries_data = _load_json("res://data/discoveries.json")
	ships_data = _load_json("res://data/ships.json")

	if scenes_data.has("scenes"):
		print("Data loaded. Scenes:%d Goods:%d Ports:%d Ships:%d" % [
			scenes_data.get("scenes", []).size(),
			goods_data.get("goods", []).size(),
			ports_data.get("ports", []).size(),
			ships_data.get("ships", []).size(),
		])


func _load_json(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		var parse_result = json.parse(file.get_as_text())
		if parse_result == OK:
			return json.data
		else:
			push_error("JSON Parse Error in %s: %s (line %d)" % [path, json.get_error_message(), json.get_error_line()])
	else:
		push_error("Could not find " + path)
	return {}


# ── 时间推进 ──────────────────────────────────────────

## 全局唯一的日推进入口。所有按日结算的系统在此依次结算。
func advance_days(n: int) -> void:
	for i in range(n):
		var prev_month: int = Calendar.month
		Calendar.advance_days(1)
		if Calendar.month != prev_month:
			GameState.accrue_interest()
		Economy.on_day_passed()
		Fleet.on_day_passed()
		day_advanced.emit(Calendar.year, Calendar.month, Calendar.day)


# ── 查询 ──────────────────────────────────────────────

func get_scene_by_id(scene_id: String) -> Dictionary:
	for s in scenes_data.get("scenes", []):
		if s.get("id") == scene_id:
			return s
	return {}


# 按 id 查询发现物（航路复核、碑拓证据等）
func get_discovery_by_id(discovery_id: String) -> Dictionary:
	for d in discoveries_data.get("discoveries", []):
		if d.get("id") == discovery_id:
			return d
	return {}


func get_good_by_id(good_id: String) -> Dictionary:
	for g in goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g
	return {}


func get_good_name(good_id: String) -> String:
	return get_good_by_id(good_id).get("name", good_id)


func get_port_by_id(port_id: String) -> Dictionary:
	for p in ports_data.get("ports", []):
		if p.get("id") == port_id:
			return p
	return {}


func get_port_name(port_id: String) -> String:
	return get_port_by_id(port_id).get("name", port_id)


## 当前章节下已解锁的港口定义列表
func unlocked_ports() -> Array:
	var out := []
	for p in ports_data.get("ports", []):
		if GameState.is_chapter_reached(p.get("unlock", "ch1")):
			out.append(p)
	return out
