## 海战观感薄层：命中顿帧、镜头轻震、炮弹命中加一缕焦烟。不改伤害/齐射/刷船数值。
## 调用方：WorldMap（开战/接舷/结算）、Cannonball（命中）、BoardingStage、SeaChart（战果飘字）。
## headless / -s 工具脚本下顿帧与震屏跳过（Engine.time_scale 仍复位），粒子照常可实例化。
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


## 炮弹命中：既有爆炸之上再加一缕慢烟，并顿帧 + 轻震。
static func on_cannon_hit(world: Node, at: Vector2, ship: Node = null) -> void:
	if world == null or not is_instance_valid(world):
		return
	hitstop(world, 0.055, 0.22)
	if ship != null:
		punch_camera(ship, 4.5)
	_spawn_ember_smoke(world, at)


static func _spawn_ember_smoke(world: Node, at: Vector2) -> void:
	var smoke := CPUParticles2D.new()
	smoke.z_index = 18
	smoke.position = at
	smoke.emitting = false
	smoke.amount = 10
	smoke.lifetime = 1.1
	smoke.one_shot = true
	smoke.explosiveness = 0.75
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 6.0
	smoke.spread = 180.0
	smoke.gravity = Vector2(0, -12)
	smoke.initial_velocity_min = 18.0
	smoke.initial_velocity_max = 42.0
	smoke.scale_amount_min = 5.0
	smoke.scale_amount_max = 11.0
	smoke.color = Color(0.22, 0.18, 0.14, 0.55)
	world.call_deferred("add_child", smoke)
	# 延迟一帧再喷，避免未入树
	smoke.ready.connect(func() -> void:
		smoke.emitting = true
		var t := smoke.get_tree().create_timer(1.4)
		t.timeout.connect(smoke.queue_free)
	)


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
