extends Node2D

const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
const _BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const _LETTERBOX_PATH := "res://scripts/ui/CombatLetterbox.gd"
const _Kit := preload("res://scripts/cutscene/cs_kit.gd")

## 战斗结束信号：outcome 为 "win"/"lose"/"flee"，data 携带战损等结算信息
signal battle_finished(outcome: String, data: Dictionary)

@onready var ship: CharacterBody2D = $Ship
@onready var label: RichTextLabel = $CanvasLayer/HUD/TideBar/Margin/Row/Label
@onready var fleet_status: Label = $CanvasLayer/HUD/TideBar/Margin/Row/VBox/FleetStatus
@onready var weather_status: Label = $CanvasLayer/HUD/TideBar/Margin/Row/VBox/WeatherStatus
@onready var canvas_modulate: CanvasModulate = $CanvasModulate
@onready var rain_particles: CPUParticles2D = $RainParticles
@onready var lightning_flash: ColorRect = $CanvasLayer/LightningFlash

var pirate_scene = preload("res://scenes/PirateShip.tscn")

var time_of_day: float = 12.0
var is_storm: bool = false
var storm_timer: float = 0.0
var lightning_timer: float = 0.0
var base_wind_strength: float = 80.0

# ── 战斗模式（P4-1 接入）──
## 由 SeaChart._on_fight_pirates 开启：遭遇海盗进入本场景即战斗专用
var combat_mode: bool = false
var combat_start_durability: float = 0.0
var player_damage: float = 0.0
## 防 _battle_exit 重入（信号同步触发期间 WorldMap 仍存活一帧）
var resolved: bool = false
## 最近一次终结是否经接舷夺船（出战题签用「夺船」）
var _last_boarded: bool = false
## 本次战斗敌船总数（HUD 显示）
var total_enemies: int = 0
## 敌单船战斗血量基数（PirateShip.hull_hp），按战力比缩放
const ENEMY_HULL_BASE := 100.0
## 敌船血量缩放 clamp 下限/上限
const ENEMY_SCALE_MIN := 0.8
const ENEMY_SCALE_MAX := 3.0
## 开战刷船距离：镜头 zoom 1.5 时可见约 850×480，1200 外等于空镜
const COMBAT_SPAWN_DIST_MIN := 300.0
const COMBAT_SPAWN_DIST_MAX := 420.0
## 镜头内等于已进 800 射程；不延迟会被 9 门齐射秒掉开局小艍
const COMBAT_FIRE_DELAY := 3.5
## 两艘满编 9 门 × 25 伤 = 450，开局 120 耐久一波沉。封顶 2 门：
## 第一轮约 100，停着打第二轮才沉，B 来得及按。
const COMBAT_CANNON_CAP := 2

## P4-2 接舷距离：低于此距离可按 G 钩住敌船进入白刃
const BOARD_DISTANCE := 140.0
## 白刃阶段（接舷中）：玩家已钩住某船，停炮击、禁逃离，只等白刃判定
var boarding: bool = false
## 接舷白刃的目标敌船（P4-2）
var boarding_target: Node2D = null

func _ready() -> void:
	var hud := $CanvasLayer/HUD
	UiTheme.apply(hud)
	UiTheme.style_body(label)
	fleet_status.add_theme_font_override("font", UiTheme.font())
	fleet_status.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	fleet_status.add_theme_color_override("font_color", UiTheme.GOLD)
	weather_status.add_theme_font_override("font", UiTheme.font())
	weather_status.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	weather_status.add_theme_color_override("font_color", UiTheme.TEXT)
	var tide := hud.get_node_or_null("TideBar")
	if tide is PanelContainer:
		tide.add_theme_stylebox_override("panel", UiTheme.plaque())
	var mini := hud.get_node_or_null("MinimapPanel")
	if mini is PanelContainer:
		mini.add_theme_stylebox_override("panel", UiTheme.panel())
	for port in $Ports.get_children():
		for child in port.get_children():
			if child is Label:
				child.add_theme_font_override("font", UiTheme.font())
				child.add_theme_color_override("font_color", UiTheme.GOLD)
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
	if combat_mode:
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
## Godot 4.6 的 Object.get 只收属性名。Node 上写 get(k, default) 会直接编不过。
func _node_float(n: Object, prop: String, fallback: float = 0.0) -> float:
	if n == null:
		return fallback
	var v = n.get(prop)
	return fallback if v == null else float(v)


func _node_str(n: Object, prop: String, fallback: String = "") -> String:
	if n == null:
		return fallback
	var v = n.get(prop)
	return fallback if v == null else str(v)


func _is_live_pirate(n: Node) -> bool:
	return n != null and n.name.begins_with("PirateShip") and _node_float(n, "hull_hp") > 0.0


func _enemies_alive() -> int:
	var n := 0
	for child in get_children():
		if _is_live_pirate(child):
			n += 1
	return n


## P4-2 接舷：返回最近存活敌船 [Node, 距离]；无存活敌船返回 []
func _nearest_enemy() -> Array:
	var best: Node2D = null
	var best_d := 1e9
	for child in get_children():
		var n2 := child as Node2D
		if n2 == null or not _is_live_pirate(n2):
			continue
		var d: float = n2.position.distance_to(ship.position)
		if d < best_d:
			best_d = d
			best = n2
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
	return _is_live_pirate(boarding_target)


## P4-2 白刃判定：按 水手数 × 士气 × 将领武力 对比双方，胜则夺船并入舰队。
## 玩家战力 = Fleet.total_crew × morale_factor × captain_power
## 敌战力 = 敌船.combat_strength（水手 × 士气 × 敌将）
## 胜率 = 玩家战力 / (玩家 + 敌)；均势 50%，一方压倒则趋近 1。
func _board_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	boarding = true
	boarding_target = enemy
	_AUDIO.combat_board(self)
	enemy.set("grappled", true)  # 敌船停航停炮

	# Lane N：真实接舷钩子 — 钩索题签 + 轻震（不改白刃数值）
	var stage: CanvasLayer = _BoardingStage.begin(self, ship, enemy, _CombatFx.board_begin_subtitle())
	_CombatFx.punch_camera(ship, 5.0)
	if not _Kit.is_headless():
		# 计时器挂在本节点下（lane gd17）：原 get_tree().create_timer 挂在 SceneTree 上，这 0.42 s 里 WorldMap 被释放
		# （别的敌船把旗舰打沉 → _battle_exit / 退出）后协程醒不来也放不掉，退出报 ObjectDB 泄漏（GDScriptFunctionState）。
		# 挂在自己下面则随本节点一起释放，挂起的协程随信号源丢弃。PROCESS_MODE_ALWAYS 同 create_timer 默认。
		var pause := Timer.new()
		pause.one_shot = true
		pause.process_mode = Node.PROCESS_MODE_ALWAYS
		pause.wait_time = 0.42
		add_child(pause)
		pause.start()
		await pause.timeout
		pause.queue_free()
	if not is_instance_valid(enemy) or not _boarding_target_valid():
		boarding = false
		boarding_target = null
		return

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
		var type_id := _node_str(enemy, "ship_type", "pirate_boat")
		var ship_name := _node_str(enemy, "ship_name", "")
		Fleet.lose_crew_random(lose_n)
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 4)
		GameState.martial = mini(100, GameState.martial + 1)
		var ok := Fleet.add_ship(type_id, ship_name)
		var taken: String = str(Fleet.ships[Fleet.ships.size() - 1].get("name", "敌船")) if ok else "敌船"
		var msg := _CombatFx.board_win_note(taken)
		var resolved_stage: CanvasLayer = _BoardingStage.resolve(self, "win", msg)
		if resolved_stage != null:
			stage = resolved_stage
		_show_combat_notice(msg)
		_CombatFx.hitstop(self, 0.09, 0.16)
		enemy.queue_free()
		boarding = false
		boarding_target = null
		if _enemies_alive() == 0:
			# 等接舷题签播完再出战，避免 WorldMap.queue_free 切断演出
			await _await_boarding_fx(stage)
			_battle_exit("win", {"boarded": true})
	else:
		var lose_n2 := maxi(1, int(Fleet.total_crew() * (0.20 + randf() * 0.10)))
		Fleet.lose_crew_random(lose_n2)
		Fleet.morale = maxi(0, Fleet.morale - 10)
		enemy.set("grappled", false)
		boarding = false
		boarding_target = null
		var msg2 := _CombatFx.board_lose_note(lose_n2)
		var lose_stage: CanvasLayer = _BoardingStage.resolve(self, "lose", msg2)
		if lose_stage != null:
			stage = lose_stage
		_show_combat_notice(msg2)
		await _await_boarding_fx(stage)


## 战斗通知浮字：在屏幕中央短暂显示（复用 FloatingText 场景），3 秒后淡出
var _notice: Label = null
func _show_combat_notice(text: String) -> void:
	if not is_instance_valid(_notice):
		_notice = Label.new()
		_notice.set_anchors_preset(Control.PRESET_CENTER)
		_notice.add_theme_font_override("font", UiTheme.font())
		_notice.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
		_notice.add_theme_color_override("font_color", UiTheme.GOLD)
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
	if ship.wind_vector.y > 0: wind_desc = "北风"
	elif ship.wind_vector.y < 0: wind_desc = "南风"
	elif ship.wind_vector.x > 0: wind_desc = "西风"
	elif ship.wind_vector.x < 0: wind_desc = "东风"

	var hp_color := "#" + UiTheme.hex(UiTheme.MOSS)
	if ship.hull_hp < 50:
		hp_color = "#" + UiTheme.hex(UiTheme.CINNABAR)

	var tail := "弃战　B"
	var mission := ""
	if combat_mode:
		mission = "敌船 %d 艘　存活 %d" % [total_enemies, _enemies_alive()]
	var boarding_hint := ""
	if combat_mode and not resolved:
		if boarding:
			tail = "白刃中"
			boarding_hint = "[color=#%s]已钩住[/color]" % UiTheme.hex(UiTheme.HONEY)
		else:
			var ne := _nearest_enemy()
			if ne.size() == 2 and ne[1] < BOARD_DISTANCE:
				tail = "接舷　G　弃战　B"
				boarding_hint = "[color=#%s]舷边可接[/color]" % UiTheme.hex(UiTheme.HONEY)
	label.text = _format_left_hud(
		mission, boarding_hint, wind_desc, int(ship.wind_strength),
		ship.sail_gear, hp_color, int(ship.hull_hp), int(ship.max_hp), tail,
	)

	var cargo_bits := PackedStringArray()
	for k in Fleet.cargo.keys():
		cargo_bits.append("%s ×%d" % [GameManager.get_good_name(k), int(Fleet.cargo[k].get("qty", 0))])
	var cargo_str := "空" if cargo_bits.is_empty() else "　".join(cargo_bits)

	fleet_status.text = "金钱　%d　　货舱　%s" % [GameState.money, cargo_str]


## 顶匾文案单独拼，避免一条长 % 串数错占位（Godot 4.6 少参数会整栏变空）。
## 两行横排：操纵在上，敌船风船体在下。实时操船，不收进浮层。
func _format_left_hud(
	mission: String, boarding_hint: String, wind_desc: String, wind_strength: int,
	sail_gear: int, hp_color: String, hull_hp: int, max_hp: int, tail: String
) -> String:
	var bits := PackedStringArray()
	var mission_line := mission.replace("\n", "")
	var hint_line := boarding_hint.replace("\n", "")
	if mission_line != "":
		bits.append(mission_line)
	if hint_line != "":
		bits.append(hint_line)
	bits.append("季风　%s　风力　%d" % [wind_desc, wind_strength])
	bits.append("船体　[color=%s]%d / %d[/color]" % [hp_color, hull_hp, max_hp])
	return "升帆　W　落帆　S　%s　　操舵　A　D　　齐射　J　K　　%s\n%s" % [
		_sail_word(sail_gear), tail, "　　".join(bits),
	]


func _sail_word(gear: int) -> String:
	if gear <= 0:
		return "收帆"
	if gear == 1:
		return "半帆"
	return "满帆"

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
			weather_status.text = "天气　骤雨"
			weather_status.add_theme_color_override("font_color", UiTheme.CINNABAR)
			rain_particles.emitting = true
			ship.wind_strength = base_wind_strength * randf_range(2.0, 3.5)
			var angle = randf() * TAU
			ship.wind_vector = Vector2(cos(angle), sin(angle))
		else:
			storm_timer = randf_range(40.0, 80.0)
			weather_status.text = "天气　晴"
			weather_status.add_theme_color_override("font_color", UiTheme.TEXT)
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

# ── 战斗模式（P4-1 接入）─────────────────────────────

## 由 _ready 在 pending_battle.battle 时调用：禁用停靠、生成敌舰队
## 自由航行刷怪（crate / 海鸟 / 鲸影 / 野海盗）已拆除：WorldMap 只作战术层。
func _setup_combat(pb: Dictionary) -> void:
	combat_mode = true
	_AUDIO.combat_start(self)
	# 战斗专用：禁掉 PortZone 停靠出口（否则 Enter 会切回 Main 丢战斗）
	$Ports.process_mode = Node.PROCESS_MODE_DISABLED
	$Ports.visible = false
	combat_start_durability = Fleet.total_durability()
	total_enemies = 0
	var enemy_list: Array = pb.get("enemy", [])
	for entry in enemy_list:
		var type_id: String = entry.get("type", "pirate_boat")
		var count: int = entry.get("count", 1)
		# sprite 只管海战精灵（船图契约）；元军哨船 type 仍是 sea_falcon，另挂 sprite=yuan_patrol
		_spawn_enemy(type_id, count, pb, str(entry.get("sprite", "")))
	weather_status.text = "海战"
	weather_status.add_theme_color_override("font_color", UiTheme.HONEY)
	_try_letterbox_enter(pb)


## 生成一支敌舰队，绕玩家船散布；hull_hp 按战力比缩放。sprite_id 空则精灵按 type 取（PirateShip.apply_sprite）
func _spawn_enemy(type_id: String, count: int, pb: Dictionary, sprite_id := "") -> void:
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
		var angle := TAU * float(i) / float(maxi(count, 1)) + randf_range(-0.25, 0.25)
		var dist := randf_range(COMBAT_SPAWN_DIST_MIN, COMBAT_SPAWN_DIST_MAX)
		p.position = ship.position + Vector2(cos(angle), sin(angle)) * dist
		p.target = ship
		p.hull_hp = hull
		# P4-2：白刃/夺船输入。节点名保持 "PirateShip" 前缀（_enemies_alive 依赖），
		# 夺船后的船名另存 ship_name（沿用敌船名，如「快船」）。
		p.ship_name = "%s" % type_name
		p.ship_type = type_id
		p.sprite_id = sprite_id
		p.crew = randi_range(crew_low, crew_high)
		p.enemy_morale = randi_range(50, 75)
		p.captain_force = 1.0 + 0.3 * float(scale - 1.0)  # 强敌水手多，头目更悍
		p.cannon_count = mini(COMBAT_CANNON_CAP, maxi(1, int(round(3.0 * scale))))
		# 刷在镜头里等于已经进射程。fire_timer 默认 0 会首帧齐射，
		# 开局小艍 120 耐久扛不住 2 艘 × 9 门，HUD 还没看清就沉。
		p.fire_timer = COMBAT_FIRE_DELAY
		p.name = "PirateShip_%d" % (i + 1)
		add_child(p)
		total_enemies += 1


## B 或 Esc：弃战逃走。成败都退出战斗，写回由 SeaChart 结算。栏上只写 B。
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
			var chance := Voyage.flee_success_chance()
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
	_last_boarded = bool(data.get("boarded", false))
	if _last_boarded:
		data["boarded"] = true
	_AUDIO.combat_result(self, outcome)
	_try_letterbox_exit(outcome)
	battle_finished.emit(outcome, data)
	queue_free()


## Godot 4 的 Object.get() 只收 1 个参数（带默认值的是 Dictionary.get），缺属性时返回 null；
## 且 float(null) 在运行期报错中止，所以对 Node 取属性统一走这两个判空封装。
static func _prop_f(o: Object, prop: String, default_v: float) -> float:
	var v = o.get(prop)
	return default_v if v == null else float(v)


static func _prop_s(o: Object, prop: String, default_v: String) -> String:
	var v = o.get(prop)
	return default_v if v == null else str(v)


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══

## Lane N：等待接舷题签播完（headless / 无舞台则立刻返回）。
func _await_boarding_fx(stage: CanvasLayer) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	if _Kit.is_headless():
		return
	if stage.has_signal("finished"):
		await stage.finished


## Lane C：进出战墨边（若 CombatLetterbox 已入库则调用；否则静默跳过）。
func _try_letterbox_enter(pb: Dictionary) -> void:
	if not ResourceLoader.exists(_LETTERBOX_PATH):
		return
	var LB = load(_LETTERBOX_PATH)
	if LB == null:
		return
	var enemy_list: Array = pb.get("enemy", [])
	var enemy_n := 0
	for e in enemy_list:
		if e is Dictionary:
			enemy_n += int(e.get("count", 1))
	var note: String = str(LB.enemy_note(enemy_list))
	if note.strip_edges() == "":
		note = _CombatFx.battle_enter_subtitle(enemy_n)
	var sub := "%s　%s" % [Calendar.get_date_string(), note]
	var sea := str(pb.get("sea_name", "外海")).strip_edges()
	if sea == "":
		sea = "外海"
	LB.enter(self, LB.sea_title(sea, "遇敌"), sub)
	_CombatFx.hitstop(self, 0.045, 0.32)


func _try_letterbox_exit(outcome: String) -> void:
	if not ResourceLoader.exists(_LETTERBOX_PATH):
		return
	var parent := get_parent()
	if parent == null:
		return
	var LB = load(_LETTERBOX_PATH)
	if LB == null:
		return
	var act_outcome := outcome
	if _last_boarded and outcome == "win":
		act_outcome = "board"
	var sea_x := "外海"
	var pb_x: Dictionary = GameManager.pending_battle
	if pb_x is Dictionary:
		var sn := str(pb_x.get("sea_name", "")).strip_edges()
		if sn != "":
			sea_x = sn
	LB.exit(parent, LB.outcome_title(act_outcome, sea_x), Calendar.get_date_string())

