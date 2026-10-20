extends SceneTree
## lane w54-combatai 敌阵摆位探针（headless，经门锁跑；真 WorldMap 海战场，开战那一帧读敌船落位）。
##   godot --headless --path . -s res://tools/qa_w54_combatai_spawn_probe.gd
## 病：WorldMap._spawn_enemy 按「这一条」里的序号摆圈——pending_battle.enemy 写成两条的阵（闯封锁 Voyage.BLOCKADE_PATROL：
## 海鹘一 + 快船二；崖山 YashanBattle.setup：海鹘一 + 快船一 / 二）每条都从 0 度起摆，海鹘与头一艘快船落在同一处
## （各自 ±0.25 rad 抖动，最远也只隔 350 px，常常船身叠着），开场就挤成一团互撞、互相挡炮。
## 修：按全场序号在 N 等分的一圈上摆（N = 各条 count 之和）；只一条的阵（遇盗快船二、元军海鹘三）全场序号就是条内序号，
## 摆法一字不变。全局随机流取数的次数与次序不变（同种子此后各掷照旧）。
##   一、闯封锁六个种子：三艘两两相距 ≥ 600 px（三等分 ±0.25 rad 最近也有一千上下）——回退即红：海鹘与头一艘快船 ≤ 350
##   二、崖山（没借过船那一档：海鹘一 + 快船一）三个种子：两艘相距 ≥ 1000
##   三、只一条的阵（遇盗快船二、元军海鹘三）：第 k 艘落在 TAU·k / N ±0.25 rad、离旗舰 700–720（与改前同式）
## 判词：末行 QA_W54_COMBATAI_SPAWN PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_COMBATAI_SPAWN"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
## pending_battle 里给全局随机流的种子键（同 WorldMap.BATTLE_SEED_KEY；WorldMap 带 autoload，-s 探针 preload 不得，照抄键名）
const BATTLE_SEED_KEY := "battle_seed"
## 摆圈的抖动与距离（同 WorldMap._spawn_enemy：±0.25 rad、COMBAT_SPAWN_DIST_MIN / MAX）
const JITTER := 0.25
const DIST_MIN := 700.0
const DIST_MAX := 720.0

var _fleet: Node = null
var _gm: Node = null
var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	var saved := {"ships": (_fleet.get("ships") as Array).duplicate(true), "morale": _fleet.get("morale"),
		"pb": (_gm.get("pending_battle") as Dictionary).duplicate(true)}
	var blockade: Array = ((root.get_node("Voyage").get_script() as Script).get_script_constant_map()["BLOCKADE_PATROL"] as Array).duplicate(true)
	print("== 一、闯封锁（%s）：三艘两两相距 ≥ 600" % _list_text(blockade))
	for sd in [101, 202, 303, 404, 505, 606]:
		var got := await _spawn({"battle": true, "power": 500.0, "player_power": 520.0, "enemy": blockade.duplicate(true),
			"sea_name": "兴化外海", "source": {"scene": "SeaChart", "event": "blockade", "port": "xinghua"}}, sd)
		var gap := _min_gap(got)
		_check(got.size() == 3 and gap >= 600.0, "种子 %d：三艘最近两艘相距 %.0f px（%s）" % [sd, gap, _where(got)])
	var yb = load("res://scripts/combat/YashanBattle.gd")
	var ypb: Dictionary = yb.call("setup", 300.0, false)
	print("== 二、崖山（没借过船那一档 %s）：两艘相距 ≥ 1000" % _list_text(ypb.get("enemy", [])))
	for sd in [11, 23, 37]:
		var got := await _spawn(ypb.duplicate(true), sd)
		var gap := _min_gap(got)
		_check(got.size() == 2 and gap >= 1000.0, "种子 %d：两艘相距 %.0f px（%s）" % [sd, gap, _where(got)])
	print("== 三、只一条的阵：第 k 艘落在 TAU·k/N ±0.25 rad、离旗舰 700–720（摆法与改前同式）")
	var singles := [[{"type": "pirate_boat", "count": 2}], [{"type": "sea_falcon", "sprite": "yuan_patrol", "count": 3}]]
	for lst in singles:
		for sd in [41, 53]:
			var got := await _spawn({"battle": true, "power": 300.0, "player_power": 300.0, "enemy": (lst as Array).duplicate(true),
				"sea_name": "泉州外海", "source": {"scene": "SeaChart", "event": "pirate"}}, sd)
			var n := 0
			for e in lst:
				n += int((e as Dictionary)["count"])
			var ok := got.size() == n
			for row in got:
				var want := TAU * float(row["k"]) / float(n)
				ok = ok and absf(wrapf(float(row["ang"]) - want, -PI, PI)) <= JITTER + 0.001 \
					and float(row["dist"]) >= DIST_MIN - 0.5 and float(row["dist"]) <= DIST_MAX + 0.5
			_check(ok, "%s 种子 %d：%s" % [_list_text(lst), sd, _where(got)])
	_fleet.set("ships", saved["ships"])
	_fleet.set("morale", saved["morale"])
	_gm.set("pending_battle", saved["pb"])
	_report()


## 起一场（旗舰福船 60 人），add_child 当场跑完 _ready（摆敌阵在里头），读各敌船相对旗舰的方位、距离；随即拆场
func _spawn(pb: Dictionary, sd: int) -> Array:
	_fleet.set("ships", [{"type": "fu_ship_medium", "name": "试船", "crew": 60, "sail_level": 1, "armor_level": 1,
		"cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 60)
	_fleet.set("escorts_in_battle", [])
	pb[BATTLE_SEED_KEY] = sd
	pb["sea_seed"] = 7_000_000 + sd
	_gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var own: Node2D = wm.get("ship")
	var out: Array = []
	for c in wm.get_children():
		var nm := String(c.name)
		if not nm.begins_with("PirateShip_") or c.is_queued_for_deletion():
			continue
		var rel: Vector2 = (c as Node2D).position - own.position
		out.append({"name": nm, "type": str(c.get("ship_type")), "k": int(nm.trim_prefix("PirateShip_")) - 1,
			"pos": (c as Node2D).position, "ang": rel.angle(), "dist": rel.length()})
	wm.set("resolved", true)
	wm.queue_free()
	await process_frame
	await process_frame
	return out


static func _min_gap(rows: Array) -> float:
	var best := INF
	for i in rows.size():
		for j in range(i + 1, rows.size()):
			best = minf(best, (rows[i]["pos"] as Vector2).distance_to(rows[j]["pos"]))
	return best


static func _where(rows: Array) -> String:
	var bits := PackedStringArray()
	for r in rows:
		bits.append("%s %s %.0f° %.0fpx" % [r["name"], r["type"], rad_to_deg(float(r["ang"])), float(r["dist"])])
	return "；".join(bits)


static func _list_text(lst: Array) -> String:
	var bits := PackedStringArray()
	for e in lst:
		bits.append("%s×%d" % [str((e as Dictionary).get("type", "")), int((e as Dictionary).get("count", 1))])
	return "+".join(bits)
