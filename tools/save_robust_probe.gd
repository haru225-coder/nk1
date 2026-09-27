extends SceneTree
## Lane h1h2：headless 探针——坏分区判坏档退 .bak、仅剩 .bak 取标签、两份皆坏不抛错。
## Lane rt：并入 state.rumors / contract_ban 强类型字典的坏值与好值用例。
## 用法：godot --headless --path . -s res://tools/save_robust_probe.gd
## 只动存档位 96，不碰正式位 1..SLOTS；输出含 SCRIPT ERROR 即视为失败。

const SLOT := 96
const GOOD_LABEL := "景炎二年　泉州　500 钱"
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
		"crew.hired 条目非对象": ["crew", {"hired": {"navigator": "老周"}, "unpaid_months": 0}],
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

	_cleanup()
	if fails == 0:
		print("SAVE_ROBUST_PROBE PASS")
		quit(0)
	else:
		print("SAVE_ROBUST_PROBE FAIL fails=%d" % fails)
		quit(1)


## 坏正式档 + 好 .bak：必须读回 .bak
func _case(name: String, primary: Dictionary) -> void:
	_cleanup()
	_write(_primary(), primary)
	_write(_primary() + ".bak", _good(BAK_LABEL, 1255, 3))
	_check(name, true, "bak", BAK_LABEL, 1255)


func _check(name: String, want_load: bool, want_src: String, want_label: String, want_year: int) -> void:
	var cal: Node = root.get_node("Calendar")
	cal.set("year", -1)
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
		"calendar": {"year": year, "month": month, "day": 1},
		"economy": {"rates": {}, "tariff": 0.1, "broker": 0.05, "investments": {}},
		"fleet": {"ships": [{"type": "fuchuan", "cargo": {}, "crew": 20}], "water": 30, "food": 30, "morale": 70, "mutiny_cooldown": 0},
		"crew": {"hired": {}, "unpaid_months": 0},
		"state": {"money": 500, "last_port": "quanzhou", "flags": {}},
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
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = _primary() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
