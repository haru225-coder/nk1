extends SceneTree
## lane-w53-p3c 三期开关胜率工具（headless，经 glock 跑）——p3b / p3c 两份旧工具合一份（p3b 那份删）：
##   二期「手感对比」口径的骨架（同种子表、300 秒窗口到限时两散、敌将 live、士气裁决可早收），
##   加 p3b 的物理帧泵 + 逐帧玩家驾驶（追最近敌船转舷、进 55° 舷弧放舷齐射——逐帧下锚与墙钟
##   解耦，同种子复跑才对得上；按 p3b 原拍 0.5 秒一锚实测负载大时漂 win→lose），与同种子逐场
##   对拍（on 跑完复跑一遍自比，漂移即红），没有玩家动手 24 种子根本打不完。
##
## 用法：godot --headless --fixed-fps 60 --path . -s res://tools/qa_w53_p3c_winrate_probe.gd -- \
##         --n=8 --seeds=11,23,37,41,53,67,79,83 --on=flood,fire | --off --ship=fu_ship_medium --enemy=pirate_boat --count=2
##   --on=LIST   逗号分隔单开几项：flood=enemy_flood_fire、fire=fire_attack_load（裸 --on 两个全开）
##   --off       三期开关全关（与 --on 互斥；都缺 = 全开）；--on 与 --off 都给，后面到的盖前面的
##   其余缺省：n=8（按 seeds 个数取小）、二期 8 种子、福船 60 人 vs 快船 ×2、morale 60、玩家驾驶
##   开局落令「装填轮换两令」（进火攻档；--orders= 换令表、--hands-off 手离舵对照）
##
## 对阵（--ship + --enemy×--count + --power/--ppower/--crew/--morale/--orders/--hands-off 自定义）：
##   --enemy=TYPE[:N[:SPRITE]]  一条一种船：N 是这一种几艘（缺省用 --count），SPRITE 照 pending_battle.enemy 的 sprite
##             （yuan_patrol = 元军哨船敌将档案）；同一种分两条写会各自从 0 度起摆、挤在一边，和游戏里一条 count=2 摆法不同
##   现有对照  fu_ship_medium 60 人 vs pirate_boat ×2（同二期 lane 量的那一仗）
##   逆风对照  fu_ship_medium 60 人 vs sea_falcon ×1、power 600 / player_power 300（敌血翻倍、水手上限 100，
##             比快船 ×2 硬得多——--compare 的第二阵；两段对阵的 WINRATE 行分开打）
##   --compare 自动跑「现有对照 + 逆风对照」两段；手动攒对阵就把 --enemy 写 sea_falcon 加 --power=600
##
## 场子照 qa_w53_2_combat_probe 的 _battle 复刻（真 WorldMap 海战场 + pending_battle，泉州外海）；
## 敌将 live（不冻敌船 fire_timer、不接管旗舰航向），士气簿裁决到即早收（同二期口径）。
## 随机源注射：pending_battle.battle_seed（WorldMap._ready 摆敌阵之前拿它播全局流；带种子的这一场白刃也从全局流取
## 种子，见 WorldMap 文件尾「开战播种」）+ pending_battle.sea_seed（SeaState 私有 _rng）+ 敌船 / 护航船 _rng 与
## EnemyFloodFire 簿 rng / 我船 DamageModel rng / 士气挂件 rng / 号令面板 _rng 按种子起；每场开打前 GameState.martial
## 拨回开跑时的值（夺船 +1 不带进下一场）。
## 旧账两笔已了（lane w54-det，在 WorldMap 钉）：① _ready 的裸 randomize() 在 _spawn_enemy 之前（敌船落位 / 水手 / 士气
##   走 OS 熵，工具 add_child 后再 seed 也钉不回）；② 白刃没拿到 ctx.seed（_melee_sides 不给，MeleeResolve 见 0 自己打乱——
##   旧注记成 BoardingStage 当场拨号，那只是它的演示场，真漏在这一处）。剩下一样归跑法：炮弹飞行、限时两散与甩脱的计时
##   走 _process 的 delta，不带 --fixed-fps 就跟着墙钟走（机器一忙，两帧之间的物理步数就变），同种子两趟仍可能翻。
## 自检判词 = 各档跑满 N 场、无 hang、每场都按种子播上了全局流；同种子逐场再跑一遍（比收法、胜负、收场明细、战斗秒数、
## 护航失夺）：帧步一定（带了 --fixed-fps）时漂一场即红，没带时漂移只记不判（WINRATE 行 replay-drift=k 照报，
## SELFCHECK 行注明帧步跟墙钟走）。
## 判词：末行 WINRATE cfg=a/N …（逐配置一行）恒打；自检不过退 1。
##
## 护航上阵（lane w53-p6-escort 加；开关 escort_battle / escort_orders，见 scripts/combat/EscortWing.gd）：
##   --escort=TYPE[:CREW]   旗舰之外加一艘护航（可写多次，至多三艘；CREW 缺省按船型 crew_min）。player_power 照 SeaChart._fleet_power
##             把护航那份并进去（游戏里遇敌时就是全队算）——开了上阵，WorldMap 再扣掉上阵那份（EscortWing.power_left），敌船血量与
##             没有护航时一样；关了照全队，敌船血量按全队战力压低（旧玩法护航只在这里起作用）
##   --escort-cmp[=off,line,lure,board]  逐档跑：esc-off（escort_battle 关，旧玩法）/ esc-line / esc-lure / esc-board（上阵、开战即下这道将令）；
##             三期两键照全开。缺省四档都跑。WINRATE 行另记 esc-lost（护航沉 + 被夺艘数）/ esc-prize（护航跳帮夺船艘数）
##   --grapple 玩家驾驶也接舷：最近敌船够得着就按 G（同 G 键先过士气簿的肯不肯跳帮），一秒至多一次；夺舱要旗舰先钩上才扳，
##             量夺舱时各档都带上它才可比
##   工具改动理由：胜率工具原先只摆旗舰一船（Fleet.ships 只写一格），护航船上阵后要量「带护航 / 各将令」的胜负，得能摆护航、
##   能下将令、能让旗舰接舷（夺舱的扳机）；不带这几个参数时行为与原先逐字一致（不摆护航、不下将令、不接舷）。

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
## --escort 摆的护航船名（同 Fleet.HULL_NAMES 前三）
const ESCORT_NAMES := ["安济", "通济", "利涉"]
## pending_battle 里给全局随机流的种子键（同 WorldMap.BATTLE_SEED_KEY；WorldMap 带 autoload，-s 工具 preload 不得，照抄键名）
const BATTLE_SEED_KEY := "battle_seed"

## 开跑时的 GameState.martial（每场开打前拨回它）
var _martial0 := 50
## 开了场却没按种子播全局流的场数（> 0 = 键名对不上 WorldMap，SELFCHECK 判红）
var _unseeded := 0


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
		elif a.begins_with("--escort="):
			if not out.has("escorts"):
				out["escorts"] = []
			var ep := str(a.trim_prefix("--escort=")).split(":")
			if (out["escorts"] as Array).size() < 3:
				(out["escorts"] as Array).append({"type": ep[0], "crew": int(ep[1]) if ep.size() > 1 else -1})
		elif a.begins_with("--escort-cmp"):
			var want: Array = ["off", "line", "lure", "board"]
			if a.begins_with("--escort-cmp="):
				want = Array(str(a.trim_prefix("--escort-cmp=")).split(",", false))
			out["cfgs"].clear()
			for w in want:
				var ek := {KEY_A: true, KEY_B: true, "escort_battle": w != "off"}
				if w != "off":
					ek["_escort_order"] = String(w)
				out["cfgs"].append({"id": "esc-" + String(w), "keys": ek})
		elif a == "--grapple":
			out["grapple"] = true
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


## 手动对阵（--enemy 攒的）：type 逐项展开 count（TYPE:N 写了就用 N）、TYPE:N:SPRITE 带精灵；power 缺省沿用现有对照 300/300
static func _hand_matchup(a: Dictionary) -> Dictionary:
	var types: Array = a.get("_enemy_hand", [])
	var wide: int = int(a.get("_count_wide", 1))
	var foes: Array = []
	for t in types:
		var left := MAX_ENEMIES
		for e in foes:
			left -= int((e as Dictionary).get("count", 1))
		var parts := String(t).split(":")
		var want := int(parts[1]) if parts.size() > 1 else wide
		var n := clampi(want, 1, maxi(1, left))
		if n > 0:
			var foe := {"type": parts[0], "count": n}
			if parts.size() > 2 and parts[2] != "":
				foe["sprite"] = parts[2]
			foes.append(foe)
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


## 帧步定不定：开跑前空转几帧，比 process delta 的累计与墙钟——带了 --fixed-fps 时空帧一帧花不到一毫秒、却按 1/fps 记账，
## 一秒的账几十毫秒就记满（帧步一定，同种子复跑应逐场一样）；不带时 delta 就是墙钟，记满一秒要真等一秒
## （炮弹飞行、限时两散与甩脱的计时都走 _process，复跑漂移只作参考）
func _fixed_step() -> bool:
	await process_frame
	var sim := 0.0
	var t0 := Time.get_ticks_usec()
	while sim < 1.0 and Time.get_ticks_usec() - t0 < 500_000:
		await process_frame
		sim += root.get_process_delta_time()
	return sim >= 2.0 * float(Time.get_ticks_usec() - t0) / 1_000_000.0


## 复跑比对的一场签名：收法、胜负、收场明细（士气裁决或各船下场）、战斗秒数（取到 0.01）、护航失 / 夺。
## 只比收法与胜负的话，两趟打成两样、碰巧都是「敌遁、胜」也看不出分岔；帧步一定时这几样都该逐位一样
static func _sig(sd: int, r: Dictionary) -> Array:
	return [sd, str(r["overcome"]), bool(r["win"]), str(r["tag"]), snappedf(float(r["held_s"]), 0.01),
		int(r["esc_lost"]), int(r["esc_prize"])]


static func _sig_text(s: Array) -> String:
	return "%s/%s/%s/%.2f 秒%s" % [str(s[1]), "胜" if bool(s[2]) else "负", str(s[3]), float(s[4]),
		("/护航失 %d 夺 %d" % [int(s[5]), int(s[6])]) if int(s[5]) + int(s[6]) > 0 else ""]


## 档位套路上开关：reset 后按 keys 置（缺键 = 关）
static func _apply_cfg(keys: Dictionary) -> void:
	_Switches.reset()
	_Switches.set_on(KEY_A, bool(keys.get(KEY_A, false)))
	_Switches.set_on(KEY_B, bool(keys.get(KEY_B, false)))
	if keys.has("escort_battle"):
		_Switches.set_on("escort_battle", bool(keys["escort_battle"]))  # lane w53-p6-escort：--escort-cmp 各档


## 一场：seed 后真起海战，玩家驾驶到收战 / 玩家旗舰拆 / 墙钟上界。
## 返回 {"overcome", "win", "wall_s", "tag"}
##   overcome = win / lose / flee（battle_finished 首参；超时未收 = "hang"）
##   win      = overcome=win / 士气敌降敌破敌遁 / 击沉受降焚沉 ≥ 1（fled 半赏不算胜）
func _battle_one(fleet: Node, gm: Node, sd: int, mu: Dictionary, keys: Dictionary, drive: bool,
		orders: Array, seed_tag: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	# 钉死双随机源：
	# ① pending_battle.battle_seed：WorldMap._ready 摆敌阵之前拿它播全局流（敌船角度 / 距 / 水手 / 士气的 randf_range，
	#   连同此后全场读全局流的掷点与白刃种子，见 WorldMap 文件尾「开战播种」）。错开 sd 一段（sd + 1_000_000）。
	# ② pending_battle.sea_seed：SeaState 用私有 _rng 不吃全局流——不注射同 sd 也复现不出
	#   （b048e297 实测同 seed 11 两场结论漂）。sea_seed 用 sd 错段避免与全局流撞（sd + 7_000_000）。
	# 手动种子段 seed_tag（外部加段起一列独立随机，不撞种子表；本工具恒传 0）
	var shift := int(seed_tag) * 1_000_003
	var ship_id := String(mu.get("ship", "fu_ship_medium"))
	var d: Dictionary = fleet.call("ship_def", ship_id)
	var dur := float(d.get("durability", 300))
	var roster: Array = [{"type": ship_id, "name": "试船", "crew": int(mu.get("crew", 60)),
		"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": dur, "max_durability": dur}]
	# lane w53-p6-escort：--escort 摆护航；护航那份战力照 SeaChart._fleet_power 并进 player_power（上阵时 WorldMap 再扣掉）
	var esc_power := 0.0
	var esc_list: Array = mu.get("escorts", [])
	for k in esc_list.size():
		var es: Dictionary = esc_list[k]
		var ed: Dictionary = fleet.call("ship_def", String(es["type"]))
		var edur := float(ed.get("durability", 200))
		var ecrew := int(es["crew"]) if int(es["crew"]) > 0 else int(ed.get("crew_min", 10))
		roster.append({"type": String(es["type"]), "name": ESCORT_NAMES[k % ESCORT_NAMES.size()], "crew": ecrew,
			"sail_level": 1, "armor_level": 1, "cargo": {}, "durability": edur, "max_durability": edur})
		esc_power += edur * 0.5 + float(ecrew) * 4.0 + float(ed.get("cannon_slots", 0)) * 25.0
	fleet.set("ships", roster)
	fleet.set("morale", int(mu.get("morale", 60)))
	esc_power *= float(fleet.call("morale_factor"))
	# 白刃夺船得手会给 GameState.martial +1（WorldMap._board_enemy），士气簿与水手的白刃系数都读它——
	# 每场开打前拨回开跑时的值，同种子复跑不随前面几场夺没夺过船漂
	root.get_node("GameState").set("martial", _martial0)
	gm.set("pending_battle", {"battle": true, "power": float(mu.get("power", 300.0)),
		"player_power": float(mu.get("ppower", 300.0)) + esc_power,
		"enemy": (mu.get("enemy", MATCHUP_PIRATES["enemy"]) as Array).duplicate(true), "sea_name": "泉州外海",
		BATTLE_SEED_KEY: sd + shift + 1_000_000,
		"sea_seed": sd + shift + 7_000_000, "source": {"scene": "qa_w53_p3c"}})
	_apply_cfg(keys)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# _ready 是 add_child 同步跑的：全局流在摆敌阵前已按 battle_seed 播过（WorldMap 认了这枚键，_battle_seeded 为真）；
	# 没认（键名对不上）就是工具自身的病——复跑漂移量的不再是种子，记一笔，末了 SELFCHECK 判红
	if not bool(wm.get("_battle_seeded")):
		_unseeded += 1
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
	# lane w53-p6-escort：护航船也是 PirateShip（is_escort），私有 rng / 水火簿 rng 同样按种子起（错段，不撞敌船）
	var escs := wm.get_children().filter(func(c): return String(c.name).begins_with("EscortShip") and not c.is_queued_for_deletion())
	for k in escs.size():
		var er := RandomNumberGenerator.new()
		er.seed = sd + shift + 4_000_000 + k * 13_579
		escs[k].set("_rng", er)
		var effb = escs[k].get("flood_fire")
		if effb is Object and is_instance_valid(effb):
			var efr := RandomNumberGenerator.new()
			efr.seed = sd + shift + 4_500_000 + k * 13_579
			(effb as Object).set("rng", efr)
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
	# lane w53-p6-escort：开战布置即下护航将令（--escort-cmp 各档；整场不变）
	var wing := wm.get_node_or_null("EscortWing")
	if wing != null and keys.has("_escort_order"):
		wing.call("lock_order", String(keys["_escort_order"]), "player")
	# 物理帧泵（p3b 的跑法改到逐帧）：每一物理帧驾驶一拍（转舷 / 冷却够放舷齐射），
	# 30 帧一圈回看战况收没收——逐帧下锚点行为与墙钟解耦，同种子复跑才对得上（按 0.5 秒
	# 一拍下锚会把「哪一拍放的」随负载挪，seed 1222 实测漂出 win→lose）。
	var held := 0.0
	var last_elapsed := -1.0
	var stuck := 0
	var wall := 0.0
	var tick := 0
	var last_g := -99.0
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
			# --grapple（lane w53-p6-escort）：最近敌船够得着就按 G（先过士气簿肯不肯跳帮），一秒至多一次
			if drive and bool(mu.get("grapple", false)) and own != null and is_instance_valid(own) and held - last_g >= 1.0 \
					and is_instance_valid(wm) and not bool(wm.get("boarding")) and not bool(wm.get("resolved")):
				var ne: Array = wm.call("_nearest_enemy")
				if ne.size() == 2 and bool((wm.call("_board_check", ne[0]) as Dictionary).get("ok", false)):
					last_g = held
					var mo = wm.get("_morale")
					if mo == null or str(mo.call("player_boarding_check")) == "":
						wm.call("_board_enemy", ne[0])
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
	var out := {"overcome": "hang", "win": false, "wall_s": wall, "tag": "", "held_s": held, "esc_lost": 0, "esc_prize": 0}
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
		var esc_rec = data.get("escort")
		if esc_rec is Dictionary:
			out["esc_lost"] = ((esc_rec as Dictionary).get("sunk", []) as Array).size() + ((esc_rec as Dictionary).get("taken", []) as Array).size()
			out["esc_prize"] = int((esc_rec as Dictionary).get("prizes", 0))
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
	_martial0 = int(saved["martial"])
	var a := _args()
	var n: int = a["n"]
	var seeds: Array = a["seeds"]
	var fails := 0
	var fixed := await _fixed_step()
	var drift_all := 0
	var runs: Dictionary = {}  # cfg id → 各 seed 的 {"overcome","win"} 签名表（复跑自比用）
	for mid in a["matchups"]:
		var mu: Dictionary
		# 手动对阵（--enemy=）是 Dictionary：String() 构造不收 Dictionary（原样写 String(mid) 一跑 --enemy= 即
		# SCRIPT ERROR 卡死，lane w53-p5-blockade 修）——段名记作 hand，对阵本体照 _hand_matchup 那份
		var mid_name := "hand" if mid is Dictionary else String(mid)
		match mid_name:
			"pirates":
				mu = MATCHUP_PIRATES.duplicate(true)
			"falcon":
				mu = MATCHUP_FALCON.duplicate(true)
			_:
				mu = (mid as Dictionary).duplicate(true) if mid is Dictionary else MATCHUP_PIRATES.duplicate(true)
		mu["ship"] = String(a["ship"])
		mu["crew"] = int(a["crew"])
		mu["morale"] = int(a["morale"])
		mu["escorts"] = (a.get("escorts", []) as Array).duplicate(true)
		mu["grapple"] = bool(a.get("grapple", false))
		print("== 对阵：%s（我方 %s %d人 morale %d，power %.0f/%.0f，%s）%s" % [
			String(mu.get("label", mid_name)), String(mu["ship"]), int(mu["crew"]), int(mu["morale"]),
			float(mu.get("power", 300.0)), float(mu.get("ppower", 300.0)),
			"玩家驾驶" if bool(a["drive"]) else "手离舵",
			("　护航 %s%s" % [str(mu["escorts"]), "　接舷" if bool(mu["grapple"]) else ""]) if not (mu["escorts"] as Array).is_empty() else ""])
		for cfg in a["cfgs"]:
			var cid := String((cfg as Dictionary)["id"])
			var keys: Dictionary = (cfg as Dictionary)["keys"]
			var rows: Array = []
			for i in n:
				var r: Dictionary = await _battle_one(fleet, gm, int(seeds[i]), mu, keys,
					bool(a["drive"]), a["orders"], 0)
				rows.append(r)
				print("%s 第 %d/%d 场 种子 %d：%s %s（%.0f 秒墙钟 / %.0f 秒战斗）%s%s" % [
					cid, i + 1, n, int(seeds[i]), str(r["overcome"]),
					"胜" if bool(r["win"]) else "负",
					float(r["wall_s"]), float(r["held_s"]),
					("・" + str(r["tag"])) if str(r["tag"]) != "" else "",
					("・护航失 %d 夺 %d" % [int(r["esc_lost"]), int(r["esc_prize"])]) if not (mu["escorts"] as Array).is_empty() else ""])
			var won := 0
			var hangs := 0
			var esc_lost := 0
			var esc_prize := 0
			var sigs: Array = []
			for i in rows.size():
				var r: Dictionary = rows[i]
				esc_lost += int(r["esc_lost"])
				esc_prize += int(r["esc_prize"])
				if bool(r["win"]):
					won += 1
				if str(r["overcome"]) == "hang":
					hangs += 1
				sigs.append(_sig(int(seeds[i]), r))
			print("%s on=%d/%d 收 %d 场（hang %d）" % [cid, won, n, n, hangs])
			if hangs > 0:
				fails += hangs
			runs[cid] = sigs
			# ── 同种子复跑自比（bit-exact 判决）：每个配置鼻子下跑第二遍，逐场签名（_sig）须一致 ──
			var again: Array = []
			for i in n:
				var r2: Dictionary = await _battle_one(fleet, gm, int(seeds[i]), mu, keys,
					bool(a["drive"]), a["orders"], 0)
				again.append(_sig(int(seeds[i]), r2))
			var drift := 0
			for i in n:
				if sigs[i] != again[i]:
					drift += 1
					print("  漂移 %s 种子 %d：%s → %s" % [cid, int(seeds[i]), _sig_text(sigs[i]), _sig_text(again[i])])
			# 漂移判词（lane w54-det）：全局流与白刃种子由 WorldMap 按 battle_seed 播（见其文件尾「开战播种」），
			# 各私有 rng 本工具注射，帧步一定时同种子复跑应逐场一样——漂了即有随机源没钉住，SELFCHECK 判红；
			# 没带 --fixed-fps 时炮弹飞行、限时两散与甩脱的计时跟着墙钟走，漂移只记不判（WINRATE 行照报）。
			drift_all += drift
			if drift > 0:
				print("  漂移注记 %s：%d/%d 场复跑翻盘（%s）" % [cid, drift, n,
					"帧步一定仍漂，有随机源没钉住" if fixed else "没带 --fixed-fps，帧步跟墙钟走"])
			# 逐配置末行（多段对阵时每段都打——主控按行收数）
			var sd_names := PackedStringArray()
			for i in n:
				sd_names.append(str(int(seeds[i])))
			print("WINRATE %s@%s=%d/%d seeds=%s replay-drift=%d%s" % [
				cid, mid_name, won, n, ",".join(sd_names), drift,
				(" esc-lost=%d esc-prize=%d" % [esc_lost, esc_prize]) if not (mu["escorts"] as Array).is_empty() else ""])
	# 还原战况与开关
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	gm.set("pending_battle", saved["pb"])
	gs.set("martial", saved["martial"])
	gs.set("money", saved["money"])
	gs.set("fame", saved["fame"])
	_Switches.reset()
	await process_frame
	if _unseeded > 0:
		print("  %d 场没按种子播全局流（pending_battle.%s 没被 WorldMap 认）" % [_unseeded, BATTLE_SEED_KEY])
		fails += _unseeded
	if fixed:
		fails += drift_all
	if fails == 0:
		print("SELFCHECK %s OK（各档跑满 %d 场、无 hang；%s）" % [TAG, n,
			"帧步一定，同种子复跑逐场一致" if fixed else "没带 --fixed-fps：帧步跟墙钟走，复跑漂移只记不判，详见各 WINRATE 行"])
		quit(0)
		return
	print("SELFCHECK %s FAIL（hang/缺场/没播种/定帧步下复跑漂移 共 %d 处）" % [TAG, fails])
	quit(1)
