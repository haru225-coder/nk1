extends Area2D

@export var speed: float = 800.0
@export var damage: float = 25.0
@export var lifetime: float = 2.0
var direction: Vector2 = Vector2.ZERO
var shooter: Node2D = null

var water_splash = preload("res://scenes/WaterSplash.tscn")
var impact_explosion = preload("res://scenes/ImpactExplosion.tscn")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
var floating_text = preload("res://scenes/FloatingText.tscn")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var tween = create_tween()
	tween.tween_callback(func(): _splash_and_die()).set_delay(lifetime)

func _process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	# 发炮的船可能已被打沉 / 夺下释放（炮弹还在飞）：已释放的实例不能再拿来比较或传进带类型的形参
	var live_shooter: Node2D = shooter if is_instance_valid(shooter) else null
	if live_shooter != null and body == live_shooter: return

	if body.has_method("take_damage"):
		# P4-3：玩家船（Ship）受击乘甲减伤；敌船（PirateShip）保持原伤害
		var dmg := damage
		if body is Ship:
			dmg = damage * Fleet.armor_damage_reduction()
		body.take_damage(dmg)
		_AUDIO.combat_hit(get_parent())
		_CombatFx.on_cannon_hit(get_parent(), position, live_shooter)
		_explode_and_die()
		_spawn_floating_text("-" + str(int(dmg)), Color.RED)
	else:
		_splash_and_die()

func _splash_and_die() -> void:
	var splash = water_splash.instantiate()
	splash.position = position
	get_parent().call_deferred("add_child", splash)
	splash.emitting = true
	queue_free()

func _explode_and_die() -> void:
	var expl = impact_explosion.instantiate()
	expl.position = position
	get_parent().call_deferred("add_child", expl)
	expl.emitting = true
	queue_free()

func _spawn_floating_text(text: String, color: Color) -> void:
	var ft = floating_text.instantiate()
	ft.position = position
	ft.text = text
	ft.add_theme_color_override("font_color", color)
	get_parent().call_deferred("add_child", ft)
