extends SceneTree
## Lane w53-5 四轮：航海日志册页的「记录 / 翻阅」钮与「记录」回执。
## 此前没有一道 Godot 门禁打开过这张册页（只有美术巡检 ShotTour 截它），册页逻辑只靠 check_symbols 认几个字样：
## 删掉 SaveSheet 里 `write.disabled = read_only` 一行、或让 on_save_slot 不看 save_game 的回值照报「已记入」，一键全绿（四轮变异实测）。
## 前者玩家看得见的后果：标题页「续卷」进来的册页「记录」可按——还没开局，一点就把空白局面（开局日子、场景 cg_title）
## 写进那一卷，真进度退成副抄、册页上再翻不到；后者：磁盘写不进时册页照样合上、记事报「已记入」，人以为记下了。
## 断言（册页经真钮打开：标题页「续卷」钮、港页岸带「航海日志」钮，接线一并验）：
##   S1 标题页「续卷」进来的册页：三卷「记录」一律不给按；
##   S2 同一册页「翻阅」按 can_load 放开（读得开的卷才给按）；
##   S3 港页「航海日志」进来的册页：「记录」按 can_save 放开（新版所记的卷不给记，其余都给按）；
##   S4 「记录」写不进（.tmp 位被占成目录）：册页不合上、记事顶上是「誊写未成」、不出「已记入」、那一卷题签不变；
##   S5 写得进：册页合上、记事顶上「已记入航海日志第N卷。」（卷号写中文，lane w53-13）、题签换成当下的日子。
##   F1 新版所记的卷（五轮已定）：can_save 为假；「记录」回调不覆写——正本逐字不动、不生副抄、册页不合上、不报已记入
##      （脚注许了「卷页未动」；原先一记就把新版进度退成副抄，再记一回连副抄冲掉）。无档 / 正本好 / 两份皆坏 can_save 为真。
## 五轮补键盘（真鼠标点开、真按键，经 root.push_input）：原先点「航海日志」开册页后焦点留在暗幕底下那颗钮上，
## Enter 把册页拆了重开，Tab / 方向键走到底下的「名册」「看风」「再候一日」、工席门，Enter 就在册页底下开浮页、出海、候日。
##   K1 鼠标点「航海日志」开册页：焦点在册页里（底座或册页里的钮），不在底下那颗钮上；
##   K2 Tab / Shift+Tab / 方向键连按：焦点始终在册页里，且确在册页的钮之间走动；
##   K3 Esc 合上册页：不开别的浮页、不换页、不过日子；
##   K4 再点开、按 Enter：册页合上，不是拆了重开。
##   K5 Tab 到「记录」再按 Enter / 空格：按的是这颗钮（原先 Main._unhandled_input 先把册页合上、什么也没记）。为不写正式位，
##      先把这颗钮的 pressed 接线换成计数，按两下数到 2、册页仍开、那一卷题签不变。
## 五轮已定：港页册页「翻阅」两下才翻（「翻阅」与「记录」并排同大，误点一下就回到那一卷的日子，眼下没记下的进度一笔勾销）：
##   C1 港页册页按一下「翻阅」：不读档（日子不变）、册页不合、记下待确认的是这一卷；
##   C2 再按一下：读档（日子回到那一卷）、册页合上、记事顶上「翻开日志第 N 卷……」；
##   C3 标题页「续卷」册页（还没开局、无进度可丢）按一下即翻。
## C 节同走 _on_load_slot 回调记 / 读存档位 93（册页的钮只连正式位 1..SLOTS，探针不写正式位）。
## 册页只列正式位 1..SLOTS：S1–S3 只读钮态、不写卷；S4 / S5 直调同一个回调 _on_save_slot 记存档位 93，不碰正式位。
## 另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红），cases 比场面断言多 2。
## 用法：godot --headless --path . -s res://tools/qa_w53_5_save_sheet_probe.gd
## 末行 QA_W53_5_SAVE_SHEET cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 93
## 只查「无档」can_save 用、从不写：别的探针都不碰的位（94 是往返探针的）
const EMPTY_SLOT := 993
const PORT := "fuzhou"

var _main: Node
var sl: Node
var gs: Node
var cal: Node
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
	if sl == null or gs == null or cal == null:
		push_error("autoload missing")
		quit(1)
		return
	_cleanup()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene") or _main.get("_resume_button") == null:
		_expect(false, "Main.gd 未载入或标题页没有「续卷」钮", "")
		_report()
		return

	# ── 标题页：按「续卷」钮打开册页（钮在没有存档时不显示，信号照发；接线即 _show_save_dialog.bind(true)）──
	_expect(bool(_main.title_mode.visible), "开在标题页（前提）", "scene=%s" % str(_main.current_scene_id))
	(_main.get("_resume_button") as Button).pressed.emit()
	await _settle(3)
	var writes := _chips("记录")
	var reads := _chips("翻阅")
	var slots := int(sl.get("SLOTS"))
	_expect(writes.size() == slots and reads.size() == slots, "标题页册页列出 %d 卷（前提）" % slots,
		"记录 %d / 翻阅 %d" % [writes.size(), reads.size()])
	var open_writes := writes.filter(func(b: Button) -> bool: return not b.disabled)
	_expect(writes.size() == slots and open_writes.is_empty(), "S1 标题页「续卷」册页的「记录」一律不给按",
		"可按 %d 卷" % open_writes.size())
	var read_ok := reads.size() == slots
	var read_note := PackedStringArray()
	for i in reads.size():
		var n := i + 1
		var want_off := not bool(sl.call("can_load", n))
		read_note.append("%d:%s%s" % [n, str(sl.call("slot_source", n)), "·关" if (reads[i] as Button).disabled else "·开"])
		if (reads[i] as Button).disabled != want_off:
			read_ok = false
	_expect(read_ok, "S2 「翻阅」按 can_load 放开（读不开的卷不给按）", " ".join(read_note))
	_main._close_save_sheet()
	await _settle(2)

	# ── 港页：按岸带「航海日志」钮打开册页 ──
	gs.from_dict({"money": 2000, "last_port": PORT, "visited_ports": [PORT], "loaded_with_beats": true, "beats_seen": ["start"]})
	cal.from_dict({"year": 1256, "month": 4, "day": 1})
	_main.load_scene(PORT)
	await _settle(4)
	var log_btn := _band_button("航海日志")
	_expect(log_btn != null and bool(_main.port_mode.visible), "港页岸带有「航海日志」钮（前提）", "scene=%s" % str(_main.current_scene_id))
	if log_btn != null:
		log_btn.pressed.emit()
	else:
		_main._show_save_dialog()
	await _settle(3)
	var port_writes := _chips("记录")
	var write_ok := port_writes.size() == slots
	var write_note := PackedStringArray()
	for i in port_writes.size():
		var n := i + 1
		var want_shut := not bool(sl.call("can_save", n))
		write_note.append("%d:%s%s" % [n, str(sl.call("slot_source", n)), "·关" if (port_writes[i] as Button).disabled else "·开"])
		if (port_writes[i] as Button).disabled != want_shut:
			write_ok = false
	_expect(write_ok, "S3 港页「航海日志」册页的「记录」按 can_save 放开（新版所记不给记，其余都给按）", " ".join(write_note))

	# ── 「记录」写不进：.tmp 位占成目录（FileAccess.open 写不开）──
	var first: bool = sl.save_game(SLOT, PORT)
	var label_before := str(sl.call("save_label", SLOT))
	cal.from_dict({"year": 1256, "month": 4, "day": 9})
	_main.update_status_panel()
	DirAccess.make_dir_recursive_absolute(_path(SLOT) + ".tmp")
	_main._on_save_slot(SLOT)
	await _settle(2)
	var lines: Array = Array(_main._log_lines)
	var top := str(lines[0]) if not lines.is_empty() else "<空>"
	_expect(first and is_instance_valid(_main.get("_save_host")) and top.contains("誊写未成") and not _has(lines, "已记入")
		and str(sl.call("save_label", SLOT)) == label_before,
		"S4 记录写不进：册页不合上、记事报誊写未成、不报已记入、题签不变",
		"册页开着=%s top=%s 题签=%s" % [str(is_instance_valid(_main.get("_save_host"))), top, str(sl.call("save_label", SLOT))])
	DirAccess.remove_absolute(_path(SLOT) + ".tmp")

	# ── 写得进：册页合上、记事报已记入、题签换成当下 ──
	_main._on_save_slot(SLOT)
	await _settle(2)
	lines = Array(_main._log_lines)
	top = str(lines[0]) if not lines.is_empty() else "<空>"
	var label_after := str(sl.call("save_label", SLOT))
	_expect(not is_instance_valid(_main.get("_save_host")) and top == "已记入航海日志第%s卷。" % root.get_node("GameManager").cn_num(SLOT)
		and label_after.contains(str(cal.call("get_date_string"))),
		"S5 记录写得进：册页合上、记事报已记入、题签是当下日子", "top=%s 题签=%s" % [top, label_after])

	# ── 新版所记的卷：不给记，回调也不覆写 ──
	var ok_none: bool = not bool(sl.call("has_save", EMPTY_SLOT)) and bool(sl.can_save(EMPTY_SLOT))
	var ok_good: bool = sl.can_save(SLOT)
	var good_text := _read_text(_path(SLOT))
	var future: Dictionary = JSON.parse_string(good_text)
	future[str(sl.get("SCHEMA_KEY"))] = int(sl.get("SAVE_SCHEMA")) + 1
	var future_text := JSON.stringify(future, "\t")
	_write_text(_path(SLOT), future_text)
	DirAccess.remove_absolute(_path(SLOT) + ".bak")
	_main._show_save_dialog()
	await _settle(2)
	_main.log_msg("记新版卷之前的一句。")
	var ok_future: bool = sl.can_save(SLOT)
	_main._on_save_slot(SLOT)
	await _settle(2)
	lines = Array(_main._log_lines)
	var mark := lines.find("记新版卷之前的一句。")
	var since: Array = lines.slice(0, mark) if mark >= 0 else lines
	_expect(ok_none and ok_good and not ok_future and _read_text(_path(SLOT)) == future_text
		and not FileAccess.file_exists(_path(SLOT) + ".bak") and is_instance_valid(_main.get("_save_host")) and mark >= 0 and not _has(since, "已记入"),
		"F1 新版所记的卷不给记：can_save 假、回调不覆写（正本逐字不动、不生副抄、册页不合、不报已记入）",
		"can_save 无档/好档/新版=%s/%s/%s 正本动了=%s 副抄=%s 记事顶=%s" % [str(ok_none), str(ok_good), str(ok_future),
			str(_read_text(_path(SLOT)) != future_text), str(FileAccess.file_exists(_path(SLOT) + ".bak")), str(lines[0]) if not lines.is_empty() else "<空>"])
	_write_text(_path(SLOT), "{\"version\": 4, \"calendar\": ")
	_expect(bool(sl.can_save(SLOT)), "F1b 两份皆坏的卷照样记得进（can_save 真）", "src=%s" % str(sl.call("slot_source", SLOT)))
	_main._close_save_sheet()
	await _settle(2)

	# ── 键盘：鼠标真点「航海日志」开册页（钮会拿到焦点），再真按键 ──
	if log_btn != null:
		var date0 := str(cal.call("get_date_string"))
		await _click(log_btn)
		var f0 := _focus()
		_expect(is_instance_valid(_main.get("_save_host")) and _in_sheet(f0), "K1 鼠标点开册页：焦点在册页里，不在底下的「航海日志」钮上",
			"焦点=%s" % _name(f0))
		var walk := PackedStringArray()
		var inside := true
		var seen := {}
		for k in [KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, KEY_TAB, -KEY_TAB, -KEY_TAB, KEY_RIGHT, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_UP]:
			await _key(absi(k), k < 0)
			var f := _focus()
			walk.append(_name(f))
			inside = inside and _in_sheet(f)
			if f is Button:
				seen[f] = true
		_expect(inside and seen.size() >= 3, "K2 Tab / Shift+Tab / 方向键：焦点始终在册页里、在册页的钮之间走",
			"走过 %d 颗钮：%s" % [seen.size(), " → ".join(walk)])
		await _key(KEY_ESCAPE)
		await _settle(2)
		_expect(not is_instance_valid(_main.get("_save_host")) and _no_float_page() and str(_main.current_scene_id) == PORT
			and str(cal.call("get_date_string")) == date0, "K3 Esc 合上册页，不开别的浮页、不换页、不过日子",
			"册页开着=%s 场景=%s 日子=%s" % [str(is_instance_valid(_main.get("_save_host"))), str(_main.current_scene_id), str(cal.call("get_date_string"))])
		if is_instance_valid(_main.get("_save_host")):
			_main._close_save_sheet()  # K3 没合上时先收掉，K4 单验 Enter
			await _settle(2)
		await _click(log_btn)
		var opened := is_instance_valid(_main.get("_save_host"))
		await _key(KEY_ENTER)
		await _settle(3)
		_expect(opened and not is_instance_valid(_main.get("_save_host")) and _no_float_page(), "K4 点开后按 Enter：册页合上，不是拆了重开",
			"点开=%s Enter 后册页开着=%s 焦点=%s" % [str(opened), str(is_instance_valid(_main.get("_save_host"))), _name(_focus())])

	# ── Tab 到「记录」按 Enter / 空格：按的是这颗钮（pressed 换成计数，不写正式位）──
	if log_btn != null:
		if is_instance_valid(_main.get("_save_host")):
			_main._close_save_sheet()
			await _settle(2)
		await _click(log_btn)
		await _key(KEY_TAB)
		var chip := _focus()
		var hits := [0]
		var label1 := str(sl.call("save_label", 1))
		var on_rec: bool = chip is Button and (chip as Button).text == "记录"
		var chip_name := _name(chip)
		if on_rec:
			for c in (chip as Button).pressed.get_connections():
				(chip as Button).pressed.disconnect(c["callable"])
			(chip as Button).pressed.connect(func() -> void: hits[0] += 1)
			await _key(KEY_ENTER)
			await _key(KEY_SPACE)
		# 修前按下那一下册页即合、钮随之拆掉：此后只认 is_instance_valid，不碰拆掉的钮
		_expect(on_rec and hits[0] == 2 and is_instance_valid(_main.get("_save_host")) and str(sl.call("save_label", 1)) == label1,
			"K5 Tab 到「记录」按 Enter / 空格：按的是这颗钮，不是合上册页",
			"焦点=%s 按到 %d 下（应 2）册页开着=%s 钮还在=%s" % [chip_name, hits[0], str(is_instance_valid(_main.get("_save_host"))),
				str(is_instance_valid(chip))])
		if is_instance_valid(_main.get("_save_host")):
			_main._close_save_sheet()
			await _settle(2)

	# ── 港页「翻阅」两下才翻；标题页一下即翻 ──
	_cleanup()
	cal.from_dict({"year": 1256, "month": 4, "day": 1})
	var saved_date := str(cal.call("get_date_string"))
	var c_saved: bool = sl.save_game(SLOT, PORT)
	cal.from_dict({"year": 1256, "month": 5, "day": 20})
	var later := str(cal.call("get_date_string"))
	_main._show_save_dialog()
	await _settle(2)
	_main._on_load_slot(SLOT)
	await _settle(2)
	var host_c = _main.get("_save_host")
	_expect(c_saved and str(cal.call("get_date_string")) == later and is_instance_valid(host_c)
		and int((host_c as Node).get_meta(&"armed", 0)) == SLOT,
		"C1 港页册页按一下「翻阅」：不读档、册页不合、待确认的是这一卷",
		"日子=%s（应仍 %s）册页开着=%s 待确认=%s" % [str(cal.call("get_date_string")), later, str(is_instance_valid(host_c)),
			str((host_c as Node).get_meta(&"armed", 0)) if is_instance_valid(host_c) else "-"])
	_main._on_load_slot(SLOT)
	await _settle(3)
	lines = Array(_main._log_lines)
	_expect(str(cal.call("get_date_string")) == saved_date and not is_instance_valid(_main.get("_save_host"))
		and not lines.is_empty() and str(lines[0]).begins_with("翻开日志第%s卷" % root.get_node("GameManager").cn_num(SLOT)),
		"C2 再按一下：读档回到那一卷的日子、册页合上、记事报翻开日志",
		"日子=%s（应 %s）册页开着=%s 记事顶=%s" % [str(cal.call("get_date_string")), saved_date,
			str(is_instance_valid(_main.get("_save_host"))), str(lines[0]) if not lines.is_empty() else "<空>"])
	cal.from_dict({"year": 1256, "month": 5, "day": 20})
	_main._show_save_dialog(true)
	await _settle(2)
	_main._on_load_slot(SLOT)
	await _settle(3)
	_expect(str(cal.call("get_date_string")) == saved_date and not is_instance_valid(_main.get("_save_host")),
		"C3 标题页「续卷」册页按一下「翻阅」即翻（还没开局、无进度可丢）",
		"日子=%s（应 %s）册页开着=%s" % [str(cal.call("get_date_string")), saved_date, str(is_instance_valid(_main.get("_save_host")))])

	_cleanup()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], "")
	print("QA_W53_5_SAVE_SHEET cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1


## 册页上某字样的小钮，按卷序（工席自上而下、自左而右即第一卷到第三卷）
func _chips(text: String) -> Array:
	var out: Array = []
	var host = _main.get("_save_host")
	if not is_instance_valid(host):
		return out
	for b in (host as Node).find_children("*", "Button", true, false):
		if (b as Button).text == text:
			out.append(b)
	return out


func _band_button(text: String) -> Button:
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	if band == null:
		return null
	for b in band.find_children("*", "Button", true, false):
		if (b as Button).text.strip_edges() == text:
			return b as Button
	return null


## 真鼠标点一颗钮（按下 + 抬起，经 root.push_input；钮会像真点那样拿到焦点）
func _click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		root.push_input(e)
		await _settle(2)


## 真按一下键（按下 + 抬起）；shift 为真时带 Shift（Shift+Tab）
func _key(code: int, shift := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.shift_pressed = shift
		e.pressed = pressed
		root.push_input(e)
		await _settle(2)


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _in_sheet(f: Control) -> bool:
	var host = _main.get("_save_host")
	return f != null and is_instance_valid(host) and (f == host or (host as Node).is_ancestor_of(f))


func _name(f: Control) -> String:
	if f == null:
		return "<无>"
	return "「%s」%s" % [str(f.get("text")) if f is Button else f.get_class(), "" if _in_sheet(f) else "（册页外）"]


## 别的浮页（人物志 / 名册 / 市舶纪事 / 船籍簿）都没开着
func _no_float_page() -> bool:
	for k in ["_codex", "_chars_wire", "_vision_stage"]:
		var n = _main.get(k)
		if is_instance_valid(n) and not bool((n as Node).get("_closing")):
			return false
	var ledger = _main.get("_ledger_layer")
	return not (is_instance_valid(ledger) and (ledger as CanvasItem).visible)


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _has(lines: Array, needle: String) -> bool:
	for x in lines:
		if str(x).contains(needle):
			return true
	return false


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _path(slot: int) -> String:
	return str(sl.get("SAVE_DIR")) + "save_%d.json" % slot


func _cleanup() -> void:
	DirAccess.remove_absolute(_path(SLOT) + ".tmp")
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = _path(SLOT) + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
