extends Node
## lane fo：船屋过场（UiTransition）期间旧页按钮还吃不吃输入 → 修船 / 购船会不会二次扣费。
## 必须带窗口、且不能用 -s 跑（-s 下 Cinematics.live() 恒假，根本不放过场）：
##   DISPLAY=:2 godot --path . res://tools/qa_yard_transition_probe.tscn
## 每一路：满钱、船体打残 → 真鼠标点「修船」→ 趁墨幕未全黑（旧页还在树上）再补一次输入 → 等过场落定，数扣了几次。
## 末了再验闸会放开：过场落定后船再打残，照常能修、照扣一次。
## 输出 YARD_TRANSITION_PROBE OK / FAIL k（各判词计数）；逐路一行 FO_CASE <路> <判词>。
## 判词分开报（lane gd18；原先一律 DOUBLE_CHARGE）：
##   NOT_READY        点前就绪不成立（钮没排稳 / 被盖住 / 过场闸没放开），不点——探针自己的前提，不是被测件回归
##   FIRST_CLICK_MISS 首点没扣钱：got_press 说明钮收没收到按下（false = 点没落到钮上，true = 钮收到了却没扣）
##   DOUBLE_CHARGE    首点扣对了，补的那次输入又扣了一次——本探针真正要抓的回归
##   WRONG_CHARGE     扣的数目不对（首点不等于价、或总扣不等于一次），SHIP_COUNT 购船后船数不对
##   WALL_CLOCK       等过场落定 / 点前就绪撞了墙钟上界、本段游戏时间还不够（压帧过重，不是挂死、不是被测件的错），
##                    本路判不了、不数钱（lane gd24；原先上界到了照样往下数，碰运气；就绪超时一律报 NOT_READY）
##   STUCK            过场游戏时间走够了仍没落定（真卡住），或落定后闸没放开
## 压帧自检：NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path . res://tools/qa_yard_transition_probe.tscn（见 shot_gate.gd）

const ShotGate := preload("res://tools/shot_gate.gd")
## 等待记账与「压帧过重 / 卡住」的分法（lane gd24，见 probe_clock 头注释「三」）
const Clock := preload("res://tools/probe_clock.gd")
const START_MONEY := 50000
## 点前就绪上界（墙钟）：页是同步重建的，排版几帧就稳；留足压帧 / 满载余量
const READY_MS := 5000
## rect 连着这么多帧不变才算排稳
const STABLE_FRAMES := 3
## 探针自己发的鼠标事件打这个 device 号，好与真指针（共用 X 显示上别的窗口开关、有人动鼠标）分开
const PROBE_DEVICE := 1878
var _main: Node
var _fails := 0
var _verdicts := {}
## 上一次点前就绪的记账（进 FO_CASE 行）：等了几帧 / 多少 ms、第一次不成立的原因
var _ready_note := ""
## 不是探针发的鼠标事件 / 窗口鼠标进出（真指针）计数；首点前后取差记进 _click_note，进 FO_CASE 行
var _foreign := 0
var _crossing := 0
var _click_note := ""


## 真指针挡在 GUI 之前（_input 先于 GUI 分发）：DISPLAY=:2 是多 lane 共用的 X，别的窗口开关 / 有人动鼠标时，
## 真指针的移动会落进本窗口；夹在首点按下与松开之间，BaseButton 判「移出了钮」、松开不发 pressed——
## gd11 记的「40 次 1 次首点未中」即此（lane gd18：只加点前就绪闸的版本 40 连跑仍 1 次，got_press=true、first=0；
## 私有 Xvfb 上晃指针 12/12 复现，吞掉后 12/12 绿；指针进出窗口不打断按下态，只计数）。
## 本探针的输入全是自己合成的（都打 PROBE_DEVICE），真指针对它只是环境噪声，一律吞掉；计数进 FO_CASE 行的 foreign=。
func _input(e: InputEvent) -> void:
	if e is InputEventMouse and e.device != PROBE_DEVICE:
		_foreign += 1
		get_viewport().set_input_as_handled()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1280, 720)
	get_window().mouse_entered.connect(func() -> void: _crossing += 1)
	get_window().mouse_exited.connect(func() -> void: _crossing += 1)
	ShotGate.frame_pressure(get_tree())
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
	var tally := PackedStringArray()
	for k in _verdicts:
		tally.append("%s=%d" % [k, _verdicts[k]])
	print("YARD_TRANSITION_PROBE %s（%s）" % ["OK" if _fails == 0 else "FAIL %d" % _fails, " ".join(tally)])
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
		e.device = PROBE_DEVICE
		Input.parse_input_event(e)
		await get_tree().process_frame


## 点前就绪（lane gd18）：首点原先只在换页后等 4 帧就点。现在点前逐帧查，全部成立才点，满 READY_MS（墙钟）
## 不成立返回红因、不点（NOT_READY，与首点未中 / 重复扣费分开报）：
##   钮在树上、可见、未禁用、未待释放；Main._upgrade_busy 已放开（上一路的过场闸）、场上没有墨幕；
##   global rect 连着 STABLE_FRAMES 帧不变（排版已稳，按下与松开落在同一处）；中心点在视口内；
##   命中：向中心点送一次鼠标移动，收下它的（gui_input）正是这枚钮——没被浮层 / 别的控件盖住。
## 本机实测换页后第一帧就排稳（40 次 × 12 路都是最短的 2 帧成立），原先那次点空不是排版没稳，真因见 _input。
func _ready_to_click(btn: Button) -> String:
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	var game_s := 0.0
	var deadline := t0 + READY_MS
	var last := Rect2()
	var still := 0
	var why := ""
	var frames := 0
	var first_why := ""
	while true:
		why = _not_ready(btn)
		if why == "":
			var r := btn.get_global_rect()
			still = still + 1 if r == last else 0
			last = r
			if still + 1 < STABLE_FRAMES:
				why = "rect 未稳（%s）" % r
			elif not await _hits(btn, r.get_center()):
				still = 0
				why = "命中不是这枚钮（%s 处被盖住）" % r.get_center()
			else:
				_ready_note = "ready=%df/%dms%s" % [frames, Time.get_ticks_msec() - t0,
					"" if first_why == "" else "（先见：%s）" % first_why]
				return ""
		if first_why == "" and not why.begins_with("rect 未稳"):
			first_why = why
		if Time.get_ticks_msec() >= deadline:
			Clock.mark(true, t0, f0, game_s, READY_MS)
			return "%d ms 未就绪：%s（%s）" % [READY_MS, why, Clock.overrun()]
		frames += 1
		await get_tree().process_frame
		game_s += get_process_delta_time()
	return why


func _not_ready(btn: Button) -> String:
	if not is_instance_valid(btn) or not btn.is_inside_tree() or btn.is_queued_for_deletion():
		return "钮不在树上"
	if not btn.is_visible_in_tree() or btn.disabled:
		return "钮不可见或已禁用"
	if bool(_main.get("_upgrade_busy")) or _transition() != null:
		return "上一路过场未落定（_upgrade_busy=%s）" % _main.get("_upgrade_busy")
	if not get_window().get_visible_rect().has_point(btn.get_global_rect().get_center()):
		return "钮中心 %s 在视口外" % btn.get_global_rect().get_center()
	return ""


## 送一次鼠标移动到 pos，看收下它的是不是 btn（Viewport 把移动事件交给该点最上层、肯收鼠标的控件）。
func _hits(btn: Button, pos: Vector2) -> bool:
	var got := [false]
	var seen := func(e: InputEvent) -> void:
		if e is InputEventMouseMotion and e.device == PROBE_DEVICE:
			got[0] = true
	btn.gui_input.connect(seen)
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.device = PROBE_DEVICE
	Input.parse_input_event(m)
	await get_tree().process_frame
	if is_instance_valid(btn) and btn.gui_input.is_connected(seen):
		btn.gui_input.disconnect(seen)
	return got[0]


## 首点：记下钮收没收到按下（got_press），供 FIRST_CLICK_MISS 分辨「点没落到钮上」与「钮收到了却没扣」。
func _first_click(btn: Button, pos: Vector2) -> bool:
	var got := [false]
	var seen := func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			got[0] = true
	btn.gui_input.connect(seen)
	var f0 := _foreign
	var c0 := _crossing
	await _click(pos)
	_click_note = "foreign=%d crossing=%d" % [_foreign - f0, _crossing - c0]
	if is_instance_valid(btn) and btn.gui_input.is_connected(seen):
		btn.gui_input.disconnect(seen)
	return got[0]


## 判词：first = 首点扣的钱，total = 一路下来总扣，unit = 一次该扣的数。见头注释。
func _verdict(first: int, total: int, unit: int) -> String:
	if first == 0:
		return "FIRST_CLICK_MISS"
	if first != unit:
		return "WRONG_CHARGE"
	if total > unit:
		return "DOUBLE_CHARGE"
	if total != unit:
		return "WRONG_CHARGE"
	return "OK"


func _tally(v: String) -> void:
	_verdicts[v] = int(_verdicts.get(v, 0)) + 1
	if v != "OK":
		_fails += 1


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


## 等到了返回 ""；撞上界返回红话（probe_clock.overrun：压帧过重 / 卡住），调用方记 _limit_verdict、不再数钱
## ——原先上界到了照样往下数（lane gd24 普查：过场还在演就数，重复扣费的那次可能还没发生，碰运气绿）。
func _settle() -> String:
	var ok: bool = await Clock.until(get_tree(), func() -> bool: return _transition() == null, SETTLE_MS)
	var why := "" if ok else "过场 %d ms 内没落定：%s" % [SETTLE_MS, Clock.overrun()]
	for _i in 4:
		await get_tree().process_frame
	return why


## 撞了墙钟上界的那一路记哪个判词：压帧过重 WALL_CLOCK，游戏时间够了还没落定 STUCK
func _limit_verdict() -> String:
	return "WALL_CLOCK" if Clock.pressured() else "STUCK"


## 点前就绪等满上界：本段游戏时间不够（压帧过重）记 WALL_CLOCK，够了仍不成立才是 NOT_READY（探针前提真不成立）
func _not_ready_verdict() -> String:
	return "WALL_CLOCK" if Clock.pressured() else "NOT_READY"


## 返回本路等过场落定撞上界的红话（没撞 / 早退为 ""）：_case_release 借这一路铺垫，撞了就不往下判
func _case_repair(how: String) -> String:
	await _open_yard()
	var s: Dictionary = _fleet().get("ships")[0]
	s["durability"] = int(s["max_durability"]) - 40
	_main.call("load_scene", "quanzhou_shipyard")
	for _i in 4:
		await get_tree().process_frame
	var rc: int = _fleet().call("repair_cost")
	var btn := _find_btn("修船")
	if btn == null or rc <= 0:
		_tally("NO_BUTTON")
		print("FO_CASE repair/%s NO_BUTTON 找不到修船钮 rc=%d" % [how, rc])
		return ""
	var not_ready := await _ready_to_click(btn)
	if not_ready != "":
		var nv := _not_ready_verdict()
		_tally(nv)
		print("FO_CASE repair/%s %s %s" % [how, nv, not_ready])
		return ""
	var pos := btn.get_global_rect().get_center()
	var got_press := await _first_click(btn, pos)
	var after_first: int = _gs().get("money")
	var d1 := _dump("after_click1", btn)
	await _poke(how, btn, pos)
	var d2 := _dump("after_poke", btn)
	var unsettled := await _settle()
	if unsettled != "":
		_tally(_limit_verdict())
		print("FO_CASE repair/%s %s %s（本路不数钱）| %s | %s" % [how, _limit_verdict(), unsettled, d1, d2])
		return unsettled
	var final: int = _gs().get("money")
	var charges := float(START_MONEY - final) / float(rc)
	var v := _verdict(START_MONEY - after_first, START_MONEY - final, rc)
	_tally(v)
	print("FO_CASE repair/%s %s rc=%d first=%d final=%d charges=%.1f got_press=%s %s %s | %s | %s" % [
		how, v, rc, START_MONEY - after_first, START_MONEY - final, charges, got_press, _click_note, _ready_note, d1, d2])
	return ""


func _case_buy_ship(how: String) -> void:
	await _open_yard()
	var btn := _find_btn("", "购入")
	if btn == null:
		_tally("NO_BUTTON")
		print("FO_CASE buy_ship/%s NO_BUTTON 找不到购入钮" % how)
		return
	var n0: int = (_fleet().get("ships") as Array).size()
	var not_ready := await _ready_to_click(btn)
	if not_ready != "":
		var nv := _not_ready_verdict()
		_tally(nv)
		print("FO_CASE buy_ship/%s %s %s" % [how, nv, not_ready])
		return
	var pos := btn.get_global_rect().get_center()
	var label := btn.text
	var list_price := int(label.get_slice("　", label.get_slice_count("　") - 1))
	var got_press := await _first_click(btn, pos)
	var after_first: int = _gs().get("money")
	var price := START_MONEY - after_first
	var d1 := _dump("after_click1", btn)
	await _poke(how, btn, pos)
	var d2 := _dump("after_poke", btn)
	var unsettled := await _settle()
	if unsettled != "":
		_tally(_limit_verdict())
		print("FO_CASE buy_ship/%s %s [%s] %s（本路不数钱）| %s | %s" % [how, _limit_verdict(), label, unsettled, d1, d2])
		while (_fleet().get("ships") as Array).size() > n0:
			(_fleet().get("ships") as Array).pop_back()
		return
	var final: int = _gs().get("money")
	var n1: int = (_fleet().get("ships") as Array).size()
	var v := _verdict(price, START_MONEY - final, list_price)
	if v == "OK" and n1 != n0 + 1:
		v = "SHIP_COUNT"
	_tally(v)
	print("FO_CASE buy_ship/%s %s [%s] price=%d spent=%d ships %d→%d got_press=%s %s %s | %s | %s" % [
		how, v, label, price, START_MONEY - final, n0, n1, got_press, _click_note, _ready_note, d1, d2])
	# 还原舰队规模，免得下一路船多
	while (_fleet().get("ships") as Array).size() > n0:
		(_fleet().get("ships") as Array).pop_back()


## 闸只挡过场期间：落定后再修一次照常扣一次
func _case_release() -> void:
	var unsettled := await _case_repair("mouse")
	if unsettled != "":
		# 铺垫那一路的过场没落定：下面「闸没放开」就不是被测件卡住，是还在演（原先报 STUCK，压帧过重时误诊）
		_tally(_limit_verdict())
		print("FO_CASE release %s 铺垫一路（repair/mouse）%s，本路判不了" % [_limit_verdict(), unsettled])
		return
	var s: Dictionary = _fleet().get("ships")[0]
	s["durability"] = int(s["max_durability"]) - 20
	_main.call("load_scene", "quanzhou_shipyard")
	for _i in 4:
		await get_tree().process_frame
	var m0: int = _gs().get("money")
	var rc: int = _fleet().call("repair_cost")
	var btn := _find_btn("修船")
	# 闸没放开 / 钮没了就是本路要抓的 STUCK，不进点前就绪的等待（那里会把它当前提等满上界）
	if btn == null or rc <= 0 or bool(_main.get("_upgrade_busy")):
		_tally("STUCK")
		print("FO_CASE release STUCK rc=%d btn=%s busy=%s" % [rc, btn != null, _main.get("_upgrade_busy")])
		return
	var not_ready := await _ready_to_click(btn)
	if not_ready != "":
		var nv := _not_ready_verdict()
		_tally(nv)
		print("FO_CASE release %s %s" % [nv, not_ready])
		return
	var got_press := await _first_click(btn, btn.get_global_rect().get_center())
	unsettled = await _settle()
	if unsettled != "":
		_tally(_limit_verdict())
		print("FO_CASE release %s %s（本路不数钱）" % [_limit_verdict(), unsettled])
		return
	var ok := int(_gs().get("money")) == m0 - rc and int(s["durability"]) == int(s["max_durability"])
	var v := "OK"
	if not ok:
		v = "FIRST_CLICK_MISS" if int(_gs().get("money")) == m0 else "STUCK"
	_tally(v)
	print("FO_CASE release %s rc=%d spent=%d busy_after=%s got_press=%s %s %s" % [
		v, rc, m0 - int(_gs().get("money")), _main.get("_upgrade_busy"), got_press, _click_note, _ready_note])
