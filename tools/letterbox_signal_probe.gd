extends SceneTree
## 海战墨边（scripts/ui/CombatLetterbox.gd）收尾信号契约的定向探针（lane gd12）：逐条走完每一种收尾路径，
## 查等待方能不能收到终止信号——每幕都挂一个裸 `await lb.finished`（墨边头注释推荐的写法），没被唤醒就是挂死。
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/letterbox_signal_probe.gd [-- --only=finish|abort|bail|parent] [--json]
## 不截图；headless 下墨边静态入口不建节点，本探针判红（须 DISPLAY=:2）。
##
## 契约（CombatLetterbox 头注释）：finished 是终止信号，每副墨边无论怎么收尾都恰好发一次；
## caption_shown / covered 是进度信号，只在真演到时发，最多一次——等进度信号的一方必须带上界，或拿 finished 当放弃的边。
##   finish：正常演完（入战 / 出战不带 on_black / 出战带 on_black）
##   abort ：被新墨边顶掉（题签前 / 全黑前），以及演完当帧又起一副（旧的还在组里）
##   bail  ：探针等不到信号判红收尾——CombatStage.teardown（探针 _bail 与正常收尾同走这一条）
##   parent：墨边挂在布景下、随布景一起被释放，不经 _abort（WorldMap._try_letterbox_enter 即此形状）

const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const GateReport := preload("res://tools/gate_report.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const TAG := "LETTERBOX_SIGNAL_PROBE"
const VIEW := Vector2i(1280, 720)
## 每幕墙钟上界：最长一幕（出战带 on_black）约 3.5 s；帧数另有 CombatStage.WAIT_FRAMES 兜底
const SCENE_MS := 8000
const PATHS := ["finish", "abort", "bail", "parent"]

var _fails: Array = []
var _rows := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	if Kit.is_headless():
		_fails.append("headless 下墨边入口返回 null、无从验信号：请用 DISPLAY=:2 跑")
		_report()
		return
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	if only != "" and not only in PATHS:
		_fails.append("--only=%s 不认（可选 %s）" % [only, "/".join(PATHS)])
		_report()
		return
	for p in PATHS:
		if only == "" or only == p:
			await call("_path_" + p)
	_report()


# ── finish：正常演完 ────────────────────────────────────────────────

func _path_finish() -> void:
	var w := _watch(Letterbox.enter(root, "刺桐外海・遇敌", "咸淳三年六月十二　海鹘二艘"))
	await _settle(w)
	_expect_row("finish/入战", w, {"caption": 1, "covered": 0, "on_black": 0})

	w = _watch(Letterbox.exit(root, "刺桐外海・战罢", "咸淳三年六月十二"))
	await _settle(w)
	_expect_row("finish/出战", w, {"caption": 1, "covered": 0, "on_black": 0})

	w = _watch_exit_black()
	await _settle(w)
	_expect_row("finish/出战带on_black", w, {"caption": 1, "covered": 1, "on_black": 1})


# ── abort：被新墨边顶掉 ─────────────────────────────────────────────

func _path_abort() -> void:
	# 题签擦出前被顶掉：caption_shown 不补发（假信号），finished 照发
	var w := _watch(Letterbox.enter(root, "外洋・遇敌"))
	await _frames(3)
	var nx := _watch(Letterbox.enter(root, "外洋・再遇"))
	await _settle(w)
	_expect_row("abort/题签前", w, {"caption": 0, "covered": 0, "on_black": 0})
	await _settle(nx)
	_expect_row("abort/顶掉它的那副照常演完", nx, {"caption": 1})

	# 全黑前被顶掉：补调 on_black（先发 covered），finished 照发
	w = _watch_exit_black()
	await _frames(3)
	nx = _watch(Letterbox.enter(root, "外洋・遇敌"))
	await _settle(w)
	_expect_row("abort/全黑前", w, {"caption": 0, "covered": 1, "on_black": 1})
	await _settle(nx)

	# 演完当帧又起一副：旧的已 queue_free、还没真释放，_spawn 扫组会再 _abort 它一次
	w = _watch(Letterbox.enter(root, "外洋・遇敌"))
	var chained := [null]
	w.lb.finished.connect(func() -> void: chained[0] = _watch(Letterbox.enter(root, "外洋・续遇")),
		Object.CONNECT_ONE_SHOT)
	await _settle(w)
	_expect_row("abort/演完当帧又起一副", w, {"caption": 1})
	if chained[0] != null:
		await _settle(chained[0])

	# 演完当帧有人直接再 _abort 它（探针收尾 / 调用方自己收场）
	w = _watch(Letterbox.enter(root, "外洋・遇敌"))
	var lb: CanvasLayer = w.lb
	lb.finished.connect(func() -> void: lb.call("_abort"), Object.CONNECT_ONE_SHOT)
	await _settle(w)
	_expect_row("abort/演完当帧又被直接 _abort", w, {"caption": 1})


# ── bail：探针判红收尾（CombatStage.teardown）──────────────────────

func _path_bail() -> void:
	# 探针那两幕的形状：墨边挂 root，布景 wm 另在；出战带 on_black 且 on_black 里放掉布景
	var wm := Node.new()
	wm.name = "StandInWorldMap"
	root.add_child(wm)
	var w := _watch_exit_black(func() -> void: wm.queue_free())
	await _frames(3)
	CombatStage.teardown(self, wm, null)
	await _settle(w)
	_expect_row("bail/出战带on_black（全黑前）", w, {"caption": 0, "covered": 1, "on_black": 1})
	_check(not is_instance_valid(wm), "bail：布景已放掉", "teardown 后布景还在")
	_check(get_nodes_in_group(Letterbox.GROUP).is_empty(), "bail：组里不剩墨边", "teardown 后组里还有墨边")

	# 题签已出、停拍中收尾
	var host := Node.new()
	root.add_child(host)
	w = _watch(Letterbox.enter(root, "刺桐外海・接舷"))
	await CombatStage.wait_signal(self, w.lb, &"caption_shown")
	CombatStage.teardown(self, host, null)
	await _settle(w)
	_expect_row("bail/停拍中", w, {"caption": 1, "covered": 0, "on_black": 0})


# ── parent：随布景释放，不经 _abort ─────────────────────────────────

func _path_parent() -> void:
	var host := Node.new()
	host.name = "StandInWorldMap"
	root.add_child(host)
	var w := _watch(Letterbox.enter(host, "刺桐外海・遇敌"))
	await _frames(3)
	host.queue_free()
	await _settle(w)
	_expect_row("parent/题签前随父释放", w, {"caption": 0, "covered": 0, "on_black": 0})

	host = Node.new()
	root.add_child(host)
	w = _watch(Letterbox.exit(host, "外洋・脱战", "", func() -> void: pass))
	await CombatStage.wait_signal(self, w.lb, &"caption_shown")
	host.queue_free()
	await _settle(w)
	# 随父释放时不补调 on_black、不发 covered：换场的一方（父）自己都没了，补调是往拆了的场里调
	_expect_row("parent/停拍中随父释放（带on_black）", w, {"caption": 1, "covered": 0, "on_black": 0})


# ── 记账 ───────────────────────────────────────────────────────────

## 给一副墨边挂上计数与一个裸 await finished 的等待方；返回记账字典。
func _watch(lb: CanvasLayer) -> Dictionary:
	var w := {"lb": lb, "spawned": lb != null, "caption": 0, "covered": 0, "on_black": 0, "finished": 0,
		"raw_await": false, "ms": 0, "t0": Time.get_ticks_msec()}
	if lb == null:
		return w
	lb.caption_shown.connect(func() -> void: w.caption += 1)
	lb.covered.connect(func() -> void: w.covered += 1)
	lb.finished.connect(func() -> void:
		w.finished += 1
		w.ms = Time.get_ticks_msec() - int(w.t0))
	_raw_waiter(lb, w)
	return w


func _watch_exit_black(extra := Callable()) -> Dictionary:
	var box := [{}]
	var lb := Letterbox.exit(root, "刺桐外海・夺船", "咸淳三年六月十二", func() -> void:
		box[0].on_black += 1
		if extra.is_valid():
			extra.call())
	box[0] = _watch(lb)
	return box[0]


## 裸 await：finished 不来，这个协程永远不醒——就是 gd6 / gd10 挂死的那种等待方
func _raw_waiter(lb: CanvasLayer, w: Dictionary) -> void:
	await lb.finished
	w.raw_await = true


## 等这一幕终结（裸 await 醒了）或到墙钟 / 帧数上界；再多停几帧，让「同帧又起一副」之类的补发有机会冒出来
func _settle(w: Dictionary) -> void:
	var deadline := Time.get_ticks_msec() + SCENE_MS
	var frames := 0
	while not w.raw_await and Time.get_ticks_msec() < deadline and frames < CombatStage.WAIT_FRAMES:
		await process_frame
		frames += 1
	await _frames(4)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect_row(name: String, w: Dictionary, want: Dictionary) -> void:
	var got := "caption=%d covered=%d on_black=%d finished=%d raw_await=%s ms=%d" % [
		w.caption, w.covered, w.on_black, w.finished, "resumed" if w.raw_await else "HUNG", w.ms]
	var bad: PackedStringArray = []
	# 已释放的实例在 4.x 里 == null 也为真，只能看上场那一刻记下的 spawned
	if not w.spawned:
		bad.append("墨边没上场")
	if not w.raw_await:
		bad.append("裸 await finished 没醒（等待方挂死）")
	if w.finished != 1:
		bad.append("finished 应恰好 1 次（%d）" % w.finished)
	for k in want:
		if int(w[k]) != int(want[k]):
			bad.append("%s 应 %d（%d）" % [k, want[k], w[k]])
	_rows += 1
	_check(bad.is_empty(), "%s  %s" % [name, got], "%s：%s  [%s]" % [name, "；".join(bad), got])


func _check(ok: bool, pass_msg: String, fail_msg: String) -> void:
	if ok:
		print("  ✓ ", pass_msg)
		GateReport.check(true, pass_msg)
	else:
		print("  ✗ ", fail_msg)
		_fails.append(fail_msg)


func _report() -> void:
	for f in _fails:
		GateReport.check(false, str(f))
	var line := ("%s_OK rows=%d" % [TAG, _rows]) if _fails.is_empty() \
		else ("%s_FAIL %d（rows=%d）" % [TAG, _fails.size(), _rows])
	print(line)
	var rc := 0 if _fails.is_empty() else 1
	GateReport.finish(GateReport.main_script_name(), rc, line, {"tag": TAG, "rows": _rows})
	quit(rc)
