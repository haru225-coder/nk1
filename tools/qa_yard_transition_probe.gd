extends Node
## lane fo：船屋过场（UiTransition）期间旧页按钮还吃不吃输入 → 修船 / 购船会不会二次扣费。
## 必须带窗口、且不能用 -s 跑（-s 下 Cinematics.live() 恒假，根本不放过场）：
##   DISPLAY=:2 godot --path . res://tools/qa_yard_transition_probe.tscn
## 每一路：满钱、船体打残 → 真鼠标点「修船」→ 趁墨幕未全黑（旧页还在树上）再补一次输入 → 等过场落定，数扣了几次。
## 末了再验闸会放开：过场落定后船再打残，照常能修、照扣一次。
## 输出 YARD_TRANSITION_PROBE OK / FAIL k；逐路一行 FO_CASE。

const START_MONEY := 50000
var _main: Node
var _fails := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1280, 720)
	var _cine: GDScript = load("res://scripts/cutscene/Cinematics.gd")
	_cine.set("auto_opening", false)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	for _i in 8:
		await get_tree().process_frame
	print("FO live=%s ui_accept=%s" % [_cine.call("live"), InputMap.action_get_events("ui_accept")])
	for how in ["mouse", "key_enter", "key_space", "joy_a", "action_ui_accept", "emit"]:
		await _case_repair(how)
	for how in ["mouse", "joy_a", "action_ui_accept", "emit"]:
		await _case_buy_ship(how)
	await _case_release()
	print("YARD_TRANSITION_PROBE %s" % ("OK" if _fails == 0 else "FAIL %d" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _gs() -> Node:
	return get_tree().root.get_node("GameState")


func _fleet() -> Node:
	return get_tree().root.get_node("Fleet")


func _open_yard() -> void:
	_gs().set("money", START_MONEY)
	_gs().set("last_port", "quanzhou")
	_main.call("load_scene", "quanzhou_shipyard")
	for _i in 4:
		await get_tree().process_frame


func _find_btn(prefix: String, contains := "") -> Button:
	for b in _main.find_children("*", "Button", true, false):
		var t := str((b as Button).text)
		if t.begins_with(prefix) and (contains == "" or t.contains(contains)) and (b as Button).is_visible_in_tree():
			return b
	return null


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await get_tree().process_frame


func _poke(how: String, btn: Variant, pos: Vector2) -> void:
	match how:
		"mouse":
			await _click(pos)
		"key_enter", "key_space":
			for pressed in [true, false]:
				var k := InputEventKey.new()
				k.keycode = KEY_ENTER if how == "key_enter" else KEY_SPACE
				k.physical_keycode = k.keycode
				k.pressed = pressed
				Input.parse_input_event(k)
				await get_tree().process_frame
		"joy_a":
			for pressed in [true, false]:
				var j := InputEventJoypadButton.new()
				j.button_index = JOY_BUTTON_A
				j.pressed = pressed
				Input.parse_input_event(j)
				await get_tree().process_frame
		"action_ui_accept":
			for pressed in [true, false]:
				var a := InputEventAction.new()
				a.action = "ui_accept"
				a.pressed = pressed
				Input.parse_input_event(a)
				await get_tree().process_frame
		"emit":
			if is_instance_valid(btn):
				btn.pressed.emit()
			await get_tree().process_frame


func _transition() -> Node:
	var ns := get_tree().get_nodes_in_group("nk1_ui_transition")
	return ns[0] if not ns.is_empty() else null


func _dump(tag: String, btn: Variant) -> String:
	var t := _transition()
	var root_mf := -1
	var black := false
	if t != null:
		root_mf = int((t.get("_root") as Control).mouse_filter)
		black = bool(t.get("_black_done"))
	var fo := get_window().gui_get_focus_owner()
	return "%s transition=%s layer=%s root.mouse_filter=%d(STOP=0) at_black=%s old_btn_in_tree=%s disabled=%s focus=%s" % [
		tag, t != null, (t.get("layer") if t != null else "-"), root_mf, black,
		is_instance_valid(btn) and btn.is_inside_tree(),
		(btn.disabled if is_instance_valid(btn) else "-"),
		(str(fo.get("text")) if fo != null else "null"),
	]


## 过场约 2.4 s（UiTransition 0.32 + 0.42 + 0.28 + 1.0 + 0.42）。上界按墙钟（lane gd11）：原 600 帧在 vsync 关
## 约 235 fps 下只合 2.55 s，比过场长不到一成，帧率再高就没等完便数钱；墙钟上界与帧率无关，留约 6 倍余量。
const SETTLE_MS := 15000


func _settle() -> void:
	var deadline := Time.get_ticks_msec() + SETTLE_MS
	while _transition() != null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for _i in 4:
		await get_tree().process_frame


func _case_repair(how: String) -> void:
	await _open_yard()
	var s: Dictionary = _fleet().get("ships")[0]
	s["durability"] = int(s["max_durability"]) - 40
	_main.call("load_scene", "quanzhou_shipyard")
	for _i in 4:
		await get_tree().process_frame
	var rc: int = _fleet().call("repair_cost")
	var btn := _find_btn("修船")
	if btn == null or rc <= 0:
		_fails += 1
		print("FO_CASE repair/%s FAIL 找不到修船钮 rc=%d" % [how, rc])
		return
	var pos := btn.get_global_rect().get_center()
	await _click(pos)
	var after_first: int = _gs().get("money")
	var d1 := _dump("after_click1", btn)
	await _poke(how, btn, pos)
	var d2 := _dump("after_poke", btn)
	await _settle()
	var final: int = _gs().get("money")
	var charges := float(START_MONEY - final) / float(rc)
	var ok := after_first == START_MONEY - rc and final == START_MONEY - rc
	if not ok:
		_fails += 1
	print("FO_CASE repair/%s %s rc=%d first=%d final=%d charges=%.1f | %s | %s" % [
		how, "OK" if ok else "DOUBLE_CHARGE", rc, START_MONEY - after_first, START_MONEY - final, charges, d1, d2])


func _case_buy_ship(how: String) -> void:
	await _open_yard()
	var btn := _find_btn("", "购入")
	if btn == null:
		_fails += 1
		print("FO_CASE buy_ship/%s FAIL 找不到购入钮" % how)
		return
	var n0: int = (_fleet().get("ships") as Array).size()
	var pos := btn.get_global_rect().get_center()
	var label := btn.text
	await _click(pos)
	var after_first: int = _gs().get("money")
	var price := START_MONEY - after_first
	var d1 := _dump("after_click1", btn)
	await _poke(how, btn, pos)
	var d2 := _dump("after_poke", btn)
	await _settle()
	var final: int = _gs().get("money")
	var n1: int = (_fleet().get("ships") as Array).size()
	var ok := price > 0 and final == after_first and n1 == n0 + 1
	if not ok:
		_fails += 1
	print("FO_CASE buy_ship/%s %s [%s] price=%d spent=%d ships %d→%d | %s | %s" % [
		how, "OK" if ok else "DOUBLE_CHARGE", label, price, START_MONEY - final, n0, n1, d1, d2])
	# 还原舰队规模，免得下一路船多
	while (_fleet().get("ships") as Array).size() > n0:
		(_fleet().get("ships") as Array).pop_back()


## 闸只挡过场期间：落定后再修一次照常扣一次
func _case_release() -> void:
	await _case_repair("mouse")
	var s: Dictionary = _fleet().get("ships")[0]
	s["durability"] = int(s["max_durability"]) - 20
	_main.call("load_scene", "quanzhou_shipyard")
	for _i in 4:
		await get_tree().process_frame
	var m0: int = _gs().get("money")
	var rc: int = _fleet().call("repair_cost")
	var btn := _find_btn("修船")
	var ok := btn != null and rc > 0 and not bool(_main.get("_upgrade_busy"))
	if ok:
		await _click(btn.get_global_rect().get_center())
		await _settle()
		ok = int(_gs().get("money")) == m0 - rc and int(s["durability"]) == int(s["max_durability"])
	if not ok:
		_fails += 1
	print("FO_CASE release %s rc=%d spent=%d busy_after=%s" % [
		"OK" if ok else "STUCK", rc, m0 - int(_gs().get("money")), _main.get("_upgrade_busy")])
