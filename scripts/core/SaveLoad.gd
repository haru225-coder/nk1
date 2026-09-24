extends Node
## 存档。序列化四个内核单例到 user://saves/。
##
## 写入走「先写 .tmp → 旧档改 .bak → .tmp 改正式名」：
## 中途崩溃（断电、被杀）最多丢这一次，不会把上一份好档写成半截 JSON。
## 读档时正式档解析失败自动退回 .bak。

const SAVE_DIR := "user://saves/"
const SLOTS := 3
const VERSION := 3


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot


func _tmp_path(slot: int) -> String:
	return _path(slot) + ".tmp"


func _bak_path(slot: int) -> String:
	return _path(slot) + ".bak"


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot)) or FileAccess.file_exists(_bak_path(slot))


func save_game(slot: int, current_scene: String = "") -> bool:
	var data := {
		"version": VERSION,
		"calendar": Calendar.to_dict(),
		"economy": Economy.to_dict(),
		"fleet": Fleet.to_dict(),
		"crew": Crew.to_dict(),
		"state": GameState.to_dict(),
		"scene": current_scene,
		"label": "%s　%s　%d 钱%s" % [
			Calendar.get_date_string(),
			GameManager.get_port_name(GameState.last_port),
			GameState.money,
			"" if GameState.ended == "" else "・终：" + GameState.ended,
		],
	}
	var tmp := _tmp_path(slot)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("无法写入存档 slot %d（%s）" % [slot, tmp])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	var final := _path(slot)
	if FileAccess.file_exists(final):
		# 旧档退为 .bak；改名失败不阻断，最坏只是少一份备份
		if DirAccess.rename_absolute(final, _bak_path(slot)) != OK:
			push_warning("存档 slot %d 旧档无法转为 .bak" % slot)
	if DirAccess.rename_absolute(tmp, final) != OK:
		push_error("存档 slot %d 无法从 .tmp 落位" % slot)
		return false
	return true


## 读一份 JSON 存档；文件不存在 / 解析失败 / 版本过新都返回空字典
func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("存档解析失败 %s: %s" % [path, json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("存档结构异常 %s：顶层不是对象" % path)
		return {}
	var data: Dictionary = json.data
	var ver := int(data.get("version", 0))
	if ver > VERSION:
		push_error("存档 %s 版本 %d 高于本版 %d，拒读" % [path, ver, VERSION])
		return {}
	return data


## 正式档优先，坏了退 .bak
func _read_slot(slot: int) -> Dictionary:
	var data := _read(_path(slot))
	if data.is_empty():
		var bak := _read(_bak_path(slot))
		if not bak.is_empty():
			push_warning("存档 slot %d 正式档不可用，已退回上一份备份" % slot)
		return bak
	return data


func load_game(slot: int) -> bool:
	var data := _read_slot(slot)
	if data.is_empty():
		return false

	Calendar.from_dict(data.get("calendar", {}))
	Economy.from_dict(data.get("economy", {}))
	Fleet.from_dict(data.get("fleet", {}))
	Crew.from_dict(data.get("crew", {}))
	GameState.from_dict(data.get("state", {}))
	return true


func saved_scene(slot: int) -> String:
	return str(_read_slot(slot).get("scene", ""))


func save_label(slot: int) -> String:
	if not has_save(slot):
		return "未记"
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return "卷页损了"
	return json.data.get("label", "未题")

