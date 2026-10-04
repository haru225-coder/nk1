extends SceneTree
## Lane w53-5 三轮：读档后船籍簿记事栏——读回的那一卷之后才发生的事不得留在记事里冒充前情。
## 修前：SaveSheet.on_load_slot 读档不动 Main 的记事。港页改读早一卷后，记事栏顶上是「翻开日志第 1 卷（lane w53-13 起写第一卷），回到 宝祐三年　三月初九。」，
## 紧跟着就是被弃那一局的「在店中歇了 1 日……如今是 宝祐三年　三月十三」——与船籍簿抬头的日子自相矛盾
## （实跑截图 wave53-5 before-ledger-log-after-load-slot1-1280x720.png）。海图回港 Main 重建时记事从空起，读档却原样留着。
## 修后：读得开的卷先清记事（LogFold 头注所列宿主五格）再读；读档时的旧卷勾稽一声照记，读不开的卷不清。
## 断言：
##   L1 读早一卷后，记事里没有读档后才发生的那句（客栈「歇了 2 日」）；
##   L2 记事顶上是「翻开日志第九十二卷，回到 <那一卷的日子>。」；
##   L3 带落空港名的旧卷：读档时的勾稽一声（「今已不见于册」）留在记事里（清在 load_game 之前，不是之后）；
##   L4 读不开的卷（两份皆坏）：原有记事不清，失败句照记在最上；
##   L5 折叠态一并清：读档前记事顶上有一折月初通告（_log_folds 非空），读后 _log_folds 空。
## 另带 script_err_tally 两判（本进程 SCRIPT ERROR 即红），cases 比场面断言多 2。
## 只动存档位 91 / 92，不碰正式位 1..SLOTS；港用福州（泉州有港口节拍幕，抵港会就地演戏）。
## 用法：godot --headless --path . -s res://tools/qa_w53_5_load_log_probe.gd
## 末行 QA_W53_5_LOAD_LOG cases=N fails=N；fails≥1 退 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const SLOT := 92
const BAD_SLOT := 91
const PORT := "fuzhou"

var _main: Node
var sl: Node
var gs: Node
var cal: Node
var fleet: Node
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
	fleet = root.get_node_or_null("Fleet")
	if sl == null or gs == null or cal == null or fleet == null:
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

	# ── 摆一卷：福州、宝祐四年四月初一，到访簿里混一枚已删港名（读档时勾稽要出一声）──
	gs.from_dict({"money": 2000, "last_port": PORT, "visited_ports": [PORT, "tungking"]})
	cal.from_dict({"year": 1256, "month": 4, "day": 1})
	fleet.from_dict({"ships": [{"type": "fu_ship_medium", "name": "试船", "durability": 300.0, "max_durability": 300.0,
		"crew": 40, "sail_level": 1, "armor_level": 1, "cargo": {}}], "water": 60, "food": 60, "morale": 70})
	_main.load_scene(PORT)
	await _settle(4)
	var saved_date: String = cal.get_date_string()
	var saved: bool = sl.save_game(SLOT, PORT)
	_expect(saved, "摆场记入第 %d 卷" % SLOT, "date=%s" % saved_date)

	# ── 读档后才发生的事：客栈歇两日（记事「如今是……四月初三」）+ 一串月初通告折成一折 ──
	_main._on_rest(2, PORT)
	await _settle(2)
	for i in 10:
		_main._on_monthly_notice("【酒馆传闻】第 %d 则旧闻。" % (i + 1))
	await _settle(2)
	var before: Array = Array(_main._log_lines)
	var folds_before: int = (_main._log_folds as Dictionary).size()
	print("  [证据] 读档前 %s 记事=%s 折叠=%d" % [cal.get_date_string(), JSON.stringify(before.slice(0, 4)), folds_before])
	_expect(_has(before, "歇了 2 日") and folds_before > 0, "读档前记事里有客栈那句、顶上有一折通告（前提）",
		"折叠=%d" % folds_before)

	# ── 读回第 92 卷 ──
	_main._on_load_slot(SLOT)
	await _settle(6)
	var after: Array = Array(_main._log_lines)
	print("  [证据] 读档后 %s 记事=%s" % [cal.get_date_string(), JSON.stringify(after)])
	_expect(not _has(after, "歇了 2 日"), "L1 读回早一卷后记事不留读档后才发生的客栈那句", JSON.stringify(after))
	var want_top := "翻开日志第%s卷，回到 %s。" % [root.get_node("GameManager").cn_num(SLOT), saved_date]
	_expect(not after.is_empty() and str(after[0]) == want_top, "L2 记事顶上是读档那一句", "top=%s" % (str(after[0]) if not after.is_empty() else "<空>"))
	_expect(_has(after, "今已不见于册"), "L3 读档时的旧卷勾稽一声留在记事里", JSON.stringify(after))
	_expect((_main._log_folds as Dictionary).is_empty(), "L5 读档前的通告折叠一并清掉", "折叠=%d" % (_main._log_folds as Dictionary).size())

	# ── 读不开的卷：原有记事不清，失败句记在最上 ──
	for p in [_path(BAD_SLOT), _path(BAD_SLOT) + ".bak"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("{\"version\": 4, \"calendar\": ")
		f.close()
	_main.log_msg("读坏卷之前的一句。")
	_main._on_load_slot(BAD_SLOT)
	await _settle(2)
	var bad: Array = Array(_main._log_lines)
	_expect(not bad.is_empty() and str(bad[0]).begins_with("第%s卷" % root.get_node("GameManager").cn_num(BAD_SLOT)) and _has(bad, "读坏卷之前的一句") and _has(bad, want_top),
		"L4 读不开的卷不清记事、失败句在最上", JSON.stringify(bad.slice(0, 3)))

	_cleanup()
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1], "")
	print("QA_W53_5_LOAD_LOG cases=%d fails=%d" % [cases, fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, name: String, detail: String) -> void:
	cases += 1
	print("  %s  %s  %s" % ["✓" if ok else "✗", name, detail])
	if not ok:
		fails += 1


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
	for slot in [SLOT, BAD_SLOT]:
		for suffix in ["", ".bak", ".tmp"]:
			var p: String = _path(slot) + suffix
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
