extends Node

signal save_completed(slot: int, success: bool)
signal load_completed(slot: int, success: bool, data: Dictionary)

const CURRENT_VERSION := 2
const MAX_SLOTS := 4
const QUICK_SLOT := 0
const SAVE_PATH_TEMPLATE := "user://nk1_save_%d.json"
const TEMP_PATH_TEMPLATE := 'user://nk1_save_%d.tmp'
const BACKUP_PATH_TEMPLATE := 'user://nk1_save_%d.bak'

var _current_scene_id: String = "cg_title"
var _active_save_path_template := SAVE_PATH_TEMPLATE
var _active_temp_path_template := TEMP_PATH_TEMPLATE
var _active_backup_path_template := BACKUP_PATH_TEMPLATE

func set_current_scene_id(scene_id: String) -> void:
	_current_scene_id = scene_id

func _save_path(slot: int) -> String:
	return _active_save_path_template % slot

func _temp_path(slot: int) -> String:
	return _active_temp_path_template % slot

func _backup_path(slot: int) -> String:
	return _active_backup_path_template % slot

func _set_test_path_stem(stem: String) -> void:
	if not OS.is_debug_build() or stem.is_empty():
		return
	_active_save_path_template = 'user://' + stem + '_%d.json'
	_active_temp_path_template = 'user://' + stem + '_%d.tmp'
	_active_backup_path_template = 'user://' + stem + '_%d.bak'

func _reset_path_templates() -> void:
	_active_save_path_template = SAVE_PATH_TEMPLATE
	_active_temp_path_template = TEMP_PATH_TEMPLATE
	_active_backup_path_template = BACKUP_PATH_TEMPLATE

func quick_save() -> bool:
	return save_game(QUICK_SLOT)

func quick_load() -> bool:
	return load_game(QUICK_SLOT)

func has_save(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	return not _read_save_file(slot).is_empty()

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
	var final_path := _save_path(slot)
	var temp_path := _temp_path(slot)
	var backup_path := _backup_path(slot)
	if not _remove_file_if_present(temp_path):
		return _complete_save(slot, false, '无法清理临时存档: ' + temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _complete_save(slot, false, '无法写入临时存档: ' + temp_path)
	file.store_string(json_str)
	file.flush()
	file.close()
	if _read_valid_save_path(temp_path).is_empty():
		_remove_file_if_present(temp_path)
		return _complete_save(slot, false, '临时存档校验失败: ' + temp_path)

	var final_is_valid := not _read_valid_save_path(final_path).is_empty()
	var rotated_final := false
	if final_is_valid:
		if not _remove_file_if_present(backup_path):
			_remove_file_if_present(temp_path)
			return _complete_save(slot, false, '无法轮换备份: ' + backup_path)
		var rotate_err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(final_path),
			ProjectSettings.globalize_path(backup_path)
		)
		if rotate_err != OK:
			_remove_file_if_present(temp_path)
			return _complete_save(slot, false, '无法轮换正式存档: ' + str(rotate_err))
		rotated_final = true
	elif FileAccess.file_exists(final_path):
		if not _remove_file_if_present(final_path):
			_remove_file_if_present(temp_path)
			return _complete_save(slot, false, '无法替换损坏存档: ' + final_path)

	var promote_err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(final_path)
	)
	if promote_err != OK:
		if rotated_final:
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(final_path)
			)
		_remove_file_if_present(temp_path)
		return _complete_save(slot, false, '无法提交正式存档: ' + str(promote_err))
	save_completed.emit(slot, true)
	return true

func _complete_save(slot: int, success: bool, message: String = '') -> bool:
	if not success and message != '':
		push_error('[SaveManager] ' + message)
	save_completed.emit(slot, success)
	return success

func _remove_file_if_present(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return err == OK

func _restore_backup_to_final(slot: int, data: Dictionary) -> bool:
	var temp_path := _temp_path(slot)
	var final_path := _save_path(slot)
	if not _remove_file_if_present(temp_path):
		return false
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, '\t'))
	file.flush()
	file.close()
	if _read_valid_save_path(temp_path).is_empty():
		_remove_file_if_present(temp_path)
		return false
	if FileAccess.file_exists(final_path) and not _remove_file_if_present(final_path):
		_remove_file_if_present(temp_path)
		return false
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(final_path)
	)
	if err != OK:
		_remove_file_if_present(temp_path)
		return false
	return true

func load_game(slot: int = 0) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		load_completed.emit(slot, false, {"msg": "无效存档槽。"})
		return false

	# 读档时清空幂等守卫，避免旧记录干扰新存档
	IdempotencyGuard.clear_all()

	var data := _read_valid_save_path(_save_path(slot))
	var recovered_from_backup := false
	if data.is_empty():
		data = _read_valid_save_path(_backup_path(slot))
		if not data.is_empty():
			recovered_from_backup = true
			_restore_backup_to_final(slot, data)
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
	CargoSystem.sanitize_after_load()
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
	result['recovered_from_backup'] = recovered_from_backup
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
	var success := true
	for path in [_save_path(slot), _temp_path(slot), _backup_path(slot)]:
		var global_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(global_path):
			continue
		var err := DirAccess.remove_absolute(global_path)
		if err != OK:
			push_error('[SaveManager] 删除失败: ' + path + ' err=' + str(err))
			success = false
	return success

func _read_save_file(slot: int) -> Dictionary:
	var data := _read_valid_save_path(_save_path(slot))
	if not data.is_empty():
		return data
	return _read_valid_save_path(_backup_path(slot))

func _read_valid_save_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_str := file.get_as_text()
	file.close()
	if json_str.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(json_str) != OK:
		return {}
	var raw: Variant = parser.data
	if not raw is Dictionary:
		return {}
	var data := (raw as Dictionary).duplicate(true)
	var version := int(data.get('save_version', 0))
	if version <= 0 or version > CURRENT_VERSION:
		return {}
	for core_key in ['game_state', 'ledger', 'cargo']:
		if not data.get(core_key) is Dictionary:
			return {}
	data = _migrate_save_data(data)
	if not data.get('world_events') is Dictionary:
		return {}
	return data

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
