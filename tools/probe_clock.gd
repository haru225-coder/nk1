extends RefCounted
## 截图 / 演出探针的推进小工具（lane gd14）：等演出靠信号或状态，上界按墙钟，不再拿帧数顶替时长。
##
## 为什么不能数帧：演出（Tween、墨幕停拍、墨边）按 delta 走，帧数只在某一个帧率下对得上时长。
##   快机（本机 DISPLAY=:2 vsync 关、空载约 235 fps）：12 帧只合 51 ms，海图船况层淡入 0.16 s、进海图绢色面纱
##   0.55 s 都没演完就截——截的是半透明的层，照样 rc=0。满载慢帧（每帧 300 ms，本机多 lane 并跑时实测 3 fps）：
##   36 帧已走 4.8 s 游戏时间（每帧 delta 封顶 0.133 s，见「三」），墨幕（淡入 + 擦出 + 副题 ≈ 1.0 s，停 1.0 s）
##   整幕演完收场，「停拍」截的是墨幕底下的页面——也照样 rc=0（本片压帧实测 14 张停拍图 14 张落空）。
##
## 一、settle(tree, n)：先过 n 帧，再等到「没有在跑的有限补间」，满 max_ms 返回 false（调用方判红）。
##   n 只管按帧走的那部分：call_deferred、Container 排版、游戏代码里的 await process_frame 链、逐帧动画
##   （如 VisionStage 开场按 50 帧演）——这些与帧率无关，按帧等是对的；n 沿用各探针原值，不加大。
##   补间部分不再靠 n：get_processed_tweens() 里 is_running 且非无限循环（get_loops_left() != -1）的都算「在演」，
##   无限循环的呼吸 / 漂动补间不算。静下来要连着两帧都查到 0：tween_callback 里接着起下一段、或 _ready 里
##   await 一帧再起补间（SeaChart 面纱）的，中间那一帧会误判「已静」。
##   SceneTreeTimer 与按 delta 自己数时间的演出（墨幕停拍、VisionStage 齐射）这里看不见——要截它们的某一相位，
##   用 until 按那一相位的状态等。
##
## 二、until(tree, cond, max_ms)：每帧查 cond，成立返回 true，满 max_ms（墙钟）返回 false。
##   等「演到某一相位」（墨幕 _holding、墨边题签还没擦出）与等信号旗标都用它；调用方截完再复核相位没过，
##   过了判红「错过」，不收一张相位不对的图。墨幕停拍另有 wait_hold / holding。
##
## 三、上界按墙钟，要按最慢帧率留量：引擎每帧 delta 最多记 8 个物理步（8/60 ≈ 0.133 s，本片实测
##   OS.delay_msec(400) 下 delta 恒 0.133）——慢过 7.5 fps 时游戏时间比墙钟慢，一段 T 秒的演出要 T ×（每帧墙钟 / 0.133）
##   秒墙钟。WAIT_MS 15 s：这里等的最长一段是墨幕进停拍（约 1.0 s 游戏时间）与补间（最长 0.66 s），
##   1 fps 下也只要约 7.5 s；本片实测最慢的一次静下来 1.1 s（chart_hud 05，3 fps）。
##   〔更正 lane gd20〕「1 fps 也够」只对上面两种等待成立；拿 until + WAIT_MS 等更长演出的探针，上界要按它自己那段算。
##   封顶后每帧游戏时间恒为 8/60 s，相位落在第几帧与压多重无关，压帧加重只会先撞墙钟上界。
##   上界 =（等待上界 ÷ 封顶下所需帧数），单位是墙钟每帧（压帧 + 渲染），gd20 实测（NK1_PROBE_SLOW_MS=150 记帧）：
##     qa_letterbox_copy：等布景自带入战墨边收场 24 帧 / 15 s → ≈ 625 ms（SLOW 400 绿、850 红「15000 ms 内没收场」）
##     letterbox_signal：每幕 SCENE_MS 20 s、最长一幕 28 帧 → ≈ 714 ms（SLOW 500 绿、950 红「墙钟上界先到」，见该探针 _settle）
##     wait_hold（title / chapter / drydock / ending / siege）：10 帧 / 15 s → ≈ 1500 ms（title：SLOW 1300 绿、1800 红「超时」）
##     settle 等补间（chart_hud / patrol_pack / voyage）：4 帧 / 15 s → ≈ 3750 ms；其余 9 支没有撞得到的墙钟等待，只剩进程 timeout
##     〔lane gd24 补 gd18 新接压帧的两支，按同一公式推算、未逐支实测〕qa_yard_transition：等过场落定约 2.4 s（18 帧）/ SETTLE_MS 15 s
##     → ≈ 830 ms，点前就绪 3 帧 / READY_MS 5 s；vision_fill_shots：齐射后最晚一格约 0.9 s（7 帧）/ 15 s → ≈ 2100 ms
##   超上界一律判红并写明「超时 / 没收场 / 墙钟上界先到」，不许绿、也不许报成被测件的错。
##   〔lane gd24〕口径收进本文件，不再各支自写：settle / until / wait_hold（及 combat_probe_stage 的 wait_until /
##   wait_signal / wait_drawn，都经 mark 记账）每次等待记下实走的墙钟 / 帧数 / 游戏时间（每帧 delta 累加）进 last。
##   上界先到时按这段游戏时间分两种（gd20 letterbox_signal 的分法推广）：游戏时间落后墙钟（≤ PRESSURE_RATIO × 墙钟，
##   每帧 delta 封顶才会这样，即慢过 7.5 fps）且不到 STALL_GAME_S＝压帧过重、判不了，不是挂死、不是被测件的错
##   （计入 pressure_hits，--json 带 error=wall_clock）；否则＝被等的东西卡住（真毛病，计入 stall_hits）。
##   只看 STALL_GAME_S 不够：上界本身不比它长的等待（qa_yard 点前就绪 5 s）在正常帧率下游戏时间≈墙钟≈5 s，
##   会在两边来回跳（gd24 变异 M4 实测：墨幕卡死时 12 路里 4 路记成压帧过重）。调用方拿 false 时用 overrun() 取这句话；ShotGate 收尾兜底：本进程有等待撞了上界而没判红
##   （调用方没看返回＝靠多停几帧碰运气）一律补一条红，error 没给时按 pressure_hits 填 wall_clock。
##
## 四、压帧自检：环境变量 NK1_PROBE_SLOW_MS=<毫秒> 时每帧 OS.delay_msec 压帧（gd10 复现手法，与 gd11 同一个变量名）：
##     NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd
##   实现 lane gd18 起收进 ShotGate.frame_pressure（全体有窗口探针一个口径），本文件不再留一份；各探针开场直接调它。

const WAIT_MS := 15000
## --json 的 error 码：墙钟上界先到、压帧过重（lane gd20 letterbox_signal 起用，gd24 各支统一）
const WALL_CLOCK := "wall_clock"
## 探针等的最长一段演出是墨边（带 on_black 的出战约 3.5 s 游戏时间）；上界先到时这段等待实走的游戏时间不到它，
## 算压帧过重（没演完是因为墙钟不够）；过了它仍没等到，是被等的东西卡住。见头注释「三」〔lane gd24〕。
const STALL_GAME_S := 5.0
## 游戏时间 / 墙钟不到这个比才算「压帧」：不封顶时 delta 就是真实帧间隔，两者几乎相等；封顶后（慢过 7.5 fps）游戏时间落后，
## 每帧 300 ms 时约 0.38、1000 ms 时约 0.13。见头注释「三」〔lane gd24〕。
const PRESSURE_RATIO := 0.8

## 最近一次等待的账（mark 写）：timed_out / ms / frames / game_s / max_ms。只记最近一次：探针的等待是串行的。
static var last := {"timed_out": false, "ms": 0, "frames": 0, "game_s": 0.0, "max_ms": 0}
## 本进程里撞上界的等待次数：压帧过重 / 卡住。ShotGate 收尾兜底看它（头注释「三」）
static var pressure_hits := 0
static var stall_hits := 0


## 此刻在跑的有限补间个数（无限循环的不算）。
static func live_tweens(tree: SceneTree) -> int:
	var n := 0
	for t in tree.get_processed_tweens():
		if t.is_valid() and t.is_running() and t.get_loops_left() != -1:
			n += 1
	return n


## 先过 n 帧，再等到连着两帧没有在跑的有限补间；满 max_ms 毫秒（墙钟）返回 false。见头注释「一」。
static func settle(tree: SceneTree, n := 2, max_ms := WAIT_MS) -> bool:
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	var game_s := 0.0
	for _i in n:
		await tree.process_frame
		game_s += tree.root.get_process_delta_time()
	var deadline := Time.get_ticks_msec() + max_ms
	var quiet := 0
	while true:
		quiet = quiet + 1 if live_tweens(tree) == 0 else 0
		if quiet >= 2:
			mark(false, t0, f0, game_s, max_ms)
			return true
		if Time.get_ticks_msec() >= deadline:
			mark(true, t0, f0, game_s, max_ms)
			return false
		await tree.process_frame
		game_s += tree.root.get_process_delta_time()
	return false


## 每帧查 cond，成立返回 true；满 max_ms 毫秒（墙钟）仍不成立返回 false（记进 last，调用方用 overrun() 报）。
static func until(tree: SceneTree, cond: Callable, max_ms := WAIT_MS) -> bool:
	var t0 := Time.get_ticks_msec()
	var f0 := Engine.get_process_frames()
	var game_s := 0.0
	while not cond.call():
		if Time.get_ticks_msec() - t0 >= max_ms:
			mark(true, t0, f0, game_s, max_ms)
			return false
		await tree.process_frame
		game_s += tree.root.get_process_delta_time()
	mark(false, t0, f0, game_s, max_ms)
	return true


## 记一次等待的账（本文件与 combat_probe_stage 的等待都调）；超时按游戏时间分压帧过重 / 卡住计数。
static func mark(timed_out: bool, t0: int, f0: int, game_s: float, max_ms: int) -> void:
	last = {"timed_out": timed_out, "ms": Time.get_ticks_msec() - t0, "frames": Engine.get_process_frames() - f0,
		"game_s": game_s, "max_ms": max_ms}
	if timed_out:
		if _pressure(game_s, int(last.ms)):
			pressure_hits += 1
		else:
			stall_hits += 1


## 一段撞了上界的等待算不算压帧过重：游戏时间落后墙钟、且没走到最长一段演出的留量（头注释「三」）
static func _pressure(game_s: float, ms: int) -> bool:
	return game_s < STALL_GAME_S and game_s <= PRESSURE_RATIO * ms / 1000.0


## 最近一次等待没撞上界（等到了 / 对象释放 / 先收到终止信号）时调，免得调用方读到更早那次的账。
static func mark_none() -> void:
	last = {"timed_out": false, "ms": 0, "frames": 0, "game_s": 0.0, "max_ms": 0}


## 最近一次等待撞上界、且游戏时间落后墙钟又不到 STALL_GAME_S：压帧过重（不是挂死、不是被测件的错）。
static func pressured() -> bool:
	return bool(last.timed_out) and _pressure(float(last.game_s), int(last.ms))


## 最近一次等待撞上界时怎么说（没撞返回 ""）。见头注释「三」〔lane gd24〕。
static func overrun() -> String:
	if not bool(last.timed_out):
		return ""
	if pressured():
		return "墙钟上界 %d ms 先到（%d 帧只走了 %.1f s 游戏时间，最长一段演出约 3.5 s）：压帧过重、判不了，不是挂死；上界见 probe_clock 头注释「三」" % [
			int(last.max_ms), int(last.frames), float(last.game_s)]
	return "卡住：已走 %.1f s 游戏时间（%d 帧、%d ms 墙钟）仍没等到，最长一段演出约 3.5 s" % [
		float(last.game_s), int(last.frames), int(last.ms)]


## 墨幕（UiTransition）是否正停在题签那一拍：淡入 0.32 + 擦出 0.42 + 副题 0.28 后停 T_HOLD 1.0 s，
## 停拍按 delta 自己数，补间看不见，所以按 _holding 状态等。已释放 / 已收场的一律 false。
static func holding(node) -> bool:
	return node != null and is_instance_valid(node) and bool(node.get("_holding")) and not bool(node.get("_done"))


## 等墨幕演到停拍：到了返回 ""；已收场（相位已过）返回「错过」、满 max_ms 返回「超时」。调用方截完再用 holding 复核。
static func wait_hold(tree: SceneTree, node, max_ms := WAIT_MS) -> String:
	var t0 := Time.get_ticks_msec()
	# 条件只捕获弱引用（lane gd17）：墨幕收场自删后再调，直接捕获 node 就报 Lambda capture freed（错过那条路）
	var ref: WeakRef = weakref(node) if node != null and is_instance_valid(node) else null
	var gone := func() -> bool:
		var n = null if ref == null else ref.get_ref()
		return n == null or bool(n.get("_done"))
	if not await until(tree, func() -> bool: return holding(null if ref == null else ref.get_ref()) or gone.call(), max_ms):
		return "超时（%d ms 未到停拍；%s）" % [max_ms, overrun()]
	if not holding(node):
		return "错过（等 %d ms 墨幕已收场，停拍一帧也没等到）" % (Time.get_ticks_msec() - t0)
	return ""
