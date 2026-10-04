extends SceneTree
## lane-w53-15 战斗方案二期新号令「砍钩」（order_cut_grapple）探针（headless）：
##   一、MeleeResolve.cut_chance 纯函数：bit=2 / crew_frac=1 下 下 cut 令 = 1.5× 未下；crew=半 ×1/2、bit 上去了 ×2/N。
##   二、真实场景：战备 WorldMap 起两艘，把敌船「钩」上、置 front=0 吃紧、让守方多合掷 cut —
##       用 resolve 直接造样本更快：同 seed 双造 resolve （玩家守方）：
##        ① 不设 def_cut_mul → 与 wave53 开工前一致（当前系统守方砍缆率 = CUT_BASE）
##        ② def_cut_mul = 1.5 → 守方脱缆结局率显著更高（跑到 200 场比较 cut_loose 出数）
##   三、号令面板接受「砍钩」：order_cut_grapple 开时 6 号出令、cut_mul = 1.5；关掉开关 issue("cut") 返 {}、
##       modifiers 里 cut_mul 仍 1.0（旧玩法一child）。签面 state_text（开关开） = 已令 / 未令，关 = 未接。
##   四、WorldMap 守方接线（借改）：真打一场敌攻我守的白刃（enemy_first=true），
##       ctx.def_cut_mul = order_mods().cut_mul（2 栏：开关开时下 6 号=1.5、没下=1.0）
## 用法：godot --headless --path . -s res://tools/qa_w53_15_cut_probe.gd
## 判词：QA_W53_15_CUT_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W53_15_CUT_PROBE"
const Melee := preload("res://scripts/combat/MeleeResolve.gd")
const Orders := preload("res://scripts/ui/CombatOrdersPanel.gd")
const Hud := preload("res://scripts/ui/CombatStatusHud.gd")
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

	print("== 一、cut_chance 纯函数")
	_sec_cut_chance()
	print("== 二、def_cut_mul ≠ 1.0 时守方脱缆多（造样 200 场）")
	_sec_resolve_cut_rate()
	print("== 三、号令面板 6 号「砍钩」开关对照")
	await _sec_panel()
	print("== 四、WorldMap 守方接线（借改一行只读）")
	await _sec_worldmap_wiring()

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


func _sec_cut_chance() -> void:
	var base: float = Melee.cut_chance(2, 1.0, 1.0)
	var cut: float = Melee.cut_chance(2, 1.0, 1.5)
	_check(is_equal_approx(base, 0.15), "bit=2 / crew=满 / 未下：基率 = CUT_BASE 0.15（得 %.3f）" % base)
	_check(is_equal_approx(cut, 0.225), "bit=2 / crew=满 / 下砍钩 = ×1.5 → 0.225（得 %.3f）" % cut)
	_check(Melee.cut_chance(2, 0.5, 1.0) < base, "守方人手减半则砍难（%.3f < %.3f）" % [Melee.cut_chance(2, 0.5, 1.0), base])
	_check(Melee.cut_chance(8, 1.0, 1.0) < base, "咬住 8 具比 2 具难砍（%.3f < %.3f）" % [Melee.cut_chance(8, 1.0, 1.0), base])
	_check(Melee.cut_chance(2, 0.0, 1.5) == 0.0, "守方死尽无砍")
	_check(Melee.cut_chance(2, 1.0, 0.0) == 0.0, "显式乘 0 = 禁用（接线 / 折断 拢以备）")


## 让守方在 front=0 吃紧多合推銬 cut / 未 cut：均势偏一点点偏弱造样（守方能撑过前几合、每合簿吃紧都只蹲 0 位）
func _resolve_runs(def_cut_mul: float, n := 200) -> Dictionary:
	var us := Melee.make_side(95, 68, 1.0, "fu_ship_medium", {"is_player": true, "name": "本土"})
	var foe := Melee.make_side(100, 66, 1.0, "sea_falcon", {"name": "海鹘"})
	var out := {"capture": 0, "surrender": 0, "repelled": 0, "cut_loose": 0, "hook_miss": 0}
	var ctx := {"hooked": true, "rel_speed": 0.0, "distance": 80.0, "wind": 80.0, "windward": 0, "sea": 1, "def_cut_mul": def_cut_mul}
	for i in range(n):
		var c: Dictionary = ctx.duplicate()
		c["seed"] = 9100 + i
		var r: Dictionary = Melee.resolve(us, foe, c)
		out[str(r["outcome"])] = int(out[str(r["outcome"])]) + 1
	return out


func _sec_resolve_cut_rate() -> void:
	var a := _resolve_runs(1.0)
	var b := _resolve_runs(1.5)
	var cut_a: int = a["cut_loose"]
	var cut_b: int = b["cut_loose"]
	_check(cut_b > cut_a, "下砍钩的守方脱缆结局更多：1.0 时 %d 场、1.5 时 %d 场 （%d > %d）" % [cut_a, cut_b, cut_b, cut_a])
	_check(cut_b >= 8, "守方脱缆率起调后不为 0（得 %d）" % cut_b)


func _sec_panel() -> void:
	# WorldMap 战备中的真面板：面板的 build / mount 由 WorldMap 挂起，本探从准备好的海战场里照例取
	# 不 new 一个停泊不动的（bind / world_ref 空、签面与 ship dock 都判不到位）
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 4:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	var panel: Node = null
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			panel = c
			break
	_check(panel != null, "号令面板在场")
	if panel != null:
		var st_text: String = panel.call("state_text", "cut")
		_check(st_text == "未令", "开关开、未下：签字面「未令」（得 %s）" % st_text)
		var pay: Dictionary = panel.call("issue", "cut")
		_check(String(pay.get("order", "")) == "cut" and bool(pay.get("on", false)), "6 号出令「砍钩」＝ true")
		var mods: Dictionary = panel.call("current_modifiers")
		_check(is_equal_approx(float(mods.get("cut_mul", 0.0)), 1.5), "modifiers.cut_mul = 1.5 起令后")
		var st2: String = panel.call("state_text", "cut")
		_check(st2 == "已令", "6 号已令：签字面「已令」")
		Switches.set_on("order_cut_grapple", false)
		var pay_off: Dictionary = panel.call("issue", "cut")
		_check(pay_off.is_empty(), "off：issue(\"cut\") 返 {}，与 wave53 开工前一致（不下也不济）")
		var st3: String = panel.call("state_text", "cut")
		_check(st3 == "未接", "off：签字面写「未接」")
		var mods_off: Dictionary = Orders.modifiers({"cut": true})
		_check(is_equal_approx(float(mods_off.get("cut_mul", 1.0)), Orders.CUT_CHANCE_MUL),
			"modifiers 纯函数：st.cut=true → cut_mul=1.5（关掉开关的版型静剧动舵一并于 issue）")
		Switches.reset()

	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	Switches.reset()


func _sec_worldmap_wiring() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 4:
		await process_frame
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			c.set("fire_timer", INF)
	var foe: Node2D = null
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			foe = c
			break
	var panel: Node = null
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			panel = c
			break
	if panel == null or foe == null:
		_check(false, "面板 / 敌船双样都在场")
	else:
		# 未下发 ⇒ def_cut_mul = 1.0（ combat_orders 面板下，此现镰主张浮る）
		var sides_off: Array = wm.call("_melee_sides", foe, true)
		var ctx_off: Dictionary = sides_off[2]
		_check(is_equal_approx(float(ctx_off.get("def_cut_mul", 0.0)), 1.0), "未下砍钩：_melee_sides ctx.def_cut_mul = 1.0（得 %.2f）" % float(ctx_off.get("def_cut_mul", -1.0)))
		# 下 6 号再查
		panel.call("issue", "cut")
		var sides_on: Array = wm.call("_melee_sides", foe, true)
		var ctx_on: Dictionary = sides_on[2]
		_check(is_equal_approx(float(ctx_on.get("def_cut_mul", 0.0)), 1.5), "下了「砍钩」：_melee_sides ctx.def_cut_mul = 1.5（得 %.2f）" % float(ctx_on.get("def_cut_mul", -1.0)))
		# 本队先钩（敌攻我守反面）：def = 敌船，cut_mul 与本队号令无关
		var sides_own: Array = wm.call("_melee_sides", foe, false)
		var ctx_own: Dictionary = sides_own[2]
		_check(not ctx_own.has("def_cut_mul"), "本队先钩：不给敌簿下砍钩（得 %s）" % str(ctx_own.get("def_cut_mul", "无")))
		# 关总开关：modal 开动 hull_ctx 1.0（不再由号令阐明，上迅实际是 1.0 照恒）
		Switches.set_on("order_cut_grapple", false)
		var sides_sw: Array = wm.call("_melee_sides", foe, true)
		var ctx_sw: Dictionary = sides_sw[2]
		_check(is_equal_approx(float(ctx_sw.get("def_cut_mul", 0.0)), 1.0), "off：under.tell cut 关时入 1.0（得 %.2f）" % float(ctx_sw.get("def_cut_mul", -1.0)))
		Switches.reset()

	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
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
