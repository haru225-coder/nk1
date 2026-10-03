extends SceneTree
## Lane h1h2：headless 探针——坏分区判坏档退 .bak、仅剩 .bak 取标签、两份皆坏不抛错。
## Lane rt：并入 state.rumors / contract_ban 强类型字典的坏值与好值用例。
## Lane rm：容器内条目级坏值——contract_ban 值、rumors 的 rate/day、contract 的数字字段；
## 读档后再戳一遍 contract_port_closed / rumor_label / contract_status 等运行时路径。
## 用法：godot --headless --path . -s res://tools/save_robust_probe.gd
## 只动存档位 96，不碰正式位 1..SLOTS；输出含 SCRIPT ERROR 即视为失败。

const SLOT := 96
const GOOD_LABEL := "景炎二年　泉州　500 钱"
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

	# 1 好档照读
	_cleanup()
	_write(_primary(), _good(GOOD_LABEL, 1256, 4))
	_check("好档", true, "primary", GOOD_LABEL, 1256)

	# 2 分区非对象：字符串 / 数组 / null / 数字，均退 .bak
	for part in ["calendar", "economy", "fleet", "crew", "state"]:
		for bad in ["坏", [1, 2], null, 7]:
			var d := _good(GOOD_LABEL, 1256, 4)
			d[part] = bad
			_case("%s=%s" % [part, JSON.stringify(bad)], d)

	# 3 分区是对象但关键结构不合法
	var structural := {
		"calendar.year 字符串": ["calendar", {"year": "景炎", "month": 3, "day": 1}],
		"calendar.month 越界": ["calendar", {"year": 1256, "month": 13, "day": 1}],
		"calendar.day 缺失": ["calendar", {"year": 1256, "month": 3}],
		"economy.rates 数组": ["economy", {"rates": [], "tariff": 0.1, "broker": 0.05, "investments": {}}],
		"economy.tariff 字符串": ["economy", {"rates": {}, "tariff": "一成", "broker": 0.05, "investments": {}}],
		"fleet.ships 字符串": ["fleet", {"ships": "福船", "water": 10, "food": 10, "morale": 70}],
		"fleet.ships 含数字": ["fleet", {"ships": [3], "water": 10, "food": 10, "morale": 70}],
		"fleet.cargo 数组": ["fleet", {"ships": [], "cargo": [1], "water": 10, "food": 10, "morale": 70}],
		"fleet.water 字符串": ["fleet", {"ships": [], "water": "满", "food": 10, "morale": 70}],
		"crew.hired 数组": ["crew", {"hired": [], "unpaid_months": 0}],
		# lane w26-k1：v4 起 hired 只存候选 id 字符串（wave23-a1），快照对象是 v3 旧形状，入档即坏；
		# 「名册查无此人 / 键非职员表」按未雇对待（与 Crew.roster / audit_stale_refs 同口径），不属本探针坏例。
		"crew.hired 条目非 id 字符串": ["crew", {"hired": {"duogong": {"id": "lin_hua"}}, "unpaid_months": 0}],
		"crew.unpaid_months null": ["crew", {"hired": {}, "unpaid_months": null}],
		"state.money 字符串": ["state", {"money": "千贯"}],
		"state.last_port 数字": ["state", {"last_port": 3}],
		"state.visited_ports 对象": ["state", {"visited_ports": {}}],
		# lane rt：GameState 强类型字典，from_dict 先赋值后判型，坏值会直接抛 SCRIPT ERROR
		"state.rumors 数组": ["state", {"money": 500, "rumors": [1, 2]}],
		"state.rumors 字符串": ["state", {"money": 500, "rumors": "泉州胡椒贵"}],
		"state.contract_ban 数组": ["state", {"money": 500, "contract_ban": ["quanzhou"]}],
		"state.contract_ban 数字": ["state", {"money": 500, "contract_ban": 7}],
	}
	for name in structural:
		var d := _good(GOOD_LABEL, 1256, 4)
		d[structural[name][0]] = structural[name][1]
		_case(name, d)

	# 3b lane rm：容器本身是对象、条目里的数字位给错型。改前实测：数组/对象/null 在 int()/float() 当场
	# SCRIPT ERROR；contract 的在 from_dict 半途抛错，其后 player_name/identity/ended 等全留缺省却报读档成功。
	# 与 _bad_fields 同口径：给了却不是数字（字符串、布尔也算）即坏档退 .bak。
	var entries := {
		"state.contract_ban 值 null": {"contract_ban": {"quanzhou": null}},
		"state.contract_ban 值 数组": {"contract_ban": {"quanzhou": [15076]}},
		"state.contract_ban 值 字符串": {"contract_ban": {"quanzhou": "十五"}},
		"state.rumors 条目 day null": {"rumors": {"quanzhou": {"pepper": {"rate": 1.2, "day": null}}}},
		"state.rumors 条目 day 对象": {"rumors": {"quanzhou": {"pepper": {"rate": 1.2, "day": {"d": 1}}}}},
		"state.rumors 条目 day 字符串": {"rumors": {"quanzhou": {"pepper": {"rate": 1.2, "day": "三十"}}}},
		"state.rumors 条目 rate 数组": {"rumors": {"quanzhou": {"pepper": {"rate": [1.2], "day": 30}}}},
		"state.contract remaining null": {"contract": _contract({"remaining": null})},
		"state.contract remaining 数组": {"contract": _contract({"remaining": [8]})},
		"state.contract remaining 字符串": {"contract": _contract({"remaining": "八"})},
		"state.contract qty 数组": {"contract": _contract({"qty": [8]})},
		"state.contract qty null": {"contract": _contract({"qty": null, "unit_purse": 0.0})},
		"state.contract unit_purse 对象": {"contract": _contract({"unit_purse": {"x": 1}})},
		"state.contract due_day null": {"contract": _contract({"due_day": null})},
		"state.contract purse 数组": {"contract": _contract({"purse": [800]})},
		"state.contract paid null": {"contract": _contract({"paid": null})},
		"state.contract offer_month 对象": {"contract": _contract({"offer_month": {}})},
		"state.contract deadline_days null": {"contract": _contract({"deadline_days": null})},
	}
	for name in entries:
		var d := _good(GOOD_LABEL, 1256, 4)
		var st: Dictionary = d["state"]
		st.merge(entries[name], true)
		_case(name, d)
		_poke(name)

	# 4 分区缺省：from_dict 默认值兜底，仍是好档
	var sparse := _good(GOOD_LABEL, 1256, 4)
	sparse.erase("economy")
	sparse.erase("crew")
	_cleanup()
	_write(_primary(), sparse)
	_check("economy/crew 缺省", true, "primary", GOOD_LABEL, 1256)

	# 4b 强类型字典给对了：照常读入 GameState
	var typed := _good(GOOD_LABEL, 1256, 4)
	typed["state"]["rumors"] = {"quanzhou": {"pepper": {"rate": 1.2, "day": 30}}}
	typed["state"]["contract_ban"] = {"quanzhou": 15075}
	_cleanup()
	_write(_primary(), typed)
	_check("rumors/contract_ban 好值", true, "primary", GOOD_LABEL, 1256)
	var gs: Node = root.get_node("GameState")
	var rumors = gs.get("rumors")
	var ban = gs.get("contract_ban")
	var typed_ok: bool = typeof(rumors) == TYPE_DICTIONARY and rumors.has("quanzhou") \
			and typeof(ban) == TYPE_DICTIONARY and int(ban.get("quanzhou", -1)) == 15075
	print("  %s  rumors/contract_ban 读回  rumors=%s contract_ban=%s" % [
		"✓" if typed_ok else "✗", JSON.stringify(rumors), JSON.stringify(ban)])
	if not typed_ok:
		fails += 1

	# 4c lane rm：条目给对了照读——整张委办读回、传闻标签能算；传闻簿/条目本身非对象 rumor_of 已按型跳过，不崩不拦
	var entry_ok := _good(GOOD_LABEL, 1256, 4)
	entry_ok["state"]["contract"] = _contract({})
	entry_ok["state"]["contract_ban"] = {"quanzhou": 15075, "mingzhou": 15076.0}
	entry_ok["state"]["rumors"] = {"quanzhou": {"pepper": {"rate": 1.2, "day": 450}, "silk": "旧式"}, "mingzhou": [1]}
	_cleanup()
	_write(_primary(), entry_ok)
	_check("条目好值 + 传闻簿非对象", true, "primary", GOOD_LABEL, 1256)
	var st_c: Dictionary = gs.call("contract_status")
	var label := str(gs.call("rumor_label", "quanzhou", "pepper"))
	var entry_good: bool = int(st_c.get("remaining", -1)) == 8 and int(st_c.get("qty", -1)) == 8 \
			and str(st_c.get("dest", "")) == "mingzhou" and label.begins_with("传闻约卖") \
			and bool(gs.call("contract_port_closed", "mingzhou")) \
			and not bool(gs.call("contract_port_closed", "quanzhou")) \
			and str(gs.call("rumor_label", "quanzhou", "silk")) == "" \
			and str(gs.call("rumor_label", "mingzhou", "pepper")) == ""
	print("  %s  条目好值读回  contract=%s rumor_label=%s" % [
		"✓" if entry_good else "✗", JSON.stringify(st_c), label])
	if not entry_good:
		fails += 1

	# 4d lane w53-5：分区「条目型」坏值——计数字段给了容器/字符串。改前实测（w53-5 demo3.gd 实锤）：
	# 读档=true 且运行时 buy_price / free_capacity / siege_power / investment_level / health_tally 出 SCRIPT ERROR。
	# 这些档「读得动」是因为 from_dict 直赋后靠 int()/float() 在运行时转条目，坏值潜伏到下一操作才炸。
	# 判坏走 .bak——旧份额与分区级坏档一条口径。
	var entries_bad := {
		# economy.rates 值须为 {货: 数字}（buy_price 读 rates[port][gid] -> float）
		"economy.rates 条目值含容器": ["economy", {"rates": {"quanzhou": {"rice": [1.2]}}, "investments": {}, "tariff": 0.1, "broker": 0.05}],
		# economy.investments 值须为数字（investment_level 直 int）
		"economy.investments 条目值数组": ["economy", {"rates": {}, "investments": {"quanzhou": [2]}, "tariff": 0.1, "broker": 0.05}],
		# fleet.ships 货舱条 qty 给了数组（ship_cargo_bulk/used_capacity 直 float -> free_capacity 炸）
		"fleet.ships 货舱条 qty 数组": ["fleet", {"ships": [{"type": "fuchuan", "cargo": {"rice": {"qty": [10], "avg_cost": 12.0}}, "crew": 20}], "water": 30, "food": 30, "morale": 70, "mutiny_cooldown": 0}],
		# fleet.ships 条目 crew 字符串（金算舰队人数出 SCRIPT ERROR）
		"fleet.ships 条目 crew 字符串": ["fleet", {"ships": [{"type": "fuchuan", "cargo": {}, "crew": "二十"}], "water": 30, "food": 30, "morale": 70, "mutiny_cooldown": 0}],
		# fleet.ships 条目 durability 字符串（damage/repair 直接 float）
		"fleet.ships 条目 durability 字符串": ["fleet", {"ships": [{"type": "fuchuan", "cargo": {}, "durability": "半"}], "water": 30, "food": 30, "morale": 70, "mutiny_cooldown": 0}],
		# state.siege 值给了容器（siege_get / siege_power 直 int/float）
		"state.siege 值数组": ["state", {"money": 500, "siege": {"troops": 300, "wall": [60], "morale": 55}}],
		# state.met_ids 给了对象（GameState.note_met / has_met 接 Array；_harden_state 清洗不判容器级）
		"state.met_ids 对象": ["state", {"money": 500, "met_ids": {"lin_hua": true}}],
		# state.era_routes 值给了容器（health_tally 直 int）
		"state.era_routes 值数组": ["state", {"money": 500, "era_routes": {"泉州→博多": [3]}}],
	}
	for name2 in entries_bad:
		var d2 := _good(GOOD_LABEL, 1256, 4)
		d2[entries_bad[name2][0]] = entries_bad[name2][1]
		_case(name2, d2)

	# 5 正式档不存在、只剩 .bak：标签取 .bak
	_cleanup()
	_write(_primary() + ".bak", _good(BAK_LABEL, 1255, 3))
	_check("仅剩 .bak", true, "bak", BAK_LABEL, 1255)

	# 6 顶层非对象 / 版本非数字 / 两份皆坏
	for raw in ["null", "[1,2]", "\"字\"", "{not-json"]:
		_cleanup()
		_write_raw(_primary(), raw)
		_write(_primary() + ".bak", _good(BAK_LABEL, 1255, 3))
		_check("顶层 %s" % raw, true, "bak", BAK_LABEL, 1255)
	var bad_ver := _good(GOOD_LABEL, 1256, 4)
	bad_ver["version"] = "三"
	_case("version 字符串", bad_ver)
	_cleanup()
	var both_bad := _good(GOOD_LABEL, 1256, 4)
	both_bad["fleet"] = "坏"
	_write(_primary(), both_bad)
	_write(_primary() + ".bak", both_bad)
	_check("两份皆坏", false, "corrupt", "卷页损了", -1)

	_finish()


## 坏正式档 + 好 .bak：必须读回 .bak
func _case(name: String, primary: Dictionary) -> void:
	_cleanup()
	_write(_primary(), primary)
	_write(_primary() + ".bak", _good(BAK_LABEL, 1255, 3))
	_check(name, true, "bak", BAK_LABEL, 1255)


## 读档后走一遍会吃条目数字位的运行时路径；坏值漏进 GameState 时这里会抛 SCRIPT ERROR。
## 读回的应是 .bak（无委办、无传闻），各路径须为空结果。
func _poke(name: String) -> void:
	var gs: Node = root.get_node("GameState")
	var closed = gs.call("contract_port_closed", "quanzhou")
	var label = gs.call("rumor_label", "quanzhou", "pepper")
	var status = gs.call("contract_status")
	var tick = gs.call("tick_contract")
	var ok: bool = typeof(closed) == TYPE_BOOL and not closed and str(label) == "" \
			and typeof(status) == TYPE_DICTIONARY and status.is_empty() and str(tick) == "" \
			and str(gs.get("player_name")) == "林探针"
	print("  %s  %s 读后运行时  closed=%s label=%s status=%s name=%s" % [
		"✓" if ok else "✗", name, str(closed), str(label), JSON.stringify(status), str(gs.get("player_name"))])
	if not ok:
		fails += 1


func _contract(over: Dictionary) -> Dictionary:
	var c := {"good_id": "pepper", "qty": 8, "remaining": 8, "dest": "mingzhou", "from": "quanzhou",
		"purse": 800, "unit_purse": 100.0, "paid": 0, "due_day": 99999, "deadline_days": 10,
		"voyage_days": 7, "offer_month": 15076}
	c.merge(over, true)
	return c


func _check(name: String, want_load: bool, want_src: String, want_label: String, want_year: int) -> void:
	var cal: Node = root.get_node("Calendar")
	cal.set("year", -1)
	# lane rm：先清空，from_dict 半途抛错时 player_name 留缺省「陈子龙」而非上一例的残值，_poke 才看得出
	root.get_node("GameState").set("player_name", "")
	var got_label := str(sl.call("save_label", SLOT))
	var got_src := str(sl.call("slot_source", SLOT))
	var got_load = sl.call("load_game", SLOT)
	var got_year := int(cal.get("year"))
	var ok: bool = typeof(got_load) == TYPE_BOOL and got_load == want_load \
			and got_src == want_src and got_label == want_label \
			and (want_year < 0 or got_year == want_year)
	print("  %s  %s  load=%s src=%s label=%s year=%d" % [
		"✓" if ok else "✗", name, str(got_load), got_src, got_label, got_year])
	if not ok:
		print("    want load=%s src=%s label=%s year=%d" % [str(want_load), want_src, want_label, want_year])
		fails += 1


func _good(label: String, year: int, month: int) -> Dictionary:
	return {
		"version": int(sl.get("VERSION")),
		# lane sv：带本版结构号；不带就是 v1 老档，load_game 会迁移回写并留 .v1（迁移另见 save_migrate_probe）
		str(sl.get("SCHEMA_KEY")): int(sl.get("SAVE_SCHEMA")),
		"calendar": {"year": year, "month": month, "day": 1},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {"ships": [{"type": "fuchuan", "cargo": {}, "crew": 20}], "water": 30, "food": 30, "morale": 70, "mutiny_cooldown": 0},
		# lane w26-k1：v4 起 hired 只存候选 id（Crew.candidate_def 回查 crew.json）
		"crew": {"hired": {"duogong": "lin_hua"}, "unpaid_months": 0},
		"state": {"money": 500, "last_port": "quanzhou", "flags": {}, "player_name": "林探针"},
		"scene": "quanzhou",
		"label": label,
	}


func _primary() -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % SLOT


func _write(path: String, data: Dictionary) -> void:
	_write_raw(path, JSON.stringify(data, "\t"))


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(str(sl.get("SAVE_DIR")))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp", ".v1", ".bak.v1"]:
		var p: String = _primary() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


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
		print("SAVE_ROBUST_PROBE PASS")
		quit(0)
	else:
		print("SAVE_ROBUST_PROBE FAIL fails=%d" % fails)
		quit(1)


## 用例之外的两判 / 主流程中止：与各用例同一张 fails 账、同一 ✓ / ✗ 行形。
func _verdict(ok: bool, what: String) -> void:
	print("  %s  %s" % ["✓" if ok else "✗", what])
	if not ok:
		fails += 1
