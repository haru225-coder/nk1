class_name Ship
extends CharacterBody2D

# 核心航海物理 v4.0 (火炮海战版)

## 分系统损伤事件（lane combat04）：船体、伤亡已记进舰队之后才发。kind 见 DamageModel.EVENT_SEVERITY，
## info 带 text（中文短注）、severity（0 转好 / 1 轻 / 2 重 / 3 危）及 comp / zone / n 等定位。
## 士气、状态条、观感要接就 connect；Ship 自己只在船上方写一行短注、飘字、点着船身三段的火烟，焦帆与舀水交给 CombatFx。
signal damage_event(kind: String, info: Dictionary)

@export var wind_vector: Vector2 = Vector2(0, 1).normalized()
@export var wind_strength: float = 80.0

var sail_gear: int = 0
var max_gear: int = 2

var base_turn_speed: float = 1.8
var max_speed: float = 300.0

var hull_hp: float = 100.0
var max_hp: float = 100.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var wake_particles: CPUParticles2D = $WakeParticles
@onready var bow_wave_left: CPUParticles2D = $BowWaveLeft
@onready var bow_wave_right: CPUParticles2D = $BowWaveRight
@onready var splinter_particles: CPUParticles2D = $SplinterParticles
@onready var camera: Camera2D = $Camera2D
@onready var damage_fx: Node2D = $DamageFx
@onready var damage_tag: Label = $DamageTag

var target_zoom = Vector2(1.5, 1.5)
# lazy load：避免 compile 时 Cannonball.gd → class Ship → preload 场景 → 再要 Cannonball.gd 的环
var cannonball_scene: PackedScene = null
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
const _DamageModel := preload("res://scripts/combat/DamageModel.gd")
var fire_cooldown: float = 0.0

## 旗舰的分系统损伤（船体 / 帆 / 舵 / 水手 + 浸水失火，lane combat04）。_ready 按旗舰船型建；没进树时第一次取用再建。
var damage_model: _DamageModel = null
## 船上方那行损伤短注（火、进水、倾侧、舵、帆、伤亡）。状态条接上以后可以关掉。
@export var show_damage_tag := true
## 找命中那颗弹：离船心这么近、不是自己打出去的 Area2D 才算（碰撞圆半径 24，弹速 800 一帧约走 13）
const IMPACT_SCAN := 90.0
## 损伤短注在船心上方多高；多久刷一次；飘字从船右侧哪里起（往上飘约 75，不碰短注）、之间隔多久、最多压几条
const TAG_RISE := 150.0
const NOTE_AT := Vector2(70, -40)
const TAG_REFRESH := 0.25
const NOTE_GAP := 0.7
const NOTE_QUEUE_MAX := 4
## 飘字的事件：接得住的险情与转好。舵叶、帆的零碎损伤只写进短注；伤亡一次 3 人以上才飘。
const NOTE_KINDS := ["leak", "compartment_full", "bulkhead_breach", "leak_stopped", "settling", "settle_stop", "list",
	"fire", "fire_spread", "fire_out", "sail_cut", "magazine", "mast_down", "rudder_lost", "jury_rudder",
	"founder", "capsize"]
## 船身三段甲板火的火烟挂点（Ship.tscn 的 DamageFx 下）；火势越大烟团越大（scale_amount_max，贴图是 32 像素的软圆）。
## 篷帆火（焦帆）与进水（舀水、甲板漫水）走观感线的 CombatFx.set_fire / set_flood（lane combat09），本船只按级调，不另画。
const FIRE_FX := {"bow": "FireBow", "mid": "FireMid", "stern": "FireStern"}
## 焦帆 / 舀水的级数变过这么多才重调一次 CombatFx（起、灭一律照调）
const FX_STEP := 0.05
const FIRE_PUFF_MIN := 0.4
const FIRE_PUFF_GAIN := 0.6
## 士气挂件（CombatMorale.Tracker，lane combat06）逐帧只读的两样情势：火势 0–1（各处合计，封顶 1）、
## 失去机动（舵失灵又没以橹代舵，或帆毁又无橹桨）。它按属性名读，这里只管每帧写对。
var fire_level := 0.0
var immobile := false
var _sprite_base_scale := Vector2.ONE
var _fx_fire_lv := 0.0
var _fx_flood_lv := 0.0
var _dress_t := 0.0
var _tag_t := 0.0
var _note_t := 0.0
var _note_queue: Array = []
var _note_scene: PackedScene = null

func _ready() -> void:
	# 战术场景反映旗舰状态；舰队数据以 Fleet 为准
	var fs: Dictionary = Fleet.flagship()
	apply_type_sprite(str(fs.get("type", "")))
	max_hp = float(fs.get("max_durability", 100.0))
	hull_hp = float(fs.get("durability", max_hp))
	var sail_lv: int = int(fs.get("sail_level", 1))
	max_speed = 300.0 + (sail_lv - 1) * 50.0
	base_turn_speed = 1.8 + (sail_lv - 1) * 0.2
	_sprite_base_scale = sprite.scale
	set_meta(&"nk1_sprite_base_scale", _sprite_base_scale)
	_CombatFx.dress_ship(self, wind_vector * clampf(wind_strength / 150.0, 0.0, 1.0))
	_polish_wake()
	_setup_damage_model(fs)
	_style_damage_tag()


## 船图契约：旗舰按 ships.json type 取 assets/ship_<type>.png，缺图留 Ship.tscn 里的 ship_fu.png。
## 不读 autoload、不依赖 @onready（没进树也能调），探针直接拿 Ship.tscn 实例验回落。
func apply_type_sprite(type_id: String) -> void:
	_CombatFx.apply_ship_sprite(get_node_or_null("Sprite2D") as Sprite2D,
		_CombatFx.ship_sprite_path(type_id, _CombatFx.SHIP_SPRITE_OWN))

func _input(event: InputEvent) -> void:
	# HUD 写 W/S 升降帆；工程默认 input map 只有方向键，两边都认。
	# 帆装打坏了挂不起满帆（DamageModel.gear_cap），升帆升到还挂得起的那档为止。
	if event.is_action_pressed("ui_up") or _key_pressed(event, KEY_W):
		sail_gear = min(sail_gear + 1, mini(max_gear, get_damage_model().gear_cap()))
	elif event.is_action_pressed("ui_down") or _key_pressed(event, KEY_S):
		sail_gear = max(sail_gear - 1, 0)
	
	if fire_cooldown <= 0:
		if event is InputEventKey and event.pressed:
			if not _can_fire():
				return
			if event.keycode == KEY_J:
				_fire_broadside(-1) # Left
			elif event.keycode == KEY_K:
				_fire_broadside(1) # Right


func _key_pressed(event: InputEvent, code: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == code


## P4-2 接舷：白刃阶段禁炮击（敌船已钩住，甲板上是白刃不是炮战）
func _can_fire() -> bool:
	var parent := get_parent()
	# Object.get 在 4.6 只收属性名，不能带默认值。
	if parent != null and parent.get("boarding") == true:
		return false
	return true

func _fire_broadside(side: int) -> void:
	var dm := get_damage_model()
	# lane combat04：船往这一舷倾得厉害，低舷入水、站不住人，这一舷打不出去。不进冷却，可以换另一舷，或者先戽水扶正。
	if not dm.side_ready(side):
		_note("%s舷低没，站不住人" % ("右" if side == 1 else "左"), 1)
		return
	# 装填时长按损伤放长：炮位缺人、船上有火烟、船身倾侧
	fire_cooldown = 2.0 * dm.reload_factor()
	var ship_dir = Vector2.UP.rotated(rotation)
	var side_dir = Vector2.RIGHT.rotated(rotation) if side == 1 else Vector2.LEFT.rotated(rotation)
	
	# P4-3：齐射弹数挂钩旗舰炮位（保底 1 发），排布居中不随炮位前移
	# lane combat04：伤亡多了人手不够、船上有火烟，只放得出几成（DamageModel.volley_factor），仍保底 1 发
	var flagship := Fleet.flagship()
	var slots := int(Fleet.ship_def(flagship.get("type", "")).get("cannon_slots", 0))
	var shots := maxi(1, int(round(float(maxi(1, slots)) * dm.volley_factor())))
	if cannonball_scene == null:
		cannonball_scene = load("res://scenes/Cannonball.tscn") as PackedScene
	for i in range(shots):
		var cb = cannonball_scene.instantiate()
		cb.position = position + ship_dir * (i - (shots - 1) * 0.5) * 20 + side_dir * 30
		# 散布按损伤放大：倾侧、火烟、生手顶位
		var spread = randf_range(-0.1, 0.1) * dm.spread_factor()
		cb.direction = side_dir.rotated(spread)
		cb.shooter = self
		get_parent().add_child(cb)
		
	_AUDIO.combat_fire(get_parent())
	_CombatFx.muzzle_flash(self, side, shots)
	_CombatFx.hull_shudder(self, 0.7, side)

	# 后坐：镜头往反舷推一下（旧 30 px 硬甩改顺势 11 px + 微收镜头，重量交给船身一颤与出手烟）
	_CombatFx.punch_camera(self, 11.0, -side_dir, 0.012)

func _physics_process(delta: float) -> void:
	if hull_hp <= 0: return
	if fire_cooldown > 0: fire_cooldown -= delta
	
	_step_damage(delta)
	if hull_hp <= 0: return
	_apply_sailing_physics(delta)
	move_and_slide()
	_update_visuals(delta)
	_process_storm_damage(delta)

func _apply_sailing_physics(delta: float) -> void:
	var ship_dir = Vector2.UP.rotated(rotation)
	var turn_input = Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		turn_input -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		turn_input += 1.0
	turn_input = clampf(turn_input, -1.0, 1.0)
	
	var turn_efficiency = 1.0
	if sail_gear == 2: turn_efficiency = 0.4
	elif sail_gear == 0: turn_efficiency = 0.0
		
	# lane combat04：舵、掌舵的人、舱水都会拖慢转向；舵失灵时船自己往一边偏，航速越快偏得越凶，A / D 还压得住一些。
	# 海战里 WorldMap 随后按 ManeuverModel 改写本帧航向与航速（损伤经 maneuver_mods 在那边乘），这里是没建海况时的旧式航行
	var dm := get_damage_model()
	rotation += turn_input * base_turn_speed * turn_efficiency * dm.turn_factor() * delta
	rotation += dm.yaw_drift() * clampf(velocity.length() / max_speed, 0.0, 1.0) * delta

	var wind_dot = ship_dir.dot(wind_vector)
	var drive_force = 0.0
	
	if sail_gear > 0:
		if wind_dot > 0:
			drive_force = (60.0 * sail_gear) + (wind_strength * wind_dot * sail_gear)
		else:
			var penalty = abs(wind_dot) * 30.0
			drive_force = max(10.0, (40.0 * sail_gear) - penalty)
	# 帆打烂了失速（有橹桨兜一点底）、操帆的人不够、舱水压低干舷、倾侧，都乘在走力上
	drive_force *= dm.speed_factor()
	
	var target_velocity = (ship_dir * drive_force)
	
	if sail_gear > 0:
		var drift = wind_vector * wind_strength * 0.4
		target_velocity += drift
		
	velocity = velocity.lerp(target_velocity, 2.0 * delta)

func _update_visuals(delta: float) -> void:
	var current_speed = velocity.length()
	
	var cross_wind = Vector2.RIGHT.rotated(rotation).dot(wind_vector)
	var roll_angle = cross_wind * wind_strength * 0.002 * sail_gear
	
	var turn_input = Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		turn_input -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		turn_input += 1.0
	turn_input = clampf(turn_input, -1.0, 1.0)
	roll_angle -= turn_input * (current_speed / max_speed) * 0.3
	
	sprite.rotation = lerp_angle(sprite.rotation, roll_angle, 5.0 * delta)
	
	var speed_ratio = current_speed / (max_speed * 1.5)
	
	if current_speed > 20.0:
		wake_particles.emitting = true
		wake_particles.initial_velocity_min = 20.0 + speed_ratio * 80.0
		wake_particles.initial_velocity_max = 40.0 + speed_ratio * 120.0
		# soft_dot 贴图：尺度用 0.2–0.55，旧无贴图方点才用 4–10
		wake_particles.scale_amount_min = 0.18
		wake_particles.scale_amount_max = 0.32 + speed_ratio * 0.28
		
		var bow_emit = current_speed > 100.0
		bow_wave_left.emitting = bow_emit
		bow_wave_right.emitting = bow_emit
		if bow_emit:
			bow_wave_left.scale_amount_min = 0.25
			bow_wave_left.scale_amount_max = 0.35 + speed_ratio * 0.25
			bow_wave_right.scale_amount_min = 0.25
			bow_wave_right.scale_amount_max = 0.35 + speed_ratio * 0.25
	else:
		wake_particles.emitting = false
		bow_wave_left.emitting = false
		bow_wave_right.emitting = false

	var zoom_val = 1.5 - (speed_ratio * 0.5)
	target_zoom = Vector2(zoom_val, zoom_val)
	camera.zoom = camera.zoom.lerp(target_zoom, 1.0 * delta)
	
	if current_speed > 250.0 or wind_strength > 150.0:
		var shake_intensity = (current_speed / 400.0) * 2.0
		camera.offset = Vector2(randf_range(-shake_intensity, shake_intensity), randf_range(-shake_intensity, shake_intensity))
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, 5.0 * delta)
	_dress_t -= delta
	if _dress_t <= 0.0:
		_dress_t = 0.4
		_CombatFx.dress_ship(self, wind_vector * clampf(wind_strength / 150.0, 0.0, 1.0))
	_update_damage_visuals(delta)

## 艏波：水滴贴图顺速度拉长（water_drop + align_y），速度联动仍由 _update_visuals 写。
## 尾迹改由 CombatFx 的 FxLook 画（中线翻白 + 开叉浪臂），WakeParticles 由它隐藏，节点保留。
func _polish_wake() -> void:
	for p in [bow_wave_left, bow_wave_right]:
		if p == null:
			continue
		p.texture = preload("res://assets/fx/water_drop.png")
		p.particle_flag_align_y = true
		p.color = Color(0.92, 0.96, 0.98, 0.5)
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.45
		p.amount = 10
		p.lifetime = 0.45
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
		p.color_ramp = g
		p.local_coords = false


func take_damage(amount: float) -> void:
	take_hit({"amount": amount})


## 带弹种、落点的命中入口（lane combat04）。hit 的键：amount（命中点数，已乘甲）；kind（shot / stone / arrow / bolt / fire / bomb / ram，
## 缺省 shot）；at（命中处的全局坐标）；zone / side / high（可缺）——见 DamageModel.apply_hit。
## Cannonball 仍调 take_damage(dmg)，落点由 _impact_local 找当帧贴着船身的那颗弹。
func take_hit(hit: Dictionary) -> void:
	if hull_hp <= 0:
		return
	splinter_particles.emitting = true
	var tween = create_tween()
	tween.tween_callback(func(): splinter_particles.emitting = false).set_delay(0.5)
	
	# 挂了船身反应节点（CombatFx.dress_ship）就不闪红：命中处一闪、一颤由 Cannonball → CombatFx.hull_impact 出
	if not _CombatFx.has_look(self):
		sprite.modulate = Color(1.25, 0.72, 0.55)
		var flash = create_tween()
		flash.tween_property(sprite, "modulate", Color.WHITE, 0.22)

	var h := hit.duplicate()
	if not h.has("local"):
		var at = _impact_local(h)
		if at != null:
			h["local"] = at
	var fx: Dictionary = get_damage_model().apply_hit(h)
	var hull_dmg := float(fx.get("hull", 0.0))
	_lose_crew(int(fx.get("crew", 0)))
	# 中弹会颠掉舱面货（箭矢、火箭这类不伤船体的不颠）
	if hull_dmg >= 5.0 and not Fleet.cargo.is_empty():
		var keys = Fleet.cargo.keys()
		var key = keys[randi() % keys.size()]
		Fleet.remove_cargo(key, 1)
	_hull_loss(hull_dmg)
	_emit_damage_events(fx.get("events", []))

func _process_storm_damage(delta: float) -> void:
	if wind_strength > 150.0 and sail_gear == 2:
		splinter_particles.emitting = true
		hull_hp -= 5.0 * delta
		Fleet.damage_fleet(5.0 * delta)
		if hull_hp <= 0:
			hull_hp = 0
			_sink_ship()
	elif wind_strength <= 150.0 or sail_gear < 2:
		if not fire_cooldown > 0: # Hacky way to not disable splinter if hit by cannon
			pass

func _sink_ship() -> void:
	# 海战（P4-1）：旗舰在 WorldMap 战斗中沉没 → 由 WorldMap 结算败局，不切场景。
	# 战斗里先清舱，会让 SeaChart 的 25% 货损落在空舱上，日志仍写「部分货物」。
	# 全队沉没的清舱在 SeaChart._sink；姊妹船还在时只走败局的比例货损。（云端 00b4）
	if GameManager.pending_battle.get("battle", false):
		get_parent()._battle_player_sunk()
		return
	Fleet.clear_cargo()
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ── 分系统损伤（lane combat04）──────────────────────────
# 船体、伤亡在这里落账（hull_hp 与 Fleet 同扣），浸水、失火逐帧推进，灌沉、倾覆仍走 _sink_ship 原路。
# 下面几支查询给状态条、指令条、机动、弹道、士气、白刃取用，不必认 DamageModel 的内部。

## 旗舰的损伤模型。没进树（探针直接 instantiate）时按 Fleet 旗舰现况建一份。
func get_damage_model() -> _DamageModel:
	if damage_model == null:
		_setup_damage_model(Fleet.flagship())
	return damage_model


## 损伤快照（DamageModel.summary，键见该函数注释）
func damage_summary() -> Dictionary:
	return get_damage_model().summary()


## 损管令：auto 均衡 / fire 救火 / flood 戽水 / fight 迎敌。不认识的令返回 false，原令不变。
func set_damage_control(mode: String) -> bool:
	return get_damage_model().set_mode(mode)


func damage_control_mode() -> String:
	return get_damage_model().mode


## 机动乘数：speed 乘在走力上、turn 乘在转向上；yaw_drift 是舵失灵时满速下每秒自偏的弧度；gear_cap 是帆装还挂得起几档
func maneuver_factors() -> Dictionary:
	var dm := get_damage_model()
	return {"speed": dm.speed_factor(), "turn": dm.turn_factor(), "yaw_drift": dm.yaw_drift(), "gear_cap": dm.gear_cap()}


## 给 ManeuverModel.step 的 mods（lane combat02 的键：sail / hull / rudder / yaw_drift / gear_cap）。
## 海战里旗舰归 WorldMap 按机动模型走，它先取这一份，损伤只在那边乘一次；Ship 自己的旧式航行只在没建海况时用 maneuver_factors。
func maneuver_mods() -> Dictionary:
	return get_damage_model().maneuver_mods()


## 火力乘数：reload 装填时长倍数（≥1）、volley 一轮放得出几成、spread 散布倍数（≥1）、port / starboard 左右舷此刻打不打得出去
func fire_factors() -> Dictionary:
	var dm := get_damage_model()
	return {"reload": dm.reload_factor(), "volley": dm.volley_factor(), "spread": dm.spread_factor(),
		"port": dm.side_ready(-1), "starboard": dm.side_ready(1)}


## 接舷能上的人（去掉正在救火、戽水、以橹代舵的）
func boarding_crew() -> int:
	return get_damage_model().boarding_crew()


func _setup_damage_model(fs: Dictionary) -> void:
	var type_id := str(fs.get("type", ""))
	damage_model = _DamageModel.new()
	damage_model.setup(type_id, Fleet.ship_def(type_id), Fleet.ship_crew(0), hull_hp, max_hp)


## 船体掉 amount：hull_hp 与舰队账（旗舰 durability）同扣，见底就沉。中弹、火烧、爆燃、灌沉都走这里。
func _hull_loss(amount: float) -> void:
	if amount <= 0.0 or hull_hp <= 0:
		return
	var take := minf(amount, hull_hp)
	hull_hp -= take
	Fleet.damage_fleet(take)
	if damage_model != null:
		damage_model.set_hull(hull_hp)
	if hull_hp <= 0:
		hull_hp = 0
		_sink_ship()


## 伤亡记进舰队（Fleet.lose_crew_random 先扣旗舰，每船至少留 1 人），损伤模型跟着对齐旗舰现有人数
func _lose_crew(n: int) -> void:
	if n <= 0:
		return
	Fleet.lose_crew_random(n)
	if damage_model != null:
		damage_model.set_crew(Fleet.ship_crew(0))


## 浸水、失火、损管逐帧推进：火烧船体、火场伤亡、灌沉或倾覆都在这里落账
func _step_damage(delta: float) -> void:
	var dm := get_damage_model()
	dm.set_crew(Fleet.ship_crew(0))  # 接舷白刃等别处减员之后对齐
	var st: Dictionary = dm.step(delta, {"wind": wind_strength, "heel": _wind_heel(), "rain": _raining()})
	_lose_crew(int(st.get("crew", 0)))
	_hull_loss(float(st.get("hull", 0.0)))
	if hull_hp > 0 and str(st.get("founder", "")) != "":
		# 灌沉 / 倾覆：船体余量一并记损，沉船照走 _sink_ship（WorldMap 败局结算）
		_hull_loss(hull_hp)
	# 帆装打坏以后挂不起的那档落下来，HUD 上的「满帆 / 半帆」才对得上
	sail_gear = mini(sail_gear, dm.gear_cap())
	fire_level = clampf(dm.fire_total(), 0.0, 1.0)
	immobile = dm.is_immobile()
	_emit_damage_events(st.get("events", []))


## 风压横倾（度，右倾为正）：横风满帆约 7 度，收帆为 0；灌了水的船由 FloodFire 再除以剩余稳性
func _wind_heel() -> float:
	var cross := Vector2.RIGHT.rotated(rotation).dot(wind_vector)
	return 7.0 * (wind_strength / 80.0) * (float(sail_gear) / 2.0) * cross


func _raining() -> bool:
	var parent := get_parent()
	return parent != null and parent.get("is_storm") == true


## 命中落点（本船坐标，y 负为艏）。hit 带 at（全局坐标）就用它；否则找此刻贴着船身、不是自己打出去的那颗弹——
## Cannonball 在 body_entered 里当帧调 take_damage，弹还在树上、就在接触点。都没有返回 null，DamageModel 随机落点。
func _impact_local(hit: Dictionary) -> Variant:
	if hit.get("at") is Vector2:
		return to_local(hit["at"])
	var parent := get_parent()
	if parent == null:
		return null
	var best: Node2D = null
	var best_d := IMPACT_SCAN
	for c in parent.get_children():
		var a := c as Area2D
		if a == null or a.get("shooter") == self or a.get("direction") == null:
			continue
		var d := a.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = a
	return null if best == null else to_local(best.global_position)


func _emit_damage_events(events: Array) -> void:
	for e in events:
		var info: Dictionary = e
		var kind := str(info.get("kind", ""))
		damage_event.emit(kind, info)
		if kind in NOTE_KINDS or (kind == "casualties" and int(info.get("n", 0)) >= 3):
			_note(str(info.get("text", "")), int(info.get("severity", 1)))


func _note(text: String, severity: int) -> void:
	if text == "":
		return
	if _note_queue.size() >= NOTE_QUEUE_MAX:
		_note_queue.pop_front()
	_note_queue.append([text, severity])


## 飘字一条一条出，免得同一发弹的几件事叠成一团
func _pump_notes(delta: float) -> void:
	_note_t -= delta
	if _note_t > 0.0 or _note_queue.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		_note_queue.clear()
		return
	if _note_scene == null:
		_note_scene = load("res://scenes/FloatingText.tscn") as PackedScene
	if _note_scene == null:
		_note_queue.clear()
		return
	_note_t = NOTE_GAP
	var item: Array = _note_queue.pop_front()
	var ft := _note_scene.instantiate() as Label
	if ft == null:
		return
	ft.text = str(item[0])
	ft.position = position + NOTE_AT
	parent.add_child(ft)
	ft.add_theme_font_size_override("font_size", 18)
	ft.add_theme_color_override("font_color", _note_color(int(item[1])))


func _note_color(severity: int) -> Color:
	if severity <= 0:
		return UiTheme.MOSS
	if severity == 1:
		return UiTheme.HONEY
	return UiTheme.CINNABAR


func _style_damage_tag() -> void:
	if damage_tag == null:
		return
	damage_tag.add_theme_font_override("font", UiTheme.font())
	damage_tag.add_theme_font_size_override("font_size", 17)
	damage_tag.add_theme_color_override("font_color", UiTheme.HONEY)
	damage_tag.add_theme_color_override("font_outline_color", Color(0.07, 0.04, 0.02, 1))
	damage_tag.add_theme_constant_override("outline_size", 4)
	damage_tag.visible = false


## 损伤观感：倾侧（船宽压扁、往低舷偏一点）、进水压暗、船身三段火烟、焦帆与舀水（CombatFx）、船上方短注、飘字
func _update_damage_visuals(delta: float) -> void:
	var dm := get_damage_model()
	var heel := deg_to_rad(clampf(dm.list_deg(), -60.0, 60.0))
	sprite.scale = Vector2(_sprite_base_scale.x * (1.0 - 0.35 * absf(sin(heel))), _sprite_base_scale.y)
	sprite.position.x = signf(heel) * 10.0 * absf(sin(heel))
	var f := dm.flood_frac()
	sprite.self_modulate = Color(1.0 - 0.3 * f, 1.0 - 0.25 * f, 1.0 - 0.1 * f)
	if damage_fx != null:
		for z in FIRE_FX:
			var p := damage_fx.get_node_or_null(str(FIRE_FX[z])) as CPUParticles2D
			if p == null:
				continue
			var i := dm.zone_fire(z)
			p.emitting = i >= 0.03
			if p.emitting:
				p.scale_amount_max = FIRE_PUFF_MIN + FIRE_PUFF_GAIN * i
				p.gravity = wind_vector * wind_strength * 0.35
	_sync_combat_fx(dm)
	if damage_tag != null:
		_tag_t -= delta
		if _tag_t <= 0.0:
			_tag_t = TAG_REFRESH
			var line := dm.status_line() if show_damage_tag else ""
			if damage_tag.text != line:
				damage_tag.text = line
				damage_tag.reset_size()
			damage_tag.visible = line != ""
		if damage_tag.visible:
			damage_tag.global_position = global_position + Vector2(-damage_tag.size.x * 0.5, -TAG_RISE)
	_pump_notes(delta)


## 焦帆、舀水交给观感线（CombatFx.set_fire / set_flood）：篷帆火势直接当火级；进水级 = 渗漏起步 0.15，
## 按舱水离沉没线（储备浮力）走了几成往上加，到线为 1（CombatFx 那边 1/3 两舷舀水、2/3 甲板漫水）。级数变够 FX_STEP 才重调。
func _sync_combat_fx(dm: _DamageModel) -> void:
	var rig := dm.zone_fire("rig")
	if absf(rig - _fx_fire_lv) >= FX_STEP or (rig > 0.0) != (_fx_fire_lv > 0.0):
		_fx_fire_lv = rig
		_CombatFx.set_fire(self, rig, wind_vector * clampf(wind_strength / 150.0, 0.0, 1.0))
	var fl := 0.0
	if dm.flood_frac() > 0.0 or dm.ff.open_leaks() > 0:
		fl = clampf(0.15 + 0.85 * dm.flood_frac() / maxf(0.05, dm.ff.reserve_now()), 0.15, 1.0)
	if absf(fl - _fx_flood_lv) >= FX_STEP or (fl > 0.0) != (_fx_flood_lv > 0.0):
		_fx_flood_lv = fl
		_CombatFx.set_flood(self, fl)
