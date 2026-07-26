extends Node
## 存档。序列化四个内核单例到 user://saves/。

const SAVE_DIR := "user://saves/"
const SLOTS := 3
const VERSION := 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))


func save_game(slot: int, current_scene: String = "") -> bool:
	var data := {
		"version": VERSION,
		"calendar": Calendar.to_dict(),
		"economy": Economy.to_dict(),
		"fleet": Fleet.to_dict(),
		"state": GameState.to_dict(),
		"scene": current_scene,
		"label": "%s・%s・%d钱" % [
			Calendar.get_date_string(),
			GameManager.get_port_name(GameState.last_port),
			GameState.money,
		],
	}
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("无法写入存档 slot %d" % slot)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


func load_game(slot: int) -> bool:
	if not has_save(slot):
		return false
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("存档解析失败 slot %d: %s" % [slot, json.get_error_message()])
		return false
	var data: Dictionary = json.data

	Calendar.from_dict(data.get("calendar", {}))
	Economy.from_dict(data.get("economy", {}))
	Fleet.from_dict(data.get("fleet", {}))
	GameState.from_dict(data.get("state", {}))
	return true


func saved_scene(slot: int) -> String:
	if not has_save(slot):
		return ""
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return ""
	return json.data.get("scene", "")


func save_label(slot: int) -> String:
	if not has_save(slot):
		return "（空）"
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return "（损坏）"
	return json.data.get("label", "（无标签）")


func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(slot)))
