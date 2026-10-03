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
## state 单格字符串位：from_dict 直赋强类型 String 字段，档里给成 bool 之外（bool 经 str() 成
## "true"/"false"，历来可行不判坏）的类型须在此拦，否则 from_dict 半途抛、其后字段全留缺省却报读档成功。
const STATE_STR_KEYS := ["player_name", "ending_id", "identity", "ended", "ended_at", "ended_text", "ended_head"]
## state 单格布尔位（STATE_NUM_KEYS 不管布尔）：给了却不是 bool 即坏。
const STATE_BOOL_KEYS := ["has_customs_permit", "loaded_with_beats"]
## state 容器内条目的数字位：GameState 读档与运行时直接 int()/float()，给成数组/对象/null 当场 SCRIPT ERROR；
## contract 的还在 from_dict 半途抛，其后 player_name/identity/ended 等全留缺省却照报读档成功。
const CONTRACT_NUM_KEYS := [
	"qty", "remaining", "purse", "unit_purse", "paid", "due_day", "deadline_days", "voyage_days", "offer_month",
]
const RUMOR_NUM_KEYS := ["rate", "day"]

## 读档成功后旧卷勾稽出有落空名目时出的一声（line 是已汇好拍的一句，slot 为读的这卷）。
## 由 Main 接到 log_msg；未接时内核照常运转（探针走 last_stale 查明细，不靠信号）。
signal stale_notice(line: String, slot: int)


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
	# 条目位：rates 值须为 {货: 数字} 的账本、investments 值须为数字。
	# from_dict 直赋后 get_rate/buy_price/investment_level 全靠 int()/float() 转，坏条目放行即 SCRIPT ERROR。
	why = _num_map_entries(eco, "rates", true)
	if why != "":
		return "economy." + why
	why = _num_map_entries(eco, "investments", false)
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
			var ship: Dictionary = s
			why = _bad_fields(ship, ["durability", "max_durability", "crew", "sail_level", "armor_level"],
					["cargo"], [])
			if why != "":
				return "fleet.ships 条目." + why
			for gid in _as_dict(ship.get("cargo", {})):
				var e = (ship["cargo"] as Dictionary)[gid]
				if typeof(e) != TYPE_DICTIONARY:
					return "fleet.ships.cargo.%s 不是对象" % gid
				why = _bad_fields(e, ["qty", "avg_cost"], [])
				if why != "":
					return "fleet.ships.cargo.%s 条目." % gid + why

	var crew: Dictionary = _as_dict(data.get("crew", {}))
	why = _bad_fields(crew, ["unpaid_months"], ["hired", "departed"])
	if why != "":
		return "crew." + why
	for cid in _as_dict(crew.get("departed", {})):
		# departed 条目 {role, name, when} 字典型；from_dict 直赋后 departed_lines() 不验型，
		# 坏条目会让船籍簿出怪行
		if typeof((crew["departed"] as Dictionary)[cid]) != TYPE_DICTIONARY:
			return "crew.departed.%s 不是对象" % cid
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
	# 单格字符串 / 布尔位（from_dict 直赋强类型字段，给了却非该型即坏）
	for k in STATE_STR_KEYS:
		if state.has(k) and not (typeof(state[k]) in [TYPE_STRING, TYPE_BOOL]):
			return "state.%s 不是字符串" % k
	for k in STATE_BOOL_KEYS:
		if state.has(k) and typeof(state[k]) != TYPE_BOOL:
			return "state.%s 不是布尔" % k
	# 委办容器：给了须为对象（from_dict typeof 判型放行，但给它成别的类型时 GameState.contract 会被静默清空、
	# 而 contract 条目坏值又不进 GameState——单列在此，免得「档里有委办」与「读到空委办」差异潜伏成坏档误判）
	if state.has("contract") and typeof(state["contract"]) != TYPE_DICTIONARY:
		return "state.contract 不是对象"
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
	# 围城账本 {troops/grain/wall/morale/…}：siege_get/siege_add/siege_power 全靠 int()/float() 转，
	# 坏值放行即守城页 SCRIPT ERROR（GameState.from_dict 直赋、不验条目）
	var sg: Dictionary = _as_dict(state.get("siege", {}))
	for key in sg:
		if not _is_num(sg[key]) and not (typeof(sg[key]) in [TYPE_STRING, TYPE_BOOL]):
			return "siege.%s 不是数字" % key
	# 行年路线 {线: 次数}：health_tally 逐值 int()，坏值即 SCRIPT ERROR
	var routes: Dictionary = _as_dict(state.get("era_routes", {}))
	for key in routes:
		if not _is_num(routes[key]):
			return "era_routes.%s 不是数字" % key
	# 封港簿 {港: 年月序号}：is_port_banned 经 str() 兜底，值却给了对象/数组时 str() 抛出不可串形
	var pb: Dictionary = _as_dict(state.get("port_bans", {}))
	for key in pb:
		if typeof(pb[key]) in [TYPE_ARRAY, TYPE_DICTIONARY]:
			return "port_bans.%s 是容器" % key
	var rumors: Dictionary = _as_dict(state.get("rumors", {}))
	for port in rumors:
		var book: Dictionary = _as_dict(rumors[port])
		for good in book:
			var why := _bad_fields(_as_dict(book[good]), RUMOR_NUM_KEYS, [])
			if why != "":
				return "rumors.%s.%s.%s" % [port, good, why]
	var ctr: Dictionary = _as_dict(state.get("contract", {}))
	var why := _bad_fields(ctr, CONTRACT_NUM_KEYS, [])
	if why != "":
		return "contract." + why
	# 委办字符串位：accept_/deliver_contract 与 audit_stale_refs 都把它喂 str() / ports.json 比对
	for k in ["good_id", "dest", "from"]:
		if ctr.has(k) and typeof(ctr[k]) != TYPE_STRING:
			return "contract.%s 不是字符串" % k
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


## 双层账本 {outer: {inner: 数字}}（deep=true 时）或单层 {key: 数字}（deep=false）的条目体检。
## economy.rates 是 {港: {货: 指数}}、investments 是 {港: 等级}：from_dict 直赋后
## get_rate/buy_price/investment_level 全靠 int()/float() 转，坏值放行即 SCRIPT ERROR。
func _num_map_entries(map: Dictionary, key: String, deep: bool) -> String:
	var outer: Dictionary = _as_dict(map.get(key, {}))
	for k in outer:
		if deep:
			var inner: Dictionary = _as_dict(outer[k])
			for kk in inner:
				if not _is_num(inner[kk]):
					return "%s.%s.%s 不是数字" % [key, k, kk]
		else:
			if not _is_num(outer[k]):
				return "%s.%s 不是数字" % [key, k]
	return ""


func load_game(slot: int) -> bool:
	_last_stale = {}
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
	_last_stale = audit_stale_refs(data)
	if not _last_stale.is_empty():
		stale_notice.emit(last_stale_note(_last_stale), slot)
	return true


## 最近一次 load_game 的落空清单（见 audit_stale_refs；未读档或统统照载为空字典）。
## 只读档内存，不碰磁盘、不改读进来的数据。UI 取走措辞即可，探针查明细。
var _last_stale: Dictionary = {}


func last_stale() -> Dictionary:
	return _last_stale.duplicate(true)


## 最近一次读档的落空一行字：无落空为空串；有则错类汇总带「」首类首枚名目，
## 玩家见到的全部措辞就在这一句。立目简次序与 audit_stale_refs 相同（
## 港 / 船式 / 勘见 / 人物 / 行年）——措辞只诉类目，枚数合并不进文字。
static func last_stale_note(stale: Dictionary) -> String:
	# 措辞（w25 主控定稿）：只说哪几类名目册上已无，不上屏任何内部编号；唯船名是玩家自己起的，引「」。
	# 例：「所记港名、「老船」的船式、勘见、人名，今已不见于册；年月亦出本朝纪年之外；余账照旧。」
	if stale.is_empty():
		return ""
	var names: Array = []
	if stale.has("port"):
		names.append("港名")
	if stale.has("ship"):
		var ship_name := str(stale["ship"].get("sample", ""))
		names.append("「%s」的船式" % ship_name if ship_name != "" else "船式")
	if stale.has("discovery"):
		names.append("勘见")
	if stale.has("character"):
		names.append("人名")
	var era := stale.has("era")
	if names.is_empty() and not era:
		return ""
	if names.is_empty():
		return "所记年月，出本朝纪年之外；余账照旧。"
	var body := "所记%s，今已不见于册" % "、".join(PackedStringArray(names))
	if era:
		body += "；年月亦出本朝纪年之外"
	return body + "；余账照旧。"


## 旧卷勾稽：港 / 船式 / 勘见 / 人物 / 行年五类里，哪些引用在本版名册图籍上查无了。
## 输入迁移后的读档字典（未走 from_dict 的原始快照）；只报不修——删式船照旧随档读
## 入、在队留存，各处取 def 已全按空表兜底（实测见 tools/save_stale_refs_probe.gd）。
## 返回 {port:{count,sample},ship:…,discovery:…,character:…,era:…}；落空类别才在字
## 典里——count 是该类落空的条数（同 id 多现只计一次），sample 供措辞引「」最多一枚。
## 判无的口径与各读取方同：港认 ports.json（剧情场景名各有去处、不入账），船认
## ships.json，勘见认 discoveries.json，人物认 characters.json；refs 只纳曾雇列传与
## 面识两处（在船雇佣按 v4 迁移已先行收去，见 _migrate_v3_to_v4）；行年以年号表
## 1253..1279 为行内，表外归入「行年」不判坏档（月日越界已在 _check_partitions 拦）。
func audit_stale_refs(data: Dictionary) -> Dictionary:
	var out := {}
	var state: Dictionary = _as_dict(data.get("state", {}))

	# 港：现泊、走通的簿引、委办起讫；账上认得的港簿与新添条目相左即可疑一处记一。
	var port := {"count": 0, "examples": [], "sample": ""}
	for pid in state.get("visited_ports", []):
		_flag_port(port, str(pid))
	_flag_port(port, str(state.get("last_port", "")))
	var contract: Dictionary = _as_dict(state.get("contract", {}))
	_flag_port(port, str(contract.get("from", "")))
	_flag_port(port, str(contract.get("dest", "")))
	if port["count"] > 0:
		port["sample"] = _port_sample(port)
		port.erase("examples")
		out["port"] = port

	# 船式：舰队各船；名册无样的船在队留存，队形不乱。
	var ship := {"count": 0, "examples": [], "sample": ""}
	var fleet: Dictionary = _as_dict(data.get("fleet", {}))
	for s in fleet.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var tid := str(s.get("type", ""))
		if tid != "" and not tid in ship["examples"] and Fleet.ship_def(tid).is_empty():
			ship["examples"].append(tid)
			ship["count"] += 1
	if ship["count"] > 0:
		ship["sample"] = _ship_sample(fleet, ship)
		ship.erase("examples")
		out["ship"] = ship

	# 勘见：未报与已领两录，去重后当众名一枚。
	var discovery := {"count": 0, "examples": [], "sample": ""}
	for key in DISCOVERY_LIST_KEYS:
		for did in state.get(key, []):
			_flag_generic(discovery, str(did), GameManager.get_discovery_by_id(str(did)).is_empty())
	if discovery["count"] > 0:
		discovery["sample"] = _generic_sample_name(discovery, "discovery")
		discovery.erase("examples")
		out["discovery"] = discovery

	# 人物：名姓只纳曾雇列传与面识（id → 人物在 GameManager 的合表；查无即落空）。
	var who_rec := {"count": 0, "examples": [], "sample": ""}
	for cid in state.get("met_ids", []):
		_flag_generic(who_rec, str(cid), GameManager.get_character(str(cid)).is_empty())
	for cid in state.get("crew_history", []):
		_flag_generic(who_rec, str(cid), GameManager.character_for_crew(str(cid)).is_empty())
	if who_rec["count"] > 0:
		who_rec["sample"] = _generic_sample_name(who_rec, "crew")
		who_rec.erase("examples")
		out["character"] = who_rec

	# 行年：以年号表 1253..1279 为行内；表外归入「行年」不判坏档。
	var cal: Dictionary = _as_dict(data.get("calendar", {}))
	if not cal.is_empty() and _is_num(cal.get("year")):
		var year := int(cal["year"])
		if year < int(Calendar.ERAS[0][0]) or year > 1279:
			out["era"] = {"count": 1, "sample": str(year)}

	return out


## 港键一行：id 非空；查无 ports.json；同类多枚只添计数与样例（取首枚）。
func _flag_port(rec: Dictionary, pid: String) -> void:
	if pid == "" or pid in rec["examples"]:
		return
	if GameManager.get_port_by_id(pid).is_empty():
		rec["examples"].append(pid)
		rec["count"] += 1


func _flag_generic(rec: Dictionary, name_id: String, missing: bool) -> void:
	if name_id == "" or name_id in rec["examples"] or not missing:
		return
	rec["examples"].append(name_id)
	rec["count"] += 1


## 港样例取 ports.json 的 name；查无再落回 id（旧卷本就没有译名）。
func _port_sample(port_rec: Dictionary) -> String:
	return str(port_rec["examples"][0])


## 船式样例为该式在队首艘的船名（舟山题的的舟名、或旧型俗名）；全为无名时落型 id。
func _ship_sample(fleet_raw: Dictionary, rec: Dictionary) -> String:
	for s in fleet_raw.get("ships", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if str(s.get("type", "")) in rec["examples"]:
			var nm := str(s.get("name", "")).strip_edges()
			if nm != "":
				return nm
	return str(rec["examples"][0])


## 样例枚 → 名目：勘见取 discovery def 的 name；人物先 crew 名册、再人物合表；
## 两边都查无就落回 id——这正应是常态：样例本就是「名册图籍上已删」的那一枚。
func _generic_sample_name(rec: Dictionary, mode: String) -> String:
	var first := str(rec["examples"][0])
	match mode:
		"discovery":
			return str(GameManager.get_discovery_by_id(first).get("name", first))
		"crew":
			for cid in rec["examples"]:
				var c := GameManager.character_for_crew(cid)
				if not c.is_empty():
					return str(c.get("name", cid))
	return first


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

