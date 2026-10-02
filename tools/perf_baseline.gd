extends SceneTree
## 性能基线探针（lane w20-c10）：在固定场面（默认 = 泉州泊冷启动 → 海图选定航向 → 真航行采样 N 秒）下测
##   帧时（平均 / p50 / p95 / max）、峰值内存（OS.get_memory_usage，每 ≥64 ms 轮询一次，压帧下也赶得上长帧）、
##   启动到可玩（主场景首帧 frame_post_draw 的墙钟 ms；headless 下无渲染、回退取「加进树到第一个 process_frame」）。
## 出基线表见 docs/性能基线.md；本件只管测，红绿归 tools/perf_baseline.py（软档，默认 warn 不 fail）。
## 用法：godot --path . -s res://tools/perf_baseline.gd [-- --scene real|synthe --secs 8 --seed 42 --nd 2]
##       godot --headless --path . -s res://tools/perf_baseline.gd [-- …]            # 无渲染也照常测（纯帧时）
##       godot --quiet --path . -s res://tools/perf_baseline.gd -- --scene real --secs 8 --json   # 机读（tools/gate_report.gd）
##       DISPLAY=:2 NK1_PROBE_SLOW_MS=300 godot --path . -s res://tools/perf_baseline.gd          # 压帧自验
## --scene real：真航行（选远港 → _on_sail_pressed → 逢事件继续 → 抵港或到秒收），量的是「真海图在跑」。
## --scene synthe：基线副支，不进航程，静置载 3D 视口 + 风向环（只量铺好了的海图一页），供发行间横向对账。
## 只动临时层与进程内存，不碰存档槽；本进程出 SCRIPT ERROR 即判红（自挂 Logger 数）。

const TAG := "PERF_BASELINE"
const VIEW := Vector2i(1280, 720)
const GateReport := preload("res://tools/gate_report.gd")
## 不 preload shot_gate / 不调 frame_pressure：本探针**就是**量帧时的，外挂压帧会把指标直接打歪，
## 同时避免被 probe_pressure 收入压帧双档集（它的 SAMPLES 不走「挂上压帧即自动入集」——这里是反例）。

var _fails: Array = []
var _ok: Array = []
var _errlog: _ScriptErrLog = null

var _scene := "real"
var _secs := 8.0
var _seed := 42
var _nd := 2
var _t0 := 0
var _startup_ms := -1
var _startup_windowed := false
var _stats: Array = []
var _peek_mem := 0
var _mem_poll_at := 0
var _frame_count := 0


class _ScriptErrLog:
	extends Logger
	var lines: Array = []

	func _log_error(function: String, _file: String, line: int, _code: String, rationale: String, _notify: bool, _type: int, _script_backtraces: Array) -> void:
		lines.append("%s:%d %s %s" % [function, line, _code, rationale])


func _init() -> void:
	call_deferred("_parse_and_run")


func _parse_and_run() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		var nxt := "" if i + 1 >= args.size() else str(args[i + 1])
		match a:
			"--scene":
				_scene = nxt
				i += 2
				continue
			"--secs":
				_secs = float(nxt)
				i += 2
				continue
			"--seed":
				_seed = int(nxt)
				i += 2
				continue
			"--nd":
				_nd = maxi(1, int(nxt))
				i += 2
				continue
			"--json", "--contract", "--quiet":
				i += 1
				continue
			_:
				i += 1
	if _scene not in ["real", "synthe"]:
		_bail("未知 --scene %s（只认 real / synthe）" % _scene)
		return
	await _run()


func _bail(what: String) -> void:
	_fails.append(what)
	GateReport.check(false, what)
	GateReport.finish("perf_baseline", 2, "%s FAIL（%s）" % [TAG, what])
	quit(2)


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	root.size = VIEW
	seed(_seed)

	_t0 = Time.get_ticks_msec()
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# 窗口下以首帧画完作「启动到可玩」，但指「树挂好后到画完」、不包 .tscn load；
	# headless 无渲染、记一帧后回退（保持同指标可比）。
	var has_renderer := DisplayServer.get_name() != "headless"
	if has_renderer:
		if not RenderingServer.frame_post_draw.is_connected(_on_first_drawn):
			RenderingServer.frame_post_draw.connect(_on_first_drawn, CONNECT_ONE_SHOT)
		_t0 = Time.get_ticks_msec()  # 启动到可玩从挂树算起
	else:
		_startup_ms = -2  # 首个 process_frame 补上
	await process_frame

	var gs: Node = root.get_node("GameState")
	var fleet: Node = root.get_node("Fleet")
	var voyage: Node = root.get_node("Voyage")
	gs.chapter = 4
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou", "hakata"]
	gs.money = maxi(int(gs.money), 800)
	fleet.water = 40
	fleet.food = 40

	var chart_scene: PackedScene = load("res://scenes/SeaChart.tscn")
	if chart_scene == null:
		_cleanup(main, null)
		_bail_and_exit("SeaChart.tscn 不可载（可能遇别的 lane 未合入的签名变动）")
		return
	var chart: Node = chart_scene.instantiate()
	root.add_child(chart)
	await _frames(6)
	if chart == null or chart.get_script() == null:
		_cleanup(main, chart)
		_bail_and_exit("SeaChart.gd 解析不通过（可能遇别的 lane 未合入的签名变动——load() 不报 Parse、
		只在 instantiate 后发现 script 是 Nil；本支基线照けれず）")
		return

	var dest := ""
	var far_d := -1.0
	var hand = chart.get("_hand")
	if hand == null:
		_cleanup(main, chart)
		_bail_and_exit("海图手牌拿不到（_hand 是 Nil；海图脚本可能没果上）")
		return
	for pid in hand:
		var d: float = voyage.distance_li("quanzhou", str(pid))
		if d > far_d:
			far_d = d
			dest = str(pid)
	if dest == "":
		_cleanup(main, chart)
		_bail_and_exit("手牌有去处")
		return
	_ok.append("手牌有去处 → %s（%.0f 里）" % [dest, far_d])

	if _scene == "synthe":
		chart.call("_select_heading", dest)
		await _frames(4)
		chart.set("total_li", far_d)
		chart.set("remaining_li", far_d * 0.42)
		chart.set("course_bearing", voyage.bearing("quanzhou", dest))
		chart.set("days_elapsed", 6)
		chart.set("sailing", true)
		chart.call("_lock_hand")
	else:
		chart.call("_select_heading", dest)
		await _frames(4)
		chart.call("_on_sail_pressed")
		await _frames(2)

	# 采样主环：每帧一对 get_ticks_msec 之差 = 上一帧墙钟时长；事件一至就「继续航行」、「未见底」就停。
	var start_ms := Time.get_ticks_msec()
	var limit_ms := int(_secs * 1000.0)
	var evl: Node = chart.get("event_panel")
	var arrived := false
	while true:
		var a := Time.get_ticks_msec()
		await process_frame
		var b := Time.get_ticks_msec()
		_stats.append(float(b - a))
		_frame_count += 1
		if _startup_ms == -2:
			_startup_ms = b - _t0
		if evl != null and evl.visible and chart.get("pending_event") != null:
			chart.call("_on_event_continue")
		if b - _mem_poll_at >= 64:
			_mem_poll_at = b
			# MEMORY_STATIC_MAX 是进程自启以来静态内存的峰、只升不减，恰是「峰值内存」
			var v := int(Performance.get_monitor(Performance.MEMORY_STATIC))
			_peek_mem = maxi(_peek_mem, v)
		if not bool(chart.get("sailing")):
			arrived = true
			break
		if b - start_ms >= limit_ms:
			break

	if bool(chart.get("sailing")):
		chart.set("sailing", false)
		fleet.at_sea = false
		chart.set("pending_event", null)
		chart.set("remaining_li", 0.0)
		if chart.has_method("_arrive"):
			chart.call("_arrive")
			await _frames(2)
	_cleanup(main, chart)
	if arrived:
		_ok.append("已抵港，采样帧 %d" % _frame_count)
	else:
		_ok.append("到限采样，帧 %d" % _frame_count)

	_check(_frame_count >= 8, "采样帧 ≥ 8（实得 %d）" % _frame_count)
	_check(_stats.size() == _frame_count, "帧时账与帧数同长")
	_check(_peek_mem > 0, "峰值内存 > 0")
	_check(_startup_ms >= 0, "启动到可玩 ≥ 0")
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	OS.remove_logger(_errlog)
	_finish()


func _cleanup(main: Node, chart: Node) -> void:
	if chart != null:
		chart.queue_free()
	main.queue_free()

func await_process_frame_later() -> void:
	pass  # 帧尾统一 await


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _on_first_drawn() -> void:
	if _startup_ms < 0:
		_startup_ms = Time.get_ticks_msec() - _t0


func _bail_and_exit(what: String) -> void:
	_fails.append(what)
	GateReport.check(false, what)
	GateReport.finish("perf_baseline", 1, "%s FAIL（%s）" % [TAG, what])
	quit(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_ok.append(what)
	else:
		_fails.append(what)
	GateReport.check(ok, what)


func _finish() -> void:
	var sorted := _stats.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := 0.0
	var p50 := 0.0
	var p95 := 0.0
	var mx := 0.0
	if n > 0:
		var s := 0.0
		for v in sorted:
			s += v
		avg = s / float(n)
		p50 = sorted[maxi(0, int(float(n) * 0.50) - 1)]
		p95 = sorted[maxi(0, mini(n - 1, int(ceil(0.95 * float(n))) - 1))]
		mx = sorted[n - 1]
	var over50 := 0
	for v in sorted:
		if v > 50.0:
			over50 += 1
	if n == 0:
		_fails.append("没采到帧时")
	_gate_done(avg, p50, p95, mx, over50)


func _gate_done(avg: float, p50: float, p95: float, mx: float, over50: int) -> void:
	print("%s_MM startup_ms=%d frames=%d avg_ms=%.1f p50_ms=%.1f p95_ms=%.1f max_ms=%.1f over50_ms=%d peak_mem_mb=%.1f" % [
		TAG, _startup_ms, _frame_count, avg, p50, p95, mx, over50, _peek_mem / 1048576.0])
	for what in _ok:
		print("  ✓ %s" % what)
	for what in _fails:
		print("  ✗ %s" % what)
	var rc := 0 if _fails.is_empty() else 1
	var summary := "%s %s（%d 项不合；%s 帧起了 %d）" % [TAG, "PASS" if rc == 0 else "FAIL", _fails.size(), _scene, _frame_count]
	print(summary)
	GateReport.check(rc == 0, "scene=%s frames=%d" % [_scene, _frame_count], "帧时 / 峰值内存 / 启动到可玩")
	GateReport.finish("perf_baseline", rc, summary)
	quit(rc)
