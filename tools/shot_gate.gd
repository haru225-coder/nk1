extends RefCounted
## 截图门禁小工具（Lane m3 / ASTRA_AUDIT M3）：把「截图探针」与「无渲染契约探针」分开。
## 默认严格：headless / 空视口 / 空图 / 实得张数不足声明张数 → 非零退出，并写明是 headless 还是真失败。
## 契约模式须显式开：命令行 `-- --contract`（或环境变量 NK1_SHOT_CONTRACT=1）；此时不截图，只验非渲染断言，
## 收尾打 `<TAG>_CONTRACT_OK`，绝不打 `OK shots=0`。
## 用法：const ShotGate := preload("res://tools/shot_gate.gd")
## 输出目录：`var OUT_DIR := ShotGate.out_dir("vision")`。默认落 /workspace/nk1-qa-shots/<子目录>；
## 设环境变量 NK1_SHOT_DIR=<目录> 则整体改落 <目录>/<子目录>（worktree / 自测别覆盖证据图，lane gd2）。
## `-- --json`：三个收尾函数改打一行 JSON（gate_report.gd，lane g2），门禁名取入口脚本文件名；调用方不用改。

const DEFAULT_SHOT_ROOT := "/workspace/nk1-qa-shots"
const GateReport := preload("res://tools/gate_report.gd")


## 截图输出目录：NK1_SHOT_DIR 为空取默认根；相对路径按启动时的 $PWD 展开。
static func out_dir(sub: String) -> String:
	var root := OS.get_environment("NK1_SHOT_DIR").strip_edges()
	if root == "":
		root = DEFAULT_SHOT_ROOT
	elif not root.is_absolute_path():
		root = OS.get_environment("PWD").path_join(root)
	return root.path_join(sub)


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


## 截图模式收尾：实得张数 < 声明张数也判失败。返回退出码。
static func finish_shots(tag: String, saved: Array, expected: int, out_dir: String, fails: Array) -> int:
	if saved.size() < expected:
		fails.append("真失败：声明 %d 张截图，实得 %d 张" % [expected, saved.size()])
	for p in saved:
		GateReport.check(true, str(p).get_file(), "shot")
	for f in fails:
		GateReport.check(false, str(f))
	var extra := {"tag": tag, "shots": saved.size(), "expected_shots": expected, "out_dir": out_dir}
	if fails.is_empty():
		var ok_line := "%s_OK shots=%d/%d -> %s" % [tag, saved.size(), expected, out_dir]
		print(ok_line)
		GateReport.finish(GateReport.main_script_name(), 0, ok_line, extra)
		return 0
	for f in fails:
		print("  ✗ ", f)
	var fail_line := "%s_FAIL %d（shots=%d/%d -> %s）" % [tag, fails.size(), saved.size(), expected, out_dir]
	print(fail_line)
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
static func finish_contract(tag: String, fails: Array) -> int:
	for f in fails:
		GateReport.check(false, str(f))
	if fails.is_empty():
		var ok_line := "%s_CONTRACT_OK（契约模式：未截图，截图门禁须另用 DISPLAY 跑）" % tag
		print(ok_line)
		GateReport.finish(GateReport.main_script_name(), 0, ok_line, {"tag": tag, "contract": true})
		return 0
	for f in fails:
		print("  ✗ ", f)
	var fail_line := "%s_CONTRACT_FAIL %d" % [tag, fails.size()]
	print(fail_line)
	GateReport.finish(GateReport.main_script_name(), 1, fail_line, {"tag": tag, "contract": true})
	return 1
