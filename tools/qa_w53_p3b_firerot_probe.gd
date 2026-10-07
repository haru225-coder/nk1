extends SceneTree
## lane w53-p3b 火攻回到装填轮换专项探针（headless）：真起 WorldMap 海战场（同一 8 个种子可比），对账
## 「开关 fire_attack_load 开 / player_gunnery 开时火攻进轮换、引火乘数真落到旗舰射出的弹上」与
## 「任一不满足照旧两档轮换、火攻令不下」。逐节（①–③ 纯函数、④ 真战场开关两态、⑤ 湿毡不混乘）：
##   一、纯函数：battery_orders({"load": "fire"}) 出 {"fire_mode": true}；fire_attack_factor(1/0/-1) = 1.5/1.0/0.6；
##       开关两态的轮换序列 —— fire_attack_load 开且旗舰挂装填簿时三档（含火攻），关时两档。
##   二、真战场开关开：按 2 键轮到第三档签面写「火攻」、battery.fire_mode 变真；放一舷，弓弩改放火箭（huojian），
##       射出的弹 fire > 0 且乘了 LOAD_TABLE.fire 的 ignite × 风位折算（本战场敌船在我下风向 / 上风 / 相平三格）；
##       湿毡（order_wet_felt 令下）不混乘进引火（只压 reload_time 一路），弹上 fire 仍 = 基础 × 风位。
##   三、真战场开关关 / player_gunnery 关：轮换两档（均装 ⇄ 专力装填、轮不到火攻）、fire_mode 不变假、
##       签面与提示与 w53-2 账逐字一致（ORDER_TIPS["load"] 原文）。
##   四、回退修复须红：开关开时 ship._load_orders(self) 取到面板两令；没有面板回中性（fire_mode false、引火 1.0）。
## 胜率口径（同 COMMON §胜率）：开关开 vs 关各 8 场（同 8 个种子，300 秒窗口，敌将 live、士气裁决可早收）的胜场差
## 由本探针外层的 qa_w53_p3b_winrate_probe.gd 另测（敌船此 lane 未挂 FloodFire，火攻烧的是开工前的敌船——写明测的基线）。
## 判词：QA_W53_P3B_FIREROT PASS / FAIL k；本进程出 SCRIPT ERROR 也判红。只改内存里的 Fleet / GameState / pending_battle，跑完还原。

const TAG := "QA_W53_P3B_FIREROT"

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

	print("== 一、纯函数：落令口与风位折算")
	_sec_pure()
	print("== 二、真战场开关开：轮换三档、火攻令落地、引火乘数上乘")
	await _sec_on(fleet)
	print("== 三、开关两态轮换与签面（关时与 w53-2 账逐字一致）")
	await _sec_off(fleet)
	print("== 四、_load_orders 面板在 / 不在两路")
	_sec_load_orders()

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


## 同 qa_w53_2_combat_probe._battle：一只广船（merchant 簿、有砲）对一艘快船；敌炮冻住
func _battle(fleet: Node) -> Node:
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	root.get_node("GameManager").set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 1}], "sea_name": "泉州外海", "source": {"scene": "qa_w53_p3b"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	for f in wm.get_children():
		if String(f.name).begins_with("PirateShip"):
			f.set("fire_timer", INF)
	return wm


func _panel_of(wm: Node) -> Node:
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			return n
	return null


func _close(wm) -> void:
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame


## 第一节 纯函数（不起战场，直接静态口）
func _sec_pure() -> void:
	var op: GDScript = load("res://scripts/ui/CombatOrdersPanel.gd")
	var bo: Dictionary = op.call("battery_orders", {"load": "fire"})
	_check(bool(bo.get("fire_mode", false)) and str(bo.get("emphasis", "")) == "balanced",
		"一① battery_orders({load: fire}) 出 fire_mode=true、emphasis balanced（得 %s）" % str(bo))
	var f_up := float(op.call("fire_attack_factor", 1))
	var f_lv := float(op.call("fire_attack_factor", 0))
	var f_dn := float(op.call("fire_attack_factor", -1))
	_check(is_equal_approx(f_up, 1.5) and is_equal_approx(f_dn, 0.6) and is_equal_approx(f_lv, 1.0),
		"一② fire_attack_factor 居上风 1.5 / 相平 1.0 / 居下风 0.6（得 %.1f / %.1f / %.1f）" % [f_up, f_lv, f_dn])
	var lt = op.get("LOAD_TABLE")
	_check(lt is Dictionary, "一③ LOAD_TABLE 取得到（%s）" % str(lt is Dictionary))
	var fire_row: Dictionary = (lt as Dictionary).get("fire", {}) if lt is Dictionary else {}
	_check(is_equal_approx(float(fire_row.get("reload", -1.0)), 1.15) and is_equal_approx(float(fire_row.get("ignite", -1.0)), 3.0),
		"一③ LOAD_TABLE.fire 照表：装填 ×1.15、引火 ×3（得 %s / %s）" % [fire_row.get("reload"), fire_row.get("ignite")])
	# ④ 状态句（ReloadAmmo.status_line）：火攻令在时句尾缀「火攻」；火药告急 / 用尽时弹药段写出（少 / 尽）——
	#    「火攻（缺药）」这类情形状态条读得出来，不用加新键
	var ra: GDScript = load("res://scripts/combat/ReloadAmmo.gd")
	var bat2 = ra.call("for_ship", ra.call("ship_def_of", "fu_ship_medium"), 60, {"tier": "merchant"})
	bat2.call("set_fire_mode", true)
	var s_fire: String = bat2.call("status_line")
	bat2.call("set_fire_mode", false)
	var s_norm: String = bat2.call("status_line")
	_check(s_fire.ends_with("火攻") and not s_norm.ends_with("火攻"),
		"一④ 状态句：火攻令在时句尾缀「火攻」，撤令不缀（得 %s / %s）" % [s_fire.right(12), s_norm.right(12)])
	var ammo2: Dictionary = bat2.get("ammo")
	ammo2["huoyao"] = 0
	bat2.set("ammo", ammo2)
	bat2.call("set_fire_mode", true)
	var s_dry: String = bat2.call("status_line")
	_check(s_dry.ends_with("火攻") and s_dry.find("火药") >= 0 and s_dry.find("尽") >= 0,
		"一④ 火攻缺药：状态句仍缀「火攻」，弹药段「火药 …（尽）」看得出来（得 …%s）" % s_dry.right(30))


## 第二节 开关开：轮换三档、火攻令落地、引火乘数乘到弹上
func _sec_on(fleet: Node) -> void:
	var sw: GDScript = load("res://scripts/combat/CombatSwitches.gd")
	sw.call("set_on", "player_gunnery", true)
	sw.call("set_on", "fire_attack_load", true)
	var wm := await _battle(fleet)
	var panel := _panel_of(wm)
	var own: Node = wm.get("ship")
	var bat = own.get("battery") if own != null else null
	if panel == null or own == null or bat == null:
		_check(false, "二 挂上号令面板、旗舰装填簿在（关 player_gunnery 时不验本节）")
		await _close(wm)
		sw.call("reset")
		return
	# ① 轮换三档：mixed → rapid → fire → mixed；签面第三档写「火攻」
	var seen := PackedStringArray([str(panel.call("state_text", "load"))])
	panel.call("issue", "load")
	seen.append(str(panel.call("state_text", "load")))
	panel.call("issue", "load")
	seen.append(str(panel.call("state_text", "load")))
	_check(seen.size() == 3 and seen[2] == "火攻",
		"二① 开关开按 2 键轮到第三档签面写「火攻」（得 %s）" % " → ".join(seen))
	_check(bool((bat as Object).get("fire_mode")),
		"二① 火攻令落地：battery.fire_mode 变真（得 %s）" % str((bat as Object).get("fire_mode")))
	var rota: Array = panel.call("loads")
	_check(rota.size() == 3 and String(rota[2]) == "fire", "二① loads() 三档、末档 fire（得 %s）" % str(rota))
	# ② 引火乘数：把敌船摆在我右舷正横（全效弧），同一条舷线上风侧取点 = 我居上风、下风侧取点 = 居下风；
	# 风向每场海况不一样，用镜像构造：上风敌位 = 下风敌位照风向镜像
	var foe: Node2D = null
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip"):
			foe = c
	if foe == null:
		_check(false, "二② 敌船在场")
		await _close(wm)
		sw.call("reset")
		return
	foe.set_physics_process(false)
	(foe as Node2D).global_rotation = 0.0  # 与旗舰同朝向：弧点布位按右舷 beam 算，不受敌船自身旋转影响
	var wv: Vector2 = (own.get("wind_vector") as Vector2).normalized()  # 吹向；敌在吹向一侧 = 敌在下方风、我居上风
	# 把旗舰转正到「右舷正横 = 吹向」——风与我横舷一致时，正横处敌船是我居上风、对蹠是居下风。布点不赌风况：
	# 上风 = oe + wv×280，下风 = oe − wv×280，两点都落在全效弧正心（舷角 0°）
	var oe: Vector2 = (own as Node2D).global_position
	var beam := Vector2.RIGHT.rotated((own as Node2D).global_rotation)
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()  # 转右舷对准吹向
	beam = Vector2.RIGHT.rotated((own as Node2D).global_rotation)
	var hud: GDScript = load("res://scripts/ui/CombatStatusHud.gd")
	_check(beam.distance_to(wv) < 0.01, "二② 转舷自证：右舷正横对准吹向（beam=%s wv=%s）" % [str(beam.round()), str(wv.round())])
	var foe_up: Vector2 = oe + wv * 280.0  # 敌在吹向侧：我居上风
	var foe_dn: Vector2 = oe - wv * 280.0  # 对蹠：居下风
	foe.global_position = foe_up
	# 舷侧整舷装毕才验弹面：手推不足再补，最多 20 秒（刚转舷后弓弩队换舷 2s + 床子弩 13s + 火砲 12s）
	var settle0 := 0.0
	while int((bat as Object).call("ready_count", 1)) < int((bat as Object).call("mount_count", 1)) and settle0 < 20.0:
		(bat as Object).call("tick", 1.0, -1, -1.0, -1.0)
		settle0 += 1.0
	# 不晃过物理帧：布完点直接射（机动模型每帧改船姿态；本格只验「乘数上乘」不验弹道 AI）
	foe.global_position = (own as Node2D).global_position + wv * 280.0
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()
	own.set("fire_cooldown", 0.0)
	var before: Array = (own.get_parent() as Node).get_children()
	own.call("_fire_broadside", 1)
	var shots: Array = []
	for c in (own.get_parent() as Node).get_children():
		if not before.has(c) and c is Area2D and c.get("shot") is Dictionary:
			shots.append(c)
	var want_up := 3.0 * 1.5  # LOAD_TABLE.fire.ignite × fire_attack_factor(居上风)
	var ok_up := not shots.is_empty()
	var seen_wid := ""
	for cb in shots:
		var s: Dictionary = cb.get("shot")
		var fw := str(s.get("weapon", ""))
		if fw == "huojian" or fw == "huopao":
			seen_wid = fw
			var f0 := 0.18 if fw == "huojian" else 0.55
			if absf(float(s.get("fire", 0.0)) - f0 * want_up) > 0.001:
				ok_up = false
	_check(ok_up and seen_wid != "",
		"二② 居上风放一舷：弓弩改火箭（%s），弹上 fire = 基础 × %.1f（得 %d 颗、%s fire）" % [
			seen_wid, want_up, shots.size(),
			";".join(shots.map(func(c): return "%s %.2f" % [(c.get("shot") as Dictionary).get("weapon"), float((c.get("shot") as Dictionary).get("fire", 0.0))]))])
	_check(is_equal_approx(float((bat as Object).get("last_volley_ignite")), want_up),
		"二② 簿上 last_volley_ignite 记 %.1f（得 %.2f）" % [want_up, float((bat as Object).get("last_volley_ignite"))])
	var up_read := int(own.call("_fire_upwind", foe)) if own.has_method("_fire_upwind") else -99
	_check(up_read == 1, "二② 风位读出我居上风（_fire_upwind 得 %d）" % up_read)
	# ③ 居下风：另一侧弧内点，引火 ×0.6（风位与②异号已布点自证）
	for cb in shots:
		cb.queue_free()
	foe.global_position = foe_dn
	# 让弓弩队先抬脚换舷（fire() 记录 move=2.0 后这次只放得出床子弩），等他们到位、左舷装毕再验弹面
	foe.global_position = (own as Node2D).global_position - wv * 280.0
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()
	own.set("fire_cooldown", 0.0)
	(bat as Object).call("fire", -1, 0.0, 280.0, 0)  # 预令：squad 记换舷
	var settle1 := 0.0
	while settle1 < 20.0:
		(bat as Object).call("tick", 1.0, -1, -1.0, -1.0)
		settle1 += 1.0
		var ready_n := int((bat as Object).call("ready_count", -1))
		var total_n := int((bat as Object).call("mount_count", -1))
		if ready_n >= total_n:
			break
	foe.global_position = (own as Node2D).global_position - wv * 280.0
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()
	own.set("fire_cooldown", 0.0)
	var before2: Array = (own.get_parent() as Node).get_children()
	own.call("_fire_broadside", -1)  # −wv 那舷是左舷：舷角正心、风位翻成居下风
	var want_dn := 3.0 * 0.6
	var ok_dn := false
	var seen_dn := ""
	for c in (own.get_parent() as Node).get_children():
		if not before2.has(c) and c is Area2D and c.get("shot") is Dictionary:
			var s: Dictionary = c.get("shot")
			var fw := str(s.get("weapon", ""))
			if fw == "huojian" or fw == "huopao":
				seen_dn += "%s %.2f " % [fw, float(s.get("fire", 0.0))]
				var f0 := 0.18 if fw == "huojian" else 0.55
				if absf(float(s.get("fire", 0.0)) - f0 * want_dn) < 0.001:
					ok_dn = true
	_check(ok_dn, "二③ 居下风放一舷：火箭 fire = 基础 × %.1f（得 %s）" % [want_dn, seen_dn if seen_dn != "" else "无火弹"])
	var dn_read := int(own.call("_fire_upwind", foe)) if own.has_method("_fire_upwind") else -99
	_check(dn_read == -1, "二③ 风位读出我居下风（_fire_upwind 得 %d）" % dn_read)
	# ④ 张湿毡（order_wet_felt）：panel 的 ignite 自身效力折半是给「面板 ignite」那一颗钉的；
	#    Ship 配弹走 LOAD_TABLE.fire.ignite 不经 order_mods，湿毡不再混乘——弹上 fire 仍 = 基础 × 风位。
	#    （先补火药：②③ 两舷各抛过火砲，账面 48 两只够两发，补回再验——验的是「湿毡不混乘」不验弹尽退回）
	(bat as Object).call("resupply", "huoyao", 96)
	var am: Dictionary = (bat as Object).get("ammo")
	am["huoyao"] = 96
	am["nujian"] = 48
	(bat as Object).set("ammo", am)
	var amm: Dictionary = (bat as Object).get("ammo_max")
	amm["huoyao"] = 96
	(bat as Object).set("ammo_max", amm)
	for c in (own.get_parent() as Node).get_children():
		if c is Area2D and c.get("shooter") == own and c.get("shot") is Dictionary:
			c.queue_free()
	# 预令右舷：squad 记换舷；床子弩 13s + 弓弩队归位 2s 一并推过再验
	foe.global_position = (own as Node2D).global_position + wv * 280.0
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()
	own.set("fire_cooldown", 0.0)
	(bat as Object).call("fire", 1, 0.0, 280.0, 0)
	var settle_w := 0.0
	while settle_w < 20.0:
		(bat as Object).call("tick", 1.0, -1, -1.0, -1.0)
		settle_w += 1.0
		if int((bat as Object).call("ready_count", 1)) >= int((bat as Object).call("mount_count", 1)):
			break
	foe.global_position = (own as Node2D).global_position + wv * 280.0
	(own as Node2D).global_rotation = wv.angle() - Vector2.RIGHT.angle()
	sw.call("set_on", "order_wet_felt", true)
	panel.call("issue", "wet")
	own.set("fire_cooldown", 0.0)
	var before3: Array = (own.get_parent() as Node).get_children()
	own.call("_fire_broadside", 1)
	var ok_wet := false
	var wet_seen := ""
	for c in (own.get_parent() as Node).get_children():
		if not before3.has(c) and c is Area2D and c.get("shot") is Dictionary:
			var s: Dictionary = c.get("shot")
			var fw := str(s.get("weapon", ""))
			if fw == "huojian" or fw == "huopao":
				wet_seen += "%s %.2f " % [fw, float(s.get("fire", 0.0))]
				var f0 := 0.18 if fw == "huojian" else 0.55
				if absf(float(s.get("fire", 0.0)) - f0 * want_up) < 0.001:
					ok_wet = true
	panel.call("issue", "wet")  # 撤湿毡
	sw.call("set_on", "order_wet_felt", true)
	sw.call("set_on", "player_gunnery", true)
	sw.call("set_on", "fire_attack_load", true)
	_check(ok_wet, "二④ 张湿毡下：火箭 fire 仍 = 基础 × 上风 %.1f（湿毡不混乘进引火，得 %s）" % [want_up, wet_seen if wet_seen != "" else "无火弹"])
	await _close(wm)
	sw.call("reset")


## 第三节 开关关 / player_gunnery 关：轮换两档、签面与提示逐字回 w53-2 账
func _sec_off(fleet: Node) -> void:
	var op: GDScript = load("res://scripts/ui/CombatOrdersPanel.gd")
	var want_tip := str((op.get("ORDER_TIPS") as Dictionary).get("load", ""))
	var sw: GDScript = load("res://scripts/combat/CombatSwitches.gd")
	for cfg in [["fire_attack_load 关", {"fire_attack_load": false, "player_gunnery": true}],
			["player_gunnery 关", {"fire_attack_load": true, "player_gunnery": false}]]:
		sw.call("set_on", "fire_attack_load", bool(cfg[1]["fire_attack_load"]))
		sw.call("set_on", "player_gunnery", bool(cfg[1]["player_gunnery"]))
		var wm := await _battle(fleet)
		var panel := _panel_of(wm)
		var own: Node = wm.get("ship")
		if panel == null or own == null:
			_check(false, "三 %s：挂上号令面板、旗舰在场" % cfg[0])
			await _close(wm)
			continue
		# 直设 load_mode = "fire" 再落令（模拟「下过火攻令之后开关路上被关」）：apply_to_ship 须把档位按 loads() 回落均装、
		# battery 收回 fire_mode（三态同吃 loads()）
		var bat = own.get("battery")
		panel.set("load_mode", "fire")
		if bat != null:
			(bat as Object).call("set_fire_mode", true)
		panel.call("apply_to_ship")
		var st: Dictionary = panel.call("state")
		_check(String(st.get("load", "")) != "fire" and String(panel.get("load_mode")) == "mixed"
			and (bat == null or not bool((bat as Object).get("fire_mode"))),
			"三 %s：火攻档在外（开关关 / 簿缺）落令即回落均装（state.load=%s，load_mode=%s，fire_mode=%s）" % [
				cfg[0], st.get("load"), panel.get("load_mode"), str((bat as Object).get("fire_mode")) if bat != null else "无簿"])
		var names := PackedStringArray()
		for _i in 3:
			panel.call("issue", "load")
			names.append(str(panel.call("state_text", "load")))
		_check(names.find("火攻") < 0 and names[0] == "专力装填" and names[1] == "均装",
			"三 %s：轮换两档（均装 ⇄ 专力装填，%s）" % [cfg[0], " → ".join(names)])
		_check(bat == null or not bool((bat as Object).get("fire_mode")),
			"三 %s：fire_mode 仍假（battery %s）" % [cfg[0], str(bat)])
		var got_tip := ""
		var rows: Dictionary = panel.get("_rows")
		if rows.has("load"):
			got_tip = str(((rows["load"] as Dictionary)["chip"] as Button).tooltip_text)
		_check(got_tip == want_tip and got_tip.find("火攻") < 0,
			"三 %s：装填侧重签提示与 w53-2 账逐字一致（%s）" % [cfg[0], "原文" if got_tip == want_tip else got_tip])
		await _close(wm)
	sw.call("reset")


## 第四节 _load_orders：面板在取两令；不在回中性
func _sec_load_orders() -> void:
	var orders_scr: GDScript = load("res://scripts/ui/CombatOrdersPanel.gd")
	var has_fn := orders_scr != null and orders_scr.has_method("_load_orders")
	_check(has_fn, "四① Ship 配弹走的静态口 _load_orders 在")
	if not has_fn:
		return
	var orphan := Node2D.new()
	root.add_child(orphan)
	var bo: Dictionary = orders_scr.call("_load_orders", orphan)
	_check(not bool(bo.get("fire_mode", true)) and str(bo.get("emphasis", "")) == "balanced",
		"四② 没挂面板：_load_orders 回中性（fire_mode=false、emphasis=balanced，得 %s）" % str(bo))
	orphan.queue_free()


class _ScriptErrLog extends Logger:
	var lines: Array = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			lines.append("%s:%d %s" % [file, line, rationale if rationale != "" else code])

	func _log_message(_message: String, _error: bool) -> void:
		pass
