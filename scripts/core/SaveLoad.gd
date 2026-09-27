extends Node
## 存档。序列化四个内核单例到 user://saves/。
##
## 写入走「先写 .tmp → 旧档改 .bak → .tmp 改正式名」：
## 中途崩溃（断电、被杀）最多丢这一次，不会把上一份好档写成半截 JSON。
## 读档时正式档解析失败自动退回 .bak。

const SAVE_DIR := "user://saves/"
const SLOTS := 3
const VERSION := 3
## Save-critical progression flags. Keep these names stable across UI/page remaps.
const EXAM_FLAG := "exam_sat"
const EXAM_FLAG_PREFIX := "exam_sat_ch"
const GUILD_FLAG_PREFIX := "guild_"
const DISCOVERY_LIST_KEYS := ["discoveries_found", "discoveries_reported"]
## 四个内核单例分区；读档前逐一体检，非对象或关键结构不合法即判坏档。
const PARTITIONS := ["calendar", "economy", "fleet", "crew"]
const STATE_NUM_KEYS := [
	"money", "debt", "fame", "martial", "chapter", "pu_attention", "peak_money",
	"network", "merchant_credit", "sea_tendency", "scholar_tendency", "hometown_tendency",
	"draft_salt", "shore_salt", "broker_salt", "berth_index", "era_trips", "era_profit",
]


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
		"state": _harden_state(GameState.to_dict()),
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


## 保存/读档的剧情关键字段要经过同一层清洗。
## 旧档可能来自早期原型或手改 JSON：旗标必须是 true，发现录必须是去重字符串。
## discoveries_reported 胜过 discoveries_found，避免坏档重复领赏。
func _harden_state(raw: Dictionary) -> Dictionary:
	var state: Dictionary = raw.duplicate(true)
	state["flags"] = _normalise_flags(state.get("flags", {}))
	var reported := _normalise_ids(state.get("discoveries_reported", []))
	var reported_set := {}
	for did in reported:
		reported_set[did] = true
	var found := []
	for did in _normalise_ids(state.get("discoveries_found", [])):
		if not reported_set.has(did):
			found.append(did)
	state["discoveries_found"] = found
	state["discoveries_reported"] = reported
	return state


func _normalise_flags(raw) -> Dictionary:
	var clean := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return clean
	for key in raw.keys():
		var flag := str(key).strip_edges()
		if not _valid_flag_name(flag) or typeof(raw.get(key)) != TYPE_BOOL:
			continue
		if not raw.get(key):
			continue
		clean[flag] = true
	return clean


func _valid_flag_name(flag: String) -> bool:
	if flag == "":
		return false
	if flag == EXAM_FLAG:
		return true
	if flag.begins_with(EXAM_FLAG_PREFIX):
		var chapter_text: String = flag.substr(EXAM_FLAG_PREFIX.length())
		return chapter_text.is_valid_int() and int(chapter_text) > 0
	if flag.begins_with(GUILD_FLAG_PREFIX):
		return flag.length() > GUILD_FLAG_PREFIX.length()
	return true


func _normalise_ids(raw) -> Array:
	var clean: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return clean
	for value in raw:
		if typeof(value) != TYPE_STRING:
			continue
		var did: String = value.strip_edges()
		if did != "" and not (did in clean):
			clean.append(did)
	return clean


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
	var ver_raw = data.get("version", 0)
	if not _is_num(ver_raw):
		push_error("存档结构异常 %s：version 不是数字" % path)
		return {}
	var ver := int(ver_raw)
	if ver > VERSION:
		push_error("存档 %s 版本 %d 高于本版 %d，拒读" % [path, ver, VERSION])
		return {}
	var bad := _check_partitions(data)
	if bad != "":
		push_error("存档结构异常 %s：%s" % [path, bad])
		return {}
	return data


func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## 字段缺省可以（from_dict 有默认值）；给了却类型不对才算坏。
func _bad_fields(part: Dictionary, nums: Array, dicts: Array, arrays: Array = []) -> String:
	for k in nums:
		if part.has(k) and not _is_num(part[k]):
			return "%s 不是数字" % k
	for k in dicts:
		if part.has(k) and typeof(part[k]) != TYPE_DICTIONARY:
			return "%s 不是对象" % k
	for k in arrays:
		if part.has(k) and typeof(part[k]) != TYPE_ARRAY:
			return "%s 不是数组" % k
	return ""


## 四分区 + state 的结构体检；返回空串为好档，否则为坏因。
## 放在 _read 里：正式档结构坏与 JSON 坏同等对待，_read_slot 自然退 .bak。
func _check_partitions(data: Dictionary) -> String:
	for key in PARTITIONS + ["state"]:
		if data.has(key) and typeof(data[key]) != TYPE_DICTIONARY:
			return "%s 分区不是对象" % key

	var cal: Dictionary = _as_dict(data.get("calendar", {}))
	if not cal.is_empty():
		for k in ["year", "month", "day"]:
			if not _is_num(cal.get(k)):
				return "calendar.%s 缺失或不是数字" % k
		if int(cal["month"]) < 1 or int(cal["month"]) > Calendar.MONTHS_PER_YEAR:
			return "calendar.month 越界"
		if int(cal["day"]) < 1 or int(cal["day"]) > Calendar.DAYS_PER_MONTH:
			return "calendar.day 越界"

	var eco: Dictionary = _as_dict(data.get("economy", {}))
	var why := _bad_fields(eco, ["tariff", "broker"], ["rates", "investments"])
	if why != "":
		return "economy." + why

	var fleet: Dictionary = _as_dict(data.get("fleet", {}))
	why = _bad_fields(fleet, ["water", "food", "morale", "mutiny_cooldown"], ["cargo"])
	if why != "":
		return "fleet." + why
	if fleet.has("ships"):
		if typeof(fleet["ships"]) != TYPE_ARRAY:
			return "fleet.ships 不是数组"
		for s in fleet["ships"]:
			if typeof(s) != TYPE_DICTIONARY:
				return "fleet.ships 含非对象条目"

	var crew: Dictionary = _as_dict(data.get("crew", {}))
	why = _bad_fields(crew, ["unpaid_months"], ["hired"])
	if why != "":
		return "crew." + why
	for r in _as_dict(crew.get("hired", {})).values():
		if typeof(r) != TYPE_DICTIONARY:
			return "crew.hired 含非对象条目"

	# GameState.from_dict 直赋强类型字段；flags / 发现录另由 _harden_state 清洗，contract 经无类型局部量判型。
	# rumors / contract_ban 虽在赋值后判型，但强类型变量赋错型当场抛 SCRIPT ERROR，兜底来不及，须在此拦。
	var state: Dictionary = _as_dict(data.get("state", {}))
	why = _bad_fields(state, STATE_NUM_KEYS, ["era_routes", "port_bans", "siege", "rumors", "contract_ban"],
			["ledger_notes", "visited_ports", "news_seen", "crew_history"])
	if why != "":
		return "state." + why
	if state.has("has_customs_permit") and typeof(state["has_customs_permit"]) != TYPE_BOOL:
		return "state.has_customs_permit 不是布尔"
	if state.has("last_port") and typeof(state["last_port"]) != TYPE_STRING:
		return "state.last_port 不是字符串"
	return ""


## 正式档优先，坏了退 .bak
func _read_slot(slot: int) -> Dictionary:
	var data := _read(_path(slot))
	if data.is_empty():
		var bak := _read(_bak_path(slot))
		if not bak.is_empty():
			push_warning("存档 slot %d 正式档不可用，已退回上一份备份" % slot)
		return bak
	return data


func _as_dict(raw) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func load_game(slot: int) -> bool:
	var data := _read_slot(slot)
	if data.is_empty():
		return false

	# _read 已体检过结构；这里仍按 Dictionary 兜底，缺省分区用空表。
	Calendar.from_dict(_as_dict(data.get("calendar", {})))
	Economy.from_dict(_as_dict(data.get("economy", {})))
	Fleet.from_dict(_as_dict(data.get("fleet", {})))
	Crew.from_dict(_as_dict(data.get("crew", {})))
	var state: Dictionary = _as_dict(data.get("state", {}))
	GameState.from_dict(_harden_state(state))
	return true


func saved_scene(slot: int) -> String:
	return str(_read_slot(slot).get("scene", ""))


## 卷页从哪一份翻出：none 无档 / primary 正本可读 / bak 正本不可用、副抄可读 / corrupt 两份皆读不出。
## 只读查询，不改文件；给航海日志册页挂脚注用。
func slot_source(slot: int) -> String:
	if not has_save(slot):
		return "none"
	if not _read(_path(slot)).is_empty():
		return "primary"
	if not _read(_bak_path(slot)).is_empty():
		return "bak"
	return "corrupt"


## 册页脚注：正本无恙时为空串；长提示不塞进 save_label。
func save_tip(slot: int) -> String:
	match slot_source(slot):
		"bak":
			return "正本卷页损了，已从副抄翻出。"
		"corrupt":
			return "正本与副抄皆不可读。"
	return ""


func save_label(slot: int) -> String:
	if not has_save(slot):
		return "未记"
	# 与 has_save / load_game 一致：正式档坏了读 .bak，避免空 FileAccess 崩日志页。
	var data := _read_slot(slot)
	if data.is_empty():
		return "卷页损了"
	return str(data.get("label", "未题"))

