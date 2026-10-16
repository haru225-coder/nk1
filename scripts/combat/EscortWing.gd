extends Node2D
## 护航船上阵（战斗方案 §五、§十 第六期；lane w53-p6-escort，开关 escort_battle）。
## 舰队里旗舰以外的船（Fleet.ships[1..]，至多 MAX_ESCORTS 艘，连旗舰、敌船同屏不过 MAX_ON_FIELD 艘）跟着进海战：
##   船体、人手、炮位各按本船，刷的是 PirateShip.tscn（is_escort 立着：节点名 EscortShip_ 前缀、不进 nk1_enemy_ships 组——
##   WorldMap 数敌船、士气挂件、敌情列、小地图都只认 PirateShip 前缀，不会把它当敌船）；运动、开炮复用 PirateShip / EnemyCaptainAI
##   那一套，敌我反过来：target 是一艘敌船，风读旗舰（wind_source），素帆（HullRig.sail_crimson 关）。
## 走法：跟在旗舰两侧后方（STATIONS），敌船进了舷就放（射线上有自己人不放）；敌船照旧都冲旗舰来。
## 记账（与「护航只在结算时按折损记账」那条对上，不记两遍）：
##   · 船体、人手逐帧照实写回 Fleet.ships 那一格（按引用认，不凭序号）：player_damage（在册船耐久差）与收战折损（水手差）都由
##     WorldMap 从 Fleet 现算，各只算一遍；
##   · 上阵的护航自带人手在本船上打：旗舰白刃只算旗舰与没上阵的船上的人（Fleet.battle_crew / lose_battle_crew），护航的人不再并进旗舰那一场；
##   · 敌船血量按战力比缩放时（WorldMap._spawn_enemy），上阵护航那一份战力不再算进 player_power（power_left）——护航真上阵开打了，
##     不能既压低敌船血量、又自己再打一遍；
##   · 沉了的护航收战时（WorldMap._battle_exit → settle）从 Fleet 摘掉：船上的人并进 data.losses 的水手数，舱货随船没了，
##     另记 data.escort（不算「颠落舱面货」）；SeaChart 只照 data.escort 写一句札记（settle_note），不再动 Fleet；
##   · 旗舰沉了照旧收战（lose{sunk}），SeaChart 13c 把沉船移出、首艘耐久 > 0 的船接任——沉了的护航此时已摘掉，接任的必是还浮着的那艘。
## 关 escort_battle：deploy 返回 null，一艘不刷，各处接头全走旧路。

const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _Maneuver := preload("res://scripts/combat/ManeuverModel.gd")
const _SeaWake := preload("res://scripts/combat/SeaWake.gd")
const _SeaPennant := preload("res://scripts/combat/SeaPennant.gd")
const PIRATE_SCENE := "res://scenes/PirateShip.tscn"

const NODE_NAME := "EscortWing"
const SHIP_PREFIX := "EscortShip_"
const MAX_ESCORTS := 3
## 同屏船数上限（旗舰 + 护航 + 敌船；方案 §十一「第六期最多同屏 6–8 艘船」）
const MAX_ON_FIELD := 8
## 护航一舷几门：同 WorldMap.COMBAT_CANNON_CAP（敌船封顶 2，护航同一把尺）；没有炮位的小船也有弓弩手，放一发
const CANNON_CAP := 2
## 开局不开炮的秒数：同 WorldMap.COMBAT_FIRE_DELAY
const FIRE_DELAY := 3.5
## 编队站位（旗舰船身坐标：x 右舷为正、y 船尾为正）：左右后侧各一，第三艘缀在正后。
## 与旗舰、彼此都隔开 PirateShip.SEPARATION_DIST（300）以上，站定了不互相推
const STATIONS := [Vector2(-230.0, 210.0), Vector2(230.0, 210.0), Vector2(0.0, 470.0)]
## 编队朝向跟旗舰船首转，每秒至多转这么多（旗舰猛一打舵，站位不跟着甩出半圈）
const FRAME_TURN := 0.8

var world: Node2D = null
var flagship: Node2D = null
## 上阵的护航：[{node, ref（Fleet.ships 那一格）, slot, name, type, dur0, crew0, fate（"" / sunk / fled）}]
var escorts: Array = []
## 编队朝向（rad）：跟着旗舰 rotation 转、转速封顶 FRAME_TURN
var _frame_rot := 0.0
## 已接上离树回调的敌船号（敌船在本翼之后刷，live_enemies 扫到就接）
var _watched: Dictionary = {}
var _settled := false


## WorldMap 上挂着的那一翼（没上阵返回 null）
static func of(w: Node) -> Node2D:
	if w == null or not is_instance_valid(w):
		return null
	var n := w.get_node_or_null(NODE_NAME)
	return n as Node2D if n != null and not n.is_queued_for_deletion() else null


## 开战（WorldMap._setup_combat，刷敌船之前）：开关开、舰队有能上阵的船就刷一翼护航，返回这一翼；否则 null（旧玩法）
static func deploy(w: Node2D, pb: Dictionary) -> Node2D:
	if w == null or not _Switches.on("escort_battle") or not bool(pb.get("battle", false)):
		return null
	var enemy_n := 0
	for e in pb.get("enemy", []):
		if e is Dictionary:
			enemy_n += maxi(0, int((e as Dictionary).get("count", 1)))
	var picks := candidates(enemy_n)
	if picks.is_empty():
		return null
	var wing := new()
	wing.name = NODE_NAME
	wing.z_index = -5  # 航迹白练压在船下（同 SeaAtmosphere.WAKE_Z）
	w.add_child(wing)
	wing._spawn(w, picks)
	return wing


## 能上阵的船：Fleet.ships 第二艘起按序取船体还在、船上有人的，至多 MAX_ESCORTS 艘，且旗舰 + 敌船 + 护航不过 MAX_ON_FIELD 艘
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
		var slot: Vector2 = STATIONS[k % STATIONS.size()]
		if is_instance_valid(flagship):
			p.position = flagship.position + slot.rotated(flagship.rotation)
			p.rotation = flagship.rotation
		w.add_child(p)
		var e := {"node": p, "ref": s, "slot": slot, "name": nm, "type": type_id,
			"dur0": float(s.get("durability", 0.0)), "crew0": int(s.get("crew", 0)), "fate": ""}
		escorts.append(e)
		Fleet.escorts_in_battle.append(s)
		p.tree_exiting.connect(_on_escort_exiting.bind(e))
		p.connect("left_battle", _on_escort_left.bind(e))
		_dress(p)


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
	_frame_rot = rotate_toward(_frame_rot, flagship.rotation, FRAME_TURN * delta)
	var foes := live_enemies()
	for e in escorts:
		if not _alive(e["node"]):
			continue
		_sync_fleet(e)
		_steer(e, foes)
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


## 敌船离树（沉 / 遁 / 被夺）：护航当即撒手——target 指着它的清掉。不清的话这一帧末它就释放，
## 护航身上留着已释放的靶，ShipLook 读 target 的风当场报错；下一物理帧 _steer 再按场上的敌船重挑
func _on_enemy_exiting(id: int) -> void:
	for e in escorts:
		var p = e["node"]
		if _alive(p) and _id(p.get("target")) == id:
			p.set("target", null)


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


## 这一艘此刻怎么走：跟旗舰站位（编队朝向 _frame_rot），靶取离它最近的敌船（开炮用）；脱离中的照敌将自己走
func _steer(e: Dictionary, foes: Array) -> void:
	var p: Node2D = e["node"]
	var cap = p.get("captain")
	var routing: bool = cap != null and cap.get("state") == &"disengage"
	p.set("friends", _friends_of(p))
	p.set("target", _nearest(p, foes))  # 场上没敌船了给 null（不拿旗舰凑数：靶就是开炮的方向）
	p.set("escort_station_on", not routing)
	p.set("escort_station", flagship.position + (e["slot"] as Vector2).rotated(_frame_rot))
	p.set("escort_lead_vel", flagship.get("velocity") if flagship.get("velocity") is Vector2 else Vector2.ZERO)


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

## 收战（WorldMap._battle_exit，player_damage 与 losses 算过之后）：沉了的护航从 Fleet 摘掉（按引用），
## 船上的人并进 data.losses.crew，护航下场写 data.escort：
##   {deployed: [{name, type}], sunk: [{name, type, crew, cargo}], fled: [{name, type}], hurt: [{name, dmg}]}
func settle(_outcome: String, data: Dictionary) -> void:
	if _settled:
		return
	_settled = true
	for e in escorts:
		if _alive(e["node"]):
			_sync_fleet(e)
	var rows := {"deployed": [], "sunk": [], "fled": [], "hurt": []}
	var gone: Array = []
	var drowned := 0
	for e in escorts:
		var s: Dictionary = e["ref"]
		var row := {"name": str(e["name"]), "type": str(e["type"])}
		(rows["deployed"] as Array).append(row)
		var fate := str(e["fate"])
		if fate == "sunk":
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


## 战后札记里交代护航的一句（SeaChart._on_battle_result 接）：沉、退出战阵、受损；什么都没出没写返回 ""
static func settle_note(data: Dictionary) -> String:
	var esc = data.get("escort")
	if not (esc is Dictionary):
		return ""
	var bits := PackedStringArray()
	for r in (esc as Dictionary).get("sunk", []):
		var cargo := _cargo_words((r as Dictionary).get("cargo", {}))
		bits.append("护航「%s」沉没%s" % [str(r.get("name", "")), "，该船货物随船（%s）" % cargo if cargo != "" else ""])
	for r in (esc as Dictionary).get("fled", []):
		bits.append("护航「%s」转舵退出战阵" % str(r.get("name", "")))
	for r in (esc as Dictionary).get("hurt", []):
		bits.append("「%s」船体受损 %d" % [str(r.get("name", "")), int(r.get("dmg", 0))])
	return "" if bits.is_empty() else "；".join(bits) + "。"


static func _cargo_words(cargo) -> String:
	if not (cargo is Dictionary) or (cargo as Dictionary).is_empty():
		return ""
	var parts := PackedStringArray()
	for gid in cargo:
		parts.append("%s %d" % [GameManager.get_good_name(gid), int(cargo[gid])])
	return "、".join(parts)
