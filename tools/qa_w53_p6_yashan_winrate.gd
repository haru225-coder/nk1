extends SceneTree
## lane-w53-p6-yashan 崖山突围的胜率 / 帧时工具（headless 可跑，经 glock 跑；带 DISPLAY=:2 时另量帧时）。
## 这一仗不是打赢，是冲出去：本工具按「冲出 / 没冲出」与帧时两个数给玩家那一场定量。
##
## 用法：
##   godot --headless --path . -s res://tools/qa_w53_p6_yashan_winrate.gd -- --n=24 --seeds=11,23,...
##     --crew=60                 旗舰水手（两三档：40 / 60 / 90 各跑一遍）
##     --ship=fu_ship_medium     旗舰船型
##     --off                     关掉这一场（开关 yashan_breakout / yashan_fire_ship），量关态对照
##     --no-fire-ships           只关火船那一枚开关
##     --fps                     带窗口（DISPLAY=:2）时量帧时，末行 FPS 行给平均 / p95 毫秒
##   --n 缺省 24（种子取 --seeds 的个数、缺省用默认表）
##
## 跑法（判词）：
##   末行 WINRATE cfg=<档> n=<场> out=<冲出> in=<没冲出> hang=<卡住> 与 FPS 行（--fps 时）。
##   自检：同种子复跑一遍逐场比对，漂移场数记在 WINRATE 行的 replay-drift=（不判红，照实写）。
##   判红只挑工具自身的病（场数跑不满 / 卡住）。玩家驾驶是脚本，不是真人。
##
## 玩家怎么开（脚本驾驶，逐物理帧）：
##   出路在正北（港湾出口），风从北来。火船顺风从北面压过来，正北一路会撞上火船——
##   所以驾驶分两件：① 舵朝出路（正北）压，② 近处有火船就让开一舷（横向让过，不调头）。
##   这一路是脚本驾驶的下限：真人玩家看得更早、让得更准，冲出率只会更高。

const TAG := "QA_W53_P6_YASHAN_WINRATE"
const LIMIT_S := 260.0            # 墙钟上限：一场 150 秒的时限 + 装载余量
const DEFAULT_SEEDS := [11, 23, 37, 41, 53, 67, 79, 83, 97, 101, 113, 127,
	139, 149, 157, 163, 173, 181, 191, 199, 211, 223, 227, 233]

var _gs: Node
var _cal: Node
var _fleet: Node
var _gm: Node
var _want_fps := false
var _off := false
var _no_fire := false
var _crew := 60
var _ship_type := "fu_ship_medium"
var _n := 24
var _seeds: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	_parse_args()
	if _off:
		CS.set_on("yashan_breakout", false)
	if _no_fire:
		CS.set_on("yashan_fire_ship", false)
	var seeds: Array = _seeds if not _seeds.is_empty() else DEFAULT_SEEDS
	seeds = seeds.slice(0, mini(_n, seeds.size()))
	var cfg := "%s crew=%d ship=%s breakout=%s fire=%s" % [
		"off" if _off else "on", _crew, _ship_type, str(CS.on("yashan_breakout")), str(CS.on("yashan_fire_ship"))]
	var first := await _sweep(seeds)
	var second := await _sweep(seeds)
	var drift := 0
	for i in mini(first.size(), second.size()):
		if bool(first[i]) != bool(second[i]):
			drift += 1
	var out_n := 0
	var in_n := 0
	var hang := 0
	for r in first:
		if r == null:
			hang += 1
		elif bool(r):
			out_n += 1
		else:
			in_n += 1
	print("WINRATE cfg=%s n=%d out=%d in=%d hang=%d replay-drift=%d" % [cfg, first.size(), out_n, in_n, hang, drift])
	print("%s DONE" % TAG)
	quit(0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--n="):
			_n = maxi(1, int(s.substr(4)))
		elif s.begins_with("--crew="):
			_crew = maxi(1, int(s.substr(7)))
		elif s.begins_with("--ship="):
			_ship_type = s.substr(7)
		elif s.begins_with("--seeds="):
			_seeds = []
			for p in s.substr(8).split(","):
				if str(p).strip_edges() != "":
					_seeds.append(int(p))
		elif s == "--off":
			_off = true
		elif s == "--no-fire-ships":
			_no_fire = true
		elif s == "--fps":
			_want_fps = true


## 一趟全跑：逐种子开场，返回每场「冲出来了没有」（null = 卡住没跑完）
func _sweep(seeds: Array) -> Array:
	var out: Array = []
	for sd in seeds:
		out.append(await _one(int(sd)))
	return out


## 一场：起 WorldMap（崖山港湾那场），脚本驾驶逐物理帧，按收战信号或本机释放判收。
## 返回 true = 冲出来了，false = 没冲出来，null = 卡住（墙钟超限还没收）
func _one(sd: int) -> Variant:
	_fleet.set("ships", [{"type": _ship_type, "name": "试船", "crew": _crew, "sail_level": 2,
		"armor_level": 1, "cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 70)
	var pb: Dictionary = YashanBattle.setup(300.0, false)
	pb["sea_seed"] = sd
	_gm.set("pending_battle", pb)
	seed(sd)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 3:
		await process_frame
	# 盖回各私有 rng（同 p3c 工具那一套：敌船 / 水火簿 / 我船损伤模型 / 士气挂件）
	var foes := wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())
	var idx := 0
	for f in foes:
		var r := RandomNumberGenerator.new()
		r.seed = sd + 3_000_000 + idx * 13_579
		idx += 1
		f.set("_rng", r)
		var ffb = f.get("flood_fire")
		if ffb is Object and is_instance_valid(ffb):
			var fr := RandomNumberGenerator.new()
			fr.seed = sd + 8_000_000 + (idx - 1) * 13_579
			(ffb as Object).set("rng", fr)
	var own: Node2D = wm.get("ship")
	if own != null:
		var dm = own.call("get_damage_model") if own.has_method("get_damage_model") else null
		if dm != null:
			var dr := RandomNumberGenerator.new()
			dr.seed = sd + 5_000_000
			dm.set("rng", dr)
	var rec: Array = []
	var freed := [false]
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	if own != null:
		own.tree_exited.connect(func() -> void: freed[0] = true)
	var t0 := Time.get_ticks_msec()
	var frame_ms: Array = []
	var last_tick := Time.get_ticks_msec()
	while rec.is_empty() and not freed[0]:
		await physics_frame
		var now := Time.get_ticks_msec()
		if _want_fps:
			frame_ms.append(float(now - last_tick))
		last_tick = now
		if not is_instance_valid(wm):
			break
		if own != null and is_instance_valid(own):
			_drive(wm, own)
		if float(now - t0) / 1000.0 > LIMIT_S:
			break
	var result: Variant = null
	if not rec.is_empty():
		result = YashanBattle.broke_out(str(rec[0][0]), rec[0][1] as Dictionary)
	if _want_fps and not frame_ms.is_empty():
		_report_fps(frame_ms)
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
	_gm.set("pending_battle", {})
	return result


## 脚本驾驶：舵压出路（正北），近处有火船就让开一舷。不改产品脚本，只改旗舰这一个节点的朝向 / 帆。
func _drive(wm: Node, own: Node2D) -> void:
	if bool(wm.get("resolved")):
		return
	# 出路：朝本场的出海那一头（WorldMap.yashan_exit_dir：风从哪来、出路就在那头）
	var sea: Vector2 = wm.call("yashan_exit_dir") if wm.has_method("yashan_exit_dir") else Vector2(0, -1)
	if sea.length() < 0.01:
		sea = Vector2(0, -1)
	var want := sea.angle() - PI * 0.5        # 船首朝出口（船首是 UP 旋转后的方向）
	var host: Node = wm.get_node_or_null("FireShips")
	if host != null:
		var near: Node2D = null
		var best := 260.0
		for c in host.get_children():
			if not (c is Node2D) or c.is_queued_for_deletion():
				continue
			var n := c as Node2D
			if bool(n.get("fire_spent")):
				continue
			var d := n.position.distance_to(own.position)
			if d < best:
				best = d
				near = n
		if near != null:
			# 让开：朝「火船的反侧」偏 60 度——不调头，只错开一舷
			var away: Vector2 = own.position - near.position
			var side := signf(away.x) if absf(away.x) > 1.0 else 1.0
			want = sea.angle() - PI * 0.5 + side * deg_to_rad(60.0)
	own.rotation = lerp_angle(own.rotation, want, 0.06)
	own.set("sail_gear", 2)


func _report_fps(frame_ms: Array) -> void:
	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var avg := 0.0
	for v in frame_ms:
		avg += float(v)
	avg /= float(frame_ms.size())
	var p95: float = float(sorted_ms[mini(sorted_ms.size() - 1, int(ceil(float(sorted_ms.size()) * 0.95)) - 1)])
	print("FPS n=%d avg=%.2fms p95=%.2fms" % [frame_ms.size(), avg, p95])


const CS := preload("res://scripts/combat/CombatSwitches.gd")
