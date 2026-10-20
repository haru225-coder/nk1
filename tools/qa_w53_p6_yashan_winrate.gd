extends SceneTree
## lane-w53-p6-yashan 崖山突围的胜率 / 帧时工具（headless 可跑，经 glock 跑；带 DISPLAY=:2 时另量帧时）。
## 这一仗不是打赢，是冲出去：本工具按「冲出 / 没冲出」与帧时两个数给玩家那一场定量。
##
## 用法：
##   godot --headless --fixed-fps 120 --path . -s res://tools/qa_w53_p6_yashan_winrate.gd -- --n=24 --seeds=11,23,...
##     --crew=60                 旗舰水手（两三档：40 / 60 / 90 各跑一遍）
##     --ship=fu_ship_medium     旗舰船型
##     --off                     关掉这一场（开关 yashan_breakout / yashan_fire_ship），量关态对照
##     --no-fire-ships           只关火船那一枚开关
##     --fps                     带窗口（DISPLAY=:2）时量帧时，末行 FPS 行给平均 / p95 毫秒
##   --n 缺省 24（种子取 --seeds 的个数、缺省用默认表）
##
## 跑法（判词）：
##   末行 WINRATE cfg=<档> n=<场> out=<冲出> in=<没冲出> hang=<卡住> 与 FPS 行（--fps 时）。
##   复现（lane w54-det）：每场 pending_battle 带 battle_seed（WorldMap 摆敌阵之前拿它播全局流，见其文件尾「开战播种」）
##   与 sea_seed，开场当即（一帧不等）把敌船 / 火船 / 水火簿 / 本船损伤模型 / 士气挂件 / 号令面板的私有 rng 盖回种子。
##   帧步还得一定：炮弹飞行、时限与火船挨没挨上的判定都走 _process，不带 --fixed-fps 就跟着墙钟走——
##   本工具物理帧率 120，配 --fixed-fps 120 是一帧一物理步（同产品 60 / 60 的一比一）。
##   自检：同种子复跑一遍逐场比对（冲没冲出 + 怎么收的），漂移场数记在 WINRATE 行的 replay-drift=；
##   帧步一定时漂一场即判红（有随机源没钉住），没带 --fixed-fps 时只作参考、照实写。
##   另判红两样工具自身的病：有场卡住（hang）、种子没播上（键名对不上 WorldMap）。
##   玩家驾驶是脚本，不是真人。
##
## 玩家怎么开（脚本驾驶，逐物理帧）：
##   出路在正北（港湾出口），风从北来。火船顺风从北面压过来，正北一路会撞上火船——
##   所以驾驶分两件：① 舵朝出路（正北）压，② 近处有火船就让开一舷（横向让过，不调头）。
##   这一路是脚本驾驶的下限：真人玩家看得更早、让得更准，冲出率只会更高。

const TAG := "QA_W53_P6_YASHAN_WINRATE"
## 卡住的判法照这一场自己的时限算：战场经过秒数（WorldMap._battle_elapsed_s，到 _battle_limit_s 即限时两散）过了时限
## 再加 HANG_PAD_S 还没收 = 卡住，记 hang 换个种子；墙钟另留 LIMIT_S 一道兜底（经过秒数停着不走的那种卡法）。
## 原先只有一道「墙钟 260 秒」，是按本场时限 60 秒（YashanBattle.BATTLE_LIMIT_S）定的——可那 60 秒没接进 WorldMap，
## 这一场实际照阶段表 300 秒两散；不带 --fixed-fps 时战场秒数跟着墙钟走，撑满时限的一场就被误记成卡住（lane w54-det 改）
const HANG_PAD_S := 30.0
const LIMIT_S := 900.0
## 物理帧率：本场的时限量的是「战场经过秒数」，一物理帧推进 1/tps 秒——帧率调高只让一场跑得快，
## 场内的秒数不变（Engine.physics_ticks_per_second 是运行期的量，不改产品）。
const PROBE_TPS := 120
const DEFAULT_SEEDS := [11, 23, 37, 41, 53, 67, 79, 83, 97, 101, 113, 127,
	139, 149, 157, 163, 173, 181, 191, 199, 211, 223, 227, 233]
## pending_battle 里给全局随机流的种子键（同 WorldMap.BATTLE_SEED_KEY；WorldMap 带 autoload，-s 工具 preload 不得，照抄键名，
## 对不上时 WorldMap._battle_seeded 为假、本工具判红）
const BATTLE_SEED_KEY := "battle_seed"

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
## 开了场却没按种子播全局流的场数（> 0 = 键名对不上 WorldMap，复跑漂移量的就不是种子了）
var _unseeded := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = PROBE_TPS
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_fleet = root.get_node("Fleet")
	_gm = root.get_node("GameManager")
	_parse_args()
	if _off:
		CS.set_on("yashan_breakout", false)
	if _no_fire:
		CS.set_on("yashan_fire_ship", false)
	# --fps-only：帧时那一档单独走（带窗口量一场，脚本驾驶 push 会改帧负载；不动产品逻辑）
	if OS.get_cmdline_user_args().has("--fps-only"):
		await _fps_run()
		quit(0)
		return
	var seeds: Array = _seeds if not _seeds.is_empty() else DEFAULT_SEEDS
	seeds = seeds.slice(0, mini(_n, seeds.size()))
	var cfg := "%s crew=%d ship=%s breakout=%s fire=%s" % [
		"off" if _off else "on", _crew, _ship_type, str(CS.on("yashan_breakout")), str(CS.on("yashan_fire_ship"))]
	var fixed := await _fixed_step()
	var first := await _sweep(seeds)
	var second := await _sweep(seeds)
	# 逐场比两样：冲没冲出、怎么收的（exit / timeup / flee / lose…）——同是冲出、一趟出港嘴一趟撑满时限，也算这一场分了岔
	var drift := 0
	for i in mini(first.size(), second.size()):
		if first[i] != second[i]:
			drift += 1
			print("  漂移 sd=%d：%s/%s → %s/%s" % [int(seeds[i]), str(first[i][0]), str(first[i][1]),
				str(second[i][0]), str(second[i][1])])
	var out_n := 0
	var in_n := 0
	var hang := 0
	for row in first:
		var r: Variant = row[0]
		if r == null:
			hang += 1
		elif bool(r):
			out_n += 1
		else:
			in_n += 1
	print("WINRATE cfg=%s n=%d out=%d in=%d hang=%d replay-drift=%d" % [cfg, first.size(), out_n, in_n, hang, drift])
	var bad: Array = []
	if hang > 0:
		bad.append("%d 场卡住没收（战场秒数过了本场时限又 %.0f 秒还没收，或墙钟超 %.0f 秒）" % [hang, HANG_PAD_S, LIMIT_S])
	if _unseeded > 0:
		bad.append("%d 场没按种子播全局流（pending_battle.%s 没被 WorldMap 认）" % [_unseeded, BATTLE_SEED_KEY])
	if fixed and drift > 0:
		bad.append("帧步一定、同种子复跑仍翻了 %d 场（有随机源没钉住）" % drift)
	if not bad.is_empty():
		print("%s FAIL：%s" % [TAG, "；".join(bad)])
		quit(1)
		return
	print("%s DONE%s" % [TAG, "" if fixed else "（帧步跟墙钟走：没带 --fixed-fps，replay-drift 只作参考）"])
	quit(0)


## 帧步定不定：开跑前空转几帧，比 process delta 的累计与墙钟——带了 --fixed-fps 时空帧一帧花不到一毫秒、却按 1/fps 记账，
## 一秒的账几十毫秒就记满（帧步一定，同种子两趟应逐场一样）；不带时 delta 就是墙钟，记满一秒要真等一秒
## （炮弹飞行、时限与火船挨没挨上的判定都走 _process，复跑漂移只作参考）。不比「每帧 delta 全等」：
## 开跑时改了物理帧率，引擎的帧步平滑头几帧会微调 delta，定帧步也不全等
func _fixed_step() -> bool:
	await process_frame
	var sim := 0.0
	var t0 := Time.get_ticks_usec()
	while sim < 1.0 and Time.get_ticks_usec() - t0 < 500_000:
		await process_frame
		sim += root.get_process_delta_time()
	return sim >= 2.0 * float(Time.get_ticks_usec() - t0) / 1_000_000.0


## 帧时那一档（DISPLAY 带上窗口跑）：起一场崖山港湾战，不脚本驾驶（帧负载要的是火船最多的那一档），
## 跑够 min_frames 帧后报平均 / p95 毫秒。开关关 / 开两态各跑一次（--off 对照）。
func _fps_run() -> void:
	var min_frames := 1800
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--frames="):
			min_frames = maxi(60, int(str(a).substr(9)))
	_fleet.set("ships", [{"type": _ship_type, "name": "试船", "crew": _crew, "sail_level": 2,
		"armor_level": 1, "cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 70)
	var pb: Dictionary = YashanBattle.setup(300.0, false)
	pb["sea_seed"] = 11
	_gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 5:
		await process_frame
	var frame_ms: Array = []
	var last := Time.get_ticks_usec()
	while frame_ms.size() < min_frames:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		if wm != null and not is_instance_valid(wm):
			wm = null        # 收了战（船沉 / 到时限）：帧时照记，布景引用先摘掉，不再碰它
			break
		if wm != null and bool(wm.get("resolved")):
			break
	_report_fps(frame_ms)
	if wm != null and is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()


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


## 一趟全跑：逐种子开场，返回每场 [冲出来了没有（null = 卡住没跑完）, 怎么收的]
func _sweep(seeds: Array) -> Array:
	var out: Array = []
	for sd in seeds:
		var r: Variant = await _one(int(sd))
		out.append([r, str(get_meta(&"last_how", "hang"))])
	return out


## 一场：起 WorldMap（崖山港湾那场），脚本驾驶逐物理帧，按收战信号或本机释放判收。
## 返回 true = 冲出来了，false = 没冲出来，null = 卡住（墙钟超限还没收）
func _one(sd: int) -> Variant:
	_fleet.set("ships", [{"type": _ship_type, "name": "试船", "crew": _crew, "sail_level": 2,
		"armor_level": 1, "cargo": {}, "durability": 300.0, "max_durability": 300.0}])
	_fleet.set("morale", 70)
	var pb: Dictionary = YashanBattle.setup(300.0, false)
	pb["sea_seed"] = sd
	# 全局随机流的种子：WorldMap._ready 摆敌阵之前拿它播种（见 WorldMap 文件尾「开战播种」）；
	# 错开 sea_seed 一段（+1M），海况与全局流不吃同一串数
	pb[BATTLE_SEED_KEY] = sd + 1_000_000
	_gm.set("pending_battle", pb)
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	# add_child 当场跑完 _ready（敌阵、火船、士气挂件、号令面板都已在树）：一帧不等，先把各私有 rng 盖回种子
	if not bool(wm.get("_battle_seeded")):
		_unseeded += 1                         # 种子没播上（键名对不上 WorldMap）：工具自身的病，末了判红
	_pin_rngs(wm, sd)
	for _i in 3:
		await process_frame
	var own: Node2D = wm.get("ship")
	var rec: Array = []
	var freed := [false]
	wm.battle_finished.connect(func(o: String, d: Dictionary) -> void: rec.append([o, d.duplicate()]))
	if own != null:
		own.tree_exited.connect(func() -> void: freed[0] = true)
	var t0 := Time.get_ticks_msec()
	var frame_ms: Array = []
	var last_tick := Time.get_ticks_msec()
	var cap_s := float(wm.get("_battle_limit_s")) + HANG_PAD_S
	var held_s := 0.0                          # 战场经过秒数（收战那一帧的读数）
	while rec.is_empty() and not freed[0]:
		await physics_frame
		var now := Time.get_ticks_msec()
		if _want_fps:
			frame_ms.append(float(now - last_tick))
		last_tick = now
		if not is_instance_valid(wm):
			break
		held_s = float(wm.get("_battle_elapsed_s"))
		if own != null and is_instance_valid(own):
			_drive(wm, own)
		if held_s > cap_s or float(now - t0) / 1000.0 > LIMIT_S:
			break
	var result: Variant = null
	var how := "hang"
	if not rec.is_empty():
		var d: Dictionary = rec[0][1]
		result = YashanBattle.broke_out(str(rec[0][0]), d)
		if bool(d.get("yashan_out", false)):
			how = "exit"                       # 真冲出了港嘴（世界那一帧判的）
		elif str(rec[0][0]) == "win":
			how = "win"
		elif bool(d.get("parted", false)):
			how = "timeup"                     # 撑满时限两散——也算冲出，但不是从港嘴出去的
		else:
			how = str(rec[0][0])
	print("  BATTLE sd=%d out=%s how=%s t=%.1fs wall=%.1fs" % [sd, str(result), how, held_s,
		float(Time.get_ticks_msec() - t0) / 1000.0])
	self.set_meta(&"last_how", how)
	if _want_fps and not frame_ms.is_empty():
		_report_fps(frame_ms)
	if is_instance_valid(wm):
		wm.set("resolved", true)
		wm.queue_free()
		await process_frame
	_gm.set("pending_battle", {})
	return result


## 各船私有的 rng 按种子起（WorldMap 只管全局流与白刃，见其文件尾「开战播种」）：敌船 _rng 与水火簿 rng、火船（FireShips 下，
## 名字不带 PirateShip_ 前缀，同样是 PirateShip 节点）、本船损伤模型、士气挂件、号令面板。各占一段种子互不相撞：
## 全局流 +1M、火船 +2M / 水火簿 +2.5M、敌船 +3M / 水火簿 +8M、本船 +5M、士气 +6M、面板 +9M（后四段同 p3c 工具）
func _pin_rngs(wm: Node, sd: int) -> void:
	var foes := wm.get_children().filter(func(c): return String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion())
	for i in foes.size():
		_pin_ship(foes[i], sd + 3_000_000 + i * 13_579, sd + 8_000_000 + i * 13_579)
	var host: Node = wm.get_node_or_null("FireShips")
	if host != null:
		var k := 0
		for c in host.get_children():
			_pin_ship(c, sd + 2_000_000 + k * 13_579, sd + 2_500_000 + k * 13_579)
			k += 1
	var own: Node = wm.get("ship")
	var dm = own.call("get_damage_model") if own != null and own.has_method("get_damage_model") else null
	if dm != null:
		dm.set("rng", _rng_of(sd + 5_000_000))
	var morale_hook = wm.get("_morale")
	if morale_hook != null:
		morale_hook.set("rng", _rng_of(sd + 6_000_000))
	for n in wm.get_children():
		if n.is_in_group("nk1_combat_orders") and n.get("_rng") is RandomNumberGenerator:
			n.set("_rng", _rng_of(sd + 9_000_000))


## 一条船（PirateShip 节点）：_rng 与水火簿（EnemyFloodFire，开关开才有）的 rng
func _pin_ship(n: Node, own_seed: int, book_seed: int) -> void:
	n.set("_rng", _rng_of(own_seed))
	var ffb = n.get("flood_fire")
	if ffb is Object and is_instance_valid(ffb):
		(ffb as Object).set("rng", _rng_of(book_seed))


func _rng_of(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## 脚本驾驶：舵压出路（正北），近处有火船就让开一舷。不改产品脚本，只改旗舰这一个节点的朝向 / 帆。
func _drive(wm: Node, own: Node2D) -> void:
	if bool(wm.get("resolved")):
		return
	# 出路：朝本场的出海那一头（WorldMap.yashan_exit_dir：风从哪来、出路就在那头）
	var sea: Vector2 = wm.call("yashan_exit_dir") if wm.has_method("yashan_exit_dir") else Vector2(0, -1)
	if sea.length() < 0.01:
		sea = Vector2(0, -1)
	# 船首 = Vector2.UP.rotated(rotation)；要让它朝 sea：rotation = sea.angle() + PI/2
	var want := sea.angle() + PI * 0.5
	# 让路：看前方 520 px 这条走廊里横着哪几艘火船，挑空隙大的一舷偏出去（按位置预测，
	# 不是每帧看谁近就拨一下——每帧抖舵船走不动）
	var bias := 0.0
	var host: Node = wm.get_node_or_null("FireShips")
	if host != null:
		var ahead := 1e9        # 前方最近那艘火船离出路那条线多远（负号在左、正号在右）
		var aim := 1e9
		for c in host.get_children():
			if not (c is Node2D) or c.is_queued_for_deletion():
				continue
			var n := c as Node2D
			if bool(n.get("fire_spent")):
				continue
			var rel: Vector2 = n.position - own.position
			var along := rel.dot(sea)                 # 往出路那头投（正 = 在前方）
			if along < 0.0 or along > 520.0:
				continue
			var across := rel.dot(Vector2(-sea.y, sea.x))   # 左右横向偏移
			if absf(across) < absf(aim):
				aim = across
				ahead = along
		if absf(aim) < 190.0:                           # 挡在正前方这条带里：往空隙那一舷偏
			bias = signf(aim) if absf(aim) > 1.0 else 1.0
			bias = -bias                                # 往火船的反侧
			want = sea.angle() + PI * 0.5 + bias * deg_to_rad(48.0)
	own.rotation = lerp_angle(own.rotation, want, 0.10)
	own.set("sail_gear", 2)
	# 脚本驾驶不全靠帆：把离开出路那一份的横速拆掉、顺出路补一份推进（真人靠 A/D 与帆，
	# 探针要的是「一个照着出路开的玩家」；速度上限取旗舰 max_speed 的六成）
	var ms := float(own.get("max_speed"))
	var v: Vector2 = own.velocity
	var along_v := v.dot(sea)
	var across_v := v - sea * along_v
	own.velocity = across_v * 0.6 + sea * clampf(maxf(along_v, 0.0) + ms * 0.06, 0.0, ms * 0.6)


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
