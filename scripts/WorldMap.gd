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
const _SeaAtmosphere := preload("res://scripts/combat/SeaAtmosphere.gd")
const _CAM_PLAQUE_CTL := preload("res://scripts/worldmap_cam_plaque.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")

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
## 开战刷船距离（09-28 验收 P02 返修，09-30 合并并入本地线；w19-g13 随镜头拉远重定；w20-b9 按 3D 船身重核）：
## 镜头 zoom 1.5 时可见约 850×480、半高 240，只好收到 210—235，比船长（约 280 px）还短，两船一开场就叠在一起。
## w19-g13 镜头拉到 0.5（Ship.CAM_ZOOM_REST，半高 720），刷船放到 560—600（两倍船长判据）。
## w20-b9 复量（tools/w20b9_spawn_gauge.gd）：ShipHull3D 视口 832 × VIS_SCALE 0.78 ≈ 649 世界 px 包围盒、
## 旗舰 / 敌船同型；开局镜头就位 zoom=CAM_ZOOM_REST 0.5（spawn 时船速还没进满航 0.42），屏上敌我不可交须
## dist × 0.5 ≥ (325 + 325)/2 = 325 屏 px → 刷船下限 ≥ 650；取 700 留 50 余量，zoom 0.5 屏上 350 ≥ 325，
## REST / 满航同图皆不交（满帆 0.42 屏上 294 仍 ≥ 291）。上限收 720 = zoom 0.5 半高（zoom 0.42 857 同），
## 任何角度刷出的船心仍在画内（story_check _w20b9_spawn_bbox_check 对账；反向变异 210 / 560 各红）。
const COMBAT_SPAWN_DIST_MIN := 700.0
const COMBAT_SPAWN_DIST_MAX := 720.0
## 镜头内等于已进 800 射程；不延迟会被 9 门齐射秒掉开局小艍
const COMBAT_FIRE_DELAY := 3.5
## 两艘满编 9 门 × 25 伤 = 450，开局 120 耐久一波沉。封顶 2 门：
## 第一轮约 100，停着打第二轮才沉，B 来得及按。
const COMBAT_CANNON_CAP := 2

# ── V0928-9 海战镜头竖向让位顶匾（w25-j1）──
## w22-h1 复量（tools/ 仓外 v0928_9_camera_gauge，zoom 0.5 / 刷船 700—720 / 30 秒）：哨船场接舷贴近时
## 敌船绕到本船正上方，船心落进顶匾 TideBar（屏矩形 (16,8)—(1264,80)）11.66%—17.99%（h1 / 本片基线两测），
## 海寇场 0—5.44%。只因镜头居中钉屏中：贴舷 140 屏 px + 敌船椭圆兜圈上冲 300+，(80−360)/0.5 = −560
## 世界 px 必挨压。修法（镜头侧，不动射程 800 / 开炮 760 / 接舷 140 / 刷船 700—720；也不藏顶匾骗指标）：
## 敌船贴身时给旗舰 Camera2D 一份「荣誉 offset」offset.y = −dy 屏 px，镜头中心自屏中向下让，
## 顶匾下沿到屏底这段可用区的中心成为镜头中心；本船世界坐标一根毫毛不动，航行 / 接舷 / 弹道全照旧。
## 量值在 scripts/Ship.gd `CAM_PLAQUE_DY`；让位口径对账见 scripts/worldmap_cam_plaque.gd，
## story_check `_w25j1_cam_plaque_check` 五断言钉住（dy = 0 沿用居中、不谋求让位，按其口径仍绿）。
## 战斗中恒开：打这一战就是在战术图上布警，多让 40 屏 px 上方的海不算损失；gate 触发会让
## 敌船「冲到顶匾才给位」，镜头与上扫不同步照样挨、并擦出底沿假出画（w25-j1 全参扫描见 Verify）。

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
## 末船接舷夺下 / 本船失守后等题签播完再收战：挡住 _process 的 win{} 抢先（await 即便 headless 也会让出一帧）
var _finishing_boarded: bool = false
## 最近一场白刃的 MeleeResolve 结果（_board_enemy 写；探针对伤亡账用，空 = 本场还没打过白刃 / 敌降免白刃）
var _last_melee: Dictionary = {}
## combat12：敌船 left_battle(escaped) 计数（HUD / 探针读）；收战下场明细另记 _enemy_fates
var _enemies_escaped: int = 0
## combat12：敌船下场账 instance_id → {type, fate}（fate 取 CombatLetterbox.FATE_VERB 的键：struck / boarded / sunk / fled）。
## 遁走在 left_battle、夺船在 _board_enemy 当场记，其余离树时按船体记沉；收战时并进 win data.fates，
## 题签（fates_of）与 SeaChart 分账（半赏只给「一艘没沉没夺没降、只是遁走」）都按它算——士气收场的 morale_verdict 只看在场的船，
## 先沉一艘、后遁一艘也报 enemy_fled，不能单凭它给半赏。
var _enemy_fates: Dictionary = {}
## lane fx3：本场接舷夺来入册的船（Fleet.ships 里那一格的引用，不凭船名认——同名「快船」可能早就在册）；
## 开战时的水粮账。弃战 / 两散收战时并进 data.prizes / data.stores_moved，供 SeaChart 交代夺船下落。
var _prizes: Array = []
var _stores_at_start: Vector2i = Vector2i.ZERO
## lane w53-2：本队折损账（收战并进 data.losses，出战墨边副题写「折水手 N 人，颠落舱面货 N 件」）——
## 开战时全队水手、夺船随船并入的水手（不算折损的负数）、开战时各货件数（中弹颠落舱面货只在战中发生，收战差额即颠落的）
var _crew_at_start: int = 0
var _prize_crew: int = 0
var _cargo_at_start: Dictionary = {}
## combat12：开战经过秒数；到 battle_limit_s（combat_phases.json thresholds，缺省 BATTLE_LIMIT_S）两散 parted
var _battle_elapsed_s: float = 0.0
var _battle_limit_s: float = 300.0
const BATTLE_LIMIT_S := 300.0
const _PHASES_PATH := "res://data/combat_phases.json"
## 号令面板（下令那一刻的浮字取号令中文名：CombatOrdersPanel.notice_for）
const _CombatOrders := preload("res://scripts/ui/CombatOrdersPanel.gd")
## lane w53-2：甩脱（阶段图 t_outsailed → player_fled，legacy flee{flee_ok, shook_off}）——还在追打的敌船（活着、没降、没在脱离）
## 全在 thresholds.escape_bu（160 步 = 1280 px，同溃逃一方逃出的距离）以外、连续满 thresholds.shake_off_s 秒，本船即算甩开了追船，
## 按脱战收场（SeaChart 走弃战成功一支：绕些路、札记「转舵抢上风头，把追船甩在后面」）；按 B 弃战时追船已尽在外也不再掷骰。
## 原先拉开了也只能空等 300 秒限时两散（敌船出 2500 px 即休眠不动，顶匾一直「存活 N」）。开战时读阶段表，读不到用这两个常量
const ESCAPE_PX := 1280.0
const SHAKE_OFF_S := 6.0
var _escape_px: float = ESCAPE_PX
var _shake_off_s: float = SHAKE_OFF_S
var _outsailed_s: float = 0.0
## lane w53-17（一条一个开关）： gale_parting 大风两散（t_gale）· morale_carry 战后士气带回 ·
## 火长预报 _gale_warn_pushed 出过一次。_morale_before 是开战那一刻的 Fleet.morale
## （morale_carry 收战时折算写回用；开关关着一字不写）
var _gale := false
var _morale_before := 0
var _gale_warn_pushed := false

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
	_setup_coastline()
	var pb: Dictionary = GameManager.pending_battle
	if pb.get("battle", false):
		_setup_combat(pb)
		# lane w53-17（一期「大风两散」）：雷暴大风场不开战——combat_phases.json t_gale，
		# 「风到七级以上不能战」。_setup_combat 全落到位再收（士气挂件 / 墨边 / 海况都要先接上，
		# 收战路径与限时两散同一支：flee{flee_ok, parted} 另带 gale=true 供 w53-16 出文字）。
		if _gale:
			_battle_exit("flee", {"flee_ok": true, "parted": true, "gale": true})
	else:
		# 防御：孤儿场景被直接打开时立即退出，不残留
		_battle_exit("flee", {})

func _process(delta: float) -> void:
	if not ship: return

	_process_weather_and_time(delta)
	if combat_mode:
		rain_particles.global_position = ship.global_position

	# V0928-9：敌船贴舷时镜头给顶匾让位（只写 honor offset，本船世界坐标不动）
	if combat_mode and not resolved:
		_cam_dy_apply()
	elif is_instance_valid(ship):
		ship.set("_cam_plaque_dy", 0.0)

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

	# lane w53-2：甩脱（阶段图 t_outsailed）——追打的敌船全在 escape_bu 外满 shake_off_s 秒即按脱战收场；钩住白刃、末船夺下等题签时不计
	if combat_mode and not resolved and not boarding and not _finishing_boarded:
		var pu := _pursuit()
		if int(pu["n"]) > 0 and int(pu["near"]) == 0:
			_outsailed_s += delta
			if _outsailed_s >= _shake_off_s:
				_battle_exit("flee", {"flee_ok": true, "shook_off": true})
		else:
			_outsailed_s = 0.0

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
	_check_gale_warn()
	if ship.hull_hp > 0.0:
		_steer_flagship(delta)


## lane w53-17（二期「火长提前报风」）：crew_role_effects 开着、火长在册、本场还没报过——
## 按当前风场推演「若照这个势头走，火长提前（GALE_WARN_S × 等级）秒那一拍的骤风顶头已迸线」，
## 即出一次浮字。只预报、不改风；预报出过后不再重报（收战的「两散」那行照旧）。
func _check_gale_warn() -> void:
	if _gale_warn_pushed or not _Switches.on("crew_role_effects") or not _Switches.on("gale_parting"):
		return
	var warn_s: float = _SeaState.GALE_WARN_S * float(Crew.level_of("huozhang"))
	if warn_s <= 0.0:
		return
	# 火长眼里的「长势」推演：mean 照半节 / 秒往前推 warn_s 秒（探针「刮大风」同此一手），那一拍的骤风顶头
	# 迸过七级作战上限（WIND_CAP）即提前报一次。现下已迸的（风暴已在头上）也报——声是出给玩家的，
	# 「两散」的收场照旧他走。只预报、不改风；报过不再重报。
	var mean_now: float = _sea.wind_mean
	var mean_then: float = mean_now + warn_s * 0.5
	if _sea.storm_peak() >= _SeaState.WIND_CAP or mean_then * (1.0 + _SeaState.GUST_AMP) * _SeaState.GALE_HEADROOM >= _SeaState.WIND_CAP:
		_gale_warn_pushed = true
		_show_combat_notice("火长望见天色不对：风要转了")


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
## 谁先抛钩谁作攻方（lane w53-2，combat_phases.json 转移 t_deck_taken / t_deck_lost / t_deck_held）：敌船自己抛钩接上来
## （PirateShip.boarding_initiator）时敌攻我守——守住了（击退 / 砍缆）敌船退开、战斗照打；守不住（敌夺舵 / 我降幡）即失船面
## player_overrun：敌搬货走人，以 lose{overrun} 收战（SeaChart 走败局非沉船一支：货损二成五、札记白刃不利）。
## 末船夺下：headless 当帧 _battle_exit(boarded=true)（story / realism 探针同帧取 boarded，只等 30 帧）；
## 窗口下等「夺船」/「失守」题签停满 T_HOLD、淡出再收战，其间 _finishing_boarded 挡住 _process 的 win{} / 限时两散、B 键弃战与士气簿裁决。
func _board_enemy(enemy: Node2D) -> void:
	if not is_instance_valid(enemy):
		return
	# 敌船先抛的钩：敌作攻方（放钩时 PirateShip 自己清掉这一标记，开头先记下）
	var enemy_first: bool = enemy.get("boarding_initiator") == true
	boarding = true
	boarding_target = enemy
	_last_melee = {}
	_AUDIO.combat_board(self)
	enemy.set("grappled", true)  # 敌船停航停炮
	_SeaAtmosphere.boarding_drama(self, ship, enemy)  # lane atmos：接舷镜头 / 钩缆 / 翻白

	# 钩索题签 + 轻震；窗口下停 0.42 s 再分胜负（combat12：combat11 把这一拍并进了同帧，begin 相位一帧没画就被 resolve 顶掉，
	# wire / vfx 截图门禁的接舷开场张截不到）。headless 不停：末船夺下仍当帧收战。
	# 计时器挂在本节点下（lane gd17）：这 0.42 s 里 WorldMap 被释放，挂起的协程随信号源丢弃，不泄漏。
	var stage: CanvasLayer = _BoardingStage.begin(self, ship, enemy, _CombatFx.board_begin_subtitle())
	_CombatFx.punch_camera(ship, 5.0)
	if not _Kit.is_headless():
		var pause := Timer.new()
		pause.one_shot = true
		pause.process_mode = Node.PROCESS_MODE_ALWAYS
		pause.wait_time = 0.42
		add_child(pause)
		pause.start()
		await pause.timeout
		pause.queue_free()
	if resolved or not is_instance_valid(enemy) or not _boarding_target_valid():
		boarding = false
		boarding_target = null
		return

	var detail := ""
	var notice := ""
	var do_capture := false

	# 敌已降幡：接舷即得，免白刃（降了的船不会自己抛钩，这一支只在本队先钩时走）。降幡两条来路都认（lane w53-2）：
	# 士气簿降了（yields_to_boarding），或敌将自己降了、船节点 struck 已立（喊话劝降得手走 PirateShip.strike_colours，士气簿不知道）——
	# 只看簿的话，竖着降幡、落帆停射的船一接舷照打一场满员白刃，还能把本队击退
	var yield_sheet = _morale.sheet_of(enemy) if _morale != null else null
	var yielded: bool = enemy.get("struck") == true or (yield_sheet != null and yield_sheet.yields_to_boarding())
	if not enemy_first and yielded:
		do_capture = true
		notice = _CombatFx.board_win_note(_node_str(enemy, "ship_name", "敌船"))
		detail = "敌船降幡，接舷收船"
	else:
		var r := _melee_resolve(enemy, enemy_first)
		_last_melee = r
		# legacy 按攻方算：win = 攻方占了对面甲板（夺船 / 对面降幡）
		var legacy := str(r.get("legacy", "lose"))
		# 攻方折 att_dead、守方折 def_dead：本队先钩本队是攻方，敌船先钩本队是守方
		var our_dead := int(r.get("def_dead" if enemy_first else "att_dead", 0))
		Fleet.lose_crew_random(our_dead)
		# 士气增减也按攻方给；本队守的那一路反过来记——攻方挫多少、守方振多少
		var morale_delta := int(r.get("att_morale_delta", 0))
		Fleet.morale = clampi(Fleet.morale + (-morale_delta if enemy_first else morale_delta), 0, Fleet.MORALE_MAX)
		# 敌船那一方的阵亡记在敌船上（lane w53-2）：白刃没拿下、敌船留在场上时，题签里「敌伤 N」那些人真的少了，
		# 下一回接舷、敌将与士气簿按剩下的人算；不记的话跳帮再败几回，敌船人数一个不少
		_enemy_lose_crew(enemy, int(r.get("att_dead" if enemy_first else "def_dead", 0)))
		detail = (_MeleeResolve.defender_summary(r) if enemy_first else str(r.get("summary", ""))).strip_edges()
		if legacy == "win" and enemy_first:
			# 失船面：敌占了本船甲板、搬货走人。题签「失守」停满再收战（headless 起不来题签，浮字兜底、当帧收战）
			_finishing_boarded = true
			var lost_stage: CanvasLayer = _BoardingStage.resolve(self, "overrun", detail)
			if lost_stage != null:
				await _await_boarding_fx(lost_stage)
			else:
				_show_combat_notice(detail)
			_battle_exit("lose", {"overrun": true})
			return
		if legacy == "win":
			do_capture = true
			GameState.martial = mini(100, GameState.martial + 1)
		else:
			# 落空 / 击退 / 脱钩：解开钩缆，不把敌船留在 grappled（敌船先钩被我击退的，PirateShip 放钩时记「跳帮受挫」）
			if is_instance_valid(enemy):
				enemy.set("grappled", false)
			boarding = false
			boarding_target = null
			var msg2 := detail if detail != "" else _CombatFx.board_lose_note(our_dead)
			# 题签：本队先钩照旧「脱钩」；敌船先钩写守方眼里的了局（击退 / 脱钩）
			var lose_stage: CanvasLayer = _BoardingStage.resolve(
				self, str(r.get("outcome", "lose")) if enemy_first else "lose", msg2)
			if lose_stage != null:
				stage = lose_stage
			else:
				_show_combat_notice(msg2)
			await _await_boarding_fx(stage)
			return

	if do_capture:
		var type_id := _node_str(enemy, "ship_type", "pirate_boat")
		var ship_name := _node_str(enemy, "ship_name", "")
		var hull_max := float(enemy.get("hull_max")) if enemy.get("hull_max") != null else 0.0
		var hull_frac := float(enemy.get("hull_hp")) / hull_max if hull_max > 0.0 else 1.0
		var ok := Fleet.add_ship(type_id, ship_name)
		if ok:
			Fleet.settle_prize(Fleet.ships.size() - 1, hull_frac)
		var taken: String = str(Fleet.ships[Fleet.ships.size() - 1].get("name", "敌船")) if ok else "敌船"
		if ok:
			_prizes.append(Fleet.ships[Fleet.ships.size() - 1])
			_prize_crew += int(Fleet.ships[Fleet.ships.size() - 1].get("crew", 0))
		if notice == "":
			notice = _CombatFx.board_win_note(taken)
		if detail == "":
			detail = notice
		var resolved_stage: CanvasLayer = _BoardingStage.resolve(self, "win", _CombatFx.board_win_subtitle(detail, taken))
		if resolved_stage != null:
			stage = resolved_stage
		else:
			# 题签起不来（headless / 不在树）才出浮字兜底：有题签就不出浮字，同一件事不在屏上说两遍（白刃失利同）。
			# crew 线 09-28 9e35254 定的，09-30 合并 a356c16 按本地线落地时丢了（fx8 只补回等题签），lane w19-g1 补回
			_show_combat_notice(notice)
		_CombatFx.hitstop(self, 0.09, 0.16)
		# 下场先记（降了的收船记受降），再清血量：离树时按船体记沉会把夺来的船记成击沉
		_note_fate(enemy, "struck" if yielded else "boarded")
		# 清血量再释放：避免 queue_free 后仍被 _enemies_alive 数到
		enemy.set("hull_hp", 0.0)
		enemy.queue_free()
		boarding = false
		boarding_target = null
		if _enemies_alive() == 0:
			# 末一艘夺下：headless 当帧收战（不 await，探针 30 帧内要收到 boarded）；窗口下等「夺船」题签停满 T_HOLD、
			# 淡出后再出战（crew 线 09-28 实机验收 9e35254：当帧出战题签只留 1 帧；09-30 合并按本地线落地时丢了，lane fx8 补回）
			_finishing_boarded = true
			if not _Kit.is_headless():
				await _await_boarding_fx(stage)
			_battle_exit("win", {"boarded": true})
		else:
			await _await_boarding_fx(stage)


## 白刃一场（MeleeResolve.resolve，钩缆已挂牢 hooked）：本队按 Fleet、敌按船节点、态势按两船节点（攻方看守方）；
## 有士气簿则本队士气换 melee_factor（没挂士气簿时本队先钩那一路同 MeleeResolve.from_battle）。
## enemy_first：敌船先抛的钩，敌作攻方、本队作守方——结果里 att_* 是敌船的、def_* 是本队的，记事里「敌 / 我」随 is_player 换位
func _melee_resolve(enemy: Node2D, enemy_first := false) -> Dictionary:
	var sides := _melee_sides(enemy, enemy_first)
	return _MeleeResolve.resolve(sides[0], sides[1], sides[2])


## 白刃两方与态势 [攻方, 守方, ctx]（_melee_resolve 用，探针验号令加力）。本队那一方的将领系数再乘号令面板的「白刃」效力：
## 备接舷聚齐了执钩拒的甲士加力，抢风 / 专力装填把甲士抽去就减；攻守都算——敌船先抛钩上来，舷边拒着的也是这些人（lane w53-2）
func _melee_sides(enemy: Node2D, enemy_first := false) -> Array:
	var us: Dictionary = _MeleeResolve.side_from_fleet(Fleet)
	var ps = _morale.player_sheet() if _morale != null else null
	if ps != null:
		us["morale"] = clampi(int(round(ps.melee_factor() * 100.0)), 0, 100)
	us["captain"] = float(us.get("captain", 1.0)) * float(order_mods().get("board_bonus", 1.0))
	var foe: Dictionary = _MeleeResolve.side_from_enemy(enemy)
	var att: Dictionary = foe if enemy_first else us
	var def: Dictionary = us if enemy_first else foe
	var ctx: Dictionary = _MeleeResolve.approach_from_nodes(
		enemy if enemy_first else ship, ship if enemy_first else enemy, Vector2.ZERO, -1.0,
		str(att.get("type", "")), str(def.get("type", ""))
	)
	ctx["hooked"] = true
	# 借改 w53-17 的 WorldMap，一行只读：守方 = 本队时把号令面板的「砍钩」效力给到 MeleeResolve 的守方砍缆率
	# （开关 order_cut_grapple 关掉时面板 cut_mul 恒 1.0，本行照旧与 wave53 开工前一致）
	if enemy_first:
		ctx["def_cut_mul"] = float(order_mods().get("cut_mul", 1.0))
	return [att, def, ctx]


## 敌船白刃折损 n 人（只记阵亡 / 重伤不起的；轻伤战后归队，同本队只扣 att_dead 的口径），水手不减到负数
func _enemy_lose_crew(enemy: Node, n: int) -> void:
	if n <= 0 or enemy == null or not is_instance_valid(enemy):
		return
	enemy.set("crew", maxi(0, int(_node_float(enemy, "crew")) - n))


## 战斗通知浮字（lane w53-2 改）：一条一行叠在本船下方、出战墨边与状态条之上，居中，最多 NOTICE_MAX 行——新的在最下，旧的往上让，
## 每行各自停 NOTICE_HOLD 秒再淡 NOTICE_FADE 秒（各管各的补间，后来的不被前一条的淡出带走）。
## 原先只有一枚 Label：锚在屏心、字从屏心往右写，正压在本船帆上；同一两帧里接踵的几条（号令、敌将改打法、降幡、士气纪实）只剩最后一条。
## _notice 指最新一行（探针读它的字）
const NOTICE_MAX := 3
const NOTICE_HOLD := 1.5
const NOTICE_FADE := 1.0
const NOTICE_GAP := 12.0
## 出战 / 入战墨边下边占画布高的比例（同 CombatLetterbox.BAR_FRAC）：浮字条底边在它之上，开战墨边还没揭开时出的字不被压住
const NOTICE_BAR_FRAC := 0.125
var _notice: Label = null
var _notice_box: VBoxContainer = null
func _show_combat_notice(text: String) -> void:
	if not is_instance_valid(_notice_box):
		_notice_box = VBoxContainer.new()
		_notice_box.name = "NoticeStack"
		_notice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_notice_box.alignment = BoxContainer.ALIGNMENT_END
		_notice_box.add_theme_constant_override("separation", 0)
		$CanvasLayer.add_child(_notice_box)
		if not get_viewport().size_changed.is_connected(_layout_notices):
			get_viewport().size_changed.connect(_layout_notices)
	# 同一句接着来（敌船远遁，PirateShip 与本场各报一遍）不另起一行，只把那一行重新停满
	if is_instance_valid(_notice) and _notice.visible and _notice.text == text:
		_hold_notice(_notice)
		return
	for c in _notice_box.get_children():
		if not (c as CanvasItem).visible:
			_notice_box.remove_child(c)
			c.queue_free()
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", UiTheme.font())
	lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_HEAD)
	lbl.add_theme_color_override("font_color", UiTheme.GOLD)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = text
	_notice_box.add_child(lbl)
	while _notice_box.get_child_count() > NOTICE_MAX:
		var old := _notice_box.get_child(0)
		_notice_box.remove_child(old)
		old.queue_free()
	_notice = lbl
	_layout_notices()
	_hold_notice(lbl)


## 一行停满 NOTICE_HOLD 秒再淡出、藏起（补间挂在这一行上，行被挤掉释放时随之作废）；重来一遍先收掉旧的
func _hold_notice(lbl: Label) -> void:
	if lbl.has_meta(&"nk1_fade"):
		var old = lbl.get_meta(&"nk1_fade")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	lbl.visible = true
	lbl.modulate.a = 1.0
	var tw := lbl.create_tween()
	tw.tween_interval(NOTICE_HOLD)
	tw.tween_property(lbl, "modulate:a", 0.0, NOTICE_FADE)
	tw.tween_callback(lbl.hide)
	lbl.set_meta(&"nk1_fade", tw)


## 浮字条摆位：画布居中，左让号令面板、右让小地图；底边在出战墨边下边与状态条之上（量得到它们就按实的让，量不到按墨边比例）
func _layout_notices() -> void:
	if not is_instance_valid(_notice_box):
		return
	var cv := get_viewport().get_visible_rect().size
	var bottom := cv.y * (1.0 - NOTICE_BAR_FRAC) - NOTICE_GAP
	var left := 0.0
	var right := cv.x
	for n in get_children():
		if n.is_in_group("nk1_combat_status"):
			var strip = n.get("_strip")
			if strip is Control and (strip as Control).is_visible_in_tree() and (strip as Control).size.y > 0.0:
				var sr := (strip as Control).get_global_rect()
				if sr.position.y > cv.y * 0.5:
					bottom = minf(bottom, sr.position.y - NOTICE_GAP)
		elif n.is_in_group("nk1_combat_orders"):
			var card = n.get("_card")
			if card is Control and (card as Control).is_visible_in_tree() and (card as Control).size.x > 0.0:
				left = maxf(left, (card as Control).get_global_rect().end.x + NOTICE_GAP)
	var mini := get_node_or_null("CanvasLayer/HUD/MinimapPanel") as Control
	if mini != null and mini.is_visible_in_tree() and mini.size.x > 0.0:
		right = minf(right, mini.get_global_rect().position.x - NOTICE_GAP)
	var cx := cv.x * 0.5
	var ms := _notice_box.get_combined_minimum_size()
	var w := maxf(ms.x, 2.0 * maxf(0.0, minf(cx - left, right - cx)))
	_notice_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_notice_box.size = Vector2(w, ms.y)
	_notice_box.position = Vector2(cx - w * 0.5, bottom - ms.y)


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
	_prizes = []
	_stores_at_start = Vector2i(Fleet.water, Fleet.food)
	_crew_at_start = Fleet.total_crew()
	_prize_crew = 0
	_cargo_at_start = _cargo_counts()
	_battle_elapsed_s = 0.0
	_battle_limit_s = _phases_battle_limit_s()
	_outsailed_s = 0.0
	_morale_before = Fleet.morale
	_gale_warn_pushed = false
	var esc := _phases_escape()
	_escape_px = esc.x
	_shake_off_s = esc.y
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
	# V0928-9：开战先抚平可能残留的让位（上一战敌近时收战），再接新战
	if is_instance_valid(ship):
		ship.set("_cam_plaque_dy", 0.0)
	# combat11：士气挂件 + 号令/状态 UI
	_morale = _CombatMorale.attach(self)
	if _morale != null:
		_morale.verdict.connect(_on_morale_verdict)
		_morale.noted.connect(_on_morale_noted)
	_CombatShoreHook.mount_combat_ui(self, ship)
	# lane atmos：海面着色器驱动、航迹、敌我旗旒与轮廓、落水涟漪
	_SeaAtmosphere.attach(self, ship)


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
			if boarding or _finishing_boarded:
				return # 白刃已钩住不能逃；末艘已夺下、「夺船」题签在演，等它带 boarded 出战（crew 线 1fe334d）
			get_viewport().set_input_as_handled()
			# lane w53-2：甩脱机会随追船远近抬（_flee_chance）——近身只看船速，追打的敌船尽在 escape_bu 外（降了的、溃走的不追）必脱、不掷骰；
			# 原先照掷航速骰，敌船在一屏开外休眠不动也会「未能甩脱，被追上跳帮，货舱被夺」
			var chance := _flee_chance()
			var ok: bool = chance >= 1.0 or randf() < chance
			_battle_exit("flee", {"flee_ok": ok, "player_damage": player_damage})


## 玩家旗舰在战斗中沉没时由 Ship._sink_ship 调用（战斗期不切场景）
func _battle_player_sunk() -> void:
	_battle_exit("lose", {"sunk": true, "player_damage": player_damage})


## 士气簿裁决（敌尽降 / 遁、我方溃逃 / 降幡）即收战；末艘已夺下、「夺船」题签在演时不裁决——敌船已尽，那一场由 _board_enemy 带 boarded 收
func _on_morale_verdict(outcome: String, data: Dictionary) -> void:
	if _finishing_boarded:
		return
	_battle_exit(outcome, data)


## 战斗终结：发信号给 SeaChart 结算，随后释放本场景
func _battle_exit(outcome: String, data: Dictionary) -> void:
	if resolved:
		return
	resolved = true
	# 战损口径（09-30 合并并入 origin 那条）：_process 里每帧按在册船重算，退出这一拍再算一遍，
	# 让直接调进来的路径（story_check 的 _board_enemy 合成调用、夺船即胜）带的数也准。
	player_damage = combat_start_durability - _roster_durability()
	data["player_damage"] = player_damage
	_last_boarded = bool(data.get("boarded", false))
	if _last_boarded:
		data["boarded"] = true
	if outcome == "win" and not data.has("fates"):
		var fates := _battle_fates()
		if not fates.is_empty():
			data["fates"] = fates
	# lane w53-17（一期战后士气带回航程）：morale_carry 开着、士气簿活着——按末值折算写回 Fleet.morale，
	# 并带 data.morale_carry 供战后单子（w53-16）。SeaChart 旧账（赢 +5 / 输 −12）照旧在这条之后走。
	if _Switches.on("morale_carry") and _morale != null and is_instance_valid(_morale):
		var mc_sheet = _morale.player_sheet()
		if mc_sheet != null:
			var carried: int = mc_sheet.carry_to_voyage(_morale_before)
			Fleet.morale = carried
			data["morale_carry"] = carried
	# lane w19-g2：旗舰沉没（lose + sunk）同带夺船账——夺来的船不上战阵、仍在册，SeaChart 沉船句要交代它；
	# lane w53-14：我方降幡（lose + struck）、失守（lose + overrun）也带——交出的是舱货，夺来的船照旧在册
	if outcome != "win" and not _prizes.is_empty():
		_prize_ledger(data)
	# lane w53-2：本场折损（矢石、白刃死的水手，中弹颠落的舱面货）交给出战墨边副题——CombatLetterbox.loss_note 早留了这一格，没人填
	if combat_mode and not data.has("losses"):
		var losses := _battle_losses()
		if not losses.is_empty():
			data["losses"] = losses
	_AUDIO.combat_result(self, outcome)
	_CombatShoreHook.unmount_combat_ui(self)
	_try_letterbox_exit(outcome, data)
	_SeaState.clear_active(_sea)
	battle_finished.emit(outcome, data)
	queue_free()


## 本场折损 {crew: 折了几名水手, cargo: 颠落几件舱面货}，没有的键不写、全没有返回 {}。
## 水手按「开战时 + 夺船并入 − 此刻」算（夺来的船带的人不抵折损，也不让折损变负）；货按开战时各货件数逐货取少了的
func _battle_losses() -> Dictionary:
	var out := {}
	var crew_lost := _crew_at_start + _prize_crew - Fleet.total_crew()
	if crew_lost > 0:
		out["crew"] = crew_lost
	var now := _cargo_counts()
	var cargo_lost := 0
	for gid in _cargo_at_start:
		cargo_lost += maxi(0, int(_cargo_at_start[gid]) - int(now.get(gid, 0)))
	if cargo_lost > 0:
		out["cargo"] = cargo_lost
	return out


## 全队各货件数 {gid: 件}（Fleet.cargo 是各船合并的只读视图）
static func _cargo_counts() -> Dictionary:
	var out := {}
	var agg: Dictionary = Fleet.cargo
	for gid in agg:
		out[gid] = int((agg[gid] as Dictionary).get("qty", 0))
	return out


## lane fx3：夺船后弃战 / 两散的夺船账（w19-g2 起旗舰沉没也走这里）——只记收战这一拍仍在册的那几格（按引用认），水粮记本场实际增量
func _prize_ledger(data: Dictionary) -> void:
	var kept: Array = []
	for p in _prizes:
		for s in Fleet.ships:
			if is_same(s, p):
				kept.append({"name": str(s.get("name", "")), "type": str(s.get("type", ""))})
				break
	data["prizes"] = kept
	data["stores_moved"] = {"water": Fleet.water - _stores_at_start.x, "food": Fleet.food - _stores_at_start.y}


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


## 甩脱两数（lane w53-2）：x = thresholds.escape_bu.v × scale.px_per_bu（像素），y = thresholds.shake_off_s.v（秒）；读不到用 ESCAPE_PX / SHAKE_OFF_S
static func _phases_escape() -> Vector2:
	var out := Vector2(ESCAPE_PX, SHAKE_OFF_S)
	var f := FileAccess.open(_PHASES_PATH, FileAccess.READ)
	if f == null:
		return out
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return out
	var t = d.get("thresholds", {})
	var sc = d.get("scale", {})
	if t is Dictionary and sc is Dictionary:
		var eb = t.get("escape_bu", {}).get("v") if t.get("escape_bu") is Dictionary else null
		var px = sc.get("px_per_bu")
		if (eb is float or eb is int) and (px is float or px is int) and float(eb) * float(px) > 0.0:
			out.x = float(eb) * float(px)
		var so = t.get("shake_off_s", {}).get("v") if t.get("shake_off_s") is Dictionary else null
		if (so is float or so is int) and float(so) > 0.0:
			out.y = float(so)
	return out


## 追打的敌船（活着、没降、没在脱离）有几艘、其中几艘在 _escape_px 以内、最近一艘多远：{"n", "near", "nearest"}（没有追船 nearest 为 INF）。
## 降了的、溃走的不追，甩脱与否不看它们——那几艘归士气簿收场（受降 / 敌遁）
func _pursuit() -> Dictionary:
	var n := 0
	var near := 0
	var nearest := INF
	for child in get_children():
		if not _is_live_pirate(child) or child.get("struck") == true:
			continue
		var cap = child.get("captain")
		if cap != null and str(cap.get("state")) == "disengage":
			continue
		n += 1
		if is_instance_valid(ship):
			var d := (child as Node2D).position.distance_to(ship.position)
			nearest = minf(nearest, d)
			if d < _escape_px:
				near += 1
	return {"n": n, "near": near, "nearest": nearest}


## B 弃战的甩脱机会（lane w53-2，待拍板 13b「弃战越远越易脱」）：最近一艘追船在 FLEE_NEAR 以内只看船速（Voyage.flee_success_chance，
## 海图上遇盗逃走同一条），拉到 _escape_px（escape_bu）以外必脱，其间按距离线性抬到 1。
## 原先只看船速：一屏开外休眠的敌船照样「追上跳帮」；上一笔补了「尽在 escape_bu 外不掷骰」，1279 px 照掷、1281 px 必脱，中间没有过渡
const FLEE_NEAR := 400.0
func _flee_chance() -> float:
	var base := Voyage.flee_success_chance()
	var d := float(_pursuit()["nearest"])
	if d >= _escape_px:
		return 1.0
	return lerpf(base, 1.0, clampf((d - FLEE_NEAR) / maxf(1.0, _escape_px - FLEE_NEAR), 0.0, 1.0))


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
		_show_combat_notice("敌船抛钩咬舷")
	else:
		_show_combat_notice("敌船抛钩落空")
	if enemy != null:
		pass  # 占位：保留 enemy 形参供信号 bind


func _on_morale_noted(_who: Node, _kind: String, text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		_show_combat_notice(t)


## 号令面板 order_issued → 可选钩子（CombatShoreHook.mount_combat_ui 若发现本方法会自动连）。
## 浮字写号令的中文名（CombatOrdersPanel.notice_for：「号令：抢风」「撤令：抢风」「号令：专力装填」），不把内部 id 当字上屏
func _on_combat_order(order_id: String, payload: Dictionary = {}) -> void:
	var msg := _CombatOrders.notice_for(order_id.strip_edges(), payload)
	if msg != "":
		_show_combat_notice(msg)


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
	# lane w53-17（一期「大风两散」）：gale_parting 开关开着、SeaState 记了这场是雷暴大风——
	# combat_phases.json t_gale 落实：开战即收（收在 _ready 尾；须先过士气挂件等接线，逐项下来不退途）。
	_gale = _Switches.on("gale_parting") and _sea.gale
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


## V0928-9：让位每渲染帧步进（挂在 _process；已用 combat_mode / resolved 把门）。战斗中恒把让位
## 量值交给 Ship（Ship.CAM_PLAQUE_DY，屏 px 荣誉 offset）；收战 / 场景卸出由调用点写 0 抚平。
## 只写 ship._cam_plaque_dy 一个量：本船世界坐标、敌船、弹道全不碰，镜头由 Ship 实测按
## offset.y = −dy 与自震抵消后写入。
func _cam_dy_apply() -> void:
	if is_instance_valid(ship):
		ship.set("_cam_plaque_dy", ship.get("CAM_PLAQUE_DY"))


# ══ 战术场岸线（lane w20-b1：g13 遗留①）════════════════════════════════════════
# 本场景原先只有海面、船与两个写死的示意港，镜头拉到 w19-g13 的 0.5 也看不到岸。
# 这里把海图 MapView 同一份真岸线（data/coastline.json + ChartProjection）摊进本场景世界坐标：
# 经纬 →（海图同口径圆锥投影）→ 海图画布 px → 按 _COAST_SCALE 缩放、再平移摆进场景。
# _COAST_SCALE 按泉州—兴化两头算：真图距约 76 km，场景里两港相距 2236 px，得 28.43；搬过去后泉、兴两港
# 正好落在岸沿上、示意港位不挪节点（遗留③港位是场景示意位，仍然记载在拍板清单）。
var _coast_rings: Array = []          # [{ pts: PackedVector2Array, box: Rect2 }]，世界坐标
var _coast_layer: Node2D = null      # 岸线层节点（探针可经 CoastlineLayer 关掉以断言变化）
const _COAST_SCALE := 28.43          # 海图 px → 世界 px：泉州—兴化真图 76 km 对场景 2236 px
const _COAST_NEAR := 8000.0          # 只铺场景中心 ±8000 内的环（镜头半幅 720；出圈整环不入画）
const _COAST_MIN_Z := 0.30           # 相机 zoom 低于此值整层淡出：远景截图不必全线露墨、也不糊成一团
const _COAST_LINE := Color(0.22, 0.18, 0.14, 0.55)   # 岸线墨线（淡；UiTheme.INK 同系）


## 战斗 / 自由场景都铺：数据缺失时返回 []，整场就不画。
func _setup_coastline() -> void:
	_coast_rings = _build_coast_rings()
	if _coast_rings.is_empty():
		return
	var layer := Node2D.new()
	layer.name = "CoastlineLayer"
	layer.z_index = -5                     # 海面（Ocean z −10）之上、船与港标之下：只作背景
	layer.draw.connect(_draw_coastline.bind(layer))
	layer.set_meta("coast_rings", _coast_rings.size())
	add_child(layer)
	_coast_layer = layer


## 经纬 → 场景世界 px：ChartProjection.to_px 后按 _COAST_SCALE 缩，再平移到泉州真位置落场 PortQuanzhou (0,1000)。
static func _build_coast_rings() -> Array:
	var data: Dictionary = GameManager.coastline_data
	if data.is_empty():
		return []
	var proj := ChartProjection.from_json()
	if not proj.loaded:
		return []
	# 两个示意港的海图真位置做锚（港位本身不动；海岸随锚搬）：泉州真位置印在海图岸内，
	# 若直接把泉州真位置压到 PortQuanzhou (0,1000)，泉州港会被岸块压住；所以锚点取 (180,1000)——
	# 即把整片海岸往北挪开一点、唯独留泉州在湾内。沿用同一锚测不出兴化二者的示意示意差，
	# 港位xíng方位仍符合真海图走向（遗留③拍板清单有载）。
	var qz_src: Vector2 = proj.to_px(118.68, 24.87)
	var world_offset: Vector2 = Vector2(180.0, 1000.0) - qz_src * _COAST_SCALE
	var out: Array = []
	for ring in data.get("land", []):
		if ring.size() < 3:
			continue
		var poly := PackedVector2Array()
		for pt in ring:
			poly.append(proj.to_px(float(pt[0]), float(pt[1])) * _COAST_SCALE + world_offset)
		var b: Rect2 = _poly_box(poly)
		# 只铺场景中心 ±_COAST_NEAR 内的环（出圈的整块弃：远洋船看不见、画了也是虚耗）
		if b.position.x > _COAST_NEAR or b.end.x < -_COAST_NEAR \
				or b.position.y > _COAST_NEAR or b.end.y < -_COAST_NEAR:
			continue
		out.append({"pts": poly, "box": b})
	return out


## 岸线层自绘：世界坐标系下画、镜头一挪本条画自动跟着，不需要手动 queue_redraw；按 zoom 定视窗、整层透明度。
func _draw_coastline(layer: CanvasItem) -> void:
	if _coast_rings.is_empty():
		return
	var cam: Camera2D = (get_node_or_null("Ship/Camera2D") as Camera2D) if has_node("Ship/Camera2D") else null
	var z: float = maxf(cam.zoom.x, 0.01) if cam != null else 0.5
	var view: Rect2 = _coast_view_rect()
	var col: Color = _COAST_LINE
	if z < _COAST_MIN_Z:
		# 远景：整层按比例淡——不糊成一片黑，也看得出有岸
		col.a *= z / _COAST_MIN_Z
	for r in _coast_rings:
		if not (r["box"] as Rect2).intersects(view, false):
			continue
		layer.draw_polyline(r["pts"], col, maxf(1.2 / z, 0.8), true)


## 当前镜头看到的世界范围（视野外扩三圈）；没拿到相机就按旗舰位置在后场大约铺一幅。
func _coast_view_rect() -> Rect2:
	var cam: Camera2D = (get_node_or_null("Ship/Camera2D") as Camera2D) if has_node("Ship/Camera2D") else null
	var center: Vector2 = Vector2.ZERO
	var z := 0.5
	if cam != null and cam.is_inside_tree():
		z = maxf(cam.zoom.x, 0.05)
		center = cam.get_screen_center_position()
	elif is_instance_valid(ship):
		center = ship.position
	var half: Vector2 = get_viewport_rect().size * 0.5 / z
	# 发散一圈：屏幕一半再扩 4 成（镜头平移 / 摆动 / 截图向斜一点时岸沿也在画）
	return Rect2(center - half * 1.4, half * 2.8)


static func _poly_box(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


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
			_sea.current_at(ship.position), delta, _flagship_mods())
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


## 旗舰这一帧的机动乘数：船体损伤（_maneuver_mods）并上号令面板的效力（lane w53-2）——抢风加派缭手帆力增、能更贴风，
## 专力装填抽走帆手帆力减；不下令全 1.0、贴风 0，与不接线时一样
func _flagship_mods() -> Dictionary:
	var mods := _maneuver_mods(ship).duplicate()
	var om := order_mods()
	mods["trim"] = float(om.get("sail_drive", 1.0))
	mods["helm"] = float(om.get("turn_rate", 1.0))
	mods["pinch_delta"] = float(om.get("pinch_delta", 0.0))
	return mods


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



## 号令面板此刻的效力（CombatOrdersPanel.modifiers_for；没挂面板 / 不下令为中性表，乘数全 1.0）。
## 旗舰机动（_flagship_mods）、装填（Ship._fire_broadside）都从这里取（lane w53-2：面板「效力」一行原先没有一处消费）
func order_mods() -> Dictionary:
	return _CombatOrders.modifiers_for(self)


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
	# 本船去钩：号令面板备接舷聚齐了钩拒手，够距底数按「钩距」效力放远（lane w53-2；G 键、顶匾「舷边可接」、状态条「可接」同走这里）；敌船钩本船照旧
	var reach := BOARD_DISTANCE * (float(order_mods().get("board_range", 1.0)) if a == ship else 1.0)
	return _Maneuver.boarding_approach(_hull_state(a), _hull_state(b), _wind_to(), _wind_speed(), reach)


func _valid_hull(n) -> bool:
	return is_instance_valid(n) and n is Node2D
