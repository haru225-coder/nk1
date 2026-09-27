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
##   超上界一律判红并写明「超时 / 没收场 / 墙钟上界先到」，不许绿、也不许报成被测件的错。
##
## 四、压帧自检：环境变量 NK1_PROBE_SLOW_MS=<毫秒> 时每帧 OS.delay_msec 压帧（gd10 复现手法，与 gd11 同一个变量名）：
##     NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path . -s res://tools/qa_title_probe.gd
##   实现 lane gd18 起收进 ShotGate.frame_pressure（全体有窗口探针一个口径），本文件不再留一份；各探针开场直接调它。

const WAIT_MS := 15000


## 此刻在跑的有限补间个数（无限循环的不算）。
static func live_tweens(tree: SceneTree) -> int:
	var n := 0
	for t in tree.get_processed_tweens():
		if t.is_valid() and t.is_running() and t.get_loops_left() != -1:
			n += 1
	return n


## 先过 n 帧，再等到连着两帧没有在跑的有限补间；满 max_ms 毫秒（墙钟）返回 false。见头注释「一」。
static func settle(tree: SceneTree, n := 2, max_ms := WAIT_MS) -> bool:
	for _i in n:
		await tree.process_frame
	var deadline := Time.get_ticks_msec() + max_ms
	var quiet := 0
	while true:
		quiet = quiet + 1 if live_tweens(tree) == 0 else 0
		if quiet >= 2:
			return true
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return false


## 每帧查 cond，成立返回 true；满 max_ms 毫秒（墙钟）仍不成立返回 false。
static func until(tree: SceneTree, cond: Callable, max_ms := WAIT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + max_ms
	while not cond.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return true


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
		return "超时（%d ms 未到停拍）" % max_ms
	if not holding(node):
		return "错过（等 %d ms 墨幕已收场，停拍一帧也没等到）" % (Time.get_ticks_msec() - t0)
	return ""
