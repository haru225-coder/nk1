extends Node2D

const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
const _BoardingStage := preload("res://scripts/combat/BoardingStage.gd")
const _MeleeResolve := preload("res://scripts/combat/MeleeResolve.gd")
const _CombatMorale := preload("res://scripts/combat/CombatMorale.gd")
const _CombatShoreHook := preload("res://scripts/combat/CombatShoreHook.gd")
const _LETTERBOX_PATH := "res://scripts/ui/CombatLetterbox.gd"
const _Kit := preload("res://scripts/cutscene/cs_kit.gd")
const _SeaState := preload("res://scripts/combat/SeaState.gd")
const _Maneuver := preload("res://scripts/combat/ManeuverModel.gd")

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
## 参考风力：海战里是 SeaState 按月令季风定本场风力的基准（季风盛时约等于它），自由航行（孤儿场景）照旧直接用
var base_wind_strength: float = 80.0

# ── 风流与机动（lane combat02）──
## 本场海况（SeaState：风向 / 风力 / 阵风 / 海流），_setup_sea 建；没开战为 null。别处用 sea_state() 取
var _sea: _SeaState = null
## 旗舰机动模型（ManeuverModel 实例）：_physics_process 里按它换掉 Ship 自己那一步的转向与位移
var _helm: _Maneuver = null
## 旗舰船首向（rad）：模型的航向，每物理帧写回 ship.rotation
var _helm_rot: float = 0.0
## 旗舰船型（ships.json id），开战时从 Fleet 旗舰取
var _flagship_type: String = ""

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

## P4-2 接舷距离：低于此距离可按 G 钩住敌船进入白刃。lane combat02 起是基准够距：
## 实际够距按风压差、上风位、相对航速在它上下浮（_board_check → ManeuverModel.boarding_approach）
const BOARD_DISTANCE := 140.0
## 白刃阶段（接舷中）：玩家已钩住某船，停炮击、禁逃离，只等白刃判定
var boarding: bool = false
## 接舷白刃的目标敌船（P4-2）
var boarding_target: Node2D = null
## lane combat11：士气观战挂件（CombatMorale.Tracker）；开战挂上，收战随场景释放
var _morale = null
## 开战时在册船数：战损只按这几条算，夺来入列的船不进 player_damage
var _battle_roster_n: int = 0
## 末船接舷夺下后等题签播完再收战：挡住 _process 的 win{} 抢先（await 即便 headless 也会让出一帧）
var _finishing_boarded: bool = false
## combat12：敌船 left_battle(escaped) 计数（HUD / 探针读）；收战下场明细另记 _enemy_fates
var _enemies_escaped: int = 0
## combat12：敌船下场账 instance_id → {type, fate}（fate 取 CombatLetterbox.FATE_VERB 的键：struck / boarded / sunk / fled）。
## 遁走在 left_battle、夺船在 _board_enemy 当场记，其余离树时按船体记沉；收战时并进 win data.fates，
## 题签（fates_of）与 SeaChart 分账（半赏只给「一艘没沉没夺没降、只是遁走」）都按它算——士气收场的 morale_verdict 只看在场的船，
## 先沉一艘、后遁一艘也报 enemy_fled，不能单凭它给半赏。
var _enemy_fates: Dictionary = {}
## combat12：开战经过秒数；到 battle_limit_s（combat_phases.json thresholds，缺省 BATTLE_LIMIT_S）两散 parted
var _battle_elapsed_s: float = 0.0
var _battle_limit_s: float = 300.0
const BATTLE_LIMIT_S := 300.0
const _PHASES_PATH := "res://data/combat_phases.json"

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

	# 战损统计：只按开战时在册的船算（夺来入列的船不进总耐久差，避免负数）
	if combat_mode:
		player_damage = combat_start_durability - _roster_durability()

	# P4-2 接舷：boarding 阶段检测白刃目标是否存活（敌被打沉/脱钩则退出）
	if combat_mode and not resolved:
		if boarding:
			if not _boarding_target_valid():
				boarding = false
				boarding_target = null

	# 敌全灭 → 获胜（接舷中 / 末船夺下等题签 不判定：避免抢掉 boarded=true）。各船下场由 _battle_exit 并进 data.fates
	if combat_mode and not resolved:
		if not boarding and not _finishing_boarded and _enemies_alive() == 0:
			_battle_exit("win", {})

	# combat12：限时两散（阶段图 t_time_up → disengaged，legacy flee{flee_ok, parted}）；钩住白刃时不计时
	if combat_mode and not resolved and not boarding and not _finishing_boarded:
		_battle_elapsed_s += delta
		if _battle_elapsed_s >= _battle_limit_s:
			_battle_exit("flee", {"flee_ok": true, "parted": true})

	_update_hud()


## lane combat02：海况逐物理帧推进，旗舰按机动模型走。本节点 process_physics_priority 调到船后面（_setup_sea），
## 这里拿到的是 Ship 本帧已按旧式风力转过向、挪过位的状态，再换成模型的（Ship.gd 不归本 lane，出航接口不动）。
func _physics_process(delta: float) -> void:
	if not combat_mode or resolved or _sea == null or _helm == null or not is_instance_valid(ship):
		return
	_sea.step(delta)
	_feed_ship_wind()
	if ship.hull_hp > 0.0:
		_steer_flagship(delta)


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
	# 夺船 queue_free 后仍在树上、hull_hp 未清时，必须排除，否则 boarded=true 收战走不到
	return (
		n != null
		and is_instance_valid(n)
		and not n.is_queued_for_deletion()
		and n.name.begins_with("PirateShip")
		and _node_float(n, "hull_hp") > 0.0
	)


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


## P4-2 / combat11：接舷白刃走 MeleeResolve；士气簿 yields 则免白刃直接夺。
## 钩缆在 G 键 / 调用方已确认够距后挂上，故 resolve 带 hooked=true（跳过抛钩掷骰，探针远距直调也能夺）。
## 末船夺下必须当帧 _battle_exit(boarded=true)：await 题签会让出帧，探针只等 30 帧，且 _process 会抢 win{}。
func _board_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	boarding = true
	boarding_target = enemy
	_AUDIO.combat_board(self)
	enemy.set("grappled", true)  # 敌船停航停炮

	var detail := ""
	var notice := ""
	var do_capture := false

	# 敌已降幡：接舷即得，免白刃
	var yield_sheet = _morale.sheet_of(enemy) if _morale != null else null
	if yield_sheet != null and yield_sheet.yields_to_boarding():
		do_capture = true
		notice = _CombatFx.board_win_note(_node_str(enemy, "ship_name", "敌船"))
		detail = "敌船降幡，接舷收船"
	else:
		# MeleeResolve：有士气簿则攻方 morale 换 melee_factor
		var ctx_extra := {"hooked": true}
		var ps = _morale.player_sheet() if _morale != null else null
		var r: Dictionary
		if ps != null:
			var us: Dictionary = _MeleeResolve.side_from_fleet(Fleet)
			us["morale"] = clampi(int(round(ps.melee_factor() * 100.0)), 0, 100)
			var foe: Dictionary = _MeleeResolve.side_from_enemy(enemy)
			var ctx: Dictionary = _MeleeResolve.approach_from_nodes(
				ship, enemy, Vector2.ZERO, -1.0, str(us.get("type", "")), str(foe.get("type", ""))
			)
			for k in ctx_extra:
				ctx[k] = ctx_extra[k]
			r = _MeleeResolve.resolve(us, foe, ctx)
		else:
			r = _MeleeResolve.from_battle(Fleet, ship, enemy, ctx_extra)

		_CombatFx.punch_camera(ship, 5.0)
		if not is_instance_valid(enemy) or not _boarding_target_valid():
			boarding = false
			boarding_target = null
			return

		var legacy := str(r.get("legacy", "lose"))
		var att_dead := int(r.get("att_dead", 0))
		var morale_delta := int(r.get("att_morale_delta", 0))
		Fleet.lose_crew_random(att_dead)
		Fleet.morale = clampi(Fleet.morale + morale_delta, 0, Fleet.MORALE_MAX)
		detail = str(r.get("summary", "")).strip_edges()
		if legacy == "win":
			do_capture = true
			GameState.martial = mini(100, GameState.martial + 1)
		else:
			# 落空 / 击退 / 脱钩：解开钩缆，不把敌船留在 grappled
			if is_instance_valid(enemy):
				enemy.set("grappled", false)
			boarding = false
			boarding_target = null
			var msg2 := detail if detail != "" else _CombatFx.board_lose_note(att_dead)
			var stage_l: CanvasLayer = _BoardingStage.begin(self, ship, enemy, _CombatFx.board_begin_subtitle())
			var lose_stage: CanvasLayer = _BoardingStage.resolve(self, "lose", msg2)
			if lose_stage != null:
				stage_l = lose_stage
			_show_combat_notice(msg2)
			await _await_boarding_fx(stage_l)
			return

	if do_capture:
		var type_id := _node_str(enemy, "ship_type", "pirate_boat")
		var ship_name := _node_str(enemy, "ship_name", "")
		var ok := Fleet.add_ship(type_id, ship_name)
		var taken: String = str(Fleet.ships[Fleet.ships.size() - 1].get("name", "敌船")) if ok else "敌船"
		if notice == "":
			notice = _CombatFx.board_win_note(taken)
		if detail == "":
			detail = notice
		var stage: CanvasLayer = _BoardingStage.begin(self, ship, enemy, _CombatFx.board_begin_subtitle())
		var resolved_stage: CanvasLayer = _BoardingStage.resolve(self, "win", detail)
		if resolved_stage != null:
			stage = resolved_stage
		_show_combat_notice(notice)
		_CombatFx.hitstop(self, 0.09, 0.16)
		# 下场先记（降了的收船记受降），再清血量：离树时按船体记沉会把夺来的船记成击沉
		_note_fate(enemy, "struck" if yield_sheet != null and yield_sheet.yields_to_boarding() else "boarded")
		# 清血量再释放：避免 queue_free 后仍被 _enemies_alive 数到
		enemy.set("hull_hp", 0.0)
		enemy.queue_free()
		boarding = false
		boarding_target = null
		if _enemies_alive() == 0:
			# 末一艘夺下：当帧收战（不 await，探针 30 帧内要收到 boarded）
			_finishing_boarded = true
			_battle_exit("win", {"boarded": true})
		else:
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
	var wind_desc := _wind_desc()

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
			if ne.size() == 2:
				var bc := _board_check(ne[0])
				if bool(bc.get("ok", false)):
					tail = "接舷　G　弃战　B"
					boarding_hint = "[color=#%s]舷边可接[/color]" % UiTheme.hex(UiTheme.HONEY)
				elif str(bc.get("reason", "")) != "":
					boarding_hint = "[color=#%s]%s[/color]" % [UiTheme.hex(UiTheme.TEXT_DIM), str(bc["reason"])]
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
		_feed_ship_wind()
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
	_enemies_escaped = 0
	_enemy_fates = {}
	_battle_elapsed_s = 0.0
	_battle_limit_s = _phases_battle_limit_s()
	combat_mode = true
	_AUDIO.combat_start(self)
	# 战斗专用：禁掉 PortZone 停靠出口（否则 Enter 会切回 Main 丢战斗）
	$Ports.process_mode = Node.PROCESS_MODE_DISABLED
	$Ports.visible = false
	combat_start_durability = Fleet.total_durability()
	_battle_roster_n = Fleet.ships.size()
	total_enemies = 0
	var enemy_list: Array = pb.get("enemy", [])
	for entry in enemy_list:
		var type_id: String = entry.get("type", "pirate_boat")
		var count: int = entry.get("count", 1)
		# sprite 只管海战精灵（船图契约）；元军哨船 type 仍是 sea_falcon，另挂 sprite=yuan_patrol
		_spawn_enemy(type_id, count, pb, str(entry.get("sprite", "")))
	_setup_sea(pb)
	_sync_ocean_look()
	if is_instance_valid(ship):
		_CombatFx.dress_ship(ship, _wind_to() * clampf(_wind_speed() / 150.0, 0.0, 1.0))
	weather_status.text = "海战　%s" % _sea.current_desc()
	weather_status.add_theme_color_override("font_color", UiTheme.HONEY)
	_try_letterbox_enter(pb)
	# combat11：士气挂件 + 号令/状态 UI
	_morale = _CombatMorale.attach(self)
	if _morale != null:
		_morale.verdict.connect(_battle_exit)
		_morale.noted.connect(_on_morale_noted)
	_CombatShoreHook.mount_combat_ui(self, ship)


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
		_wire_enemy_signals(p)
		total_enemies += 1


## B 或 Esc：弃战逃走。成败都退出战斗，写回由 SeaChart 结算。栏上只写 B。
## G：接舷白刃（P4-2）。贴近敌船时按 G 钩住进入白刃判定
func _unhandled_input(event: InputEvent) -> void:
	if not combat_mode or resolved:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G:
			var ne := _nearest_enemy()
			if boarding or ne.size() != 2:
				return
			if _morale != null:
				var why: String = _morale.player_boarding_check()
				if why != "":
					get_viewport().set_input_as_handled()
					_show_combat_notice(why)
					return
			var bc := _board_check(ne[0])
			if bool(bc.get("ok", false)):
				get_viewport().set_input_as_handled()
				_board_enemy(ne[0])
			elif str(bc.get("note", "")) != "":
				get_viewport().set_input_as_handled()
				_show_combat_notice(str(bc["note"]))
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
	if outcome == "win" and not data.has("fates"):
		var fates := _battle_fates()
		if not fates.is_empty():
			data["fates"] = fates
	_AUDIO.combat_result(self, outcome)
	_CombatShoreHook.unmount_combat_ui(self)
	_try_letterbox_exit(outcome, data)
	_SeaState.clear_active(_sea)
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


## 开战在册船的现总耐久（不含夺来入列的船）
func _roster_durability() -> float:
	var d := 0.0
	var n := mini(_battle_roster_n, Fleet.ships.size())
	for i in range(n):
		d += float(Fleet.ships[i].get("durability", 0))
	return d


## combat07：听敌将信号，更新通知 / 降幡观感（不重写 AI）
func _wire_enemy_signals(p: Node) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.has_signal("captain_state_changed"):
		var cb_s := Callable(self, "_on_captain_state_changed").bind(p)
		if not p.is_connected("captain_state_changed", cb_s):
			p.connect("captain_state_changed", cb_s)
	if p.has_signal("left_battle"):
		var cb_l := Callable(self, "_on_enemy_left_battle").bind(p)
		if not p.is_connected("left_battle", cb_l):
			p.connect("left_battle", cb_l)
	var cb_x := Callable(self, "_on_enemy_exiting").bind(p)
	if not p.tree_exiting.is_connected(cb_x):
		p.tree_exiting.connect(cb_x)
	if p.has_signal("grapple_thrown"):
		var cb_g := Callable(self, "_on_enemy_grapple_thrown").bind(p)
		if not p.is_connected("grapple_thrown", cb_g):
			p.connect("grapple_thrown", cb_g)


## combat12：记一艘敌船的下场（先记者为准：遁走 / 夺船当场记，离树时的「沉」不改写）
func _note_fate(enemy: Node, fate: String) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var id := enemy.get_instance_id()
	if not _enemy_fates.has(id):
		_enemy_fates[id] = {"type": _node_str(enemy, "ship_type", ""), "fate": fate}


## 敌船离树：没记过下场、船体见底的记沉（击沉 / 焚毁都走 PirateShip._explode）；船体还在的是收场拆树，不记
func _on_enemy_exiting(enemy: Node) -> void:
	if enemy != null and is_instance_valid(enemy) and _node_float(enemy, "hull_hp") <= 0.0:
		_note_fate(enemy, "sunk")


## 收战时的敌船下场明细 [{type, fate}]（形同 CombatLetterbox.fates_of）：已离场的取 _enemy_fates；
## 同帧刚沉、还没离树的按船体补记沉；还在场的按士气簿补记降幡 / 遁出（士气收场的那几艘）
func _battle_fates() -> Array:
	for child in get_children():
		if child is Node2D and String(child.name).begins_with("PirateShip") \
				and (child.is_queued_for_deletion() or _node_float(child, "hull_hp") <= 0.0):
			_note_fate(child, "sunk")
	var out: Array = []
	for id in _enemy_fates:
		out.append((_enemy_fates[id] as Dictionary).duplicate())
	if _morale != null and is_instance_valid(_morale):
		for child in get_children():
			if not _is_live_pirate(child) or _enemy_fates.has(child.get_instance_id()):
				continue
			var sheet = _morale.sheet_of(child)
			if sheet == null:
				continue
			if sheet.has_struck():
				out.append({"type": _node_str(child, "ship_type", ""), "fate": "struck"})
			elif sheet.escaped:
				out.append({"type": _node_str(child, "ship_type", ""), "fate": "fled"})
	return out


## 一场最长秒数：combat_phases.json thresholds.battle_limit_s.v，读不到用 BATTLE_LIMIT_S
static func _phases_battle_limit_s() -> float:
	var f := FileAccess.open(_PHASES_PATH, FileAccess.READ)
	if f == null:
		return BATTLE_LIMIT_S
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		var t = d.get("thresholds", {})
		if t is Dictionary and t.get("battle_limit_s") is Dictionary:
			var v = t["battle_limit_s"].get("v")
			if (v is float or v is int) and float(v) > 0.0:
				return float(v)
	return BATTLE_LIMIT_S


func _on_captain_state_changed(state: StringName, label: String, reason: String, enemy: Node = null) -> void:
	var lab := label.strip_edges()
	if lab == "":
		lab = str(state)
	var why := reason.strip_edges()
	var msg := "敌将改打法：%s" % lab
	if why != "":
		msg = "%s（%s）" % [msg, why]
	_show_combat_notice(msg)
	if str(state) == "strike" and enemy is Node2D and is_instance_valid(enemy):
		_CombatFx.strike_colors(enemy)


func _on_enemy_left_battle(how: String, enemy: Node = null) -> void:
	var nm := "敌船"
	if enemy != null and is_instance_valid(enemy):
		var sn = enemy.get("ship_name")
		if sn != null and str(sn).strip_edges() != "":
			nm = str(sn)
		if how == "escaped":
			_enemies_escaped += 1
			_note_fate(enemy, "fled")
			_show_combat_notice("敌船「%s」脱离远遁" % nm)
		else:
			_show_combat_notice("敌船「%s」离场（%s）" % [nm, how])
			# 沉没类离场：补沉船观感（PirateShip._explode 本身未调 CombatFx）
			if enemy is Node2D:
				_CombatFx.on_ship_sunk(self, (enemy as Node2D).global_position, false)
	else:
		_show_combat_notice("敌船离场（%s）" % how)


func _on_enemy_grapple_thrown(ok: bool, enemy: Node = null) -> void:
	if ok:
		_show_combat_notice("敌船抛钩咬舷！")
	else:
		_show_combat_notice("敌船抛钩落空")
	if enemy != null:
		pass  # 占位：保留 enemy 形参供信号 bind


func _on_morale_noted(_who: Node, _kind: String, text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		_show_combat_notice(t)


## 号令面板 order_issued → 可选钩子（CombatShoreHook.mount_combat_ui 若发现本方法会自动连）
func _on_combat_order(order_id: String, _payload: Dictionary = {}) -> void:
	var oid := order_id.strip_edges()
	if oid != "":
		_show_combat_notice("号令：%s" % oid)


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


func _try_letterbox_exit(outcome: String, data: Dictionary = {}) -> void:
	if not ResourceLoader.exists(_LETTERBOX_PATH):
		return
	var parent := get_parent()
	if parent == null:
		return
	var LB = load(_LETTERBOX_PATH)
	if LB == null:
		return
	var sea_x := "外海"
	var pb_x: Dictionary = GameManager.pending_battle
	if pb_x is Dictionary:
		var sn := str(pb_x.get("sea_name", "")).strip_edges()
		if sn != "":
			sea_x = sn
	# combat09：exit_for 按 outcome/data 分事由（夺船 / 敌降 / 溃逃…），递 data 含 boarded
	LB.exit_for(parent, outcome, data, sea_x, Calendar.get_date_string())


# ══ 风流与机动（lane combat02）══════════════════════════════════
# 海况（SeaState）按月令季风与海域定风、定流；旗舰按 ManeuverModel 走：顶风减速、侧风横漂（风压差）、顺风加速，
# 转向半径按船型、舵效随对水航速，海流叠成对地航速；接舷够距吃风压差、上风位与相对航速。
# 敌船怎么走归 PirateShip / EnemyCaptainAI，这里不挪敌船（免得与之重算海流）；它们要风流读数走下面的查询口或 SeaState.active()。

## 开战建海况与旗舰机动模型。pending_battle 可选键（剧情 / 探针定场用，SeaChart 不写）：
##   sea_seed 随机种子 · wind_bearing 吹向方位（度，0 北 90 东）· wind_strength 风力
func _setup_sea(pb: Dictionary) -> void:
	var month := Calendar.month
	_sea = _SeaState.new()
	_sea.setup(Calendar.wind_bearing_of(month), Calendar.monsoon_strength_of(month), base_wind_strength,
		str(pb.get("sea_name", "外海")), int(pb.get("sea_seed", -1)))
	if pb.has("wind_bearing") or pb.has("wind_strength"):
		var to_b: float = float(pb.get("wind_bearing", _SeaState.bearing_of(_sea.wind_to)))
		_sea.force_wind(to_b, float(pb.get("wind_strength", _sea.wind_mean)))
	_SeaState.bind_active(_sea)
	var fs := Fleet.flagship()
	_flagship_type = str(fs.get("type", ""))
	# 旗舰节点上记一笔船型：别的模块拿船节点问 ManeuverModel（hull_state_of）时认得出是什么船
	ship.set_meta(_Maneuver.META_HULL_TYPE, _flagship_type)
	_helm = _Maneuver.new(_flagship_type, int(fs.get("sail_level", 1)), Crew.level_of("duogong"))
	_helm_rot = ship.rotation
	# 先读一次帆向（dt = 0 不改航速），顶匾第一帧就写对
	_helm.step(Vector2.UP.rotated(_helm_rot), 0.0, int(ship.sail_gear), _sea.wind_to, _sea.wind_speed,
		_sea.current_at(ship.position), 0.0)
	# 物理帧排在船后面：Ship / PirateShip 先走完本帧，_physics_process 再按模型改旗舰
	process_physics_priority = 10
	_feed_ship_wind()


## 海况的风喂给旗舰：Ship 拿它算侧倾（旧式推力已被模型换掉）。海战风力封顶在风暴伤线以下（SeaState.WIND_CAP）
func _feed_ship_wind() -> void:
	ship.wind_strength = _wind_speed()
	ship.wind_vector = _wind_to()


## 旗舰按机动模型走一帧：航向按舵效转（对水航速 / 船型转向半径），航速按帆向，外加风压差横漂与海流。
## Ship 这一帧按旧式风力挪过的那段位移补差成模型的；钩住敌船时两船绑在一处，停航停舵、不随流走开。
func _steer_flagship(delta: float) -> void:
	var heading := Vector2.UP.rotated(_helm_rot)
	var want: Vector2
	if boarding:
		want = _helm.hold(heading, delta)
	else:
		want = _helm.step(heading, _helm_input(), int(ship.sail_gear), _sea.wind_to, _sea.wind_speed,
			_sea.current_at(ship.position), delta, _maneuver_mods(ship))
		_helm_rot = wrapf(_helm_rot + _helm.yaw_rate * delta, -PI, PI)
	ship.rotation = _helm_rot
	var fix: Vector2 = (want - ship.velocity) * delta
	if fix.length_squared() > 0.0001:
		ship.move_and_collide(fix)
	ship.velocity = want


## 旗舰操舵输入（同 Ship：方向键左右或 A / D；−1 左舵 … 1 右舵）
func _helm_input() -> float:
	var t := Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		t -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		t += 1.0
	return clampf(t, -1.0, 1.0)


## 船体损伤对机动的折减（可选接口）：船节点有 maneuver_mods() 就原样用（键见 ManeuverModel 头注释）；
## 没有而有 maneuver_factors()（lane combat04 损伤模型：speed 走力 / turn 转向 / yaw_drift 舵失灵自偏 / gear_cap 帆挂得起几成）
## 就换成 hull / rudder / yaw_drift / gear_cap；都没有按完好算
func _maneuver_mods(n: Object) -> Dictionary:
	if n == null:
		return {}
	if n.has_method("maneuver_mods"):
		var m = n.call("maneuver_mods")
		if m is Dictionary:
			return m
	if n.has_method("maneuver_factors"):
		var f = n.call("maneuver_factors")
		if f is Dictionary:
			var out := {}
			for pair in [["speed", "hull"], ["turn", "rudder"], ["yaw_drift", "yaw_drift"], ["gear_cap", "gear_cap"]]:
				if f.has(pair[0]):
					out[pair[1]] = f[pair[0]]
			return out
	return {}


## 船节点 → ManeuverModel 查询用的船况（ManeuverModel.hull_state_of：位置、对地速度、船首向、船型、升帆几成，
## 敌船不报 sail_gear 的按满帆算）；旗舰船型按开战时 Fleet 旗舰的
func _hull_state(n: Node2D) -> Dictionary:
	var st := _Maneuver.hull_state_of(n)
	if n == ship:
		st["type"] = _flagship_type
	return st


## 接舷够不够得着：吃风压差、上风位与相对航速（旗舰钩 enemy）
func _board_check(enemy: Node2D) -> Dictionary:
	return boarding_approach_of(ship, enemy)


## 顶匾的风：海况的八方风名 + 旗舰此刻帆向（顶风 / 抢风 / 侧风 / 顺风）；没建海况（孤儿场景）照旧按 Ship 的风写四向
func _wind_desc() -> String:
	if _sea != null and _helm != null:
		return "%s　%s" % [_sea.wind_name(), _helm.sail_state]
	var wv: Vector2 = ship.wind_vector
	if wv.y > 0:
		return "北风"
	if wv.y < 0:
		return "南风"
	if wv.x > 0:
		return "西风"
	if wv.x < 0:
		return "东风"
	return "无风"


func _wind_to() -> Vector2:
	return _sea.wind_to if _sea != null else Vector2(0, 1)


func _wind_speed() -> float:
	return _sea.wind_speed if _sea != null else base_wind_strength


## 离树（出战 queue_free、探针拆布景）放掉当前海况，别处 SeaState.active() 不再拿到这一场
func _exit_tree() -> void:
	_SeaState.clear_active(_sea)


# ── 查询口（只读：给敌船 AI、指令面板、弹道、白刃取用）──

## 本场海况（SeaState 实例：wind_to / wind_speed / current_at / wind_name / current_desc / snapshot）；没开战为 null
func sea_state() -> RefCounted:
	return _sea


## 海面着色器跟风向：涌浪带沿季风拉长；开战时调一次，阵风大变时可再调。
func _sync_ocean_look() -> void:
	var ocean := get_node_or_null("Ocean") as CanvasItem
	if ocean == null or ocean.material == null:
		return
	var mat := ocean.material as ShaderMaterial
	if mat == null:
		return
	var w := _wind_to()
	if w.length() > 0.01:
		mat.set_shader_parameter("wind_angle", w.angle())
	var spd := clampf(_wind_speed() / 180.0, 0.15, 1.0)
	mat.set_shader_parameter("wave_speed", lerpf(0.18, 0.42, spd))
	mat.set_shader_parameter("foam_amount", lerpf(0.28, 0.62, spd))
	mat.set_shader_parameter("glint_amount", lerpf(0.12, 0.32, spd))



## 旗舰机动读数（帆向、对水 / 对地航速、风压差角、转向半径……，ManeuverModel.snapshot）并上海况读数（SeaState.snapshot）
func maneuver_snapshot() -> Dictionary:
	var out := {}
	if _sea != null:
		out.merge(_sea.snapshot())
	if _helm != null:
		out.merge(_helm.snapshot())
	return out


## shooter 打 target 的舷角：哪一舷、离正横几度、在不在射界，顺逆风与侧倾对射程、准头的修正（ManeuverModel.fire_arc）。
## 两个形参故意不写类型：调用方手里的船可能刚被打沉释放，带类型的形参收到已释放实例当场报错；这里判了才用，失效返回 {}
func fire_arc_of(shooter, target, arc_half_deg := 30.0) -> Dictionary:
	if not (_valid_hull(shooter) and _valid_hull(target)):
		return {}
	var st := _hull_state(shooter)
	return _Maneuver.fire_arc(shooter.position, st["heading"], target.position, _wind_to(), _wind_speed(),
		int(st["gear"]), arc_half_deg)


## a 钩 b 的接舷接近：够距按风压差、上风位、相对航速在 BOARD_DISTANCE 上下浮（ManeuverModel.boarding_approach）。
## 形参不写类型同 fire_arc_of；失效返回 {}
func boarding_approach_of(a, b) -> Dictionary:
	if not (_valid_hull(a) and _valid_hull(b)):
		return {}
	return _Maneuver.boarding_approach(_hull_state(a), _hull_state(b), _wind_to(), _wind_speed(), BOARD_DISTANCE)


func _valid_hull(n) -> bool:
	return is_instance_valid(n) and n is Node2D
