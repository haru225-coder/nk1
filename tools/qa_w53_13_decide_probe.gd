extends SceneTree
## lane-w53-13（把 w53 待拍板逐条定下来并做掉）。一支探针分段，每段钉一条拍板后的修复（退掉那处修复，那一段就红）：
##   Y 跳年封顶（待拍板 6）：晋升跳年落点不越过 1275（德祐元年）。修前 1274 年三月开第四章原样跳四年，落到景炎三年三月，
##     士人线回港当场判「未归」、1276 兴化守城一阵没打；海商线同理跳过 1277 涵江、1279 崖山。
##   L 船籍簿终章段（待拍板 4b）：了结之地那条章目写「泊在占城」，「终章・可了结」只在章目全达时写（与顶匾同一口径）。
##     修前章目叫「至占城了结一纲」，泊在占城时打勾成「已　至占城了结一纲」，读着像已经了结；「终章・可了结」第四章
##     任何时候都写，本钱还差两万也照写，离了牙行什么都不发生。
##   H 晨潮钉了结之地（待拍板 4）：章目只差「泊在占城」一条时，晨潮三向第一席恒是占城。修前占城只按顺风短程轮转，
##     从广州出发八手里多半不见占城（lane w53-12 实测平均候约十三日）。
##   E 剧情终局后船籍簿只写结局名（待拍板 67）：纲首、忠肃一类走 GameState.finish 的终局，船籍簿与顶匾原照列本章章目
##     （博多局第二章全打勾「已」却永不开章）。现在与第四章了结同一口径：只写「了结　<结局名>」。
##   Z 违约罚文零值不写（待拍板 62）：钱匣空了不写「牙行扣 0 钱」；名声已是 0 不写「名声减 1」（w53-10 079efc9 已做，此处合钉）。
##   P 毁约按未交部分罚（待拍板 17）：交了大半再放弃，罚额按未交那截酬金的一成五（至少 40），不再按全额。
##   K 章节总述落船籍簿（待拍板 3）：chapters.json 的 hint 在章目没走完时写在船籍簿章名下；走完了不写。修前 hint 从不上屏。
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
	await _l_ledger_settle()
	await _h_heading_pin()
	await _k_ledger_hint()
	await _e_ended_ledger()
	_z_contract_zero()
	_p_partial_fine()
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


# ── L 船籍簿终章段 ─────────────────────────────────────

func _page() -> String:
	_main.call("update_status_panel")
	var s := _main.get("status_label") as RichTextLabel
	return s.text if s != null else ""


func _ready_ch4(port: String, peak: int) -> void:
	_gs.from_dict({})
	_cal.from_dict({"year": 1268, "month": 6, "day": 1})
	_gs.chapter = 4
	var er: Dictionary = _gs.chapter_def(4).get("ending_requires", {})
	_gs.money = peak
	_gs.peak_money = peak
	var ids: Array = []
	for raw in er.get("must_visit", []):
		ids.append(str(raw))
	for p in _gm.ports_data.get("ports", []):
		var pid := str(p.get("id", ""))
		if ids.size() >= int(er.get("visited_count", 0)):
			break
		if not (pid in ids):
			ids.append(pid)
	_gs.visited_ports = ids
	_gs.last_port = port


func _l_ledger_settle() -> void:
	print("── L 船籍簿终章段：「泊在占城」与「终章・可了结」")
	var er: Dictionary = _gs.chapter_def(4).get("ending_requires", {})
	var need := int(er.get("peak_money", 0))
	# 本钱、港数、亲至都够，人在广州：差的只是泊到占城
	_ready_ch4("guangzhou", need + 1000)
	var page := _page()
	_expect(page.contains("・　泊在占城") and not page.contains("至占城了结一纲"),
		"泊在广州：末条章目写「・　泊在占城」（实读：%s）" % _snip(page, "占城"))
	_expect(not page.contains("终章・可了结"),
		"泊在广州、尚差一条：不写「终章・可了结」（实读：%s）" % _snip(page, "第四章"))
	# 泊在占城，本钱还差：那一条打勾写「已　泊在占城」，不写成「已　至占城了结一纲」，也不写可了结
	_ready_ch4("champa", need - 20000)
	page = _page()
	_expect(page.contains("泊在占城") and not page.contains("至占城了结一纲"),
		"泊在占城、本钱未够：那一条写「泊在占城」打勾（实读：%s）" % _snip(page, "占城"))
	_expect(not page.contains("终章・可了结"),
		"泊在占城、本钱还差两万：不写「终章・可了结」（实读：%s）" % _snip(page, "第四章"))
	# 反向基：章目全达（不进港、不触发了结，只重画船籍簿）——照写「终章・可了结」
	_ready_ch4("champa", need + 1000)
	page = _page()
	_expect(page.contains("终章・可了结"),
		"反向基：章目全达时船籍簿照写「终章・可了结」（实读：%s）" % _snip(page, "第四章"))


# ── H 晨潮钉了结之地 ─────────────────────────────────

func _h_heading_pin() -> void:
	print("── H 晨潮三向：只差泊在占城时占城占第一席")
	var hd: GDScript = load("res://scripts/core/HeadingDraft.gd") as GDScript
	var need := int(_gs.chapter_def(4).get("ending_requires", {}).get("peak_money", 0))
	_ready_ch4("guangzhou", need + 1000)
	var firsts: Array = []
	for salt in 8:
		firsts.append(str(hd.call("deal", "guangzhou", salt)[0]))
	_expect(firsts.count("champa") == 8,
		"章目只差泊在占城、人在广州：八手晨潮第一席都是占城（实得 %s）" % str(firsts))
	# 反向基：本钱还差（不止差泊港一条）——不钉占城，照顺风短程轮转
	_ready_ch4("guangzhou", need - 20000)
	firsts.clear()
	for salt in 8:
		firsts.append(str(hd.call("deal", "guangzhou", salt)[0]))
	_expect(firsts.count("champa") < 8,
		"反向基：本钱未够时不钉占城，第一席照轮转（实得 %s）" % str(firsts))


# ── K 章节总述落船籍簿 ───────────────────────────────

func _k_ledger_hint() -> void:
	print("── K 船籍簿章名下写本章总述（chapters.json hint）")
	var h2 := str(_gs.chapter_def(2).get("next_requires", {}).get("hint", ""))
	var h4 := str(_gs.chapter_def(4).get("ending_requires", {}).get("hint", ""))
	_gs.from_dict({})
	_cal.from_dict({"year": 1262, "month": 6, "day": 1})
	_gs.chapter = 2
	_gs.peak_money = 8200
	_gs.visited_ports = ["quanzhou", "fuzhou"]
	_gs.last_port = "quanzhou"
	var page := _page()
	_expect(h2 != "" and page.contains(h2), "第二章章目未走完：船籍簿写本章总述「%s」（实读：%s）" % [h2, _snip(page, "第二章")])
	var need := int(_gs.chapter_def(4).get("ending_requires", {}).get("peak_money", 0))
	_ready_ch4("guangzhou", need - 20000)
	page = _page()
	_expect(h4 != "" and page.contains(h4), "第四章章目未走完：船籍簿写终章总述（实读：%s）" % _snip(page, "第四章"))
	# 反向基：章目全达（下回入港即了结）——不再写总述，免得催办已办完的事
	_ready_ch4("champa", need + 1000)
	page = _page()
	_expect(not page.contains(h4), "反向基：章目全达时不写总述（实读：%s）" % _snip(page, "第四章"))


# ── E 剧情终局后船籍簿只写结局名 ─────────────────────────

func _e_ended_ledger() -> void:
	print("── E 剧情终局后：船籍簿 / 顶匾不再列章目，只写结局名")
	_gs.from_dict({})
	_cal.from_dict({"year": 1276, "month": 3, "day": 1})
	_gs.chapter = 2
	_gs.peak_money = 30000
	_gs.visited_ports = ["quanzhou", "fuzhou", "zhangzhou", "wenzhou", "penghu", "ryukyu", "mingzhou", "jeju", "hakata"]
	_gs.last_port = "hakata"
	_gs.finish("纲首", "（探针）")
	var page := _page()
	var hint := str(_main.call("_chapter_hint"))
	_expect(page.contains("了结　纲首") and not page.contains("亲至　博多唐房") and not page.contains("走通港口"),
		"纲首终局后（第二章、章目全达）：船籍簿只写「了结　纲首」、不列章目（实读：%s）" % _snip(page, "第二章"))
	_expect(hint == "了结　纲首", "纲首终局后顶匾写「了结　纲首」（实读「%s」）" % hint)


# ── Z 违约罚文零值不写 ─────────────────────────────────

func _z_fail(money: int, fame: int, reason: String) -> String:
	_gs.from_dict({})
	_gs.money = money
	_gs.fame = fame
	_gs.contract = {"good_id": "silk", "dest": "hakata", "purse": 400, "from": "quanzhou", "remaining": 5, "due_day": 1}
	return str(_gs.call("_fail_contract", reason))


func _z_contract_zero() -> void:
	print("── Z 违约罚文：零值不写")
	var t := _z_fail(0, 0, "毁约")
	_expect(not t.contains("扣 0 钱") and not t.contains("名声减 1") and t.contains("钱匣是空的"),
		"钱 0、名声 0 毁约：不写「扣 0 钱」「名声减 1」，写钱匣是空的（实读「%s」）" % t)
	t = _z_fail(0, 3, "逾期")
	_expect(not t.contains("扣 0 钱") and t.contains("名声减 1") and _gs.fame == 2,
		"钱 0、名声 3 逾期：不写「扣 0 钱」，照写名声减 1（实读「%s」，名声 %d）" % [t, _gs.fame])
	t = _z_fail(500, 3, "毁约")
	_expect(t.contains("牙行扣 60 钱") and t.contains("名声减 1"),
		"反向基：钱、名声都够时照写「牙行扣 60 钱，名声减 1」（实读「%s」）" % t)


# ── P 毁约按未交部分罚 ─────────────────────────────────

func _p_fine(purse: int, paid: int) -> int:
	_gs.from_dict({})
	_gs.money = 5000
	_gs.contract = {"good_id": "silk", "dest": "hakata", "purse": purse, "paid": paid, "from": "quanzhou", "remaining": 3, "due_day": 99999}
	return int(_gs.contract_fine())


func _p_partial_fine() -> void:
	print("── P 毁约罚额按未交那截酬金算")
	var f := _p_fine(1000, 800)
	_expect(f == 40, "酬 1000、已付 800：罚未交 200 的一成五 30、至少 40 → 40（实得 %d）" % f)
	f = _p_fine(2000, 400)
	_expect(f == 240, "酬 2000、已付 400：罚未交 1600 的一成五 → 240（实得 %d）" % f)
	f = _p_fine(2000, 0)
	_expect(f == 300, "反向基：一件未交照全额一成五 → 300（实得 %d）" % f)


func _snip(t: String, anchor: String, span := 60) -> String:
	var i := t.find(anchor)
	return (t.substr(0, span) if i < 0 else t.substr(maxi(0, i - 20), span)).replace("\n", "⏎")


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_13_DECIDE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)
