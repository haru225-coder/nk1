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
## lane w53-p3a 三期「火与水」：敌船进水失火的薄适配层（CombatSwitches.enemy_flood_fire），
## 里面只挂 FloodFire 这一件，不挂完整的伤损模型——舱数 / 稳性 / 储备浮力照 DamageModel 同一张船型档
const _EnemyFF := preload("res://scripts/combat/EnemyFloodFire.gd")
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
## lane w53-2：本船先抛钩跳过去、被放开船还在 = 本船这攻方没拿下（被击退 / 被砍缆）→ 敌将记跳帮受挫、退回炮战。
## 走 setter 而不是逐帧看：headless 下白刃当场结算，钩上、放开在同一次调用里，逐帧看会漏掉。
var grappled: bool = false:
	set(v):
		var released := grappled and not v
		var boarded_first := boarding_initiator
		grappled = v
		if released:
			boarding_initiator = false
		if released and hull_hp > 0.0 and captain != null:
			if boarded_first:
				captain.on_boarding_repelled()
			else:
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
## lane w53-p3a：敌船进水失火簿（EnemyFloodFire）。开关 enemy_flood_fire 开、进 _ready 时按船种 / 体量起一份；
## 关时恒为 null，收弹、逐帧、读口全走不到它，本船与基线逐字一致
var flood_fire = null
## lane w53-p3a：火势快照（0–1），起火观感 / p3b-c 读用；簿不在恒 0
var fire_level := 0.0

var _last_state: StringName = &""
var _consorts: Array = []
var _consorts_seen: bool = false
var _left: bool = false
var _rng := RandomNumberGenerator.new()
## lane w53-p3flood：倾侧观感的基准船图缩放（_ready 记下；heel 只乘算压扁，不直写绝对值）
var _base_sprite_scale := Vector2.ONE
## lane w53-p3flood：水火观感的重调阈值与上一回调用级（与 Ship.FX_STEP 同档；级数变不够不重调，免得每帧摸粒子）
const _FF_FX_STEP := 0.05
var _ff_fx_fire_lv := -1.0
var _ff_fx_flood_lv := -1.0
var _ff_heel_x := 0.0  # 当帧倾侧横向偏移（px，写进 sprite.position.x；冻结帧收观感时归零）
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
	_base_sprite_scale = sprite.scale if sprite != null else Vector2.ONE  # lane w53-p3flood：倾侧观感的基准（乘算不直写）
	_ensure_flood_fire()
	_ensure_captain()
	_setup_tag()


## 开關 enemy_flood_fire 开、簿还没起：按船种 / 体量起一份 EnemyFloodFire（取数照玩家船 DamageModel 同一张船型档；
## 有炮位才带火药——EnemyFloodFire.setup 里按 cannon_slots > 0 定）。关开关不调本行，flood_fire 恒 null
func _ensure_flood_fire() -> void:
	if flood_fire != null or not CombatSwitches.on("enemy_flood_fire"):
		return
	var fleet := get_node_or_null("/root/Fleet")
	if fleet == null or not fleet.has_method("ship_def"):
		return  # 没进树 / 没挂 Fleet（探针裸实例化）：收起簿、行为照基线，批次需要时调用方自己起
	flood_fire = _EnemyFF.new()
	flood_fire.setup(ship_type, fleet.call("ship_def", ship_type))


## 给 p3c 敌情列的读口（契约固定）：开关开且有簿时给火 / 进水 / 烧着的段 / 倾侧 / 正下沉；关开关或没有簿返回 {}
func flood_fire_state() -> Dictionary:
	if flood_fire == null:
		return {}
	return flood_fire.state()


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

	_step_flood_fire(delta)
	var ship_dir = Vector2.UP.rotated(rotation)
	var angle_diff = ship_dir.angle_to((target.position - position).normalized())
	_process_firing(delta, angle_diff, dist)
	if bool(orders.get("grapple", false)) and _try_grapple():
		return
	if bool(orders.get("leave", false)):
		_leave_battle()


## lane w53-p3a：敌船进水失火逐帧。水火只在 switch 开、簿在、不冻结（已降 / 被钩 / 白刃进行中 / 已结算）时长；
## 火烧船体走 take_damage 同一处扣（不绕开击沉逻辑），火场伤亡扣 crew；缓沉涨满 1 或倾覆走与击沉同一条 _explode
func _step_flood_fire(delta: float) -> void:
	if flood_fire == null:
		return
	var host := get_parent()
	var flags := {"struck": struck, "grappled": grappled, "boarding": host != null and host.get("boarding") == true,
		"resolved": host != null and host.get("resolved") == true}
	if flood_fire.frozen(flags):
		_ff_look_off()  # lane w53-p3flood：冻结帧顺手收观感（冻结后没人再调 _sync_fire_look，不收就挂着火烟定格）
		return
	# 风与雨照本场的（target 船 = 玩家旗舰，WorldMap 海战逐帧写 wind_strength；雨从 WorldMap.is_storm 同一路读）
	var env := {"wind": 80.0, "rain": false}
	var ws = target.get("wind_strength")
	if ws != null:
		env["wind"] = float(ws)
	if host != null and host.get("is_storm") == true:
		env["rain"] = true
	var st: Dictionary = flood_fire.step(delta, crew, env)
	var blaze := clampf(float(st["hull_dps"]), 0.0, 1.0)
	if blaze > 0.0:
		# 「走 take_damage 同一处结算，不要绕开击沉逻辑」= 收弹那一条质检路：火烧船体扣账交 Cannonball 唯一爱看的
		# take_ballistic_hit 走 book 走 DamageModel 的 fx/伤亡飘字/敌将 on_hit —— 不在 _step 里另打一条 take_damage。
		# FloodFire 出的是「船体上限的几分」：乘上 hull_max 换点数，每帧 delta 份落账
		take_ballistic_hit({"kind": "", "hull": blaze * hull_max * delta, "amount": 0.0,
			"local": Vector2.ZERO, "heavy": true, "crew": 0.0, "fire": 0.0})
	if hull_hp <= 0.0:
		return  # 这一帧烧沉了，take_ballistic_hit → take_damage 已经走过 _explode
	if int(st["crew_cas"]) > 0:
		crew = maxi(0, crew - int(st["crew_cas"]))
	if str(st["founder"]) != "":
		# 缓沉涨满 / 倾覆：船体一并记损，沉船与击沉同一条 _explode 路（赏钱照击沉）
		take_ballistic_hit({"kind": "", "hull": hull_max * 2.0, "amount": 0.0,
			"local": Vector2.ZERO, "heavy": true, "crew": 0.0, "fire": 0.0})
		return
	# 观感：篷帆 / 甲板着起时拽现成 CombatFx 火烟与戽水出来，倾侧压扁船图（_sync_fire_look，全用现成特效件）
	fire_level = clampf(flood_fire.ff.fire_total(), 0.0, 1.0)
	_sync_fire_look(st)


## 水火观感只用现成特效件（CombatFx.set_fire 焦帆火烟、set_flood 戽水漫水——Ship 同一条观感线），
## 不另画新图：火势按级调烟柱、顺风拖；进水先见舷边戽水花、水多了甲板漫白沫；倾侧把船图往低舷
## 压扁偏一点（与 Ship._update_damage_visuals 同一手感：40° 顶格压宽两成半、偏 8px；乘算，不直写）。
## 级数变不够 _FF_FX_STEP 不重调，免得每帧摸粒子（与 Ship 的 FX_STEP 同理）。
## p3a 原稿的 DamageFx 支路（FireRig / FireBow…）在敌船上是空转：Ship.tscn 才有那些节点，
## PirateShip.tscn 挂不出来——本函数直接走观感线，不再找 DamageFx。
func _sync_fire_look(st: Dictionary) -> void:
	if not is_instance_valid(sprite):
		return
	var ff = flood_fire.ff if flood_fire != null else null
	# 篷帆火势直接当火级（Ship._sync_combat_fx 同一路）；风往哪吹烟往哪拖（目标船上的风力场，读不到当无风）
	if absf(fire_level - _ff_fx_fire_lv) >= _FF_FX_STEP or (fire_level > 0.0) != (_ff_fx_fire_lv > 0.0):
		_ff_fx_fire_lv = fire_level
		_CombatFx.set_fire(self, fire_level, _ff_wind_drag())
	# 进水级 = 渗漏起步 0.15，按舱水离沉没线（储备浮力）走了几成往上加，到线为 1（Ship 同式；
	# CombatFx 那边 1/3 两舷戽水、2/3 甲板漫水）
	var fl := 0.0
	if ff != null and (ff.flood_frac() > 0.0 or ff.open_leaks() > 0):
		fl = clampf(0.15 + 0.85 * ff.flood_frac() / maxf(0.05, ff.reserve_now()), 0.15, 1.0)
	if absf(fl - _ff_fx_flood_lv) >= _FF_FX_STEP or (fl > 0.0) != (_ff_fx_flood_lv > 0.0):
		_ff_fx_flood_lv = fl
		_CombatFx.set_flood(self, fl)
	# 倾侧：船图往低舷压扁偏一点（40° 顶格乘 0.75、偏 8px）。st 没带舷向（老口径）就当不倾。
	var list_deg := float(st.get("list_deg", 0.0))
	var heel := clampf(absf(list_deg) / 40.0, 0.0, 0.25)
	sprite.scale = Vector2(_base_sprite_scale.x * (1.0 - 0.25 * heel), _base_sprite_scale.y)
	_ff_heel_x = signf(list_deg) * 8.0 * heel
	sprite.position.x = _ff_heel_x


## 收观感：冻结（已降 / 被钩 / 白刃 / 已结算）或沉前拨一次——烟停喷（余烟自散）、戽水停、船图归位。
## 冻结帧 _step_flood_fire 早退后没人再调 _sync_fire_look，不主动收就会挂着火烟定格。
func _ff_look_off() -> void:
	if _ff_fx_fire_lv > 0.0:
		_ff_fx_fire_lv = 0.0
		_CombatFx.set_fire(self, 0.0)
	if _ff_fx_flood_lv > 0.0:
		_ff_fx_flood_lv = 0.0
		_CombatFx.set_flood(self, 0.0)
	if is_instance_valid(sprite) and _base_sprite_scale != Vector2.ONE:
		sprite.scale = _base_sprite_scale
		sprite.position.x = 0.0
		_ff_heel_x = 0.0


## 烟与火星顺风拖的方向（世界向量，长度 0–1）：目标船上的风力场（WorldMap 海战逐帧写 wind_vector /
## wind_strength， Ship._sync_combat_fx 同一来源），读不到给零向量（烟只往上散）。
func _ff_wind_drag() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	var wv = target.get("wind_vector")
	var ws = target.get("wind_strength")
	if wv is Vector2 and ws != null:
		return (wv as Vector2) * clampf(float(ws) / 150.0, 0.0, 1.0)
	return Vector2.ZERO


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

	# lane w53-p3a：水火缠身时人手去堵漏 / 救火，出膛数折掉几发（EnemyFloodFire 按损伤簿算，从炮位抽人）；
	# 簿不在（开关关、没进 Fleet 的探针布景）volley_n == range(cannon_count) 齐——与基线逐字一致
	var volley_n := cannon_count
	if flood_fire != null:
		var shrink: float = flood_fire.fire_volley_shrink(crew, cannon_count)
		if shrink < 1.0:
			volley_n = maxi(0, int(round(cannon_count * shrink)))
		# 火烟倾侧也在拖装填：cooldown 按 VOLLEY_GAP 再乘一份（≤1.8×）
		if shrink < 1.0 or flood_fire.ff.fire_total() > 0.0 or absf(flood_fire.ff.list_deg()) > 5.0:
			fire_timer *= clampf(1.0 + 0.5 * flood_fire.ff.fire_total() + absf(flood_fire.ff.list_deg()) / 40.0, 1.0, 1.8)
	if volley_n <= 0:
		return

	_AUDIO.combat_fire(get_parent())
	_CombatFx.muzzle_flash(self, side, volley_n)
	_CombatFx.hull_shudder(self, 0.55, side)
	if cannonball_scene == null:
		cannonball_scene = load("res://scenes/Cannonball.tscn") as PackedScene
	var spread_k: float = captain.spread()
	# lane w53-p3a：满舷（簿不在 / 无水火）时 range(cannon_count) 与本 range(volley_n) 一致
	for i in range(volley_n):
		var cb = cannonball_scene.instantiate()
		cb.position = position + ship_dir * (i - (volley_n - 1) * 0.5) * 20 + side_dir * 30
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


## 脱离远遁：拉开到脱离距离，离开战场（WorldMap 按存活数结算，敌船都走光即胜局「敌船已退」）
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


## lane w53-p3a：簿在且水火能动（簿在船上、不在冻结态）时记损也带着进水走；这一条只在簿真在时进，
## hit_side 取自旧弹命中舷位（不明处传 0 不偏舷）；开关关 / 冻结时本函数照走不到，进水量只往岸上账
func _note_ff_hit(amount: float, hit_side := 0) -> void:
	if flood_fire == null or hull_hp <= 0.0 or is_queued_for_deletion():
		return
	var host := get_parent()
	var flags := {"struck": struck, "grappled": grappled, "boarding": host != null and host.get("boarding") == true,
		"resolved": host != null and host.get("resolved") == true}
	if flood_fire.frozen(flags):
		return
	flood_fire.on_timed_hit(amount, hit_side)


func take_damage(amount: float) -> void:
	hull_hp -= amount
	# lane w53-p3a：旧口径弹（玩家 player_gunnery 关出来的直线铁子 / 火烧不在此调）照 hull 有漏的机会进水
	# （没有引火——旧账不带弹种引火率）；开关关 / 已降、被钩、白刃、结算时不动水
	_note_ff_hit(amount)
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


## lane w53-p3a：玩家 side 接上装填簿 / 弹道（player_gunnery 开）时，Cannonball._strike 在开关
## （enemy_flood_fire）开、簿在的这两道闸后才会走进来；关时走不到（Cannonball 侧同样把关）。
## 船体、伤亡、闪红、飘字、敌将士气全与旧口径 take_damage 同一处走（不另起账）；带过来的 kind / local / heavy
## 只喂进水失火簿——水线下重弹按几率开漏、带 fire 的弹按几率点火。
## 注意：Godot 4.6 的 Object._call 在 Node 上不会拦到未声明的方法，类名 PirateShip 的 has_method 又
## 吃静态表——「off 时真的没有 take_ballistic_hit」这条要在 Cannonball 那边把关，本函数只做货真派一名。
func take_ballistic_hit(hit: Dictionary) -> void:
	# 已排队回收就该弹都挡下：火烧沉的那一发走穿了 take_ballistic_hit → take_damage → _explode，
	# 再往后任何 set 都会报到 freed 上。沉完就不进簿、不点 sprite、不摸敌将
	if is_queued_for_deletion():
		return
	var hull := float(hit.get("hull", 0.0))
	# 闪红 / 焦痕 / 飘字照样出：命中观感不打折（muzzle / impact 由 Cannonball 侧已出，这里只照本体反应）
	if hull > 0.0:
		take_damage(hull)
	else:
		# 不伤船体的轻矢（箭 / 轻弩）：船体不衰、闪一焦红提示钉住了
		if not _CombatFx.has_look(self):
			sprite.modulate = Color(1.15, 0.85, 0.8)
			_hit_tween = create_tween()
			_hit_tween.tween_property(sprite, "modulate", _rest_modulate(), 0.16)
	# 那一发沉了不再加漏加火（已排队回收）
	if is_queued_for_deletion():
		return
	if flood_fire != null:
		# take_ballistic_hit 收递的是 bow/mid 指向 de local，不跨余切——路过 host 已 queue_free 时跳过坐漏/点火符，
		# flood_fire 簿是 RefCounted 不随 node 拆，读后从 _step 算无龙——簿不在（＝开关关）这条道根本走不到，无需再判
		var host := get_parent()
		var flags := {"struck": struck, "grappled": grappled, "boarding": host != null and host.get("boarding") == true,
			"resolved": host != null and host.get("resolved") == true}
		if not flood_fire.frozen(flags):
			flood_fire.on_ballistic_hit(hit)
	# 轻矢打人不伤船：弹种 crew 期望值照概率落到甲板（与旧口径 take_damage 的伤亡同口径）
	var expect := float(hit.get("crew", 0.0))
	if expect > 0.0:
		var dead := int(expect)
		if _rng.randf() < expect - float(dead):
			dead += 1
		dead = mini(dead, maxi(0, crew - 1))
		if dead > 0:
			crew -= dead


func _rest_modulate() -> Color:
	return Color(0.72, 0.7, 0.68) if struck else Color.WHITE  # 降了：落帆，船色发灰


func _explode() -> void:
	# 赏金走 SeaChart 结算，击沉不再掉拾取箱。船身残影歪倒没入海面（CombatFx.founder，纯观感），真节点照旧当帧释放
	_ff_look_off()  # lane w53-p3flood：沉前先收火烟 / 戽水（节点随船 queue_free，收在 founder 残影之前，免得冒烟残影定格）
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
