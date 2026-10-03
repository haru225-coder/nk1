extends Node
## lane w53-9：海图回港的抵港横幅（挂签式：只写副题 +「泊」印）在各种窗口比例下都挂在港名匾下。
## 港名匾在港页顶上按像素定位，画布变高（16:10、4:3、竖屏）它不动；挂签原先按画布高的比例摆，
## 1280×800 离匾 23px 远于 16:9、1024×768（画布 1280×960）远 69px、720×1280（画布 1280×2275）远 443px，浮在画面中腰。
## 走 Main 的真实接线（_arrival_banner + load_scene 进港 → Main 起横幅），量匾与绢带的实际位置：
##   一、16:9 基准：绢带上缘落在匾的下半截到匾下 8px 之间（挂在匾下，不压港名、不脱开），左右居中对齐匾（差 ≤ 2px）。
##   二、其余各比例：绢带上缘离匾底的距离与 16:9 相同（差 ≤ 2px），左右居中对齐匾（差 ≤ 2px）。
## 必须带窗口、且不能用 -s 跑（-s 下 Cinematics.live() 恒假，Main 不起横幅）：
##   DISPLAY=:2 godot --path . res://tools/qa_w53_9_port_banner_probe.tscn
## 逐比例一行 W53_9_BANNER <窗口> OK|FAIL <细节>；末行 QA_W53_9_PORT_BANNER OK | FAIL <n>，rc 0 / 1。
## 等待按横幅自己的时钟推进、上界按墙钟（WAIT_MS），撞上界判红并写明。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）；
## 每种窗口都得出判词，缺哪种即点名判红；_run 半路出错由 _run_guarded 就地判红收尾。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const TAG := "QA_W53_9_PORT_BANNER"
const PORT := "fuzhou"
const GROUP := "nk1_port_banner"
## 第一项是基准（16:9）；其余：16:10、4:3、竖屏、超宽
const SIZES := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1024, 768), Vector2i(720, 1280), Vector2i(1280, 540)]
## 绢带滑入用 0.6 秒（PortBanner.SLIDE），过了再量
const SETTLED_T := 0.8
const WAIT_MS := 20000

var _fails := 0
var _main: Node
var _tally: ScriptErrTally
var _reported := false
var _seen := {}
var _base_gap := INF


func _ready() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_verdict("run", false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _verdict(what: String, ok: bool, detail: String) -> void:
	_seen[what] = true
	print("W53_9_BANNER %s %s %s" % [what, "OK" if ok else "FAIL", detail])
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	get_window().size = SIZES[0]
	if Kit.is_headless():
		_verdict("all", false, "headless 下横幅不建节点：须 DISPLAY=:2 带窗口、以场景启动")
		_report()
		return
	var cine: GDScript = load("res://scripts/cutscene/Cinematics.gd")
	cine.set("enabled", true)
	cine.set("auto_opening", false)
	cine.set("opening_seen", true)
	var gs: Node = get_tree().root.get_node("GameState")
	var cal: Node = get_tree().root.get_node("Calendar")
	gs.call("from_dict", {})
	cal.call("from_dict", {"year": 1256, "month": 4, "day": 1})
	# 走过一港：不是序章后第一次进港（那一回演第一章章节卡、不出横幅）
	gs.set("visited_ports", ["quanzhou"])
	gs.set("last_port", "quanzhou")
	print("%s_BEGIN live=%s" % [TAG, cine.call("live")])
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _frames(8)
	for wh in SIZES:
		await _case(wh)
	_report()


func _banner() -> Node:
	for n in get_tree().get_nodes_in_group(GROUP):
		if not (n as Node).is_queued_for_deletion():
			return n
	return null


func _case(wh: Vector2i) -> void:
	var label := "%dx%d" % [wh.x, wh.y]
	get_window().size = wh
	await _frames(10)
	_main.set("_arrival_banner", true)
	_main.call("load_scene", PORT)
	_main.set("_arrival_banner", false)
	var b: Node = _banner()
	if b == null:
		_verdict(label, false, "海图回港进%s没起抵港横幅（页型 %s）" % [PORT, _main.get("_shore_kind_now")])
		return
	if not bool(b.get("_hang")):
		_verdict(label, false, "横幅不是挂签式（with_name=false 只写副题）——Main 的接线变了，本探针量的对象不对")
		return
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(b) and float(b.get("_t")) < SETTLED_T and Time.get_ticks_msec() - t0 < WAIT_MS:
		await get_tree().process_frame
	if not is_instance_valid(b) or float(b.get("_t")) < SETTLED_T:
		_verdict(label, false, "横幅没走到 %.1f 秒（墙钟上界 %d ms 先到 / 半路被释放）" % [SETTLED_T, WAIT_MS])
		return
	var holder: Node = (_main.get("port_mode") as Node).get_node_or_null("PortPlaqueHolder")
	var plaque: Control = holder.get_child(0) if holder != null and holder.get_child_count() > 0 else null
	if plaque == null:
		_verdict(label, false, "港页上找不到港名匾（PortPlaqueHolder）")
		return
	var band: Control = b.get("_band")
	var pr := plaque.get_global_rect()
	var br := Rect2(band.position, band.size)
	var gap := br.position.y - pr.end.y
	var dx := br.get_center().x - pr.get_center().x
	var cv := get_viewport().get_visible_rect().size
	var where := "画布 %dx%d：匾 y %.0f–%.0f，绢带 y %.0f–%.0f，离匾底 %.0fpx，中线差 %.0fpx" % [cv.x, cv.y, pr.position.y, pr.end.y, br.position.y, br.end.y, gap, dx]
	if _base_gap == INF:
		_base_gap = gap
		_verdict(label, gap >= -pr.size.y * 0.4 and gap <= 8.0 and absf(dx) <= 2.0,
			"16:9 基准挂在匾下（上缘落在匾下半截到匾下 8px、左右居中）——%s" % where)
	else:
		_verdict(label, absf(gap - _base_gap) <= 2.0 and absf(dx) <= 2.0,
			"与 16:9 同样挂在匾下（离匾底差 %.0fpx ≤ 2、左右居中）——%s" % [gap - _base_gap, where])
	while is_instance_valid(b) and Time.get_ticks_msec() - t0 < WAIT_MS:
		await get_tree().process_frame


func _report() -> void:
	_reported = true
	var missing := PackedStringArray()
	for wh in SIZES:
		var label := "%dx%d" % [wh.x, wh.y]
		if not _seen.has(label):
			missing.append(label)
	if not missing.is_empty() and not _seen.has("all"):
		_verdict("sizes", false, "这几种窗口没出判词（半路被脚本错掐断、或提前 return，等于没测）：" + "、".join(missing))
	for v in _tally.verdicts():
		_verdict("script_errors", v[0], v[1])
	print("%s %s" % [TAG, "OK" if _fails == 0 else "FAIL %d" % _fails])
	get_tree().quit(1 if _fails > 0 else 0)
