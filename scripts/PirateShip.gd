class_name PirateShip
extends CharacterBody2D

@export var max_speed: float = 250.0
@export var base_turn_speed: float = 1.5
@export var hull_hp: float = 80.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var wake_particles: CPUParticles2D = $WakeParticles

var target: Node2D = null
# lazy load：与 Ship.gd 同因，打断 Cannonball 场景自引用环
var cannonball_scene: PackedScene = null
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
## lane combat07：敌将 AI（接近 / 抢上风 / 保持舷炮 / 接舷企图 / 脱离 / 降幡），本船只管照舵令开船、开炮、抛钩
const _Captain := preload("res://scripts/combat/EnemyCaptainAI.gd")
## 可选模块（别的 lane 的；不在库就不读）：接舷钩索（combat05）、海况（combat02）
const _MELEE_PATH := "res://scripts/combat/MeleeResolve.gd"
const _SEA_STATE_PATH := "res://scripts/combat/SeaState.gd"
## CombatMorale（combat06）观战挂件写在船节点上的士气簿快照（state / fire …）
const _MORALE_META := &"nk1_combat_morale"
## CombatOrdersPanel（combat08）号令面板的组：玩家「降幡劝降」的结果从它的 parley_resolved 来
const _ORDERS_GROUP := "nk1_combat_orders"

## 开炮总闸：> 0 不放（WorldMap 开场给 COMBAT_FIRE_DELAY 接敌延迟；放完一轮给 VOLLEY_GAP）。
## 为 INF 即布景冻结（tools/combat_probe_stage.gd freeze_enemy_fire）：船照常机动，但不开炮、不抛钩、不离场——
## 敌船自己不会让海战结算，探针布景靠这条站得住。
var fire_timer: float = 0.0

## P4-3 齐射弹数：海战由 _spawn_enemy 按 scale 写入，封顶 COMBAT_CANNON_CAP。
var cannon_count: int = 3

## P4-2 接舷：被玩家钩住后停止航行/开炮，进入白刃判定。
## lane combat07：钩着时被放开、船还在 = 白刃本船守住（WorldMap 判对方败才放钩）→ 敌将士气大振、退开整队。
## 走 setter 而不是逐帧看：headless 下白刃当场结算，钩上、放开在同一次调用里，逐帧看会漏掉。
var grappled: bool = false:
	set(v):
		var released := grappled and not v
		grappled = v
		if released:
			boarding_initiator = false
		if released and hull_hp > 0.0 and captain != null:
			captain.on_melee_held()
			enemy_morale = captain.reported_morale()
## 敌船型号（_spawn_enemy 传入；白刃夺船时 Fleet.add_ship 用）。缺省是海寇快船
var ship_type: String = "pirate_boat"
## 海战精灵 id（_spawn_enemy 传 enemy.sprite；空则用 ship_type）→ assets/ship_<id>.png，缺图回落 ship_falcon.png
var sprite_id: String = ""
## 敌船名（夺船后并入舰队沿用；节点名保持 "PirateShip" 前缀供 WorldMap 计数）
var ship_name: String = ""
## 敌船水手数（_spawn_enemy 按船型初始化）；白刃判定输入
var crew: int = 20
## 敌船士气 0-100；白刃判定输入。开战后由敌将 AI 按受创 / 伤亡 / 僚船折损 / 白刃胜负逐帧回写
var enemy_morale: int = 60
## 敌将武力系数；白刃判定输入
var captain_force: float = 1.0

## lane combat07：敌将换了打法（state 见 EnemyCaptainAI 的六个常量；label 是上屏中文；reason 是一句理由）
signal captain_state_changed(state: StringName, label: String, reason: String)
## lane combat07：自己离了战场（how = "escaped" 脱离远遁）；随后 queue_free，WorldMap 按存活数照常结算
signal left_battle(how: String)
## lane combat07：本船抛了一次钩（ok = 钩上了，随即请宿主开白刃）
signal grapple_thrown(ok: bool)
## 场上敌船都在这个组里（别的 lane 的 HUD / 探针按组找，不必认节点名）
const GROUP := "nk1_enemy_ships"
## 一轮放完到下一轮（另一舷）最短间隔；同一舷还要等装填（EnemyCaptainAI.reload_time）
const VOLLEY_GAP := 1.2
## 降了的船白刃不再抵抗：战力只剩这么多（几个亡命的）
const STRUCK_RESIST := 0.15
## 标签摆在船在屏上最高处再往上 TAG_GAP：船图（512×0.62）上船身约 244 长、连帆约 116 宽，按转角算往上伸多高
const TAG_HALF_LEN := 122.0
const TAG_HALF_BEAM := 58.0
const TAG_GAP := 22.0
## 换打法的标签亮多久（降幡常亮）
const TAG_SHOW := 2.4

## 敌将（_ready 建；探针可换成别的实例）
var captain = null
## 已降（落帆停驶、停射；combat_strength 打折）
var struck: bool = false
## 开战时的船体（_ready 记；受创比例、航速折损都按它算）
var hull_max: float = 0.0
## 随船矢石轮数：-1 按敌将档案 / ReloadAmmo 定，>= 0 由调用方钉死
var ammo_volleys: int = -1
## 随船矢石余量 0–1（只读属性：HUD、CombatMorale 挂件按属性读，矢石尽是降幡压力之一）
var ammo_frac: float:
	get:
		return float(captain.ammo_frac()) if captain != null else 1.0
## 这一次接舷是本船先抛的钩（WorldMap 结算白刃时据此把本船当攻方；放钩即清）
var boarding_initiator: bool = false

var _last_state: StringName = &""
var _consorts: Array = []
var _consorts_seen: bool = false
var _left: bool = false
var _rng := RandomNumberGenerator.new()
var _tag_tween: Tween = null
var _hit_tween: Tween = null
var _parley_wired := false
var _parley_look := 0.0
## 可选模块的脚本（全局查一次）
static var _melee_scr = null
static var _melee_seen := false
static var _sea_scr = null
static var _sea_seen := false


func _ready() -> void:
	sprite.modulate = Color.WHITE
	apply_sprite()
	add_to_group(GROUP)
	set_meta(&"nk1_sprite_base_scale", sprite.scale if sprite else Vector2.ONE)
	_CombatFx.dress_ship(self)
	_polish_wake()
	_rng.randomize()
	_ensure_captain()
	_setup_tag()


## 船图契约：敌船精灵取 assets/ship_<sprite_id 或 ship_type>.png，缺图留 PirateShip.tscn 里的 ship_falcon.png。
## 不依赖 @onready（没进树也能调），探针直接拿 PirateShip.tscn 实例验回落。
func sprite_key() -> String:
	return sprite_id if sprite_id.strip_edges() != "" else ship_type


func apply_sprite() -> void:
	_CombatFx.apply_ship_sprite(get_node_or_null("Sprite2D") as Sprite2D,
		_CombatFx.ship_sprite_path(sprite_key(), _CombatFx.SHIP_SPRITE_ENEMY))


## 建敌将（_spawn_enemy 已写好 ship_type / crew / 士气 / 敌将系数，add_child 才进 _ready，这时读到的就是开战值）
func _ensure_captain() -> void:
	if hull_max <= 0.0:
		hull_max = maxf(hull_hp, 1.0)
	if captain != null:
		return
	captain = _Captain.new()
	captain.setup(ship_type, sprite_key(), captain_force, crew, float(enemy_morale), cannon_count)
	if ammo_volleys >= 0:
		captain.volleys = ammo_volleys
		captain.volleys_max = maxi(ammo_volleys, 1)


## 标签跟船走、始终正立（放在 _process：探针摆拍会关掉物理帧再挪船，标签照样跟上）
func _process(_delta: float) -> void:
	_hold_tag()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target): return
	if hull_hp <= 0: return
	_ensure_captain()
	if grappled:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta) # P4-2 接舷：被钩住后减速停住
		return

	var dist = position.distance_to(target.position)
	if dist > 2500.0: return # Too far, sleep

	_wire_parley(delta)
	var orders: Dictionary = captain.tick(_situation(), delta)
	# 敌船之间分离：兜圈时被本船甩乱了阵脚（本船开船、掉头）也不压成一艘。
	# 只偏航向，不改航速、转向上限与开炮判定（开炮仍按对本船的 angle_diff）。
	var push := _separation_push()
	if push != Vector2.ZERO:
		var heading: Vector2 = orders.get("heading", Vector2.UP.rotated(rotation))
		orders["heading"] = (heading + push * SEPARATION_WEIGHT).normalized()
	enemy_morale = int(orders.get("morale", enemy_morale))
	_note_state()
	_steer(orders, delta)
	move_and_slide()

	var speed_ratio = velocity.length() / max_speed
	wake_particles.emitting = speed_ratio > 0.05
	wake_particles.scale_amount_min = 0.16
	wake_particles.scale_amount_max = 0.28 + speed_ratio * 0.25

	var ship_dir = Vector2.UP.rotated(rotation)
	var angle_diff = ship_dir.angle_to((target.position - position).normalized())
	_process_firing(delta, angle_diff, dist)
	if bool(orders.get("grapple", false)) and _try_grapple():
		return
	if bool(orders.get("leave", false)):
		_leave_battle()


## 喂给敌将的局势（键名即 EnemyCaptainAI 读的键）。风取目标船的 wind_vector / wind_strength（WorldMap 海战逐帧写），
## 海流取 SeaState.active()（combat02）；玩家白刃战力与 WorldMap._board_enemy 同式；CombatMorale 挂件在场就带上士气簿的 state / fire。
func _situation() -> Dictionary:
	var host := get_parent()
	var wind := Vector2(0, 1)  # WorldMap 海战缺省：北风
	var wind_strength := 80.0
	var wv = target.get("wind_vector")
	if wv is Vector2:
		wind = wv
	var ws = target.get("wind_strength")
	if ws != null:
		wind_strength = float(ws)
	var book := _morale_book()
	var t_hull := 1.0
	var th = target.get("hull_hp")
	var tm = target.get("max_hp")
	if th != null and tm != null and float(tm) > 0.0:
		t_hull = clampf(float(th) / float(tm), 0.0, 1.0)
	var t_max := 300.0
	var tmx = target.get("max_speed")
	if tmx != null:
		t_max = float(tmx)
	var lost := _consorts_lost()
	return {
		"pos": position, "heading": Vector2.UP.rotated(rotation), "vel": velocity, "max_speed": max_speed,
		"target_pos": target.position, "target_vel": _target_velocity(),
		"target_heading": Vector2.UP.rotated(target.rotation), "target_max_speed": t_max, "target_hull": t_hull,
		"wind": wind, "wind_strength": wind_strength, "current": _sea_current(),
		"hull": clampf(hull_hp / hull_max, 0.0, 1.0), "crew": crew, "morale": enemy_morale,
		"own_strength": combat_strength(), "target_strength": _player_boarding_strength(),
		"consorts": _consorts.size(), "consorts_gone": lost[0], "consorts_struck": lost[1],
		"host_boarding": host != null and host.get("boarding") == true,
		"frozen": is_inf(fire_timer),
		"morale_state": str(book.get("state", "")), "fire_factor": float(book.get("fire", 1.0)),
	}


## 与别的活敌船相距不足 SEPARATION_DIST 就往外推，越近推得越狠；返回各邻船推力之和（无邻船为零向量）。
## （09-28 验收返修，09-30 并入本地线：本地线操船换成 EnemyCaptainAI，这条分离推力独立于操船法，照旧生效）
const SEPARATION_DIST := 300.0
## 推力并进航向时的权重：贴身（推力≈1）时压过绕舷侧的本意，相距一半以上时只偏一点
const SEPARATION_WEIGHT := 2.0


func _target_velocity() -> Vector2:
	var tb := target as CharacterBody2D
	return tb.velocity if tb != null else Vector2.ZERO


## 同场敌船互相分离：兜圈时被本船甩乱了阵脚也不压成一艘。只算同父的活敌船；返回合力（零向量＝不推）
func _separation_push() -> Vector2:
	var push := Vector2.ZERO
	var host := get_parent()
	if host == null or not is_inside_tree():
		return push
	for n in get_tree().get_nodes_in_group(GROUP):
		if n == self or n.get_parent() != host or n.is_queued_for_deletion():
			continue
		var other := n as PirateShip
		if other.hull_hp <= 0.0:
			continue
		var away := position - other.position
		var d := away.length()
		if d < 0.001 or d >= SEPARATION_DIST:
			continue
		push += away / d * (1.0 - d / SEPARATION_DIST)
	return push


## 玩家一方白刃战力（WorldMap._board_enemy 同式：水手 × 士气系数 × 将领系数）；没有 Fleet 时按中等商船估
func _player_boarding_strength() -> float:
	var fleet := get_node_or_null("/root/Fleet")
	if fleet == null or not fleet.has_method("total_crew") or not fleet.has_method("morale_factor") \
			or not fleet.has_method("captain_power"):
		return 60.0
	return float(fleet.call("total_crew")) * float(fleet.call("morale_factor")) * float(fleet.call("captain_power"))


## 僚船：第一次看局势时记下同场的其它敌船；之后数折了几艘 [沉 / 被夺 / 走了, 降了]
func _consorts_lost() -> Array:
	var host := get_parent()
	if not _consorts_seen and host != null:
		_consorts_seen = true
		for c in host.get_children():
			if c != self and String(c.name).begins_with("PirateShip") and float(_prop(c, "hull_hp", 0.0)) > 0.0:
				_consorts.append(weakref(c))
	var gone := 0
	var down := 0
	for r in _consorts:
		var c = (r as WeakRef).get_ref()
		if c == null or c.is_queued_for_deletion() or float(_prop(c, "hull_hp", 0.0)) <= 0.0:
			gone += 1
		elif _prop(c, "struck", false) == true:
			down += 1
	return [gone, down]


static func _prop(o: Object, key: String, fallback: Variant) -> Variant:
	var v = o.get(key)
	return fallback if v == null else v


## 照舵令开船：舵效随船速（多桨船掉头快），航速 = 最高航速 × 帆桨 × 该航向风力系数 × 船体折损；有惯性，外加风压、海流
func _steer(orders: Dictionary, delta: float) -> void:
	var ship_dir := Vector2.UP.rotated(rotation)
	var want: Vector2 = orders.get("heading", ship_dir)
	var turn: float = base_turn_speed * float(captain.turn_factor(velocity.length() / maxf(max_speed, 1.0)))
	rotation += clampf(ship_dir.angle_to(want), -turn * delta, turn * delta)
	ship_dir = Vector2.UP.rotated(rotation)
	var hull_k := 0.55 + 0.45 * clampf(hull_hp / hull_max, 0.0, 1.0)
	var spd: float = max_speed * float(orders.get("throttle", 1.0)) * float(orders.get("drive", 1.0)) * hull_k
	var drift: Vector2 = orders.get("drift", Vector2.ZERO)
	velocity = velocity.lerp(ship_dir * spd + drift, clampf(1.6 * delta, 0.0, 1.0))


func _process_firing(delta: float, angle_diff: float, dist: float) -> void:
	fire_timer -= delta
	if fire_timer > 0: return
	if grappled: return # P4-2 接舷：被钩住后不开炮
	# 敌将定打不打、打哪舷：正横、那舷装好了、射程够（顺风远逆风近）、矢石还有、没降、没在白刃
	var side: int = captain.fire_side(angle_diff, dist)
	if side == 0: return
	fire_timer = VOLLEY_GAP
	captain.on_fired(side)
	# Fire broadside
	var ship_dir = Vector2.UP.rotated(rotation)
	var side_dir = Vector2.RIGHT.rotated(rotation)
	if side < 0: side_dir = Vector2.LEFT.rotated(rotation)

	_AUDIO.combat_fire(get_parent())
	_CombatFx.muzzle_flash(self, side, cannon_count)
	_CombatFx.hull_shudder(self, 0.55, side)
	if cannonball_scene == null:
		cannonball_scene = load("res://scenes/Cannonball.tscn") as PackedScene
	var spread_k: float = captain.spread()
	for i in range(cannon_count):
		var cb = cannonball_scene.instantiate()
		cb.position = position + ship_dir * (i - (cannon_count - 1) * 0.5) * 20 + side_dir * 30
		var spread = randf_range(-spread_k, spread_k)
		cb.direction = side_dir.rotated(spread)
		cb.shooter = self
		get_parent().add_child(cb)


## 抛钩：钩上了就请宿主开白刃（WorldMap._board_enemy，与玩家按 G 同一条路：钩索题签 → 白刃判定 → 夺船 / 脱钩）。
## 宿主不在、正在白刃、已结算都不抛。返回 true = 已开白刃（本帧到此为止）。
func _try_grapple() -> bool:
	var host := get_parent()
	if host == null or not host.has_method("_board_enemy"):
		return false
	if host.get("boarding") == true or host.get("resolved") == true:
		return false
	# 宿主有接舷够距判定（WorldMap.boarding_approach_of，与玩家按 G 同一把尺：风压差、上风位、相对航速）就先问它：够不着不抛，接着靠
	if host.has_method("boarding_approach_of"):
		var ap = host.call("boarding_approach_of", self, target)
		if ap is Dictionary and not ap.is_empty() and not bool(ap.get("ok", true)):
			return false
	var ok: bool = _rng.randf() < _grapple_odds()
	captain.on_grapple(ok)
	grapple_thrown.emit(ok)
	if not ok:
		_flash_tag("钩索落空")
		return false
	_flash_tag("抛钩接舷")
	boarding_initiator = true
	host.call("_board_enemy", self)
	return true


## 一次抛钩的钩牢率：MeleeResolve（combat05）在就按它——本船作攻方（side_from_enemy）、玩家船队作守方（side_from_fleet）、
## 两船态势（approach_from_nodes：相对速度、舷距、风、上下风，ManeuverModel 在还并进够距）；不在按敌将内置（相对速度 / 风力 / 人手）
func _grapple_odds() -> float:
	var mr = _melee_script()
	if mr != null:
		var att = mr.call("side_from_enemy", self)
		var def = mr.call("side_from_fleet", get_node_or_null("/root/Fleet"))
		var ctx = mr.call("approach_from_nodes", self, target)
		if att is Dictionary and def is Dictionary and ctx is Dictionary:
			var c = mr.call("grapple_chance", att, def, ctx)
			if typeof(c) == TYPE_FLOAT or typeof(c) == TYPE_INT:
				return clampf(float(c), 0.0, 1.0)
	return float(captain.grapple_chance((velocity - _target_velocity()).length(), crew))


static func _melee_script():
	if not _melee_seen:
		_melee_seen = true
		if ResourceLoader.exists(_MELEE_PATH):
			var s = load(_MELEE_PATH)
			if s is Script and s.has_method("side_from_enemy") and s.has_method("side_from_fleet") \
					and s.has_method("approach_from_nodes") and s.has_method("grapple_chance"):
				_melee_scr = s
	return _melee_scr


## 海流：SeaState.active()（combat02 本场海况，开战才有）的 current_at；没入库 / 没开战为零
func _sea_current() -> Vector2:
	var ss = _sea_script()
	if ss == null:
		return Vector2.ZERO
	var sea = ss.call("active")
	if sea is Object and is_instance_valid(sea) and sea.has_method("current_at"):
		var c = sea.call("current_at", position)
		if c is Vector2:
			return c
	return Vector2.ZERO


static func _sea_script():
	if not _sea_seen:
		_sea_seen = true
		if ResourceLoader.exists(_SEA_STATE_PATH):
			var s = load(_SEA_STATE_PATH)
			if s is Script and s.has_method("active"):
				_sea_scr = s
	return _sea_scr


## CombatMorale 挂件写在本船节点上的士气簿快照；没挂就空
func _morale_book() -> Dictionary:
	if has_meta(_MORALE_META):
		var m = get_meta(_MORALE_META)
		if m is Dictionary:
			return m
	return {}


## 外头定了本船降（喊话劝降得手之类）：敌将径直降幡，下一物理帧照常落帆、停射、报降
func strike_colours(why := "") -> void:
	_ensure_captain()
	captain.force_strike(why if why != "" else "敌将%s" % str(captain.profile.get("strike_word", "降幡")))


## 玩家「降幡劝降」的结果（CombatOrdersPanel.parley_resolved 的 result）：点的是本船才算——敌竖降幡即降；
## 敌愈坚按面板建议加士气（morale_delta.enemy）；敌不应不动
func hear_parley(result: Dictionary) -> void:
	if result.get("target") != self or hull_hp <= 0.0:
		return
	_ensure_captain()
	match str(result.get("result", "")):
		"surrender":
			strike_colours("喊话劝降，%s" % str(captain.profile.get("strike_word", "降幡")))
		"defy":
			var md = result.get("morale_delta", {})
			var up := int(md.get("enemy", 4)) if md is Dictionary else 4
			enemy_morale = clampi(enemy_morale + up, 0, 100)


## 场上有号令面板就接它的 parley_resolved（面板可能比敌船晚挂，没找到每秒再看一眼，接上即止）
func _wire_parley(delta: float) -> void:
	if _parley_wired:
		return
	_parley_look -= delta
	if _parley_look > 0.0:
		return
	_parley_look = 1.0
	for n in get_tree().get_nodes_in_group(_ORDERS_GROUP):
		if n.has_signal("parley_resolved"):
			if not n.is_connected("parley_resolved", hear_parley):
				n.connect("parley_resolved", hear_parley)
			_parley_wired = true


## 脱离远遁：拉开到脱离距离，离开战场（WorldMap 按存活数结算，敌船都走光即「海盗已退」）
func _leave_battle() -> void:
	if _left:
		return
	_left = true
	set_physics_process(false)
	_notice("敌船「%s」脱离远遁" % _display_name())
	left_battle.emit("escaped")
	queue_free()


func _display_name() -> String:
	return ship_name if ship_name.strip_edges() != "" else "敌船"


func _notice(text: String) -> void:
	var host := get_parent()
	if host != null and host.has_method("_show_combat_notice"):
		host.call("_show_combat_notice", text)


## 敌将换了打法：发信号、亮标签；降了就落帆、停射、白刃打折，并告诉玩家贴舷可收
func _note_state() -> void:
	var st: StringName = captain.state
	if st == _last_state:
		return
	_last_state = st
	var label: String = captain.label()
	captain_state_changed.emit(st, label, str(captain.reason))
	if captain.is_struck() and not struck:
		struck = true
		if _hit_tween != null and _hit_tween.is_valid():
			_hit_tween.kill()  # 中弹闪红的补间会把船色拉回白，降多半就在中弹后一两帧
		if is_instance_valid(sprite):
			sprite.modulate = _rest_modulate()
		_notice("敌船「%s」%s" % [_display_name(), str(captain.profile.get("strike_word", "降幡"))])
	_flash_tag(label, st == _Captain.STRIKE)


func _polish_wake() -> void:
	if wake_particles == null:
		return
	wake_particles.texture = preload("res://assets/fx/soft_dot.png")
	wake_particles.color = Color(0.88, 0.94, 0.97, 0.5)
	wake_particles.scale_amount_min = 0.16
	wake_particles.scale_amount_max = 0.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1,1,1,0.8), Color(1,1,1,0.4), Color(1,1,1,0.0)])
	wake_particles.color_ramp = g
	wake_particles.local_coords = false


func take_damage(amount: float) -> void:
	hull_hp -= amount
	# 挂了船身反应节点就不闪红：命中处一闪、顺来力一颤、焦痕由 Cannonball → CombatFx.hull_impact 出
	if not _CombatFx.has_look(self):
		sprite.modulate = Color(1.2, 0.5, 0.45)
		_hit_tween = create_tween()
		_hit_tween.tween_property(sprite, "modulate", _rest_modulate(), 0.2)
	# lane combat07：矢石落在甲板上也伤人（每 25 伤约死 0–2 人），敌将按受创掉士气
	var killed := int(roundf(amount / 25.0 * _rng.randf_range(0.3, 1.6)))
	if killed > 0:
		crew = maxi(0, crew - killed)
	if captain != null and hull_hp > 0:
		captain.on_hit(amount, hull_max, hull_hp)
		enemy_morale = captain.reported_morale()

	if hull_hp <= 0:
		# 击沉这一发的过量按与命中同口径的伤亡率记进甲板。原先 hull_hp 留负数、超出的份随船沉凭空蒸发——
		# 残船重赏（hull 5 挨 25）与恰好击沉（hull 25 挨 25）登船收尸时活人一般多，挨过重的一发跟挠痒一样。
		# 夹回 0 同原先的数值口径（负数不是状态，向下游 _enemies_alive / _is_live_pirate 等看齐）。
		var overkill := maxf(0.0, -hull_hp)
		if overkill > 0.0:
			var extra := int(roundf(overkill / 25.0 * _rng.randf_range(0.3, 1.6)))
			if extra > 0:
				crew = maxi(0, crew - extra)
		hull_hp = 0.0
		_explode()


func _rest_modulate() -> Color:
	return Color(0.72, 0.7, 0.68) if struck else Color.WHITE  # 降了：落帆，船色发灰


func _explode() -> void:
	# 赏金走 SeaChart 结算，击沉不再掉拾取箱。船身残影歪倒没入海面（CombatFx.founder，纯观感），真节点照旧当帧释放
	_CombatFx.founder(self)
	queue_free()


## 本船离场（沉 / 被夺 / 远遁）时，还在飞的本船炮弹不再指着本船：Cannonball 命中时把 shooter 传给
## CombatFx.on_cannon_hit（形参带类型），传已释放的节点会报 SCRIPT ERROR（基线就有：敌船沉后它的弹才落）。
func _exit_tree() -> void:
	var host := get_parent()
	if host == null:
		return
	for c in host.get_children():
		if c is Area2D and c.get("shooter") == self:
			c.set("shooter", null)


## P4-2 白刃：敌侧战力 = 水手 × 士气系数 × 敌将系数（对齐设计文档公式）；已降的船只剩 STRUCK_RESIST
func combat_strength() -> float:
	var morale_factor := 0.6 + 0.4 * (float(enemy_morale) / 100.0)
	var resist := STRUCK_RESIST if struck else 1.0
	return float(crew) * morale_factor * captain_force * resist


## 敌将当前打法（中文，HUD / 探针读）；没建敌将时给空串
func captain_label() -> String:
	return str(captain.label()) if captain != null else ""



# ── 标签：换打法时在船头上方亮两秒（降幡常亮），始终正立 ──

func _setup_tag() -> void:
	var lbl := get_node_or_null("IntentTag/Label") as Label
	if lbl == null:
		return
	lbl.add_theme_font_override("font", UiTheme.font())
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", UiTheme.GOLD)
	lbl.add_theme_color_override("font_outline_color", Color(0.07, 0.04, 0.02, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = ""
	_hold_tag()


func _hold_tag() -> void:
	var tag := get_node_or_null("IntentTag") as Node2D
	if tag != null:
		tag.global_position = global_position + Vector2(0, -tag_lift())
		tag.global_rotation = 0.0
		var tk := _CombatFx.world_text_k(self)
		tag.global_scale = Vector2(tk, tk)


## 标签离船心多高（世界坐标）：船头朝上下时躲过船头，横着时贴着帆顶
func tag_lift() -> float:
	return absf(cos(rotation)) * TAG_HALF_LEN + absf(sin(rotation)) * TAG_HALF_BEAM + TAG_GAP


func _flash_tag(text: String, stay := false) -> void:
	var tag := get_node_or_null("IntentTag") as Node2D
	var lbl := get_node_or_null("IntentTag/Label") as Label
	if tag == null or lbl == null or not is_inside_tree():
		return
	lbl.text = text
	var col: Color = UiTheme.GOLD
	if captain != null and captain.state == _Captain.STRIKE:
		col = UiTheme.TEXT  # 常亮，要看得清：贴舷按 G 可收
	elif captain != null and captain.state == _Captain.BOARD:
		col = UiTheme.HONEY
	elif captain != null and captain.state == _Captain.DISENGAGE:
		col = UiTheme.TEXT_DIM
	lbl.add_theme_color_override("font_color", col)
	if _tag_tween != null and _tag_tween.is_valid():
		_tag_tween.kill()
	tag.modulate.a = 1.0
	if stay:
		return
	_tag_tween = create_tween()
	_tag_tween.tween_interval(TAG_SHOW)
	_tag_tween.tween_property(tag, "modulate:a", 0.0, 0.6)
