extends SceneTree
## Lane w53-5 四轮：航海日志册页的「记录 / 翻阅」钮与「记录」回执。
## 此前没有一道 Godot 门禁打开过这张册页（只有美术巡检 ShotTour 截它），册页逻辑只靠 check_symbols 认几个字样：
## 删掉 SaveSheet 里 `write.disabled = read_only` 一行、或让 on_save_slot 不看 save_game 的回值照报「已记入」，一键全绿（四轮变异实测）。
## 前者玩家看得见的后果：标题页「续卷」进来的册页「记录」可按——还没开局，一点就把空白局面（开局日子、场景 cg_title）
## 写进那一卷，真进度退成副抄、册页上再翻不到；后者：磁盘写不进时册页照样合上、记事报「已记入」，人以为记下了。
## 断言（册页经真钮打开：标题页「续卷」钮、港页岸带「航海日志」钮，接线一并验）：
##   S1 标题页「续卷」进来的册页：三卷「记录」一律不给按；
##   S2 同一册页「翻阅」按 can_load 放开（读得开的卷才给按）；
##   S3 港页「航海日志」进来的册页：三卷「记录」都给按；
##   S4 「记录」写不进（.tmp 位被占成目录）：册页不合上、记事顶上是「誊写未成」、不出「已记入」、那一卷题签不变；
##   S5 写得进：册页合上、记事顶上「已记入航海日志第 N 卷。」、题签换成当下的日子。
## 册页只列正式位 1..SLOTS：S1–S3 只读钮态、不写卷；S4 / S5 直调同一个回调 _on_save_slot 记存档位 93，不碰正式位。
## 另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红），cases 比场面断言多 2。
## 用法：godot --headless --path . -s res://tools/qa_w53_5_save_sheet_probe.gd
## 末行 QA_W53_5_SAVE_SHEET cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 93
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
	var shut := port_writes.filter(func(b: Button) -> bool: return b.disabled)
	_expect(port_writes.size() == slots and shut.is_empty(), "S3 港页「航海日志」册页的「记录」三卷都给按",
		"记录 %d 张、不给按 %d" % [port_writes.size(), shut.size()])

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
	_expect(not is_instance_valid(_main.get("_save_host")) and top == "已记入航海日志第 %d 卷。" % SLOT
		and label_after.contains(str(cal.call("get_date_string"))),
		"S5 记录写得进：册页合上、记事报已记入、题签是当下日子", "top=%s 题签=%s" % [top, label_after])

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
