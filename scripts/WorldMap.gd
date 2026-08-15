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

## P4-2 接舷距离：低于此距离可按 G 钩住敌船进入白刃
const BOARD_DISTANCE := 140.0
## 白刃阶段（接舷中）：玩家已钩住某船，停炮击、禁逃离，只等白刃判定
var boarding: bool = false
## 接舷白刃的目标敌船（P4-2）
var boarding_target: Node2D = null

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

	# P4-2 接舷：boarding 阶段检测白刃目标是否存活（敌被打沉/脱钩则退出）
	if combat_mode and not resolved:
		if boarding:
			if not _boarding_target_valid():
				boarding = false
				boarding_target = null

	# 敌全灭 → 获胜（接舷中不判定：白刃还没分出胜负）
	if combat_mode and not resolved:
		if not boarding and _enemies_alive() == 0:
			_battle_exit("win", {})

	_update_hud()


## 战斗模式下存活敌船数（PirateShip 爆炸后 hull_hp 归零仍存活一帧，按血量判定）
func _enemies_alive() -> int:
	var n := 0
	for child in get_children():
		if child.name.begins_with("PirateShip") and float(child.get("hull_hp", 0.0)) > 0.0:
			n += 1
	return n


## P4-2 接舷：返回最近存活敌船 [Node, 距离]；无存活敌船返回 []
func _nearest_enemy() -> Array:
	var best: Node2D = null
	var best_d := 1e9
	for child in get_children():
		if child.name.begins_with("PirateShip") and float(child.get("hull_hp", 0.0)) > 0.0:
			var d := child.position.distance_to(ship.position)
			if d < best_d:
				best_d = d
				best = child
	if best == null:
		return []
	return [best, best_d]


## P4-2 接舷：白刃目标是否仍存活（board_target 未被打沉）
func _boarding_target_valid() -> bool:
	if boarding_target == null:
		return false
	if not is_instance_valid(boarding_target):
		boarding_target = null
		return false
	return float(boarding_target.get("hull_hp", 0.0)) > 0.0


## P4-2 白刃判定：按 水手数 × 士气 × 将领武力 对比双方，胜则夺船并入舰队。
## 玩家战力 = Fleet.total_crew × morale_factor × captain_power
## 敌战力 = 敌船.combat_strength（水手 × 士气 × 敌将）
## 胜率 = 玩家战力 / (玩家 + 敌)；均势 50%，一方压倒则趋近 1。
func _board_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	boarding = true
	boarding_target = enemy
	enemy.set("grappled", true)  # 敌船停航停炮

	var player_board := Fleet.total_crew() * Fleet.morale_factor() * Fleet.captain_power()
	var enemy_board: float = enemy.combat_strength()
	if player_board + enemy_board <= 0.0:
		player_board = 1.0
		enemy_board = 1.0

	var p_win := player_board / (player_board + enemy_board)
	var win := randf() < p_win

	# 白刃必死人：胜方损失 8%-15%，负方损失 20%-30%（下限 1，保火种）
	var lose_n := maxi(1, int(Fleet.total_crew() * (0.08 + randf() * 0.07)))
	if win:
		var type_id: String = enemy.get("ship_type", "sea_falcon")
		var ship_name: String = enemy.get("ship_name", "")
		Fleet.lose_crew_random(lose_n)
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 4)
		# 主角武力成长：白刃夺船历练（上限 100）
		GameState.martial = mini(100, GameState.martial + 1)
		# 夺船并入舰队：add_ship 自动初始化 sail_level/armor_level/cargo
		var ok := Fleet.add_ship(type_id, ship_name)
		var msg := "接舷白刃，夺下敌船「%s」！" % (Fleet.ships[Fleet.ships.size() - 1].get("name", "敌船") if ok else "敌船")
		_show_combat_notice(msg)
		enemy.queue_free()
		boarding = false
		boarding_target = null
		if _enemies_alive() == 0:
			_battle_exit("win", {})
	else:
		var lose_n2 := maxi(1, int(Fleet.total_crew() * (0.20 + randf() * 0.10)))
		Fleet.lose_crew_random(lose_n2)
		Fleet.morale = maxi(0, Fleet.morale - 10)
		enemy.set("grappled", false)  # 敌船脱钩，继续炮击/逃逸
		boarding = false
		boarding_target = null
		_show_combat_notice("白刃失利，死了 %d 名水手，敌船脱钩。" % lose_n2)


## 战斗通知浮字：在屏幕中央短暂显示（复用 FloatingText 场景），3 秒后淡出
var _notice: Label = null
func _show_combat_notice(text: String) -> void:
	if not is_instance_valid(_notice):
		_notice = Label.new()
		_notice.set_anchors_preset(Control.PRESET_CENTER)
		_notice.add_theme_font_size_override("font_size", 28)
		_notice.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
		_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_notice.add_theme_constant_override("outline_size", 4)
		$CanvasLayer.add_child(_notice)
	_notice.text = text
	_notice.visible = true
	_notice.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_notice, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func(): _notice.visible = false)


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
	var boarding_hint := ""
	if combat_mode and not resolved:
		if boarding:
			tail = "白刃判定中…"
			boarding_hint = "[color=yellow]已钩住敌船，白刃战定生死！[/color]\n"
		else:
			var ne := _nearest_enemy()
			if ne.size() == 2 and ne[1] < BOARD_DISTANCE:
				tail = "G: 接舷　B/Esc: 逃走"
				boarding_hint = "[color=yellow]敌船就在舷边，按 G 钩住白刃！[/color]\n"
	var text = "%s%s当前季风: %s\n风力强度: %d\nW/S: 升降帆 (当前档位: %d)\nA/D: 操舵\nJ/K: 左/右舷齐射开炮\n船体耐久: [color=%s]%d/%d[/color]\n%s%s" % [
		mission, boarding_hint, wind_desc, int(ship.wind_strength), ship.sail_gear, hp_color, int(ship.hull_hp), int(ship.max_hp), tail,
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
	var d := Fleet.ship_def(type_id)
	# 敌船水手数：按船型满编区间随机取（白刃判定输入，夺船后并入舰队）
	var crew_low: int = int(d.get("crew_min", 20))
	var crew_high: int = int(d.get("crew_max", crew_low + 10))
	var type_name: String = d.get("name", "敌船")
	for i in range(count):
		var p := pirate_scene.instantiate()
		var angle := randf() * TAU
		var dist := randf_range(1200.0, 2000.0)
		p.position = ship.position + Vector2(cos(angle), sin(angle)) * dist
		p.target = ship
		p.hull_hp = hull
		p.drops_loot = false  # 战斗中不掉宝箱，赏金走 SeaChart 结算
		# P4-2：白刃/夺船输入。节点名保持 "PirateShip" 前缀（_enemies_alive 依赖），
		# 夺船后的船名另存 ship_name（沿用敌船名，如「海鹘」）。
		p.ship_name = "%s" % type_name
		p.ship_type = type_id
		p.crew = randi_range(crew_low, crew_high)
		p.enemy_morale = randi_range(50, 75)
		p.captain_force = 1.0 + 0.3 * float(scale - 1.0)  # 强敌水手多，头目更悍
		p.cannon_count = maxi(1, int(round(3.0 * scale)))  # P4-3：敌船弹数随战力比温和缩放（0.8~3.0 → 2~9 发）
		add_child(p)
		total_enemies += 1


## B/Esc：弃战逃走。成败都退出战斗，写回由 SeaChart 结算
## G：接舷白刃（P4-2）。贴近敌船时按 G 钩住进入白刃判定
func _unhandled_input(event: InputEvent) -> void:
	if not combat_mode or resolved:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			if boarding or _nearest_enemy().size() != 2:
				return
			var ne := _nearest_enemy()
			if ne[1] < BOARD_DISTANCE:
				get_viewport().set_input_as_handled()
				_board_enemy(ne[0])
		elif event.keycode == KEY_B or event.keycode == KEY_ESCAPE:
			if boarding:
				return # 白刃已钩住，不能逃
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
