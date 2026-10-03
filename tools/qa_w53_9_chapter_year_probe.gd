extends SceneTree
## lane w53-9：章节卡上的年号（Cinematics.year_text）与历法同一个口径。
## 晋升时章节卡按「当前年 + 跳年」现算年号（ChapterSheet.cinema_before_sheet 与 Main 首港卡都只传年、不传月；
## 跳年只整年地跳、月份不变，所以卡出来那一刻的月就是当前历法的月）。原写法按年取年号表第一条、不认改元的月份：
## 1276 年五月起历法已是「景炎元年」，卡上照写「德祐二年」；1278 年五月起历法是「祥兴元年」，卡上照写「景炎三年」——
## 晋升册页的「四年后・景炎元年八月初一」就压在卡底下，同一屏两个年号。
## 断言：
##   一、1253–1295 逐年逐月把 Calendar 拨到该年月：year_text(年, Calendar.ERAS) 的「年号＋年数」段 == Calendar.get_era_year_string()，
##       「・」后的公元数字 == 该年的中文数字；历法表外（「未纪」）时 year_text 给空串（章节卡退回数据里的静态年号）。
##   二、四个点名锚：1276 三月 / 八月、1278 四月 / 六月（防口径整体漂移时第一条只报个数）。
## 用法：godot --headless --path . -s res://tools/qa_w53_9_chapter_year_probe.gd
## 输出末行 QA_W53_9_CHAPTER_YEAR OK | FAIL <n>；rc 0 / 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd，
## _run 半路被脚本错掐断由 _run_guarded 就地判红）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W53_9_CHAPTER_YEAR"
const DIGITS := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

var _tally: ScriptErrTally
var _fails := 0
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _expect(ok: bool, msg: String) -> void:
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		_fails += 1


func _cn_digits(y: int) -> String:
	var s := ""
	for ch in str(y):
		s += DIGITS[int(ch)]
	return s


func _run() -> void:
	await process_frame
	var cal: Node = root.get_node_or_null("Calendar")
	# Cinematics 引 SaveLoad（autoload），-s 主循环里 preload 编不过，照 qa_calendar_probe 走 load()
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cal == null or cine == null:
		_expect(false, "Calendar autoload / Cinematics.gd 取不到（cal=%s cine=%s）" % [cal, cine])
		_report()
		return
	var eras: Array = cal.get_script().get_script_constant_map().get("ERAS", [])
	var keep := [cal.year, cal.month, cal.day]
	var bad := PackedStringArray()
	var cells := 0
	for y in range(1253, 1296):
		for m in range(1, 13):
			cal.year = y
			cal.month = m
			cal.day = 1
			cells += 1
			var got := str(cine.call("year_text", y, eras))
			if str(cal.call("get_era")) == "未纪":
				if got != "":
					bad.append("%d-%02d 历法表外、卡却写「%s」" % [y, m, got])
				continue
			var want := "%s・%s" % [str(cal.call("get_era_year_string")), _cn_digits(y)]
			if got != want:
				bad.append("%d-%02d 卡「%s」/ 历法「%s」" % [y, m, got, want])
	_expect(bad.is_empty(), "1253–1295 逐月 %d 格：章节卡年号与历法同口径（不符 %d 格%s）" % [cells, bad.size(),
		"" if bad.is_empty() else "：" + "；".join(bad.slice(0, 6)) + ("……" if bad.size() > 6 else "")])
	for a in [[1276, 3, "德祐二年・一二七六"], [1276, 8, "景炎元年・一二七六"], [1278, 4, "景炎三年・一二七八"], [1278, 6, "祥兴元年・一二七八"]]:
		cal.year = int(a[0])
		cal.month = int(a[1])
		var g := str(cine.call("year_text", int(a[0]), eras))
		_expect(g == str(a[2]), "%d 年 %d 月晋升：卡写「%s」（实 %s）" % [a[0], a[1], a[2], g])
	cal.year = keep[0]
	cal.month = keep[1]
	cal.day = keep[2]
	_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("%s %s" % [TAG, "OK" if _fails == 0 else "FAIL %d" % _fails])
	quit(1 if _fails > 0 else 0)
