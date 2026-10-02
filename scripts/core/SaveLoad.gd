extends Node
## 存档。序列化四个内核单例到 user://saves/。
##
## 写入走「先写 .tmp → 旧档改 .bak → .tmp 改正式名」：
## 中途崩溃（断电、被杀）最多丢这一次，不会把上一份好档写成半截 JSON。
## 读档时正式档解析失败自动退回 .bak。
##
## 结构版本（save_schema）：缺省视为 v1。低于本版走 _migrate_vN_to_vN+1 链，
## load_game 迁完回写正式档、原件另存 <档名>.v<N>；高于本版（更新的游戏写的）明确拒读，
## 不退 .bak——副抄多半也是同一新版写的，静默退回只会把人带回更旧的进度且看不出缘由。

const SAVE_DIR := "user://saves/"
const SLOTS := 3
## 旧读档器认的头：旧版只拒 version > 3。结构兼容的改动只升 SAVE_SCHEMA，旧版仍能照读新档；
## 哪天结构真的不兼容，两者同升，让旧版也拒。（v3 → v4：crew.hired 快照收成 id 即此例）
const VERSION := 4
const SAVE_SCHEMA := 4
const SCHEMA_KEY := "save_schema"
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
## state 容器内条目的数字位：GameState 读档与运行时直接 int()/float()，给成数组/对象/null 当场 SCRIPT ERROR；
## contract 的还在 from_dict 半途抛，其后 player_name/identity/ended 等全留缺省却照报读档成功。
const CONTRACT_NUM_KEYS := [
	"qty", "remaining", "purse", "unit_purse", "paid", "due_day", "deadline_days", "voyage_days", "offer_month",
]
const RUMOR_NUM_KEYS := ["rate", "day"]


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
		SCHEMA_KEY: SAVE_SCHEMA,
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
	state["met_ids"] = _normalise_ids(state.get("met_ids", []))
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


## 读一份 JSON 存档并归类：missing 不存在 / corrupt 坏档 / future 新版所记 / ok 可读。
## ok 时 data 已迁到本版结构，schema 为文件里的原结构版本。
func _inspect(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"status": "corrupt"}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("存档解析失败 %s: %s" % [path, json.get_error_message()])
		return {"status": "corrupt"}
	if not (json.data is Dictionary):
		push_error("存档结构异常 %s：顶层不是对象" % path)
		return {"status": "corrupt"}
	var data: Dictionary = json.data
	var ver_raw = data.get("version", 0)
	if not _is_num(ver_raw):
		push_error("存档结构异常 %s：version 不是数字" % path)
		return {"status": "corrupt"}
	var schema_raw = data.get(SCHEMA_KEY, 1)
	if not _is_num(schema_raw) or int(schema_raw) < 1:
		push_error("存档结构异常 %s：%s 不是正整数" % [path, SCHEMA_KEY])
		return {"status": "corrupt"}
	var ver := int(ver_raw)
	var schema := int(schema_raw)
	if schema > SAVE_SCHEMA or ver > VERSION:
		push_error("存档 %s 为新版所记（结构 v%d / 头 %d），本版只识到 v%d / %d，拒读且不退副抄" % [
			path, schema, ver, SAVE_SCHEMA, VERSION])
		return {"status": "future", "schema": schema}
	if schema < SAVE_SCHEMA:
		data = _migrate(data, schema)
		if data.is_empty():
			return {"status": "corrupt"}
	var bad := _check_partitions(data)
	if bad != "":
		push_error("存档结构异常 %s：%s" % [path, bad])
		return {"status": "corrupt"}
	return {"status": "ok", "data": data, "schema": schema}


## 只要数据：坏档、新版档、不存在都返回空字典
func _read(path: String) -> Dictionary:
	return _inspect(path).get("data", {})


## 迁移链：从 from_schema 一步一步升到 SAVE_SCHEMA，每步一个 _migrate_vN_to_vN+1。
## 加新结构时：SAVE_SCHEMA +1，写一个新的迁移函数，在 match 里挂一行。
## 迁移函数只补缺、改名、换形，类型坏的字段原样留给 _check_partitions 判坏档。
func _migrate(data: Dictionary, from_schema: int) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	for v in range(from_schema, SAVE_SCHEMA):
		match v:
			1:
				out = _migrate_v1_to_v2(out)
			2:
				out = _migrate_v2_to_v3(out)
			3:
				out = _migrate_v3_to_v4(out)
			_:
				push_error("存档迁移链缺 v%d → v%d" % [v, v + 1])
				return {}
		out[SCHEMA_KEY] = v + 1
	return out


## v1 → v2：v1 是还没有 save_schema 的档，早期原型写的可能缺后加的 state 字段。
## 补上与 GameState.from_dict 相同的缺省值，读回结果不变，但回写后的档自带完整字段。
func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var state = data.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return data
	var defaults := {
		"player_name": "陈子龙",
		"identity": "undecided",
		"hometown_tendency": 0,
		"rumors": {},
		"contract_ban": {},
		"news_seen": [],
		"crew_history": [],
		"ended": "",
	}
	for k in defaults:
		if not state.has(k):
			state[k] = defaults[k]
	# 历史最高钱数缺了就从当前钱数起算，与 from_dict 的缺省同口径
	if not state.has("peak_money") and _is_num(state.get("money")):
		state["peak_money"] = state["money"]
	data["state"] = state
	return data


## v2 → v3：人物志「已识」入档（state.met_ids，见 GameState.met_ids）。v2 档没有这一键，按档里推得出的回填：
## 曾雇 / 此刻在船的职事（state.crew_history、crew.hired 各条的 id → characters.json 人物 id；v2 档的 hired 还是整条快照，各条里自带 id 键）、
## 守城页已当面见过林华（state.siege.lin_hua_sent 或旗 lin_hua_reminded）。
## 推不出的（酒馆里看过没雇、见面页见过）不补，照旧按进度与传闻判；已有 met_ids 的不动。
func _migrate_v2_to_v3(data: Dictionary) -> Dictionary:
	var state = data.get("state", {})
	if typeof(state) != TYPE_DICTIONARY or state.has("met_ids"):
		return data
	var crew_ids: Array = []
	var hist = state.get("crew_history", [])
	if typeof(hist) == TYPE_ARRAY:
		crew_ids.append_array(hist)
	var hired = _as_dict(data.get("crew", {})).get("hired", {})
	if typeof(hired) == TYPE_DICTIONARY:
		for c in hired.values():
			if typeof(c) == TYPE_DICTIONARY:
				crew_ids.append(c.get("id"))
	var met: Array = []
	for cid in crew_ids:
		if typeof(cid) != TYPE_STRING or cid == "":
			continue
		var who := str(GameManager.character_for_crew(cid).get("id", ""))
		if who != "" and not (who in met):
			met.append(who)
	var sent = _as_dict(state.get("siege", {})).get("lin_hua_sent", false)
	var reminded = _as_dict(state.get("flags", {})).get("lin_hua_reminded", false)
	var saw_lin: bool = (typeof(sent) == TYPE_BOOL and sent) or (typeof(reminded) == TYPE_BOOL and reminded)
	if saw_lin and not ("lin_hua" in met):
		met.append("lin_hua")
	state["met_ids"] = met
	data["state"] = state
	return data


## v3 → v4：crew.hired 由「职事 → 整条快照」收成「职事 → 候选 id」（DESIGN1-8②，存档迁移矩阵 §二）。
## 名字、月俸、品级从此只认名册 crew.json 这一份数——快照落盘的那套删，不双轨。
## 快照里取不出 id 或名册查无此人的条目直接收掉：那格按未雇对待（Crew.id 查不到即未雇；
## crew_history 另有曾雇记录，下船与人物志不靠这一格）。快照 id 与键的职事对不上的，以名册为准。
func _migrate_v3_to_v4(data: Dictionary) -> Dictionary:
	var crew = data.get("crew", {})
	if typeof(crew) != TYPE_DICTIONARY:
		return data
	var hired = crew.get("hired", {})
	if typeof(hired) != TYPE_DICTIONARY:
		return data
	var out := {}
	for role_id in hired:
		var v = hired[role_id]
		if typeof(v) == TYPE_STRING:
			# v3 档的 hired 本不该是字符串；真出现了按「名册 id」校验，查无此人即收掉，
			# 不把来路不明的字串直通过档（v4 起 hired 只认名册 id，与 Crew 读取口径一致）。
			if Crew.candidate_def(str(v)).is_empty():
				push_warning("存档迁移 v3→v4：hired.%s 的字符串「%s」不在名册，收掉该职事位" % [str(role_id), str(v)])
				continue
			out[role_id] = str(v)
			continue
		if typeof(v) != TYPE_DICTIONARY:
			if typeof(v) != TYPE_NIL:
				push_warning("存档迁移 v3→v4：hired.%s 这条不是快照对象也不是 id，收掉该职事位" % str(role_id))
			continue
		var cand_id := str(v.get("id", ""))
		if cand_id == "":
			push_warning("存档迁移 v3→v4：hired.%s 的快照取不出 id，收掉该职事位" % str(role_id))
			continue
		var cand: Dictionary = Crew.candidate_def(cand_id)
		if cand.is_empty():
			push_warning("存档迁移 v3→v4：hired.%s 的候选 id「%s」不在名册，收掉该职事位" % [str(role_id), cand_id])
			continue
		out[role_id] = cand_id
	crew["hired"] = out
	data["crew"] = crew
	return data


## 迁移后回写：原件先另存 <档名>.v<N>（已有则不覆盖，保住最早的原件），再经 .tmp 落位。
## 回写失败不阻断读档：内存里已是迁好的数据，下次记录自然写成新结构。
func _write_back_migrated(path: String, data: Dictionary, from_schema: int) -> bool:
	var keep := "%s.v%d" % [path, from_schema]
	if not FileAccess.file_exists(keep) and DirAccess.copy_absolute(path, keep) != OK:
		push_warning("存档 %s 原件无法另存为 %s，本次不回写" % [path, keep])
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("存档 %s 迁移结果无法写入 %s" % [path, tmp])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_warning("存档 %s 迁移结果无法从 .tmp 落位" % path)
		DirAccess.remove_absolute(tmp)
		return false
	return true


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
		if typeof(r) != TYPE_STRING:
			return "crew.hired 含非字符串条目（v4 起只存候选 id）"

	# GameState.from_dict 直赋强类型字段；flags / 发现录另由 _harden_state 清洗，contract 经无类型局部量判型（条目见 _bad_entries）。
	# rumors / contract_ban 虽在赋值后判型，但强类型变量赋错型当场抛 SCRIPT ERROR，兜底来不及，须在此拦。
	var state: Dictionary = _as_dict(data.get("state", {}))
	why = _bad_fields(state, STATE_NUM_KEYS, ["era_routes", "port_bans", "siege", "rumors", "contract_ban"],
			["ledger_notes", "visited_ports", "news_seen", "crew_history", "met_ids"])
	if why != "":
		return "state." + why
	why = _bad_entries(state)
	if why != "":
		return "state." + why
	if state.has("has_customs_permit") and typeof(state["has_customs_permit"]) != TYPE_BOOL:
		return "state.has_customs_permit 不是布尔"
	if state.has("last_port") and typeof(state["last_port"]) != TYPE_STRING:
		return "state.last_port 不是字符串"
	return ""


## state 容器内条目体检，与 _bad_fields 同口径：数字位给了却不是数字即坏。
## contract_ban {港: 年月序号}、rumors {港: {货: {rate, day}}}、contract 的数字字段。
## 传闻簿 / 传闻条目本身非对象时 rumor_of 已按型跳过，contract 非对象 from_dict 已判型置空，都不算坏。
func _bad_entries(state: Dictionary) -> String:
	var ban: Dictionary = _as_dict(state.get("contract_ban", {}))
	for port in ban:
		if not _is_num(ban[port]):
			return "contract_ban.%s 不是数字" % port
	var rumors: Dictionary = _as_dict(state.get("rumors", {}))
	for port in rumors:
		var book: Dictionary = _as_dict(rumors[port])
		for good in book:
			var why := _bad_fields(_as_dict(book[good]), RUMOR_NUM_KEYS, [])
			if why != "":
				return "rumors.%s.%s.%s" % [port, good, why]
	var why := _bad_fields(_as_dict(state.get("contract", {})), CONTRACT_NUM_KEYS, [])
	if why != "":
		return "contract." + why
	return ""


## 定出这一卷从哪一份翻出：
## none 无档 / primary 正本可读 / bak 正本不可用、副抄可读 / future 新版所记 / corrupt 两份皆读不出。
## 正本是新版档时不看副抄；正本坏了而副抄是新版档，也按 future 报，别让人以为是卷页损了。
func _resolve(slot: int) -> Dictionary:
	if not has_save(slot):
		return {"source": "none", "data": {}}
	var primary := _inspect(_path(slot))
	match str(primary.get("status")):
		"ok":
			return {"source": "primary", "data": primary["data"], "path": _path(slot), "schema": primary["schema"]}
		"future":
			return {"source": "future", "data": {}, "schema": primary["schema"]}
	var bak := _inspect(_bak_path(slot))
	match str(bak.get("status")):
		"ok":
			return {"source": "bak", "data": bak["data"], "path": _bak_path(slot), "schema": bak["schema"]}
		"future":
			return {"source": "future", "data": {}, "schema": bak["schema"]}
	return {"source": "corrupt", "data": {}}


## 正式档优先，坏了退 .bak；新版档不退
func _read_slot(slot: int) -> Dictionary:
	var got := _resolve(slot)
	if got["source"] == "bak":
		push_warning("存档 slot %d 正式档不可用，已退回上一份备份" % slot)
	return got["data"]


func _as_dict(raw) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func load_game(slot: int) -> bool:
	var got := _resolve(slot)
	var data: Dictionary = got["data"]
	if data.is_empty():
		return false
	if got["source"] == "bak":
		push_warning("存档 slot %d 正式档不可用，已退回上一份备份" % slot)
	# 老结构的档在 _inspect 里已迁好；这里回写，下次不必再迁
	if int(got["schema"]) < SAVE_SCHEMA:
		_write_back_migrated(str(got["path"]), data, int(got["schema"]))

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


## 卷页从哪一份翻出：none / primary / bak / future / corrupt（见 _resolve）。
## 只读查询，不改文件；给航海日志册页挂脚注用。
func slot_source(slot: int) -> String:
	return str(_resolve(slot)["source"])


## 册页脚注：正本无恙时为空串；长提示不塞进 save_label。
func save_tip(slot: int) -> String:
	var got := _resolve(slot)
	match str(got["source"]):
		"bak":
			return "正本卷页损了，已从副抄翻出。"
		"future":
			var schema := int(got.get("schema", 0))
			if schema > SAVE_SCHEMA:
				return "此卷为新版所记，存档格式 v%d，本版只识到 v%d；请换新版再翻，卷页未动。" % [schema, SAVE_SCHEMA]
			return "此卷为新版所记；请换新版再翻，卷页未动。"
		"corrupt":
			return "正本与副抄皆不可读。"
	return ""


## 翻阅失败时的日志句：新版档与坏档分开说。
func load_fail_note(slot: int) -> String:
	if slot_source(slot) == "future":
		return "为新版所记，本版读不了。"
	return "正本与副抄皆不可读。"


func save_label(slot: int) -> String:
	if not has_save(slot):
		return "未记"
	# 与 has_save / load_game 一致：正式档坏了读 .bak，避免空 FileAccess 崩日志页；新版档另题。
	var got := _resolve(slot)
	if got["source"] == "future":
		return "新版所记"
	var data: Dictionary = got["data"]
	if data.is_empty():
		return "卷页损了"
	return str(data.get("label", "未题"))

