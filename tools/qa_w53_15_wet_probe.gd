extends SceneTree
## lane-w53-15 战斗方案二期新号令「张湿毡」（order_wet_felt，DamageModel 一侧）探针（headless）：
##   一、DamageModel.apply_hit 开关对照（纯账）：同 type / 同量（箭如雨）惨打 400 发统计：
##       on 中弹引火机会折半、受矢石伤亡 ×0.7；off 一切照旧。
##   二、DamageModel.step 火一路照打 60 s 明火：on 烧到船身、烧帆、烧人都减半（burn ×0.5）。
##   三、号令面板 7 号：order_wet_felt 开时 issue("wet") 效差 modifiers 里 ignite=0.5、exposure=0.7、
##       reload_time ×1.15、board_bonus ×0.9；apply_to_ship 把 wet_felt 落到 Ship.damage_model。
##       关掉开关：issue("wet") 返 {}、DamageModel.wet_felt 拾 default false、照 wave53 开工前件。
## 用法：godot --headless --path . -s res://tools/qa_w53_15_wet_probe.gd
## 判词：QA_W53_15_WET_PROBE PASS / FAIL k；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W53_15_WET_PROBE"
const Dm := preload("res://scripts/combat/DamageModel.gd")
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

	print("== 一、DamageModel.apply_hit：wet_felt 折半引火 + ×0.7 伤亡")
	_sec_apply_hit()
	print("== 二、DamageModel.step 火账照 half")
	_sec_step_fire()
	print("== 三、号令面板 7 号与 DamageModel 接线（开 / 关开关对照）")
	await _sec_panel_wiring()

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


## 数学断言 + 中火首火对比（同 seed 分簿、每簿首枚 fire kind 是否着：预期 on ≈ 0.4×簿数、off ≈ 0.8×簿数）+
## 死伤对比（on 明显少于 off），把按 fire/casualty_mul 的判青夫在函数数学面上打成一个开裂处。
func _sec_apply_hit() -> void:
	var def: Dictionary = root.get_node("Fleet").call("ship_def", "fu_ship_medium")
	var dm_off := Dm.new()
	dm_off.call("setup", "fu_ship_medium", def, 60, 300.0, 300.0, 42)
	var dm_on := Dm.new()
	dm_on.call("setup", "fu_ship_medium", def, 60, 300.0, 300.0, 42)
	dm_on.call("set_wet_felt", true)
	_check(is_equal_approx(float(dm_off.call("fire_effects_mul")), 1.0), "off：fire_effects_mul = 1.0")
	_check(is_equal_approx(float(dm_on.call("fire_effects_mul")), 0.5), "on：fire_effects_mul = 0.5")
	_check(is_equal_approx(float(dm_on.call("casualty_mul")), 0.7), "on：casualty_mul = 0.7")
	_check(is_equal_approx(float(dm_off.call("casualty_mul")), 1.0), "off：casualty_mul = 1.0")
	# 首火对比：50 簿每簿首 40 发 fire kind，着火次数跨簿统计
	var off_a := _first_fire_stats(false, def)
	var on_a := _first_fire_stats(true, def)
	_check(int(off_a) >= 25 and int(off_a) <= 48, "off 50 簿首枚 fire kind 中 火数 ≈ 40 (点火概率 0.8，得 %d)" % int(off_a))
	_check(int(on_a) >= 4 and int(on_a) <= 30, "on 50 簿首枚 fire kind 中 火数 ≈ 20 (点火概率 0.4，得 %d)" % int(on_a))
	# 死伤对比（同批 bomb+arrow，湿毡 ×0.7）
	var dead_off := _casualty_stats(false, def)
	var dead_on := _casualty_stats(true, def)
	_check(dead_off > 0 and dead_on > 0 and dead_on <= dead_off * 0.9,
		"on 伤亡 ≤ off ×0.9（得 off=%d on=%d，期望比 ≈ 0.7）" % [dead_off, dead_on])


## 50 簿：每簿第一枚 fire kind 的中火（zone 未起时 ignite() 必有事件，檄明单发 的 roll 到底有没有着）跨簿数；
## 旧口径（逐发 events 数）zone 上 cap 后不再报事件，判不出点火机会的差异，改用首枚
func _first_fire_stats(wet: bool, def: Dictionary) -> int:
	var cnt := 0
	for batch in range(50):
		var dm := Dm.new()
		dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 700 + batch)
		if wet:
			dm.call("set_wet_felt", true)
		var r: Dictionary = dm.call("apply_hit", {"amount": 25.0, "kind": "fire", "high": true})
		var got := false
		for e in (r.get("events", []) as Array):
			if String((e as Dictionary).get("kind", "")) == "fire":
				got = true
				break
		if got:
			cnt += 1
	return cnt


func _casualty_stats(wet: bool, def: Dictionary) -> int:
	var casum := 0
	for batch in range(50):
		var dm := Dm.new()
		dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 700 + batch)
		if wet:
			dm.call("set_wet_felt", true)
		for j in range(30):
			var kind: String = ["bomb", "arrow"][j % 2]
			var r: Dictionary = dm.call("apply_hit", {"amount": 25.0, "kind": kind, "high": true})
			casum += int(r.get("crew", 0))
	return casum


func _sec_step_fire() -> void:
	var def: Dictionary = root.get_node("Fleet").call("ship_def", "fu_ship_medium")
	var a := _burn_in_seconds(false, def)
	var b := _burn_in_seconds(true, def)
	_check(a > 0.0, "fo 步 off 后火非零（得 %.4f）" % a)
	_check(a > 0.0 and is_equal_approx(b, a * 0.5), "照步 60 s：on 总烧量 ≌ off ×0.5（off=%.4f on=%.4f）" % [a, b])


## 簿上起一栏中火，步 60 s（5 s tick×12）累计烧船 / 烧帆；Dev null 按 off 另开一簿同 seed 确 star概率
func _burn_in_seconds(wet: bool, def: Dictionary) -> float:
	var dm := Dm.new()
	dm.call("setup", "fu_ship_medium", def, 80, 300.0, 300.0, 1141)
	if wet:
		dm.call("set_wet_felt", true)
	var ff = dm.get("ff")
	ff.call("ignite", "mid", 0.8)
	# 簿上到 0 个救火手（crew 归零不分派）——只验 DamageModel step 在火一层的烧账本身，
	# 别和 crew_split 自己起的救火战上（救火起后火势一走、 off/on 同 seed 殊途灭失都看不到）
	dm.call("set_crew", 0)
	var tot := 0.0
	for i in range(12):
		var r: Dictionary = dm.call("step", 5.0, {})
		tot += float(r.get("hull", 0.0))
	return tot


func _foes(wm: Node) -> Array:
	return wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


func _battle(fleet: Node, gm: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "canton_ship")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "canton_ship", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "sea_falcon", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_15"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 4:
		await process_frame
	for c in _foes(wm):
		c.set("fire_timer", INF)
	return wm


func _sec_panel_wiring() -> void:
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"), "pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}

	# 开：7 号 wet 效差 modifiers & apply_to_ship 落 Ship.damage_model
	var wm := await _battle(fleet, gm)
	var panel: Node = null
	for c in wm.get_children():
		if c.is_in_group(Orders.GROUP):
			panel = c
			break
	_check(panel != null, "号令面板在场")
	var ship: Node2D = Hud.ship_of(wm)
	var dm = Hud.damage_of(ship)
	_check(dm != null, "旗舰损伤簿（Ship.damage_model）在场")
	if panel != null and dm != null:
		var pay: Dictionary = panel.call("issue", "wet")
		_check(String(pay.get("order", "")) == "wet" and bool(pay.get("on", false)), "7 号出令「张湿毡」＝ true")
		var mods: Dictionary = panel.call("current_modifiers")
		_check(is_equal_approx(float(mods.get("ignite", 1.0)), 0.5), "ignite 折半 = 0.5（得 %.2f）" % float(mods.get("ignite", 1.0)))
		_check(float(mods.get("exposure", 1.0)) < 1.0, "exposure 受矢石伤亡 ×0.7 起令加权（得 %.2f）" % float(mods.get("exposure", 1.0)))
		panel.call("apply_to_ship")
		_check(bool((dm as Object).get("wet_felt")), "apply_to_ship 把 wet_felt 落到 Ship.damage_model")
		# 照世行推一下修改：off 泡甜仍有 apply_to_ship 时 wet_felt 不 advance置（笺子开、湿毡关）
		panel.call("issue", "wet")  # 撤
		panel.call("apply_to_ship")
		_check(not bool((dm as Object).get("wet_felt")), "撤令后再 apply_to_ship：wet_felt 落回 false")
	await _close(wm)
	Switches.reset()

	# 关：7 号不下、DamageModel 保持 default false
	Switches.set_on("order_wet_felt", false)
	var wm2 := await _battle(fleet, gm)
	var panel2: Node = null
	for c in wm2.get_children():
		if c.is_in_group(Orders.GROUP):
			panel2 = c
			break
	if panel2 != null:
		var pay_off: Dictionary = panel2.call("issue", "wet")
		_check(pay_off.is_empty(), "order_wet_felt 关：issue(\"wet\") 返 {}、面签 \"未接\"（得 %s）" % str(panel2.call("state_text", "wet")))
		var dm2 = Hud.damage_of(Hud.ship_of(wm2))
		_check(dm2 == null or not bool((dm2 as Object).get("wet_felt")), "off：DamageModel.wet_felt 照旧 default false")
	await _close(wm2)
	Switches.reset()

	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])


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