extends SceneTree
## lane-w53-15 战斗方案一期「点敌船或 Tab 选中出小卡」探针（enemy_intel）：
##   一、布景海战：敌情列 _intel_ship 开局收、sea foe 一艘挂上后 Tab → 选中、行内这艘字涂金；
##       再 Tab → 换到下一艘；点（gui_input 一枚 InputEventMouseButton 左键）对同一行 → 收起 / 换行。
##   二、喊话钮的亮灭 = CombatOrdersPanel.parley_road 的 lit 三样（钩住・帆索残・动摇）：
##       满血未钩簿稳 → 「喊话」disabled；改齐 → 上「disabled」drop；再点细看 → _ship_detail_lbl.visible 展开。
##   三、enemy_intel 关：整列不带 _intel_ship（旧玩法一child）。切细 process 重 run：read_selected enemy None。
## 用法：godot --headless --path . -s res://tools/qa_w53_15_shipcard_probe.gd
## 判词：QA_W53_15_SHIPCARD_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W53_15_SHIPCARD_PROBE"
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
const Orders := preload("res://scripts/ui/CombatOrdersPanel.gd")
const Switches := preload("res://scripts/combat/CombatSwitches.gd")

var _fails: Array = []
var _errlog: _ScriptErrLog = null


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	print(("  ✓ " if ok else "  ✗ ") + what)
	if not ok:
		_fails.append(what)


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	print("== 一、Tab 循环选中、点行替代 / 收起、行字涂金")
	await _sec_tab_and_click(fleet, gm)
	print("== 二、喊话钮的亮灭跟 parley_road 三样；细看钮展开明细")
	await _sec_hail_detail(fleet, gm)
	print("== 三、enemy_intel 关：小卡不建、selected 一直空")
	await _sec_off(fleet, gm)

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	await process_frame
	OS.remove_logger(_errlog)
	_check(_errlog.lines.is_empty(), "本进程无 SCRIPT ERROR（%d 行%s）" % [_errlog.lines.size(),
		"：" + str(_errlog.lines[0]) if not _errlog.lines.is_empty() else ""])
	if _fails.is_empty():
		print("%s PASS" % TAG)
		quit(0)
		return
	print("%s FAIL %d" % [TAG, _fails.size()])
	for f in _fails:
		print("   ✗ " + str(f))
	quit(1)


func _battle(fleet: Node, gm: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 2}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 6:
		await process_frame
	for c in _foes(wm):
		c.set("fire_timer", INF)
	return wm


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _hud_of(wm: Node) -> Node:
	for c in wm.get_children():
		if c.is_in_group(Hud.GROUP):
			return c
	return null


func _sec_tab_and_click(fleet: Node, gm: Node) -> void:
	var wm := await _battle(fleet, gm)
	var hud := _hud_of(wm)
	_check(hud != null, "状态条在场")
	if hud == null:
		await _close(wm)
		return
	_check(hud.call("selected_enemy") == null, "开局未选中敌船（_selected_id = 0）")
	var foes := _foes(wm)
	for _i in 3:
		await process_frame
	# Tab 走 _unhandled_input：绕过 Input.parse + Viewport.push_input 发进去，看面板自择一艘
	var tab_ev := InputEventKey.new()
	tab_ev.keycode = KEY_TAB
	tab_ev.pressed = true
	root.push_input(tab_ev)
	await process_frame
	var first: Node = hud.call("selected_enemy")
	_check(first != null, "按 Tab 后选中一艘（不是 null）")
	_check(first != null and ((first as Object).get_instance_id() == (foes[0] as Object).get_instance_id()
		or (first as Object).get_instance_id() == (foes[1] as Object).get_instance_id()),
		"选中的是场上的一艘")
	hud.call("select_next_enemy")
	var second: Node = hud.call("selected_enemy")
	_check(second != null and second != first, "再 Tab 换到另一艘")
	# 点行收起：把 _select_enemy 再次调用同 id（同 row click 语义 = 再点同一行收起）
	hud.call("_select_enemy", (second as Object).get_instance_id())
	_check(hud.call("selected_enemy") == null, "再点同 id = 再点同一行收起")
	# 点再选：用鼠标 InputEventMouseButton 走 _on_intel_row_gui_input
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = true
	hud.call("_on_intel_row_gui_input", btn, 0)
	var third: Node = hud.call("selected_enemy")
	_check(third != null and (third as Object).get_instance_id() == (foes[0] as Object).get_instance_id(),
		"点第 0 行选中第 0 艘（得 %s）" % str((third as Object).get_instance_id() if third != null else "空"))
	await _close(wm)


func _sec_hail_detail(fleet: Node, gm: Node) -> void:
	var wm := await _battle(fleet, gm)
	var hud := _hud_of(wm)
	if hud == null:
		_check(false, "状态条在场")
		await _close(wm)
		return
	for _i in 2:
		await process_frame
	var foe: Node2D = _foes(wm)[0]
	foe.set_meta(&"nk1_combat_morale", {"state": "steady", "value": 70})
	hud.call("_select_enemy", (foe as Object).get_instance_id())
	hud.call("refresh")
	var ship_card := hud.get("_intel_ship") as Control
	var hail := hud.get("_ship_hail_btn") as Button
	_check(ship_card != null and ship_card.visible, "选中后小卡 _intel_ship 出")
	_check(hail != null and hail.disabled, "满血未钩簿稳：喊话钮 disabled（parley_road 三样不全）")
	# 凑齐三样：钩住・伤过半・动摇 → 钮亮
	foe.set("grappled", true)
	(foe as Object).set_meta(&"nk1_combat_morale", {"state": "wavering", "value": 25})
	var hull0 := Hud.prop_f(foe, "hull_hp", 1.0)
	((hud as Object).get("_hull_seen") as Dictionary)[(foe as Object).get_instance_id()] = hull0
	foe.set("hull_hp", hull0 * 0.3)
	hud.call("refresh")
	_check(not hail.disabled, "钩住・帆残・动摇：喊话钮 enabled")
	foe.set_meta(&"nk1_combat_morale", {"state": "steady", "value": 70})
	foe.set("grappled", false)
	# 细看钮：点击 toggle detail
	var detail: Label = hud.get("_ship_detail_lbl")
	_check(detail != null and not detail.visible, "细看前 detail 收")
	hud.call("_toggle_detail")
	_check(detail.visible and detail.text != "", "点细看：detail 展开且写有船体 / 士气文字（%s）" % detail.text.split("　")[0])
	await _close(wm)


func _sec_off(fleet: Node, gm: Node) -> void:
	Switches.set_on("enemy_intel", false)
	var wm := await _battle(fleet, gm)
	var hud := _hud_of(wm)
	if hud != null:
		_check(hud.get("_intel_ship") == null and hud.get("_intel") == null, "enemy_intel 关：小卡 / 敌情列一概不建（旧玩法一child）")
		_check(hud.call("selected_enemy") == null, "enemy_intel 关：selected 架不起来 = null")
	await _close(wm)
	Switches.reset()


class _ScriptErrLog extends Logger:
	var lines: Array = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass
