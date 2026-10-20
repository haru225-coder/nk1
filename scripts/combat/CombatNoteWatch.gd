## 海战里的旁注小笺观察件（lane w54-polish）：WorldMap._setup_combat 挂一个，每 POLL_S 秒看一眼场面，
## 哪样新玩法头一回露面就排一张 CombatNotes 小笺（看过的、开关关着的先由 CombatNotes.want 挡掉）。
## 只读场面：不改任何数、不掷骰、不碰随机流（胜率工具同种子复跑照旧逐场一致），随 WorldMap 一起释放。
## 总开关 combat_notes 关着时 attach 不挂，场上多不出一个节点。
##
## 开场（START_S 秒后，入战墨边快揭开时）按 START_ORDER 排：护航将令（护航上阵了）→ 崖山（崖山那一场）→
## 风与潮 → 号令 → 炮位与装填（旗舰挂了装填簿）→ 敌情 → 职事（船上雇着六职事里的哪一个）。其后逐样等它第一次露面：
##   接舷：最近一艘敌船贴到 BOARD_DISTANCE × BOARD_NEAR 以内，或已钩住；白刃三决断：拍板层在等人拍；
##   劝降：有敌船阵脚动摇（士气簿 shaken 以下、没降）；士气：我方士气簿掉出「稳」；砍钩：有敌将改打法「接舷企图」；
##   水与火：敌船起火或进水 FLOOD_MIN 以上；张湿毡：我船起火；火攻：装填侧重头一回离开均装、火攻又在轮换里；
##   追击：有敌将转「脱离」，或已有一艘遁走。
## 场面一律按名字 / 组 / 属性鸭子型取（PirateShip 前缀、nk1_melee_decision、nk1_combat_orders、船节点士气 meta），
## 不 preload 那几件，它们改了内部也只是这一张小笺不出。
extends Node

const _Notes := preload("res://scripts/ui/CombatNotes.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

const NODE_NAME := "CombatNoteWatch"
const POLL_S := 0.25
const START_S := 2.0
const START_ORDER := ["escort", "yashan", "sea", "orders", "gunnery", "intel", "roles"]
## 打仗时各管一样的六职事（Crew 职事 id；data/combat_phases.json officer_effects 同这六样）
const ROLES := ["huozhang", "duogong", "zongguan", "yiren", "tongshi", "zashi"]
## 接舷那张：贴到够距的这么多倍就出（人还没按 G，先知道 G 是干什么的）；WorldMap 读不到常量按 BOARD_FALLBACK
const BOARD_NEAR := 1.5
const BOARD_FALLBACK := 140.0
const SHAKEN := ["shaken", "wavering", "routing"]
const FLOOD_MIN := 0.05
## 士气簿写在船节点上的 meta 键（同 CombatStatusHud.MORALE_META）
const MORALE_META := &"nk1_combat_morale"

var world: Node = null
var _acc := 0.0
var _t := 0.0
var _started := false


## 挂到海战场上（已挂的沿用）；总开关关、world 无效返回 null
static func attach(w: Node) -> Node:
	if w == null or not is_instance_valid(w) or not _Switches.on(_Notes.SWITCH):
		return null
	var old := w.get_node_or_null(NODE_NAME)
	if old != null and not old.is_queued_for_deletion():
		return old
	var n: Node = (load("res://scripts/combat/CombatNoteWatch.gd") as GDScript).new()
	n.name = NODE_NAME
	n.set("world", w)
	w.add_child(n)
	return n


func _process(delta: float) -> void:
	if world == null or not is_instance_valid(world) or world.get("resolved") == true:
		return
	_t += delta
	_acc += delta
	if _acc < POLL_S:
		return
	_acc = 0.0
	if not _started:
		if _t < START_S:
			return
		_started = true
		for id in START_ORDER:
			if _start_ready(id):
				_Notes.offer(world, id)
	poll()


## 开场那几张各自露没露面
func _start_ready(id: String) -> bool:
	match id:
		"escort":
			var wing := world.get_node_or_null("EscortWing")
			return wing != null and wing.has_method("escort_nodes") and not (wing.call("escort_nodes") as Array).is_empty()
		"yashan":
			return world.get("_yashan_on") == true
		"gunnery":
			var ship = world.get("ship")
			return ship is Object and is_instance_valid(ship) and ship.get("battery") != null
		"intel":
			return not live_enemies().is_empty()
		"roles":
			var crew := get_node_or_null("/root/Crew")
			if crew == null or not crew.has_method("level_of"):
				return false
			for r in ROLES:
				if int(crew.call("level_of", r)) > 0:
					return true
			return false
	return true


## 看一眼场面（探针可直接调；开场那几张由 _process 按时排）
func poll() -> void:
	var ship = world.get("ship")
	var foes := live_enemies()
	if _Notes.want("boarding") and (world.get("boarding") == true or _nearest(ship, foes) <= _board_reach() * BOARD_NEAR):
		_Notes.offer(world, "boarding")
	if _Notes.want("melee_decision") and _deciding():
		_Notes.offer(world, "melee_decision")
	if _Notes.want("parley"):
		for e in foes:
			if e.get("struck") != true and str(_morale_of(e).get("state", "")) in SHAKEN:
				_Notes.offer(world, "parley")
				break
	if _Notes.want("morale") and str(_morale_of(ship).get("state", "")) in SHAKEN:
		_Notes.offer(world, "morale")
	if _Notes.want("cut_grapple") and _any_captain(foes, "board"):
		_Notes.offer(world, "cut_grapple")
	if _Notes.want("flood_fire"):
		for e in foes:
			var ff = e.call("flood_fire_state") if e.has_method("flood_fire_state") else {}
			if ff is Dictionary and (float(ff.get("fire", 0.0)) > 0.0 or float(ff.get("flood", 0.0)) >= FLOOD_MIN):
				_Notes.offer(world, "flood_fire")
				break
	if _Notes.want("wet_felt") and _own_fire(ship) > 0.0:
		_Notes.offer(world, "wet_felt")
	if _Notes.want("fire_load") and _fire_load_picked():
		_Notes.offer(world, "fire_load")
	if _Notes.want("pursue"):
		var gone = world.get("_enemies_escaped")
		if _any_captain(foes, "disengage") or (gone is int and int(gone) > 0):
			_Notes.offer(world, "pursue")


## 场上活着的敌船（同 WorldMap._is_live_pirate 的名字口径：PirateShip 前缀、船体未尽；护航 EscortShip_、火船 FireShip_ 不算）
func live_enemies() -> Array:
	var out: Array = []
	for c in world.get_children():
		if c is Node2D and String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion():
			var hp = c.get("hull_hp")
			if (hp is float or hp is int) and float(hp) > 0.0:
				out.append(c)
	return out


func _board_reach() -> float:
	var scr = world.get_script()
	if scr is Script:
		var v = (scr as Script).get_script_constant_map().get("BOARD_DISTANCE", BOARD_FALLBACK)
		if v is float or v is int:
			return float(v)
	return BOARD_FALLBACK


static func _nearest(ship, foes: Array) -> float:
	if not (ship is Node2D) or not is_instance_valid(ship):
		return INF
	var best := INF
	for e in foes:
		best = minf(best, (e as Node2D).global_position.distance_to((ship as Node2D).global_position))
	return best


func _deciding() -> bool:
	for n in get_tree().get_nodes_in_group("nk1_melee_decision"):
		if not n.is_queued_for_deletion() and n.has_method("waiting") and bool(n.call("waiting")):
			return true
	return false


static func _morale_of(n) -> Dictionary:
	if not (n is Object) or not is_instance_valid(n) or not (n as Object).has_meta(MORALE_META):
		return {}
	var m = (n as Object).get_meta(MORALE_META)
	return m if m is Dictionary else {}


static func _any_captain(foes: Array, state: String) -> bool:
	for e in foes:
		var cap = e.get("captain")
		if cap is Object and is_instance_valid(cap) and str(cap.get("state")) == state:
			return true
	return false


static func _own_fire(ship) -> float:
	if not (ship is Object) or not is_instance_valid(ship):
		return 0.0
	var dm = ship.get("damage_model")
	if not (dm is Object):
		return 0.0
	var ff = dm.get("ff")
	if ff is Object and ff.has_method("fire_total"):
		return float(ff.call("fire_total"))
	return 0.0


## 号令面板的装填侧重离开了均装，且火攻在这一场的轮换里（三档）
func _fire_load_picked() -> bool:
	for n in world.get_children():
		if n.is_in_group("nk1_combat_orders") and n.has_method("loads"):
			return str(n.get("load_mode")) != "mixed" and (n.call("loads") as Array).size() > 2
	return false
