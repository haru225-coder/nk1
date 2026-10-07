extends SceneTree
## lane w53-p3b「火攻回到轮换」胜率对拍（按 wave53-p3-COMMON §胜率）：开关开 vs 关各 8 场、
## 同 8 个种子、300 秒窗口，敌将 live、士气裁决可早收。对手敌船此时未挂 FloodFire（p3a 未入基线），
## 火攻烧的是「防火面 = wave53 开工前的敌船」——写明测的基线。
## 打法：真起 WorldMap 海战场（fu_ship_medium 60 人对 pirate_boat ×2），玩家 J 键按号抽射，
## 2 号切到火攻 / 两档轮换；限时两散 / 士气裁决 / 沉没都收。逐场记 outcome。
## 用法：godot --headless --path . -s res://tools/qa_w53_p3b_winrate_probe.gd；判词末行 WINRATE …（不入一键，编 EXEMPT）。

const ENEMY := [{"type": "pirate_boat", "count": 2}]
const WINDOW_S := 300.0
const SEEDS := [5301, 5302, 5303, 5304, 5305, 5306, 5307, 5308]

var _report := []
var _wins_on := 0
var _wins_off := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== w53-p3b 胜率对拍：同 8 种子 × 两态（敌将 live、士气裁决早收、300s 窗口）")
	for cfg in [["on", true], ["off", false]]:
		var wins := 0
		for sd in SEEDS:
			var r: Dictionary = await _arena(sd, bool(cfg[1]))
			_report.append("%s seed=%d → %s（%.0fs）" % [cfg[0], sd, str(r.get("outcome", "")), float(r.get("t", 0.0))])
			if str(r.get("outcome")) == "win":
				wins += 1
		if bool(cfg[1]):
			_wins_on = wins
		else:
			_wins_off = wins
		print("  -- %s: %d / %d" % [cfg[0], wins, SEEDS.size()])
	for line in _report:
		print("   " + line)
	print("WINRATE p3b fire_attack_load：on %d / %d，off %d / %d，差 %.1f 个百分点（基线：敌船未挂 FloodFire，火攻烧的是开工前的敌船）" % [
		_wins_on, SEEDS.size(), _wins_off, SEEDS.size(), float(_wins_on - _wins_off) / float(SEEDS.size()) * 100.0])
	quit(0)


## 一场：同种子开战场。开关两态只差 fire_attack_load；玩家 _fire_broadside 由「2 号令（切火攻）+ J 键」驱动，
## 其余放权敌将。返回 {"outcome", "t"}
func _arena(sd: int, fire_on: bool) -> Dictionary:
	seed(sd)
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 70)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": ENEMY, "sea_name": "泉州外海", "source": {"scene": "qa_w53_p3b_win"}})
	var sw: GDScript = load("res://scripts/combat/CombatSwitches.gd")
	sw.call("set_on", "fire_attack_load", fire_on)
	sw.call("set_on", "player_gunnery", true)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	var own: Node = wm.get("ship")
	# 开局切到火攻（开关开时第三档）/ 只切到专力装填（关开关；两档轮换）
	if panel != null:
		panel.call("issue", "load")
		panel.call("issue", "load")
	var rec := {"outcome": "", "t": 0.0}
	if wm.has_signal("battle_finished"):
		wm.battle_finished.connect(func(o: String, _dd: Dictionary) -> void: rec["outcome"] = o)
	# 轮询走物理帧（固定步长）：每拍 = 1/60 秒游戏时间，一晃一拍，比 create_timer 的墙钟跑快几十倍。
	# 驾驶一拍一令（转向转舷用 dt=1/60 的量围）。战斗经过秒按 WorldMap._battle_elapsed_s 实读
	var held := 0.0
	var last_elapsed := -1.0
	var stuck := 0
	while held < WINDOW_S and str(rec["outcome"]) == "":
		for _i in 30:  # 一拍 0.5 秒游戏时间
			await physics_frame
			if is_instance_valid(wm):
				var el := float(wm.get("_battle_elapsed_s"))
				if el > last_elapsed:
					last_elapsed = el
					held = el
					stuck = 0
				else:
					stuck += 1
			if str(rec["outcome"]) != "" or held >= WINDOW_S or stuck > 6000:
				break
		if stuck > 6000:
			rec["outcome"] = "hang"
			break
		# 玩家驾驶：追着最近敌船转舷放箭；冷却够就 J
		if is_instance_valid(own) and float(own.get("fire_cooldown")) <= 0.0:
			var foe: Node2D = null
			var best := INF
			for c in wm.get_children():
				if String(c.name).begins_with("PirateShip") and float(c.get("hull_hp")) > 0.0:
					var dd := (c as Node2D).global_position.distance_squared_to((own as Node2D).global_position)
					if dd < best:
						best = dd
						foe = c
			if foe != null:
				var to: Vector2 = foe.global_position - (own as Node2D).global_position
				var sb := Vector2.RIGHT.rotated((own as Node2D).global_rotation)
				var side := 1 if to.dot(sb) >= 0.0 else -1
				var off := absf(sb.angle_to(to))
				if off < deg_to_rad(55.0):
					own.call("_fire_broadside", side)
				else:
					# 把最近敌船转进舷弧
					var want := to.angle() - (Vector2.RIGHT.angle() if side > 0 else Vector2.LEFT.angle())
					(own as Node2D).rotation = want
	if str(rec["outcome"]) == "":
		rec["outcome"] = "flee"  # 300s 限时两散（combat12 读表；截窗按两散收）
	rec["t"] = held
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	sw.call("reset")
	return rec
