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

var fire_timer: float = 0.0

## P4-3 齐射弹数：海战由 _spawn_enemy 按 scale 写入，封顶 COMBAT_CANNON_CAP。
var cannon_count: int = 3

## P4-2 接舷：被玩家钩住后停止航行/开炮，进入白刃判定
var grappled: bool = false
## 敌船型号（_spawn_enemy 传入；白刃夺船时 Fleet.add_ship 用）。缺省是海寇快船
var ship_type: String = "pirate_boat"
## 海战精灵 id（_spawn_enemy 传 enemy.sprite；空则用 ship_type）→ assets/ship_<id>.png，缺图回落 ship_falcon.png
var sprite_id: String = ""
## 敌船名（夺船后并入舰队沿用；节点名保持 "PirateShip" 前缀供 WorldMap 计数）
var ship_name: String = ""
## 敌船水手数（_spawn_enemy 按船型初始化）；白刃判定输入
var crew: int = 20
## 敌船士气 0-100；白刃判定输入
var enemy_morale: int = 60
## 敌将武力系数；白刃判定输入
var captain_force: float = 1.0
## 兜圈半径（WorldMap._spawn_enemy 按刷船距离写入）：600 内绕本船兜圈时把半径稳在这里；0 = 旧法（转到较近的一侧舷）
var orbit_radius: float = 0.0
## 兜圈方向（+1 / −1）：同一战各船同向，按刷船角度隔开就彼此追不上
var orbit_sense: float = 1.0
## 半径偏差折成向心 / 离心修正的增益：偏出半径的两成即转 24° 左右往回收
const ORBIT_GAIN := 2.0

func _ready() -> void:
	sprite.modulate = Color.WHITE
	apply_sprite()


## 船图契约：敌船精灵取 assets/ship_<sprite_id 或 ship_type>.png，缺图留 PirateShip.tscn 里的 ship_falcon.png。
## 不依赖 @onready（没进树也能调），探针直接拿 PirateShip.tscn 实例验回落。
func sprite_key() -> String:
	return sprite_id if sprite_id.strip_edges() != "" else ship_type


func apply_sprite() -> void:
	_CombatFx.apply_ship_sprite(get_node_or_null("Sprite2D") as Sprite2D,
		_CombatFx.ship_sprite_path(sprite_key(), _CombatFx.SHIP_SPRITE_ENEMY))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target): return
	if hull_hp <= 0: return
	if grappled:
		velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta) # P4-2 接舷：被钩住后减速停住
		return
	
	var dist = position.distance_to(target.position)
	if dist > 2500.0: return # Too far, sleep
	
	var dir_to_target = (target.position - position).normalized()
	var ship_dir = Vector2.UP.rotated(rotation)
	
	var angle_diff = ship_dir.angle_to(dir_to_target)
	
	# AI Logic: 
	# If far, steer towards player
	# If close, steer to broadside (90 degrees off) to shoot
	var target_angle_diff = angle_diff
	if dist < 600.0:
		if orbit_radius > 0.0:
			# 各守一个侧舷位：同向兜圈，半径稳在开战刷船距离（镜头里），几艘按刷船角度隔开、彼此追不上。
			# 旧法「转到较近的那一侧舷」：左右两艘都朝船头兜，汇成一团；兜着兜着半径漂到约 600，出了画（crew 线 09-28 实测）
			var tangent: Vector2 = dir_to_target.rotated(-orbit_sense * PI / 2.0)
			var pull := clampf((dist - orbit_radius) / orbit_radius * ORBIT_GAIN, -1.0, 1.0)
			target_angle_diff = ship_dir.angle_to((tangent + dir_to_target * pull).normalized())
		else:
			if angle_diff > 0: target_angle_diff -= PI/2.0
			else: target_angle_diff += PI/2.0
	# 敌船之间分离：兜圈时被本船甩乱了阵脚（本船开船、掉头）也不压成一艘。
	# 只偏航向，不改航速、转向上限与开炮判定（开炮仍按对本船的 angle_diff）。
	var push := _separation_push()
	if push != Vector2.ZERO:
		var want: Vector2 = (ship_dir.rotated(target_angle_diff) + push * SEPARATION_WEIGHT).normalized()
		target_angle_diff = ship_dir.angle_to(want)

	rotation += clamp(target_angle_diff, -base_turn_speed*delta, base_turn_speed*delta)
	
	velocity = ship_dir * max_speed
	move_and_slide()
	
	var speed_ratio = velocity.length() / max_speed
	wake_particles.emitting = true
	# 尾迹挂 soft_dot（64 px 柔点）：原先无贴图时 scale 即边长像素（2—6），换贴图按半透明芯径约 28 px 折算
	wake_particles.scale_amount_max = (2.0 + speed_ratio * 4.0) * DOT_PX_SCALE
	
	_process_firing(delta, angle_diff, dist)

func _process_firing(delta: float, angle_diff: float, dist: float) -> void:
	fire_timer -= delta
	if fire_timer > 0: return
	if grappled: return # P4-2 接舷：被钩住后不开炮
	if dist > 800.0: return
	
	# Check if player is on broadside (approx 90 degrees left or right)
	var is_broadside = abs(abs(angle_diff) - PI/2.0) < 0.3
	if is_broadside:
		fire_timer = 3.0
		# Fire broadside
		var ship_dir = Vector2.UP.rotated(rotation)
		var side_dir = Vector2.RIGHT.rotated(rotation)
		if angle_diff < 0: side_dir = Vector2.LEFT.rotated(rotation)
		
		_AUDIO.combat_fire(get_parent())
		if cannonball_scene == null:
			cannonball_scene = load("res://scenes/Cannonball.tscn") as PackedScene
		for i in range(cannon_count):
			var cb = cannonball_scene.instantiate()
			cb.position = position + ship_dir * (i - (cannon_count - 1) * 0.5) * 20 + side_dir * 30
			var spread = randf_range(-0.1, 0.1)
			cb.direction = side_dir.rotated(spread)
			cb.shooter = self
			get_parent().add_child(cb)

func take_damage(amount: float) -> void:
	hull_hp -= amount
	sprite.modulate = Color(1.2, 0.5, 0.45)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	
	if hull_hp <= 0:
		_explode()

func _explode() -> void:
	# 赏金走 SeaChart 结算，击沉不再掉拾取箱
	queue_free()


## P4-2 白刃：敌侧战力 = 水手 × 士气系数 × 敌将系数（对齐设计文档公式）
func combat_strength() -> float:
	var morale_factor := 0.6 + 0.4 * (float(enemy_morale) / 100.0)
	return float(crew) * morale_factor * captain_force


## 分离：船图约 317 px 长（512 × 0.62），碰撞圆只有 24，物理上不相撞、画面上却能整条压住。
## 与别的活敌船相距不足 SEPARATION_DIST 就往外推，越近推得越狠；返回各邻船推力之和（无邻船为零向量）。
const SEPARATION_DIST := 300.0
## 推力并进航向时的权重：贴身（推力≈1）时压过绕舷侧的本意，相距一半以上时只偏一点
const SEPARATION_WEIGHT := 2.0
## 无贴图粒子的 scale 是方块边长（像素）；挂 assets/fx/soft_dot.png（64 px，半透明芯径约 28 px）后按 1/28 折成同样大小的柔点
const DOT_PX_SCALE := 1.0 / 28.0


func _separation_push() -> Vector2:
	var push := Vector2.ZERO
	var host := get_parent()
	if host == null:
		return push
	for n in host.get_children():
		if n == self or not (n is PirateShip) or n.is_queued_for_deletion():
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
