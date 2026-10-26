extends RefCounted
## 船型插画（船屋坞位、船谱、船籍簿旗舰）。只作展示，不改船的数值。
## 海战精灵不走这里：CombatFx 按 res://assets/ship_<id>.png 取，缺图回落 ship_fu / ship_falcon。
## 插画优先 data/ships_art.json 的 plate（文件在才用），否则 plates/<id>.jpg、ship_<id>.png、ship_fu.png。
## id 空或不是合法文件名时不拼路径，交界面只留字。


const ART_JSON := "res://data/ships_art.json"
const PLATE_FMT := "res://assets/ships/plates/%s.jpg"
const SPRITE_FMT := "res://assets/ship_%s.png"
const FALLBACK_PLATE := "res://assets/ship_fu.png"

static var _ships: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}


static func _table() -> Dictionary:
	if _loaded:
		return _ships
	_loaded = true
	if not FileAccess.file_exists(ART_JSON):
		return _ships
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ART_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _ships
	var rows = (parsed as Dictionary).get("ships", {})
	if typeof(rows) == TYPE_DICTIONARY:
		_ships = rows
	return _ships


## 这一型此刻用哪张图。空串表示没有，调用方不要挂空框。
static func plate_path(type_id: String) -> String:
	var tid := type_id.strip_edges()
	if tid == "" or not tid.is_valid_filename():
		return ""
	var row = _table().get(tid, {})
	if typeof(row) == TYPE_DICTIONARY:
		var listed := str((row as Dictionary).get("plate", ""))
		if listed != "" and FileAccess.file_exists(listed):
			return listed
	var plate := PLATE_FMT % tid
	if FileAccess.file_exists(plate):
		return plate
	var sprite := SPRITE_FMT % tid
	if FileAccess.file_exists(sprite):
		return sprite
	if FileAccess.file_exists(FALLBACK_PLATE):
		return FALLBACK_PLATE
	return ""


static func texture(type_id: String) -> Texture2D:
	var path := plate_path(type_id)
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var tex := GameManager.load_texture(path)
	if tex != null:
		_cache[path] = tex
	return tex


## 坞位大图、船谱小图。没有这型的画就不挂框。
static func mount_plate(body: VBoxContainer, type_id: String, tall: int) -> void:
	var tex := texture(type_id)
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.name = "ShipPlate"
	rect.texture = tex
	rect.custom_minimum_size = Vector2(448, tall)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rect)


## 船谱：本章已到的船型，或已经在册的（夺来的快船未到章也入谱）。不售的写明坞外不卖。
static func mount_codex(main: Control, catalog: Array, reached: PackedStringArray) -> void:
	var owned := {}
	for raw_hull in Fleet.ships:
		if typeof(raw_hull) != TYPE_DICTIONARY:
			continue
		var owned_id := str((raw_hull as Dictionary).get("type", ""))
		if owned_id != "":
			owned[owned_id] = true
	var rows: Array = []
	for raw_ship in catalog:
		if typeof(raw_ship) != TYPE_DICTIONARY:
			continue
		var ship_row: Dictionary = raw_ship
		var ship_id := str(ship_row.get("id", ""))
		if ship_id == "":
			continue
		var unlock := str(ship_row.get("unlock", "ch1"))
		if unlock == "":
			unlock = "ch1"
		if not reached.has(unlock) and not bool(owned.get(ship_id, false)):
			continue
		rows.append(ship_row)
	if rows.is_empty():
		return
	var slip: VBoxContainer = main._slip_body()
	main._slip_title(slip, "船谱", "本章见过、或已在册的船")
	for raw_row in rows:
		var row: Dictionary = raw_row
		mount_plate(slip, str(row.get("id", "")), 200)
		var nm := str(row.get("name", "船"))
		var cls := str(row.get("class", ""))
		main._slip_note(slip, nm if cls == "" else "%s　%s" % [nm, cls], UiTheme.TEXT)
		if row.get("for_sale", true) == false:
			main._slip_note(slip, "坞外不售。海上夺来的才入籍。")
		else:
			var hist := str(row.get("historical_note", ""))
			if hist != "":
				main._slip_note(slip, hist)
