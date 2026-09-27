extends SceneTree
## Lane Z1：海图船况面板 / 顶匾札记旁注纪实短标签巡检。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/voyage/
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_voyage_status_probe.gd   # 截图门禁（须出 6 张）
##       godot --headless --path . -s res://tools/qa_voyage_status_probe.gd -- --contract   # 只验非渲染断言，不截图
## 默认严格须出 6 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_voyage_status_probe.gd
## -s 勿用 autoload 标识符。

const VIEW := Vector2i(1280, 720)
const CHART_SCENE := "res://scenes/SeaChart.tscn"
var OUT_DIR := ShotGate.out_dir("voyage")
const TAG := "QA_VOYAGE"
const EXPECTED_SHOTS := 6
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _chart: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_VOYAGE_BEGIN")
	Clock.frame_pressure(self)
	_check_wiring()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await _frames(6)

	var gs: Node = root.get_node("GameState")
	var fleet: Node = root.get_node("Fleet")
	var voyage: Node = root.get_node("Voyage")
	var cal: Node = root.get_node("Calendar")
	gs.chapter = 4
	gs.last_port = "quanzhou"
	gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou", "hakata"]
	gs.money = maxi(int(gs.money), 800)
	fleet.water = 40
	fleet.food = 40

	_chart = (load(CHART_SCENE) as PackedScene).instantiate()
	root.add_child(_chart)
	await _frames(8)

	# 选一张手牌，开船况（无委办基线）
	var hand: PackedStringArray = _chart.get("_hand")
	var dest := ""
	var far_d := -1.0
	for pid in hand:
		var d: float = voyage.distance_li("quanzhou", str(pid))
		if d > far_d:
			far_d = d
			dest = str(pid)
	_expect(dest != "", "手牌有去处")
	if dest != "":
		_chart.call("_select_heading", dest)
		await _frames(4)
	_chart.call("_refresh_status")
	await _frames(2)
	_chart.call("_toggle_condition")
	await _frames(10)
	_expect(_condition_visible(), "船况层已开")
	var body := _status_bbcode()
	_expect(body.find("船队") >= 0, "船况段头「船队」")
	_expect(body.find("舰队") < 0, "船况无「舰队」段头")
	_expect(body.find("十次") < 0, "船况无「十次」教程括注")
	_expect(body.find("日速") < 0, "船况无「日速」工程口吻")
	_expect(body.find("航段") >= 0 or dest == "", "有航段细节或无去处")
	_expect_condition_full()
	await _shot("01_condition_baseline")
	_chart.call("_close_condition")
	await _frames(4)

	# 在身委办：顶匾短标 + 船况限日词
	gs.contract = {
		"good_id": "silk_fabric", "remaining": 20, "qty": 20,
		"dest": dest if dest != "" else "hakata", "from": "quanzhou",
		"due_day": cal.absolute_day() + 2, "purse": 900, "paid": 0,
	}
	_chart.call("_refresh_status")
	await _frames(3)
	var strip := _strip_bbcode()
	_expect(strip.find("委办") >= 0, "顶匾有委办短标")
	_chart.call("_toggle_condition")
	await _frames(8)
	body = _status_bbcode()
	_expect(body.find("剩") >= 0 or body.find("限今日") >= 0 or body.find("已逾") >= 0, "船况委办短限日")
	_expect(body.find("截止") < 0 and body.find("逾期") < 0, "船况无「截止/逾期」现代词")
	_expect_condition_full()
	await _shot("02_condition_contract")
	_chart.call("_close_condition")
	await _frames(3)
	await _shot("03_strip_contract")

	# 航行中：行成短标（非 /100）
	if dest != "":
		_chart.set("total_li", far_d)
		_chart.set("remaining_li", far_d * 0.42)
		_chart.set("course_bearing", voyage.bearing("quanzhou", dest))
		_chart.set("days_elapsed", 6)
		_chart.set("sailing", true)
		_chart.call("_lock_hand")
		_chart.call("_refresh_status")
		await _frames(4)
		strip = _strip_bbcode()
		_expect(strip.find("行成") >= 0, "顶匾航行「行成」")
		_expect(strip.find("/ 100") < 0, "顶匾无「/ 100」进度腔")
		await _shot("04_strip_sailing")
		_chart.call("_toggle_condition")
		await _frames(8)
		body = _status_bbcode()
		_expect(body.find("行成") >= 0, "船况航行「行成」")
		_expect(body.find("/ 100") < 0, "船况无「/ 100」")
		_expect_condition_full()
		await _shot("05_condition_sailing")
		_chart.call("_close_condition")
		await _frames(2)

	# 告警：水粮紧 + 委办迫近
	_chart.set("sailing", false)
	fleet.water = 5
	fleet.food = 5
	gs.contract = {
		"good_id": "silk_fabric", "remaining": 20, "qty": 20,
		"dest": dest if dest != "" else "hakata", "from": "quanzhou",
		"due_day": cal.absolute_day() + 1, "purse": 900, "paid": 0,
	}
	if dest != "":
		_chart.call("_select_heading", dest)
	_chart.call("_refresh_status")
	await _frames(3)
	_chart.call("_toggle_condition")
	await _frames(8)
	_expect_condition_full()
	await _shot("06_condition_alert")

	_report()


func _check_wiring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/SeaChart.gd")
	var vis := _visible_strings(src)
	_expect("AUTOWRAP_OFF" in src, "顶匾 strip 不折行")
	_expect("行成" in src, "航行短标「行成」")
	_expect("委办已逾" in src or "委办 %d 日" in src, "顶匾委办短标")
	_expect("[b]船队[/b]" in src, "船况段头「船队」")
	for bad in ["十次约有八次", "逃走没被抢走货", "日速 ×", "今日截止", "已逾期", "[b]舰队[/b]"]:
		_expect(bad not in vis, "可见文案无「%s」" % bad)
	var voy := FileAccess.get_file_as_string("res://scripts/core/Voyage.gd")
	_expect("日行较快" in voy or "日行较缓" in voy, "order_blurb 纪实短注")
	_expect("日速 ×" not in _visible_strings(voy), "order_blurb 无日速公式")


func _visible_strings(src: String) -> String:
	var rx := RegEx.new()
	rx.compile("\"([^\"\\\\]|\\\\.)*\"")
	var out := PackedStringArray()
	for line in src.split("\n"):
		var code := line.get_slice("#", 0)
		for m in rx.search_all(code):
			out.append(m.get_string())
	return "\n".join(out)


func _condition_visible() -> bool:
	if _chart == null:
		return false
	var layer: Node = _chart.get("_condition_layer")
	return layer != null and bool(layer.get("visible"))


func _status_bbcode() -> String:
	if _chart == null:
		return ""
	var lab: RichTextLabel = _chart.get("status_label")
	return "" if lab == null else str(lab.text)


func _strip_bbcode() -> String:
	if _chart == null:
		return ""
	var lab: RichTextLabel = _chart.get("_strip_line")
	return "" if lab == null else str(lab.text)


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完（进海图面纱 0.55 s、船况层淡入 0.16 s）；墙钟上界见 probe_clock.gd
func _frames(n: int) -> void:
	if not await Clock.settle(self, n):
		_expect(false, "演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


## 截船况层前：层已淡入满（原先数 8–10 帧，快机上只合 40 ms，截的是半透明层）
func _expect_condition_full() -> void:
	var layer = _chart.get("_condition_layer") if is_instance_valid(_chart) else null
	var a: float = float(layer.modulate.a) if layer != null and bool(layer.visible) else 0.0
	_expect(a >= 1.0, "船况层已淡入满（a=%.2f）" % a)


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _report() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
