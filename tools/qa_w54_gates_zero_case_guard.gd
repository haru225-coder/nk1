extends SceneTree
## lane w54-gates：探针「一格断言都没跑过也照样印全部通过」的守卫探针（静态读源码，headless 秒级）。
##
## 起因：tools/qa_w53_4_story_probe.gd 的三节断言全挂在 data/chapters.json 与 data/ports.json
## 遍历出来的每一格上；两档读不进来（文件缺、JSON 坏、结构改名）时 _load 给 {}，三个循环各空转一圈，
## 一格 _check 都过不到，末行照旧印「qa_w53_4_story.gd：全部通过」、退 0——闸的红绿押在「数据在」
## 这件全篇没人判过的事上。修法（同 lane w54-gates 那一笔）：读档后先判「两档都读得出且非空」、收尾判
## 「至少跑过一格断言」（cases>0）、末行出 cases=N fails=M，判绿不再是「没出红字」，而是「数得出来跑过几格」。
##
## 本探针钉两件事（静态读 qa_w53_4_story_probe.gd 的源码，不跑它）：
##   一、判据还在：源码里有「两档非空」那格断言，且 _check 会记 cases。
##   二、判据真能咬人：收尾分支里 cases 参与判红——把 cases>0 那格删掉、或把 quit 改回按 fails 单判，
##       这一格必须红。
## 另带一对内存样本自证：把「空表上全空转 + 照印通过」与「先判非空 + cases>0」两种源码喂给本探针的
## 认法函数，须一红一绿——退掉认法本身（正则改坏、匹配改松）先红在这一格，而不是悄悄放行。
##
## 用法：godot --headless --path . -s res://tools/qa_w54_gates_zero_case_guard.gd（经门锁跑）
## 末行 W54_GATES_ZERO_CASE_GUARD cases=N fails=M；fails>0 退 1。运行期脚本错即红（tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TARGET := "res://tools/qa_w53_4_story_probe.gd"
const TAG := "W54_GATES_ZERO_CASE_GUARD"

var fails := 0
var cases := 0
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
	_run()
	_reported = true
	_report()


func _run() -> void:
	print("%s_BEGIN" % TAG)
	var src := _read(TARGET)
	_expect(src != "", "%s 读得出（%d 字符）" % [TARGET, src.length()])
	if src == "":
		return

	# ── 一、判据还在 ──
	_expect(_has_data_guard(src),
		"读档后先判两档非空：源码里有对 chapters / ports 非空的 _check")
	_expect(_counts_cases(src),
		"_check 记 cases：源码里 cases 随断言累加")
	_expect(_has_zero_case_red(src),
		"收尾判「至少跑过一格断言」（cases 参与判红）")
	_expect(not src.contains("qa_w53_4_story.gd：全部通过"),
		"末行不再是一句无计数的「全部通过」——出 cases=N fails=M 才算数得出跑过几格")

	# ── 二、判据真能咬人：两个反例源码各须判红、正例判绿 ──
	var vacuous := _fixture_vacuous()
	var guarded := _fixture_guarded()
	_expect(not _pass_path_honest(vacuous),
		"自证（反例一）：空表上全空转、照印「全部通过」的写法判红")
	_expect(not _pass_path_honest(vacuous.replace("var fails := 0", "var fails := 0\nvar cases := 0")
			.replace("func _check(cond: bool, msg: String) -> void:\n", "func _check(cond: bool, msg: String) -> void:\n\tcases += 1\n")),
		"自证（反例二）：记了 cases、收尾仍只按 fails 判绿的写法判红")
	_expect(_pass_path_honest(guarded),
		"自证（正例）：先判两档非空、收尾 cases>0 的写法判绿")


## 认法：两档读档后有无「非空」断言（chapters.json / ports.json 都要点名，且那句是 _check）
func _has_data_guard(src: String) -> bool:
	var has_ch := src.find("chapters.json") >= 0 and src.find("chapters.get(\"chapters\", []).size() > 0") >= 0
	var has_pt := src.find("ports.json") >= 0 and src.find("ports.get(\"ports\", []).size() > 0") >= 0
	return has_ch and has_pt


## 认法：_check 里 cases 随每一格断言累加（cases += 1），不是摆设变量
func _counts_cases(src: String) -> bool:
	var body := _func_body(src, "_check")
	return body.contains("cases += 1")


## 认法：收尾分支里 cases 参与判红——有 cases > 0 那格断言，或 quit 按 cases 与 fails 合并判
func _has_zero_case_red(src: String) -> bool:
	if src.contains("cases > 0"):
		return true
	var i := src.find("quit(")
	while i >= 0:
		var line_end := src.find("\n", i)
		var line := src.substr(i, line_end - i if line_end >= 0 else src.length() - i)
		if line.contains("cases"):
			return true
		i = src.find("quit(", i + 1)
	return false


## 把两种写法各自过一遍真源码里的两条认法，判这一支是不是「空转也能绿」
func _pass_path_honest(src: String) -> bool:
	return _has_data_guard(src) and _counts_cases(src) and _has_zero_case_red(src) \
		and not src.contains("qa_w53_4_story.gd：全部通过")


## 反例（修前原样，节选）：两档读进空表、三节空转、末行印全部通过
func _fixture_vacuous() -> String:
	return """extends SceneTree
var fails := 0
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1
func _init() -> void:
	var chapters: Dictionary = _load("res://data/chapters.json")
	var ports: Dictionary = _load("res://data/ports.json")
	for ch in chapters.get("chapters", []):
		_check(true, "章 %s" % ch.get("id"))
	if fails > 0:
		quit(1)
		return
	print("qa_w53_4_story.gd：全部通过")
	quit(0)
"""


## 正例（修后原样，节选）：先判两档非空、_check 记 cases、收尾 cases>0
func _fixture_guarded() -> String:
	return """extends SceneTree
var fails := 0
var cases := 0
func _check(cond: bool, msg: String) -> void:
	cases += 1
	if cond:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		fails += 1
func _init() -> void:
	var chapters: Dictionary = _load("res://data/chapters.json")
	var ports: Dictionary = _load("res://data/ports.json")
	_check(chapters.get("chapters", []).size() > 0 and ports.get("ports", []).size() > 0, "两档非空")
	_check(cases > 0, "至少跑过一格断言")
	quit(1 if fails > 0 else 0)
"""


## 行首 func 起、到下一个行首 func / static func 为止（含缩进体；认法只看 _check 的小体，够用）
func _func_body(src: String, name: String) -> String:
	var head := "\nfunc %s(" % name
	var i := src.find(head)
	if i < 0 and src.begins_with("func %s(" % name):
		i = 0
	if i < 0:
		return ""
	var start := i + 1
	var nxt := src.find("\nfunc ", start)
	var alt := src.find("\nstatic func ", start)
	if nxt < 0 or (alt >= 0 and alt < nxt):
		nxt = alt
	return src.substr(start, nxt - start if nxt >= 0 else src.length() - start)


func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _report() -> void:
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	if fails == 0:
		print("%s cases=%d fails=0" % [TAG, cases])
		quit(0)
		return
	print("%s cases=%d fails=%d" % [TAG, cases, fails])
	quit(1)
