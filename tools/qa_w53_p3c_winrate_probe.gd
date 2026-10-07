extends SceneTree
## lane-w53-p3c 三期开关胜率对比工具（headless，经 glock 跑）：二期「手感对比」同一口径——
## 同 8 个种子、300 秒窗口（到限时两散）、敌将 live、士气裁决可早收，跑「三期开关全开」
## （enemy_flood_fire、fire_attack_load）与「三期开关全关」各 N 场，每场打印收场与胜负，
## 末行 WINRATE on=a/N off=b/N diff=±x.x pp。
##
## 场子照 qa_w53_2_combat_probe 的 _battle 复刻（真 WorldMap 海战场 + pending_battle，泉州外海、
## 福船 60 人对两艘快船——同二期 lane 量的那一仗）；敌将 live（不冻敌船 fire_timer、不接管旗舰航向），
## 士气簿裁决到即早收（同二期口径）。每场 seed(sd) 后开战，WorldMap 自身的 randf 序按种子走。
##
## p3a（敌船 FloodFire 实战接线）没落地前，两键没有任何消费者：enemy_flood_fire 在敌船侧无人读——
## 同键值跑两遍 hands-off 场，on/off 各行须逐字相同。这本身就是工具的自检：哪天 on/off 不一致，
## 要么是 p3a 已接线（自检完成史命，工具留给主控在三期全落地后量差），要么是数又被谁碰了。
## （p3a 落地后敌船挂 flood_fire_state()：我方的矢石照样能打它进水失火，开关关时敌船不灾。）
##
## 用法：godot --headless --path . -s res://tools/qa_w53_p3c_winrate_probe.gd -- --n=8 --seeds=11,23,37,41,53,67,79,83
##   --n 场数（缺省 8，与 seeds 个数不齐时按小者跑）；--seeds 逗号分隔种子表（缺省同二期 8 种子）。
## 判词：末行 WINRATE … 恒打；自检（on/off 未接线须一致）不过退 1。

const TAG := "QA_W53_P3C_WINRATE"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const KEY_A := "enemy_flood_fire"
const KEY_B := "fire_attack_load"
const LIMIT_S := 300.0
const POLL_MS := 500


func _init() -> void:
	call_deferred("_run")


func _args() -> Dictionary:
	var out := {"n": 8, "seeds": [11, 23, 37, 41, 53, 67, 79, 83]}
	var rest := OS.get_cmdline_user_args()
	for a in rest:
		if a.begins_with("--n="):
			out["n"] = maxi(1, int(a.trim_prefix("--n=")))
		elif a.begins_with("--seeds="):
			var lst: Array = []
			for t in str(a.trim_prefix("--seeds=")).split(",", false):
				lst.append(int(t))
			if not lst.is_empty():
				out["seeds"] = lst
	out["n"] = mini(int(out["n"]), (out["seeds"] as Array).size())
	return out


## 一场：seed 后真起海战，hands-off 等到收战 / 玩家旗舰拆 / 墙钟与游戏时长双上界；
## 返回 {"overcome", "win", "wall_s", "tag"}
##   overcome = win / lose / flee（battle_finished 首参；超时未收 = "hang"）
##   win      = strike / sunk / burned / boarded / 士气敌降敌破敌遁（fled 半赏不算胜）
func _battle_one(fleet: Node, gm: Node, sd: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	# 钉死双随机源：
	# ① seed(sd)：全局流用于 WorldMap._spawn_enemy（敌船角度 / 距 / 水手 / 士气的 randf_range）。
	# ② pending_battle.sea_seed：SeaState 用 _rng 私有 RandomNumberGenerator，rng_seed=-1 时不吃
	#    seed() 那个全局流——不注射它 8 个 sd 也复现不出（本 lane 实测同 seed 11 两场结论漂）。注射它，
	#    同一 sea_seed 跑 on / off 同一场对得上。sea_seed 用 sd 不同段避免与全局流撞（sd + 7_000_000）。
	var d: Dictionary = fleet.call("ship_def", "fu_ship_medium")
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", 60)
	seed(sd)
	gm.set("pending_battle", {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": [{"type": "pirate_boat", "count": 2}], "sea_name": "泉州外海",
		"sea_seed": sd + 7_000_000, "source": {"scene": "qa_w53_p3c"}})
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, data: Dictionary) -> void: rec.append([o, data.duplicate()]))
	# 士气裁决可早收（挂件 verdict 信号接到 _battle_exit，同二期）；双手离舵，玩家船不打一炮
	var own_freed := [false]
	var own: Node = wm.get("ship")
	if own != null:
		own.tree_exited.connect(func() -> void: own_freed[0] = true)
	for _i in 2:
		await process_frame
	var wall := 0.0
	var hangs := 0
	while rec.is_empty() and not own_freed[0]:
		await create_timer(float(POLL_MS) / 1000.0).timeout
		wall = float(Time.get_ticks_msec() - t0) / 1000.0
		if wall > LIMIT_S + 60.0 and float(wm.get("_battle_elapsed_s")) < 1.0:
			hangs += 1  # 时限推进卡住：记一档但不死等
		if wall > LIMIT_S + 180.0:
			break
		if not is_instance_valid(wm):
			break
	var out := {"overcome": "hang", "win": false, "wall_s": wall, "tag": ""}
	if not rec.is_empty():
		out["overcome"] = str(rec[0][0])
		var data: Dictionary = rec[0][1]
		var verdict := str(data.get("morale_verdict", ""))
		# 玩家胜 = 击沉 ≥ 1 艘 / 烧沉 ≥ 1 艘 / 夺船 ≥ 1 艘 / 敌全 投降/崩溃 收兵。
		# 敌「遁走」（fled，包括限时两散甩脱）属半赏不算玩家胜。
		var fates: Array = data.get("fates", [])
		var sunk_n := 0
		var struck_n := 0
		for f in fates:
			if str(f.get("fate", "")) == "sunk":
				sunk_n += int(f.get("count", 1))
			elif str(f.get("fate", "")) == "struck":
				struck_n += int(f.get("count", 1))
		out["win"] = verdict in ["enemy_struck", "enemy_broken"] \
			or bool(data.get("boarded", false)) \
			or sunk_n + struck_n + int(data.get("burned", 0)) > 0
		out["tag"] = verdict if verdict != "" else str(data.get("fates", []))
	if is_instance_valid(wm):
		wm.set("resolved", true)  # 拆布景不再发 battle_finished
		wm.queue_free()
	fleet.set("morale", 60)
	await process_frame
	return out


func _run() -> void:
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var gs: Node = root.get_node("GameState")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true), "martial": gs.get("martial"),
		"money": gs.get("money"), "fame": gs.get("fame")}
	var a := _args()
	var n: int = a["n"]
	var seeds: Array = a["seeds"]
	var rows: Dictionary = {"on": [], "off": []}
	for mode in ["on", "off"]:
		_Switches.reset()
		_Switches.set_on(KEY_A, mode == "on")
		_Switches.set_on(KEY_B, mode == "on")
		for i in n:
			var r := await _battle_one(fleet, gm, int(seeds[i]))
			rows[mode].append(r)
			print("%s 第 %d/%d 场 种子 %d：%s %s（%.0f 秒墙钟）%s" % [
				mode, i + 1, n, int(seeds[i]), str(r["overcome"]),
				"胜" if bool(r["win"]) else "负",
				float(r["wall_s"]),
				("・" + str(r["tag"])) if str(r["tag"]) != "" else ""])
	# 还原战况
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	_Switches.reset()
	await process_frame
	var won := func(mode: String) -> int:
		var c := 0
		for r in rows[mode]:
			if bool(r["win"]):
				c += 1
		return c
	var a_won: int = won.call("on")
	var b_won: int = won.call("off")
	var diff := float(a_won - b_won) / float(n) * 100.0
	print("WINRATE on=%d/%d off=%d/%d diff=%+.1f pp" % [a_won, n, b_won, n, diff])
	# 自检：两键还无人接线（p3a 未落地）时 on/off 各行须逐字相同
	var alike := true
	for i in n:
		var ro: Dictionary = rows["on"][i]
		var rf: Dictionary = rows["off"][i]
		if str(ro["overcome"]) != str(rf["overcome"]) or bool(ro["win"]) != bool(rf["win"]):
			alike = false
			break
	if alike:
		print("SELFCHECK unwired-identical OK（两键未接线，on/off 各行逐字相同——这本身是工具的自检）")
		quit(0)
		return
	print("SELFCHECK unwired-identical FAIL（on/off 不一致：p3a 已接线，或有人碰了两键的消费者）")
	quit(1)
