extends Node

signal save_completed(slot: int, success: bool)
signal load_completed(slot: int, success: bool, data: Dictionary)

const CURRENT_VERSION := 1
const MAX_SLOTS := 5
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

	var path := _save_path(slot)
	if not FileAccess.file_exists(path):
		load_completed.emit(slot, false, {"msg": "无存档。"})
		return false

	var json_str := FileAccess.get_file_as_string(path)
	if json_str.is_empty():
		load_completed.emit(slot, false, {"msg": "读取存档失败。"})
		return false

	var raw: Variant = JSON.parse_string(json_str)
	if raw == null or not raw is Dictionary:
		load_completed.emit(slot, false, {"msg": "存档格式损坏。"})
		return false

	var data: Dictionary = _migrate_save_data(raw)
	var version := int(data.get("save_version", 0))
	if version <= 0 or version > CURRENT_VERSION:
		load_completed.emit(slot, false, {"msg": "存档版本不兼容。"})
		return false

	GameState.from_save_dict(data.get("game_state", {}))
	LedgerSystem.from_save_dict(data.get("ledger", {}))
	CargoSystem.from_save_dict(data.get("cargo", {}))

	var scene_id: String = data.get("current_scene_id", "cg_title")
	_current_scene_id = scene_id

	var result := {
		"current_scene_id": scene_id,
		"timestamp": data.get("timestamp", ""),
		"save_version": version,
		"balance": LedgerSystem.get_balance(),
	}
	load_completed.emit(slot, true, result)
	return true

func get_save_info(slot: int = 0) -> Dictionary:
	if not has_save(slot):
		return {}

	var path := _save_path(slot)
	var json_str := FileAccess.get_file_as_string(path)
	if json_str.is_empty():
		return {}

	var raw: Variant = JSON.parse_string(json_str)
	if raw == null or not raw is Dictionary:
		return {}

	var data: Dictionary = _migrate_save_data(raw)
	var ledger: Dictionary = data.get("ledger", {})
	return {
		"slot": slot,
		"save_version": data.get("save_version", 0),
		"timestamp": data.get("timestamp", ""),
		"current_scene_id": data.get("current_scene_id", ""),
		"balance": int(ledger.get("balance", 0)),
	}

func _migrate_save_data(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version < CURRENT_VERSION:
		# Reserved for future version upgrades (e.g. 1 -> 2).
		pass
	return data