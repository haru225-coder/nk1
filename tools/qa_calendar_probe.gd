extends SceneTree
## lane w26-k9 无门禁 sweep：「宝祐三年　三月初一」是纸面起点，还是玩家推进别的日子真会显示。
##   sweep 证据：全仓此前没有一处行为断言对日历推进与纪年命名守卫——
##   qa_rest_days / qa_iz_skip_notice / qa_money_notices 各调用 GameManager.advance_days，
##   却都不读任何玩家可见的文本，日历文字无人断言；qa_voyage_status 只查 SeaChart 的航行面板文案。
## 断言三组（与某一轮真状态对照，不是「跑起来没报错」）：
##   C1 开局不自证：挂树默认 1255-03-01，船籍簿页首行须显示「宝祐三年　三月初一」；
##      日历逻辑推 29 日跨到四月初一，页首须同步显示「四月初一」。
##   C2 状态不变量：页首月名 = 探针自拼参考月名（不引 Calendar.CN_NUM，防共同变量同错），
##      且与前月页文不同（防「月份不动时仍显示旧值」漏检）；与锚点月名一起核。
##   C3 改元与纪年：景定元年正月一改元；年名须与日历 _era_row() 同一基准；推到 1276-06 景炎元年
##      （表外锚：景炎 1276-05 起用，ERA_START 1276,5）、1278-05 祥兴元年。
## 用法：godot --headless --path . -s res://tools/qa_calendar_probe.gd
## 输出末行 CALENDAR_PROBE fails=N；N>0 时 exit 1。

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var _fails := 0
var cases := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	cal = root.get_node_or_null("Calendar")
	if gs == null or gm == null or cal == null:
		push_error("autoload missing")
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Main.tscn missing")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入")
		_report()
		return
	if _ledger_label() == null:
		_expect(false, "Main.status_label 未挂上（船籍簿页 Label 未找到）")
		_report()
		return

	await _c1_day_advance_shows()
	await _c2_condition_invariant()
	await _c3_era_and_names()

	_report()


func _settle(n := 3) -> void:
	for _i in range(n):
		await process_frame


## 船籍簿页 RichTextLabel（LedgerPage.update_panel 显示日历 + 金钱 + 船队等）
func _ledger_label() -> RichTextLabel:
	return _main.get("status_label") as RichTextLabel


## 读取挂树后 Label 的实际文（RichTextLabel.text 即 bbcode 源文）。
func _book_text() -> String:
	var s := _ledger_label()
	return s.text if s != null else ""


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		_fails += 1
		print("  ✗ ", what)


## 探针自拼的中文数字（不引 Calendar.CN_NUM，防与在线实现共同变量同错）
func _cn(n: int) -> String:
	if n <= 0:
		return "零"
	var seq := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
	if n <= 10:
		return seq[n]
	if n < 20:
		return "十" + seq[n - 10]
	if n == 20 or n == 30:
		return seq[n / 10] + "十"
	if n > 20:
		return "廿" + seq[n - 20]
	return seq[n / 10] + "十" + seq[n % 10]


func _local_month_name(m: int) -> String:
	if m == 1:
		return "正月"
	if m == 11:
		return "冬月"
	if m == 12:
		return "腊月"
	return _cn(m) + "月"


## 直接让 Main 重排船籍簿页（status_label），让页面文案随日历更新
func _repaint() -> void:
	if _main.has_method("update_status_panel"):
		_main.call("update_status_panel")


# ── C1 开局 / 日推进真实反映 ─────────────────────────

func _c1_day_advance_shows() -> void:
	print("── C1 开局显示 1255-03-01，并按 advance_days 推进")
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_main.load_scene("xinghua")
	await _settle(6)
	_repaint()
	var page := _book_text()
	_expect(str(page).contains("宝祐三年　三月初一"),
		"开局页首显示「宝祐三年　三月初一」（实读前 60：%s）" % str(page).substr(0, 60))
	gm.advance_days(29)  # 3/1 + 29 日 = 三月三十（SceneTree 醒来即 March 初一；advance_days 逐日末步推进）
	_repaint()
	page = _book_text()
	_expect(str(page).contains("三月三十"),
		"advance_days(29) 后页首显示「三月三十」（实读前 60：%s）" % str(page).substr(0, 60))
	gm.advance_days(1)  # 三月三十 + 1 → 四月初一
	_repaint()
	page = _book_text()
	_expect(str(page).contains("四月初一"),
		"再 advance_days(1) 后页首显示「四月初一」（实读前 60：%s）" % str(page).substr(0, 60))


# ── C2 显示月份 = 内部月份（状态不变量，探针自拼参考值）──

func _c2_condition_invariant() -> void:
	print("── C2 页首月名 = 探针自拼月名（逐月各核一次 + 与前月文不同 LCD 校验）")
	var prev_text := ""
	for m in range(1, 13):
		cal.from_dict({"year": 1255, "month": m, "day": 1})
		_repaint()
		var page: String = str(_book_text())
		var wanted := _local_month_name(m)
		_expect(page.contains(wanted),
			"月 %d：页首含「%s」（实读前 60：%s）" % [m, wanted, page.substr(0, 60)])
		if prev_text != "":
			_expect(page != prev_text,
				"月 %d 页文与前月不同（LCD：月份不动时仍显示旧值也要判红）" % m)
		prev_text = page


# ── C3 改元、纪年与年名对照 ────────────────────────────

func _c3_era_and_names() -> void:
	print("── C3 改元与纪年名")
	# 景定元年正月一
	cal.from_dict({"year": 1260, "month": 1, "day": 1})
	_repaint()
	var page: String = str(_book_text())
	_expect(page.contains("正月初一"),
		"景定元年正月一：页首当月日（实读前 60：%s）" % page.substr(0, 60))
	# 年名须与日历 _era_row() 同一基准（探针自拼年份）
	var peep_row: Array = cal.call("_era_row")
	_expect(page.contains(peep_row[2]),
		"页首年号 = 日历 _era_row() 的 %s（实读前 60：%s）" % [str(peep_row[2]), page.substr(0, 60)])
	var ey: int = cal.year - int(peep_row[0]) + 1
	var era_ey: String = str(peep_row[2]) + ("元年" if ey == 1 else _cn(ey) + "年")
	_expect(page.contains(era_ey),
		"景定元年：页首纪年「%s」（实读前 60：%s）" % [era_ey, page.substr(0, 60)])

	# 景炎元年六月（表外锚：景炎 1276-05 起用，ERA_START 1276,5）
	cal.from_dict({"year": 1276, "month": 6, "day": 5})
	_repaint()
	page = str(_book_text())
	_expect(page.contains("景炎元年"),
		"1276-06 页首显示「景炎元年」（实读前 60：%s）" % page.substr(0, 60))
	_expect(page.contains("六月初五"),
		"1276-06 页首显示「六月初五」（实读前 60：%s）" % page.substr(0, 60))

	# 祥兴元年五月（表外锚：祥兴 1278-05 起用）
	cal.from_dict({"year": 1278, "month": 5, "day": 1})
	_repaint()
	page = str(_book_text())
	_expect(page.contains("祥兴元年"),
		"1278-05 页首显示「祥兴元年」（实读前 60：%s）" % page.substr(0, 60))

	# 祥兴元年正月三十 +1 → 二月一（年号不变、月日进一）
	cal.from_dict({"year": 1278, "month": 1, "day": 30})
	gm.advance_days(1)
	_expect(str(cal.get_date_string()).contains("二月初一"),
		"正月三十 +1 日 = 二月初一（历法实读：%s）" % str(cal.get_date_string()))
	_repaint()
	page = str(_book_text())
	_expect(page.contains("二月初一"),
		"祥兴元年正月三十 +1 日：页首「二月初一」（实读前 60：%s）" % page.substr(0, 60))


func _report() -> void:
	print("CALENDAR_PROBE cases=%d fails=%d" % [cases, _fails])
	quit(1 if _fails > 0 else 0)
