extends SceneTree
## Lane sv：headless 探针——存档结构版本 save_schema 的迁移与拒读。
## 用法：godot --headless --path . -s res://tools/save_migrate_probe.gd
## 只动存档位 95，不碰正式位 1..SLOTS；输出含 SCRIPT ERROR 即视为失败。
##   v1 老档（无 save_schema、缺后加的 state 字段）→ 读入成功、字段补齐、回写 v2、原件另存 .v1、副抄不动
##   未来档（save_schema / version 高于本版）→ 明确拒读、题签与脚注可读、不退副抄、文件不动
##   v2 档（lane fx6，无 state.met_ids）→ 人物志「已识」按雇用记录 / 在船职事 / 守城见林华回填，推不出的留空；原件另存 .v2

const SLOT := 95
const OLD_LABEL := "景炎二年　泉州　800 钱"
const BAK_LABEL := "景炎元年　兴化　300 钱"

var sl: Node
var fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	sl = root.get_node_or_null("SaveLoad")
	if sl == null:
		push_error("SaveLoad autoload missing")
		quit(1)
		return
	var cur := int(sl.get("SAVE_SCHEMA"))
	var key := str(sl.get("SCHEMA_KEY"))
	var gs: Node = root.get_node("GameState")
	var cal: Node = root.get_node("Calendar")
	print("本版 SAVE_SCHEMA=%d VERSION=%d" % [cur, int(sl.get("VERSION"))])

	# ── 1 v1 老档：无 save_schema，state 只有早期原型那几样 ──
	_cleanup()
	var v1 := _v1(OLD_LABEL, 1256, 800)
	var v1_text := JSON.stringify(v1, "\t")
	_write_raw(_primary(), v1_text)
	var bak_text := JSON.stringify(_current(BAK_LABEL, 1255), "\t")
	_write_raw(_bak(), bak_text)
	print("  [证据] v1 老档 state 键：%s（无 %s）" % [JSON.stringify(v1["state"].keys()), key])
	_expect("v1 读档前 slot_source", str(sl.call("slot_source", SLOT)), "primary")
	_expect("v1 读档前题签", str(sl.call("save_label", SLOT)), OLD_LABEL)
	gs.call("from_dict", {"player_name": "占位", "money": 1})
	cal.set("year", -1)
	_expect("v1 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("v1 读回 Calendar.year", str(cal.get("year")), "1256")
	_expect("v1 读回 money", str(gs.get("money")), "800")
	_expect("v1 读回 player_name（缺省补齐）", str(gs.get("player_name")), "陈子龙")
	_expect("v1 读回 peak_money（按 money 起算）", str(gs.get("peak_money")), "800")
	var after := _read_json(_primary())
	var st: Dictionary = after.get("state", {})
	print("  [证据] 回写后正本 %s=%s state 键：%s" % [key, _int_str(after.get(key)), JSON.stringify(st.keys())])
	_expect("回写后正本 %s" % key, _int_str(after.get(key)), str(cur))
	for k in ["player_name", "identity", "hometown_tendency", "rumors", "contract_ban", "news_seen", "crew_history", "ended", "peak_money", "met_ids"]:
		_expect("回写后 state.%s 已补" % k, str(st.has(k)), "true")
	_expect("回写后 state.flags 原样保留", JSON.stringify(st.get("flags")), JSON.stringify({"guild_quanzhou": true}))
	_expect("回写后 label 原样保留", str(after.get("label")), OLD_LABEL)
	_expect("原件另存 %s.v1 存在" % _primary().get_file(), str(FileAccess.file_exists(_primary() + ".v1")), "true")
	_expect("原件 .v1 与迁移前逐字节一致", str(_read_text(_primary() + ".v1") == v1_text), "true")
	_expect("副抄 .bak 未动", str(_read_text(_bak()) == bak_text), "true")
	_expect("无残留 .tmp", str(FileAccess.file_exists(_primary() + ".tmp")), "false")
	# 再读一次：已是本版，不再迁，.v1 不被覆盖
	var migrated_text := _read_text(_primary())
	_expect("二次 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("二次读后正本不再改写", str(_read_text(_primary()) == migrated_text), "true")
	_expect("二次读后 .v1 仍是原件", str(_read_text(_primary() + ".v1") == v1_text), "true")

	# ── 2 v1 老档连 state 分区都没有：迁移补出带缺省的 state ──
	_cleanup()
	var bare := _v1(OLD_LABEL, 1256, 800)
	bare.erase("state")
	_write_raw(_primary(), JSON.stringify(bare, "\t"))
	_expect("v1 无 state load_game", str(sl.call("load_game", SLOT)), "true")
	var bare_after := _read_json(_primary())
	_expect("v1 无 state 回写后 state.identity", str(_as_dict(bare_after.get("state")).get("identity")), "undecided")
	_expect("v1 无 state 回写后 %s" % key, _int_str(bare_after.get(key)), str(cur))

	# ── 3 正本坏、副抄是 v1：从副抄读入并迁移，回写副抄、另存 .bak.v1 ──
	_cleanup()
	_write_raw(_primary(), "{not-json")
	var bak_v1_text := JSON.stringify(_v1(BAK_LABEL, 1255, 300), "\t")
	_write_raw(_bak(), bak_v1_text)
	_expect("正本坏+副抄 v1 slot_source", str(sl.call("slot_source", SLOT)), "bak")
	_expect("正本坏+副抄 v1 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("副抄回写 %s" % key, _int_str(_read_json(_bak()).get(key)), str(cur))
	_expect("副抄原件另存 .bak.v1", str(_read_text(_bak() + ".v1") == bak_v1_text), "true")
	_expect("坏正本未被动", _read_text(_primary()), "{not-json")

	# ── 4 未来档：save_schema 高于本版 + 好副抄 → 明确拒读，不退副抄 ──
	_future_case("save_schema=%d" % (cur + 97), {key: cur + 97}, true)
	# ── 5 未来档：旧头 version 高于本版（无 save_schema）→ 同样拒读 ──
	_future_case("version=99", {"version": 99}, false)
	# ── 6 正本缺失、副抄是未来档 → 也报 future，不报「卷页损了」──
	_cleanup()
	var fut_bak := _current(BAK_LABEL, 1255)
	fut_bak[key] = cur + 1
	var fut_bak_text := JSON.stringify(fut_bak, "\t")
	_write_raw(_bak(), fut_bak_text)
	_expect("仅副抄且为未来档 slot_source", str(sl.call("slot_source", SLOT)), "future")
	_expect("仅副抄且为未来档 load_game", str(sl.call("load_game", SLOT)), "false")
	_expect("仅副抄且为未来档 副抄未动", str(_read_text(_bak()) == fut_bak_text), "true")

	# ── 7 save_schema 坏值：按坏档对待，照旧退副抄 ──
	for bad in ["二", 0, -3, null, [2]]:
		_cleanup()
		var d := _current(OLD_LABEL, 1256)
		d[key] = bad
		_write_raw(_primary(), JSON.stringify(d, "\t"))
		_write_raw(_bak(), bak_text)
		_expect("%s=%s 判坏档退副抄" % [key, JSON.stringify(bad)], str(sl.call("slot_source", SLOT)), "bak")
		_expect("%s=%s 题签取副抄" % [key, JSON.stringify(bad)], str(sl.call("save_label", SLOT)), BAK_LABEL)

	# ── 8 本版 save_game 写出 save_schema ──
	_cleanup()
	_expect("save_game", str(sl.call("save_game", SLOT, "quanzhou")), "true")
	var fresh := _read_json(_primary())
	print("  [证据] save_game 写出 version=%s %s=%s" % [_int_str(fresh.get("version")), key, _int_str(fresh.get(key))])
	_expect("save_game 写出 %s" % key, _int_str(fresh.get(key)), str(cur))
	_expect("本版档读回不生成 .v*", str(sl.call("load_game", SLOT)) + "/" + str(_any_versioned()), "true/false")

	_met_backfill_cases()

	_cleanup()
	if fails == 0:
		print("SAVE_MIGRATE_PROBE PASS")
		quit(0)
	else:
		print("SAVE_MIGRATE_PROBE FAIL fails=%d" % fails)
		quit(1)


## lane fx6：v2 → v3 人物志「已识」（state.met_ids）回填。v2 档没有这一键：
## 曾雇（crew_history）、此刻在船（crew.hired 各条 id）的职事，守城页见过林华（siege.lin_hua_sent / 旗 lin_hua_reminded）补进去；
## 推不出的（只在酒馆里看过、没雇）不补；已带 met_ids 的档不动。读档后 GameState.met_ids 即档里这一份（不串上一份）。
func _met_backfill_cases() -> void:
	var gs: Node = root.get_node("GameState")
	var key := str(sl.get("SCHEMA_KEY"))
	# 职事候选 wu_zhen / lin_awu 在 characters.json 里同名（sources.crew_id），回填出的就是人物 id
	# 9a 雇过 wu_zhen（已辞）、lin_awu 在船、守城页已见林华 → 三人回填
	_cleanup()
	var d := _current(OLD_LABEL, 1276)
	d[key] = 2
	d["crew"] = {"hired": {"duogong": {"id": "lin_awu", "role": "duogong"}}, "unpaid_months": 0}
	d["state"]["crew_history"] = ["wu_zhen", "lin_awu"]
	d["state"]["siege"] = {"round": 3, "lin_hua_sent": true}
	var v2_text := JSON.stringify(d, "\t")
	_write_raw(_primary(), v2_text)
	gs.call("from_dict", {"met_ids": ["chen_zan"]})
	_expect("v2 无 met_ids load_game", str(sl.call("load_game", SLOT)), "true")
	var got: Array = gs.get("met_ids")
	print("  [证据] v2 回填后 GameState.met_ids=%s" % JSON.stringify(got))
	_expect("v2 回填：雇过 / 在船 / 守城见过林华", JSON.stringify(got), JSON.stringify(["wu_zhen", "lin_awu", "lin_hua"]))
	_expect("v2 读档后不串上一份的「见过」", str("chen_zan" in got), "false")
	var after := _read_json(_primary())
	_expect("v2 回写后 %s" % key, _int_str(after.get(key)), str(int(sl.get("SAVE_SCHEMA"))))
	_expect("v2 回写后 state.met_ids 落盘", JSON.stringify(_as_dict(after.get("state")).get("met_ids")), JSON.stringify(["wu_zhen", "lin_awu", "lin_hua"]))
	_expect("v2 原件另存 .v2 逐字节一致", str(_read_text(_primary() + ".v2") == v2_text), "true")
	# 9b 只有旗 lin_hua_reminded（守城已了、siege 已清）→ 仍回填林华
	_cleanup()
	d = _current(OLD_LABEL, 1277)
	d[key] = 2
	d["state"]["flags"] = {"lin_hua_reminded": true}
	_write_raw(_primary(), JSON.stringify(d, "\t"))
	_expect("v2 旗 lin_hua_reminded load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("v2 旗 lin_hua_reminded → 回填林华", JSON.stringify(gs.get("met_ids")), JSON.stringify(["lin_hua"]))
	# 9c 推不出（没雇过、siege 里林华未出、无旗）→ 留空，保持未识
	_cleanup()
	d = _current(OLD_LABEL, 1276)
	d[key] = 2
	d["state"]["siege"] = {"round": 1, "lin_hua_sent": false}
	_write_raw(_primary(), JSON.stringify(d, "\t"))
	gs.call("from_dict", {"met_ids": ["wu_zhen"]})
	_expect("v2 推不出 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("v2 推不出 → met_ids 为空", JSON.stringify(gs.get("met_ids")), "[]")
	# 9d 本版档自带 met_ids（含酒馆里看过没雇的）→ 原样读回，不回填、不回写
	_cleanup()
	d = _current(OLD_LABEL, 1276)
	d["state"]["met_ids"] = ["cai_qixing"]
	d["state"]["crew_history"] = ["wu_zhen"]
	var v3_text := JSON.stringify(d, "\t")
	_write_raw(_primary(), v3_text)
	_expect("本版档 met_ids load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("本版档 met_ids 原样读回（不因 crew_history 补人）", JSON.stringify(gs.get("met_ids")), JSON.stringify(["cai_qixing"]))
	_expect("本版档读回正本不改写、不生成 .v*", "%s/%s" % [str(_read_text(_primary()) == v3_text), str(_any_versioned())], "true/false")
	# 9e 存—读来回：本会话见过（note_met）→ save_game → 打乱 → load_game 仍在
	_cleanup()
	gs.call("from_dict", {})
	gs.call("note_met", "cai_qixing")
	gs.call("note_met", "cai_qixing")
	_expect("note_met 去重", JSON.stringify(gs.get("met_ids")), JSON.stringify(["cai_qixing"]))
	_expect("save_game（带 met_ids）", str(sl.call("save_game", SLOT, "quanzhou")), "true")
	_expect("save_game 写出 state.met_ids", JSON.stringify(_as_dict(_read_json(_primary()).get("state")).get("met_ids")), JSON.stringify(["cai_qixing"]))
	gs.call("from_dict", {"met_ids": ["wu_zhen"]})
	_expect("存—读来回 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("存—读来回 met_ids 复原", JSON.stringify(gs.get("met_ids")), JSON.stringify(["cai_qixing"]))


func _future_case(name: String, patch: Dictionary, show_schema: bool) -> void:
	var cal: Node = root.get_node("Calendar")
	_cleanup()
	var d := _current(OLD_LABEL, 1256)
	for k in patch:
		d[k] = patch[k]
	var prim_text := JSON.stringify(d, "\t")
	var bak_text := JSON.stringify(_current(BAK_LABEL, 1255), "\t")
	_write_raw(_primary(), prim_text)
	_write_raw(_bak(), bak_text)
	cal.set("year", -1)
	var src := str(sl.call("slot_source", SLOT))
	var label := str(sl.call("save_label", SLOT))
	var tip := str(sl.call("save_tip", SLOT))
	var loaded := str(sl.call("load_game", SLOT))
	var note := str(sl.call("load_fail_note", SLOT))
	print("  [证据] 未来档 %s → source=%s label=%s load=%s\n          tip=%s\n          note=第 %d 卷%s" % [
		name, src, label, loaded, tip, SLOT, note])
	_expect("未来档 %s slot_source" % name, src, "future")
	_expect("未来档 %s 题签" % name, label, "新版所记")
	_expect("未来档 %s load_game 拒读" % name, loaded, "false")
	_expect("未来档 %s 未退副抄（year 未被改写）" % name, str(cal.get("year")), "-1")
	_expect("未来档 %s 脚注点明新版" % name, str(tip.find("新版所记") >= 0), "true")
	if show_schema:
		_expect("未来档 %s 脚注带版本号" % name, str(tip.find("v%d" % int(patch.values()[0])) >= 0), "true")
	_expect("未来档 %s 日志句" % name, note, "为新版所记，本版读不了。")
	_expect("未来档 %s 正本未动" % name, str(_read_text(_primary()) == prim_text), "true")
	_expect("未来档 %s 副抄未动" % name, str(_read_text(_bak()) == bak_text), "true")
	_expect("未来档 %s 未生成 .v*" % name, str(_any_versioned()), "false")


func _expect(name: String, got: String, want: String) -> void:
	var ok := got == want
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, got])
	if not ok:
		print("    want %s" % want)
		fails += 1


## v2 之前的档：只有 version 头，state 是早期原型那几样
func _v1(label: String, year: int, money: int) -> Dictionary:
	return {
		"version": int(sl.get("VERSION")),
		"calendar": {"year": year, "month": 4, "day": 1},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {"ships": [{"type": "fuchuan", "cargo": {}, "crew": 20}], "water": 30, "food": 30, "morale": 70},
		"crew": {"hired": {}, "unpaid_months": 0},
		"state": {"money": money, "last_port": "quanzhou", "flags": {"guild_quanzhou": true}},
		"scene": "quanzhou",
		"label": label,
	}


func _current(label: String, year: int) -> Dictionary:
	var d := _v1(label, year, 300)
	d[str(sl.get("SCHEMA_KEY"))] = int(sl.get("SAVE_SCHEMA"))
	return d


## JSON 读回的数字是 float，按整数比
func _int_str(v) -> String:
	return str(int(v)) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else "<%s>" % str(v)


func _as_dict(raw) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _primary() -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT


func _bak() -> String:
	return _primary() + ".bak"


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<无>"
	return FileAccess.get_file_as_string(path)


func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read_text(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(str(sl.get("SAVE_DIR")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _any_versioned() -> bool:
	for base in [_primary(), _bak()]:
		for v in range(1, 10):
			if FileAccess.file_exists("%s.v%d" % [base, v]):
				return true
	return false


func _cleanup() -> void:
	for base in [_primary(), _bak()]:
		for suffix in ["", ".tmp", ".v1", ".v2", ".v3"]:
			var p: String = base + suffix
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
