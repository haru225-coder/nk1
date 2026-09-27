extends RefCounted
## 有窗口探针用真海战布景（WorldMap + pending_battle）时的两件防挂死小工具（lane gd10）。
## 接的探针：combat_vfx_probe / combat_wire_probe / vision_letterbox_probe / qa_letterbox_copy_probe。
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
## 二、等信号 / 等条件带帧数上界：wait_signal / wait_until。
##   CombatLetterbox 的 caption_shown 只在题签真擦出后发：题签前被新墨边顶掉（_abort）不发；墨边挂在布景下、
##   随布景一起被释放（不走 _abort）则 caption_shown 与 finished 都不发——裸 await 一律挂死（lane gd10 复现）。
##   不在 _abort 里补发：题签没演就说「题签已出」是假信号，截图探针会把一张没题签的图当题签图收下；也管不到随父释放那条路。
##   这里改成「帧数上界 + 断言最后状态」：对象被释放立刻返回 false，否则最多等 max_frames 帧；调用方拿 false 判红收尾。
##
## wm / obj 形参故意不写类型：已释放的实例传给带类型的形参当场 SCRIPT ERROR、协程中断——正是要防的挂死。

const FIRE_FROZEN := INF
## 默认上界：墨边最长一幕（带 on_black 的出战）约 3.5 s，本机约 235 fps ≈ 820 帧；留足余量给快机与慢帧
const WAIT_FRAMES := 6000


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


## 每帧查 cond，成立返回 true；满 max_frames 帧仍不成立返回 false。
static func wait_until(tree: SceneTree, cond: Callable, max_frames := WAIT_FRAMES) -> bool:
	var frames := 0
	while not cond.call():
		if frames >= max_frames:
			return false
		await tree.process_frame
		frames += 1
	return true


## 等 obj 的无参信号 sig：收到返回 true；obj 被释放或满 max_frames 帧返回 false。
static func wait_signal(tree: SceneTree, obj, sig: StringName, max_frames := WAIT_FRAMES) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	var hit := [false]
	var cb := func() -> void: hit[0] = true
	obj.connect(sig, cb, Object.CONNECT_ONE_SHOT)
	await wait_until(tree, func() -> bool: return hit[0] or not is_instance_valid(obj), max_frames)
	if is_instance_valid(obj) and obj.is_connected(sig, cb):
		obj.disconnect(sig, cb)
	return hit[0]
