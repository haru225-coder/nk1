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
var lines: Array = []
var _mutex := Mutex.new()


func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	lines.append("%s（%s:%d）" % [rationale if rationale != "" else code, file, line])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
