extends RefCounted
## 门禁机读输出（lane g2）：GDScript 门禁原生 `--json`，JSON 形状与 tools/gate_json.py 相同（见 docs/GATES.md §二）。
## 开关：用户参数带 `--json`，即 `godot … -s res://tools/X.gd -- --json`。
## 不带 `--json`：check()/warn() 只把条目记进静态数组，finish() 直接返回；不打印、不挂 logger、不碰 Engine.print_to_stdout，
##   门禁人读输出与退出码逐字不变。
## 带 `--json`：本脚本一被 preload（门禁脚本编译时即加载，早于 _init）就在 _static_init 关掉 stdout，门禁与游戏代码的
##   print 一律不外泄；另挂一个 Logger 只数引擎 ERROR / SCRIPT ERROR。收尾 finish() 临时打开 stdout，打一行 JSON。
##   引擎横幅「Godot Engine v…」在脚本加载前就已打出，脚本管不着：要 stdout 恰好一行，命令里加 `--quiet`。
## 用法：const GateReport := preload("res://tools/gate_report.gd")
##   GateReport.check(ok, name[, detail])   GateReport.warn(name[, detail])
##   收尾：GateReport.finish("门禁名", rc, "人读判词行")，然后照旧 quit(rc)。

static var _checks: Array = []
static var _logger: _ErrorCounter = null
static var _finished := false


static func _static_init() -> void:
	if not json_mode():
		return
	Engine.print_to_stdout = false
	_logger = _ErrorCounter.new()
	OS.add_logger(_logger)


static func json_mode() -> bool:
	return "--json" in OS.get_cmdline_user_args()


static func check(ok: bool, name: String, detail := "") -> void:
	_checks.append({"name": name, "ok": ok, "detail": detail})


## warn 条目：ok=true、level=warn，不计入 total/pass/fail（同 gate_json.py 的 ⚠ / COMPILE_CHECK NOTE）。
static func warn(name: String, detail := "") -> void:
	_checks.append({"name": name, "ok": true, "detail": detail, "level": "warn"})


## 入口脚本文件名（去 .gd），截图探针用它当门禁名。
static func main_script_name() -> String:
	var ml := Engine.get_main_loop()
	var s: Script = ml.get_script() if ml != null else null
	return s.resource_path.get_file().get_basename() if s != null else ""


## 收尾打一行 JSON；非 --json 模式什么也不做。只打一次。
static func finish(gate: String, rc: int, summary: String, extra := {}) -> void:
	if not json_mode() or _finished:
		return
	_finished = true
	var checks := _checks.duplicate(true)
	var hard := checks.filter(func(c): return c.get("level", "") != "warn")
	if rc != 0 and hard.all(func(c): return c["ok"]):
		var why := "退出码 %d，但没登记到失败条目（中途崩溃或提前退出）" % rc
		checks.append({"name": "exit_code", "ok": false, "detail": why})
		hard.append(checks[-1])
	var n_pass := hard.filter(func(c): return c["ok"]).size()
	var errors: Array = _logger.lines.duplicate() if _logger != null else []
	var n_script := _logger.script_errors if _logger != null else 0
	var doc := {
		"gate": gate, "ok": rc == 0, "exit_code": rc, "summary": summary, "checks": checks,
		"counts": {"total": hard.size(), "pass": n_pass, "fail": hard.size() - n_pass,
			"warn": checks.size() - hard.size(), "engine_errors": errors.size(), "script_errors": n_script},
		"cmd": [OS.get_executable_path()] + Array(OS.get_cmdline_args()) + ["--"] + Array(OS.get_cmdline_user_args()),
	}
	if not errors.is_empty():
		doc["errors"] = errors.slice(0, 20)
	doc.merge(extra)
	if _logger != null:
		OS.remove_logger(_logger)
	Engine.print_to_stdout = true
	print(JSON.stringify(doc, "", false))
	Engine.print_to_stdout = false


## 只数错误类日志（ERROR / SCRIPT ERROR / SHADER ERROR），WARNING 不计；普通 print 不经此处。
class _ErrorCounter extends Logger:
	const PREFIX := {0: "ERROR", 2: "SCRIPT ERROR", 3: "SHADER ERROR"}
	var lines: Array = []
	var script_errors := 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if not PREFIX.has(error_type):
			return
		_mutex.lock()
		var msg: String = rationale if rationale != "" else code
		lines.append("%s: %s" % [PREFIX[error_type], msg])
		if error_type == 2:
			script_errors += 1
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
