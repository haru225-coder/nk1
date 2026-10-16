extends SceneTree
## lane w53-p6-escort 第六期性能探针（方案 §十一「第六期最多同屏 6–8 艘船；火船粒子数不超过现在的上限」）：
##   三档，各量 FRAMES 帧（≥ 600）的平均帧时与 p95（毫秒）：
##     on      开关 escort_battle 开：旗舰 + 护航 3 + 快船 4 = 同屏 8 艘
##     off     开关关（护航不上阵）：旗舰 + 快船 4 = 5 艘
##     yashan  崖山突围那一场（yashan lane）：pending_battle 照 YashanBattle.setup 起——旗舰 + 元军船阵 + 火船，护航不上阵
##             （no_escort），同屏照那边 SCREEN_CAP 压在 8 艘；仓里没有 res://scripts/combat/YashanBattle.gd 就跳过这一档
##             （印一行「跳过」，不判红）
##   同屏船数的数法（同 EscortWing 头注）：旗舰 1 + 护航（EscortShip_）+ 敌船（PirateShip_）+ 火船（FireShip_，挂在 FireShips 下）。
##   另报 process / physics 每帧耗时、每帧物理步数、绘制调用、同屏船数（整段最少 / 开场）、在喷粒子总数（整段取最多）。
## 用法（带窗口，帧时作数；本机无 GPU、:2 走软件渲染，绝对值偏大，看开 / 关两份之差）：
##   DISPLAY=:2 bash /workspace/w53/tools/glock.sh godot --fixed-fps 60 --path . -s res://tools/qa_w53_p6_perf_probe.gd \
##     [-- --frames=900 --warmup=120 --cfg=on,off --fireships=N]
##   --fixed-fps 60：每帧恰走一步物理（同游戏里 60 帧一步），量到的是一帧的全部开销；vsync 关、max_fps 0，不被垂直同步钉在 16.7。
##   headless（门禁 gates-full 照常这么跑）：无渲染，帧时只含 CPU——判词照出，数不作数（印一行注记）。
## 布景：打不沉、不溃、不打光——敌船与护航船体 100000、敌船水手 120 士气 90、矢石 999 轮；旗舰 300 人、耐久 100000、半帆开船、
##   见敌在舷就放（同胜率工具的驾驶）；士气簿裁决不接（不半路收战）。量的是「8 艘都在场、你来我往放箭」的稳态帧，不是哪方先垮。
##   护航开战即下「列队」：跟在旗舰侧后，都在画内。
##   yashan 一档：火船照那边的走法顺风漂来、挨着旗舰就点火、点完自焚（量的就是火船烧起来那几秒）；旗舰出了港嘴那道线
##   那一场就按冲出收战——探针把那道线（WorldMap._yashan_escape_px）推到天边，旗舰收帆不走，让火船都漂到、烧完。
##   --fireships=N：盖掉这一档的火船艘数（pending_battle.yashan.fire_ships；不管同屏上限，压测用）。
## 判词：每份一行 PERF cfg=… ships=… fireships=… frames=… mean_ms=… p95_ms=…；末行 QA_W53_P6_PERF PASS|FAIL（采满帧、
##   on / off 船数对、yashan 开场同屏 ≤ 8、没半路收战、本进程无 SCRIPT ERROR）。不判帧时快慢（机器负载起伏大），数交人读、写进 commit。

const TAG := "QA_W53_P6_PERF"
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const YASHAN_PATH := "res://scripts/combat/YashanBattle.gd"
const TOUGH := 100000.0

var _frames := 900
var _warmup := 120
var _cfgs: Array = ["on", "off", "yashan"]
var _fireships := -1
var _fails: Array = []
var _errlog: _ScriptErrLog = null


class _ScriptErrLog:
	extends Logger
	var lines: Array = []

	func _log_error(function: String, _file: String, line: int, _code: String, rationale: String, _notify: bool, _type: int, _script_backtraces: Array) -> void:
		lines.append("%s:%d %s %s" % [function, line, _code, rationale])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_errlog = _ScriptErrLog.new()
	OS.add_logger(_errlog)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = maxi(600, int(a.trim_prefix("--frames=")))
		elif a.begins_with("--warmup="):
			_warmup = maxi(0, int(a.trim_prefix("--warmup=")))
		elif a.begins_with("--cfg="):
			_cfgs = Array(a.trim_prefix("--cfg=").split(",", false))
		elif a.begins_with("--fireships="):
			_fireships = maxi(0, int(a.trim_prefix("--fireships=")))  # 只管 yashan 一档
	var headless := DisplayServer.get_name() == "headless"
	print("%s 起：%s，每份 %d 帧（先空跑 %d 帧）；--fixed-fps 60 带没带看每行 phys_per_frame（1.00 = 每帧恰一步物理）" % [TAG,
		"headless（无渲染，帧时只含 CPU，不作数）" if headless else "带窗口", _frames, _warmup])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var fleet: Node = root.get_node("Fleet")
	var gm: Node = root.get_node("GameManager")
	var saved := {"ships": (fleet.get("ships") as Array).duplicate(true), "morale": fleet.get("morale"),
		"pb": (gm.get("pending_battle") as Dictionary).duplicate(true)}
	var ran: Array = []
	for cfg in _cfgs:
		if String(cfg) == "yashan" and not ResourceLoader.exists(YASHAN_PATH):
			print("PERF cfg=yashan 跳过：%s 不在仓里（崖山突围那一路没并进来）" % YASHAN_PATH)
			continue
		await _measure(String(cfg), fleet, gm)
		ran.append(String(cfg))
	fleet.set("ships", saved["ships"])
	fleet.set("morale", saved["morale"])
	fleet.set("escorts_in_battle", [])
	gm.set("pending_battle", saved["pb"])
	_Switches.reset()
	await process_frame
	if not _errlog.lines.is_empty():
		_fails.append("本进程 SCRIPT ERROR %d 条（头一条：%s）" % [_errlog.lines.size(), str(_errlog.lines[0])])
	if _fails.is_empty():
		print("%s PASS（%s 各采满 %d 帧、船数对、没半路收战、无 SCRIPT ERROR）" % [TAG, "/".join(PackedStringArray(ran)), _frames])
		quit(0)
		return
	for f in _fails:
		print("  ✗ " + str(f))
	print("%s FAIL（%d 项）" % [TAG, _fails.size()])
	quit(1)


func _mk(t: String, nm: String, crew: int) -> Dictionary:
	return {"type": t, "name": nm, "crew": crew, "sail_level": 1, "armor_level": 1, "cargo": {},
		"durability": TOUGH, "max_durability": TOUGH}


func _measure(cfg: String, fleet: Node, gm: Node) -> void:
	_Switches.reset()
	_Switches.set_on("escort_battle", cfg != "off")
	fleet.set("ships", [_mk("fu_ship_medium", "旗舰", 300), _mk("keel_boat", "安济", 30),
		_mk("fu_ship_medium", "通济", 40), _mk("canton_ship", "利涉", 50)])
	fleet.set("morale", 70)
	fleet.set("escorts_in_battle", [])
	seed(6600)
	var pb := {"battle": true, "power": 400.0, "player_power": 1000.0,
		"enemy": [{"type": "pirate_boat", "count": 4}], "sea_name": "泉州外海", "sea_seed": 7_006_600,
		"source": {"scene": "qa_w53_p6_perf"}}
	if cfg == "yashan":
		# 崖山那一场照那边自己的场次起（元军船阵、火船、港湾海况、no_escort）；海况种子定死好复现
		var ys = load(YASHAN_PATH)
		pb = ys.call("setup", 1000.0, true)
		pb["sea_seed"] = 7_006_600
		if _fireships >= 0 and pb.get("yashan") is Dictionary:
			(pb["yashan"] as Dictionary)["fire_ships"] = _fireships
	gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	var rec: Array = []
	wm.battle_finished.connect(func(o: String, _d: Dictionary) -> void: rec.append(o))
	# 布景打不沉、不溃、不打光（刷好、第一物理帧之前就改：士气挂件头一回登记的就是改过的船体）
	for c in wm.get_children():
		var nm := String(c.name)
		if nm.begins_with("PirateShip") or nm.begins_with("EscortShip"):
			c.set("hull_max", TOUGH)
			c.set("hull_hp", TOUGH)
			if nm.begins_with("PirateShip"):
				c.set("crew", 120)
				c.set("enemy_morale", 90)
			var cap = c.get("captain")
			if cap != null:
				cap.set("morale", 90.0)
				cap.set("volleys", 999)
				cap.set("volleys_max", 999)
	var mo = wm.get("_morale")
	if mo != null and mo.verdict.is_connected(Callable(wm, "_on_morale_verdict")):
		mo.verdict.disconnect(Callable(wm, "_on_morale_verdict"))
	var own: Node2D = wm.get("ship")
	own.set("sail_gear", 0 if cfg == "yashan" else 1)
	if cfg == "yashan" and wm.get("_yashan_escape_px") != null:
		wm.set("_yashan_escape_px", 1.0e9)  # 港嘴那道线推到天边：旗舰收帆不走，火船都漂到、烧完
	var wing := wm.get_node_or_null("EscortWing")
	if wing != null:
		wing.call("lock_order", "line", "player")
	var fire_n := _fire_ships(wm)
	var ships_start := _ships_on_field(wm)
	var want_ships := 1 + 4 + (3 if cfg != "off" else 0)
	var times: Array = []
	var proc_ms := 0.0
	var phys_ms := 0.0
	var ships_min := 99
	var parts_max := 0
	var draws := 0.0
	var phys0 := 0
	var last := Time.get_ticks_usec()
	for i in _warmup + _frames:
		await process_frame
		var now := Time.get_ticks_usec()
		if not is_instance_valid(wm) or not rec.is_empty():
			break
		_drive(wm, own)
		if i == _warmup:
			phys0 = Engine.get_physics_frames()
		if i >= _warmup:
			times.append(float(now - last) / 1000.0)
			proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			ships_min = mini(ships_min, _ships_on_field(wm))
			if (i - _warmup) % 30 == 0:
				parts_max = maxi(parts_max, _particles(wm))
		last = Time.get_ticks_usec()
	var n := times.size()
	var phys_steps := Engine.get_physics_frames() - phys0
	if n < _frames:
		_fails.append("cfg=%s 只采到 %d 帧（应 %d；%s）" % [cfg, n, _frames, "半路收战 " + str(rec) if not rec.is_empty() else "布景没了"])
	if cfg == "yashan":
		if ships_start > 8:
			_fails.append("cfg=yashan 开场同屏 %d 艘（旗舰 + 敌船 + 火船 + 护航，应 ≤ 8）" % ships_start)
	elif ships_min != want_ships:
		_fails.append("cfg=%s 同屏船数最少 %d（应 %d）" % [cfg, ships_min, want_ships])
	times.sort()
	var mean := 0.0
	for t in times:
		mean += float(t)
	mean /= maxf(1.0, float(n))
	var p95: float = float(times[clampi(int(ceil(0.95 * float(n))) - 1, 0, maxi(0, n - 1))]) if n > 0 else 0.0
	var mx: float = float(times[n - 1]) if n > 0 else 0.0
	print("PERF cfg=%s ships=%d ships_start=%d fireships=%d frames=%d mean_ms=%.2f p95_ms=%.2f max_ms=%.2f process_ms=%.2f physics_ms=%.2f phys_per_frame=%.2f draw_calls=%.0f particles_max=%d mode=%s" % [
		cfg, ships_min, ships_start, fire_n, n, mean, p95, mx, proc_ms / maxf(1.0, float(n)), phys_ms / maxf(1.0, float(n)),
		float(phys_steps) / maxf(1.0, float(n)), draws / maxf(1.0, float(n)), parts_max,
		"headless" if DisplayServer.get_name() == "headless" else "windowed"])
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
	await process_frame
	await process_frame


## 旗舰见敌在舷就放（同胜率工具：最近一艘进 55° 舷弧、冷却好了即放）；不转舵，船照半帆直走
func _drive(wm: Node, own: Node2D) -> void:
	if own == null or not is_instance_valid(own) or float(own.get("fire_cooldown")) > 0.0:
		return
	var best := INF
	var foe: Node2D = null
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and float(c.get("hull_hp")) > 0.0:
			var d := (c as Node2D).global_position.distance_squared_to(own.global_position)
			if d < best:
				best = d
				foe = c
	if foe == null:
		return
	var to: Vector2 = foe.global_position - own.global_position
	var sb := Vector2.RIGHT.rotated(own.global_rotation)
	if absf(sb.angle_to(to)) < deg_to_rad(55.0) or absf((-sb).angle_to(to)) < deg_to_rad(55.0):
		own.call("_fire_broadside", 1 if to.dot(sb) >= 0.0 else -1)


## 同屏船数（数法同 EscortWing 头注）：旗舰 + 场上活着的敌船（PirateShip_）/ 护航（EscortShip_）+ 还没烧完的火船（FireShip_）
static func _ships_on_field(wm: Node) -> int:
	var n := 0
	for c in wm.get_children():
		var nm := String(c.name)
		if (nm.begins_with("PirateShip") or nm.begins_with("EscortShip")) and not c.is_queued_for_deletion() \
				and float(c.get("hull_hp")) > 0.0:
			n += 1
	return n + _fire_ships(wm) + (1 if is_instance_valid(wm.get("ship")) else 0)


## 场上还在的火船（崖山那一场挂在 WorldMap/FireShips 下，节点名 FireShip_ 前缀）
static func _fire_ships(wm: Node) -> int:
	var n := 0
	for c in wm.find_children("FireShip_*", "", true, false):
		if not c.is_queued_for_deletion():
			n += 1
	return n


## 在喷的粒子总数（CPU / GPU 粒子节点的 amount，emitting 才算）
static func _particles(wm: Node) -> int:
	var n := 0
	for p in wm.find_children("*", "CPUParticles2D", true, false):
		if (p as CPUParticles2D).emitting:
			n += (p as CPUParticles2D).amount
	for p in wm.find_children("*", "GPUParticles2D", true, false):
		if (p as GPUParticles2D).emitting:
			n += (p as GPUParticles2D).amount
	return n
