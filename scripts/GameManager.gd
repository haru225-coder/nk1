extends Node
## 数据加载与全局时间推进中枢。
## 时间推进走 advance_days() 这一个入口，避免各系统各自监听信号导致结算顺序不确定。

## 月结产生的通知（欠饷等），供 UI 显示
signal monthly_notice(text: String)

## 海战上下文。SeaChart 开战前写入；WorldMap._ready 读取；SeaChart 结算后清空。
var pending_battle: Dictionary = {}

var scenes_data: Dictionary = {}
var goods_data: Dictionary = {}
var ports_data: Dictionary = {}
var npcs_data: Dictionary = {}
var discoveries_data: Dictionary = {}
var ships_data: Dictionary = {}
var chapters_data: Dictionary = {}
var crew_data: Dictionary = {}
var port_beats: Array = []


func _ready() -> void:
	load_data()


func load_data() -> void:
	scenes_data = _load_json("res://data/scenes.json")
	goods_data = _load_json("res://data/goods.json")
	ports_data = _load_json("res://data/ports.json")
	npcs_data = _load_json("res://data/npcs.json")
	discoveries_data = _load_json("res://data/discoveries.json")
	ships_data = _load_json("res://data/ships.json")
	chapters_data = _load_json("res://data/chapters.json")
	crew_data = _load_json("res://data/crew.json")
	port_beats = _load_json("res://data/port_beats.json").get("beats", [])

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
			var notice := Crew.pay_wages()
			if notice != "":
				monthly_notice.emit(notice)
		Economy.on_day_passed()
		Fleet.on_day_passed()


# ── 资源 ──────────────────────────────────────────────

## 按文件头而非扩展名加载图片。
## assets 里有四张 .png 实际是 JPEG（icon_academy / icon_guild / icon_residence / icon_temple），
## 导入器按扩展名解码会失败，并把 .import 写成 valid=false。
## 对这种文件直接 load() 会在回退成功之前先刷一条 ERROR，港口界面每张图标都打一次。
func load_texture(path: String) -> Texture2D:
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var decoded := _texture_from_bytes(bytes)
		if decoded != null and (_header_mismatches_extension(path, bytes) or _import_marked_invalid(path)):
			return decoded
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
		return decoded
	return load(path) as Texture2D


func _import_marked_invalid(path: String) -> bool:
	var sidecar := path + ".import"
	if not FileAccess.file_exists(sidecar):
		return false
	var text := FileAccess.get_file_as_string(sidecar)
	return text.begins_with("valid=false") or text.contains("\nvalid=false")


func _header_mismatches_extension(path: String, bytes: PackedByteArray) -> bool:
	if bytes.size() < 3:
		return false
	var ext := path.get_extension().to_lower()
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return ext != "jpg" and ext != "jpeg"
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		return ext != "png"
	if bytes[0] == 0x57 and bytes[1] == 0x45:
		return ext != "webp"
	return false


func _texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 8:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:                       # JPEG: FF D8
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E:  # PNG: 89 50 4E 47
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x57 and bytes[1] == 0x45:                     # WEBP: WE(BP)
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


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
