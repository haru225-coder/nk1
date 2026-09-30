## 海战观感薄层（lane combat09 起按宋元近海写实改）：矢石命中的木屑与尘烟、船上的焦帆 / 舀水花 / 降幡、沉船残迹，
## 以及分阶段的纪实短注（进水、失火、降幡、接舷、溃逃）。不改伤害 / 齐射 / 刷船数值，也不判哪条船进水、失火、降幡——
## 那归损伤、士气模型；本文件只按调用方给的状态出观感与文字。
## 调用方：WorldMap（开战/接舷/结算）、Cannonball（命中）、BoardingStage、SeaChart（战果飘字）。
## 新入口 on_missile_hit / set_fire / set_flood / strike_colors / on_ship_sunk 与各阶段短注，供弹道、损伤、士气、敌将各线接线。
## 打中敌船不震镜头（远处看得见木屑，手上不该跟着抖）——敌船自己挨：命中处一闪、船身顺来力一颤、留焦痕（hull_impact）；
## 本船挨打才推镜头（按轻重、顺来力）、重的加一拍屏幕错位与极短顿帧（combat12 分层）。一闪都是星芒短拍，不用软白晕。
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


## 海战里挂在世界坐标上的字（敌船意图签、本船损伤短注、飘字）与镜头震幅原是按旗舰镜头 zoom 1.5 定的尺寸。
## w19-g13 把海战镜头拉远到 0.5（Ship.CAM_ZOOM_REST）后，这些按「1.5 ÷ 现镜头 zoom」反缩放，屏上字号、震幅与原先一样。
const WORLD_TEXT_REF_ZOOM := 1.5


## 世界坐标里字 / 震幅的反缩放系数（没有镜头时 1.0）
static func world_text_k(node: Node) -> float:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return 1.0
	var vp := node.get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam == null or cam.zoom.x <= 0.0:
		return 1.0
	return WORLD_TEXT_REF_ZOOM / cam.zoom.x


## 在旗舰 Camera2D 上叠加一次短震（与航速震共用 offset，随后被 Ship 以 5/s 平滑拉回，约 0.2 s 回正）。
## dir 给了就顺着它推（本船挨打：顺来力；齐射：反舷后坐），另带一点横向抖；没给按旧式随机方向。
## zoom_kick：镜头往里一收（× 1 + zoom_kick，封顶 8 %），Ship 按航速缩放镜头时约 1 s 缓回——重的一下有「沉」感。
static func punch_camera(ship: Node, intensity := 6.0, dir := Vector2.ZERO, zoom_kick := 0.0) -> void:
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
	intensity *= world_text_k(ship)
	if dir.length_squared() > 0.0001:
		var d := dir.normalized()
		cam.offset = d * intensity + d.orthogonal() * randf_range(-0.3, 0.3) * intensity
	else:
		cam.offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	if zoom_kick > 0.0:
		cam.zoom *= 1.0 + clampf(zoom_kick, 0.0, 0.08)


## 命中轻重 0.2–1.2：按弹种给底（箭轻、砲石重、霹雳炮最重）；有杀伤点数（DamageModel 口径，砲石一发 30）就按点数算。
## 船身一颤、命中一闪、焦痕大小、本船镜头推多远都按它。
const KIND_SEVERITY := {"bolt": 0.55, "arrow": 0.35, "stone": 0.9, "fire": 0.5, "bomb": 1.1}


static func hit_severity(kind: String, amount := -1.0) -> float:
	var base := float(KIND_SEVERITY.get(kind, 0.6))
	if amount < 0.0:
		return base
	var s := amount / 30.0
	match kind:
		"bomb":
			s += 0.25
		"bolt", "arrow":
			s *= 0.8
	return clampf(s, 0.2, 1.2)


# ── 出海船着装与船身反应（lane ship-vfx）────────────────────────────────
## 着装：船身 shader ship_seagoing（帆抖、命中一记炽橙、焦痕）+ 船身反应节点 FxLook（_Look：命中一闪衰减、焦痕表、
## 旗舰挨重时的屏幕一拍；隐藏旧的方点尾迹 WakeParticles）。每船只挂一次，可反复调刷新风向。
## 与别线分工：投影 / 贴舷白浪 / 受光 / 摇曳归 ShipLook（HullWater、HullLight，combat12-E），航迹白练 / 敌船朱边 / 旗旒 / 涟漪
## 归 SeaAtmosphere（lane atmos）；这里不再画影子、不再画航迹。一颤仍走 hull_shudder 的 scale / rotation 补间（ShipLook 两层照抄变换）。
const LOOK_NODE := "FxLook"
const SHIP_SHADER := "res://assets/shaders/ship_seagoing.gdshader"
const KICK_SHADER := "res://assets/shaders/screen_kick.gdshader"
const _Ballistics := preload("res://scripts/combat/Ballistics.gd")
## 舷侧炮位间距上限（船长方向，px）
const MUZZLE_SPACING := 22.0
## 齐射 / 命中一闪的暖白
const C_FLASH := Color(1.0, 0.86, 0.56)
## 砲石砸碎船板扬起的木尘（深于砲石尘：落在奶油硬帆上也看得见）
const C_WOOD_DUST := Color(0.46, 0.36, 0.26, 0.82)
## 出手焰：橙黄（加色在深海上不能太白，太白就成一团白光）
const C_MUZZLE := Color(1.0, 0.6, 0.24)
## 火药烟（比砲石尘偏灰、偏冷一点）
const C_GUNSMOKE := Color(0.80, 0.78, 0.74, 0.88)


static func dress_ship(ship: Node2D, wind := Vector2.ZERO) -> Node2D:
	if ship == null or not is_instance_valid(ship):
		return null
	var sprite := ship.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		_apply_seagoing_mat(sprite, wind)
	var look := ship.get_node_or_null(LOOK_NODE) as Node2D
	if look == null and sprite != null:
		look = _Look.new()
		look.name = LOOK_NODE
		(look as _Look).setup(ship, sprite, not _is_foe(ship))
		ship.add_child(look)
	return look


## 敌船：PirateShip 有 ship_type、入 nk1_enemy_ships 组；旗舰都没有
static func _is_foe(ship: Node) -> bool:
	return ship.is_in_group("nk1_enemy_ships") or ship.get("ship_type") != null


static func _look_of(ship) -> _Look:
	if ship == null or not is_instance_valid(ship):
		return null
	return (ship as Node).get_node_or_null(LOOK_NODE) as _Look


## 船上已挂船身反应节点（挂了就不再用 modulate 闪红：一闪交给 shader、一颤交给 hull_shudder）
static func has_look(ship) -> bool:
	return _look_of(ship) != null


static func _apply_seagoing_mat(sprite: Sprite2D, wind: Vector2) -> void:
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader == null or mat.shader.resource_path != SHIP_SHADER:
		var sh := load(SHIP_SHADER) as Shader
		if sh == null:
			return
		mat = ShaderMaterial.new()
		mat.shader = sh
		sprite.material = mat
	var w := wind.limit_length(1.0)
	# 精灵局部：船首 -y，把世界风旋进船局部
	var ship := sprite.get_parent() as Node2D
	var local := w
	if ship != null:
		local = w.rotated(-ship.rotation)
	mat.set_shader_parameter("wind_dir", local if local.length() > 0.05 else Vector2(0.12, -0.35))
	mat.set_shader_parameter("wind_strength", clampf(w.length(), 0.15, 1.0))


## 船身挨了一发（Cannonball._strike 在交完杀伤之后调；敌我都调）：命中处一记炽橙、砲石 / 火器 / 重的留焦痕，
## 船身往背着来力的一舷一颤（hull_shudder，轻重按 hit_severity）。at / from 是全局坐标（落点 / 出膛点）；
## amount 是 DamageModel 口径的命中点数（缺省按弹种）。没挂 _Look 的船不做。
static func hull_impact(ship, at: Vector2, from: Vector2, kind := "stone", amount := -1.0) -> void:
	var look := _look_of(ship)
	if look == null:
		return
	var sev := hit_severity(kind, amount)
	look.impact(at, sev, kind)
	# 来力从哪一舷进：船局部 x 的正负（+x 右舷）；往另一舷坐
	var n2 := ship as Node2D
	var local := (from - n2.global_position).rotated(-n2.global_rotation)
	hull_shudder(n2, 0.6 + 0.7 * sev, -1 if local.x > 0.0 else 1)


## 甲板颤：本船挨打 / 本船齐射后坐时，船身 scale 一挤、略侧倾，再弹回。叠加以最后一次为准。
## intensity 约 0.5–1.5；headless 跳过（探针仍可数 tween 前的 scale 元数据）。
static func hull_shudder(ship: Node2D, intensity := 1.0, side := 0) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var sprite := ship.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	var iv := clampf(intensity, 0.25, 2.0)
	if not ship.has_meta(&"nk1_sprite_base_scale"):
		ship.set_meta(&"nk1_sprite_base_scale", sprite.scale)
	var base: Vector2 = ship.get_meta(&"nk1_sprite_base_scale")
	# 挤扁：横向按舷侧方向略压，纵向略抻
	var squash := Vector2(1.0 - 0.06 * iv, 1.0 + 0.04 * iv)
	if side != 0:
		squash = Vector2(1.0 + 0.03 * iv * sign(float(side)), 1.0 - 0.05 * iv)
	sprite.scale = base * squash
	var roll := 0.07 * iv * (1.0 if side == 0 else float(side))
	var rig := ship.get_node_or_null("HullRig")
	var use_rig := rig != null and rig.has_method("shudder")
	if not use_rig:
		sprite.rotation = roll
	if Kit.is_headless():
		# headless：立刻复位，只留一帧可观测的 scale 变化痕迹
		sprite.scale = base
		if not use_rig:
			sprite.rotation = 0.0
		return
	if ship.has_meta(&"nk1_shudder_tween"):
		var old = ship.get_meta(&"nk1_shudder_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := ship.create_tween()
	ship.set_meta(&"nk1_shudder_tween", tw)
	tw.set_parallel(true)
	tw.tween_property(sprite, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if use_rig:
		rig.call("shudder", roll)
	else:
		tw.tween_property(sprite, "rotation", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 本船挨重的一拍屏幕反应（红蓝错位 + 四角一暗，约 0.15 s）；只旗舰（有镜头的那条）挂得上。push 是世界里的来力方向。
static func screen_kick(ship, severity: float, push := Vector2.ZERO) -> void:
	var look := _look_of(ship)
	if look == null or Kit.is_headless():
		return
	look.kick(severity, push)


## 船体椭圆（半长, 半宽），与弹道判命中同一把尺
static func _hull_ab(ship: Node) -> Vector2:
	return _Ballistics.hull_footprint(ship)


## 舷侧齐射出手：side -1 左舷 / +1 右舷；ports 炮位数（封顶 9）。每位一记短促暖闪（星芒顺出手方向拉长，约 0.09 s）+
## 几颗顺出手方向的火星拖线 + 一小团火药烟（菜花形烟团，往外推开、顺风飘、慢慢鼓大散去）。挂在战场下，放完自删。
static func muzzle_flash(ship: Node2D, side: int, ports := 3) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var world := ship.get_parent()
	if world == null:
		return
	var n := clampi(ports, 1, 9)
	var ab := _hull_ab(ship)
	var ship_dir := Vector2.UP.rotated(ship.rotation)
	var side_dir := (Vector2.RIGHT if side >= 0 else Vector2.LEFT).rotated(ship.rotation)
	var gap := minf(MUZZLE_SPACING, ab.x * 1.2 / float(n))
	for i in n:
		var along := (float(i) - float(n - 1) * 0.5) * gap
		var at: Vector2 = ship.position + ship_dir * along + side_dir * (ab.y + 3.0)
		_spawn_muzzle_at(world, at, side_dir)


static func _spawn_muzzle_at(world: Node, at: Vector2, out_dir: Vector2) -> void:
	_flash_sprite(world, at + out_dir * 9.0, out_dir.angle(), Vector2(0.85, 0.42), C_MUZZLE, 0.1)
	_flash_sprite(world, at + out_dir * 3.0, randf() * TAU, Vector2(0.3, 0.3), Color(1.0, 0.95, 0.78), 0.07)
	var spark := _burst(world, at, 5, 0.3, 25, "spark_streak.png")
	spark.material = _add_mat()
	spark.particle_flag_align_y = true
	spark.direction = out_dir
	spark.spread = 20.0
	spark.initial_velocity_min = 200.0
	spark.initial_velocity_max = 380.0
	spark.damping_min = 380.0
	spark.damping_max = 620.0
	spark.scale_amount_min = 0.55
	spark.scale_amount_max = 0.95
	spark.color_ramp = _spark_ramp()
	var smoke := _burst(world, at + out_dir * 6.0, 4, 1.9, 22, "smoke_puff.png")
	smoke.explosiveness = 0.95
	smoke.direction = out_dir
	smoke.spread = 28.0
	smoke.gravity = Vector2(3, -8)
	smoke.initial_velocity_min = 55.0
	smoke.initial_velocity_max = 110.0
	smoke.damping_min = 70.0
	smoke.damping_max = 110.0
	smoke.angle_max = 360.0
	smoke.scale_amount_min = 0.18
	smoke.scale_amount_max = 0.3
	smoke.scale_amount_curve = _billow_curve()
	smoke.color = C_GUNSMOKE
	smoke.color_ramp = _puff_ramp()


## 敌船沉没 / 焚毁：留一张船身残影（同贴图、同 shader，焦痕都在）原地歪倒、压暗、没入海面，约 1.8 s；
## 真船节点照旧当帧释放（计数、结算零改动）。连同 on_ship_sunk 的白沫漂木一起出。
static func founder(ship: Node2D, burned := false) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var world := ship.get_parent() as Node2D
	var sprite := ship.get_node_or_null("Sprite2D") as Sprite2D
	if world == null or sprite == null or sprite.texture == null:
		return
	on_ship_sunk(world, ship.position, burned)
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.material = sprite.material
	ghost.transform = world.global_transform.affine_inverse() * sprite.global_transform
	ghost.add_to_group(GROUP)
	world.call_deferred("add_child", ghost)
	ghost.ready.connect(func() -> void:
		var tw := ghost.create_tween().set_parallel(true)
		var tilt := 0.32 * (1.0 if randf() < 0.5 else -1.0)
		tw.tween_property(ghost, "rotation", ghost.rotation + tilt, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(ghost, "scale", ghost.scale * 0.84, 1.8).set_ease(Tween.EASE_IN)
		# 先压暗入水色（0.5 s），再没下去（1.3 s 淡尽）
		tw.tween_property(ghost, "self_modulate", Color(0.36, 0.46, 0.52, 0.85), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(ghost, "self_modulate", Color(0.2, 0.3, 0.36, 0.0), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(ghost.queue_free), CONNECT_ONE_SHOT)


static func on_cannon_hit(world: Node, at: Vector2, ship: Node = null) -> void:
	if world == null or not is_instance_valid(world):
		return
	on_missile_hit(world, at, "stone", _hits_own_ship(world, at, ship))


## 矢石命中：kind 见 HIT_KINDS（认不得的按 stone）。落点上一记短促星芒（加色，≤ 0.1 s），随后按弹种：
##   stone 木屑 + 砲石尘 + 舷边溅水；bolt 木屑少、一点尘；fire 火星拖线 + 焦烟；bomb 大一号的闪 + 火星 + 木屑 + 火药烟。
## own_hit（挨打的是本船）：镜头顺来力推一下（按轻重 5–19 px，另收 0–3.6 % 镜头）、重的加一拍屏幕错位、极短顿帧（combat12 分层：
## 箭矢轻、霹雳重）。船身自己的一闪一颤不在这里——Cannonball 另调 hull_impact，敌我都一样。
static func on_missile_hit(world: Node, at: Vector2, kind := "stone", own_hit := false) -> void:
	if world == null or not is_instance_valid(world):
		return
	if own_hit:
		var own := world.get("ship") as Node2D
		var sev := hit_severity(kind)
		var push := Vector2.ZERO
		if own != null and is_instance_valid(own):
			push = own.position - at
		punch_camera(own, 5.0 + 12.0 * sev, push, 0.03 * sev)
		if sev >= 0.6:
			screen_kick(own, sev, push)
		var stop_d := 0.028
		var stop_s := 0.22
		match kind:
			"bolt":
				stop_d = 0.018
			"bomb":
				stop_d = 0.05
				stop_s = 0.14
		hitstop(world, stop_d, stop_s)
	match kind:
		"bolt":
			_spawn_flash(world, at, 0.35, Color(1.0, 0.78, 0.45))
			_spawn_splinters(world, at, 7)
			_spawn_smoke(world, at, C_DUST, 2, 0.14)
		"fire":
			_spawn_flash(world, at, 0.4, Color(1.0, 0.7, 0.36))
			_spawn_sparks(world, at, 12)
			_spawn_smoke(world, at, C_CHAR, 3, 0.2)
		"bomb":
			_spawn_flash(world, at, 1.4, C_MUZZLE)
			_spawn_sparks(world, at, 16)
			_spawn_splinters(world, at, 16)
			_spawn_smoke(world, at, C_GUNSMOKE, 6, 0.3)
		_:
			_spawn_flash(world, at, 1.05, C_MUZZLE)
			_spawn_splinters(world, at, 18)
			_spawn_smoke(world, at, C_WOOD_DUST, 4, 0.24)
			_spawn_hull_spray(world, at)


## 落点是不是本船：world.ship（WorldMap 的旗舰）在、开火的不是它、落点离它中心不过 OWN_HIT_RADIUS
static func _hits_own_ship(world: Node, at: Vector2, shooter: Node) -> bool:
	var own := world.get("ship") as Node2D
	if own == null or not is_instance_valid(own) or own == shooter:
		return false
	return own.position.distance_to(at) <= OWN_HIT_RADIUS


## 沉船：几块漂木、一串气泡（一圈大涟漪由 SeaAtmosphere 在海面上画）；burned（烧沉的）另加一缕余烟。船节点释放之前调，at 是船的位置。
static func on_ship_sunk(world: Node, at: Vector2, burned := false) -> void:
	if world == null or not is_instance_valid(world):
		return
	# 船没处的大涟漪归 SeaAtmosphere（海面着色器画），这里只出漂木与气泡
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
	wreck.texture = Kit.fx_texture("splinter.png")
	wreck.scale_amount_min = 1.4
	wreck.scale_amount_max = 2.6
	wreck.color = C_WOOD
	wreck.color_ramp = _fade_ramp()
	var bubbles := _burst(world, at, 7, 1.1, 5, "spray_drop.png")
	bubbles.explosiveness = 0.25
	bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	bubbles.emission_sphere_radius = 18.0
	bubbles.spread = 180.0
	bubbles.initial_velocity_min = 4.0
	bubbles.initial_velocity_max = 14.0
	bubbles.scale_amount_min = 0.18
	bubbles.scale_amount_max = 0.32
	bubbles.color = C_FOAM
	bubbles.color_ramp = _fade_ramp()
	if burned:
		_spawn_smoke(world, at, C_CHAR, 8, 0.45)


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
			_spawn_smoke(ship.get_parent(), _in_parent(ship, SAIL_CENTER), C_STEAM, 5, 0.3)
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
	var smoke := _emitter(fx, "Smoke", 14, 3.2, "smoke_puff.png")
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


## 木屑：船板迸出的参差碎片（旧板面深、新茬浅），四散打转、很快落回水面
static func _spawn_splinters(world: Node, at: Vector2, amount: int) -> void:
	var p := _burst(world, at, amount, 0.8, 19, "splinter.png")
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 230.0
	p.damping_min = 220.0
	p.damping_max = 340.0
	p.angle_max = 360.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.15
	p.color_initial_ramp = _ramp("wood", [[0.0, C_WOOD], [1.0, C_WOOD_FRESH]])
	p.color_ramp = _fade_ramp()


## 一蓬烟（砲石尘 / 焦烟 / 火药烟 / 扑火白汽，按 tint）：菜花形烟团（smoke_puff 128 px），size 是贴图倍数；
## 慢慢鼓起、往上风下飘散
static func _spawn_smoke(world: Node, at: Vector2, tint: Color, amount: int, size: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := _burst(world, at, amount, 1.7, 18, "smoke_puff.png")
	p.explosiveness = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5.0
	p.spread = 180.0
	p.gravity = Vector2(4, -12)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 40.0
	p.damping_min = 22.0
	p.damping_max = 40.0
	p.angle_max = 360.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.15
	p.scale_amount_curve = _billow_curve()
	p.color = tint
	p.color_ramp = _puff_ramp()


## 火星拖线：细亮线顺速度拉长（spark_streak + align_y），很快熄
static func _spawn_sparks(world: Node, at: Vector2, amount := 14) -> void:
	var p := _burst(world, at, amount, 0.38, 20, "spark_streak.png")
	p.material = _add_mat()
	p.particle_flag_align_y = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	p.damping_min = 260.0
	p.damping_max = 440.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color_ramp = _spark_ramp()


## 落点一闪：七叉星芒（flash_star 64 px × size），随机转角，0.03 s 撑开、0.1–0.12 s 内收掉——只一拍，不留白晕。
## 落点多在船上（奶油硬帆、亮木板），加色在亮处会冲成白看不见，所以外层星芒用常规混合的炽橙，只有芯是加色
static func _spawn_flash(world: Node, at: Vector2, size := 0.6, tint := C_FLASH) -> void:
	_flash_sprite(world, at, randf() * TAU, Vector2(size, size), tint, 0.12, false)
	_flash_sprite(world, at, randf() * TAU, Vector2(size, size) * 0.45, Color(1.0, 0.95, 0.8), 0.08)


## 一张星芒：rot 转角，scl 终尺寸（贴图倍数），life 秒后收尽自删；additive=false 用常规混合（亮底上也看得见）。延迟一帧入场（同 _burst）
static func _flash_sprite(world: Node, at: Vector2, rot: float, scl: Vector2, tint: Color, life: float, additive := true) -> void:
	if world == null or not is_instance_valid(world):
		return
	var s := Sprite2D.new()
	s.texture = Kit.fx_texture("flash_star.png")
	if additive:
		s.material = _add_mat()
	s.position = at
	s.rotation = rot
	s.z_index = 24
	s.scale = scl * 0.55
	s.modulate = tint
	s.set_meta(&"nk1_flash", true)
	s.add_to_group(GROUP)
	s.ready.connect(func() -> void:
		var tw := s.create_tween()
		tw.tween_property(s, "scale", scl, life * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "modulate:a", 0.0, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(s.queue_free), CONNECT_ONE_SHOT)
	world.call_deferred("add_child", s)


## 砲石砸在舷上：舷边一小簇溅水（水滴顺速度拉长）+ 一圈白沫
static func _spawn_hull_spray(world: Node, at: Vector2) -> void:
	var p := _burst(world, at, 10, 0.55, 17, "water_drop.png")
	p.particle_flag_align_y = true
	p.spread = 180.0
	p.initial_velocity_min = 70.0
	p.initial_velocity_max = 170.0
	p.damping_min = 160.0
	p.damping_max = 260.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	p.color = C_FOAM
	p.color_ramp = _fade_ramp()
	var ring := _burst(world, at, 1, 0.9, 16, "foam_ring.png")
	ring.explosiveness = 1.0
	ring.scale_amount_min = 0.55
	ring.scale_amount_max = 0.55
	ring.scale_amount_curve = _grow_curve()
	ring.color = Color(C_FOAM, 0.7)
	ring.color_ramp = _fade_ramp()


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


## 烟团鼓大：出生 0.45 倍，前三成时间撑到八成，末了满倍（火药烟先猛后缓）
static func _billow_curve() -> Curve:
	if _cache.has("billow"):
		return _cache["billow"]
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.45))
	c.add_point(Vector2(0.3, 0.8))
	c.add_point(Vector2(1.0, 1.0))
	_cache["billow"] = c
	return c


# ── 船身反应节点（dress_ship 挂在船下，名 FxLook）───────────────────────
## 逐帧：命中一记炽橙按帧衰减、写焦痕表（船身 shader 的 hit / scars）；旗舰另挂一层屏幕错位（ScreenKick），挨重一下亮约 0.15 s。
## 盖掉旧层：船下的 WakeParticles（方点 / 软圆点尾迹；航迹白练已归 SeaAtmosphere 的 SeaWake）隐藏不删——节点照在，Ship / PirateShip 照写不报错。
class _Look extends Node2D:
	const SCAR_MAX := 6

	var ship: Node2D
	var sprite: Sprite2D
	var own := false
	var hit_uv := Vector2(0.5, 0.5)
	var hit_z := 0.0
	var hit_r := 16.0
	var scars := PackedVector4Array()
	var _scar_i := 0
	var _kick: ColorRect = null
	var _kick_amt := 0.0

	func setup(host: Node2D, spr: Sprite2D, is_own: bool) -> void:
		ship = host
		sprite = spr
		own = is_own

	func _ready() -> void:
		top_level = true
		global_transform = Transform2D.IDENTITY

	func _mat() -> ShaderMaterial:
		return sprite.material as ShaderMaterial if sprite != null and is_instance_valid(sprite) else null

	## 命中处一记炽橙（UV、半径按轻重），砲石 / 火器 / 重的记一处焦痕（满 SCAR_MAX 轮换最旧的）
	func impact(at: Vector2, sev: float, kind: String) -> void:
		if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
			return
		var uv := sprite.to_local(at) / sprite.texture.get_size() + Vector2(0.5, 0.5)
		hit_uv = uv.clamp(Vector2(0.02, 0.02), Vector2(0.98, 0.98))
		hit_z = clampf(0.55 + 0.45 * sev, 0.0, 1.0)
		hit_r = 8.0 + 12.0 * sev
		if kind in ["stone", "bomb", "fire"] or sev >= 0.6:
			var sc := Vector4(hit_uv.x, hit_uv.y, 8.0 + 13.0 * sev, clampf(0.5 + 0.45 * sev, 0.0, 1.0))
			if scars.size() < SCAR_MAX:
				scars.append(sc)
			else:
				scars[_scar_i] = sc
				_scar_i = (_scar_i + 1) % SCAR_MAX
			var m := _mat()
			if m != null:
				m.set_shader_parameter("scars", scars)
				m.set_shader_parameter("scar_n", scars.size())

	func kick(sev: float, push: Vector2) -> void:
		if not own:
			return
		if _kick == null:
			_kick = ColorRect.new()
			_kick.name = "ScreenKick"
			_kick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_kick.z_index = 90
			var sh := load("res://assets/shaders/screen_kick.gdshader") as Shader
			if sh != null:
				var m := ShaderMaterial.new()
				m.shader = sh
				_kick.material = m
			add_child(_kick)
		_kick_amt = maxf(_kick_amt, clampf(sev, 0.0, 1.2))
		var m2 := _kick.material as ShaderMaterial
		if m2 != null:
			m2.set_shader_parameter("dir", push.normalized() if push.length_squared() > 0.0001 else Vector2.RIGHT)

	func _process(delta: float) -> void:
		if ship == null or not is_instance_valid(ship) or sprite == null or not is_instance_valid(sprite):
			return
		global_transform = Transform2D.IDENTITY
		var wp := ship.get_node_or_null("WakeParticles") as CanvasItem
		if wp != null and wp.visible:
			wp.visible = false
		if hit_z > 0.001:
			hit_z *= exp(-delta * 20.0)
			var m := _mat()
			if m != null:
				m.set_shader_parameter("hit", Vector4(hit_uv.x, hit_uv.y, hit_z, hit_r))
		_step_kick(delta)

	func _step_kick(delta: float) -> void:
		if _kick == null:
			return
		_kick_amt *= exp(-delta * 15.0)
		_kick.visible = _kick_amt > 0.02
		if not _kick.visible:
			return
		var cam := ship.get("camera") as Camera2D
		if cam == null:
			_kick.visible = false
			return
		var view := get_viewport().get_visible_rect().size / cam.zoom
		_kick.position = cam.get_screen_center_position() - view * 0.5
		_kick.size = view
		var m := _kick.material as ShaderMaterial
		if m != null:
			m.set_shader_parameter("amount", clampf(_kick_amt, 0.0, 1.0))


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


## 旗舰沉没。prize = sea_prize_note 的夺船句（lane w19-g2），夹在「余船尚在。」与「船体受损」之间：交代在前、账目在后。
## 全队俱没（fleet_gone）时不写夺船句：夺来的船随后由 SeaChart._sink 一并清掉，写「已入船籍」反成虚账。
static func sea_sunk_note(cargo_str: String, damage: int, fleet_gone: bool, prize := "") -> String:
	var cargo := cargo_str.strip_edges()
	if fleet_gone:
		return "旗舰沉没，货舱随船。%s船体受损 %d。" % [cargo, maxi(0, damage)]
	return "旗舰沉没，该船货物随船。%s余船尚在。%s船体受损 %d。" % [cargo, prize.strip_edges(), maxi(0, damage)]


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


## 敌船遁走（出战「击退」）：没沉没降，只捞到些漂散的货，所以赏半。账目写法同 sea_win_note
static func sea_fled_note(spoil: int, damage: int, promo := "") -> String:
	var base := "敌船转篷遁走，只拾得些漂散的货。获财货 %d 钱。船体受损 %d。" % [maxi(0, spoil), maxi(0, damage)]
	var p := promo.strip_edges()
	return base if p == "" else base + p


## 夺船后弃战脱身 / 两散（lane fx3）：接在脱战句之后交代夺来的船与水粮，交代在前、账目在后，同战果注记三式。
## prizes = WorldMap 收战时仍在册的夺船 [{name, type}]（同名合计，按先夺先写）；water / food = 本场水粮实际增量
## （本地线夺船不转水粮，恒 0 → 写「未及搬过」）。不加「接舷既定。」前缀：弃战不是接舷定局。无夺船返回空串。
static func sea_prize_note(prizes: Array, water := 0, food := 0) -> String:
	var order: Array = []
	var count: Dictionary = {}
	for p in prizes:
		var n := str((p as Dictionary).get("name", "")).strip_edges() if p is Dictionary else str(p).strip_edges()
		if n == "":
			n = "敌船"
		if not count.has(n):
			order.append(n)
			count[n] = 0
		count[n] = int(count[n]) + 1
	if order.is_empty():
		return ""
	var parts: PackedStringArray = []
	for n in order:
		parts.append("「%s」%s艘" % [n, _cn_count(int(count[n]))])
	var stores := "船上水粮未及搬过。"
	if water > 0 or food > 0:
		stores = "搬过水 %d、粮 %d。" % [maxi(0, water), maxi(0, food)]
	return "所夺%s已入船籍，%s" % ["、".join(parts), stores]


## 艘数写汉字（本文件不引 autoload，不借 GameManager.cn_num）；十以上照写阿拉伯数字
static func _cn_count(n: int) -> String:
	var d := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	return d[n] if n >= 0 and n < 10 else str(n)


## 两散（letterbox parted / disengaged）：天色晚了，两边各自收帆
static func sea_parted_note() -> String:
	return "天色晚了，两边各自收帆。"


## 我方溃逃（出战「溃逃」）：弃货奔逃
static func sea_rout_note(cargo_str: String, crew_lost: int) -> String:
	return "水手溃散，弃货奔逃。%s水手减员 %d。" % [cargo_str.strip_edges(), maxi(0, crew_lost)]
