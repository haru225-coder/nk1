extends RefCounted
## 有窗口探针用真海战布景（WorldMap + pending_battle）时的防挂死 / 按演出推进小工具（lane gd10 立；三、收尾 lane gd12；gd11 改按时长）。
## 接的探针：combat_vfx_probe / combat_wire_probe / vision_letterbox_probe / qa_letterbox_copy_probe / qa_wire_vision_screenshots；
## 收尾信号契约的定向探针：letterbox_signal_probe。
##
## 一、布景不自己结算：freeze_enemy_fire(wm)，在 root.add_child(wm) 之后当帧调（WorldMap._ready 已同步刷好敌船）。
##   WorldMap 是真海战：敌船 3.5 s 首轮齐射、此后 3 s 一轮，探针不开船、不回炮，旗舰被击沉 →
##   Ship._sink_ship → WorldMap._battle_exit("lose") → 自起一副出战墨边 + queue_free()。满载慢帧下
##   combat_wire 的帧表里就能沉（lane gd10 复现 2/6）；探针再碰 wm 报 previously freed、_run 中断、quit 没人调 → 挂死。
##   三种冻法里选「只冻敌船开炮」：
##   - 冻结算（wm.resolved = true）：_battle_exit 成了空操作，但炮照打、旗舰照掉血掉货、HUD 数字照变，
##     还把 resolved 这个被测状态本身改掉了（letterbox 两支探针正要断言它），判「没结算」成了自证。
##   - 抬旗舰耐久：只把沉船往后推，慢帧再慢一点照样沉；还改 Fleet 数据与 HUD 读数。
##   - 冻开炮：探针里布景唯一的伤害来源就是敌炮（玩家不开炮、海战固定晴天无风暴伤），掐掉源头结算就不会自己发生；
##     敌船照常航行、可被钩住，WorldMap / BoardingStage / 墨边照常逐帧跑——combat_* 要的接舷演出不受影响
##     （整棵 wm 设 PROCESS_MODE_DISABLED 会连挂在它下面的 BoardingStage 一起冻住，所以不用那个）。
##   收尾用 standing_fail(wm)：布景仍在且未结算才算数；万一被释放照判红，不挂死。
##
## 二、等信号 / 等条件带墙钟上界：wait_signal / wait_until。
##   CombatLetterbox 的 caption_shown 只在题签真擦出后发：题签前被新墨边顶掉（_abort）不发；墨边挂在布景下、
##   随布景一起被释放（不走 _abort）则 caption_shown 与 finished 都不发——裸 await 一律挂死（lane gd10 复现）。
##   不在 _abort 里补发：题签没演就说「题签已出」是假信号，截图探针会把一张没题签的图当题签图收下；也管不到随父释放那条路。
##   这里改成「上界 + 断言最后状态」：对象被释放立刻返回 false，否则最多等 max_ms 毫秒；调用方拿 false 判红收尾。
##   上界按墙钟（lane gd11；gd10 原是 6000 帧）：演出按 delta 走，帧上界随帧率伸缩——235 fps 下 25 s、压到 7 fps 下 14 min。
##   墨边的 finished 是终止信号、每条收尾路径都恰好发一次（lane gd12，见 CombatLetterbox 头注释），所以等进度信号时
##   finished 先来就立刻返回 false，不必干等到上界；上界只兜「演出本身卡住」。
##
## 三、收尾一条路：teardown(tree, wm, gm)。探针正常收尾、等不到信号的 _bail、墨边没上场的早退都先走它再出报告：
##   场上每副墨边走 _abort（与被新墨边顶掉同一条，经 _finish 发 finished，挂着的等待方都醒）→ 放掉布景 → 清战况。
##   _bail 另带 error=NO_SIGNAL 进 --json，与「张数不足」等普通红分得开（ShotGate.finish_* 的 error 参数）。
##
## 四、截「演出到了某一相位」的那一帧：shot_when（lane gd11）。
##   原先探针按帧记账（combat_vfx 的 40 / 20 / 45 帧），帧数只在某一个帧率下才对得上演出：本机 vsync 关约 235 fps 时
##   132 帧只盖 1.2 s，入战墨边（约 3.2 s）还没收，「01_naval_hud」截的是墨边；满载慢帧下 20 帧就过了接舷整幕，
##   「02_boarding_stage」截的是题签已收的空海面——两边都照样 rc=0、张数齐，假绿（gd11 压帧实测）。
##   改成：每帧画完（frame_post_draw）后在已画出的状态上查 want，成立就当帧截 root——截到的正是满足 want 的那一帧；
##   gone 成立（该相位已过：题签换了 / 题签层收场 / 布景被释放）立刻判红「错过」，满 max_ms 判红「超时」。
##   截完空两帧再返回：存 PNG 阻塞的那段墙钟会整笔记进下一帧的 delta（process 的 delta 不封顶），调用方紧接着起的
##   计时器 / 补间（_board_enemy 的 0.42 s、preview_boarding 的 0.55 s）会被吃掉这一段（gd11 实测 0.55 s 只剩约 0.2 s）。
##   第一帧把这笔长 delta 消化掉，第二帧起 delta 恢复正常。这两帧只能按帧：要消化的是「一帧的 delta」，与帧率无关。
##
## 五、压帧自检（lane gd11 立）：环境变量 NK1_PROBE_SLOW_MS=<毫秒> 时每帧 OS.delay_msec 压帧，探针照常跑，用来证明推进与帧率无关：
##     NK1_PROBE_SLOW_MS=160 DISPLAY=:2 godot --path . -s res://tools/combat_vfx_probe.gd
##   实现 lane gd18 起收进 ShotGate.frame_pressure（全体有窗口探针一个口径），本文件不再留一份；各探针开场直接调它。
##
## 六、lambda 不直接捕获会被释放的节点（lane gd17）。wait_until / shot_when 的条件每帧都调，节点在等待里被释放
##   （墨边演完自删、布景结算释放）后再调一次，Godot 就报 `Lambda capture at index N was freed. Passed "null" instead.`
##   ——判定照旧（null 进 is_instance_valid 为 false），但每次跑都多两行引擎 ERROR（gd15 待议 1）。
##   写法：捕获 `weakref(node)`，条件里 `ref.get_ref()` 取（已释放得 null，本文件的 helper 都收 null）；下标盒子 [false]
##   照旧直接捕获（Array 是值容器，不会被释放）。watch_captures() / captures_freed() 在探针进程里挂一个 Logger 数这类
##   ERROR（只数调用栈落在 res://tools/ 的），探针收尾断言为 0，防回退。
##
## wm / obj / parent 形参故意不写类型：已释放的实例传给带类型的形参当场 SCRIPT ERROR、协程中断——正是要防的挂死。

const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const FIRE_FROZEN := INF
## _bail 的 --json error 码：等的信号没来（墨边提前终结，或到上界）
const NO_SIGNAL := "no_signal"
## 默认墙钟上界：等的最长一幕是墨边（带 on_black 的出战约 3.5 s）。delta 不封顶，压帧 / 慢机下游戏时间照墙钟走，
## 所以上界与帧率无关；留约 5 倍给满载机、hitstop 降速与截图存盘。
const WAIT_MS := 20000
## 帧数上界：本文件的等待已改墙钟（lane gd11），只留给 letterbox_signal_probe 在它自己的墙钟 deadline 之外当兜底
const WAIT_FRAMES := 6000
## 同 BoardingStage.GROUP
const BOARD_GROUP := "nk1_boarding_stage"


## 把 wm 下所有敌船（节点名 PirateShip* 前缀，同 WorldMap._is_live_pirate）的开炮计时冻住；返回冻住的艘数。
static func freeze_enemy_fire(wm) -> int:
	var n := 0
	if wm == null or not is_instance_valid(wm):
		return n
	for c in wm.get_children():
		if String(c.name).begins_with("PirateShip") and "fire_timer" in c:
			c.set("fire_timer", FIRE_FROZEN)
			n += 1
	return n


## 布景仍在且未自行结算 → ""；否则返回一句红因（写明是布景问题，不是被测件回归），调用方记进 fails。
static func standing_fail(wm) -> String:
	if wm == null or not is_instance_valid(wm) or wm.is_queued_for_deletion():
		return "布景 WorldMap 在探针拆场前已自行结算释放（冻开炮失效，不是被测件回归）"
	if bool(wm.get("resolved")):
		return "布景海战在探针演示中自行结算（冻开炮失效，不是被测件回归）"
	return ""


## 每帧查 cond，成立返回 true；满 max_ms 毫秒（墙钟）仍不成立返回 false。
static func wait_until(tree: SceneTree, cond: Callable, max_ms := WAIT_MS) -> bool:
	var deadline := Time.get_ticks_msec() + max_ms
	while not cond.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return true


## 等 obj 的无参信号 sig：收到返回 true；obj 被释放、先收到终止信号 stop（缺省 finished）、或满 max_ms 毫秒返回 false。
static func wait_signal(tree: SceneTree, obj, sig: StringName, max_ms := WAIT_MS, stop := &"finished") -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var hit := [false]
	var ended := [false]
	var cb := func() -> void: hit[0] = true
	var cb_stop := func() -> void: ended[0] = true
	obj.connect(sig, cb, Object.CONNECT_ONE_SHOT)
	var watch_stop: bool = stop != sig and obj.has_signal(stop)
	if watch_stop:
		obj.connect(stop, cb_stop, Object.CONNECT_ONE_SHOT)
	var ref: WeakRef = weakref(obj)  # 不直接捕获 obj：等待中被释放后再调条件会报 Lambda capture freed（头注释「六」）
	await wait_until(tree, func() -> bool: return hit[0] or ended[0] or ref.get_ref() == null, max_ms)
	if is_instance_valid(obj):
		if obj.is_connected(sig, cb):
			obj.disconnect(sig, cb)
		if watch_stop and obj.is_connected(stop, cb_stop):
			obj.disconnect(stop, cb_stop)
	return hit[0]


## 探针收尾（正常 / _bail / 早退同走这里）：场上墨边一律 _abort（发 finished、带 on_black 的先补调），
## 布景没释放就放掉，给了 gm 就清 pending_battle。之后调用方照常出报告、quit。
static func teardown(tree: SceneTree, wm, gm = null) -> void:
	for n in tree.get_nodes_in_group(Letterbox.GROUP):
		n.call("_abort")
	if wm != null and is_instance_valid(wm) and not wm.is_queued_for_deletion():
		wm.queue_free()
	if gm != null and is_instance_valid(gm):
		gm.set("pending_battle", {})


## 等到某一帧画出来时 want 成立：返回 ""，调用方当帧（不再 await）截 root 纹理即那一帧。
## gone 成立返回「错过」、满 max_ms 返回「超时」（都带已等毫秒数），调用方记红收尾。
static func wait_drawn(tree: SceneTree, want: Callable, gone := Callable(), max_ms := WAIT_MS) -> String:
	var t0 := Time.get_ticks_msec()
	while true:
		await tree.process_frame
		await RenderingServer.frame_post_draw
		if want.call():
			return ""
		var waited := Time.get_ticks_msec() - t0
		if gone.is_valid() and gone.call():
			return "错过（等 %d ms 该相位已过，一帧也没画到）" % waited
		if waited >= max_ms:
			return "超时（%d ms 未到该相位）" % max_ms
	return ""


## 等到画出满足 want 的那一帧就当帧调 shoot（调用方传 ShotGate.shot 的闭包：本文件不接 shot_gate，不是截图门禁）；
## 等不到把「label 没截到该相位：…」记进 fails、返回 false。截完空两帧再返回，理由见头注释「四」。
static func shot_when(tree: SceneTree, label: String, fails: Array, shoot: Callable,
		want: Callable, gone := Callable(), max_ms := WAIT_MS) -> bool:
	var why := await wait_drawn(tree, want, gone, max_ms)
	if why != "":
		fails.append("%s 没截到该相位：%s" % [label, why])
		print("  FAIL %s 没截到该相位：%s" % [label, why])
		return false
	shoot.call()
	await tree.process_frame
	await tree.process_frame
	return true


## parent 下正在演的接舷题签层（BoardingStage；已收场 / 被顶掉的不算），没有返回 null。
static func boarding_stage(tree: SceneTree, parent) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null
	for n in tree.get_nodes_in_group(BOARD_GROUP):
		if n.get_parent() == parent and not n.is_queued_for_deletion() and not bool(n.get("_done")):
			return n
	return null


## parent 下接舷题签此刻画着的题名（接舷 / 夺船 / 脱钩 / 白刃）与题签不透明度；没有题签层返回 ["", 0.0]。
static func board_caption(tree: SceneTree, parent) -> Array:
	var st := boarding_stage(tree, parent)
	if st == null:
		return ["", 0.0]
	var title = st.get("_title")
	var slip = st.get("_slip")
	if title == null or slip == null:
		return ["", 0.0]
	return [str(title.text), float(slip.modulate.a)]


## parent 下正在演的墨边（CombatLetterbox；WorldMap 入战那副挂在 wm 下），没有返回 null。
static func letterbox_under(tree: SceneTree, parent) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null
	for n in tree.get_nodes_in_group(Letterbox.GROUP):
		if n.get_parent() == parent and not n.is_queued_for_deletion():
			return n
	return null


## 开始数本进程里探针脚本的「Lambda capture … was freed」引擎 ERROR（头注释「六」）；重复调只挂一个。
static func watch_captures() -> void:
	if _capture_log == null:
		_capture_log = _CaptureLog.new()
		OS.add_logger(_capture_log)


## 摘下 watch_captures 挂的 Logger，返回期间数到的次数；没挂过返回 0。探针收尾（报告前）调一次，断言为 0。
static func captures_freed() -> int:
	if _capture_log == null:
		return 0
	OS.remove_logger(_capture_log)
	var n := _capture_log.hits
	_capture_log = null
	return n


static var _capture_log: _CaptureLog = null


class _CaptureLog extends Logger:
	var hits := 0

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if not ("Lambda capture" in rationale or "Lambda capture" in code):
			return
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				if bt.get_frame_file(i).begins_with("res://tools/"):
					hits += 1
					return

