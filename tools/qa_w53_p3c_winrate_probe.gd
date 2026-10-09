extends SceneTree
## lane-w53-p3c 三期开关胜率工具（headless，经 glock 跑）——p3b / p3c 两份旧工具合一份（p3b 那份删）：
##   二期「手感对比」口径的骨架（同种子表、300 秒窗口到限时两散、敌将 live、士气裁决可早收），
##   加 p3b 的物理帧泵 + 逐帧玩家驾驶（追最近敌船转舷、进 55° 舷弧放舷齐射——逐帧下锚与墙钟
##   解耦，同种子复跑才对得上；按 p3b 原拍 0.5 秒一锚实测负载大时漂 win→lose），与同种子逐场
##   对拍（on 跑完复跑一遍自比，漂移即红），没有玩家动手 24 种子根本打不完。
##
## 用法：godot --headless --path . -s res://tools/qa_w53_p3c_winrate_probe.gd -- \
##         --n=8 --seeds=11,23,37,41,53,67,79,83 --on=flood,fire | --off --ship=fu_ship_medium --enemy=pirate_boat --count=2
##   --on=LIST   逗号分隔单开几项：flood=enemy_flood_fire、fire=fire_attack_load（裸 --on 两个全开）
##   --off       三期开关全关（与 --on 互斥；都缺 = 全开）；--on 与 --off 都给，后面到的盖前面的
##   其余缺省：n=8（按 seeds 个数取小）、二期 8 种子、福船 60 人 vs 快船 ×2、morale 60、玩家驾驶
##   开局落令「装填轮换两令」（进火攻档；--orders= 换令表、--hands-off 手离舵对照）
##
## 对阵（--ship + --enemy×--count + --power/--ppower/--crew/--morale/--orders/--hands-off 自定义）：
##   现有对照  fu_ship_medium 60 人 vs pirate_boat ×2（同二期 lane 量的那一仗）
##   逆风对照  fu_ship_medium 60 人 vs sea_falcon ×1、power 600 / player_power 300（敌血翻倍、水手上限 100，
##             比快船 ×2 硬得多——--compare 的第二阵；两段对阵的 WINRATE 行分开打）
##   --compare 自动跑「现有对照 + 逆风对照」两段；手动攒对阵就把 --enemy 写 sea_falcon 加 --power=600
##
## 场子照 qa_w53_2_combat_probe 的 _battle 复刻（真 WorldMap 海战场 + pending_battle，泉州外海）；
## 敌将 live（不冻敌船 fire_timer、不接管旗舰航向），士气簿裁决到即早收（同二期口径）。
## 随机源注射（sea_seed 私有流 + 敌船 _rng 与 EnemyFloodFire 簿 rng / 我船 DamageModel rng /
## 士气挂件 rng / 号令面板 _rng 按种子起）之后，每种开关配置各跑满 N 场无 hang、同种子复跑
## 逐场结论一致（bit-exact 到 overcome+胜负）自检过；WorldMap._ready 的 randomize() 是全局播种
## （seed(sd) 之后又撒一次主随机流，注射钉不住）、MeleeResolve 逐合 / gm / Calendar 仍走 OS 时流，
## 若跑出漂移 SELFCHECK 会红——红了重跑或换种子。
## 判词：末行 WINRATE cfg=a/N …（逐配置一行）恒打；自检不过退 1。

const TAG := "QA_W53_P3C_WINRATE"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Panel := preload("res://scripts/ui/CombatOrdersPanel.gd")
const KEY_A := "enemy_flood_fire"
const KEY_B := "fire_attack_load"
const LIMIT_S := 300.0
## 一档的墙钟上限：同种子复跑 / 逆风阵拖满窗是常态，给两份余量；超了记 hang 判红不等死
const WALL_LIMIT_S := LIMIT_S * 2.0
## 敌船数量上限（同一场跑出 4 艘以上多半是 walrus 攒出来的）与对阵缺省
const MAX_ENEMIES := 4

## 两种对阵（--compare 的两段，也可 --matchup=pirates|falcon 单点一段）
const MATCHUP_PIRATES := {"label": "现有对照：福船60人对快船×2", "power": 300.0, "ppower": 300.0,
	"enemy": [{"type": "pirate_boat", "count": 2}]}
const MATCHUP_FALCON := {"label": "逆风对照：福船60人对元军海鹘×1（power 600 敌血翻倍）", "power": 600.0, "ppower": 300.0,
	"enemy": [{"type": "sea_falcon", "count": 1}]}

## 开关配置：--on/--off 攒；key → 中文名只给打印用
const CFG_NAMES := {KEY_A: "flood", KEY_B: "fire"}


func _init() -> void:
	call_deferred("_run")


func _args() -> Dictionary:
	var out := {"n": 8, "seeds": [11, 23, 37, 41, 53, 67, 79, 83], "cfgs": [], "matchups": [],
		"ship": "fu_ship_medium", "crew": 60, "morale": 60, "drive": true, "orders": ["load", "load"]}
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
		elif a == "--compare":
			out["matchups"] = ["pirates", "falcon"]
		elif a.begins_with("--matchup="):
			var ms: Array = out["matchups"]
			for t in str(a.trim_prefix("--matchup=")).split(",", false):
				if not ms.has(t):
					ms.append(t)
		elif a.begins_with("--ship="):
			out["ship"] = str(a.trim_prefix("--ship="))
		elif a.begins_with("--enemy="):
			if not out.has("_enemy_hand"):
				out["_enemy_hand"] = []
			(out["_enemy_hand"] as Array).append(str(a.trim_prefix("--enemy=")))
		elif a.begins_with("--count="):
			out["_count_wide"] = clampi(int(a.trim_prefix("--count=")), 1, MAX_ENEMIES)
		elif a.begins_with("--power="):
			out["_power_hand"] = maxf(1.0, float(a.trim_prefix("--power=")))
		elif a.begins_with("--ppower="):
			out["_ppower_hand"] = maxf(1.0, float(a.trim_prefix("--ppower=")))
		elif a.begins_with("--crew="):
			out["crew"] = maxi(1, int(a.trim_prefix("--crew=")))
		elif a.begins_with("--morale="):
			out["morale"] = clampi(int(a.trim_prefix("--morale=")), 1, 100)
		elif a == "--hands-off":
			out["drive"] = false
		elif a.begins_with("--orders="):
			out["orders"] = Array(str(a.trim_prefix("--orders=")).split(",", false))
		elif a == "--off":
			out["cfgs"].clear()
			out["cfgs"].append({"id": "off", "keys": {}})
		elif a.begins_with("--on"):
			var keys := {}
			if a.begins_with("--on="):
				for t in str(a.trim_prefix("--on=")).split(",", false):
					match t:
						"flood", KEY_A:
							keys[KEY_A] = true
						"fire", KEY_B:
							keys[KEY_B] = true
			else:
				keys = {KEY_A: true, KEY_B: true}
			if (out["cfgs"] as Array).size() == 1 and String((out["cfgs"] as Array)[0].get("id", "")) == "off":
				out["cfgs"].clear()
			out["cfgs"].append({"id": _cfg_id(keys), "keys": keys})
	# 缺省一段一档：--compare 起手前、--on/--off 都没给，跑全开 × 现有对照（同二期口径的读数面）
	if (out["cfgs"] as Array).is_empty():
		out["cfgs"].append({"id": "on", "keys": {KEY_A: true, KEY_B: true}})
	if (out["matchups"] as Array).is_empty():
		if out.has("_enemy_hand"):
			out["matchups"] = [_hand_matchup(out)]
		else:
			out["matchups"] = ["pirates"]
	out["n"] = mini(int(out["n"]), (out["seeds"] as Array).size())
	return out


## 手动对阵（--enemy 攒的）：type 逐项展开 count；power 缺省沿用现有对照 300/300
static func _hand_matchup(a: Dictionary) -> Dictionary:
	var types: Array = a.get("_enemy_hand", [])
	var wide: int = int(a.get("_count_wide", 1))
	var foes: Array = []
	for t in types:
		var left := MAX_ENEMIES
		for e in foes:
			left -= int((e as Dictionary).get("count", 1))
		var n := clampi(wide, 1, maxi(1, left))
		if n > 0:
			foes.append({"type": String(t), "count": n})
	return {"label": "手动对阵：%s %d人对 %s" % [String(a["ship"]), int(a["crew"]), str(foes)],
		"power": float(a.get("_power_hand", 300.0)), "ppower": float(a.get("_ppower_hand", 300.0)),
		"enemy": foes}


## 配置 id：全开 = on、全关 = off、单开 = on-flood / on-fire（打印与 WINRATE 行用）
static func _cfg_id(keys: Dictionary) -> String:
	if bool(keys.get(KEY_A, false)) and bool(keys.get(KEY_B, false)):
		return "on"
	if not bool(keys.get(KEY_A, false)) and not bool(keys.get(KEY_B, false)):
		return "off"
	var bits: Array = []
	for k in [KEY_A, KEY_B]:
		if bool(keys.get(k, false)):
			bits.append(String(CFG_NAMES[k]))
	return "on-" + "-".join(bits)


## 档位套路上开关：reset 后按 keys 置（缺键 = 关）
static func _apply_cfg(keys: Dictionary) -> void:
	_Switches.reset()
	_Switches.set_on(KEY_A, bool(keys.get(KEY_A, false)))
	_Switches.set_on(KEY_B, bool(keys.get(KEY_B, false)))


## 一场：seed 后真起海战，玩家驾驶到收战 / 玩家旗舰拆 / 墙钟上界。
## 返回 {"overcome", "win", "wall_s", "tag"}
##   overcome = win / lose / flee（battle_finished 首参；超时未收 = "hang"）
##   win      = overcome=win / 士气敌降敌破敌遁 / 击沉受降焚沉 ≥ 1（fled 半赏不算胜）
func _battle_one(fleet: Node, gm: Node, sd: int, mu: Dictionary, keys: Dictionary, drive: bool,
		orders: Array, seed_tag: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	# 钉死双随机源：
	# ① seed(sd)：全局流用于 WorldMap._spawn_enemy（敌船角度 / 距 / 水手 / 士气的 randf_range）。
	# ② pending_battle.sea_seed：SeaState 用私有 _rng 不吃全局流——不注射同 sd 也复现不出
	#   （b048e297 实测同 seed 11 两场结论漂）。sea_seed 用 sd 错段避免与全局流撞（sd + 7_000_000）。
	# 手动种子段 seed_tag（外部加段起一列独立随机，不撞种子表；本工具恒传 0）
	var shift := int(seed_tag) * 1_000_003
	var ship_id := String(mu.get("ship", "fu_ship_medium"))
	var d: Dictionary = fleet.call("ship_def", ship_id)
	var dur := float(d.get("durability", 300))
	fleet.set("ships", [{"type": ship_id, "name": "试船", "crew": int(mu.get("crew", 60)),
		"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": dur, "max_durability": dur}])
	fleet.set("morale", int(mu.get("morale", 60)))
	seed(sd + shift)
	gm.set("pending_battle", {"battle": true, "power": float(mu.get("power", 300.0)),
		"player_power": float(mu.get("ppower", 300.0)),
		"enemy": (mu.get("enemy", MATCHUP_PIRATES["enemy"]) as Array).duplicate(true), "sea_name": "泉州外海",
		"sea_seed": sd + shift + 7_000_000, "source": {"scene": "qa_w53_p3c"}})
	_apply_cfg(keys)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, data: Dictionary) -> void: rec.append([o, data.duplicate()]))
	# 注射所有未 seed 的私有 rng（运行时节点成员，不改产品脚本）——要不然同 seed 两场照样漂：
	#   PirateShip._rng        敌炮散布 / 命中手 / 跳帮判定（_spawn_enemy 才能读到的成员）
	#   PirateShip.flood_fire  EnemyFloodFire 簿的 rng（时级命中开漏开火的掷点；p3a 开关开才有簿）
	#   Ship.damage_model.rng  命中落点 / 舱位 / 左侧右舷
	#   CombatMorale 挂件 rng   我方溃逃甩脱 roll
	# SeaState 那一支已用 pending_battle.sea_seed 钉（WorldMap._setup_sea 转给它）。
	var foes := wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())
	var foe_rng_idx := 0
	for f in foes:
		var r := RandomNumberGenerator.new()
		r.seed = sd + shift + 3_000_000 + foe_rng_idx * 13_579
		foe_rng_idx += 1
		f.set("_rng", r)
		# 敌船水火簿（EnemyFloodFire）：p_seed=0 时自家 rng.randomize() 走 OS 时流——
		# 漏不漏、漏哪舷都掷它，不钉同种子两跑漂（fire/flood 路径直接关系到敌船几时才沉）
		var ffb = f.get("flood_fire")
		if ffb is Object and is_instance_valid(ffb):
			var fr := RandomNumberGenerator.new()
			fr.seed = sd + shift + 8_000_000 + (foe_rng_idx - 1) * 13_579
			(ffb as Object).set("rng", fr)
	var ship_node = wm.get("ship")
	if ship_node != null:
		var dm = ship_node.call("get_damage_model") if ship_node.has_method("get_damage_model") else null
		if dm != null:
			var dr := RandomNumberGenerator.new()
			dr.seed = sd + shift + 5_000_000
			dm.set("rng", dr)
	var morale_hook = wm.get("_morale")
	if morale_hook != null:
		var mr := RandomNumberGenerator.new()
		mr.seed = sd + shift + 6_000_000
		morale_hook.set("rng", mr)
	# 士气裁决可早收（挂件 verdict 信号接到 _battle_exit，同二期）；玩家驾驶按 orders 开局落令
	var own_freed := [false]
	var own: Node = wm.get("ship")
	if own != null:
		own.tree_exited.connect(func() -> void: own_freed[0] = true)
	for _i in 2:
		await process_frame
	var panel: Node = null
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders"):
			panel = n
	if drive and panel != null:
		# 号令面板 _init 里 _rng.randomize() 走 OS 时流（白刃过场的甩脱骰掷它）；钉回再落令
		if panel.get("_rng") is RandomNumberGenerator:
			var prng := RandomNumberGenerator.new()
			prng.seed = sd + shift + 9_000_000
			panel.set("_rng", prng)
		for o in orders:
			panel.call("issue", String(o))
	# 物理帧泵（p3b 的跑法改到逐帧）：每一物理帧驾驶一拍（转舷 / 冷却够放舷齐射），
	# 30 帧一圈回看战况收没收——逐帧下锚点行为与墙钟解耦，同种子复跑才对得上（按 0.5 秒
	# 一拍下锚会把「哪一拍放的」随负载挪，seed 1222 实测漂出 win→lose）。
	var held := 0.0
	var last_elapsed := -1.0
	var stuck := 0
	var wall := 0.0
	var tick := 0
	while rec.is_empty() and not own_freed[0]:
		for _i in 30:
			await physics_frame
			tick += 1
			if not is_instance_valid(wm):
				break
			# 玩家驾驶（逐帧）：追着最近敌船转舷放箭；冷却够、敌进 55° 舷弧就放
			if drive and own != null and is_instance_valid(own) and float(own.get("fire_cooldown")) <= 0.0:
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
						# 把最近敌船转进舷弧（直接改角——脚本驾驶不走输入，产品里玩家靠 WASD 转头）
						var want := to.angle() - (Vector2.RIGHT.angle() if side > 0 else Vector2.LEFT.angle())
						(own as Node2D).rotation = want
			var el := float(wm.get("_battle_elapsed_s"))
			if el > last_elapsed:
				last_elapsed = el
				held = el
				stuck = 0
			else:
				stuck += 1
			if not rec.is_empty() or own_freed[0] or held >= LIMIT_S or stuck > 6000:
				break
		for _i in 30:
			await physics_frame
			if not is_instance_valid(wm):
				break
			var el := float(wm.get("_battle_elapsed_s"))
			if el > last_elapsed:
				last_elapsed = el
				held = el
				stuck = 0
			else:
				stuck += 1
			if not rec.is_empty() or own_freed[0] or held >= LIMIT_S or stuck > 6000:
				break
		wall = float(Time.get_ticks_msec() - t0) / 1000.0
		if not is_instance_valid(wm) or not rec.is_empty() or own_freed[0] \
				or held >= LIMIT_S or stuck > 6000 or wall > WALL_LIMIT_S:
			break
	var out := {"overcome": "hang", "win": false, "wall_s": wall, "tag": "", "held_s": held}
	if not rec.is_empty():
		out["overcome"] = str(rec[0][0])
		var data: Dictionary = rec[0][1]
		var verdict := str(data.get("morale_verdict", ""))
		# 玩家胜 = overcome=win / 击沉 ≥ 1 艘 / 焚沉 ≥ 1 艘 / 夺船 / 敌 降幡或崩溃或全遁（士气簿已下场裁过本队胜）：
		# 「敌遁半赏」是 SeaChart 的经济注，不是判定框架的裁判口径（brief 口径按 overcome/win 不按 spoil）。
		var fates: Array = data.get("fates", [])
		var sunk_n := 0
		var struck_n := 0
		for f in fates:
			if str(f.get("fate", "")) == "sunk":
				sunk_n += int(f.get("count", 1))
			elif str(f.get("fate", "")) == "struck":
				struck_n += int(f.get("count", 1))
		out["win"] = str(rec[0][0]) == "win" or verdict in ["enemy_struck", "enemy_broken", "enemy_fled"] \
			or bool(data.get("boarded", false)) \
			or sunk_n + struck_n + int(data.get("burned", 0)) > 0
		out["tag"] = verdict if verdict != "" else str(data.get("fates", []))
	if is_instance_valid(wm):
		wm.set("resolved", true)  # 拆布景不再发 battle_finished
		wm.queue_free()
	fleet.set("morale", int(mu.get("morale", 60)))
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
	var fails := 0
	var runs: Dictionary = {}  # cfg id → 各 seed 的 {"overcome","win"} 签名表（复跑自比用）
	for mid in a["matchups"]:
		var mu: Dictionary
		match String(mid):
			"pirates":
				mu = MATCHUP_PIRATES.duplicate(true)
			"falcon":
				mu = MATCHUP_FALCON.duplicate(true)
			_:
				mu = (mid as Dictionary).duplicate(true) if mid is Dictionary else MATCHUP_PIRATES.duplicate(true)
		mu["ship"] = String(a["ship"])
		mu["crew"] = int(a["crew"])
		mu["morale"] = int(a["morale"])
		print("== 对阵：%s（我方 %s %d人 morale %d，power %.0f/%.0f，%s）" % [
			String(mu.get("label", mid)), String(mu["ship"]), int(mu["crew"]), int(mu["morale"]),
			float(mu.get("power", 300.0)), float(mu.get("ppower", 300.0)),
			"玩家驾驶" if bool(a["drive"]) else "手离舵"])
		for cfg in a["cfgs"]:
			var cid := String((cfg as Dictionary)["id"])
			var keys: Dictionary = (cfg as Dictionary)["keys"]
			var rows: Array = []
			for i in n:
				var r: Dictionary = await _battle_one(fleet, gm, int(seeds[i]), mu, keys,
					bool(a["drive"]), a["orders"], 0)
				rows.append(r)
				print("%s 第 %d/%d 场 种子 %d：%s %s（%.0f 秒墙钟 / %.0f 秒战斗）%s" % [
					cid, i + 1, n, int(seeds[i]), str(r["overcome"]),
					"胜" if bool(r["win"]) else "负",
					float(r["wall_s"]), float(r["held_s"]),
					("・" + str(r["tag"])) if str(r["tag"]) != "" else ""])
			var won := 0
			var hangs := 0
			var sigs: Array = []
			for i in rows.size():
				var r: Dictionary = rows[i]
				if bool(r["win"]):
					won += 1
				if str(r["overcome"]) == "hang":
					hangs += 1
				sigs.append([int(seeds[i]), str(r["overcome"]), bool(r["win"])])
			print("%s on=%d/%d 收 %d 场（hang %d）" % [cid, won, n, n, hangs])
			if hangs > 0:
				fails += hangs
			runs[cid] = sigs
			# ── 同种子复跑自比（bit-exact 判决）：每个配置鼻子下跑第二遍，逐场 (overcome, win) 须一致 ──
			var again: Array = []
			for i in n:
				var r2: Dictionary = await _battle_one(fleet, gm, int(seeds[i]), mu, keys,
					bool(a["drive"]), a["orders"], 0)
				again.append([int(seeds[i]), str(r2["overcome"]), bool(r2["win"])])
			var drift := 0
			for i in n:
				if str(sigs[i][1]) != str(again[i][1]) or bool(sigs[i][2]) != bool(again[i][2]):
					drift += 1
					print("  漂移 %s 种子 %d：%s/%s → %s/%s" % [cid, int(seeds[i]),
						str(sigs[i][1]), "胜" if bool(sigs[i][2]) else "负",
						str(again[i][1]), "胜" if bool(again[i][2]) else "负"])
			if drift > 0:
				fails += drift
			# 逐配置末行（多段对阵时每段都打——主控按行收数）
			var sd_names := PackedStringArray()
			for i in n:
				sd_names.append(str(int(seeds[i])))
			print("WINRATE %s@%s=%d/%d seeds=%s replay-drift=%d" % [
				cid, String(mid), won, n, ",".join(sd_names), drift])
	# 还原战况与开关
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	_Switches.reset()
	await process_frame
	if fails == 0:
		print("SELFCHECK %s OK（各档跑满 %d 场、无 hang、同种子复跑逐场一致）" % [TAG, n])
		quit(0)
		return
	print("SELFCHECK %s FAIL（hang/漂移 共 %d 处）" % [TAG, fails])
	quit(1)
