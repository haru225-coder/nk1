extends RefCounted
## 截图门禁小工具（Lane m3 / ASTRA_AUDIT M3）：把「截图探针」与「无渲染契约探针」分开。
## 默认严格：headless / 空视口 / 空图 / 实得张数不足声明张数 → 非零退出，并写明是 headless 还是真失败。
## 契约模式须显式开：命令行 `-- --contract`（或环境变量 NK1_SHOT_CONTRACT=1）；此时不截图，只验非渲染断言，
## 收尾打 `<TAG>_CONTRACT_OK`，绝不打 `OK shots=0`。
## 用法：const ShotGate := preload("res://tools/shot_gate.gd")
## 输出目录：`var OUT_DIR := ShotGate.out_dir("vision")`。默认落 /workspace/nk1-qa-shots/<子目录>；
## 设环境变量 NK1_SHOT_DIR=<目录> 则整体改落 <目录>/<子目录>（worktree / 自测别覆盖证据图，lane gd2）。
## `-- --json`：三个收尾函数改打一行 JSON（gate_report.gd，lane g2），门禁名取入口脚本文件名；调用方不用改。
## finish_shots / finish_contract 的 error：判红时写进 JSON 的 error 字段（如 _bail 的 "no_signal"，lane gd12），
##   让「中途等不到信号收尾」与「张数不足」等普通红分得开；人读输出不变，不判红时不写。
## 压帧自检 frame_pressure(tree)（lane gd18 收口：gd11 / gd14 在 combat_probe_stage / probe_clock 各起过一份，都收进这里）：
##   环境变量 NK1_PROBE_SLOW_MS=<毫秒> 时在 root 下挂一个节点、每帧 OS.delay_msec 压帧（模拟满载慢帧，gd10 复现手法）；
##   未设什么也不挂；重复调只挂一次，不叠压。「压帧下也绿」是全体有窗口探针的口径：截图探针与只借本文件挂压帧的
##   定向探针（letterbox_signal / qa_yard_transition，不截图、不入截图册）开场都调它；
##   gates_md 查每个接本文件的脚本代码行里都调了 ShotGate.frame_pressure，漏挂判红。
##     NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd
## 墙钟上界兜底（lane gd24）：两个收尾函数先看 probe_clock 的账——本进程有等待撞了上界，而调用方没判红（没看返回、
##   靠多停几帧碰运气），补一条红；error 没给且有「压帧过重」的撞界时填 wall_clock，JSON 另带 timeouts（压帧过重次数）/
##   stalls（卡住次数）。口径见 probe_clock 头注释「三」。
## 被测树自检 start_tree_probe(path, fails, label) + check_fields(inst, required, fails, label)（lane w23-a9，接 w22-h5 遗留 / c7 修法二）：
##   截图探针实例化被测场景前的三种秒级判红症状共用面——1) load() 返回 null；2) instantiate() 返回 null；
##   3) 实例在但脚本没挂上（SceneTree 上 tscn 根 GDScript Parse Error 时 instantiate 照常返回非 null 的 Node 壳，
##   此时 get_script() 为 null、脚本字段全 nil；不拦，裸 add_child(壳) → 后续 _chart.get("map") == null → 一路 SCRIPT ERROR，
##   最后被外层 900 s 超时 / probe_clock 墙钟兜底慢红）。这三查 start_tree_probe 同步做，返回 null == 已判红，
##   调用方接着 _report() 收尾。点名「脚本贴上后必须非 null 的字段」由 check_fields 做、因 @onready / _ready
##   入树过帧后才挂的字段必须放在 add_child+_frames 之后才能点，否则会误报；各道的 required 清单不同、不进共用面硬编码。
##   例：
##     _chart = ShotGate.start_tree_probe(CHART_SCENE, _fails, "SeaChart 01 港名密区")
##     if _chart == null: _report(); return
##     root.add_child(_chart); await _frames(8)
##     if not ShotGate.check_fields(_chart, {"map": "MapView path 错"}, _fails, "SeaChart 01 港名密区"): _report(); return
##   红是因为挂不出 / 字段 nil 时，fails 各追加一条带【label / 症状 / 排查法】的中文行——人读秒懂、机器也读 json error。
##   与源码探查 src_probe 不合并同用：那只读文件层（源码字号 / 开关 / 旗号），这层「起场景、逐字段试」，层不同。
## 本进程 SCRIPT ERROR 即红（lane w53-11）：本件一被 preload（探针脚本编译时、早于其 _init）就在 _static_init 挂共用件
##   tools/script_err_tally.gd 的计数器（只数 ERROR_TYPE_SCRIPT；push_error / 引擎 ERROR 不算）；finish_shots /
##   finish_contract 收尾时判 verdicts() 两判（计数器自证 + 本进程 0 条，判词同 story :3156），判不过的进 fails →
##   `<TAG>_FAIL`。此前截图探针中途出脚本错照样拍够张数打 `<TAG>_OK`、退 0（gate_report 原生 --json 也只数 script_errors
##   不改判定）；二十五支截图册探针接线前现网全跑 0 条 SCRIPT ERROR。

const DEFAULT_SHOT_ROOT := "/workspace/nk1-qa-shots"
const GateReport := preload("res://tools/gate_report.gd")
const Clock := preload("res://tools/probe_clock.gd")
const ENV_SLOW := "NK1_PROBE_SLOW_MS"
const PRESSURE_NODE := "ProbeFramePressure"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

static var _script_errs: ScriptErrTally = null


static func _static_init() -> void:
	_script_errs = ScriptErrTally.new()
	OS.add_logger(_script_errs)


## 收尾前判本进程 SCRIPT ERROR（头注释「本进程 SCRIPT ERROR 即红」）：两判里判不过的进 fails，判得过的不另打印。
static func _script_err_fails(fails: Array) -> void:
	if _script_errs == null:
		return
	for v in _script_errs.verdicts():
		if not v[0]:
			fails.append(str(v[1]))


## 截图输出目录：NK1_SHOT_DIR 为空取默认根；相对路径按启动时的 $PWD 展开。
static func out_dir(sub: String) -> String:
	var root := OS.get_environment("NK1_SHOT_DIR").strip_edges()
	if root == "":
		root = DEFAULT_SHOT_ROOT
	elif not root.is_absolute_path():
		root = OS.get_environment("PWD").path_join(root)
	return root.path_join(sub)


## NK1_PROBE_SLOW_MS>0 时挂压帧节点，返回每帧压的毫秒数；未设返回 0、什么也不挂。已挂过的不再挂，返回那一份的毫秒数。
static func frame_pressure(tree: SceneTree) -> int:
	var ms := int(OS.get_environment(ENV_SLOW).strip_edges())
	if ms <= 0 or tree == null:
		return 0
	var had := tree.root.get_node_or_null(PRESSURE_NODE)
	if had != null:
		return int(had.get("ms"))
	var n := _FramePressure.new()
	n.ms = ms
	n.name = PRESSURE_NODE
	tree.root.add_child(n)
	print("  %s=%d：每帧压 %d ms（约 %.1f fps 以下）" % [ENV_SLOW, ms, ms, 1000.0 / ms])
	return ms


class _FramePressure extends Node:
	var ms := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		OS.delay_msec(ms)


## 被测树自检（头注释）：load / instantiate / get_script 三查同步做，秒级判红后返回 null；
## 调用方判 null == 判红、接着 _report() 收尾。点名字段由 check_fields 做、必须放在 add_child+过帧之后
## （@onready / _ready 里才挂上的字段在未入树时当然为 null——一体做会误报）。
static func start_tree_probe(path: String, fails: Array = [], label := "") -> Node:
	var where := "【%s】" % label if label != "" else "【截图道】"
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		fails.append("%s load(%s) 返回 null（场景文件缺 / 根脚本 Parse Error / 依赖链断）：本道秒级判红不等；请在编辑器打开 %s 看第一处错" % [where, path, path])
		return null
	var inst: Node = packed.instantiate()
	if inst == null:
		fails.append("%s load(%s) 成功但 instantiate() 返回 null（根节点 null / 根脚本的 extends 链 Parse Error）：本道秒级判红不等；请在编辑器打开 %s 逐级查红" % [where, path, path])
		return null
	if inst.get_script() == null:
		fails.append("%s %s 挂上了但 get_script() == null：根脚本有 Parse Error（SceneTree 下 tscn 遇见 Parse Error 的 GDScript 会照常 instantiate 出 Node 壳，字段全 nil——不拦会一路 SCRIPT ERROR、让截图门禁等 900 s）；请在编辑器打开 %s 根节点的脚本改语法错" % [where, path, path])
		return null
	return inst


## 共用自检第二段（头注释）：入树过帧后检查调用方点名的字段。返回 true=全齐，false=有 nil（已 append 一条可读原因进 fails）。
## 调用方「if not ShotGate.check_fields(...): _report(); return」——与 start_tree_probe 同体例。
static func check_fields(inst: Node, required: Dictionary, fails: Array, label := "") -> bool:
	var where := "【%s】" % label if label != "" else "【截图道】"
	var path := str(inst.scene_file_path) if inst != null else "<null>"
	for key: String in required.keys():
		if inst == null or inst.get(key) == null:
			var hint := str(required[key]).strip_edges()
			if hint != "":
				hint = "（%s）" % hint
			fails.append("%s %s 挂上了但点名字段 %s == null%s：本道秒级判红不等；请开编辑器查 %s 里这个名字的 path / preload / autoload 依赖" % [where, path, key, hint, path.get_file().get_basename() + ".gd"])
			return false
	return true


static func contract_mode() -> bool:
	if OS.get_environment("NK1_SHOT_CONTRACT") == "1":
		return true
	return "--contract" in OS.get_cmdline_user_args()


## 无渲染环境时返回中文原因；有渲染返回 ""。
static func no_render_reason() -> String:
	if DisplayServer.get_name() == "headless":
		return "headless 无渲染环境（DisplayServer=headless）：截图门禁无法判定，请用 DISPLAY=:2 跑；只验契约请显式加 -- --contract"
	var drv := RenderingServer.get_current_rendering_driver_name()
	if drv == "" or drv == "dummy":
		return "渲染驱动为 dummy（%s）：无渲染环境，截图门禁无法判定，请用 DISPLAY=:2 跑；只验契约请显式加 -- --contract" % drv
	return ""


## 取当前视口图；空视口/空图返回 null 并把真失败原因写进 fails。
static func grab(root: Window, name: String, fails: Array) -> Image:
	var tex := root.get_texture()
	if tex == null:
		fails.append("真失败：%s 视口纹理为空（有窗口却无纹理）" % name)
		return null
	var img := tex.get_image()
	if img == null or img.is_empty() or img.get_width() == 0 or img.get_height() == 0:
		fails.append("真失败：%s 视口图像为空（有窗口却取不到画面）" % name)
		return null
	return img


## 画面是否为一色（空视口/未绘制）：32×18 网格采样全都几乎相同即判空。
## 网格要密：墨幕题签帧只有正中一条题签（约占纵向 36%–47%），5×5 网格会整条跨过去误判一色（lane sg2）。
const BLANK_GRID := Vector2i(32, 18)


static func is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / (2 * BLANK_GRID.x), h / (2 * BLANK_GRID.y))
	for gy in BLANK_GRID.y:
		for gx in BLANK_GRID.x:
			var c := img.get_pixel(int(w * (gx + 0.5) / BLANK_GRID.x), int(h * (gy + 0.5) / BLANK_GRID.y))
			if absf(c.r - first.r) + absf(c.g - first.g) + absf(c.b - first.b) > 0.03:
				return false
	return true


## 截一张：空视口 / 一色空图（allow_blank=false 时）/ 存盘失败都记为真失败；成功把路径追加进 saved。
static func shot(root: Window, path: String, saved: Array, fails: Array, allow_blank := false) -> Image:
	var name := path.get_file()
	var img := grab(root, name, fails)
	if img == null:
		return null
	if not allow_blank and is_blank(img):
		fails.append("真失败：%s 画面一色（空视口或未绘制）" % name)
		return img
	var err := img.save_png(path)
	if err != OK:
		fails.append("真失败：%s 存盘失败（err=%d）" % [path, err])
		return img
	saved.append(path)
	print("  shot %s %dx%d" % [path, img.get_width(), img.get_height()])
	return img


## 墙钟上界兜底（头注释）：有撞界而 fails 为空时补一条红；返回要写进 JSON 的 error，timeouts / stalls 写进 extra。
static func _wall_clock(fails: Array, error: String, extra: Dictionary) -> String:
	var hits := Clock.pressure_hits + Clock.stall_hits
	if hits == 0:
		return error
	extra["timeouts"] = Clock.pressure_hits
	if Clock.stall_hits > 0:
		extra["stalls"] = Clock.stall_hits
	if Clock.pressure_hits > 0:
		print("  注：本跑 %d 次等待墙钟上界先到、压帧过重（不是挂死，也不是被测件的错；--json error=%s）" % [
			Clock.pressure_hits, Clock.WALL_CLOCK])
	if fails.is_empty():
		fails.append("有 %d 次等待撞了墙钟上界（压帧过重 %d / 卡住 %d）却没判红：调用方没看返回，这一跑是碰运气得来的绿，判不了" % [
			hits, Clock.pressure_hits, Clock.stall_hits])
	if error == "" and Clock.pressure_hits > 0:
		return Clock.WALL_CLOCK
	return error


## 截图模式收尾：实得张数 < 声明张数也判失败。返回退出码。
static func finish_shots(tag: String, saved: Array, expected: int, out_dir: String, fails: Array, error := "") -> int:
	_script_err_fails(fails)
	if saved.size() < expected:
		fails.append("真失败：声明 %d 张截图，实得 %d 张" % [expected, saved.size()])
	var extra := {"tag": tag, "shots": saved.size(), "expected_shots": expected, "out_dir": out_dir}
	error = _wall_clock(fails, error, extra)
	for p in saved:
		GateReport.check(true, str(p).get_file(), "shot")
	for f in fails:
		GateReport.check(false, str(f))
	if fails.is_empty():
		var ok_line := "%s_OK shots=%d/%d -> %s" % [tag, saved.size(), expected, out_dir]
		print(ok_line)
		GateReport.finish(GateReport.main_script_name(), 0, ok_line, extra)
		return 0
	for f in fails:
		print("  ✗ ", f)
	var fail_line := "%s_FAIL %d（shots=%d/%d -> %s）" % [tag, fails.size(), saved.size(), expected, out_dir]
	print(fail_line)
	if error != "":
		extra["error"] = error
	GateReport.finish(GateReport.main_script_name(), 1, fail_line, extra)
	return 1


## 无渲染又未开契约模式：直接判红。返回退出码 1。
static func fail_no_render(tag: String, reason: String, expected: int) -> int:
	print("  ✗ ", reason)
	var line := "%s_FAIL headless（声明 %d 张截图，实得 0；此为环境不具备，不是画面回归）" % [tag, expected]
	print(line)
	GateReport.check(false, reason, "no-render")
	GateReport.finish(GateReport.main_script_name(), 1, line, {"tag": tag, "shots": 0, "expected_shots": expected, "no_render": true})
	return 1


## 契约模式收尾：只报契约断言，不报张数。返回退出码。
static func finish_contract(tag: String, fails: Array, error := "") -> int:
	_script_err_fails(fails)
	var extra := {"tag": tag, "contract": true}
	error = _wall_clock(fails, error, extra)
	for f in fails:
		GateReport.check(false, str(f))
	if fails.is_empty():
		var ok_line := "%s_CONTRACT_OK（契约模式：未截图，截图门禁须另用 DISPLAY 跑）" % tag
		print(ok_line)
		GateReport.finish(GateReport.main_script_name(), 0, ok_line, extra)
		return 0
	for f in fails:
		print("  ✗ ", f)
	var fail_line := "%s_CONTRACT_FAIL %d" % [tag, fails.size()]
	print(fail_line)
	if error != "":
		extra["error"] = error
	GateReport.finish(GateReport.main_script_name(), 1, fail_line, extra)
	return 1
