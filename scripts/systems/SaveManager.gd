class_name SaveManager extends RefCounted

const SAVE_PATH := "user://save.json"

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func save_game(current_scene_id: String) -> bool:
	var data := {
		"version": 1,
		"current_scene_id": current_scene_id,
		"fleet": GameState.fleet.to_dict(),
		"survival": GameState.survival.to_dict(),
		"trade": GameState.trade.to_dict(),
		"story": GameState.story.to_dict(),
		"navigation": GameState.navigation.to_dict(),
		"market": GameState.market.to_dict(),
		"ledger": LedgerSystem.to_dict(),
		"cargo": CargoSystem.to_dict(),
	}
	var json_str := JSON.stringify(data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 写入失败: " + SAVE_PATH)
		return false
	f.store_string(json_str)
	f.close()
	return true

static func load_game() -> Dictionary:
	if not has_save():
		return {"success": false, "msg": "无存档。"}
	var json_str := FileAccess.get_file_as_string(SAVE_PATH)
	if json_str.is_empty():
		return {"success": false, "msg": "读取存档失败。"}
	var d: Variant = JSON.parse_string(json_str)
	if d == null or not d is Dictionary:
		return {"success": false, "msg": "存档格式损坏。"}
	if d.get("version", 0) != 1:
		return {"success": false, "msg": "存档版本不兼容。"}
	# 恢复状态
	GameState.fleet.from_dict(d.get("fleet", {}))
	GameState.survival.from_dict(d.get("survival", {}))
	GameState.trade.from_dict(d.get("trade", {}))
	GameState.story.from_dict(d.get("story", {}))
	GameState.navigation.from_dict(d.get("navigation", {}))
	GameState.market.from_dict(d.get("market", {}))
	LedgerSystem.from_dict(d.get("ledger", {}))
	CargoSystem.from_dict(d.get("cargo", {}))
	return {"success": true, "scene_id": d.get("current_scene_id", "cg_title")}
