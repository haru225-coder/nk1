extends Node

signal save_completed(slot: int, success: bool)
signal load_completed(slot: int, success: bool, data: Dictionary)

const CURRENT_VERSION := 2
const MAX_SLOTS := 4
const QUICK_SLOT := 0
const SAVE_PATH_TEMPLATE := "user://nk1_save_%d.json"

var _current_scene_id: String = "cg_title"

func set_current_scene_id(scene_id: String) -> void:
	_current_scene_id = scene_id

func _save_path(slot: int) -> String:
	return SAVE_PATH_TEMPLATE % slot

func quick_save() -> bool:
	return save_game(QUICK_SLOT)

func quick_load() -> bool:
	return load_game(QUICK_SLOT)

func has_save(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	return FileAccess.file_exists(_save_path(slot))

func save_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		save_completed.emit(slot, false)
		return false

	var data := {
		"save_version": CURRENT_VERSION,
		"timestamp": Time.get_datetime_string_from_system(true),
		"current_scene_id": _current_scene_id,
		"game_state": GameState.to_save_dict(),
		"ledger": LedgerSystem.to_save_dict(),
		"cargo": CargoSystem.to_save_dict(),
		"world_events": WorldEventTracker.to_save_dict(),
	}

	var json_str := JSON.stringify(data, "\t")
	var path := _save_path(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 写入失败: " + path)
		save_completed.emit(slot, false)
		return false
	f.store_string(json_str)
	f.close()
	save_completed.emit(slot, true)
	return true

func load_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		load_completed.emit(slot, false, {"msg": "无效存档槽。"})
		return false

	# 读档时清空幂等守卫，避免旧记录干扰新存档
	IdempotencyGuard.clear_all()

	var data := _read_save_file(slot)
	if data.is_empty():
		load_completed.emit(slot, false, {"msg": "无存档。"})
		return false

	var version := int(data.get("save_version", 0))
	if version <= 0 or version > CURRENT_VERSION:
		load_completed.emit(slot, false, {"msg": "存档版本不兼容。"})
		return false

	GameState.from_save_dict(data.get("game_state", {}))
	LedgerSystem.from_save_dict(data.get("ledger", {}))
	CargoSystem.from_save_dict(data.get("cargo", {}))
	WorldEventTracker.from_save_dict(data.get("world_events", {}))

	# strengthen consistency after load (for old saves and state sync)
	var m = GameState.market
	if m:
		if m.port_stocks.is_empty() and GameManager.ports_data and GameManager.goods_data:
			m.init_from_ports(GameManager.ports_data.get("ports", []), GameManager.goods_data.get("goods", []))
		_validate_and_sync_world_events()

	var scene_id: String = data.get("current_scene_id", "cg_title")
	_current_scene_id = scene_id

	var result := _build_save_info(slot, data)
	result["balance"] = LedgerSystem.get_balance()
	load_completed.emit(slot, true, result)
	return true

func get_save_info(slot: int = 0) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS:
		return {"slot": slot, "exists": false}
	if not has_save(slot):
		return {"slot": slot, "exists": false}
	var data := _read_save_file(slot)
	if data.is_empty():
		return {"slot": slot, "exists": false}
	return _build_save_info(slot, data)

func get_all_saves_info() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(MAX_SLOTS):
		if has_save(slot):
			var data := _read_save_file(slot)
			if data.is_empty():
				result.append({"slot": slot, "exists": false})
			else:
				result.append(_build_save_info(slot, data))
		else:
			result.append({"slot": slot, "exists": false})
	return result

func delete_save(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return true
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[SaveManager] 删除失败: " + path + " err=" + str(err))
		return false
	return true

func _read_save_file(slot: int) -> Dictionary:
	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var json_str := FileAccess.get_file_as_string(path)
	if json_str.is_empty():
		return {}
	var raw: Variant = JSON.parse_string(json_str)
	if raw == null or not raw is Dictionary:
		return {}
	return _migrate_save_data(raw)

func _build_save_info(slot: int, data: Dictionary) -> Dictionary:
	var ledger: Dictionary = data.get("ledger", {})
	var game_state: Dictionary = data.get("game_state", {})
	var scene_id: String = data.get("current_scene_id", "")
	return {
		"slot": slot,
		"exists": true,
		"timestamp": _format_timestamp(data.get("timestamp", "")),
		"current_scene_id": scene_id,
		"current_location_name": _resolve_location_name(scene_id, game_state),
		"balance": int(ledger.get("balance", 0)),
		"save_version": data.get("save_version", 0),
	}

func _resolve_location_name(scene_id: String, game_state: Dictionary) -> String:
	var nav: Dictionary = game_state.get("navigation", {})
	var port_id: String = nav.get("last_port", "")
	if port_id != "":
		var port_data := GameManager.get_port_data(port_id)
		if not port_data.is_empty():
			return port_data.get("name", port_id)
	if scene_id.begins_with("port_"):
		var pid := scene_id.replace("port_", "")
		var port_data := GameManager.get_port_data(pid)
		if not port_data.is_empty():
			return port_data.get("name", pid)
	var scene_data := GameManager.get_scene_by_id(scene_id)
	if not scene_data.is_empty():
		return scene_data.get("title", scene_id)
	match scene_id:
		"world_map":
			return "海上"
		"cg_title":
			return "标题画面"
		_:
			return scene_id

func _format_timestamp(ts: String) -> String:
	if ts == "":
		return ""
	var s := ts.replace("T", " ")
	if s.length() > 16:
		return s.substr(0, 16)
	return s

func _migrate_save_data(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version < 2:
		# Add world_events for pre full world event saves (compatibility)
		if not data.has("world_events"):
			data["world_events"] = {
				"active_events": [],
				"triggered_events": {},
				"port_triggered": {},
				"cooldowns": {},
				"version": 1
			}
		# Ensure game_state.market.upcoming_events exists for old saves
		var gs = data.get("game_state", {})
		if not gs.has("market") or not gs["market"] is Dictionary:
			gs["market"] = {
				"port_stocks": {},
				"upcoming_events": []
			}
		else:
			var market_dict: Dictionary = gs["market"]
			if not market_dict.has("upcoming_events") or not market_dict["upcoming_events"] is Array:
				market_dict["upcoming_events"] = []
			gs["market"] = market_dict
		data["game_state"] = gs
	return data


func _validate_and_sync_world_events() -> void:
	var m = GameState.market
	if m == null:
		return
	var active_list = WorldEventTracker.get_active_events()
	var clean_upcoming: Array[Dictionary] = []
	for item in m.upcoming_events:
		var e = item.get("event") as BaseEconomicEvent
		if e == null:
			continue
		var is_duplicate := false
		for ae in active_list:
			if ae != null and ae.event_id == e.event_id and ae.target_port == e.target_port:
				is_duplicate = true
				break
		if not is_duplicate:
			clean_upcoming.append(item)
	m.upcoming_events = clean_upcoming