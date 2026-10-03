extends Logger
## lane w53-11：必跑 gate 的「本进程 SCRIPT ERROR / Parse Error 即红」判闸共用件。
## 来源：godot_story_check.gd:3135-3147 的 _ScriptErrTally（lane w19-g11 实证：运行期脚本错
## 把断言整段跳没、fails 不涨、`godot --headless -s` 退出码守 0——四支必跑 qa_* strip / rest
## 探针注册表判词照抄 story 的「本进程 SCRIPT ERROR 即红」格却没装 Logger，judge 背书空转）。
## 既接 preload 则必须是 Logger 直系的家：OS.add_logger(_tally) / OS.remove_logger(_tally)
## 对参数静态校验「是 Logger」，preload 的 GDScript 不是；父必须写 extends Logger
## （个体经 ScriptErrTally.new() 造——Godot 4 脚本类名归 preload 句柄用，不再上 class_name
## 公众字典，避免 headless -s 干净跑 `OS.add_script` 时公众字典空、编不过；preload 的
## 多 SceneTree 脚本各持同名实例零走样）。
## 主义复用 story 同款入账规则：只数 `Logger.ERROR_TYPE_SCRIPT`（Parse / Compile / 运行期脚本
## 错都归这条——见 story_check :3133），`ERROR / WARNING`（如 exit 时资源回收噪声、
## push_error / Vulkan 回落）不入账、照打 stderr 不判闸。
## 用法（探针侧，lane w53-11 二轮把收尾两判收进 verdicts()，qa_* 探针同一写法）：
##   _init()        ：_tally = ScriptErrTally.new(); OS.add_logger(_tally); call_deferred("_run_guarded")
##   _run_guarded() ：await _run()；回来时 _report() 还没走过 = _run 半路被脚本错掐断（见下）→
##                    _expect(false, "主流程跑到收尾（%s）" % _tally.abort_note()) 后 _report()，就地判红收尾
##   _report()      ：_reported = true; for v in _tally.verdicts(): _expect(v[0], v[1])，再印末行、quit
## （包装函数不叫 _main：探针多有成员 `var _main: Node` 挂 Main 场景，同名即编不过。）
## 为什么要 _run_guarded 包一层：`_run` 自己的代码行出 SCRIPT ERROR，GDScript 只中止这一个函数——
## `quit()` 再也不执行，`-s` 主循环空转到外层 timeout（rc=124，被当「假红」重跑）；被包一层后
## 中止的协程照样发 completed、`await _run()` 立刻返回（同步段出错 / await 之后出错两种实测都回得来），
## 包装层据此判红退 1。
var lines: Array = []
var _mutex := Mutex.new()
var _detached := false


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	lines.append("%s（%s:%d）" % [rationale if rationale != "" else code, file, line])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## 包装层判「_run 半路中止」时的点名句：有脚本错报首条原文；没有（_run 提前 return、没走收尾）另说一句。
func abort_note() -> String:
	_mutex.lock()
	var s: String = ("_run 半路中止，首条脚本错：" + str(lines[0])) if not lines.is_empty() \
		else "_run 提前 return、没走收尾"
	_mutex.unlock()
	return s


## 收尾两判（story :3156 同款，判词逐字同）：先自证计数器只认 SCRIPT 类——新造一只、喂 SCRIPT /
## ERROR / WARNING 各一须恰数到 1；再摘下本计数器判本进程真路 0 条。返回 [[ok, 判词], [ok, 判词]]，
## 探针逐条喂自家 _expect（各计一案）。摘下后再出的错不再入账；重入不重摘。
func verdicts() -> Array:
	var probe: Logger = get_script().new()
	probe._log_error("f", "res://x.gd", 1, "", "自证 SCRIPT", false, ERROR_TYPE_SCRIPT, [])
	probe._log_error("f", "res://x.gd", 2, "", "自证 ERROR", false, ERROR_TYPE_ERROR, [])
	probe._log_error("f", "res://x.gd", 3, "", "自证 WARNING", false, ERROR_TYPE_WARNING, [])
	var n_probe: int = (probe.get("lines") as Array).size()
	if not _detached:
		_detached = true
		OS.remove_logger(self)
	_mutex.lock()
	var errs: Array = lines.duplicate()
	_mutex.unlock()
	return [
		[n_probe == 1, "SCRIPT ERROR 计数器自证：只数脚本类（喂 SCRIPT / ERROR / WARNING 各一，数到 %d）" % n_probe],
		[errs.is_empty(), "运行中无 SCRIPT ERROR / Parse Error（%d 条%s）" % [errs.size(),
			"" if errs.is_empty() else "，首条：" + str(errs[0])]],
	]
