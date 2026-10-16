extends Node2D
## 护航船上阵与三道将令（战斗方案 §五、§十 第六期；lane w53-p6-escort，开关 escort_battle / escort_orders）。
## 舰队里旗舰以外的船（Fleet.ships[1..]，至多 MAX_ESCORTS 艘，连旗舰、敌船同屏不过 MAX_ON_FIELD 艘）跟着进海战：
##   船体、人手、炮位各按本船，刷的是 PirateShip.tscn（is_escort 立着：节点名 EscortShip_ 前缀、不进 nk1_enemy_ships 组——
##   WorldMap 数敌船、士气挂件、敌情列、小地图都只认 PirateShip 前缀，不会把它当敌船）；运动、开炮复用 PirateShip / EnemyCaptainAI
##   那一套，敌我反过来：target 是一艘敌船，风读旗舰（wind_source），素帆（HullRig.sail_crimson 关）。
## 三道将令（开战布置时下一道、整场不变；ORDER_WINDOW_S 秒里没下照列队）：
##   列队 line   护航跟在旗舰两侧后方（STATIONS），敌船进了舷就放；敌船照旧都冲旗舰来
##   曳敌 lure   每艘护航迎上去缠住一艘敌船：近到 LURE_PX，那艘敌船掉头来打护航（target 改成护航），旗舰少挨一艘；护航孤船挨打
##   夺舱 board  护航先照列队跟着、甲士聚舷待命（装填 BOARD_RELOAD_MUL 倍慢）；旗舰一钩上（不论谁先抛的钩），护航去钩第二艘
## 护航与敌船之间的接舷白刃不进 WorldMap._board_enemy（那是旗舰那一场）：两船并住停驶 MELEE_HOLD_S 秒，再按 MeleeResolve 一掷，
## 不起题签；钩着的那几秒用 escort_locked 拴住（不碰 grappled：士气挂件把 grappled 当旗舰钩舷算）。
## 记账（与「护航只在结算时按折损记账」那条对上，不记两遍）：
##   · 船体、人手逐帧照实写回 Fleet.ships 那一格（按引用认，不凭序号）：player_damage（在册船耐久差）与收战折损（水手差）都由
##     WorldMap 从 Fleet 现算，各只算一遍；
##   · 上阵的护航自带人手在本船上打：旗舰白刃只算旗舰与没上阵的船上的人（Fleet.battle_crew / lose_battle_crew），护航的人不再并进旗舰那一场；
##   · 敌船血量按战力比缩放时（WorldMap._spawn_enemy），上阵护航那一份战力不再算进 player_power（power_left）——护航真上阵开打了，
##     不能既压低敌船血量、又自己再打一遍；
##   · 沉了 / 被夺的护航收战时（WorldMap._battle_exit → settle）从 Fleet 摘掉：船上的人并进 data.losses 的水手数，舱货随船没了，
##     另记 data.escort（不算「颠落舱面货」）；SeaChart 只照 data.escort 写一句札记（settle_note），不再动 Fleet；
##   · 旗舰沉了照旧收战（lose{sunk}），SeaChart 13c 把沉船移出、首艘耐久 > 0 的船接任——沉了的护航此时已摘掉，接任的必是还浮着的那艘。
## 同屏船数（MAX_ON_FIELD = 8，方案 §十一「第六期最多同屏 6–8 艘」）的数法：
##   旗舰 1 + 护航（EscortShip_）+ 敌船（pending_battle.enemy 各条 count 之和，刷出来是 PirateShip_）
##   + 火船（pending_battle.yashan.fire_ships，崖山那一场刷出来是 FireShips 下的 FireShip_）≤ 8；
##   护航上阵艘数 = min(MAX_ESCORTS, 8 − 1 − 敌船 − 火船, 能上阵的船)，算出来 ≤ 0 就一艘不刷。
##   pending_battle.no_escort == true（崖山突围那一场写，YashanBattle.NO_ESCORT_KEY）：护航不上阵，旗舰以外的船留在外围。
## 关 escort_battle：deploy 返回 null，一艘不刷，各处接头全走旧路；关 escort_orders：不出将令签，护航照列队。
## 随机：只掷全局流（randf / randi），探针 / 胜率工具 seed() 盖得住。

const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Maneuver := preload("res://scripts/combat/ManeuverModel.gd")
const _MeleeResolve := preload("res://scripts/combat/MeleeResolve.gd")
const _SeaWake := preload("res://scripts/combat/SeaWake.gd")
const _SeaPennant := preload("res://scripts/combat/SeaPennant.gd")
const PIRATE_SCENE := "res://scenes/PirateShip.tscn"

const NODE_NAME := "EscortWing"
const SHIP_PREFIX := "EscortShip_"
const MAX_ESCORTS := 3
## 同屏船数上限（旗舰 + 护航 + 敌船 + 火船；数法见头注）
const MAX_ON_FIELD := 8
## pending_battle 里「这一场护航不上阵」的键（崖山突围写，同 YashanBattle.NO_ESCORT_KEY；本件不 preload 那边，键名照抄）
const NO_ESCORT_KEY := "no_escort"
## 护航一舷几门：同 WorldMap.COMBAT_CANNON_CAP（敌船封顶 2，护航同一把尺）；没有炮位的小船也有弓弩手，放一发
const CANNON_CAP := 2
## 开局不开炮的秒数：同 WorldMap.COMBAT_FIRE_DELAY
const FIRE_DELAY := 3.5
## 编队站位（旗舰船身坐标：x 右舷为正、y 船尾为正）：左右后侧各一，第三艘缀在正后。
## 与旗舰、彼此都隔开 PirateShip.SEPARATION_DIST（300）以上，站定了不互相推
const STATIONS := [Vector2(-230.0, 210.0), Vector2(230.0, 210.0), Vector2(0.0, 470.0)]
## 曳敌：护航近到这么远，那艘敌船掉头来追护航；拉开过 LURE_DROP_PX（护航跑远了 / 退出战阵）敌船回头找旗舰
const LURE_PX := 650.0
const LURE_DROP_PX := 1600.0
## 夺舱：钩上后两船并住这么多秒再分胜负（看得见两船拴在一处；其间任一沉了、旗舰来钩这艘，白刃作罢）
const MELEE_HOLD_S := 3.0
## 夺舱待命：甲士聚舷，弩炮手少了，装填慢这么多倍
const BOARD_RELOAD_MUL := 1.25
## 开战布置：开战这么多秒里下将令（键盘 8 / 9 / 0、点签、触屏点签），下了就定、整场不变；过时没下照列队
const ORDER_WINDOW_S := 10.0
## 编队朝向跟旗舰船首转，每秒至多转这么多（旗舰猛一打舵，站位不跟着甩出半圈）
const FRAME_TURN := 0.8

const ORDER_LINE := "line"
const ORDER_LURE := "lure"
const ORDER_BOARD := "board"
const ORDERS := ["line", "lure", "board"]
const ORDER_NAMES := {"line": "列队", "lure": "曳敌", "board": "夺舱"}
## 签面提示与面板代价行（平实写明代价）
const ORDER_TIPS := {
	"line": "护航跟在旗舰两侧后方，敌船进了舷就放箭。代价：敌船照旧都冲旗舰来，护航不替旗舰挡。",
	"lure": "每艘护航迎上去缠住一艘敌船，引它掉头来打护航，旗舰少挨一艘。代价：护航孤船挨打，可能被打沉，海寇还会跳帮夺船。",
	"board": "护航跟着旗舰，甲士聚舷待命，放箭慢两成；旗舰钩上一艘后，护航去钩第二艘。代价：白刃不利要折人手。",
}
## 面板代价行（「列队代价：…」一令一行，16 号字放得下号令面板一行）
const ORDER_COSTS := {
	"line": "敌船照旧冲旗舰",
	"lure": "护航孤船或沉或被夺",
	"board": "放箭慢两成、跳帮折人",
}

var world: Node2D = null
var flagship: Node2D = null
## 上阵的护航：[{node, ref（Fleet.ships 那一格）, slot, name, type, dur0, crew0, fate（"" / sunk / taken / fled）, lure, board, mode}]
var escorts: Array = []
var order := ORDER_LINE
var order_locked := false
## 谁定的将令：player（玩家下的）/ timeout（过时照列队）/ auto（escort_orders 关）
var order_by := ""
## 旗舰钩上过一艘（夺舱的扳机；_board_enemy 开头调 on_flagship_hooked）
var flag_hooked := false
## 护航跳帮夺下的船数（data.escort.prizes）
var prizes_taken := 0
## 被曳走的敌船：敌船 instance_id → 护航 instance_id（存号不存节点：沉了、被夺的船先释放，拿号比对不碰已释放的实例）
var _lured: Dictionary = {}
## 编队朝向（rad）：跟着旗舰 rotation 转、转速封顶 FRAME_TURN
var _frame_rot := 0.0
## 已接上离树回调的敌船号（敌船在本翼之后刷，live_enemies 扫到就接）
var _watched: Dictionary = {}
## 挂着的护航白刃：[{att, def, t}]
var _melees: Array = []
var _t := 0.0
var _settled := false


## WorldMap 上挂着的那一翼（没上阵返回 null）
static func of(w: Node) -> Node2D:
	if w == null or not is_instance_valid(w):
		return null
	var n := w.get_node_or_null(NODE_NAME)
	return n as Node2D if n != null and not n.is_queued_for_deletion() else null


## 开战（WorldMap._setup_combat，刷敌船之前）：开关开、这一场许护航上阵（no_escort 不为真）、舰队有能上阵的船、
## 同屏还有空位（数法见头注）就刷一翼护航，返回这一翼；否则 null（旧玩法）
static func deploy(w: Node2D, pb: Dictionary) -> Node2D:
	if w == null or not _Switches.on("escort_battle") or not bool(pb.get("battle", false)):
		return null
	if bool(pb.get(NO_ESCORT_KEY, false)):
		return null
	var picks := candidates(hulls_against(pb))
	if picks.is_empty():
		return null
	var wing := new()
	wing.name = NODE_NAME
	wing.z_index = -5  # 航迹白练压在船下（同 SeaAtmosphere.WAKE_Z）
	w.add_child(wing)
	wing._spawn(w, picks)
	return wing


## 这一场旗舰对面要占的同屏格数：敌船（pending_battle.enemy 各条 count 之和）+ 火船（pending_battle.yashan.fire_ships）
static func hulls_against(pb: Dictionary) -> int:
	var n := 0
	for e in pb.get("enemy", []):
		if e is Dictionary:
			n += maxi(0, int((e as Dictionary).get("count", 1)))
	var ys = pb.get("yashan", {})
	if ys is Dictionary:
		n += maxi(0, int((ys as Dictionary).get("fire_ships", 0)))
	return n


## 能上阵的船：Fleet.ships 第二艘起按序取船体还在、船上有人的，至多 MAX_ESCORTS 艘，且旗舰 + 对面（敌船 + 火船）+ 护航不过 MAX_ON_FIELD 艘
static func candidates(enemy_n: int) -> Array:
	var room := mini(MAX_ESCORTS, MAX_ON_FIELD - 1 - maxi(0, enemy_n))
	var out: Array = []
	for i in range(1, Fleet.ships.size()):
		if out.size() >= room:
			break
		var s: Dictionary = Fleet.ships[i]
		if float(s.get("durability", 0.0)) <= 0.0 or int(s.get("crew", 0)) <= 0:
			continue
		out.append(s)
	return out


## 敌船血量缩放用的我方战力（WorldMap._spawn_enemy）：上阵护航那一份照 SeaChart._fleet_power 的口径
## （耐久 × 0.5 + 水手 × 4 + 炮位 × 25，乘士气系数；甲级那项按全队算、不拆）从 player_power 里扣掉；没上阵原样返回
static func power_left(wing: Node, player_power: float) -> float:
	if wing == null or not is_instance_valid(wing) or not wing.has_method("power_share"):
		return player_power
	return maxf(1.0, player_power - float(wing.call("power_share")))


func power_share() -> float:
	var p := 0.0
	for e in escorts:
		var s: Dictionary = e["ref"]
		p += float(s.get("durability", 0.0)) * 0.5 + float(s.get("crew", 0)) * 4.0 \
			+ float(Fleet.ship_def(str(s.get("type", ""))).get("cannon_slots", 0)) * 25.0
	return p * Fleet.morale_factor()


func _spawn(w: Node2D, picks: Array) -> void:
	world = w
	flagship = w.get("ship") as Node2D
	if is_instance_valid(flagship):
		_frame_rot = flagship.rotation
	var scene := load(PIRATE_SCENE) as PackedScene
	for k in picks.size():
		var s: Dictionary = picks[k]
		var type_id := str(s.get("type", ""))
		var d := Fleet.ship_def(type_id)
		var p := scene.instantiate() as CharacterBody2D
		p.set("is_escort", true)
		var rig := p.get_node_or_null("HullRig")
		if rig != null:
			rig.set("sail_crimson", false)  # 我方素帆（敌船朱帆）
		var nm := _display_name(s)
		p.name = "%s%d" % [SHIP_PREFIX, k + 1]
		p.set("ship_type", type_id)
		p.set("ship_name", nm)
		p.set("crew", int(s.get("crew", 1)))
		p.set("hull_max", float(s.get("max_durability", d.get("durability", 100))))
		p.set("hull_hp", float(s.get("durability", 0.0)))
		p.set("enemy_morale", int(Fleet.morale))
		p.set("captain_force", 1.0)
		p.set("cannon_count", clampi(int(d.get("cannon_slots", 0)) / 2, 1, CANNON_CAP))
		p.set("armor_mul", clampf(1.0 - 0.10 * float(int(s.get("armor_level", 1)) - 1), 0.5, 1.0))
		# 航速照本船船型（ManeuverModel 同一张表：V_REF × 船速系数 × 帆改装），跟得上旗舰
		var prof: Dictionary = _Maneuver.profile_of(type_id)
		p.set("max_speed", _Maneuver.V_REF * float(prof.get("hull", 0.95)) * (1.0 + _Maneuver.SAIL_LV_SPEED * float(int(s.get("sail_level", 1)) - 1)))
		p.set("fire_timer", FIRE_DELAY)
		p.set("wind_source", flagship)
		p.set("wing", self)
		var slot: Vector2 = STATIONS[k % STATIONS.size()]
		if is_instance_valid(flagship):
			p.position = flagship.position + slot.rotated(flagship.rotation)
			p.rotation = flagship.rotation
		w.add_child(p)
		var e := {"node": p, "ref": s, "slot": slot, "name": nm, "type": type_id,
			"dur0": float(s.get("durability", 0.0)), "crew0": int(s.get("crew", 0)), "fate": "", "lure": null, "board": null,
			"mode": ""}
		escorts.append(e)
		Fleet.escorts_in_battle.append(s)
		p.tree_exiting.connect(_on_escort_exiting.bind(e))
		p.connect("left_battle", _on_escort_left.bind(e))
		_dress(p)
	if not _Switches.on("escort_orders"):
		order_locked = true
		order_by = "auto"
	_set_mode_all()


## 上屏船名：Fleet.display_name（撞名的加「・甲」「・乙」）；按引用找序号
static func _display_name(s: Dictionary) -> String:
	for i in range(Fleet.ships.size()):
		if is_same(Fleet.ships[i], s):
			return Fleet.display_name(i)
	return str(s.get("name", "护航船"))


## 我方旗旒与航迹白练（SeaAtmosphere 只认旗舰与 PirateShip 前缀，护航由这里自己挂；旗旒挂点 HullRig 逐帧按主桅投影改写）
func _dress(p: Node2D) -> void:
	var pen: Node2D = _SeaPennant.new()
	pen.name = "OwnPennant"
	pen.position = Vector2(0.0, -70.0)
	pen.z_index = 3
	pen.set("fill", Color(0.90, 0.88, 0.80, 0.95))
	pen.set("trim", Color(0.24, 0.42, 0.40, 0.9))
	pen.set("length", 46.0)
	pen.set("root_w", 8.0)
	p.add_child(pen)
	var wake: Node2D = _SeaWake.new()
	wake.name = "Wake_%s" % p.name
	wake.set("hull", p)
	wake.set("half_beam", 44.0)
	wake.set("half_len", 128.0)
	add_child(wake)


func _exit_tree() -> void:
	# 收战没走 settle 就拆了（探针拆布景、出错）：登记照样清掉，旗舰白刃回旧口径
	if not _settled:
		Fleet.escorts_in_battle.clear()


# ── 逐帧 ──────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if world == null or not is_instance_valid(world) or world.get("resolved") == true:
		return
	if not is_instance_valid(flagship):
		return
	_t += delta
	_frame_rot = rotate_toward(_frame_rot, flagship.rotation, FRAME_TURN * delta)
	if not order_locked and _t >= ORDER_WINDOW_S:
		lock_order(ORDER_LINE, "timeout")
	var foes := live_enemies()
	for e in escorts:
		if not _alive(e["node"]):
			continue
		_sync_fleet(e)
		_steer(e, foes)
	_tick_lured()
	_tick_melees(delta)
	_feed_pennants()


## 场上活着的敌船（同 WorldMap._is_live_pirate 口径）；头一回扫到的接上离树回调
func live_enemies() -> Array:
	var out: Array = []
	if world == null:
		return out
	for c in world.get_children():
		if c is Node2D and String(c.name).begins_with("PirateShip") and not c.is_queued_for_deletion() \
				and float(c.get("hull_hp")) > 0.0:
			out.append(c)
			var id := (c as Node).get_instance_id()
			if not _watched.has(id):
				_watched[id] = true
				(c as Node).tree_exiting.connect(_on_enemy_exiting.bind(id))
	return out


## 敌船离树（沉 / 遁 / 被夺）：护航当即撒手——target / 曳敌 / 夺舱指着它的都清掉。不清的话这一帧末它就释放，
## 护航身上留着已释放的靶，ShipLook 读 target 的风当场报错；下一物理帧 _steer 再按场上的敌船重挑
func _on_enemy_exiting(id: int) -> void:
	_lured.erase(id)
	for e in escorts:
		var p = e["node"]
		if _alive(p) and _id(p.get("target")) == id:
			p.set("target", null)
		if _id(e["lure"]) == id:
			e["lure"] = null
		if _id(e["board"]) == id:
			e["board"] = null


## 上阵护航节点（活着的）
func escort_nodes() -> Array:
	var out: Array = []
	for e in escorts:
		if _alive(e["node"]):
			out.append(e["node"])
	return out


static func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and not (n as Node).is_queued_for_deletion() and float(n.get("hull_hp")) > 0.0


## 节点号（已释放 / 空给 0）：比对拿号，不拿可能已释放的实例去比
static func _id(n) -> int:
	return (n as Object).get_instance_id() if n != null and is_instance_valid(n) else 0


## 船体、人手写回 Fleet 那一格（引用）：耐久照节点船体，水手照节点人数（每船至少留 1 人，同 Fleet._lose_crew 保火种）
func _sync_fleet(e: Dictionary) -> void:
	var p = e["node"]
	if p == null or not is_instance_valid(p):
		return
	var s: Dictionary = e["ref"]
	s["durability"] = clampf(float(p.get("hull_hp")), 0.0, float(s.get("max_durability", e["dur0"])))
	s["crew"] = maxi(1, int(p.get("crew")))


## 这一艘此刻怎么走：曳敌缠着它那艘，夺舱扳机扣了去钩第二艘，其余跟站位（列队 / 夺舱待命）；脱离中的照敌将自己走
func _steer(e: Dictionary, foes: Array) -> void:
	var p: Node2D = e["node"]
	var cap = p.get("captain")
	var routing: bool = cap != null and cap.get("state") == &"disengage"
	p.set("friends", _friends_of(p))
	var mode := _mode_of(e, foes)
	if mode != e["mode"]:
		e["mode"] = mode
		_apply_mode(e)
	match mode:
		"lure":
			p.set("target", e["lure"])
			p.set("escort_station_on", false)
		"board":
			p.set("target", e["board"])
			p.set("escort_station_on", false)
		_:
			p.set("target", _nearest(p, foes))  # 场上没敌船了给 null（不拿旗舰凑数：靶就是开炮的方向）
			p.set("escort_station_on", not routing)
			p.set("escort_station", flagship.position + (e["slot"] as Vector2).rotated(_frame_rot))
			p.set("escort_lead_vel", flagship.get("velocity") if flagship.get("velocity") is Vector2 else Vector2.ZERO)


## 本艘此刻的走法：lure（曳敌缠着一艘）/ board（夺舱去钩第二艘）/ station（跟站位）。
## 缠 / 钩的那艘转舵脱离了就放它走（降了的照钩、不照缠）：曳敌是把它从旗舰身边引开，它要逃就由它逃——
## 护航追着它跑，它拉不开离场线、走不了，两船耗到限时两散（胜率工具同种子 300 秒两散实测）
func _mode_of(e: Dictionary, foes: Array) -> String:
	if not order_locked:
		return "station"
	match order:
		ORDER_LURE:
			if not _engaged(e["lure"], false):
				e["lure"] = _pick_lure(e, _fighting(foes, false))
			return "lure" if _engaged(e["lure"], false) else "station"
		ORDER_BOARD:
			if not flag_hooked:
				return "station"
			if not _engaged(e["board"], true) or _id(e["board"]) == _id(world.get("boarding_target")):
				e["board"] = _pick_board(e, _fighting(foes, true))
			return "board" if _engaged(e["board"], true) else "station"
	return "station"


## 还缠得住 / 钩得着：活着、没转舵脱离；降了的只算钩得着（夺舱收船）、不算缠得住（曳敌引的是还在打的）
static func _engaged(n, struck_ok: bool) -> bool:
	if not _alive(n):
		return false
	var cap = n.get("captain")
	if cap != null and cap.get("state") == &"disengage":
		return false
	return struck_ok or n.get("struck") != true


static func _fighting(foes: Array, struck_ok: bool) -> Array:
	return foes.filter(func(f): return _engaged(f, struck_ok))


## 换走法：敌将的接舷许可、装填快慢跟着换；标签亮一下
func _apply_mode(e: Dictionary) -> void:
	var p: Node2D = e["node"]
	var cap = p.get("captain")
	if cap == null:
		return
	cap.set("force_board", e["mode"] == "board")
	cap.set("reload_mul", BOARD_RELOAD_MUL if order == ORDER_BOARD and order_locked and e["mode"] != "board" else 1.0)
	if p.has_method("_flash_tag"):
		match e["mode"]:
			"lure":
				p.call("_flash_tag", "曳敌")
			"board":
				p.call("_flash_tag", "夺舱")
			_:
				p.call("_flash_tag", str(ORDER_NAMES.get(order, "列队")) if order_locked else "列队")


func _set_mode_all() -> void:
	for e in escorts:
		e["mode"] = ""


## 曳敌挑哪艘：先挑还没有护航缠着的、离本艘最近的；都有人缠了就挑最近的
func _pick_lure(e: Dictionary, foes: Array) -> Node2D:
	var taken := {}
	for o in escorts:
		if o != e and _alive(o["node"]) and _alive(o["lure"]):
			taken[(o["lure"] as Node).get_instance_id()] = true
	var free: Array = []
	for f in foes:
		if not taken.has((f as Node).get_instance_id()):
			free.append(f)
	var pick := _nearest(e["node"], free)
	return pick if pick != null else _nearest(e["node"], foes)


## 夺舱挑「第二艘」：旗舰正钩着的那艘不挑、别的护航正钩着的不挑，离本艘最近的
func _pick_board(e: Dictionary, foes: Array) -> Node2D:
	var skip := {}
	var bt = world.get("boarding_target")
	if bt != null and is_instance_valid(bt):
		skip[(bt as Node).get_instance_id()] = true
	for o in escorts:
		if o != e and _alive(o["node"]) and _alive(o["board"]):
			skip[(o["board"] as Node).get_instance_id()] = true
	var pool: Array = []
	for f in foes:
		if not skip.has((f as Node).get_instance_id()):
			pool.append(f)
	return _nearest(e["node"], pool)


static func _nearest(from: Node2D, pool: Array) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for c in pool:
		var d := (c as Node2D).position.distance_squared_to(from.position)
		if d < best_d:
			best_d = d
			best = c
	return best


## 放舷前要躲开的自己人：旗舰与别的护航
func _friends_of(p: Node2D) -> Array:
	var out: Array = [flagship]
	for e in escorts:
		if _alive(e["node"]) and _id(e["node"]) != p.get_instance_id():
			out.append(e["node"])
	return out


## 曳敌：护航近到 LURE_PX，它缠的那艘敌船掉头来打护航；护航没了 / 跑远了 / 不再缠它，敌船回头找旗舰
func _tick_lured() -> void:
	for id in _lured.keys():
		var foe = instance_from_id(id)
		var esc = instance_from_id(int(_lured[id]))
		var keep: bool = _alive(foe) and _alive(esc) and (foe as Node2D).position.distance_to((esc as Node2D).position) <= LURE_DROP_PX
		if keep:
			for e in escorts:
				if _id(e["node"]) == int(_lured[id]) and _id(e["lure"]) != int(id):
					keep = false
		if not keep:
			_release_lured(int(id))
	if order != ORDER_LURE or not order_locked:
		return
	for e in escorts:
		var p = e["node"]
		var foe = e["lure"]
		if not (_alive(p) and _alive(foe)) or _lured.has(_id(foe)):
			continue
		if _id(foe.get("target")) != _id(flagship) or _id(foe) == _id(world.get("boarding_target")) or bool(foe.get("struck")):
			continue
		if (p as Node2D).position.distance_to((foe as Node2D).position) <= LURE_PX:
			_lured[_id(foe)] = _id(p)
			foe.set("target", p)
			foe.set("wind_source", flagship)
			foe.set("wing", self)
			_notice("敌船「%s」掉头来打护航「%s」" % [str(foe.get("ship_name")), str(e["name"])])


## 被曳走的敌船回头找旗舰（风照旧读旗舰、白刃不再交护航一翼）
func _release_lured(foe_id: int) -> void:
	_lured.erase(foe_id)
	var foe = instance_from_id(foe_id)
	if _alive(foe):
		foe.set("target", flagship)
		foe.set("wind_source", null)
		foe.set("wing", null)


func _feed_pennants() -> void:
	var sea = world.call("sea_state") if world.has_method("sea_state") else null
	if sea == null:
		return
	var wind: Vector2 = sea.get("wind_to") if sea.get("wind_to") is Vector2 else Vector2(0, 1)
	var force := clampf(float(sea.get("wind_speed")) / 130.0, 0.0, 1.0)
	for e in escorts:
		var p = e["node"]
		if not _alive(p):
			continue
		var pen := (p as Node).get_node_or_null("OwnPennant")
		if pen != null:
			pen.set("wind", wind.normalized() if wind.length() > 0.01 else Vector2(0, 1))
			pen.set("force", force)


# ── 将令 ──────────────────────────────────────────────

## 下将令（号令面板的签 / 键 / 触屏都走这里；探针、胜率工具直调）：开战布置时只下一次，下了就定、整场不变。返回下没下成
func lock_order(id: String, by := "player") -> bool:
	if order_locked or not id in ORDERS:
		return false
	order = id
	order_locked = true
	order_by = by
	_set_mode_all()
	if by == "timeout":
		_notice("护航未得将令，照列队跟定旗舰")
	else:
		_notice("护航将令：%s（整场不变）" % str(ORDER_NAMES[id]))
	return true


## 将令表（号令面板运行时取：面板不 preload 本件——本件直读 Fleet / GameState，-s 工具在 autoload 挂上前 preload 面板会连带编不过）
func order_table() -> Dictionary:
	return {"ids": ORDERS, "names": ORDER_NAMES, "tips": ORDER_TIPS, "costs": ORDER_COSTS}


## 布置还剩几秒（已定为 0）
func order_left_s() -> float:
	return 0.0 if order_locked else maxf(0.0, ORDER_WINDOW_S - _t)


## 将令签亮不亮：escort_orders 开、还没定
func orders_open() -> bool:
	return _Switches.on("escort_orders") and not order_locked and not escort_nodes().is_empty()


# ── 接舷白刃（护航钩敌船 / 被曳的敌船钩护航）──────────────────

## 旗舰钩上了一艘（WorldMap._board_enemy 开头，不论谁先抛的钩）：夺舱的扳机；护航正钩着这艘的白刃作罢（让给旗舰那一场）
func on_flagship_hooked(enemy: Node) -> void:
	flag_hooked = true
	for m in _melees.duplicate():
		if _id(m["att"]) == _id(enemy) or _id(m["def"]) == _id(enemy):
			_melees.erase(m)
			_unlock(m["att"])
			_unlock(m["def"])
	if order == ORDER_BOARD and order_locked:
		for e in escorts:
			e["mode"] = ""


## 船抛钩（PirateShip._try_grapple：钩的不是旗舰——护航去钩敌船、被曳的敌船去钩护航）。返回 true = 钩上了、白刃挂起
func ship_hooks(att: Node2D, def: Node2D) -> bool:
	if world == null or world.get("resolved") == true or not (_alive(att) and _alive(def)):
		return false
	var bt := _id(world.get("boarding_target"))
	if _busy(att) or _busy(def) or (bt != 0 and (_id(def) == bt or _id(att) == bt)):
		return false
	if world.has_method("boarding_approach_of"):
		var ap = world.call("boarding_approach_of", att, def)
		if ap is Dictionary and not (ap as Dictionary).is_empty() and not bool(ap.get("ok", true)):
			return false
	var ctx: Dictionary = _MeleeResolve.approach_from_nodes(att, def, Vector2.ZERO, -1.0,
		str(att.get("ship_type")), str(def.get("ship_type")))
	var odds := _MeleeResolve.grapple_chance(melee_side(att), melee_side(def), ctx)
	var ok := randf() < odds
	var cap = att.get("captain")
	if cap != null:
		cap.call("on_grapple", ok)
	if not ok:
		att.call("_flash_tag", "钩索落空")
		return false
	att.call("_flash_tag", "抛钩接舷")
	att.set("escort_locked", true)
	def.set("escort_locked", true)
	_melees.append({"att": att, "def": def, "t": MELEE_HOLD_S})
	if att.get("is_escort") == true:
		_notice("护航「%s」钩住%s，跳帮夺舱" % [str(att.get("ship_name")), str(def.get("ship_name"))])
	else:
		_notice("敌船「%s」抛钩咬住护航「%s」" % [str(att.get("ship_name")), str(def.get("ship_name"))])
	return true


func _busy(n: Node2D) -> bool:
	for m in _melees:
		if _id(m["att"]) == _id(n) or _id(m["def"]) == _id(n):
			return true
	return false


static func _unlock(n) -> void:
	if n != null and is_instance_valid(n):
		n.set("escort_locked", false)


## 白刃一方：船节点按 MeleeResolve.side_from_enemy 读（水手、士气、将领系数、船型、船名）；护航那方换成本队的白刃装备
## （同 side_from_fleet：弓弩手两成、披甲两成五、灰瓶两枚）
static func melee_side(n: Node2D) -> Dictionary:
	var s: Dictionary = _MeleeResolve.side_from_enemy(n)
	if n.get("is_escort") == true:
		s["archers"] = 0.2
		s["armor"] = 0.25
		s["pots"] = 2
	return s


func _tick_melees(delta: float) -> void:
	for m in _melees.duplicate():
		var att = m["att"]
		var def = m["def"]
		if not (_alive(att) and _alive(def)):
			_melees.erase(m)
			_unlock(att)
			_unlock(def)
			continue
		m["t"] = float(m["t"]) - delta
		if float(m["t"]) <= 0.0:
			_melees.erase(m)
			resolve_melee(att, def)


## 一场护航白刃（钩缆已挂牢）：MeleeResolve 一掷；双方折人、攻方得手夺船（护航夺敌船入船籍 / 敌船夺走护航），不得手各自退开
func resolve_melee(att: Node2D, def: Node2D) -> Dictionary:
	_unlock(att)
	_unlock(def)
	if not (_alive(att) and _alive(def)) or world == null:
		return {}
	var ctx: Dictionary = _MeleeResolve.approach_from_nodes(att, def, Vector2.ZERO, -1.0,
		str(att.get("ship_type")), str(def.get("ship_type")))
	ctx["hooked"] = true
	ctx["seed"] = randi() | 1
	var r: Dictionary = _MeleeResolve.resolve(melee_side(att), melee_side(def), ctx)
	att.set("crew", maxi(0, int(att.get("crew")) - int(r.get("att_dead", 0))))
	def.set("crew", maxi(0, int(def.get("crew")) - int(r.get("def_dead", 0))))
	var att_name := str(att.get("ship_name"))
	var def_name := str(def.get("ship_name"))
	if str(r.get("legacy", "lose")) == "win":
		if att.get("is_escort") == true:
			var taken: String = str(world.call("escort_prize", def)) if world.has_method("escort_prize") else ""
			prizes_taken += 1
			_notice("护航「%s」跳帮夺下%s" % [att_name, taken if taken != "" else def_name])
		else:
			_lose_escort(def, "taken")
			_notice("护航「%s」被敌船「%s」跳帮夺去" % [def_name, att_name])
	else:
		var att_cap = att.get("captain")
		var def_cap = def.get("captain")
		if att_cap != null:
			att_cap.call("on_boarding_repelled")
			att.set("enemy_morale", int(att_cap.call("reported_morale")))
		if def_cap != null:
			def_cap.call("on_melee_held")
			def.set("enemy_morale", int(def_cap.call("reported_morale")))
		var dead := int(r.get("att_dead", 0))
		if att.get("is_escort") == true:
			_notice("护航「%s」跳帮受挫，折 %d 人" % [att_name, dead])
			_witness("ally_routed")
		else:
			_notice("护航「%s」打退跳帮" % def_name)
	for e in escorts:
		if _alive(e["node"]):
			_sync_fleet(e)
	return r


## 护航被夺：记下场、写回 Fleet、离场（船随敌去，收战时从 Fleet 摘掉）
func _lose_escort(p: Node2D, fate: String) -> void:
	for e in escorts:
		if _id(e["node"]) == p.get_instance_id() and e["fate"] == "":
			_sync_fleet(e)
			e["fate"] = fate
			_witness("ally_captured" if fate == "taken" else "ally_sunk")
	p.queue_free()


func _witness(kind: String) -> void:
	var mo = world.get("_morale") if world != null else null
	if mo != null and is_instance_valid(mo):
		var ps = mo.call("player_sheet")
		if ps != null:
			ps.call("witness", kind)


func _notice(text: String) -> void:
	if world != null and is_instance_valid(world) and world.has_method("_show_combat_notice"):
		world.call("_show_combat_notice", text)


# ── 离场 ──────────────────────────────────────────────

## 护航离树：船体见底即沉（PirateShip._explode）；收战拆树（world.resolved）不记下场
func _on_escort_exiting(e: Dictionary) -> void:
	var p = e["node"]
	if p == null or not is_instance_valid(p):
		return
	# 缠着它的敌船当即回头找旗舰：节点这一帧末就释放，别处（ShipLook 读 target 的风）不能再拿到它
	for id in _lured.keys():
		if int(_lured[id]) == p.get_instance_id():
			_release_lured(int(id))
	if e["fate"] != "":
		return
	if float(p.get("hull_hp")) <= 0.0:
		var s: Dictionary = e["ref"]
		s["durability"] = 0.0
		s["crew"] = maxi(1, int(p.get("crew")))
		e["fate"] = "sunk"
		if world != null and is_instance_valid(world) and world.get("resolved") != true:
			_witness("ally_sunk")
			_notice("护航「%s」沉没" % str(e["name"]))
	else:
		_sync_fleet(e)


## 护航退出战阵（敌将「脱离」拉开到离场线，PirateShip._leave_battle）：船还在本队，带着这一场的伤
func _on_escort_left(_how: String, e: Dictionary) -> void:
	if e["fate"] != "":
		return
	_sync_fleet(e)
	e["fate"] = "fled"
	_witness("ally_routed")


# ── 收战 ──────────────────────────────────────────────

## 收战（WorldMap._battle_exit，player_damage 与 losses 算过之后）：沉了 / 被夺的护航从 Fleet 摘掉（按引用），
## 船上的人并进 data.losses.crew，护航下场写 data.escort：
##   {order, order_by, deployed: [{name, type}], sunk / taken: [{name, type, crew, cargo}], fled: [{name, type}], hurt: [{name, dmg}], prizes}
func settle(_outcome: String, data: Dictionary) -> void:
	if _settled:
		return
	_settled = true
	_melees.clear()
	for e in escorts:
		if _alive(e["node"]):
			_sync_fleet(e)
	var rows := {"order": order, "order_by": order_by, "deployed": [], "sunk": [], "taken": [], "fled": [], "hurt": [],
		"prizes": prizes_taken}
	var gone: Array = []
	var drowned := 0
	for e in escorts:
		var s: Dictionary = e["ref"]
		var row := {"name": str(e["name"]), "type": str(e["type"])}
		(rows["deployed"] as Array).append(row)
		var fate := str(e["fate"])
		if fate == "sunk" or fate == "taken":
			var lost := row.duplicate()
			lost["crew"] = int(s.get("crew", 0))
			lost["cargo"] = _cargo_of(s)
			(rows[fate] as Array).append(lost)
			gone.append(s)
			drowned += int(s.get("crew", 0))
			continue
		if fate == "fled":
			(rows["fled"] as Array).append(row)
		var dmg := float(e["dur0"]) - float(s.get("durability", 0.0))
		if dmg >= 1.0:
			(rows["hurt"] as Array).append({"name": str(e["name"]), "dmg": int(round(dmg))})
	_remove_ships(gone)
	if drowned > 0:
		var losses: Dictionary = data.get("losses", {})
		losses["crew"] = int(losses.get("crew", 0)) + drowned
		data["losses"] = losses
	data["escort"] = rows
	Fleet.escorts_in_battle.clear()
	for id in _lured.keys():
		var foe = instance_from_id(id)
		if _alive(foe):
			foe.set("wing", null)
	_lured.clear()


static func _cargo_of(s: Dictionary) -> Dictionary:
	var out := {}
	var sc = s.get("cargo", {})
	if sc is Dictionary:
		for gid in sc:
			var q := int((sc[gid] as Dictionary).get("qty", 0))
			if q > 0:
				out[gid] = q
	return out


## 摘船（Fleet.remove_ships 按引用摘），坞位跟着拨：指着摘掉的那艘归 0，指在它后面的往前挪一格（同 SeaChart 13c）
static func _remove_ships(refs: Array) -> void:
	for r in refs:
		var idx := -1
		for i in range(Fleet.ships.size()):
			if is_same(Fleet.ships[i], r):
				idx = i
				break
		if idx < 0:
			continue
		Fleet.remove_ships([r])
		var berth := int(GameState.berth_index)
		if berth == idx:
			GameState.berth_index = 0
		elif berth > idx:
			GameState.berth_index = berth - 1


## 战后札记里交代护航的一句（SeaChart._on_battle_result 接）：沉、被夺、退出战阵、受损、跳帮夺船；什么都没出没写返回 ""
static func settle_note(data: Dictionary) -> String:
	var esc = data.get("escort")
	if not (esc is Dictionary):
		return ""
	var bits := PackedStringArray()
	for r in (esc as Dictionary).get("sunk", []):
		var cargo := _cargo_words((r as Dictionary).get("cargo", {}))
		bits.append("护航「%s」沉没%s" % [str(r.get("name", "")), "，该船货物随船（%s）" % cargo if cargo != "" else ""])
	for r in (esc as Dictionary).get("taken", []):
		bits.append("护航「%s」被敌跳帮夺去" % str(r.get("name", "")))
	for r in (esc as Dictionary).get("fled", []):
		bits.append("护航「%s」转舵退出战阵" % str(r.get("name", "")))
	for r in (esc as Dictionary).get("hurt", []):
		bits.append("「%s」船体受损 %d" % [str(r.get("name", "")), int(r.get("dmg", 0))])
	var n := int((esc as Dictionary).get("prizes", 0))
	if n > 0:
		bits.append("护航跳帮夺下 %d 艘" % n)
	return "" if bits.is_empty() else "；".join(bits) + "。"


static func _cargo_words(cargo) -> String:
	if not (cargo is Dictionary) or (cargo as Dictionary).is_empty():
		return ""
	var parts := PackedStringArray()
	for gid in cargo:
		parts.append("%s %d" % [GameManager.get_good_name(gid), int(cargo[gid])])
	return "、".join(parts)
