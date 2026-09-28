extends SceneTree
## 发现录巡检：寺观近侧旧迹（未勘 / 已入册 / 已呈案）与市舶司呈报工席，截到 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/discovery/。
## 断言：呈报签副题「赏钱 N　声名 N」、chip「呈报」挂 tooltip；呈报后挪入 discoveries_reported、日志「入案」。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_discovery_probe.gd   # 截图门禁（须出 5 张）
##       godot --headless --path . -s res://tools/qa_discovery_probe.gd -- --contract   # 只验非渲染断言，不截图
## 空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_discovery_probe.gd

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("discovery")
const TAG := "QA_DISCOVERY"
const EXPECTED_SHOTS := 5
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
	root.size = Vector2i(VIEW)
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_DISCOVERY_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	_gs = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	ShotGate.frame_pressure(self)
	root.add_child(_main)
	await _settle(10)

	_gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	_gs.money = 5000
	_gs.last_port = "quanzhou"

	# 航中与寺观各记一件：废烽堠（福州近侧）、湄洲神女祠（泉州近侧）
	_expect(bool(_gs.record_discovery("beacon_ruin")), "record beacon_ruin")
	_expect(bool(_gs.record_discovery("meizhou_shrine")), "record meizhou_shrine")
	var money0: int = int(_gs.money)
	_expect(money0 == 5000, "record_discovery 不给钱（%d）" % money0)

	_main.load_scene("fuzhou_temple")
	await _settle(10)
	_expect(_has_label("已入册"), "福州寺观 废烽堠 已入册")
	_expect(_has_label("赏格回市舶司。"), "福州寺观 旁注 赏格回市舶司")
	await _shot("01_fuzhou_temple_recorded")

	_main.load_scene("quanzhou_temple")
	await _settle(10)
	_expect(_has_label("未勘"), "泉州寺观 有未勘旧迹")
	_expect(_has_label("已入册"), "泉州寺观 湄洲神女祠 已入册")
	await _shot("02_quanzhou_temple_mixed")

	_main.load_scene("quanzhou_yamen")
	await _settle(10)
	_expect(_has_label("赏钱 70　声名 7"), "市舶司 废烽堠 副题")
	_expect(_has_label("赏钱 110　声名 11"), "市舶司 湄洲神女祠 副题")
	var chips := _report_chips()
	_expect(chips.size() == 2, "市舶司 两枚呈报 chip（得 %d）" % chips.size())
	for c in chips:
		var tip := str((c as Control).tooltip_text)
		_expect(tip.contains("呈报入案"), "呈报 tooltip 含「呈报入案」")
		_expect(not tip.contains("点击"), "呈报 tooltip 无 UI 腔")
	await _shot("03_quanzhou_yamen_pending")

	_main.call("_on_report_discovery", "beacon_ruin")
	await _settle(10)
	_expect("beacon_ruin" in _gs.discoveries_reported, "beacon_ruin 挪入 discoveries_reported")
	_expect(not ("beacon_ruin" in _gs.discoveries_found), "beacon_ruin 出 discoveries_found")
	_expect(int(_gs.money) == money0 + 70, "呈报赏钱 70（得 %d）" % (int(_gs.money) - money0))
	_expect(_report_chips().size() == 1, "呈报后剩一枚 chip")
	_expect(_log_has("「废烽堠」入案。赏钱 70，声名添 7。"), "呈报日志纪实短句")
	await _shot("04_quanzhou_yamen_reported")

	_main.load_scene("fuzhou_temple")
	await _settle(10)
	_expect(_has_label("已呈案"), "福州寺观 废烽堠 已呈案")
	await _shot("05_fuzhou_temple_reported")

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _report_chips() -> Array:
	var out: Array = []
	_collect_buttons(_main, out)
	return out.filter(func(b): return str((b as Button).text).strip_edges() == "呈报" and (b as Control).is_visible_in_tree())


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button and not n.is_queued_for_deletion():
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


func _has_label(text: String) -> bool:
	return _find_label(_main, text)


func _find_label(n: Node, text: String) -> bool:
	if n is Label and not n.is_queued_for_deletion() and (n as Label).text == text and (n as Control).is_visible_in_tree():
		return true
	for c in n.get_children():
		if _find_label(c, text):
			return true
	return false


func _log_has(needle: String) -> bool:
	return _text_has(_main, needle)


func _text_has(n: Node, needle: String) -> bool:
	if n is RichTextLabel and (n as RichTextLabel).get_parsed_text().contains(needle):
		return true
	if n is Label and (n as Label).text.contains(needle):
		return true
	for c in n.get_children():
		if _text_has(c, needle):
			return true
	return false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## 先过 n 帧（排版 / 延迟调用 / 逐帧演出按帧走），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_fails.append("演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)
		print("  ✗ 演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


func _shot(stem: String) -> void:
	await _settle(2)
	if _contract:
		return
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)
