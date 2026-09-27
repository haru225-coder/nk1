extends SceneTree
## 海战墨边（scripts/ui/CombatLetterbox.gd）收尾信号契约的定向探针（lane gd12）：逐条走完每一种收尾路径，
## 查等待方能不能收到终止信号——每幕都挂一个裸 `await lb.finished`（墨边头注释推荐的写法），没被唤醒就是挂死。
## Run: DISPLAY=:2 godot --path . -s res://tools/letterbox_signal_probe.gd [-- --only=finish|abort|bail|parent] [--json]
## 不截图；headless 下墨边静态入口不建节点，本探针判红（须 DISPLAY=:2）。
##
## 契约（CombatLetterbox 头注释）：finished 是终止信号，每副墨边无论怎么收尾都恰好发一次；
## caption_shown / covered 是进度信号，只在真演到时发，最多一次——等进度信号的一方必须带上界，或拿 finished 当放弃的边。
##   finish：正常演完（入战 / 出战不带 on_black / 出战带 on_black）
##   abort ：被新墨边顶掉（题签前 / 全黑前），以及演完当帧又起一副（旧的还在组里）
##   bail  ：探针等不到信号判红收尾——CombatStage.teardown（探针 _bail 与正常收尾同走这一条）
##   parent：墨边挂在布景下、随布景一起被释放，不经 _abort（WorldMap._try_letterbox_enter 即此形状）
## 推进口径（lane gd14）：「题签前 / 全黑前」收尾按墨边相位下手（已上场、进度信号还没发），下手当刻把前提写成断言，
##   不数帧（原先数 3 帧：每帧 delta 封顶 0.133 s，3 帧至多 0.4 s，落不过 1.12 s 题签，本不会错；改写是让前提可见）。
##   每幕只按墙钟 SCENE_MS 等（原另有 6000 帧兜底，快机上 6000 帧只合 25 s，从来不先到，删）。
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/letterbox_signal_probe.gd

const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const CombatStage := preload("res://tools/combat_probe_stage.gd")
const GateReport := preload("res://tools/gate_report.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const Clock := preload("res://tools/probe_clock.gd")
const TAG := "LETTERBOX_SIGNAL_PROBE"
const VIEW := Vector2i(1280, 720)
## 每幕墙钟上界：最长一幕（出战带 on_black）约 3.5 s 游戏时间。原 8 s：慢过 7.5 fps 时每帧 delta 封顶 0.133 s，
## 游戏时间比墙钟慢（每帧 400 ms 时 3 倍，这一幕要 10.5 s 墙钟），压帧下误报「挂死」（lane gd14 实测）；
## 20 s：每帧 400 ms 时仍留近一倍余量。
## 上界（lane gd20 实测）：最长一幕在封顶下要 28 帧，墙钟每帧（压帧 + 渲染）过 ≈ 700 ms 就等不完——本机 NK1_PROBE_SLOW_MS=500 绿、
## 950 红。超上界不许靠「多停 4 帧」碰运气变绿，也不许报成「挂死」：墨边还在演就记「墙钟上界先到」判红（见 _settle）。
const SCENE_MS := 20000
## 最长一幕的游戏时长留量：上界先到时本幕已走的游戏时间不到它，才算「压帧过重、没演完」；过了它还在演就是墨边卡住
const SCENE_GAME_S := 5.0
const PATHS := ["finish", "abort", "bail", "parent"]

var _fails: Array = []
var _rows := 0
## 墙钟上界先到、本幕游戏时间还没走够的行数（压帧过重）；--json 里带 error=wall_clock 单列，与契约回归 / 墨边卡住分得开
var _timeouts := 0


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
	Clock.frame_pressure(self)
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
	await _before(w, "abort/题签前")
	var nx := _watch(Letterbox.enter(root, "外洋・再遇"))
	await _settle(w)
	_expect_row("abort/题签前", w, {"caption": 0, "covered": 0, "on_black": 0})
	await _settle(nx)
	_expect_row("abort/顶掉它的那副照常演完", nx, {"caption": 1})

	# 全黑前被顶掉：补调 on_black（先发 covered），finished 照发
	w = _watch_exit_black()
	await _before(w, "abort/全黑前")
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
	await _before(w, "bail/全黑前")
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
	await _before(w, "parent/题签前")
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
		"raw_await": false, "ms": 0, "t0": Time.get_ticks_msec(), "timeout": "", "pressure": false}
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


## 等这一幕终结（裸 await 醒了）或到墙钟上界；再多停 4 帧，让「同帧又起一副」之类的补发有机会冒出来
## （补发走 call_deferred / 下一帧的 _process，按帧等是对的）。
## 上界先到、墨边还在演（仍在树上、未终结），按这段等待实走的游戏时间分两种，本行都判红，且不看那 4 帧里 finished
## 来没来（lane gd20：每帧 950 ms 时有的行靠这 4 帧碰上 finished 变绿、有的没碰上报「挂死」）：
##   不到 SCENE_GAME_S：压帧过重、本幕没演完，报上界（不是挂死，也不是墨边的错）；
##   过了 SCENE_GAME_S：游戏时间够了还在演，是墨边卡住。
## 墨边已终结 / 已释放而裸 await 仍没醒，才是真挂死，照旧由 _expect_row 报。
func _settle(w: Dictionary) -> void:
	var f0 := Engine.get_process_frames()
	var game_s := [0.0]
	if not await Clock.until(self, func() -> bool:
			game_s[0] += root.get_process_delta_time()
			return w.raw_await, SCENE_MS):
		var lb = w.lb
		if lb != null and is_instance_valid(lb) and lb.is_inside_tree() and not bool(lb.get("_done")):
			var n := Engine.get_process_frames() - f0
			w.pressure = game_s[0] < SCENE_GAME_S
			if w.pressure:
				w.timeout = "墙钟上界 %d ms 先到、墨边还在演（%d 帧只走了 %.1f s 游戏时间，本幕最长约 3.5 s）：压帧过重、本行判不了，不是挂死；上界见 SCENE_MS 注释" % [
					SCENE_MS, n, game_s[0]]
			else:
				w.timeout = "墨边卡住：已走 %.1f s 游戏时间（%d 帧）仍未收尾，本幕最长约 3.5 s" % [game_s[0], n]
	await _frames(4)


## 「题签前 / 全黑前」下手的时刻：墨边已真演起来（上边合拢补间走过一帧），进度信号一个都还没发。
## 下手当刻复核：已发了说明墨边时序变了（题签 / 全黑比合拢先到），本行前提不成立——记红，不把别的路径当这条验。
func _before(w: Dictionary, tag: String) -> void:
	var lb = w.lb
	await Clock.until(self, func() -> bool:
		return lb == null or not is_instance_valid(lb) or (lb.get("_top") as Control).size.y > 0.0, SCENE_MS)
	_check(w.caption == 0 and w.covered == 0 and w.finished == 0,
		"%s：下手时墨边已上场、进度信号未发" % tag,
		"%s：下手时进度信号已发（题签 %d / 全黑 %d / 终结 %d），前提不成立" % [tag, w.caption, w.covered, w.finished])


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _expect_row(name: String, w: Dictionary, want: Dictionary) -> void:
	var got := "caption=%d covered=%d on_black=%d finished=%d raw_await=%s ms=%d" % [
		w.caption, w.covered, w.on_black, w.finished, "resumed" if w.raw_await else "HUNG", w.ms]
	var bad: PackedStringArray = []
	if str(w.timeout) != "":
		_rows += 1
		_timeouts += 1 if w.pressure else 0
		_check(false, "", "%s：%s  [%s]" % [name, w.timeout, got])
		return
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
	# 每一幕都已终结（上面逐行判过 finished），墨边协程须全部醒来自退、一个不剩（lane gd15：没醒的退出时报 ObjectDB 泄漏）
	if not Kit.is_headless():
		_check(Letterbox.waiters == 0, "收尾：墨边协程全部醒来（waiters=0）",
			"收尾：仍有 %d 个墨边协程挂在等待上（没被唤醒，退出会报 ObjectDB 泄漏）" % Letterbox.waiters)
	for f in _fails:
		GateReport.check(false, str(f))
	var line := ("%s_OK rows=%d" % [TAG, _rows]) if _fails.is_empty() \
		else ("%s_FAIL %d（rows=%d）" % [TAG, _fails.size(), _rows])
	print(line)
	var rc := 0 if _fails.is_empty() else 1
	var extra := {"tag": TAG, "rows": _rows}
	if _timeouts > 0:
		extra["error"] = "wall_clock"
		extra["timeouts"] = _timeouts
	GateReport.finish(GateReport.main_script_name(), rc, line, extra)
	quit(rc)
