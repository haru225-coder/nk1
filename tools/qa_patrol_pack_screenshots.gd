extends SceneTree
## Lane Y：巡检证据包（入行/赴试/名册/海图）→ ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/patrol-pack/
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_patrol_pack_screenshots.gd
## 只截证据，不改玩法。
##       godot --headless --path . -s res://tools/qa_patrol_pack_screenshots.gd -- --contract   # 只验非渲染断言，不截图
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_patrol_pack_screenshots.gd
## 默认严格须出 11 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("patrol-pack")
const CHART_SCENE := "res://scenes/SeaChart.tscn"
const TAG := "QA_PATROL_PACK"
const EXPECTED_SHOTS := 11
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _main: Node
var _gs: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("NK1_CHARS_SYNC", "1")
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_PATROL_PACK_BEGIN")
	ShotGate.frame_pressure(self)

	_gs = root.get_node("GameState")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(8)

	# ── 入行 / 赴试 ──
	_gs.money = maxi(int(_gs.money), 5000)
	_gs.merchant_credit = maxi(int(_gs.merchant_credit), 8)
	_gs.network = maxi(int(_gs.network), 1)
	_gs.last_port = "quanzhou"
	_gs.chapter = 1
	if _gs.has_method("clear_flag"):
		_gs.clear_flag("exam_sat_ch1")
	elif "exam_sat_ch1" in _gs.flags:
		_gs.flags.erase("exam_sat_ch1")
	for port in ["quanzhou", "hakata", "guangzhou"]:
		var fk := "guild_%s" % port
		if fk in _gs.flags:
			_gs.flags.erase(fk)

	await _open_and_shot("quanzhou_guild", "01_quanzhou_guild_join", "交会费入行")
	await _open_and_shot("hakata_guild", "02_hakata_guild_join", "交会费入行")
	await _open_and_shot("quanzhou_exam", "03_quanzhou_exam_sit", "入场赴试")

	await _goto("quanzhou_guild")
	var join_btn := _button_with_text(_main, "交会费入行")
	if join_btn == null:
		_fails.append("泉州入行按钮缺失")
	else:
		join_btn.pressed.emit()
		await _frames(4)
		await _shot("04_quanzhou_guild_joined")

	await _goto("quanzhou_exam")
	var sit_btn := _button_with_text(_main, "入场赴试")
	if sit_btn == null:
		_fails.append("贡院赴试按钮缺失")
	else:
		sit_btn.pressed.emit()
		await _frames(4)
		await _shot("05_quanzhou_exam_sat")

	# ── 名册（岸上浮页）──
	# 藏 Main 可视层，挂 CharsShoreOverlay
	for c in _main.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	_main.visible = false
	await _frames(2)
	var ov: Control = (load("res://scenes/chars/CharsShoreOverlay.tscn") as PackedScene).instantiate()
	root.add_child(ov)
	ov.call("begin", "chen_wenlong")
	await _frames(14)
	# 名册浮页淡入 0.18 s（原先数 14 帧，快机上只合 60 ms）
	_expect(ov.modulate.a >= 1.0, "名册浮页已淡入满（a=%.2f）" % ov.modulate.a)
	await _shot("06_roster_panel")
	var roster = ov.get("_roster")
	if roster != null and roster.has_method("_on_tab"):
		roster.call("_on_tab", "职事")
		await _frames(6)
		await _shot("07_roster_crew")
		roster.call("_on_tab", "史实")
		await _frames(6)
		await _shot("08_roster_historical")
	else:
		_fails.append("名册节点缺 _on_tab")
	if is_instance_valid(ov):
		root.remove_child(ov)
		ov.free()
	await _frames(2)

	# ── 海图 ──
	_main.visible = true
	for c in _main.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = true
	await _frames(2)
	_gs.chapter = 4
	_gs.last_port = "quanzhou"
	_gs.visited_ports = ["quanzhou", "xinghua", "fuzhou", "zhangzhou"]
	var voyage: Node = root.get_node("Voyage")
	var chart: Node = (load(CHART_SCENE) as PackedScene).instantiate()
	root.add_child(chart)
	await _frames(8)
	var map: Node = chart.get("map")
	if map:
		map.call("frame_ports", ["quanzhou", "xinghua", "xinghua_harbor", "fuzhou", "zhangzhou", "penghu"], 0.10, 0.0)
		await _frames(6)
	await _shot("09_chart_port_dense")

	var hand: PackedStringArray = chart.get("_hand")
	var far := ""
	var far_d := -1.0
	for pid in hand:
		var d: float = voyage.distance_li("quanzhou", str(pid))
		if d > far_d:
			far_d = d
			far = str(pid)
	if far != "" and map:
		chart.call("_select_heading", far)
		await _frames(4)
		chart.set("total_li", far_d)
		chart.set("remaining_li", far_d * 0.42)
		chart.set("course_bearing", voyage.bearing("quanzhou", far))
		chart.set("days_elapsed", 6)
		chart.set("sailing", true)
		chart.call("_lock_hand")
		var traveled := far_d * 0.58
		var at: Dictionary = voyage.point_along_track("quanzhou", far, traveled)
		var tw = map.call("move_ship_lonlat", float(at["lon"]), float(at["lat"]), voyage.bearing_at("quanzhou", far, traveled), 0.58, 0.01)
		# 裸 await finished：补间被 kill（再调 move_ship_lonlat）就永不返回；改带墙钟上界
		if tw is Tween and not await Clock.until(self, func() -> bool: return not (tw as Tween).is_running()):
			_expect(false, "船标补间 %d ms 内没走完" % Clock.WAIT_MS)
		# 取景照游戏发舶那一下（SeaChart._on_sail_pressed：起讫两港、pad 0.30，缩放受 MapView.FRAME_ZOOM_MAX 管）。
		# 原先对着船标硬设 zoom 1.4，截到的是远洋一片空海、比例尺二百里、不见岸线，不是玩家看到的航行画面（w19-g13）。
		map.call("frame_ports", ["quanzhou", far], 0.30, 0.0)
		chart.call("_refresh_status")
		await _frames(4)
	await _shot("10_chart_sailing_hud")

	# ── 11 告警朱字（WorldMap 独立挂载在 DISPLAY=:2 上常空镜，改拍海图告警）──
	var fleet: Node = root.get_node("Fleet")
	var cal: Node = root.get_node("Calendar")
	if is_instance_valid(chart):
		chart.set("sailing", false)
		chart.set("days_elapsed", 0)
		fleet.water = 6
		fleet.food = 6
		var dest_id := far if far != "" else "hakata"
		_gs.contract = {
			"good_id": "silk_fabric", "remaining": 30, "qty": 30,
			"dest": dest_id, "from": "quanzhou",
			"due_day": cal.absolute_day() + 2, "purse": 900, "paid": 0,
		}
		chart.call("_log", "[color=#A8322A]第 5 日・水粮已尽　舱中有人病倒[/color]")
		chart.call("_refresh_hand")
		if far != "":
			chart.call("_select_heading", far)
		await _frames(4)
		await _shot("11_chart_alert_strip")
		if is_instance_valid(chart):
			root.remove_child(chart)
			chart.free()

	_report()


func _open_and_shot(scene_id: String, name: String, must_btn: String) -> void:
	await _goto(scene_id)
	var btn := _button_with_text(_main, must_btn)
	if btn == null:
		_fails.append("%s 缺少按钮「%s」" % [scene_id, must_btn])
	else:
		print("OK button 「%s」 on %s" % [must_btn, scene_id])
	await _shot(name)


func _goto(scene_id: String) -> void:
	_main.load_scene(scene_id)
	await _frames(5)
	RenderingServer.force_draw()
	await process_frame


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	var samples: Array = [
		img.get_pixel(w / 2, h / 2),
		img.get_pixel(8, 8),
		img.get_pixel(w - 9, 8),
		img.get_pixel(8, h - 9),
		img.get_pixel(w - 9, h - 9),
		img.get_pixel(w / 4, h / 4),
		img.get_pixel(3 * w / 4, 3 * h / 4),
	]
	var lum_sum := 0.0
	for px in samples:
		lum_sum += (px as Color).get_luminance()
	var avg_lum := lum_sum / float(samples.size())
	if avg_lum < 0.04:
		_fails.append("截屏过暗 %s avg_lum=%.3f" % [name, avg_lum])


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完（名册淡入 0.18 s、立像淡入 0.22 s、进海图面纱 0.55 s）；
## 墙钟上界见 probe_clock.gd
func _frames(n: int) -> void:
	if not await Clock.settle(self, n):
		_expect(false, "演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _button_with_text(root_node: Node, text: String) -> Button:
	var hits: Array = []
	_collect_buttons(root_node, text, hits)
	return hits[0] if not hits.is_empty() else null


func _collect_buttons(n: Node, text: String, hits: Array) -> void:
	if n.is_queued_for_deletion():
		return
	if n is Button and (n as Button).text == text:
		hits.append(n)
	for c in n.get_children():
		_collect_buttons(c, text, hits)


func _report() -> void:
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
