## 海战观感薄层（lane combat09 起按宋元近海写实改）：矢石命中的木屑与尘烟、船上的焦帆 / 舀水花 / 降幡、沉船残迹，
## 以及分阶段的纪实短注（进水、失火、降幡、接舷、溃逃）。不改伤害 / 齐射 / 刷船数值，也不判哪条船进水、失火、降幡——
## 那归损伤、士气模型；本文件只按调用方给的状态出观感与文字。
## 调用方：WorldMap（开战/接舷/结算）、Cannonball（命中）、BoardingStage、SeaChart（战果飘字）。
## 新入口 on_missile_hit / set_fire / set_flood / strike_colors / on_ship_sunk 与各阶段短注，供弹道、损伤、士气、敌将各线接线。
## 命中不顿帧；打中敌船不震镜头（远处看得见木屑，手上不该跟着抖），本船挨打才轻颤一下。hitstop 只留给接舷白刃那几拍。
## headless / -s 工具脚本下顿帧与震屏跳过（Engine.time_scale 仍复位），粒子照常可实例化（探针在 headless 下也能数节点）。
## 船上的持续观感挂在船节点下（FxFire / FxFlood / FxStrike，入组 GROUP），随船释放；收尾只用子 Timer 与补间，不 await、不留协程。
extends RefCounted

const Kit := preload("res://scripts/cutscene/cs_kit.gd")
const IMPACT_PATH := "res://scenes/ImpactExplosion.tscn"
const SPLASH_PATH := "res://scenes/WaterSplash.tscn"
const GROUP := "nk1_combat_fx"

## 船图契约（钩子线、海寇线、美术包线共用）：海战精灵 = assets/ship_<id>.png，文件在才用，不在就回落默认贴图。
##   己方旗舰：id = 旗舰 ships.json type，回落 ship_fu.png（Ship.tscn 里挂的那张）
##   敌船：id = enemy.sprite，没有就用 type，回落 ship_falcon.png（PirateShip.tscn 里挂的那张）
## 两张默认贴图由出图方同名重画；新槽（ship_pirate_boat / ship_sea_falcon / ship_yuan_patrol …）收一张生效一张。
## 门禁（check_symbols 十节）：ship_<x>.png 若存在须 512² RGBA，x 须是 ships.json 的 type 或 SHIP_SPRITE_EXTRA 里的名字。
const SHIP_SPRITE_FMT := "res://assets/ship_%s.png"
const SHIP_SPRITE_OWN := "res://assets/ship_fu.png"
const SHIP_SPRITE_ENEMY := "res://assets/ship_falcon.png"
## 不是 ships.json type、却可以当精灵 id 的名字：enemy.sprite 专用（元军哨船 type 仍是 sea_falcon）
const SHIP_SPRITE_EXTRA := ["yuan_patrol"]

## 矢石命中的种类（on_missile_hit 的 kind）。宋元近海以砲（抛石）、床子弩、火箭为主，火药只见霹雳炮、蒺藜火球一类，
## 不是近代舰炮：
##   stone：砲石、铁弹——船板迸出木屑、一蓬尘烟（Cannonball 现有的炮弹按这一种算）
##   bolt：床子弩大箭——扎进船板，木屑少、不起烟
##   fire：火箭、火砲——火星四溅、一缕焦烟；落在帆上即焦帆（起不起火归损伤模型，起了调 set_fire）
##   bomb：霹雳炮、火球——一闪、一团浅色火药烟，木屑多
const HIT_KINDS := ["stone", "bolt", "fire", "bomb"]
## 船节点下持续观感的子节点名
const FIRE_NODE := "FxFire"
const FLOOD_NODE := "FxFlood"
const STRIKE_NODE := "FxStrike"
## 落点离旗舰中心这么近才算打在本船上（船体碰撞半径 24，炮弹进圈即结算，留出弹径与一帧位移）
const OWN_HIT_RADIUS := 72.0
## 船图局部坐标（船首朝 -y；Sprite2D 缩 0.62，512 图约合长 280、宽 100）：帆区中心与半幅、两舷离中线、船头旗位
const SAIL_CENTER := Vector2(0, -18)
const SAIL_EXTENTS := Vector2(20, 44)
const BEAM_HALF := 44.0
const BANNER_AT := Vector2(0, -118)
## 色：船板木屑（旧板面深、新茬浅，逐粒在两端之间取）、砲石尘、焦烟、帆篷烧出的烟灰、火药烟、扑火白汽、水沫
const C_WOOD := Color(0.40, 0.27, 0.15)
const C_WOOD_FRESH := Color(0.86, 0.74, 0.54)
const C_DUST := Color(0.64, 0.58, 0.50, 0.72)
const C_CHAR := Color(0.14, 0.12, 0.10, 0.72)
const C_SOOT := Color(0.27, 0.24, 0.21, 0.75)
const C_POWDER := Color(0.86, 0.84, 0.80, 0.74)
const C_STEAM := Color(0.88, 0.90, 0.90, 0.55)
const C_FOAM := Color(0.88, 0.94, 0.97, 0.80)
## 降幡的白幡（素绢，不是纯白：与宣纸字色同一路）
const C_BANNER := Color(0.94, 0.92, 0.86, 0.96)


## 按船图契约取精灵路径。id 空、或 assets/ship_<id>.png 不在，就回落 fallback；不读 autoload，-s 探针可直接调。
static func ship_sprite_path(sprite_id: String, fallback: String) -> String:
	var sid := sprite_id.strip_edges()
	if sid == "" or not sid.is_valid_filename():
		return fallback
	var path := SHIP_SPRITE_FMT % sid
	if ResourceLoader.exists(path, "Texture2D"):
		return path
	return fallback


## 把 sprite 换成 path 指的贴图；已是这张就不动。load 失败保留原贴图（画面零变化）。
static func apply_ship_sprite(sprite: Sprite2D, path: String) -> void:
	if sprite == null:
		return
	if sprite.texture != null and sprite.texture.resource_path == path:
		return
	var tex := load(path) as Texture2D
	if tex != null:
		sprite.texture = tex

## 顿帧：短时压低 time_scale，结束后复原。叠加以最后一次为准。
static var _hitstop_token := 0


static func hitstop(host: Node, duration := 0.07, scale := 0.18) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if Kit.is_headless():
		return
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	var tree := host.get_tree()
	if tree == null:
		Engine.time_scale = 1.0
		return
	# 用真实秒（不受 time_scale 影响）计时
	var timer := tree.create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		if token == _hitstop_token:
			Engine.time_scale = 1.0
	)


## 在旗舰 Camera2D 上叠加一次短震（与航速震共用 offset，随后被 Ship 平滑拉回）。
static func punch_camera(ship: Node, intensity := 6.0) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if Kit.is_headless():
		return
	var cam: Camera2D = ship.get("camera") as Camera2D
	if cam == null:
		var n := ship.get_node_or_null("Camera2D")
		cam = n as Camera2D
	if cam == null:
		return
	cam.offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))


# ── 矢石命中 ─────────────────────────────────────────────────────────

## 炮弹命中（Cannonball 现调这一支，ship 传的是开火方）：按砲石算；落点在本船身上才震镜头，不顿帧。
static func on_cannon_hit(world: Node, at: Vector2, ship: Node = null) -> void:
	if world == null or not is_instance_valid(world):
		return
	on_missile_hit(world, at, "stone", _hits_own_ship(world, at, ship))


## 矢石命中船体：kind 见 HIT_KINDS（认不得的按 stone）。own_hit：挨打的是本船——镜头轻颤一下，甲板跟着一震。
static func on_missile_hit(world: Node, at: Vector2, kind := "stone", own_hit := false) -> void:
	if world == null or not is_instance_valid(world):
		return
	if own_hit:
		punch_camera(world.get("ship") as Node, 3.5)
	match kind:
		"bolt":
			_spawn_splinters(world, at, 6)
		"fire":
			_spawn_sparks(world, at)
			_spawn_smoke(world, at, C_CHAR, 5, 0.6)
		"bomb":
			_spawn_flash(world, at)
			_spawn_splinters(world, at, 18)
			_spawn_smoke(world, at, C_POWDER, 9, 1.0)
		_:
			_spawn_splinters(world, at, 12)
			_spawn_smoke(world, at, C_DUST, 6, 0.75)


## 落点是不是本船：world.ship（WorldMap 的旗舰）在、开火的不是它、落点离它中心不过 OWN_HIT_RADIUS
static func _hits_own_ship(world: Node, at: Vector2, shooter: Node) -> bool:
	var own := world.get("ship") as Node2D
	if own == null or not is_instance_valid(own) or own == shooter:
		return false
	return own.position.distance_to(at) <= OWN_HIT_RADIUS


## 沉船：原地一圈白沫、几块漂木、一串气泡；burned（烧沉的）另加一缕余烟。船节点释放之前调，at 是船的位置。
static func on_ship_sunk(world: Node, at: Vector2, burned := false) -> void:
	if world == null or not is_instance_valid(world):
		return
	var ring := _burst(world, at, 20, 1.6, 4, "soft_dot.png")
	ring.explosiveness = 0.85
	ring.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	ring.emission_ring_radius = 34.0
	ring.emission_ring_inner_radius = 24.0
	ring.radial_accel_min = 26.0
	ring.radial_accel_max = 48.0
	ring.damping_min = 8.0
	ring.damping_max = 16.0
	ring.scale_amount_min = 0.22
	ring.scale_amount_max = 0.42
	ring.color = C_FOAM
	ring.color_ramp = _fade_ramp()
	var wreck := _burst(world, at, 10, 3.2, 5)
	wreck.explosiveness = 0.9
	wreck.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	wreck.emission_sphere_radius = 22.0
	wreck.spread = 180.0
	wreck.initial_velocity_min = 6.0
	wreck.initial_velocity_max = 20.0
	wreck.damping_min = 2.0
	wreck.damping_max = 5.0
	wreck.angle_max = 360.0
	wreck.angular_velocity_min = -30.0
	wreck.angular_velocity_max = 30.0
	wreck.scale_amount_min = 2.5
	wreck.scale_amount_max = 5.5
	wreck.color = C_WOOD
	wreck.color_ramp = _fade_ramp()
	var bubbles := _burst(world, at, 16, 1.1, 5, "spray_drop.png")
	bubbles.explosiveness = 0.25
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 18.0
	bubbles.spread = 180.0
	bubbles.initial_velocity_min = 4.0
	bubbles.initial_velocity_max = 14.0
	bubbles.scale_amount_min = 0.25
	bubbles.scale_amount_max = 0.55
	bubbles.color = C_FOAM
	bubbles.color_ramp = _fade_ramp()
	if burned:
		_spawn_smoke(world, at, C_CHAR, 10, 1.3)


# ── 船上的持续观感：失火（焦帆）/ 进水（舀水花）/ 降幡 ──────────────────
# level 0–1 是损伤模型给的火势 / 进水程度；≤ 0 即扑灭 / 水止：停喷，余烟余沫放完自删。反复调只改强弱，不重建节点。
# 返回船上的该节点（从没挂过返回 null；正在收尾的照样返回它），探针数节点用。

## 焦帆：帆区起火苗、火星、焦烟（烟用世界坐标，船走烟拖在后面）。扑灭时帆上冒一蓬白汽。
## wind：风往哪吹（世界坐标，长度 0–1 表风力；缺省无风，烟只往上散），烟与火星顺风拖。
static func set_fire(ship: Node2D, level: float, wind := Vector2.ZERO) -> Node2D:
	if ship == null or not is_instance_valid(ship):
		return null
	var fx := ship.get_node_or_null(FIRE_NODE) as Node2D
	if level <= 0.0:
		if fx != null and _wind_down(fx, 3.0):
			_spawn_smoke(ship.get_parent(), _in_parent(ship, SAIL_CENTER), C_STEAM, 6, 0.7)
		return fx
	if fx == null:
		fx = _fire_rig(ship)
	_revive(fx)
	var lv := clampf(level, 0.0, 1.0)
	var flame := fx.get_node("Flame") as CPUParticles2D
	flame.emission_rect_extents = SAIL_EXTENTS * lerpf(0.35, 1.0, lv)
	flame.scale_amount_min = lerpf(0.20, 0.38, lv)
	flame.scale_amount_max = lerpf(0.36, 0.74, lv)
	flame.initial_velocity_max = lerpf(26.0, 64.0, lv)
	var drift := wind.limit_length(1.0) * 70.0
	var ember := fx.get_node("Ember") as CPUParticles2D
	ember.emitting = lv >= 0.3
	ember.gravity = Vector2(0, -42) + drift * 0.6
	var smoke := fx.get_node("Smoke") as CPUParticles2D
	smoke.emission_rect_extents = SAIL_EXTENTS * lerpf(0.3, 0.8, lv)
	smoke.gravity = Vector2(4, -18) + drift
	smoke.color = Color(C_SOOT, lerpf(0.45, 0.8, lv))
	smoke.scale_amount_min = lerpf(0.22, 0.32, lv)
	smoke.scale_amount_max = lerpf(0.38, 0.62, lv)
	fx.set_meta(&"level", lv)
	return fx


## 进水：水手往舷外舀水（先一舷、再两舷），水多了甲板上漫起水沫（船身吃水渐深）。
static func set_flood(ship: Node2D, level: float) -> Node2D:
	if ship == null or not is_instance_valid(ship):
		return null
	var fx := ship.get_node_or_null(FLOOD_NODE) as Node2D
	if level <= 0.0:
		if fx != null:
			_wind_down(fx, 1.6)
		return fx
	if fx == null:
		fx = _flood_rig(ship)
	_revive(fx)
	var lv := clampf(level, 0.0, 1.0)
	for side in ["BailR", "BailL"]:
		var bail := fx.get_node(side) as CPUParticles2D
		bail.initial_velocity_min = lerpf(50.0, 80.0, lv)
		bail.initial_velocity_max = lerpf(90.0, 140.0, lv)
	(fx.get_node("BailL") as CPUParticles2D).emitting = lv >= 0.34
	(fx.get_node("Wash") as CPUParticles2D).emitting = lv >= 0.67
	fx.set_meta(&"level", lv)
	return fx


## 降幡：船头升起一面素绢白幡（敌船落帆请降）。已升过的不再升；随船释放。返回幡节点。
static func strike_colors(ship: Node2D) -> Node2D:
	if ship == null or not is_instance_valid(ship):
		return null
	var fx := ship.get_node_or_null(STRIKE_NODE) as Node2D
	if fx != null:
		return fx
	fx = Node2D.new()
	fx.name = STRIKE_NODE
	fx.position = BANNER_AT
	fx.z_index = 3
	fx.add_to_group(GROUP)
	var pole := Line2D.new()
	pole.name = "Pole"
	pole.width = 2.0
	pole.default_color = Color(Kit.C_JIAOMO, 0.9)
	pole.points = PackedVector2Array([Vector2(0, -4), Vector2(0, 16)])
	fx.add_child(pole)
	var banner := Polygon2D.new()
	banner.name = "Banner"
	banner.color = C_BANNER
	# 燕尾幡：挂在杆头，向右舷拖开
	banner.polygon = PackedVector2Array([Vector2(0, -3), Vector2(30, 0), Vector2(24, 5), Vector2(31, 10), Vector2(0, 11)])
	fx.add_child(banner)
	ship.add_child(fx)
	# 升幡 0.5 s，随后迎风轻摆；补间挂在幡节点上，随船释放一并停掉
	banner.scale = Vector2(1.0, 0.1)
	fx.create_tween().tween_property(banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var flutter := fx.create_tween().set_loops()
	flutter.tween_property(banner, "skew", 0.26, 0.45).set_trans(Tween.TRANS_SINE)
	flutter.tween_property(banner, "skew", -0.18, 0.45).set_trans(Tween.TRANS_SINE)
	return fx


static func _fire_rig(ship: Node2D) -> Node2D:
	var fx := Node2D.new()
	fx.name = FIRE_NODE
	fx.position = SAIL_CENTER
	fx.z_index = 2
	fx.add_to_group(GROUP)
	var smoke := _emitter(fx, "Smoke", 14, 3.2, "mist_puff.png")
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.spread = 180.0
	smoke.initial_velocity_min = 6.0
	smoke.initial_velocity_max = 22.0
	smoke.damping_min = 2.0
	smoke.damping_max = 6.0
	smoke.angle_max = 360.0
	smoke.scale_amount_curve = _grow_curve()
	smoke.color_ramp = _puff_ramp()
	var flame := _emitter(fx, "Flame", 24, 0.55, "soft_dot.png")
	flame.material = _add_mat()
	flame.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flame.spread = 180.0
	flame.gravity = Vector2(0, -70)
	flame.initial_velocity_min = 6.0
	flame.color_ramp = _flame_ramp()
	var ember := _emitter(fx, "Ember", 12, 1.7, "ember.png")
	ember.material = _add_mat()
	ember.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ember.emission_rect_extents = SAIL_EXTENTS * 0.6
	ember.spread = 180.0
	ember.initial_velocity_min = 16.0
	ember.initial_velocity_max = 58.0
	ember.tangential_accel_min = -16.0
	ember.tangential_accel_max = 16.0
	ember.scale_amount_min = 0.4
	ember.scale_amount_max = 0.9
	ember.color_ramp = _spark_ramp()
	ship.add_child(fx)
	return fx


static func _flood_rig(ship: Node2D) -> Node2D:
	var fx := Node2D.new()
	fx.name = FLOOD_NODE
	fx.z_index = 2
	fx.add_to_group(GROUP)
	var wash := _emitter(fx, "Wash", 12, 1.5, "soft_dot.png")
	wash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wash.emission_rect_extents = Vector2(BEAM_HALF * 0.75, 96)
	wash.spread = 180.0
	wash.initial_velocity_min = 2.0
	wash.initial_velocity_max = 9.0
	wash.scale_amount_min = 0.35
	wash.scale_amount_max = 0.7
	wash.color = Color(0.62, 0.74, 0.80, 0.34)
	wash.color_ramp = _puff_ramp()
	wash.emitting = false
	# 舀水：水手成桶往舷外泼，一阵一阵（explosiveness）；方向按船身局部左右舷，泼出后落回海面
	for side in [["BailR", 1.0], ["BailL", -1.0]]:
		var bail := _emitter(fx, side[0], 12, 0.7, "spray_drop.png")
		bail.position = Vector2(BEAM_HALF * float(side[1]), 8)
		bail.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		bail.emission_rect_extents = Vector2(2, 58)
		bail.direction = Vector2(float(side[1]), 0)
		bail.spread = 24.0
		bail.explosiveness = 0.55
		bail.gravity = Vector2(0, 70)
		bail.damping_min = 110.0
		bail.damping_max = 170.0
		bail.scale_amount_min = 0.35
		bail.scale_amount_max = 0.75
		bail.color = C_FOAM
		bail.color_ramp = _fade_ramp()
	ship.add_child(fx)
	return fx


## 船上持续观感用的发射器：世界坐标（船动了粒子留在原处），入场即喷；重力清零（引擎缺省 (0, 980) 会一路往下掉），要飘的各自给。
static func _emitter(parent: Node, node_name: String, amount: int, lifetime: float, tex := "") -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.gravity = Vector2.ZERO
	if tex != "":
		p.texture = Kit.fx_texture(tex)
	parent.add_child(p)
	return p


## 收尾：各发射器停喷，余下的粒子放完（after 秒）整组自删。已在收尾的不重排，返回 false。
static func _wind_down(fx: Node2D, after: float) -> bool:
	if fx.get_node_or_null("WindDown") != null:
		return false
	for c in fx.get_children():
		if c is CPUParticles2D:
			(c as CPUParticles2D).emitting = false
	var t := Timer.new()
	t.name = "WindDown"
	t.one_shot = true
	t.wait_time = after
	t.autostart = true
	t.timeout.connect(fx.queue_free)
	fx.add_child(t)
	return true


## 收尾途中又起（复燃 / 又进水）：撤掉收尾计时，发射器重新喷；具体哪几支喷由调用方按 level 再定。
static func _revive(fx: Node2D) -> void:
	var t := fx.get_node_or_null("WindDown") as Timer
	if t == null:
		return
	t.stop()
	fx.remove_child(t)
	t.queue_free()
	for c in fx.get_children():
		if c is CPUParticles2D:
			(c as CPUParticles2D).emitting = true


## 船身局部点 → 船的父节点（战场）局部坐标：一次性粒子挂在战场下，position 按战场局部算
static func _in_parent(ship: Node2D, local_pt: Vector2) -> Vector2:
	var p := ship.get_parent() as Node2D
	return p.to_local(ship.to_global(local_pt)) if p != null else ship.to_global(local_pt)


# ── 一次性粒子 ───────────────────────────────────────────────────────

## 一次性粒子：延迟一帧入场（命中多在物理回调里，当场 add_child 不稳），入场即喷，放完（finished）自删；重力同上清零。
static func _burst(world: Node, at: Vector2, amount: int, lifetime: float, z := 18, tex := "") -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = z
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.gravity = Vector2.ZERO
	p.emitting = false
	if tex != "":
		p.texture = Kit.fx_texture(tex)
	p.add_to_group(GROUP)
	p.ready.connect(p.set_emitting.bind(true), CONNECT_ONE_SHOT)
	p.finished.connect(p.queue_free)
	world.call_deferred("add_child", p)
	return p


## 木屑：船板迸出的碎片（旧板面深、新茬浅），四散、打着转落回水面
static func _spawn_splinters(world: Node, at: Vector2, amount: int) -> void:
	var p := _burst(world, at, amount, 0.9, 19)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.spread = 180.0
	p.gravity = Vector2(0, 90)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 170.0
	p.damping_min = 120.0
	p.damping_max = 200.0
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 2.2
	p.scale_amount_max = 5.0
	p.color_initial_ramp = _ramp("wood", [[0.0, C_WOOD], [1.0, C_WOOD_FRESH]])
	p.color_ramp = _fade_ramp()


## 一蓬烟（砲石尘 / 焦烟 / 火药烟 / 扑火白汽，按 tint）：慢慢鼓起、往上飘散
static func _spawn_smoke(world: Node, at: Vector2, tint: Color, amount: int, size: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := _burst(world, at, amount, 1.5, 18, "soft_dot.png")
	p.explosiveness = 0.75
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.spread = 180.0
	p.gravity = Vector2(4, -16)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 38.0
	p.damping_min = 18.0
	p.damping_max = 36.0
	p.angle_max = 360.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.2
	p.scale_amount_curve = _grow_curve()
	p.color = tint
	p.color_ramp = _puff_ramp()


## 火箭命中：火星四溅，很快熄
static func _spawn_sparks(world: Node, at: Vector2) -> void:
	var p := _burst(world, at, 14, 0.6, 20, "ember.png")
	p.material = _add_mat()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.spread = 180.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 140.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.color_ramp = _spark_ramp()


## 霹雳炮炸开的一闪（火药不多，闪一下就没）
static func _spawn_flash(world: Node, at: Vector2) -> void:
	var p := _burst(world, at, 2, 0.16, 21, "glow_warm.png")
	p.material = _add_mat()
	p.explosiveness = 1.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.65
	p.color_ramp = _ramp("flash", [[0.0, Color(1.0, 0.95, 0.82, 0.9)], [1.0, Color(1.0, 0.7, 0.4, 0.0)]])


# ── 色阶与曲线（共用，按名缓存）────────────────────────────────────────

static var _cache := {}


static func _ramp(key: String, points: Array) -> Gradient:
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for pt in points:
		offs.append(float(pt[0]))
		cols.append(pt[1])
	g.offsets = offs
	g.colors = cols
	_cache[key] = g
	return g


## 满色进场、末段淡出（木屑、水沫、气泡）
static func _fade_ramp() -> Gradient:
	return _ramp("fade", [[0.0, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0)]])


## 烟团：淡入、停一会、淡出
static func _puff_ramp() -> Gradient:
	return _ramp("puff", [[0.0, Color(1, 1, 1, 0)], [0.18, Color(1, 1, 1, 1)], [0.65, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]])


## 火苗：焰心发白 → 橙 → 暗红散去（加色混合）
static func _flame_ramp() -> Gradient:
	return _ramp("flame", [
		[0.0, Color(1.0, 0.92, 0.7, 0.0)], [0.12, Color(1.0, 0.8, 0.42, 0.9)],
		[0.5, Color(0.98, 0.45, 0.14, 0.7)], [1.0, Color(0.5, 0.1, 0.04, 0.0)],
	])


## 火星：亮黄 → 橙 → 暗红熄灭（加色混合）
static func _spark_ramp() -> Gradient:
	return _ramp("spark", [
		[0.0, Color(1.0, 0.9, 0.62, 0.0)], [0.08, Color(1.0, 0.82, 0.45, 1.0)],
		[0.5, Color(1.0, 0.5, 0.16, 0.85)], [1.0, Color(0.6, 0.12, 0.04, 0.0)],
	])


## 烟越飘越大：出生 0.55 倍，末了满倍
static func _grow_curve() -> Curve:
	if _cache.has("grow"):
		return _cache["grow"]
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.55))
	c.add_point(Vector2(1.0, 1.0))
	_cache["grow"] = c
	return c


static func _add_mat() -> CanvasItemMaterial:
	if _cache.has("add"):
		return _cache["add"]
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cache["add"] = m
	return m


# ── 分阶段纪实短注（进水 / 失火 / 降幡 / 接舷 / 溃逃）──────────────────
# 飘字与战况日志用：只写看得见的事，无叹号、不报血量。who 是船名，空就按 foe 写「敌船」/「本船」；
# 敌船名前冠「敌船」，与 board_win_note 同一写法。level / stage 越界的按两端算。

## 进水四级：0 渗漏 / 1 一舱进水（福船分舱，隔舱挡得住）/ 2 数舱进水 / 3 沉没
const FLOOD_NOTES := [
	"%s船板中石渗水，水手舀水塞漏。",
	"%s一舱进水，隔舱尚固。",
	"%s数舱进水，船身侧倾，行船迟重。",
	"%s进水不止，渐没于波。",
]
## 失火四拍：0 起火 / 1 延烧 / 2 扑灭 / 3 焚毁
const FIRE_NOTES := [
	"%s帆篷中火箭，火起。",
	"%s火延舱面，水手泼水、覆湿毡扑救。",
	"%s火已扑灭，帆焦半幅。",
	"%s烈焰焚舟，舟人纷纷落水。",
]


## 船的称呼：敌船「海鹘」/「福船」；没有船名写「敌船」/「本船」
static func ship_ref(who: String, foe := false) -> String:
	var n := who.strip_edges()
	if n == "":
		return "敌船" if foe else "本船"
	return ("敌船「%s」" if foe else "「%s」") % n


static func flood_note(level: int, who := "", foe := false) -> String:
	return FLOOD_NOTES[clampi(level, 0, FLOOD_NOTES.size() - 1)] % ship_ref(who, foe)


static func fire_note(stage: int, who := "", foe := false) -> String:
	return FIRE_NOTES[clampi(stage, 0, FIRE_NOTES.size() - 1)] % ship_ref(who, foe)


## 敌船降幡请降（配 strike_colors）
static func strike_note(who := "") -> String:
	return "%s落帆降幡，舟人弃械请降。" % ship_ref(who, true)


## 接舷分拍：挠钩落空 / 搭住登舟 / 敌众登舟被逐回
static func grapple_miss_note() -> String:
	return "挠钩落空，敌船擦舷而过。"


static func board_leap_note() -> String:
	return "挠钩搭住敌舷，水手缘索登舟。"


static func board_repel_note(crew_lost: int) -> String:
	return "敌众登舟，已被逐回。水手减员 %d。" % maxi(0, crew_lost)


## 我方溃逃：水手无斗志、弃战奔逃（配出战墨边「溃逃」）
static func rout_note(crew_lost := 0) -> String:
	var base := "水手溃散，争下舢板，本船弃战奔逃。"
	return base if crew_lost <= 0 else base + "水手减员 %d。" % crew_lost


## 论文纪实短注（飘字用）：无叹号、无营销词。
static func board_win_note(ship_name: String) -> String:
	var n := ship_name.strip_edges()
	if n == "":
		n = "敌船"
	return "接舷既定。敌船「%s」并入本队。" % n


static func board_lose_note(crew_lost: int) -> String:
	return "白刃不利。水手减员 %d。敌船脱钩。" % maxi(0, crew_lost)


## date_str 由调用方传入（Calendar.get_date_string()），本文件不直接引用 autoload，便于 -s 探针预加载。
static func battle_enter_subtitle(enemy_count: int, date_str := "") -> String:
	if date_str.strip_edges() == "":
		return "敌船 %d 艘" % enemy_count
	return "%s　敌船 %d 艘" % [date_str.strip_edges(), enemy_count]


## 接舷开场副题（题签下沿）。
static func board_begin_subtitle() -> String:
	return "钩索已抛"


## 海图战果注记（SeaChart._on_battle_result 用）：克制纪实，无叹号。
static func sea_win_note(spoil: int, damage: int, promo := "") -> String:
	var base := "海盗已退。获财货 %d 钱。船体受损 %d。" % [maxi(0, spoil), maxi(0, damage)]
	var p := promo.strip_edges()
	return base if p == "" else base + p


static func sea_sunk_note(cargo_str: String, damage: int, fleet_gone: bool) -> String:
	var cargo := cargo_str.strip_edges()
	if fleet_gone:
		return "旗舰沉没，货舱随船。%s船体受损 %d。" % [cargo, maxi(0, damage)]
	return "旗舰沉没，该船货物随船。%s余船尚在。船体受损 %d。" % [cargo, maxi(0, damage)]


static func sea_board_lose_note(cargo_str: String, damage: int) -> String:
	return "白刃不利，货舱被夺。%s船体受损 %d。" % [cargo_str.strip_edges(), maxi(0, damage)]


static func sea_flee_ok_note() -> String:
	return "转舵抢上风头，把追船甩在后面。绕了些路。"


static func sea_flee_fail_note(cargo_str: String) -> String:
	return "未能甩脱。被追上跳帮，货舱被夺。%s" % cargo_str.strip_edges()


## 敌船降幡（出战「受降」）：货与人一并收押，账目写法同 sea_win_note
static func sea_surrender_note(spoil: int, damage: int, promo := "") -> String:
	var base := "敌船降幡，货与人一并收押。获财货 %d 钱。船体受损 %d。" % [maxi(0, spoil), maxi(0, damage)]
	var p := promo.strip_edges()
	return base if p == "" else base + p


## 我方溃逃（出战「溃逃」）：弃货奔逃
static func sea_rout_note(cargo_str: String, crew_lost: int) -> String:
	return "水手溃散，弃货奔逃。%s水手减员 %d。" % [cargo_str.strip_edges(), maxi(0, crew_lost)]
