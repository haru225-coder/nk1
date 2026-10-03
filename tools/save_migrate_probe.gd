extends SceneTree
## Lane sv / w22-h9：headless 探针——存档结构版本 save_schema 的迁移与拒读，加尾段 T1–T10 存读档边界。
## 用法：godot --headless --path . -s res://tools/save_migrate_probe.gd
## 只动存档位 95，不碰正式位 1..SLOTS；输出含 SCRIPT ERROR 即视为失败。
##   v1 老档（无 save_schema、缺后加的 state 字段）→ 读入成功、字段补齐、回写本版（现 save_schema 3，经 v1→v2→v3 迁移链）、原件另存 .v1、副抄不动
##   未来档（save_schema / version 高于本版）→ 明确拒读、题签与脚注可读、不退副抄、文件不动
##   v2 档（lane fx6，无 state.met_ids）→ 人物志「已识」按雇用记录 / 在船职事 / 守城见林华回填，推不出的留空；原件另存 .v2
## 关键字段过链不丢（lane w20-c9，存档迁移矩阵的断言档）：v1 / v2 老档沿迁移链读入后，船与水粮（fleet 原样过链，迁移不碰 fleet）、
##   旗号（state.flags 原样保留，含玉湖事件标记 chen_zan_stake）、「已识」（v2 按档回填）逐档断言；v1 旗式样 chen_zan_stake + exam_sat_ch2 须真读进
##   GameState.flags、v1 旗舰 cargo 逐字比对读回原样；v1 fleet 分区整个缺席为 v1 骨档真实边界——判好档、fleet 回缺省（高危档回归：别静默判坏，也别声称保住了船）。

const SLOT := 95
const OLD_LABEL := "景炎二年　泉州　800 钱"
const BAK_LABEL := "景炎元年　兴化　300 钱"

var sl: Node
var fails := 0


func _init() -> void:
	call_deferred("_run_guarded")


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
	_expect("无残留 .tmp", str(FileAccess.file_exists(_primary() + ".tmp")), "false")
	# 再读一次：已是本版，不再迁，.v1 不被覆盖
	var migrated_text := _read_text(_primary())
	_expect("二次 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("二次读后正本不再改写", str(_read_text(_primary()) == migrated_text), "true")
	_expect("二次读后 .v1 仍是原件", str(_read_text(_primary() + ".v1") == v1_text), "true")
	# 副抄在本例全程未动（位上正本可读时副抄只是冷备，不读不写）
	_expect("副抄 .bak 全程未动", str(_read_text(_bak()) == bak_text), "true")
	# 关键字段过链另起：K 系自管清理与铺档（含毁副抄位）
	_keyfield_cases()

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

	# ── lane w23-a1：v3 → v4 迁移断言（crew.hired 快照收成 id，见 docs/存档迁移矩阵.md v3→v4 行）──
	_hired_id_only_cases()

	# ── w22-h9 存读档边界 T1–T10（注释逐条对照 docs/存档迁移矩阵.md §六）──
	_edge_cases()

	_finish()


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
	# v2 档的 hired 还是整条快照形状（v3→v4 才收成 id，此档只走到 v3），各条自带的 id 键供 v2→v3 回填
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

## （`v3_text` 这个局部名沿自本片立项前的探针原版——它装的是「本版档」文本；v4 之后名不符实，仅留注，不更动既有断言串）
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


## lane w20-c9（存档迁移矩阵）：老档过迁移链的关键字段留存。船 / 水粮（fleet 原样过链，两级迁移都只动 state）、
## 旗号（state.flags 原样过链，迁移只补键不改值）、「已识」（v2 档按档回填，见 _met_backfill_cases）。
## v1 档用玉湖事件标记 chen_zan_stake + 科举旗 exam_sat_ch2 当旗式样、带舱 flagship 当船式样；
## fleet 分区整个缺席是 v1 骨档的真实边界：判好档、fleet 回缺省——断言「好档 + 落缺省」，防有人静默改判坏档、
## 也防有人声称这种情况保住了船（高危档回归，见 docs/存档迁移矩阵.md）。
func _keyfield_cases() -> void:
	var gs: Node = root.get_node("GameState")
	var fleet: Node = root.get_node("Fleet")
	var key := str(sl.get("SCHEMA_KEY"))
	# K1 v1 → 本版：旗号 + 发现录过链不丢，水粮读回
	_cleanup()
	var d1 := _v1(OLD_LABEL, 1256, 800)
	d1["state"]["flags"] = {"chen_zan_stake": true, "exam_sat_ch2": true, "guild_quanzhou": true}
	d1["state"]["discoveries_found"] = ["mulan_weir"]
	d1["state"]["visited_ports"] = ["quanzhou", "xinghua"]
	var d1_text := JSON.stringify(d1, "\t")
	_write_raw(_primary(), d1_text)
	gs.call("from_dict", {"flags": {"stale_flag": true}, "money": 1})
	_expect("K1 v1 关键字段 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("K1 玉湖事件标记过链（chen_zan_stake）", str(gs.call("has_flag", "chen_zan_stake")), "true")
	_expect("K1 科考旗过链（exam_sat_ch2）", str(gs.call("has_flag", "exam_sat_ch2")), "true")
	_expect("K1 行会旗过链（guild_quanzhou）", str(gs.call("has_flag", "guild_quanzhou")), "true")
	_expect("K1 读档不串上一份残旗", str(gs.call("has_flag", "stale_flag")), "false")
	_expect("K1 发现录过链（discoveries_found）", JSON.stringify(gs.get("discoveries_found")), JSON.stringify(["mulan_weir"]))
	_expect("K1 到访港口过链（visited_ports）", JSON.stringify(gs.get("visited_ports")), JSON.stringify(["quanzhou", "xinghua"]))
	_expect("K1 水过链", _int_str(fleet.get("water")), "30")
	_expect("K1 粮过链", _int_str(fleet.get("food")), "30")
	# K1 另存的 .v1 与写入档逐字节一致（例 1 同款保真比对，换带旗式样再验「存的是写入这份、不掺上一例的槽态」）
	_expect("K1 另存 .v1 逐字节保真（带旗式样）", str(_read_text(_primary() + ".v1") == d1_text), "true")
	# K2 同档再验船式样：旗舰带舱过链逐字原样、只留一艘
	var ships: Array = fleet.get("ships")
	_expect("K2 v1 船只数原样", str(ships.size()), "1")
	_expect("K2 v1 旗舰型号过链", str(_as_dict(ships[0]).get("type")), "fuchuan")
	_expect("K2 v1 旗舰舱位原样", JSON.stringify(_as_dict(ships[0]).get("cargo")), JSON.stringify({}))
	# K3 fleet 分区缺席（v1 骨档真实边界）：好档，fleet 落缺省
	_cleanup()
	var d3 := _v1(OLD_LABEL, 1256, 800)
	d3.erase("fleet")
	_write_raw(_primary(), JSON.stringify(d3, "\t"))
	fleet.call("from_dict", {"ships": [{"type": "shachuan", "cargo": {}, "crew": 1}], "water": 9, "food": 9})
	gs.call("from_dict", {"money": 1})
	_expect("K3 v1 无 fleet 分区 load_game（好档）", str(sl.call("load_game", SLOT)), "true")
	_expect("K3 fleet 落缺省：无船", str((fleet.get("ships") as Array).size()), "0")
	_expect("K3 fleet 落缺省：水", _int_str(fleet.get("water")), "0")
	_expect("K3 state 照迁：回写后 %s" % key, _int_str(_read_json(_primary()).get(key)), str(int(sl.get("SAVE_SCHEMA"))))
	# K4 v2 → 本版：回写落盘的 met_ids 之外，旗与水粮同样过链
	_cleanup()
	var d4 := _current(OLD_LABEL, 1276)
	d4[key] = 2
	d4["fleet"]["water"] = 17
	d4["fleet"]["food"] = 23
	d4["state"]["flags"] = {"chen_zan_stake": true}
	d4["state"]["siege"] = {"round": 3, "lin_hua_sent": true}
	_write_raw(_primary(), JSON.stringify(d4, "\t"))
	gs.call("from_dict", {"flags": {"stale_flag": true}})
	_expect("K4 v2 关键字段 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("K4 玉湖事件标记过链（chen_zan_stake）", str(gs.call("has_flag", "chen_zan_stake")), "true")
	_expect("K4 读档不串上一份残旗", str(gs.call("has_flag", "stale_flag")), "false")
	_expect("K4 水过链", _int_str(fleet.get("water")), "17")
	_expect("K4 粮过链", _int_str(fleet.get("food")), "23")
	_expect("K4 「已识」回填（守城见林华）", JSON.stringify(gs.get("met_ids")), JSON.stringify(["lin_hua"]))
	# K4 另存的 .v2 与写入档逐字节一致（同 K1 的保真比对，v2 式样）
	_expect("K4 另存 .v2 逐字节保真（v2 带旗式样）", str(_read_text(_primary() + ".v2") == JSON.stringify(d4, "\t")), "true")
	# K4b v2 档自带 met_ids：迁移早退不动这一键（守卫「state.has("met_ids")」在）；防有人把 v2→v3 回填改成无脑强灌
	_cleanup()
	var d4b := _current(OLD_LABEL, 1276)
	d4b[key] = 2
	d4b["state"]["met_ids"] = ["cai_qixing"]
	d4b["state"]["crew_history"] = ["wu_zhen"]
	_write_raw(_primary(), JSON.stringify(d4b, "\t"))
	_expect("K4b v2 自带 met_ids load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("K4b v2 已有 met_ids 不被回填顶掉", JSON.stringify(gs.get("met_ids")), JSON.stringify(["cai_qixing"]))
	_expect("K4b v2 回写后 met_ids 落盘仍是原样", JSON.stringify(_as_dict(_read_json(_primary()).get("state")).get("met_ids")), JSON.stringify(["cai_qixing"]))


## lane w23-a1：v3 → v4——crew.hired 由「职事 → 整条快照」收成「职事 → 候选 id」（DESIGN1-8②）。
## 读入即 id-only、字段回查名册与快照一致；快照变形（非对象 / 缺 id / 名册除名）按口径收掉，不判坏、不留双轨。
func _hired_id_only_cases() -> void:
	var gs: Node = root.get_node("GameState")
	var crew: Node = root.get_node("Crew")
	var key := str(sl.get("SCHEMA_KEY"))
	# H1 v3 档：火长 wu_zhen、舵工 lin_awu 各带整条快照（盗来的工资 level 是编的，回查只认名册）
	_cleanup()
	var d := _current(OLD_LABEL, 1256)
	d[key] = 3
	d["crew"] = {"hired": {
			"huozhang": {"id": "wu_zhen", "role": "huozhang", "name": "吴振", "level": 3, "wage": 999},
			"duogong": {"id": "lin_awu", "role": "duogong", "name": "林阿五", "level": 3, "wage": 999},
		}, "unpaid_months": 1}
	var v3_text := JSON.stringify(d, "\t")
	_write_raw(_primary(), v3_text)
	gs.call("from_dict", {})
	crew.call("from_dict", {})
	_expect("H1 v3 hired 快照 load_game", str(sl.call("load_game", SLOT)), "true")
	var hired: Dictionary = crew.get("hired")
	print("  [证据] v3→v4 读入后 Crew.hired=%s" % JSON.stringify(hired))
	_expect("H1 读入后 hired 收成 id-only", JSON.stringify(hired), JSON.stringify({"huozhang": "wu_zhen", "duogong": "lin_awu"}))
	_expect("H1 unpaid_months 过链", str(crew.get("unpaid_months")), "1")
	# 回查口径：快照里写 3 级 / 999 钱是盗的数，名册（crew.json）是什么就是什么
	var roster_def := crew.call("candidate_def", "wu_zhen") as Dictionary
	print("  [证据] 名册 wu_zhen level=%s wage=%s；快照写的是 level=3 wage=999" % [_int_str(roster_def.get("level")), _int_str(roster_def.get("wage"))])
	_expect("H1 品级回查名册不认快照（wu_zhen）", _int_str(crew.call("level_of", "huozhang")), _int_str(roster_def.get("level")))
	_expect("H1 月俸回查名册（两人合计）", _int_str(crew.call("monthly_wage")), _int_str(_roster_wage_sum(["wu_zhen", "lin_awu"])))
	var roster_ids: Array = []
	for c in crew.call("roster"):
		roster_ids.append(str(c.get("id", "")))
	roster_ids.sort()
	_expect("H1 roster 回查 id 不丢（吴针、林阿五都在船）", JSON.stringify(roster_ids), JSON.stringify(["lin_awu", "wu_zhen"]))
	# 回写 + 原件另存
	var after := _read_json(_primary())
	_expect("H1 回写后正本 %s" % key, _int_str(after.get(key)), str(int(sl.get("SAVE_SCHEMA"))))
	_expect("H1 回写后 hired 落盘 id-only", JSON.stringify(_as_dict(after.get("crew")).get("hired")), JSON.stringify({"huozhang": "wu_zhen", "duogong": "lin_awu"}))
	_expect("H1 原件另存 .v3 逐字节一致", str(_read_text(_primary() + ".v3") == v3_text), "true")
	# 存档形状门禁：再存写出的就是 id-only
	sl.call("save_game", SLOT, "quanzhou")
	_expect("H1 save_game 写出 hired id-only", JSON.stringify(_as_dict(_read_json(_primary()).get("crew")).get("hired")), JSON.stringify({"huozhang": "wu_zhen", "duogong": "lin_awu"}))
	# H2 v3 快照变形：非对象条目 / 缺 id / 名册除名 → 各按口径收掉，档不判坏
	_cleanup()
	d = _current(OLD_LABEL, 1256)
	d[key] = 3
	d["crew"] = {"hired": {
			"huozhang": {"id": "wu_zhen", "role": "huozhang"},
			"yuanshi": "老周",
			"tongshi": {"role": "tongshi"},
			"zashi": {"id": "gone_cand", "role": "zashi"},
		}, "unpaid_months": 0}
	_write_raw(_primary(), JSON.stringify(d, "\t"))
	crew.call("from_dict", {"hired": {"yiren": "monk_puji"}})
	_expect("H2 v3 快照变形 load_game（不判坏）", str(sl.call("load_game", SLOT)), "true")
	_expect("H2 变形条目收掉只留真名册人", JSON.stringify(crew.get("hired")), JSON.stringify({"huozhang": "wu_zhen"}))
	_expect("H2 读档不串上一份残员", str((crew.get("hired") as Dictionary).has("yiren")), "false")
	_expect("H2 收掉的人不再领饷", str(crew.call("monthly_wage")), str(int(crew.call("candidate_def", "wu_zhen").get("wage", 0))))
	# H3 v1 骨档沿 v1→v2→v3→v4 全链过：空 hired 不炸、schema 升到本版
	_cleanup()
	d = _v1(BAK_LABEL, 1255, 300)
	_write_raw(_primary(), JSON.stringify(d, "\t"))
	_expect("H3 v1 档全链 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("H3 v1 空 hired 过链仍空", JSON.stringify(crew.get("hired")), "{}")
	_expect("H3 回写后正本到本版", _int_str(_read_json(_primary()).get(key)), str(int(sl.get("SAVE_SCHEMA"))))
	_expect("H3 原件另存 .v1", str(FileAccess.file_exists(_primary() + ".v1")), "true")


## 月俸期望按名册现算：快照里（本例伪造的）工资不算数
func _roster_wage_sum(ids: Array) -> int:
	var crew: Node = root.get_node("Crew")
	var total := 0
	for cand_id in ids:
		total += int(crew.call("candidate_def", str(cand_id)).get("wage", 0))
	return total


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
		for suffix in ["", ".tmp", ".v1", ".v2", ".v3", ".v4"]:
			var p: String = base + suffix
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)


## ─── w22-h9 存读档边界 T1–T10 ────────────────────────────────────────────────
## 每条注释对应 docs/存档迁移矩阵.md §六「现状 → 判据」。fail-stop 才修、软的不栽、
## 只钉现行为、不改源；只用存档位 95（不碰正式位）。

func _edge_cases() -> void:
	print("  ── w22-h9 T1–T10：存读档边界 ──")
	var gs: Node = root.get_node("GameState")
	var cal: Node = root.get_node("Calendar")
	var fleet: Node = root.get_node("Fleet")
	var key := str(sl.get("SCHEMA_KEY"))

	# ── T1 空文件（0 字节 / 只有空白）── 已经按不可读退副抄、提示「正本与副抄皆不可读」，判据：source=corrupt、题签「卷页损了」、不动文件
	var bak_text := JSON.stringify(_current(BAK_LABEL, 1255), "\t")
	for blank in ["", "   \n\t"]:
		_cleanup()
		_write_raw(_primary(), blank)
		cal.set("year", -1)
		var src := str(sl.call("slot_source", SLOT))
		_expect("T1 空档 slot_source", src, "corrupt")
		_expect("T1 空档 load_game 拒读", str(sl.call("load_game", SLOT)), "false")
		_expect("T1 空档日志句", str(sl.call("load_fail_note", SLOT)), "正本与副抄皆不可读。")
		_expect("T1 空档题签", str(sl.call("save_label", SLOT)), "卷页损了")
		_expect("T1 空档 Calendar 未被改写", str(cal.get("year")), "-1")
		_expect("T1 空文件本体未被动", _read_text(_primary()), blank)

	# ── T2 半截 JSON（写到一半 / 截断字符串）── 同源坏档，走 T1 同一判据
	for trunc in ["{\"version\":3,\"save_schema\":3,\"calendar\":{\"year\":1260,\"month\":4,\"day\":1,\"", "[1,2,{\"a\":", "\"partial\"", "{\"a\":null,\"b\""]:
		_cleanup()
		_write_raw(_primary(), trunc)
		_write_raw(_bak(), bak_text)
		_expect("T2 截断 slot_source", str(sl.call("slot_source", SLOT)), "bak")
		_expect("T2 截断题签取副抄", str(sl.call("save_label", SLOT)), BAK_LABEL)
		_expect("T2 截断 load_game 读副抄", str(sl.call("load_game", SLOT)), "true")
		_expect("T2 截断读回 money（副抄）", str(gs.get("money")), "300")

	# ── T3 顶层 JSON 合法但不是对象（数组/字串/数字）── 顶层型错即坏档，拒绝并退副抄
	for shape in ["[1,2]", "\"plain\"", "42", "null", "true"]:
		_cleanup()
		_write_raw(_primary(), shape)
		_write_raw(_bak(), bak_text)
		_expect("T3 顶层非对象 %s" % shape.substr(0, 8), str(sl.call("slot_source", SLOT)), "bak")
		_expect("T3 题签取副抄 %s" % shape.substr(0, 8), str(sl.call("save_label", SLOT)), BAK_LABEL)

	# ── T4 字段类型给了却不是数（money / water / year / tariff 写成字串 / 对象 / 数组 / 布尔）
	# 原有破检分支（外加验证：money=float 3.0 我可保纯、money=bool true 要判坏）
	for bad in [{"money": "足八百"}, {"money": {"qty": 800}}, {"money": [800]}, {"money": true},
			{"water": "三十"}, {"year": "丙戌"}, {"tariff": "十一税"}, {"chapter": "ch2"}]:
		_cleanup()
		var d := _current(OLD_LABEL, 1256)
		for k in bad:
			if k == "year":
				d["calendar"]["year"] = bad[k]
			elif k == "water":
				d["fleet"]["water"] = bad[k]
			elif k == "tariff":
				d["economy"]["tariff"] = bad[k]
			else:
				# money / chapter / flags 都属 state 分区
				d["state"][k] = bad[k]
		_write_raw(_primary(), JSON.stringify(d, "\t"))
		_write_raw(_bak(), bak_text)
		_expect("T4 %s=…判坏退副抄 题签" % str(bad.keys()[0]), str(sl.call("save_label", SLOT)), BAK_LABEL)

	# ── T5 缺必填键（calendar.year / day / month 缺一）── 日历三件套缺一即坏档退副抄
	# lane w24-b3（a0ops 遗留①）：a0ops 对抗审计时（探针 185✓/0✗）点出此段落笔当时 :458-462
	# 三条只钉「题签取副抄」、未钉 `slot_source=bak`；现位 :538-545（随 h9 之后各 lane 落码挪行）。
	# 题签断言与 slot_source 是两条链：题签只核对「露出的是副抄字样」（数据链），不判 _resolve 的
	# 来源分类（source 链）——若 _resolve 给出副抄数据却把 source 错标成 primary / corrupt，或坏正本其实
	# 被判成了别类、靠背地拼来的题签蒙混，题签照样绿。故这五条真断言一处不缺：
	# ① source=bak（根因；「备份当正本 / 正本当备份」这类错位全被它测到）；② 题签走副抄（措辞链）；
	# ③ load true（真能读）；④ 读回值取副抄（预塞 money=999 + 正本 800 都被副抄 300 盖掉，错位即现）；
	# ⑤ 坏正本未被动（只读副抄不趁机回写坏档——本版副抄本无回写一说，此处给「判坏不碰文」上锁）。
	for missing in ["year", "month", "day"]:
		_cleanup()
		var d := _current(OLD_LABEL, 1256)
		d["calendar"].erase(missing)
		var t5_pr_text := JSON.stringify(d, "\t")
		_write_raw(_primary(), t5_pr_text)
		_write_raw(_bak(), bak_text)
		gs.call("from_dict", {"money": 999})
		_expect("T5 calendar 缺 %s source=bak" % missing, str(sl.call("slot_source", SLOT)), "bak")
		_expect("T5 calendar 缺 %s 判坏退副抄" % missing, str(sl.call("save_label", SLOT)), BAK_LABEL)
		_expect("T5 calendar 缺 %s load_game 读副抄" % missing, str(sl.call("load_game", SLOT)), "true")
		_expect("T5 calendar 缺 %s 读回 money（副抄 300，盖住正本/早前 800/999）" % missing, str(gs.get("money")), "300")
		_expect("T5 calendar 缺 %s 坏正本未动（迁移不回写坏档）" % missing, str(_read_text(_primary()) == t5_pr_text), "true")

	# ── T6 未来版本号（save_schema / version 超本版）── 例 4/5 已钉；这里再钉「题签未来+脚注带版本号」那套文本
	# （既有 _future_case 所钉在案；此处只补一份「副抄自身也是未来档，但正本坏」→ 仍报 future 不报卷页损）
	_cleanup()
	var fut_bak2 := _current(BAK_LABEL, 1255)
	fut_bak2[key] = int(sl.get("SAVE_SCHEMA")) + 5
	_write_raw(_primary(), "{not-json")
	_write_raw(_bak(), JSON.stringify(fut_bak2, "\t"))
	_expect("T6 正本坏+副抄未来 slot_source", str(sl.call("slot_source", SLOT)), "future")
	_expect("T6 正本坏+副抄未来 日志句", str(sl.call("load_fail_note", SLOT)), "为新版所记，本版读不了。")

		# ── T7 存档里引用了数据表已删的 id（港 / 船型 / 发现物 / 委办目的港 / 人物 / 日历出本朝范围）
	# 现行为（w22-h9 实测钉牢，不改源）：体检只判型，不判 id 是否仍在册——load_game true、各分区原样读入、
	# 不报错不提示。要不要读档时给玩家提一句，属口径，交策划（docs/存档迁移矩阵.md §六 遗留）。
	var t7_cases := [
		["T7a 已删港 last_port", func(d): d["state"]["last_port"] = "tungking", func(): return str(gs.get("last_port")), "tungking"],
		["T7b 已删船型", func(d): d["fleet"]["ships"] = [{"type": "jungle_junk", "cargo": {}, "crew": 6}], func(): return str((fleet.get("ships") as Array).size()), "1"],
		["T7c 已删发现物", func(d): d["state"]["discoveries_found"] = ["gone_cape"], func(): return JSON.stringify(gs.get("discoveries_found")), JSON.stringify(["gone_cape"])],
		["T7e 已删人物 met_ids", func(d): d["state"]["met_ids"] = ["gone_person"], func(): return JSON.stringify(gs.get("met_ids")), JSON.stringify(["gone_person"])],
		["T7f 日历出本朝范围", func(d): d["calendar"]["year"] = 9990, func(): return str(cal.get("year")), "9990"],
	]
	for c in t7_cases:
		_cleanup()
		var d7 := _current(OLD_LABEL, 1256)
		(c[1] as Callable).call(d7)
		_write_raw(_primary(), JSON.stringify(d7, "\t"))
		_expect("%s：load_game 照读" % c[0], str(sl.call("load_game", SLOT)), "true")
		_expect("%s：原样读入" % c[0], str((c[2] as Callable).call()), c[3])

	# ── T8 槽位文件被删：仅 .bak 在 → source=bak 能读；两份皆无 → none
	_cleanup()
	_write_raw(_bak(), bak_text)
	_expect("T8 只剩副抄 slot_source", str(sl.call("slot_source", SLOT)), "bak")
	_expect("T8 只剩副抄 load_game", str(sl.call("load_game", SLOT)), "true")
	_expect("T8 只剩副抄读回 year", str(cal.get("year")), "1255")
	_cleanup()
	_expect("T8 两份皆无 slot_source", str(sl.call("slot_source", SLOT)), "none")
	_expect("T8 两份皆无 has_save", str(sl.call("has_save", SLOT)), "false")
	_expect("T8 两份皆无题签", str(sl.call("save_label", SLOT)), "未记")

	# ── T9 连存两次：逐字节一致
	_cleanup()
	gs.call("from_dict", {})
	sl.call("save_game", SLOT, "quanzhou")
	var s1 := _read_text(_primary())
	sl.call("save_game", SLOT, "quanzhou")
	var s2 := _read_text(_primary())
	_expect("T9 连存两次逐字节一致", str(s1 == s2), "true")
	# ── T10 读档后立刻再存：读进不乱写（T-98）+ 连存稳定
	_cleanup()
	var d10 := _current(OLD_LABEL, 1256)
	_write_raw(_primary(), JSON.stringify(d10, "\t"))
	gs.call("from_dict", {})
	_expect("T10 先存再读 load_game", str(sl.call("load_game", SLOT)), "true")
	sl.call("save_game", SLOT, "quanzhou")
	var once := _read_text(_primary())
	sl.call("save_game", SLOT, "quanzhou")
	_expect("T10 读后连续再存 逐字节稳定", str(_read_text(_primary()) == once), "true")

	print("  ── w22-h9 T1–T10 完 ──")


# ── lane w53-11：本进程 SCRIPT ERROR 即红 ─────────────────────────────────────
## 头注「输出含 SCRIPT ERROR 即视为失败」此前只是口头约定——没装 Logger，坏档值在 from_dict / 读后运行时路径
## 抛的脚本错只打 stderr、退出码守 0（本探针守的恰是这一类回归）；现接共用件 tools/script_err_tally.gd 判红，
## _run_guarded 兜 _run 自身中止（原先 quit 不执行、空转到外层 timeout）。这一节放在文件尾、计数器由成员初始化
## 挂上（先于 _init，挂得与 _init 里一样早）：别的文档引着本文件上部的行号，往前插行就得跟号。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
var _tally: ScriptErrTally = _arm_tally()
var _reported := false


func _arm_tally() -> ScriptErrTally:
	var t: ScriptErrTally = ScriptErrTally.new()
	OS.add_logger(t)
	return t


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_verdict(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_finish()


## 收尾（从 _run 尾挪出；_run_guarded 判中止时也走这里，照样清存档位）：SCRIPT ERROR 两判（共用件 verdicts()，
## story :3156 同款判词）记进同一张 fails 账，再印末行。
func _finish() -> void:
	_reported = true
	if sl != null:
		_cleanup()
	for v in _tally.verdicts():
		_verdict(v[0], v[1])
	if fails == 0:
		print("SAVE_MIGRATE_PROBE PASS")
		quit(0)
	else:
		print("SAVE_MIGRATE_PROBE FAIL fails=%d" % fails)
		quit(1)


## 用例之外的两判 / 主流程中止：与各用例同一张 fails 账、同一 ✓ / ✗ 行形。
func _verdict(ok: bool, what: String) -> void:
	print("  %s  %s" % ["✓" if ok else "✗", what])
	if not ok:
		fails += 1
