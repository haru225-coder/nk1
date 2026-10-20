extends SceneTree
## lane w54-settings：「记录」覆写已有卷先问一句专项探针。一段钉一条，回退即红。
##
## 原先的毛病：航海日志册页的「记录」与「翻阅」并排同大，这一卷已记过时，「记录」一点就照当下的局面重写这一卷——
## 原来的进度退成副抄，再记一回连副抄也冲掉，误点一下无从找回。「翻阅」五轮已定两下才翻，「记录」照同一手。
## 断言：
##   O1 这一卷已有一份记得进的卷（正本可读）：按一下「记录」不落笔——正本逐字不动、不生副抄、册页不合上，
##      这一格的钮改写成「确认记录」、挂上悬停交代，其余两格仍是「记录」；
##   O2 再按一下：落笔——册页合上、记事顶上「已记入航海日志第 N 卷。」、题签换成当下日子；
##   O3 按别卷的「记录」改认那一卷：原先待确认的那格退回「记录」，待确认落到这一卷，且按一下照旧不落笔；
##   O4 无档的卷一下就记（没有进度可覆）；正本与副抄皆不可读的卷（没有可读的进度可丢）也一下就记；
##   O5 新版所记的卷压根不给按（can_save 假），直调回调也不覆写、不记待确认；
##   O6 副抄顶着（正本坏了、翻得出的那份是副抄）也算已有一份卷：按一下不落笔。
## 册页的钮只连正式位 1..SLOTS，探针不写正式位；落笔都直调同一个回调 _on_save_slot 记存档位 547（本 lane 自用段）。
## 钮面改写（「确认记录」）与回退另拿一只挂 Same 两格的假册页验：Main._save_host 临时换成它，验完换回——
## 册页真列的三格只读不按，正式位的档一个字不动。
## 另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红），cases 比场面断言多 2。
## 用法：godot --headless --path . -s res://tools/qa_w54_settings_overwrite_probe.gd
## 末行 QA_W54_SETTINGS_OVERWRITE cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 547
## 别的卷：只用来验「按别卷改认」，最后一起清掉
const OTHER := 548
const PORT := "fuzhou"

var _main: Node
var sl: Node
var gs: Node
var cal: Node
var gm: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时收尾不会被调到——回到这里就地判红收尾
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note(), "")
		_report()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	sl = root.get_node_or_null("SaveLoad")
	gs = root.get_node_or_null("GameState")
	cal = root.get_node_or_null("Calendar")
	gm = root.get_node_or_null("GameManager")
	if sl == null or gs == null or cal == null or gm == null:
		push_error("autoload missing")
		quit(1)
		return
	_cleanup()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入", "")
		_report()
		return

	# ── 摆一个港页局面，记下这一卷（直调 save_game，不经回调）──
	gs.from_dict({"money": 2000, "last_port": PORT, "visited_ports": [PORT], "loaded_with_beats": true, "beats_seen": ["start"]})
	cal.from_dict({"year": 1256, "month": 4, "day": 1})
	_main.load_scene(PORT)
	await _settle(4)
	var ok_first: bool = sl.save_game(SLOT, PORT)
	var text_before := _read_text(_path(SLOT))
	var label_before := str(sl.call("save_label", SLOT))

	# ── O1 按一下「记录」：不落笔，钮改写「确认记录」──
	cal.from_dict({"year": 1256, "month": 5, "day": 20})
	_main.update_status_panel()
	_main._show_save_dialog()
	await _settle(3)
	_main.log_msg("按记录之前的一句。")
	_main._on_save_slot(SLOT)
	await _settle(2)
	var armed_host = _main.get("_save_host")
	var armed_meta := int((armed_host as Node).get_meta(&"save_armed", 0)) if is_instance_valid(armed_host) else -1
	var chip_text := _chip_texts()
	_expect(ok_first and is_instance_valid(armed_host) and armed_meta == SLOT
		and _read_text(_path(SLOT)) == text_before and not FileAccess.file_exists(_path(SLOT) + ".bak")
		and str(sl.call("save_label", SLOT)) == label_before
		and not _has_since("已记入"),
		"O1 已记过的卷按一下「记录」：不落笔、册页不合、题签不变、待确认的是这一卷",
		"待确认=%d 正本动了=%s 副抄=%s 册页开着=%s 题签=%s" % [armed_meta, str(_read_text(_path(SLOT)) != text_before),
			str(FileAccess.file_exists(_path(SLOT) + ".bak")), str(is_instance_valid(armed_host)), str(sl.call("save_label", SLOT))])
	var fake := _fake_sheet([SLOT, 1, 2])
	var fake_text := _fake_arm(fake, SLOT)
	_expect(chip_text == ["记录", "记录", "记录"] and fake_text == ["确认记录", "记录", "记录"]
		and _chip_tip(fake, SLOT) != "",
		"O1b 待确认那一格改写「确认记录」并挂悬停交代，其余格仍是「记录」",
		"真册页=%s 假册页=%s" % [" ".join(chip_text), " ".join(fake_text)])

	# ── O2 再按一下：落笔 ──
	_main._on_save_slot(SLOT)
	await _settle(3)
	var lines: Array = Array(_main._log_lines)
	var top := str(lines[0]) if not lines.is_empty() else "<空>"
	var label_after := str(sl.call("save_label", SLOT))
	_expect(not is_instance_valid(_main.get("_save_host")) and top == "已记入航海日志第%s卷。" % gm.call("cn_num", SLOT)
		and label_after.contains(str(cal.call("get_date_string"))) and FileAccess.file_exists(_path(SLOT) + ".bak"),
		"O2 再按一下：册页合上、记事报已记入、题签是当下日子、旧卷退成副抄", "top=%s 题签=%s" % [top, label_after])

	# ── O3 按别卷的「记录」改认那一卷 ──
	_cleanup()
	sl.save_game(SLOT, PORT)
	sl.save_game(OTHER, PORT)
	_main._show_save_dialog()
	await _settle(3)
	var t_slot := _read_text(_path(SLOT))
	var t_other := _read_text(_path(OTHER))
	_main._on_save_slot(SLOT)
	await _settle(2)
	_main._on_save_slot(OTHER)
	await _settle(2)
	# 真册页只列正式位 1..SLOTS：改认那一格拿同一只假册页验，免得往正式位落笔
	var fake3 := _fake_sheet([SLOT, OTHER, 1])
	_fake_arm(fake3, SLOT)
	var chips3 := _fake_arm(fake3, OTHER)
	_expect(chips3 == ["记录", "确认记录", "记录"] and _read_text(_path(SLOT)) == t_slot \
		and _read_text(_path(OTHER)) == t_other,
		"O3 按别卷的「记录」改认那一卷：原先待确认的退回「记录」，两卷都还没落笔",
		"钮=%s 两卷动了=%s" % [" ".join(chips3), str(_read_text(_path(SLOT)) != t_slot or _read_text(_path(OTHER)) != t_other)])
	_main._close_save_sheet()
	await _settle(2)

	# ── O4 无档 / 两份皆坏的卷一下就记 ──
	_cleanup()
	cal.from_dict({"year": 1256, "month": 6, "day": 2})
	_main.update_status_panel()
	_main._show_save_dialog()
	await _settle(3)
	_main._on_save_slot(SLOT)
	await _settle(3)
	var none_saved := not is_instance_valid(_main.get("_save_host")) and str(sl.call("slot_source", SLOT)) == "primary"
	# 两份皆坏：正本与副抄都写成读不出的半截
	_write_text(_path(SLOT), "{\"version\": 4, \"calendar\": ")
	_write_text(_path(SLOT) + ".bak", "[")
	_main.log_msg("坏卷之前的一句。")
	_main._show_save_dialog()
	await _settle(3)
	_main._on_save_slot(SLOT)
	await _settle(3)
	var corrupt_saved := not is_instance_valid(_main.get("_save_host")) and str(sl.call("slot_source", SLOT)) == "primary" \
		and _has_since("已记入")
	_expect(none_saved, "O4a 无档的卷一下就记（没有进度可覆）", "src=%s 册页开着=%s" % [str(sl.call("slot_source", SLOT)),
		str(is_instance_valid(_main.get("_save_host")))])
	_expect(corrupt_saved, "O4b 正本与副抄皆不可读的卷一下就记（没有可读的进度可丢）", "src=%s 记事=%s" % [str(sl.call("slot_source", SLOT)),
		"已记入" if _has_since("已记入") else "<无>"])

	# ── O5 新版所记的卷：不给按、直调也不覆写、不记待确认 ──
	var future: Dictionary = JSON.parse_string(_read_text(_path(SLOT)))
	future[str(sl.get("SCHEMA_KEY"))] = int(sl.get("SAVE_SCHEMA")) + 1
	var future_text := JSON.stringify(future, "\t")
	_write_text(_path(SLOT), future_text)
	DirAccess.remove_absolute(_path(SLOT) + ".bak")
	_main._show_save_dialog()
	await _settle(3)
	# 册页那格照 can_save 关掉不给按（SaveSheet 建册时定，见 S3 / 本节 can_save 一判）；这里验直调回调也不覆写、不记待确认
	_main._on_save_slot(SLOT)
	await _settle(2)
	var host5 = _main.get("_save_host")
	_expect(not bool(sl.can_save(SLOT)) and is_instance_valid(host5)
		and int((host5 as Node).get_meta(&"save_armed", 0)) == 0 and _read_text(_path(SLOT)) == future_text,
		"O5 新版所记的卷不给按、直调也不覆写、不记待确认",
		"can_save=%s 待确认=%d 正本动了=%s" % [str(sl.can_save(SLOT)),
			int((host5 as Node).get_meta(&"save_armed", 0)) if is_instance_valid(host5) else -1,
			str(_read_text(_path(SLOT)) != future_text)])
	_main._close_save_sheet()
	await _settle(2)

	# ── O6 副抄顶着：正本坏了、翻得出的是副抄，也算已有一份卷 ──
	_cleanup()
	sl.save_game(SLOT, PORT)
	sl.save_game(SLOT, PORT)  # 第二回记：正本退成副抄
	var bak_text := _read_text(_path(SLOT) + ".bak")
	_write_text(_path(SLOT), "{not-json")
	_main._show_save_dialog()
	await _settle(3)
	_main._on_save_slot(SLOT)
	await _settle(2)
	var host6 = _main.get("_save_host")
	_expect(str(sl.call("slot_source", SLOT)) == "bak" and is_instance_valid(host6)
		and int((host6 as Node).get_meta(&"save_armed", 0)) == SLOT and _read_text(_path(SLOT)) == "{not-json"
		and _read_text(_path(SLOT) + ".bak") == bak_text,
		"O6 副抄顶着也算已有一份卷：按一下不落笔、待确认、正本与副抄都不动",
		"src=%s 待确认=%d 正本=%s 副抄动了=%s" % [str(sl.call("slot_source", SLOT)),
			int((host6 as Node).get_meta(&"save_armed", 0)) if is_instance_valid(host6) else -1,
			_read_text(_path(SLOT)).substr(0, 8), str(_read_text(_path(SLOT) + ".bak") != bak_text)])
	if is_instance_valid(_main.get("_save_host")):
		_main._close_save_sheet()
		await _settle(2)

	_cleanup()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], "")
	print("QA_W54_SETTINGS_OVERWRITE cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1


## 假册页：一只不挂进树里的底座，挂上几格名叫 Write<卷号> 的「记录」钮（与真 SaveSheet 同名同初值）。
## 验「按一下改写确认记录 / 按别卷改认」时把它顶到 Main._save_host 上，回调改写的就是它——正式位的档一个字不动。
func _fake_sheet(slots: Array) -> Control:
	var host := Control.new()
	for n in slots:
		var b := Button.new()
		b.name = "Write%d" % int(n)
		b.text = "记录"
		host.add_child(b)
	return host


## 把假册页顶上去、直调回调按一下这一卷，换回真册页，回各格钮面（按假册页上挂的先后）。
func _fake_arm(host: Control, slot: int) -> Array:
	var real = _main.get("_save_host")
	_main.set("_save_host", host)
	_main._on_save_slot(slot)
	_main.set("_save_host", real)
	var out: Array = []
	for child in host.get_children():
		if child is Button:
			out.append(str((child as Button).text))
	return out


## 假册页上某一格的悬停交代
func _chip_tip(host: Control, slot: int) -> String:
	for b in host.find_children("Write%d" % slot, "Button", true, false):
		return str((b as Button).tooltip_text)
	return ""


## 册页上各格的「记录 / 确认记录」钮，按卷序（第一卷到第三卷）
func _chip_texts() -> Array:
	var out: Array = []
	var host = _main.get("_save_host")
	if not is_instance_valid(host):
		return out
	for n in range(1, int(sl.get("SLOTS")) + 1):
		for b in (host as Node).find_children("Write%d" % n, "Button", true, false):
			out.append(str((b as Button).text))
	return out


## 记事里「按记录之前/坏卷之前的一句」之后有没有出现过 needle（认最后一句标记）
func _has_since(needle: String) -> bool:
	var lines: Array = Array(_main._log_lines)
	for i in lines.size():
		if str(lines[i]).begins_with("按记录之前的一句") or str(lines[i]).begins_with("坏卷之前的一句"):
			for j in range(0, i):
				if str(lines[j]).contains(needle):
					return true
			return false
	return false


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _path(slot: int) -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % slot


func _cleanup() -> void:
	for slot in [SLOT, OTHER]:
		for suffix in ["", ".bak", ".tmp"]:
			var p: String = _path(slot) + suffix
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
			elif DirAccess.dir_exists_absolute(p):
				DirAccess.remove_absolute(p)
