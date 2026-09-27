extends SceneTree
## 牙行/市舶过秤面板巡检：截图到 /workspace/nk1-qa-shots/market/。
## 断言：价格行「买/卖」下有手续脚注「含抽解・扣佣」；正文含过秤短注；市舶修埠短句纪实。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_market_panel_probe.gd   # 截图门禁（须出 5 张）
##       godot --headless --path /workspace/nk1 -s res://tools/qa_market_panel_probe.gd -- --contract   # 只验非渲染断言，不截图
## 默认严格须出 5 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。

const VIEW := Vector2(1280, 720)
var OUT_DIR := ShotGate.out_dir("market")
const TAG := "QA_MARKET"
const EXPECTED_SHOTS := 5
const ShotGate := preload("res://tools/shot_gate.gd")

var _main: Node
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
	print("QA_MARKET_BEGIN")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	gs.money = 5000
	# 展开委办细则
	if "_contract_detail_open" in _main:
		_main.set("_contract_detail_open", true)

	_main.load_scene("quanzhou_market")
	await _settle(12)
	_expect(str(_main.scene_title.text).contains("牙行"), "牙行匾「%s」" % _main.scene_title.text)
	_expect(str(_main.body_text.text).contains("牙人过秤开票"), "过秤短注")
	_expect(str(_main.body_text.text).contains("柜上只摆三样"), "柜上三样")
	var fee_n := _count_fee_labels(_main)
	_expect(fee_n >= 1, "价格行手续脚注×%d" % fee_n)
	_expect(_find_label_text(_main, "含抽解・扣佣"), "见「含抽解・扣佣」")
	_expect(_find_label_text(_main, "买 ") and _find_label_text(_main, "卖 "), "见买/卖价行")
	await _shot("01_quanzhou_market")

	# 细则展开态（若有委办）
	await _shot("02_quanzhou_market_contract")

	# 点买 1（有钱）——日志含过秤
	var bought := _press_buy_one(_main)
	await _settle(8)
	if bought:
		_expect(_log_has("过秤买入") or _log_has("抽解在内"), "买入日志过秤/抽解")
	await _shot("03_quanzhou_market_after_buy")

	_main.load_scene("quanzhou_yamen")
	await _settle(10)
	_expect(str(_main.scene_title.text).contains("市舶司"), "市舶匾")
	var body := str(_main.body_text.text)
	_expect(body.contains("验引") or body.contains("货单"), "市舶正文")
	# 修埠短句：未修或已修都不应再写「加深市场」
	_expect(not _find_label_text(_main, "加深市场"), "无「加深市场」")
	_expect(not _find_label_text(_main, "市场更深"), "无「市场更深」")
	await _shot("04_quanzhou_yamen")

	# 福州牙行对照（价格行脚注仍在）
	gs.last_port = "fuzhou"
	_main.load_scene("fuzhou_market")
	await _settle(10)
	_expect(_count_fee_labels(_main) >= 1 or str(_main.body_text.text).contains("渔妇") or str(_main.body_text.text).contains("门闸"), "福州牙行或闭门")
	await _shot("05_fuzhou_market")

	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("QA_MARKET_CHECK ok ", what)
	else:
		_fails.append(what)
		print("QA_MARKET_CHECK fail ", what)


func _count_fee_labels(n: Node) -> int:
	var c := 0
	if n is Label and str((n as Label).text) == "含抽解・扣佣":
		c = 1
	for ch in n.get_children():
		c += _count_fee_labels(ch)
	return c


func _find_label_text(n: Node, needle: String) -> bool:
	if n is Label and str((n as Label).text).contains(needle):
		return true
	if n is RichTextLabel and str((n as RichTextLabel).text).contains(needle):
		return true
	for ch in n.get_children():
		if _find_label_text(ch, needle):
			return true
	return false


func _press_buy_one(n: Node) -> bool:
	# 找文案为「买 1」的按钮
	var b := _find_button(n, "买 1")
	if b == null:
		return false
	(b as BaseButton).pressed.emit()
	return true


func _find_button(n: Node, text: String) -> BaseButton:
	if n is BaseButton and str((n as BaseButton).text) == text:
		return n as BaseButton
	for ch in n.get_children():
		var f := _find_button(ch, text)
		if f != null:
			return f
	return null


func _log_has(needle: String) -> bool:
	# Main 日志区：尽量从常见节点名取
	var logn := _find_named(_main, "LogLabel")
	if logn == null:
		logn = _find_named(_main, "LogText")
	if logn is Label:
		return str((logn as Label).text).contains(needle)
	if logn is RichTextLabel:
		return str((logn as RichTextLabel).text).contains(needle)
	# 退化：全树搜
	return _find_label_text(_main, needle)


func _find_named(n: Node, node_name: String) -> Node:
	if n.name == node_name:
		return n
	for ch in n.get_children():
		var f := _find_named(ch, node_name)
		if f != null:
			return f
	return null


func _shot(stem: String) -> void:
	if _contract:
		return
	await _settle(2)
	RenderingServer.force_draw()
	await process_frame
	await RenderingServer.frame_post_draw
	ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, stem], _saved, _fails)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
