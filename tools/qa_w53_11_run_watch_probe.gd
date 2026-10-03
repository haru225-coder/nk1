extends SceneTree
## lane w53-11 四轮：截图门禁共用件 tools/shot_gate.gd 的「`_run` 断气兜底」自证探针（回退即红）。
## 起因：截图册探针一律 `_init` → call_deferred("_run")、流程写在 `_run` 本体里；`_run` 自己的代码行出 SCRIPT ERROR 时
##   GDScript 只中止这一个函数，quit() 永不执行——进程空转到外层超时（一键 / probe_pressure 900 s，rc=124 当假红重跑）。
##   shot_gate 现每帧看门：入口 `_run` 断气后宽限 RUN_ABORT_GRACE_FRAMES 帧仍没走到收尾，就地判红退 1。
## 五案（本探针不造真脚本错：往 shot_gate 现役计数器直接喂记录，进程 0 条 SCRIPT ERROR、probe_pressure 两档照绿；
##   真断气由截图探针 `_run` 本体注入实测，见提交说明）：
##   一、看门挂上：shot_gate 被 preload 后、首帧前已把 _run_watch 挂到本树 process_frame
##   二、判据：script_err_tally.run_abort_note 只认入口脚本自己的 `_run` 帧（子函数 / lambda / 别的脚本的 `_run` /
##       Parse Error / 引擎 ERROR 类都不算）
##   三、子函数错不响：喂一条「入口脚本的子函数出错」，过 6 帧看门不响（调用方照走，归收尾判红）
##   四、`_run` 断气即响：再喂一条「入口脚本 `_run` 出错」，看门判红一次、判词点名那条错（经测试口 run_watch_hook 接住，不退出）
##   五、宽限让路：喂错到判红隔 RUN_ABORT_GRACE_FRAMES ～ +2 帧（自带 `_run_guarded` 的探针断气当帧自行收尾，看门不抢）
## 本进程 SCRIPT ERROR 即红（共用件 script_err_tally.gd 两判）；本探针 `_run` 半路被脚本错掐断由 _run_guarded 就地判红收尾。
## 用法：godot --headless --path . -s res://tools/qa_w53_11_run_watch_probe.gd [-- --json]
## 逐案 `  ✓ …` / `  ✗ …`；末行 `QA_W53_11_RUN_WATCH cases=N fails=K`，退 0 / 1。
const ShotGate := preload("res://tools/shot_gate.gd")
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const GateReport := preload("res://tools/gate_report.gd")
const TAG := "QA_W53_11_RUN_WATCH"

var _tally: ScriptErrTally
var _cases := 0
var _fails := 0
var _reported := false
var _fired: Array = []


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	ShotGate.frame_pressure(self)  # gates_md「接 shot_gate 的脚本都挂压帧」口径；未设 NK1_PROBE_SLOW_MS 什么也不挂
	await process_frame
	# 成员一律运行期取：回退了看门的 shot_gate / 计数器照样编得过、逐案判红（编译期点名会编不过、空转到超时）
	var gate: Object = ShotGate
	var me: String = get_script().resource_path
	var no_bt: Array[ScriptBacktrace] = []  # call() 不替定型数组转型，喂入须传定型空数组
	_expect(process_frame.is_connected(Callable(gate, "_run_watch")), "一、看门挂上：shot_gate 被 preload 后首帧前已把 _run_watch 挂到本树 process_frame")

	var t: Object = ScriptErrTally.new()
	t.call("_log_error", "_sub", me, 1, "", "子函数错", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	t.call("_log_error", "<anonymous lambda>", me, 2, "", "lambda 错", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	t.call("_log_error", "_run", "res://scripts/Main.gd", 3, "", "别的脚本的 _run 错", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	t.call("_log_error", "GDScript::reload", me, 4, "", "Parse Error", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	t.call("_log_error", "_run", me, 5, "", "引擎 ERROR 类", false, Logger.ERROR_TYPE_ERROR, no_bt)
	var has_note := t.has_method("run_abort_note")
	var none: String = str(t.call("run_abort_note", me)) if has_note else "（计数器没有 run_abort_note）"
	t.call("_log_error", "_run", me, 6, "", "入口 _run 错", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	var hit: String = str(t.call("run_abort_note", me)) if has_note else ""
	_expect(none == "" and hit.begins_with("入口 _run 错"), "二、判据只认入口脚本自己的 `_run` 帧（前五条不算：%s；第六条点名：%s）" % [
		none if none != "" else "—", hit if hit != "" else "—"])

	gate.set("run_watch_hook", func(why: String) -> void: _fired.append([why, Engine.get_process_frames()]))
	var live: Object = gate.get("_script_errs")
	live.call("_log_error", "_sub", me, 7, "", "子函数里出错（自证喂入）", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	for _i in 6:
		await process_frame
	_expect(_fired.is_empty(), "三、子函数错不响：喂入后 6 帧看门判红 %d 次（应 0）" % _fired.size())

	var g: int = int(gate.get("RUN_ABORT_GRACE_FRAMES")) if gate.get("RUN_ABORT_GRACE_FRAMES") != null else 2
	var fed := Engine.get_process_frames()
	live.call("_log_error", "_run", me, 8, "", "_run 断气（自证喂入）", false, Logger.ERROR_TYPE_SCRIPT, no_bt)
	for _i in g + 6:
		await process_frame
		if not _fired.is_empty():
			break
	var why: String = str(_fired[0][0]) if _fired.size() == 1 else ""
	_expect(_fired.size() == 1 and "_run 断气（自证喂入）" in why and why.begins_with("主流程跑到收尾"),
		"四、`_run` 断气即响：看门判红 %d 次（应 1），判词「%s」" % [_fired.size(), why])
	var lag := int(_fired[0][1]) - fed if not _fired.is_empty() else -1
	_expect(lag >= g and lag <= g + 2, "五、宽限让路：喂错到判红隔 %d 帧（应 %d～%d）" % [lag, g, g + 2])
	_report()


func _expect(ok: bool, msg: String) -> void:
	_cases += 1
	print(("  ✓ " if ok else "  ✗ ") + msg)
	GateReport.check(ok, msg)
	if not ok:
		_fails += 1


func _report() -> void:
	_reported = true
	# 测试口里的 lambda 绑着本主循环实例：退出前不清，引擎拆静态变量时悬空崩（4.6.3 实测 malloc abort，rc=134）
	(ShotGate as Object).set("run_watch_hook", Callable())
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	var rc := 1 if _fails > 0 else 0
	var line := "%s cases=%d fails=%d" % [TAG, _cases, _fails]
	print(line)
	GateReport.finish(GateReport.main_script_name(), rc, line)
	quit(rc)
