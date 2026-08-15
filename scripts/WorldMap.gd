extends Node2D

## 战斗结束信号：outcome 为 "win"/"lose"/"flee"，data 携带战损等结算信息
signal battle_finished(outcome: String, data: Dictionary)

@onready var ship: CharacterBody2D = $Ship
@onready var label: RichTextLabel = $CanvasLayer/HUD/LeftPanel/Margin/Label
@onready var fleet_status: Label = $CanvasLayer/HUD/RightPanel/Margin/FleetStatus
@onready var weather_status: Label = $CanvasLayer/HUD/RightPanel/Margin/WeatherStatus
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $CanvasLayer/LightningFlash

var crate_scene = preload("res://scenes/Crate.tscn")
var pirate_scene = preload("res://scenes/PirateShip.tscn")
var seagull_tex = preload("res://assets/seagull.png")
var whale_tex = preload("res://assets/whale_shadow.png")

var time_of_day: float = 12.0
var is_storm: bool = false
var storm_timer: float = 0.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 80.0

var crate_spawn_timer: float = 5.0
var animal_spawn_timer: float = 10.0
var pirate_spawn_timer: float = 20.0

# ── 战斗模式（P4-1 接入）──
## 由 SeaChart._on_fight_pirates 开启：遭遇海盗进入本场景即战斗专用
var combat_mode: bool = false
var combat_start_durability: float = 0.0
var player_damage: float = 0.0
## 防 _battle_exit 重入（信号同步触发期间 WorldMap 仍存活一帧）
var resolved: bool = false
## 本次战斗敌船总数（HUD 显示）
var total_enemies: int = 0
## 敌单船战斗血量基数（PirateShip.hull_hp），按战力比缩放
const ENEMY_HULL_BASE := 100.0
## 敌船血量缩放 clamp 下限/上限
const ENEMY_SCALE_MIN := 0.8
const ENEMY_SCALE_MAX := 3.0

func _ready() -> void:
	randomize()
	var pb: Dictionary = GameManager.pending_battle
	if pb.get("battle", false):
		_setup_combat(pb)
	else:
		# 防御：孤儿场景被直接打开时立即退出，不残留
		_battle_exit("flee", {})

func _process(delta: float) -> void:
	if not ship: return

	_process_weather_and_time(delta)
	if not combat_mode:
		_process_spawns(delta)
		rain_particles.global_position = ship.global_position

	# 战损统计：以进入战斗时的舰队总耐久为基准（仅战斗期有意义）
	if combat_mode:
		player_damage = combat_start_durability - Fleet.total_durability()

	# 敌全灭 → 获胜
	if combat_mode and not resolved:
		if _enemies_alive() == 0:
			_battle_exit("win", {})

	_update_hud()


## 战斗模式下存活敌船数（PirateShip 爆炸后 hull_hp 归零仍存活一帧，按血量判定）
func _enemies_alive() -> int:
	var n := 0
	for child in get_children():
		if child.name.begins_with("PirateShip") and float(child.get("hull_hp", 0.0)) > 0.0:
			n += 1
	return n


func _update_hud() -> void:
	var wind_desc = "无风"
	if ship.wind_vector.y > 0: wind_desc = "北风 (自北向南吹)"
	elif ship.wind_vector.y < 0: wind_desc = "南风 (自南向北吹)"
	elif ship.wind_vector.x > 0: wind_desc = "西风 (自西向东吹)"
	elif ship.wind_vector.x < 0: wind_desc = "东风 (自东向西吹)"

	var hp_color = "green"
	if ship.hull_hp < 50: hp_color = "red"

	var tail := "B/Esc: 弃战逃走"
	var mission := "敌船 %d 艘　存活 %d\n" % [total_enemies, _enemies_alive()] if combat_mode else ""
	var text = "%s当前季风: %s\n风力强度: %d\nW/S: 升降帆 (当前档位: %d)\nA/D: 操舵\nJ/K: 左/右舷齐射开炮\n船体耐久: [color=%s]%d/%d[/color]\n%s" % [
		mission, wind_desc, int(ship.wind_strength), ship.sail_gear, hp_color, int(ship.hull_hp), int(ship.max_hp), tail,
	]
	label.text = text

	var cargo_str = ""
	if Fleet.cargo.is_empty():
		cargo_str = "空"
	else:
		for k in Fleet.cargo.keys():
			cargo_str += GameManager.get_good_name(k) + " x" + str(Fleet.cargo[k].get("qty", 0)) + " "

	fleet_status.text = "【舰队资产】\n金钱: %d\n货舱: %s" % [GameState.money, cargo_str]

func _process_weather_and_time(delta: float) -> void:
	# 战斗模式固定晴朗：风暴伤会污染 player_damage 统计并破坏公平性
	if combat_mode:
		is_storm = false
		rain_particles.emitting = false
		# 战斗目标提示由 _setup_combat 设置，这里不覆盖
		ship.wind_strength = base_wind_strength
		ship.wind_vector = Vector2(0, 1)
		canvas_modulate.color = canvas_modulate.color.lerp(Color(1, 1, 1, 1), 2.0 * delta)
		return

	time_of_day += delta * 0.2
	if time_of_day >= 24.0: time_of_day -= 24.0
	
	var light_color = Color(1, 1, 1, 1)
	if time_of_day < 5.0 or time_of_day > 19.0:
		light_color = Color(0.2, 0.2, 0.4, 1.0)
	elif time_of_day >= 5.0 and time_of_day < 7.0:
		light_color = Color(0.8, 0.5, 0.4, 1.0)
	elif time_of_day > 17.0 and time_of_day <= 19.0:
		light_color = Color(0.8, 0.4, 0.2, 1.0)
		
	storm_timer -= delta
	if storm_timer <= 0:
		is_storm = not is_storm
		if is_storm:
			storm_timer = randf_range(20.0, 40.0)
			weather_status.text = "当前天气: 狂风骤雨 (极其危险!)"
			weather_status.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "当前天气: 晴朗"
			weather_status.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
			rain_particles.emitting = false
			ship.wind_strength = base_wind_strength
			ship.wind_vector = Vector2(0, 1)

	if is_storm:
		light_color = light_color.lerp(Color(0.3, 0.3, 0.4, 1.0), 0.8)
		lightning_timer -= delta
		if lightning_timer <= 0:
			_strike_lightning()
			lightning_timer = randf_range(2.0, 8.0)
			
	canvas_modulate.color = canvas_modulate.color.lerp(light_color, 2.0 * delta)

func _strike_lightning() -> void:
	lightning_flash.visible = true
	lightning_flash.color.a = 0.8
	var tween = create_tween()
	tween.tween_property(lightning_flash, "color:a", 0.0, 0.3)
	tween.tween_callback(func(): lightning_flash.visible = false)

func _process_spawns(delta: float) -> void:
	crate_spawn_timer -= delta
	if crate_spawn_timer <= 0:
		crate_spawn_timer = randf_range(10.0, 20.0)
		var crate = crate_scene.instantiate()
		var offset = Vector2(randf_range(-1500, 1500), randf_range(-1500, 1500))
		crate.position = ship.position + ship.velocity.normalized() * 500.0 + offset
		add_child(crate)
		
	animal_spawn_timer -= delta
	if animal_spawn_timer <= 0:
		animal_spawn_timer = randf_range(15.0, 30.0)
		_spawn_animal()
		
	pirate_spawn_timer -= delta
	if pirate_spawn_timer <= 0:
		pirate_spawn_timer = randf_range(30.0, 60.0)
		var pirate = pirate_scene.instantiate()
		var angle = randf() * TAU
		var dist = randf_range(1500, 2500)
		pirate.position = ship.position + Vector2(cos(angle), sin(angle)) * dist
		pirate.target = ship
		add_child(pirate)

func _spawn_animal() -> void:
	var sprite = Sprite2D.new()
	var is_whale = randf() > 0.5
	if is_whale:
		sprite.texture = whale_tex
		sprite.scale = Vector2(0.5, 0.5)
		sprite.modulate.a = 0.5
		sprite.z_index = -1
	else:
		sprite.texture = seagull_tex
		sprite.scale = Vector2(0.2, 0.2)
		sprite.z_index = 10
		
	var offset = Vector2(randf_range(-1000, 1000), randf_range(-1000, 1000))
	sprite.position = ship.position + offset
	
	var move_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	sprite.rotation = move_dir.angle() + PI/2.0
	
	add_child(sprite)
	
	var tween = create_tween()
	var target_pos = sprite.position + move_dir * 3000.0
	tween.tween_property(sprite, "position", target_pos, 20.0)
	tween.tween_callback(func(): sprite.queue_free())


# ── 战斗模式（P4-1 接入）─────────────────────────────

## 由 _ready 在 pending_battle.battle 时调用：禁用停靠、禁自动刷怪、生成敌舰队
func _setup_combat(pb: Dictionary) -> void:
	combat_mode = true
	# 战斗专用：禁掉 PortZone 停靠出口（否则 Enter 会切回 Main 丢战斗）
	$Ports.process_mode = Node.PROCESS_MODE_DISABLED
	$Ports.visible = false
	combat_start_durability = Fleet.total_durability()
	total_enemies = 0
	var enemy_list: Array = pb.get("enemy", [])
	for entry in enemy_list:
		var type_id: String = entry.get("type", "sea_falcon")
		var count: int = entry.get("count", 1)
		_spawn_enemy(type_id, count, pb)
	weather_status.text = "海战！ 击沉敌船"
	weather_status.add_theme_color_override("font_color", Color(1, 0.6, 0.2))


## 生成一支敌舰队，绕玩家船散布；hull_hp 按战力比缩放
func _spawn_enemy(type_id: String, count: int, pb: Dictionary) -> void:
	var enemy_power: float = float(pb.get("power", 300.0))
	var player_power: float = float(pb.get("player_power", 1.0))
	if player_power <= 0.0:
		player_power = 1.0
	var scale := clampf(enemy_power / player_power, ENEMY_SCALE_MIN, ENEMY_SCALE_MAX)
	var hull: float = ENEMY_HULL_BASE * scale
	for i in range(count):
		var p := pirate_scene.instantiate()
		var angle := randf() * TAU
		var dist := randf_range(1200.0, 2000.0)
		p.position = ship.position + Vector2(cos(angle), sin(angle)) * dist
		p.target = ship
		p.hull_hp = hull
		p.drops_loot = false  # 战斗中不掉宝箱，赏金走 SeaChart 结算
		add_child(p)
		total_enemies += 1


## B/Esc：弃战逃走。成败都退出战斗，写回由 SeaChart 结算
func _unhandled_input(event: InputEvent) -> void:
	if not combat_mode or resolved:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			var chance := clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)
			var ok := randf() < chance
			_battle_exit("flee", {"flee_ok": ok, "player_damage": player_damage})


## 玩家旗舰在战斗中沉没时由 Ship._sink_ship 调用（战斗期不切场景）
func _battle_player_sunk() -> void:
	_battle_exit("lose", {"sunk": true, "player_damage": player_damage})


## 战斗终结：发信号给 SeaChart 结算，随后释放本场景
func _battle_exit(outcome: String, data: Dictionary) -> void:
	if resolved:
		return
	resolved = true
	data["player_damage"] = player_damage
	battle_finished.emit(outcome, data)
	queue_free()
