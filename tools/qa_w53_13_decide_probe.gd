extends SceneTree
## lane-w53-13（把 w53 待拍板逐条定下来并做掉）。一支探针分段，每段钉一条拍板后的修复（退掉那处修复，那一段就红）：
##   Y 跳年封顶（待拍板 6）：晋升跳年落点不越过 1275（德祐元年）。修前 1274 年三月开第四章原样跳四年，落到景炎三年三月，
##     士人线回港当场判「未归」、1276 兴化守城一阵没打；海商线同理跳过 1277 涵江、1279 崖山。
## 用法：godot --headless --path . -s res://tools/qa_w53_13_decide_probe.gd
## 末行 W53_13_DECIDE cases=N fails=M；fails>0 退 1。
## 运行期脚本错只中止出错的那一段（其后断言整段跳过、fails 不涨、退出码守 0）——接共用件 tools/script_err_tally.gd：
## 本进程有 SCRIPT ERROR 即红；_run_guarded 包一层，_boot 半路被掐断（没走到 _report）也就地判红收尾。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _main: Node
var _gs: Node
var _gm: Node
var _cal: Node
var _tally: ScriptErrTally
var _reported := false


func _expect(ok: bool, msg: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _boot()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _boot() -> void:
	_gs = root.get_node_or_null("GameState")
	_gm = root.get_node_or_null("GameManager")
	_cal = root.get_node_or_null("Calendar")
	if _gs == null or _gm == null or _cal == null:
		_expect(false, "autoload GameState / GameManager / Calendar 都在")
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine != null:
		cine.set("auto_opening", false)
		cine.set("opening_seen", true)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for i in 10:
		await process_frame
	await _y_skip_cap()
	_report()


func _settle(n := 4) -> void:
	for _i in n:
		await process_frame


## 摆一局「第 ch 章晋升条件刚好全达」：本钱、港数、亲至都够，人泊在开章之港（有 settle_at 取它，否则泉州）
func _ready_for(ch: int, y: int, m: int) -> Dictionary:
	_gs.from_dict({})
	_cal.from_dict({"year": y, "month": m, "day": 1})
	_gs.chapter = ch
	var req: Dictionary = _gs.chapter_def(ch).get("next_requires", {})
	var need := int(req.get("peak_money", 0))
	_gs.money = need + 500
	_gs.peak_money = need + 500
	var ids: Array = []
	for raw in req.get("must_visit", []):
		ids.append(str(raw))
	for p in _gm.ports_data.get("ports", []):
		var pid := str(p.get("id", ""))
		if ids.size() >= int(req.get("visited_count", 0)):
			break
		if not (pid in ids):
			ids.append(pid)
	_gs.visited_ports = ids
	var settle := str(req.get("settle_at", ""))
	_gs.last_port = settle if settle != "" else "quanzhou"
	for n in _gs.pending_news():
		_gs.mark_news_seen(str(n.get("id", "")))
	return req


func _sheet_text() -> String:
	var host = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return ""
	var out := ""
	for l in (host as Node).find_children("*", "Label", true, false):
		out += str((l as Label).text) + "\n"
	return out


# ── Y 跳年封顶 ─────────────────────────────────────────

func _y_skip_cap() -> void:
	print("── Y 晋升跳年落点不越过 1275（德祐元年）")
	# 1274 年三月开第四章：chapters.json 第三章写跳四年，封顶后只跳一年，落在德祐元年三月
	_ready_for(3, 1274, 3)
	var res: Dictionary = _gs.try_advance_chapter()
	_expect(bool(res.get("advanced", false)) and int(res.get("years", -1)) == 1,
		"1274-03 开第四章：只跳一年（chapters.json 写 %d 年；实得 advanced=%s years=%s）" % [
			int(_gs.chapter_def(3).get("advance_years", 0)), str(res.get("advanced", false)), str(res.get("years", "?"))])
	_main.call("_show_chapter_dialog", res)
	await _settle()
	var sheet := _sheet_text()
	_expect(int(_cal.year) == 1275 and int(_cal.month) == 3,
		"册页跳年后历法落在德祐元年三月（实落 %d-%02d）——1276 守城、1277 涵江、1279 崖山都还在前头" % [int(_cal.year), int(_cal.month)])
	_expect(sheet.contains("【一年后・") and not sheet.contains("【四年后・"),
		"册页题头写「一年后」，不写「四年后」（实读：%s）" % sheet.substr(0, 40).replace("\n", "⏎"))
	_main.call("_confirm_chapter_sheet")
	await _settle()
	# 1276 年二月才开第三章：已在终局段里，一年也不跳
	_ready_for(2, 1276, 2)
	res = _gs.try_advance_chapter()
	_expect(bool(res.get("advanced", false)) and int(res.get("years", -1)) == 0,
		"1276-02 开第三章：已过德祐元年，不跳年（实得 years=%s）" % str(res.get("years", "?")))
	# 反向基：早年开章照数据跳满——1258 年五月开第二章跳两年，封顶不该误伤
	_ready_for(1, 1258, 5)
	res = _gs.try_advance_chapter()
	_expect(bool(res.get("advanced", false)) and int(res.get("years", -1)) == int(_gs.chapter_def(1).get("advance_years", 0)),
		"反向基：1258-05 开第二章照数据跳 %d 年（实得 years=%s）" % [int(_gs.chapter_def(1).get("advance_years", 0)), str(res.get("years", "?"))])


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_13_DECIDE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
