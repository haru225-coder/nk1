extends CharacterBody2D

@export var max_speed: float = 250.0
@export var base_turn_speed: float = 1.5
@export var hull_hp: float = 80.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var wake_particles: CPUParticles2D = $WakeParticles

var target: Node2D = null
var cannonball_scene = preload("res://scenes/Cannonball.tscn")
var crate_scene = preload("res://scenes/Crate.tscn")

## 击沉后是否掉宝箱（战斗模式下由 WorldMap 置 false，赏金走 SeaChart 结算）
@export var drops_loot: bool = true

var fire_timer: float = 0.0

## P4-3 齐射弹数：默认 3 覆盖自由航行刷出的海盗（_process_spawns 不设此字段）；
## 海战由 _spawn_enemy 按 scale 写入 2~9。
var cannon_count: int = 3

## P4-2 接舷：被玩家钩住后停止航行/开炮，进入白刃判定
var grappled: bool = false
## 敌船型号（_spawn_enemy 传入；白刃夺船时 Fleet.add_ship 用）
var ship_type: String = "sea_falcon"
## 敌船名（夺船后并入舰队沿用；节点名保持 "PirateShip" 前缀供 WorldMap 计数）
var ship_name: String = ""
## 敌船水手数（_spawn_enemy 按船型初始化）；白刃判定输入
var crew: int = 20
## 敌船士气 0-100；白刃判定输入
var enemy_morale: int = 60
## 敌将武力系数；白刃判定输入
var captain_force: float = 1.0

func _ready() -> void:
	sprite.modulate = Color(1, 0.5, 0.5) # Make it look reddish/evil

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
		if angle_diff > 0: target_angle_diff -= PI/2.0
		else: target_angle_diff += PI/2.0
		
	rotation += clamp(target_angle_diff, -base_turn_speed*delta, base_turn_speed*delta)
	
	velocity = ship_dir * max_speed
	move_and_slide()
	
	var speed_ratio = velocity.length() / max_speed
	wake_particles.emitting = true
	wake_particles.scale_amount_max = 2.0 + speed_ratio * 4.0
	
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
		
		for i in range(cannon_count):
			var cb = cannonball_scene.instantiate()
			cb.position = position + ship_dir * (i - (cannon_count - 1) * 0.5) * 20 + side_dir * 30
			var spread = randf_range(-0.1, 0.1)
			cb.direction = side_dir.rotated(spread)
			cb.shooter = self
			get_parent().add_child(cb)

func take_damage(amount: float) -> void:
	hull_hp -= amount
	sprite.modulate = Color(1, 0.2, 0.2)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1, 0.5, 0.5), 0.2)
	
	if hull_hp <= 0:
		_explode()

func _explode() -> void:
	# Loot pinata（战斗模式下关闭：赏金由 SeaChart 结算）
	if drops_loot:
		for i in range(5):
			var crate = crate_scene.instantiate()
			crate.position = position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
			get_parent().call_deferred("add_child", crate)

	# Could add explosion particles here
	queue_free()


## P4-2 白刃：敌侧战力 = 水手 × 士气系数 × 敌将系数（对齐设计文档公式）
func combat_strength() -> float:
	var morale_factor := 0.6 + 0.4 * (float(enemy_morale) / 100.0)
	return float(crew) * morale_factor * captain_force
