## 新手上手小笺（lane w54-tutorial）：开局头半小时——头一回进港页、进牙行、开海图、海上遇盗，以及头一回进市舶司或被蒲家记上一笔
## 之后的那个港页——页边各出一张宣纸小笺，一两句讲清这一页怎么用。文案在 data/tutorial_notes.json；弹出、排队、已读借 CombatNotes 那一层
## （同一页里与海战小笺排一个队，一张一张出；已读旗 tutorial_note_<id>，随档走）。
##
## 谁看得到：本机航海日志里一卷存档都没有时新开的一局（同开场过场 Cinematics.want_opening 的口径）。头一回走到要出小笺的地方时定下来、
## 记旗 tutorial_on / tutorial_off（随档走）：老玩家另起一局、读进旧档（两枚都没有）都记 off，此后一张不出；新手存了档再读回来，
## 接着出没看过的。工具 / 探针驱动的主循环不替人定、不写旗（探针要看小笺，自己立 tutorial_on）。
## 开关 CombatSwitches.tutorial_notes（默认开；关 = 一张不出、旗标一枚不写；讲解小笺总开关 combat_notes 关时也不出）。
##
## 几时出：offer 在这一页下挂一个候场小件，等页面静下来（换页题签、抵港挂签、章节卡、过场演完，升章册页、航海日志、船籍簿、船况合上，
## 海战收了）再交给小笺层；没等到场合就散了（alive 不再为真），不排、不记已读，下回再遇照出。排进去以后照旧盯着：场合散了还在排队的
## 撤下，strict 的（海上遇盗那张随事件面板）正出着也收起。不暂停、不吞键，不碰任何账、不掷骰。
## 脚本里不写 autoload 标识符（-s 工具 preload 进来也编得过），GameState / SaveLoad 按路径取。
extends Node

const _Notes := preload("res://scripts/ui/CombatNotes.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

const SWITCH := "tutorial_notes"
## 这一局定下来的：看新手小笺 / 不看
const FLAG_ON := "tutorial_on"
const FLAG_OFF := "tutorial_off"
## 候场小件的名字：前缀 + 小笺 id（同一页同一张只挂一个）
const WAIT_PREFIX := "TutorialWait_"
## 多久看一眼；交给小笺层之前至少等这么久（进海图的绢色淡入、进港的墨刷匾先落定）
const POLL_S := 0.1
const SETTLE_S := 0.6
## 页面上盖着东西：换页题签、抵港挂签（组）；章节卡、过场（脚本类名，不 preload）；升章册页、航海日志（host 上的成员，在树就算）；
## 船籍簿、海图船况（host 上的浮层，看得见才算）；海战（host 下挂着带 battle_finished 的场）
const BUSY_GROUPS := ["nk1_ui_transition", "nk1_port_banner"]
const BUSY_CLASSES := ["ChapterCard", "CutscenePlayer"]
const BUSY_HOSTS := ["_chapter_host", "_save_host"]
const BUSY_LAYERS := ["_ledger_layer", "_condition_layer"]

var host: Node = null
var id := ""
## 场合还在不在（空 = 只看 host）；strict：场合散了正出着的也收起
var alive := Callable()
var strict := false
var _t := 0.0
var _acc := 0.0
var _pushed := false


# ── 谁看得到（纯函数，探针可不建节点直接验）──────────────

static func _node(path: String) -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root.get_node_or_null(path) if ml is SceneTree else null


static func _state() -> Node:
	return _node("GameState")


## 本机航海日志里有没有一卷存档（同 Cinematics._any_save：正本或副抄在就算）
static func any_save() -> bool:
	var sl := _node("SaveLoad")
	if sl == null or not sl.has_method("has_save"):
		return false
	var slots := int((sl.get_script() as Script).get_script_constant_map().get("SLOTS", 3))
	for slot in range(1, slots + 1):
		if bool(sl.call("has_save", slot)):
			return true
	return false


## 主循环是游戏自己的，不是 -s 工具 / 巡检脚本驱动的 SceneTree（同 Cinematics.live 的后一半）
static func _real_run() -> bool:
	var ml := Engine.get_main_loop()
	return ml != null and ml.get_script() == null


## 定下这一局看不看：本机一卷存档都没有 = 新手，记 tutorial_on；有存档记 tutorial_off。返回看不看
static func decide(has_save: bool) -> bool:
	var gs := _state()
	if gs == null or not gs.has_method("set_flag"):
		return false
	gs.call("set_flag", FLAG_OFF if has_save else FLAG_ON)
	return not has_save


## 这一局看不看新手小笺：开关开着、已定 on；还没定的，游戏自己的主循环此刻按本机存档定下（工具里不定、不写旗）
static func active() -> bool:
	if not _Switches.on(SWITCH):
		return false
	var gs := _state()
	if gs == null or not gs.has_method("has_flag"):
		return false
	if bool(gs.call("has_flag", FLAG_ON)):
		return true
	if bool(gs.call("has_flag", FLAG_OFF)) or not _real_run():
		return false
	return decide(any_save())


## 这一张该不该出：新手那一本里有它、这一局看小笺、开关全开、还没看过
static func want(note_id: String) -> bool:
	return _Notes.tutorial_table().has(note_id) and active() and _Notes.want(note_id)


## 页面静了没有（见 BUSY_*）
static func quiet(h: Node) -> bool:
	if h == null or not is_instance_valid(h) or not h.is_inside_tree():
		return false
	for g in BUSY_GROUPS:
		if not h.get_tree().get_nodes_in_group(g).is_empty():
			return false
	for c in h.get_children():
		var scr = c.get_script()
		if (scr is Script and (scr as Script).get_global_name() in BUSY_CLASSES) or c.has_signal("battle_finished"):
			return false
	for k in BUSY_HOSTS:
		var n = h.get(k)
		if is_instance_valid(n) and n is Node and (n as Node).is_inside_tree():
			return false
	for k in BUSY_LAYERS:
		var n = h.get(k)
		if is_instance_valid(n) and n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return false
	return true


## 排一张：该出（want）、这一页没挂着同一张的候场小件、小笺层上也没出着 / 排着它，就挂一个候场小件。返回挂上没有
static func offer(h: Node, note_id: String, p_alive := Callable(), p_strict := false) -> bool:
	if h == null or not is_instance_valid(h) or not h.is_inside_tree() or h.is_queued_for_deletion():
		return false
	if not want(note_id):
		return false
	var old := h.get_node_or_null(WAIT_PREFIX + note_id)
	if old != null and not old.is_queued_for_deletion():
		return false
	var lay := _Notes.layer_of(h)
	if lay != null and (str(lay.call("current")) == note_id or (lay.call("pending") as PackedStringArray).has(note_id)):
		return false
	var n: Node = (load("res://scripts/ui/TutorialNotes.gd") as GDScript).new()
	n.name = WAIT_PREFIX + note_id
	n.set("host", h)
	n.set("id", note_id)
	n.set("alive", p_alive)
	n.set("strict", p_strict)
	h.add_child(n)
	return true


## 让路：这一页上别的新手小笺，正出着的收起、还排着的撤下、还在候场的不等了（海上遇盗等不得，先出它）。海战小笺不动
static func clear_others(h: Node, keep: String) -> void:
	if h == null or not is_instance_valid(h):
		return
	var lay := _Notes.layer_of(h)
	for other in _Notes.tutorial_table().keys():
		if str(other) == keep:
			continue
		if lay != null:
			lay.call("withdraw", str(other))
		var w := h.get_node_or_null(WAIT_PREFIX + str(other))
		if w != null:
			w.queue_free()


# ── 候场小件 ────────────────────────────────────────

func _process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		queue_free()
		return
	_t += delta
	_acc += delta
	if _acc < POLL_S:
		return
	_acc = 0.0
	var on := alive.is_null() or bool(alive.call())
	var lay := _Notes.layer_of(host)
	if _pushed:
		var cur := lay != null and str(lay.call("current")) == id
		var queued := lay != null and (lay.call("pending") as PackedStringArray).has(id)
		if not cur and not queued:
			queue_free()  # 出过了（已读）、或被别处撤下
		elif not on and (queued or strict):
			lay.call("withdraw", id)
			queue_free()
		return
	if not on or not want(id):
		queue_free()  # 场合散了、看过了、开关关了：不排，下回再遇照出
		return
	if _t < SETTLE_S or not quiet(host):
		return
	_pushed = _Notes.offer(host, id)
	if not _pushed:
		queue_free()
