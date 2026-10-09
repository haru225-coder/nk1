class_name EnemyCaptainAI
extends RefCounted
## Lane combat07：敌将（敌船船长）战术状态机。PirateShip 每个物理帧喂一份局势（tick），取回舵令：航向 / 帆桨 / 抛钩 / 离场；
## 开不开炮、打哪一舷另问 fire_side。本件只做判断，不碰场景树、不读 autoload——局势全由调用方填（PirateShip._situation），
## 所以能拿假局势逐条验（self_check）。
##
## 六个状态（LABELS 即上屏文案）：
##   接近 approach      敌在射程外：拉近，瞄目标上风一侧，到场就带着风头
##   抢上风 weather     进了射程却在下风：先绕到上风——帆船按受风角抢风换舷，多桨船逆风摇橹直上；抢不到按时放弃
##   保持舷炮 broadside 把目标压在装好的那一舷正横，守住射距带；矢石有数，将尽时近了才放
##   接舷企图 board     人多势众 / 矢石将尽 / 敌船已残或停驶：抢前截住、并舷同速，近了抛钩，钩上请宿主开白刃
##   脱离 disengage     士气沮丧 / 船体重创 / 僚船尽失 / 矢石告罄：转舵远遁（多桨船逆风摇橹，帆船顺风放走），拉开到 ESCAPE_DIST 离场
##   降幡 strike        士气崩溃，或重创又逃不脱：落帆停驶、停射，白刃不再抵抗（PirateShip.combat_strength 打折），等对方接舷收船；
##                      久无人接收则乘隙遁去（改脱离，不再回头）
## 脱离、降幡都是粘的：脱离只在溃因都已不在、敌船将沉、我方白刃占优时回帆抢船；降幡不回头。
##
## 宋元近海口径：风是头等事（占上风进退由己，落下风只能挨打或走）；多桨快船不全靠风，逆风也追得上、逃得掉，但桨手会累；
## 矢石、火药有数，打光了只能接舷或走；海寇本意在夺船劫货，人多就抛钩跳帮，失利即散；元军哨船重阵法，宁远射、少近战。
##
## 可选外部 API（别的 lane 的；文件不在 / 方法不在 / 签名对不上，一律退回本件内置启发式，不报错）：
##   HOOKS 逐项登记「能力 → 模块路径、候选方法名、形参类型」：只认候选名里第一个「静态、形参个数与类型逐个对上」的方法，
##   返回值类型不对也退回内置；提供方有零参 is_live() 就先问它（CombatMorale 数据读不到即停用）；
##   CombatMorale 另读阈值常量（MORALE_CONSTS，只读不调）。set_provider 可显式注入（探针 / 日后装配件），force_builtin 全部钉回内置。
##   现对上的：CombatMorale.captain_verdict（combat06，士气裁决）、ManeuverModel.speed_factor（combat02，航速系数，入库即接）。
##   局势里的 morale_state / fire_factor 是 CombatMorale 观战挂件写在船节点 meta 上的士气簿（PirateShip 转进来）：在场即以它为准。
##   接舷钩牢率（MeleeResolve.grapple_chance，形参是两方白刃字典）与海流（SeaState.active）要节点，由 PirateShip 那头接。

const APPROACH := &"approach"
const WEATHER := &"weather"
const BROADSIDE := &"broadside"
const BOARD := &"board"
const DISENGAGE := &"disengage"
const STRIKE := &"strike"
const LABELS := {
	APPROACH: "接近", WEATHER: "抢上风", BROADSIDE: "保持舷炮",
	BOARD: "接舷企图", DISENGAGE: "脱离", STRIKE: "降幡",
}

## 局势每 0.4 s 重估一次（航向每帧跟）；同级状态之间至少呆满 MIN_DWELL 再换，防来回抖。脱离 / 降幡不受限。
const DECIDE_EVERY := 0.4
const MIN_DWELL := 1.2
## 射距（像素）：ENGAGE_DIST 外先接近；舷炮守 RANGE_MIN–RANGE_MAX；FIRE_RANGE 是横风时估的最远一射，顺风远、逆风近
const ENGAGE_DIST := 680.0
const RANGE_MIN := 260.0
const RANGE_MAX := 540.0
const FIRE_RANGE := 760.0
## 正横 ±FIRE_ARC 内才放（旧版 0.3）
const FIRE_ARC := 0.32
## 抢上风：上风余量 =（我 − 敌）·风源向 / 距离；低于 WEATHER_WANT 才去抢，到 WEATHER_OK 算占住；
## 逼近到 WEATHER_MIN_DIST 内就不抢了，再进要拉开到 WEATHER_MIN_DIST + WEATHER_REENTER；绕到敌上风 WEATHER_STANDOFF、
## 从自己这一侧偏 WEATHER_PASS 过去（不从敌船身上穿）；一场里抢风总时长封顶 WEATHER_TIMEOUT × 档案 gauge
const WEATHER_WANT := 0.1
const WEATHER_OK := 0.35
const WEATHER_STANDOFF := 380.0
const WEATHER_PASS := 220.0
const WEATHER_MIN_DIST := 250.0
const WEATHER_REENTER := 80.0
const WEATHER_TIMEOUT := 8.0
## 抛钩：距离在 GRAPPLE_RANGE 内（WorldMap.BOARD_DISTANCE 是 140）、相对速度不过 GRAPPLE_REL_SPEED，每 GRAPPLE_EVERY 秒试一次；
## 连失 GRAPPLE_FAILS 次退回炮战歇 GRAPPLE_REST 秒；白刃得手 / 跳帮受挫后 REBOARD_COOLDOWN 秒内不再贴上来
const GRAPPLE_RANGE := 120.0
const GRAPPLE_REL_SPEED := 170.0
const GRAPPLE_EVERY := 1.4
const GRAPPLE_FAILS := 3
const GRAPPLE_REST := 8.0
const REBOARD_COOLDOWN := 14.0
## 本船先抛钩跳帮、白刃没拿下（被击退 / 被砍缆）掉的士气：与守住白刃时大振的 12 对称
const BOARD_REPELLED_SHOCK := 12.0
## 脱离拉开到此即离场（WorldMap 镜头 1.5 倍约看 850×480，1500 早出了视野）
const ESCAPE_DIST := 1500.0
## 追的窗口（lane w53-p4-melee，开关 pursue_window）：敌船遁走不是瞬间脱离——下风的、伤重的先得手短挫一截、
## 离场线再拖后一程，本船满帆多半追得上、贴得上钩（钩住 = 白刃照旧）；贴不上（对面满帆顺风还在上风）照走
const PURSUE_TURN_PENALTY := 0.8
const PURSUE_DIST_PAD := 260.0
## 降后久无人接收（STRIKE_SLIP_TIME 秒、对方还在 STRIKE_SLIP_DIST 外）就乘隙遁去
const STRIKE_SLIP_TIME := 35.0
const STRIKE_SLIP_DIST := 520.0
## 硬帆船最近能吃到离风源约 63° 的风（近迎风）；再往里顶风走不动，要抢风换舷
const TACK := 1.1
## 矢石余量到此算「将尽」：改谋接舷，放炮也等近了再放
const AMMO_LOW := 0.25
## 将尽时「近了」的尺度：SAVE_RANGE 内才放（fire_side 惜弹）；舷炮守的射距带远边跟着收到 SAVE_RANGE − SAVE_MARGIN（lane w53-2）。
## 不收的话照旧守 RANGE_MIN–RANGE_MAX，多半兜在 360–540 之间够不上自己惜弹的射距：实测哨船余弹一两分钟一发不放，拖到限时两散
const SAVE_RANGE := 360.0
const SAVE_MARGIN := 40.0
## 一舷装填（满员时）秒数；人少了慢，见 reload_time。取旧版齐射冷却 3 s（ReloadAmmo 落地前不替弹道那一路改射速）
const SIDE_RELOAD := 3.0
## 桨力：多桨快船 0.62、海鹘带橹 0.3、商船只有几支橹 0.15（以满帆顺风为 1）；划满 STAMINA_DRAIN 秒力竭，歇 STAMINA_REST 秒回满
const OARS := {"pirate_boat": 0.62, "sea_falcon": 0.3}
const OARS_DEFAULT := 0.15
const STAMINA_DRAIN := 25.0
const STAMINA_REST := 40.0

## 敌将档案：
##   board_ratio 白刃战力比到此就想接舷（WorldMap 白刃胜率 = 比 /（1 + 比）：1.5 约六成、1.8 约六成半、2.3 约七成——跳帮失手是整船被夺，没把握不贴）
##   desperate   矢石将尽时拼一把接舷要的最低比（海寇敢赌，元军宁可收兵）
##   hull_rout   船体剩这么多、白刃又没把握就走（海寇见伤即走，元军硬扛）
##   rout / strike 士气线；disc 受创掉士气的倍数；gauge 看重上风的程度（抢风时长预算的倍数）；volleys 随船矢石可放几轮；strike_word 降时的说法
const PROFILES := {
	"pirate": {"label": "海寇", "board_ratio": 1.5, "desperate": 0.85, "hull_rout": 0.4,
		"rout": 34.0, "strike": 10.0, "disc": 1.1, "gauge": 0.6, "volleys": 8, "strike_word": "落帆乞降"},
	"patrol": {"label": "元军哨船", "board_ratio": 2.3, "desperate": 1.3, "hull_rout": 0.25,
		"rout": 22.0, "strike": 14.0, "disc": 0.75, "gauge": 1.0, "volleys": 12, "strike_word": "降幡请降"},
	"default": {"label": "敌船", "board_ratio": 1.8, "desperate": 1.0, "hull_rout": 0.33,
		"rout": 28.0, "strike": 12.0, "disc": 1.0, "gauge": 0.8, "volleys": 10, "strike_word": "降幡"},
}

## 可选外部 API：能力 → [模块路径, 候选方法名（按序取第一个对得上的）, 形参类型]
const HOOKS := {
	# (船首向, 风去向, 风力) → 该航向的航速系数（满帆顺风约 1）
	"speed_factor": ["res://scripts/combat/ManeuverModel.gd",
		["captain_speed_factor", "speed_factor", "sail_speed_factor", "point_of_sail_factor"],
		[TYPE_VECTOR2, TYPE_VECTOR2, TYPE_FLOAT]],
	# (局势 ctx，键见 _verdict_ctx) → 含 rout / flee 即脱离，含 surrender / strike 即降幡，其余不改
	"morale_verdict": ["res://scripts/combat/CombatMorale.gd",
		["captain_verdict", "morale_verdict", "rout_verdict"],
		[TYPE_DICTIONARY]],
	# (水手, 每舷炮位) → 一舷装填秒数
	"reload_time": ["res://scripts/combat/ReloadAmmo.gd",
		["captain_reload_time", "side_reload_time", "reload_time"],
		[TYPE_INT, TYPE_INT]],
	# (船型) → 随船矢石可放几轮
	"volleys": ["res://scripts/combat/ReloadAmmo.gd",
		["captain_volleys", "volleys_for", "starting_volleys"],
		[TYPE_STRING]],
	# (相对速度, 风力, 水手) → 一次抛钩得手概率
	"grapple_chance": ["res://scripts/combat/MeleeResolve.gd",
		["captain_grapple_chance", "grapple_chance", "hook_chance"],
		[TYPE_FLOAT, TYPE_FLOAT, TYPE_INT]],
}
## CombatMorale 的阈值常量（只读常量表，不调用）：有就替掉档案里的溃走 / 降幡线；≤1 的当比例 ×100
const MORALE_PATH := "res://scripts/combat/CombatMorale.gd"
const MORALE_CONSTS := {
	"rout": ["ROUT_THRESHOLD", "ROUT_MORALE", "ROUT_LINE"],
	"strike": ["SURRENDER_THRESHOLD", "SURRENDER_MORALE", "STRIKE_MORALE"],
}

## 模块查找按路径缓存（全局一份）；注入的只作用于本实例
static var _hook_cache := {}

var state: StringName = &""
var prev_state: StringName = &""
## 最近一次换状态的理由（中文短句，上屏 / 探针读）
var reason := ""
## [[秒, 状态, 理由], …]，最多留 32 条
var history: Array = []
var profile_id := "default"
var profile: Dictionary = PROFILES["default"]
## 士气 0–100：本件按受创 / 伤亡 / 僚船折损 / 白刃胜负增减；PirateShip 回写 enemy_morale
var morale := 60.0
var volleys := 8
var volleys_max := 8
var oars := OARS_DEFAULT
var rout_line := 28.0
var strike_line := 12.0

var _injected := {}
var _builtin_only := false
var _morale_start := 60.0
var _reported := 60
var _captain_force := 1.0
var _crew_start := 1
var _crew_seen := -1
var _guns := 1
var _consorts_gone := 0
var _consorts_struck := 0
var _time := 0.0
var _dwell := 0.0
var _decide_t := 0.0
var _since_hit := 99.0
var _weather_spent := 0.0
var _grapple_cd := 0.0
var _grapple_fails := 0
var _reboard_cd := 0.0
var _cd_reason := ""
var _stamina := 1.0
var _tack := 0
var _side := 1
var _side_reload := {-1: 0.0, 1: 0.0}
var _slipping := false
var _s: Dictionary = {}
var _g: Dictionary = {}
## 追的窗口（lane w53-p4-melee，开关 pursue_window）：true 时脱离的离场线拖后 PURSUE_DIST_PAD、逃速短挫
## PURSUE_TURN_PENALTY——挂法两路，哪路在先都认：
##   ① 局面 s["pursue_window"]（PirateShip 转进；本 lane 不动 PirateShip，WorldMap 往敌将实例上塞 ②）
##   ② 本成员（WorldMap._spawn_enemy 按开关写；探针直写照走）
## 关开关 / 两路都缺席 = 逐字旧脱离（ESCAPE_DIST 不变、逃速不挫）
var pursue_window := false


## 开战时调一次（PirateShip._ready）。sprite_key 用来认元军哨船（sprite=yuan_patrol）。
func setup(ship_type: String, sprite_key: String, captain_force: float, crew: int, morale0: float, guns: int) -> void:
	profile_id = profile_for(ship_type, sprite_key)
	profile = PROFILES[profile_id]
	oars = float(OARS.get(ship_type, OARS_DEFAULT))
	_captain_force = captain_force
	_crew_start = maxi(crew, 1)
	_crew_seen = crew
	morale = clampf(morale0, 0.0, 100.0)
	_morale_start = morale
	_reported = int(roundf(morale))
	_guns = maxi(guns, 1)
	rout_line = float(profile["rout"])
	strike_line = float(profile["strike"])
	if not _builtin_only:
		_read_morale_consts()
	volleys_max = int(profile["volleys"])
	var v = _call_hook("volleys", [ship_type])
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		volleys_max = clampi(int(v), 0, 99)
	volleys = volleys_max


static func profile_for(ship_type: String, sprite_key: String) -> String:
	if sprite_key == "yuan_patrol":
		return "patrol"
	if ship_type == "pirate_boat":
		return "pirate"
	return "default"


static func label_of(st: StringName) -> String:
	return str(LABELS.get(st, ""))


func label() -> String:
	return label_of(state)


func is_struck() -> bool:
	return state == STRIKE or _slipping


func ammo_frac() -> float:
	return 1.0 if volleys_max <= 0 else clampf(float(volleys) / float(volleys_max), 0.0, 1.0)


## 士气取整（回写 PirateShip.enemy_morale 用）；同时记下「本件报出去的数」，下一帧局势里的士气与它不同即外部改过
func reported_morale() -> int:
	_reported = int(roundf(morale))
	return _reported


# ── 每帧 ────────────────────────────────────────────

## s：局势（键见 PirateShip._situation）；返回舵令 {heading, throttle, drive, drift, grapple, leave, state, morale}
func tick(s: Dictionary, delta: float) -> Dictionary:
	_s = s
	_time += delta
	_dwell += delta
	_since_hit += delta
	_grapple_cd = maxf(0.0, _grapple_cd - delta)
	_reboard_cd = maxf(0.0, _reboard_cd - delta)
	for side in [-1, 1]:
		_side_reload[side] = maxf(0.0, float(_side_reload[side]) - delta)
	if state == WEATHER:
		_weather_spent += delta
	_sync(s)
	_rally(delta)
	_g = _geometry(s)
	_decide_t -= delta
	if _decide_t <= 0.0 or state == &"":
		_decide_t = DECIDE_EVERY
		_evaluate(s)
	return _orders(s, delta)


## 这一帧该放哪一舷：+1 右舷、-1 左舷、0 不放。angle_diff = 船首向 → 目标的夹角（正 = 目标在右）。
func fire_side(angle_diff: float, dist: float) -> int:
	if state == STRIKE or _slipping or volleys <= 0:
		return 0
	if bool(_s.get("frozen", false)) or bool(_s.get("host_boarding", false)):
		return 0  # 布景冻结；或白刃正酣，往接舷处放箭伤的是自己人
	if absf(absf(angle_diff) - PI * 0.5) > FIRE_ARC:
		return 0
	var side := 1 if angle_diff > 0.0 else -1
	if float(_side_reload[side]) > 0.0:
		return 0
	var heading: Vector2 = _s.get("heading", Vector2.UP)
	var shot_dir := heading.rotated(float(side) * PI * 0.5)
	var wind: Vector2 = _g.get("wind", Vector2.ZERO)
	var rng := FIRE_RANGE * (1.0 + 0.12 * shot_dir.dot(wind))  # 顺风射远、逆风射近
	if ammo_frac() <= AMMO_LOW:
		rng = minf(rng, SAVE_RANGE)  # 惜弹：近了再放
	if state == DISENGAGE:
		rng = minf(rng, 420.0)  # 且走且射，只打贴上来的
	return side if dist <= rng else 0


## 放过一轮：扣矢石、这一舷进装填
func on_fired(side: int) -> void:
	volleys = maxi(0, volleys - 1)
	_side_reload[side] = reload_time(int(_s.get("crew", _crew_start)))


## 一舷装填秒数：人手少了慢（满员 SIDE_RELOAD，剩一半约 ×1.4，封顶 ×2）；ReloadAmmo 在就按它；再除以士气簿的射速系数
func reload_time(crew: int) -> float:
	var t = _call_hook("reload_time", [crew, _guns])
	var base := SIDE_RELOAD * clampf(sqrt(float(_crew_start) / float(maxi(crew, 1))), 1.0, 2.0)
	if typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_INT:
		base = clampf(float(t), 1.5, 20.0)
	# 士气簿给的射速系数（CombatMorale 挂件 meta 的 fire；动摇了手慢），没有即 1
	return base / clampf(float(_s.get("fire_factor", 1.0)), 0.4, 1.5)


## 散布（弧度）：士气低了手抖
func spread() -> float:
	return 0.07 + 0.08 * (1.0 - clampf(morale / 100.0, 0.0, 1.0))


## 舵效：船速低舵不吃水（最慢 0.35）；多桨船能一舷划一舷倒着掉头（不低于 0.6）
func turn_factor(speed_ratio: float) -> float:
	var f := clampf(0.35 + 0.65 * speed_ratio, 0.35, 1.0)
	return maxf(f, 0.6) if oars >= 0.4 else f


## 一次抛钩得手概率
func grapple_chance(rel_speed: float, crew: int) -> float:
	var ws := float(_s.get("wind_strength", 80.0))
	var c = _call_hook("grapple_chance", [rel_speed, ws, crew])
	if typeof(c) == TYPE_FLOAT or typeof(c) == TYPE_INT:
		return clampf(float(c), 0.0, 1.0)
	return builtin_grapple_chance(rel_speed, ws, crew)


static func builtin_grapple_chance(rel_speed: float, wind_strength: float, crew: int) -> float:
	var calm := 1.0 - clampf((wind_strength - 110.0) / 220.0, 0.0, 0.45)  # 风浪大，钩索难上
	var slow := 1.0 - 0.6 * clampf(rel_speed / GRAPPLE_REL_SPEED, 0.0, 1.0)  # 并舷越稳越好钩
	var hands := clampf(float(crew) / 30.0, 0.3, 1.2)  # 抛钩、拽缆都要人手
	return clampf(0.5 * calm * slow * hands, 0.05, 0.85)


# ── 事件（PirateShip 转进来）──────────────────────────

## 中了一弹：掉士气（丢 1% 船体约掉 0.45，过半 / 过四分之三各再一震）
func on_hit(dmg: float, hull_max: float, hull_after: float) -> void:
	_since_hit = 0.0
	var hm := maxf(hull_max, 1.0)
	var before := (hull_after + dmg) / hm
	var after := hull_after / hm
	var shock := 0.45 * dmg / hm * 100.0
	if before > 0.5 and after <= 0.5:
		shock += 5.0
	if before > 0.25 and after <= 0.25:
		shock += 8.0
	_shake(shock)


## 抛钩结果：失手记次数，连失几次先退回炮战歇一阵
func on_grapple(ok: bool) -> void:
	_grapple_cd = GRAPPLE_EVERY
	if ok:
		_grapple_fails = 0
		return
	_grapple_fails += 1
	if _grapple_fails >= GRAPPLE_FAILS:
		_grapple_fails = 0
		_reboard_cd = GRAPPLE_REST
		_cd_reason = "钩索屡失，暂退炮战"


## 外头定了本船降（玩家喊话劝降得手之类）：径直降幡，不等下一次判局势；已降 / 已遁的不动
func force_strike(why: String) -> void:
	if state == STRIKE or _slipping:
		return
	_set_state(STRIKE, why)


## ── lane w53-17（二期「通事劝降」）──────────────────────────────
## 只读接口：通事每级劝降胜算 +0.05（combat_phases.json orders call_surrender.tongshi_per_level、
## officer_effects.tongshi.call_surrender 两个源同数）。crew_role_effects 开关那头在战端判
## （WorldMap / 劝降面板），本件只委办「按品级折算」这一笔纯函——tongshi_level ≤ 0 即 0。
## 接线那头归 w53-15 的劝降面板（parley_chance 吃掉它）。
const TONGSHI_PER_LEVEL := 0.05
static func parley_bonus_tongshi(tongshi_level: int) -> float:
	return TONGSHI_PER_LEVEL * float(maxi(0, tongshi_level))


## 白刃打完、船还在自己手里（WorldMap 判对方败、脱钩）：士气大振，退开整队再说
func on_melee_held() -> void:
	morale = minf(100.0, morale + 12.0)
	_reboard_cd = REBOARD_COOLDOWN
	_cd_reason = "白刃得手，退开整队"


## 本船先抛钩跳帮、白刃没拿下、船还在自己手里（WorldMap 判本船这攻方败、放钩）：海寇失利即散——士气受挫，退回炮战歇一阵
func on_boarding_repelled() -> void:
	_shake(BOARD_REPELLED_SHOCK)
	_reboard_cd = REBOARD_COOLDOWN
	_cd_reason = "跳帮受挫，退回炮战"


## 掉士气：档案 disc × 敌将系数（悍将稳得住）× 成群的底气（同场还有 n 艘僚船在打，每艘把震动压掉一截；僚船一折，底气跟着没）
func _shake(x: float) -> void:
	var disc := float(profile["disc"]) * clampf(1.15 - 0.15 * _captain_force, 0.75, 1.15)
	var live := maxi(0, int(_s.get("consorts", 0)) - _consorts_gone - _consorts_struck)
	morale = maxf(0.0, morale - x * disc / (1.0 + 0.2 * float(live)))


## 外部改的士气 / 水手 / 僚船折损，按局势对账
func _sync(s: Dictionary) -> void:
	var m_ext := int(s.get("morale", _reported))
	if m_ext != _reported:
		morale = clampf(float(m_ext), 0.0, 100.0)  # 别处（探针 / 别的模块）改了士气，以它为准
	var c := int(s.get("crew", _crew_seen))
	if _crew_seen >= 0 and c < _crew_seen:
		_shake(0.6 * float(_crew_seen - c) / float(_crew_start) * 100.0)  # 死伤
	_crew_seen = c
	var gone := int(s.get("consorts_gone", 0))
	var struck := int(s.get("consorts_struck", 0))
	if gone > _consorts_gone:
		_shake(12.0 * float(gone - _consorts_gone))  # 僚船沉了 / 被夺 / 走了
	if struck > _consorts_struck:
		_shake(8.0 * float(struck - _consorts_struck))  # 僚船降了：降是会传染的
	_consorts_gone = gone
	_consorts_struck = struck


## 一阵没挨打就慢慢收拢人心（回到开战时为止；逃着的、降了的不回）
func _rally(delta: float) -> void:
	if _since_hit >= 6.0 and state != DISENGAGE and state != STRIKE and morale < _morale_start:
		morale = minf(_morale_start, morale + 0.35 * delta)


# ── 判局势 ───────────────────────────────────────────

func _geometry(s: Dictionary) -> Dictionary:
	var pos: Vector2 = s.get("pos", Vector2.ZERO)
	var tp: Vector2 = s.get("target_pos", pos)
	var to_t := tp - pos
	var dist := to_t.length()
	var dir_t := to_t / dist if dist > 0.01 else Vector2.UP
	var wv: Vector2 = s.get("wind", Vector2.ZERO)
	var wind := wv.normalized() if wv.length() > 0.01 else Vector2.ZERO
	var upwind := 0.0
	if dist > 0.01 and wind != Vector2.ZERO:
		upwind = (pos - tp).dot(-wind) / dist
	var vel: Vector2 = s.get("vel", Vector2.ZERO)
	var tv: Vector2 = s.get("target_vel", Vector2.ZERO)
	return {"dist": dist, "dir_t": dir_t, "wind": wind, "up": -wind, "upwind": upwind,
		"rel_speed": (vel - tv).length(), "target_speed": tv.length()}


func _derive(s: Dictionary) -> Dictionary:
	var g := _g
	var own := float(s.get("own_strength", 1.0))
	var foe := float(s.get("target_strength", 1.0))
	var ratio := 9.9 if foe <= 0.01 else minf(9.9, own / foe)
	var flee := _flee_heading(s, g)
	var hull := float(s.get("hull", 1.0))
	var my_flee := float(s.get("max_speed", 250.0)) * _drive_factor(flee, s) * (0.55 + 0.45 * hull)
	var their := float(s.get("target_max_speed", 300.0)) * builtin_sail_factor(flee, g["wind"], float(s.get("wind_strength", 80.0)))
	var consorts := maxi(int(s.get("consorts", 0)), 0)
	# 追的窗口（lane w53-p4-melee，开关 pursue_window）：敌能跑多快先短挫一截——下风的、伤重的先被本船咬住；
	# 追不上的（对面满帆顺风在上风）can_escape 照旧为真、照走（不困住逃兵）
	if _pursue_on(s):
		my_flee *= PURSUE_TURN_PENALTY
	return {
		"dist": g["dist"], "upwind": g["upwind"], "ratio": ratio, "hull": hull,
		"escape_dist": ESCAPE_DIST + (PURSUE_DIST_PAD if _pursue_on(s) else 0.0),
		"crew_frac": float(s.get("crew", _crew_start)) / float(_crew_start),
		"ammo": ammo_frac(), "target_hull": float(s.get("target_hull", 1.0)),
		"target_speed": g["target_speed"], "wind_strength": float(s.get("wind_strength", 80.0)),
		"lost_frac": 0.0 if consorts == 0 else float(_consorts_gone + _consorts_struck) / float(consorts),
		"can_escape": my_flee >= 0.92 * their or float(g["dist"]) >= 900.0,
	}


func _evaluate(s: Dictionary) -> void:
	var d := _derive(s)
	if state == STRIKE:
		if _dwell >= STRIKE_SLIP_TIME and float(d["dist"]) >= STRIKE_SLIP_DIST:
			_slipping = true
			_set_state(DISENGAGE, "降后无人接收，乘隙遁去")
		return
	if _slipping:
		return
	var v := _verdict(d)
	if v[0] == "strike":
		_set_state(STRIKE, v[1])
		return
	if state == DISENGAGE:
		# 溃因都不在了（v 空）、敌船又将沉，才回帆抢船；不然回帆一拍、溃走一拍来回抖
		if v[0] == "" and float(d["target_hull"]) <= 0.2 and float(d["ratio"]) >= 1.2:
			_set_state(BOARD, "敌船将沉，回帆抢船")
		return
	if v[0] == "rout":
		_set_state(DISENGAGE, v[1])
		return
	var want := _tactical(d)
	if want[0] != state and (_dwell >= MIN_DWELL or state == &""):
		_set_state(want[0], want[1])


## 士气裁决：["strike" | "rout" | "", 理由]。谁说了算，按序：
##   一、船节点上的士气簿（CombatMorale 挂件写的 meta，局势键 morale_state）：降、溃听它，其余只剩战术上的走；
##   二、CombatMorale.captain_verdict（is_live 为真才算数）：降、溃听它，它说稳也只剩战术上的走；
##   三、都没有：本件内置（士气线 + 逃不逃得掉 + 战术上的走）。
func _verdict(d: Dictionary) -> Array:
	var ms := str(_s.get("morale_state", ""))
	if ms != "":
		if ms == "struck":
			return ["strike", _strike_why()]
		if ms == "routing":
			return ["rout", "士气已沮，转舵脱离"]
		return _tactical_rout(d)
	var ext = _call_hook("morale_verdict", [_verdict_ctx(d)])
	if (typeof(ext) == TYPE_STRING or typeof(ext) == TYPE_STRING_NAME) and _hook_live("morale_verdict"):
		var t := str(ext).to_lower()
		if t.find("surrender") >= 0 or t.find("strike") >= 0:
			return ["strike", _strike_why()]
		if t.find("rout") >= 0 or t.find("flee") >= 0:
			return ["rout", "士气已沮，转舵脱离"]
		return _tactical_rout(d)
	return _builtin_verdict(d)


## 内置士气裁决：士气线、重创 / 伤亡 / 矢石尽又逃不脱即降，再加战术上的走。
## 追的窗口（lane w53-p4-melee，开关 pursue_window）：重创又贴着玩家时追窗口开——逃不脱的线挂上追窗（咬住的痕）
func _builtin_verdict(d: Dictionary) -> Array:
	var m := morale
	var escape := bool(d["can_escape"])
	if m <= strike_line:
		return ["strike", _strike_why()]
	if float(d["hull"]) <= 0.22 and m <= 40.0 and _pursue_on(_s):
		return ["strike", "船体重创，逃不脱，%s" % profile["strike_word"]]
	if float(d["hull"]) <= 0.22 and m <= 40.0 and not escape:
		return ["strike", "船体重创，逃不脱，%s" % profile["strike_word"]]
	if float(d["crew_frac"]) <= 0.3 and m <= 45.0 and not escape:
		return ["strike", "伤亡过半，%s" % profile["strike_word"]]
	if state == DISENGAGE and _dwell >= 8.0 and float(d["dist"]) < 450.0 and m <= 30.0:
		return ["strike", "逃不脱，%s" % profile["strike_word"]]
	if float(d["ammo"]) <= 0.0 and float(d["ratio"]) < 0.6 and not escape and m <= 45.0:
		return ["strike", "矢石告罄，%s" % profile["strike_word"]]
	if m <= rout_line:
		return ["rout", "士气已沮，转舵脱离"]
	return _tactical_rout(d)


## 战术上的走（与士气簿无关，敌将自己的算盘）：船伤了又贴不上、僚船折了、矢石打光又贴不上
func _tactical_rout(d: Dictionary) -> Array:
	var m := morale
	if float(d["hull"]) <= float(profile["hull_rout"]) and float(d["ratio"]) < 1.1:
		return ["rout", "船体重创，无力再战"]
	if float(d["lost_frac"]) >= 0.99 and float(d["ratio"]) < 0.9 and m <= 55.0:
		return ["rout", "僚船尽失，孤船难支"]
	if float(d["lost_frac"]) >= 0.5 and float(d["ratio"]) < 0.8 and m <= 40.0:
		return ["rout", "僚船折损过半，无心恋战"]
	# 矢石打光、白刃比又够不上本档案拼接舷的线（desperate，同 _tactical「矢石将尽，改谋接舷」）：不贴就只能走（lane w53-2）。
	# 原先写死 0.85（海寇那一档）：哨船 1.3、别的 1.0，比落在 [0.85, desperate) 的弹尽船既不贴也不走，兜着空舷拖到限时两散
	if float(d["ammo"]) <= 0.0 and float(d["ratio"]) < float(profile["desperate"]):
		return ["rout", "矢石告罄，无以为战"]
	return ["", ""]


func _strike_why() -> String:
	return "士气崩溃，%s" % profile["strike_word"]


func _verdict_ctx(d: Dictionary) -> Dictionary:
	return {"morale": morale, "hull": d["hull"], "crew_frac": d["crew_frac"], "ammo": d["ammo"],
		"ratio": d["ratio"], "lost_frac": d["lost_frac"], "can_escape": d["can_escape"],
		"state": String(state), "profile": profile_id}


## 战术层（士气没出事时）：[状态, 理由]
func _tactical(d: Dictionary) -> Array:
	var ratio := float(d["ratio"])
	var br := float(profile["board_ratio"])
	if _reboard_cd > 0.0:
		if state == BOARD:
			return [BROADSIDE, _cd_reason]
	else:
		var why := ""
		if ratio >= br:
			why = "人多势众，逼近接舷"
		elif float(d["ammo"]) <= AMMO_LOW and ratio >= float(profile["desperate"]):
			why = "矢石将尽，改谋接舷"  # 不贴就只能走：拼一把
		elif float(d["target_hull"]) <= 0.35 and ratio >= br * 0.75:
			why = "敌船已残，趁势抢船"  # 赶在它沉之前抢下来
		elif float(d["target_speed"]) < 35.0 and ratio >= br * 0.85 and float(d["dist"]) < 520.0:
			why = "敌船停驶，趁势接舷"  # 停着的好钩，可甲板上照样要打
		elif state == BOARD and ratio >= br - 0.3:
			why = reason  # 迟滞：比值掉到门槛下 0.3 才退回炮战
		if why != "":
			return [BOARD, why]
		if state == BOARD:
			return [BROADSIDE, "敌众我寡，退回炮战"]
	if float(d["dist"]) > ENGAGE_DIST:
		return [APPROACH, "敌在射程外，拉近接敌"]
	var dist := float(d["dist"])
	var upwind := float(d["upwind"])
	var can_weather := float(d["wind_strength"]) >= 40.0 and _weather_spent < WEATHER_TIMEOUT * float(profile["gauge"])
	if state == WEATHER:
		if not can_weather:
			return [BROADSIDE, "抢风不成，就地接战"]
		if dist < WEATHER_MIN_DIST:
			return [BROADSIDE, "敌船逼近，就地接战"]
		if upwind >= WEATHER_OK:
			return [BROADSIDE, "已占上风，横舷接战"]
		return [WEATHER, reason]
	# 进抢风比退出多要 WEATHER_REENTER 的距离：免得在逼近线上一进一退
	if can_weather and dist >= WEATHER_MIN_DIST + WEATHER_REENTER and upwind < WEATHER_WANT:
		return [WEATHER, "敌占上风，先抢风头"]
	return [BROADSIDE, "占定舷位，横舷接战"]


func _set_state(st: StringName, why: String) -> void:
	if st == state:
		return
	prev_state = state
	state = st
	reason = why
	_dwell = 0.0
	history.append([snappedf(_time, 0.01), String(st), why])
	if history.size() > 32:
		history.pop_front()


# ── 出舵令 ───────────────────────────────────────────

func _orders(s: Dictionary, delta: float) -> Dictionary:
	var g := _g
	var pos: Vector2 = s.get("pos", Vector2.ZERO)
	var tp: Vector2 = s.get("target_pos", pos)
	var tv: Vector2 = s.get("target_vel", Vector2.ZERO)
	var heading: Vector2 = s.get("heading", Vector2.UP)
	var up: Vector2 = g["up"]
	var dist := float(g["dist"])
	var want := heading
	var throttle := 1.0
	var grapple := false
	var leave := false
	match state:
		APPROACH:
			var lead := clampf(dist / 400.0, 0.0, 2.0)
			want = _sailable((tp + tv * lead + up * 200.0 - pos).normalized())
		WEATHER:
			var lat := up.orthogonal()
			if lat.dot(pos - tp) < 0.0:
				lat = -lat
			want = _sailable((tp + up * WEATHER_STANDOFF + lat * WEATHER_PASS - pos).normalized())
		BROADSIDE:
			_side = _pick_side(s, g)
			want = _sailable(beam_heading(g["dir_t"], _side, _range_open(dist)))
			throttle = 0.75  # 减帆稳住射台
		BOARD:
			want = _board_heading(s, g)
			if dist <= 260.0:
				var near_drive := maxf(_drive_factor(want, s), 0.05)
				throttle = clampf((tv.length() + 40.0) / (float(s.get("max_speed", 250.0)) * near_drive), 0.25, 1.0)  # 并舷同速
			var frozen := bool(s.get("frozen", false)) or bool(s.get("host_boarding", false))
			grapple = not frozen and _grapple_cd <= 0.0 and dist <= GRAPPLE_RANGE \
				and float(g["rel_speed"]) <= GRAPPLE_REL_SPEED
		DISENGAGE:
			want = _flee_heading(s, g)
			# 追的窗口（pursue_window）：离场线拖后一程——敌半帆逃时本船满帆多半来得及贴钩；关开关复制旧口径
			leave = dist >= ESCAPE_DIST + (PURSUE_DIST_PAD if _pursue_on(s) else 0.0)
			leave = leave and not bool(s.get("frozen", false))
		STRIKE:
			throttle = 0.0
	if want.length() < 0.01:
		want = heading
	var drive := _drive_factor(want, s)
	_row(want, throttle, s, delta)
	var ws := float(s.get("wind_strength", 80.0))
	var leeway := 0.12 if state == STRIKE else 0.22 * throttle
	var current: Vector2 = s.get("current", Vector2.ZERO)
	return {"heading": want, "throttle": throttle, "drive": drive,
		"drift": g["wind"] * ws * leeway + current,
		"grapple": grapple, "leave": leave, "state": state, "morale": reported_morale()}


## 目标压在 side 舷正横的航向：side +1 右舷、-1 左舷；open > 0 背离目标拉开射距，< 0 靠拢
static func beam_heading(dir_to_target: Vector2, side: int, open: float) -> Vector2:
	return dir_to_target.rotated(-float(side) * (PI * 0.5 + open))


## 射距带外时偏多少：太近背离、太远靠拢，最多 0.5 rad。矢石将尽时带的远边收到 SAVE_RANGE − SAVE_MARGIN：惜弹只在 SAVE_RANGE 内放，得靠上去
func _range_open(dist: float) -> float:
	var far := RANGE_MAX if ammo_frac() > AMMO_LOW else SAVE_RANGE - SAVE_MARGIN
	if dist < RANGE_MIN:
		return clampf((RANGE_MIN - dist) / 200.0, 0.0, 0.5)
	if dist > far:
		return -clampf((dist - far) / 300.0, 0.0, 0.5)
	return 0.0


## 挑一舷：转舵少、那舷装好了、那个航向走得动的优先；占着上风时，绕着敌船转会往下风掉，
## 那一舷的航向一带下风就记代价——宁可调头换另一舷，在上风来回打（不然绕半圈丢了风头又得重抢）。现舷有惯性，别的明显更好才换
func _pick_side(s: Dictionary, g: Dictionary) -> int:
	var heading: Vector2 = s.get("heading", Vector2.UP)
	var best := _side
	var best_cost := INF
	for side in [-1, 1]:
		var h := beam_heading(g["dir_t"], side, _range_open(float(g["dist"])))
		var cost := absf(heading.angle_to(h)) / PI
		cost += float(_side_reload[side]) * 0.18
		if _drive_factor(h, s) < 0.2:
			cost += 0.8
		if float(g["upwind"]) < 0.75:
			cost += 0.9 * float(profile["gauge"]) * maxf(0.0, h.dot(g["wind"]) - 0.15)
		if side == _side:
			cost -= 0.3
		if cost < best_cost:
			best_cost = cost
			best = side
	return best


## 接舷：远了抢前截（按对方航速取提前量），近了抢到对方舷侧、同向并上去
func _board_heading(s: Dictionary, g: Dictionary) -> Vector2:
	var pos: Vector2 = s.get("pos", Vector2.ZERO)
	var tp: Vector2 = s.get("target_pos", pos)
	var tv: Vector2 = s.get("target_vel", Vector2.ZERO)
	var dist := float(g["dist"])
	if dist > 260.0:
		var closing := maxf(float(s.get("max_speed", 250.0)) * 0.6, 80.0)
		var lead := clampf(dist / closing, 0.0, 2.5)
		return _sailable((tp + tv * lead - pos).normalized())
	var th: Vector2 = s.get("target_heading", g["dir_t"])
	var n := th.orthogonal()
	if n.dot(pos - tp) < 0.0:
		n = -n
	var slot := tp + n * 70.0 + th * 20.0 + tv * 0.4
	var w := clampf(1.0 - dist / 260.0, 0.0, 1.0) * 0.6
	var h := (slot - pos).normalized() * (1.0 - w) + th * w
	return _sailable(h.normalized() if h.length() > 0.01 else th)


## 脱离航向：一圈 24 个航向里挑拉开最快的——我方该航向的航速，减去对方照直追来的一半航速（对方按帆船估），
## 乘背离敌船的分量；只挑背着敌船走的，现航向略占便宜（不来回摆）。多桨船由此自然挑逆风摇橹（帆船追不上来），
## 帆船多半顺风放走；敌船正在下风时帆船只能横风走。
func _flee_heading(s: Dictionary, g: Dictionary) -> Vector2:
	var away: Vector2 = -g["dir_t"]
	var heading: Vector2 = s.get("heading", away)
	var my_max := float(s.get("max_speed", 250.0))
	var their_max := float(s.get("target_max_speed", 300.0))
	var ws := float(s.get("wind_strength", 80.0))
	var best := away
	var best_score := -INF
	for i in 24:
		var h := Vector2.UP.rotated(TAU * float(i) / 24.0)
		var off := h.dot(away)
		if off < 0.2:
			continue
		var gain := my_max * _drive_factor(h, s) - 0.5 * their_max * builtin_sail_factor(h, g["wind"], ws)
		var score := gain * (0.3 + off) + 8.0 * h.dot(heading)
		if score > best_score:
			best_score = score
			best = h
	return best


## 想去的方向顶风走不动时改走近迎风（左右两舷择一，换舷要穿风、另一舷明显更好才换）；划得动的多桨船直去
func _sailable(desired: Vector2) -> Vector2:
	var wind: Vector2 = _g.get("wind", Vector2.ZERO)
	if wind == Vector2.ZERO or _row_power() >= 0.4 or desired.dot(wind) >= -cos(TACK):
		return desired
	var up := -wind
	var h1 := up.rotated(TACK)
	var h2 := up.rotated(-TACK)
	var use_1 := desired.dot(h1) >= desired.dot(h2)
	if _tack != 0:
		var cur_1 := _tack > 0
		var cur := h1 if cur_1 else h2
		var other := h2 if cur_1 else h1
		use_1 = cur_1 if desired.dot(other) < desired.dot(cur) + 0.25 else not cur_1
	_tack = 1 if use_1 else -1
	return h1 if use_1 else h2


## 该航向的航速系数：帆（外部机动模型或内置受风角）与桨取大
func _drive_factor(heading: Vector2, s: Dictionary) -> float:
	var wind: Vector2 = _g.get("wind", Vector2.ZERO)
	var ws := float(s.get("wind_strength", 80.0))
	var sail := builtin_sail_factor(heading, wind, ws)
	var ext = _call_hook("speed_factor", [heading, wind, ws])
	if typeof(ext) == TYPE_FLOAT or typeof(ext) == TYPE_INT:
		sail = clampf(float(ext), 0.05, 1.5)
	return maxf(sail, _row_power())


func _row_power() -> float:
	return oars * (0.5 + 0.5 * _stamina)


## 桨出力比帆大、又要快走时是在划桨：耗力；否则歇着回力
func _row(heading: Vector2, throttle: float, s: Dictionary, delta: float) -> void:
	var wind: Vector2 = _g.get("wind", Vector2.ZERO)
	var sail := builtin_sail_factor(heading, wind, float(s.get("wind_strength", 80.0)))
	if throttle >= 0.6 and _row_power() > sail + 0.02:
		_stamina = maxf(0.0, _stamina - delta / STAMINA_DRAIN)
	else:
		_stamina = minf(1.0, _stamina + delta / STAMINA_REST)


## 追的窗口此刻开吗：局面键优先（PirateShip 转进的「开关动过」），缺席看本成员（WorldMap 开局写死）
func _pursue_on(s: Dictionary) -> bool:
	if s.has("pursue_window"):
		return bool(s["pursue_window"])
	return pursue_window


## 内置受风角：c = 船首向·风去向（1 顺风、0 横风、-1 顶风）。横风约 0.62、顺风 1；离风源 63° 内（近迎风再往里）掉到 0.1 顶风停滞。
## 风力 80 约 ×1；无风只剩 0.12（帆船漂着）
static func builtin_sail_factor(heading: Vector2, wind: Vector2, strength: float) -> float:
	if wind == Vector2.ZERO or strength <= 1.0:
		return 0.12
	var c := heading.normalized().dot(wind.normalized())
	var f := 0.62 + 0.38 * c if c >= 0.0 else maxf(0.1, 0.62 + 0.9 * c)
	return f * clampf(0.55 + strength / 180.0, 0.6, 1.25)


# ── 可选外部 API ─────────────────────────────────────

## 探针 / 装配件显式指定某项能力由谁提供；obj 传 null 即钉回内置
func set_provider(id: String, obj: Object, method: String) -> void:
	_injected[id] = [obj, method]


## 全部钉回内置（self_check 用：不让仓里恰好在的外部模块干扰判例）
func force_builtin() -> void:
	_builtin_only = true
	_injected.clear()


## 各项能力此刻由谁提供：「内置」或「模块名.方法名」
func providers() -> Dictionary:
	var out := {}
	for id in HOOKS:
		var h := _resolve(id)
		var obj = h[0]
		out[id] = "内置" if obj == null else "%s.%s" % [_obj_name(obj), h[1]]
	return out


static func _obj_name(obj: Object) -> String:
	if obj is Script:
		var p := (obj as Script).resource_path
		return p.get_file().get_basename() if p != "" else "注入脚本"
	return obj.get_class()


## 提供方在用吗：有零参的静态 is_live()（CombatMorale：数据读不到即整套停用、裁决恒空）就问它，没有这支当它在用
func _hook_live(id: String) -> bool:
	var obj = _resolve(id)[0]
	if obj == null:
		return false
	if obj is Script:
		for m in (obj as Script).get_script_method_list():
			if str(m["name"]) == "is_live":
				return (m.get("args", []) as Array).is_empty() and bool((obj as Object).call("is_live"))
		return true
	return not obj.has_method("is_live") or bool(obj.call("is_live"))


func _call_hook(id: String, args: Array) -> Variant:
	var h := _resolve(id)
	if h[0] == null:
		return null
	return (h[0] as Object).callv(h[1], args)


func _resolve(id: String) -> Array:
	if _injected.has(id):
		return _injected[id]
	if _builtin_only:
		return [null, ""]
	if not _hook_cache.has(id):
		_hook_cache[id] = _find_hook(HOOKS[id])
	return _hook_cache[id]


## 模块在、候选名里有静态方法且形参个数、类型逐个对上，才算数
static func _find_hook(spec: Array) -> Array:
	var path: String = spec[0]
	if not ResourceLoader.exists(path):
		return [null, ""]
	var scr = load(path)
	if not (scr is Script):
		return [null, ""]
	var methods := {}
	for m in (scr as Script).get_script_method_list():
		methods[str(m["name"])] = m
	for name in spec[1]:
		if methods.has(name) and _signature_ok(methods[name], spec[2]):
			return [scr, name]
	return [null, ""]


static func _signature_ok(m: Dictionary, types: Array) -> bool:
	if (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) == 0:
		return false
	var args: Array = m.get("args", [])
	if args.size() != types.size():
		return false
	for i in args.size():
		if int(args[i].get("type", TYPE_NIL)) != int(types[i]):
			return false
	return true


func _read_morale_consts() -> void:
	if not ResourceLoader.exists(MORALE_PATH):
		return
	var scr = load(MORALE_PATH)
	if not (scr is Script):
		return
	var consts: Dictionary = (scr as Script).get_script_constant_map()
	for key in MORALE_CONSTS:
		for cname in MORALE_CONSTS[key]:
			var v = consts.get(cname)
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				continue
			var x := float(v) * (100.0 if float(v) <= 1.0 else 1.0)
			if x > 0.0 and x < 100.0:
				if key == "rout":
					rout_line = x
				else:
					strike_line = x
				break


# ── 自检（假局势逐条过状态机；返回不合的条目，空即全对）─────────────

static func self_check() -> Array:
	var bad: Array = []
	var ai = _fresh()
	ai.tick(_sit({"target_pos": Vector2(0, -1200)}), 0.1)
	_want(bad, ai.state == APPROACH, "射程外应接近（得 %s）" % ai.state)
	# 北风（风去向 +y）：我在敌南面 = 下风
	ai = _fresh()
	ai.tick(_sit({"pos": Vector2(0, 400)}), 0.1)
	_want(bad, ai.state == WEATHER, "敌占上风应先抢风（得 %s）" % ai.state)
	ai = _fresh()
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	_want(bad, ai.state == BROADSIDE, "已在上风应横舷接战（得 %s）" % ai.state)
	ai._s["frozen"] = false
	_want(bad, ai.fire_side(PI * 0.5, 400.0) == 1 and ai.fire_side(-PI * 0.5, 400.0) == -1,
		"目标在右舷正横放右舷、左舷正横放左舷")
	_want(bad, ai.fire_side(0.2, 400.0) == 0 and ai.fire_side(PI * 0.5, 1200.0) == 0, "不在正横 / 射程外不放")
	ai._s["frozen"] = true
	_want(bad, ai.fire_side(PI * 0.5, 400.0) == 0, "布景冻结不放")
	ai = _fresh("pirate_boat")
	ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 150.0, "target_strength": 50.0}), 0.1)
	_want(bad, ai.state == BOARD and ai.reason.find("人多势众") >= 0, "海寇人多应接舷（得 %s %s）" % [ai.state, ai.reason])
	ai = _fresh()
	ai.volleys = 1
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	_want(bad, ai.state == BOARD and ai.reason.find("矢石将尽") >= 0, "矢石将尽应改接舷（得 %s %s）" % [ai.state, ai.reason])
	ai = _fresh()
	var o: Dictionary = ai.tick(_sit({"pos": Vector2(0, -100), "own_strength": 200.0, "target_strength": 50.0}), 0.1)
	_want(bad, ai.state == BOARD and bool(o["grapple"]), "贴舷、同速、占优应抛钩")
	o = ai.tick(_sit({"pos": Vector2(0, -100), "own_strength": 200.0, "target_strength": 50.0,
		"target_vel": Vector2(400, 0)}), 0.1)
	_want(bad, not bool(o["grapple"]), "相对速度太大不抛钩")
	o = ai.tick(_sit({"pos": Vector2(0, -100), "own_strength": 200.0, "target_strength": 50.0, "frozen": true}), 0.5)
	_want(bad, not bool(o["grapple"]), "布景冻结不抛钩")
	ai = _fresh("pirate_boat", 30.0)
	ai.tick(_sit({"pos": Vector2(0, -400), "morale": 30}), 0.1)
	_want(bad, ai.state == DISENGAGE, "海寇士气 30 应脱离（得 %s）" % ai.state)
	for i in 4:
		ai.tick(_sit({"pos": Vector2(0, -400), "morale": 90}), 0.5)  # 过了 MIN_DWELL 才算数
	_want(bad, ai.state == DISENGAGE, "脱离是粘的：士气回升也不回头（得 %s）" % ai.state)
	o = ai.tick(_sit({"pos": Vector2(0, -1600), "morale": 90}), 0.5)
	_want(bad, bool(o["leave"]), "脱离拉开到 %d 应离场" % int(ESCAPE_DIST))
	o = ai.tick(_sit({"pos": Vector2(0, -1600), "morale": 90, "frozen": true}), 0.5)
	_want(bad, not bool(o["leave"]), "布景冻结不离场")
	ai = _fresh("fu_ship_medium", 8.0)
	o = ai.tick(_sit({"pos": Vector2(0, -400), "morale": 8}), 0.1)
	_want(bad, ai.state == STRIKE and float(o["throttle"]) == 0.0, "士气崩溃应降幡、落帆（得 %s）" % ai.state)
	ai._s["frozen"] = false
	_want(bad, ai.fire_side(PI * 0.5, 300.0) == 0, "降了不放")
	for i in 4:
		ai.tick(_sit({"pos": Vector2(0, -400), "morale": 90}), 0.5)
	_want(bad, ai.state == STRIKE, "降幡不回头（得 %s）" % ai.state)
	# 帆船在敌上风、重创、士气 38：往下风逃跑不过满帆的对方 → 降
	ai = _fresh("fu_ship_medium", 38.0)
	ai.tick(_sit({"pos": Vector2(0, -400), "morale": 38, "hull": 0.2, "target_max_speed": 320.0}), 0.1)
	_want(bad, ai.state == STRIKE, "重创又逃不脱应降（得 %s %s）" % [ai.state, ai.reason])
	# 回帆抢船：溃因还在（士气低）就不回头，免得回帆一拍、溃走一拍来回抖；溃因没了、敌船将沉才回
	ai = _fresh("fu_ship_medium", 20.0)
	ai.tick(_sit({"pos": Vector2(0, -400), "morale": 20}), 0.1)
	var sinking := {"pos": Vector2(0, -400), "morale": 20, "target_hull": 0.1, "own_strength": 200.0, "target_strength": 50.0}
	ai.tick(_sit(sinking), 0.5)
	_want(bad, ai.state == DISENGAGE, "溃因还在，敌船将沉也不回帆（得 %s）" % ai.state)
	sinking["morale"] = 60
	ai.tick(_sit(sinking), 0.5)
	_want(bad, ai.state == BOARD and ai.reason.find("回帆") >= 0, "溃因没了、敌船将沉才回帆抢船（得 %s %s）" % [ai.state, ai.reason])
	# 多桨船同样处境：逆风摇橹逃得掉 → 脱离
	ai = _fresh("pirate_boat", 38.0)
	ai.tick(_sit({"pos": Vector2(0, -400), "morale": 38, "hull": 0.2, "target_max_speed": 320.0}), 0.1)
	_want(bad, ai.state == DISENGAGE, "多桨船重创逃得掉应脱离（得 %s %s）" % [ai.state, ai.reason])
	# 抢风封顶：一直在下风，抢满预算就就地接战
	ai = _fresh()
	for i in 40:
		ai.tick(_sit({"pos": Vector2(0, 400)}), 0.4)
	_want(bad, ai.state == BROADSIDE and ai.reason.find("抢风不成") >= 0, "抢风超时应就地接战（得 %s %s）" % [ai.state, ai.reason])
	# 抢风中被逼近 → 就地接战（理由不能写成「已占上风」）；逼近线内外不来回：拉开到 +REENTER 以前不再抢
	ai = _fresh()
	ai.tick(_sit({"pos": Vector2(0, 400)}), 0.1)
	ai.tick(_sit({"pos": Vector2(0, 200)}), 1.3)
	_want(bad, ai.state == BROADSIDE and ai.reason.find("逼近") >= 0, "抢风中被逼近应就地接战（得 %s %s）" % [ai.state, ai.reason])
	ai.tick(_sit({"pos": Vector2(0, 300)}), 1.3)
	_want(bad, ai.state == BROADSIDE, "逼近线外 %d 以内不回头抢风（得 %s）" % [int(WEATHER_MIN_DIST + WEATHER_REENTER), ai.state])
	# 防抖：刚进舷炮，比值一冒头也要呆满 MIN_DWELL 再接舷
	ai = _fresh()
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 200.0, "target_strength": 50.0}), 0.45)
	_want(bad, ai.state == BROADSIDE, "未满 MIN_DWELL 不换状态")
	ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 200.0, "target_strength": 50.0}), 1.0)
	_want(bad, ai.state == BOARD, "满 MIN_DWELL 后该接舷了（得 %s）" % ai.state)
	# 矢石将尽、白刃比又不够拼接舷：守的射距带收进惜弹射距——相距 400 要往敌船靠（满弹在带内横着守、不靠）
	ai = _fresh()
	o = ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 40.0}), 0.1)
	var hold := (o["heading"] as Vector2).dot(Vector2(0, 1))
	ai = _fresh()
	ai.volleys = 1
	o = ai.tick(_sit({"pos": Vector2(0, -400), "own_strength": 40.0}), 0.1)
	var close_in := (o["heading"] as Vector2).dot(Vector2(0, 1))
	_want(bad, ai.state == BROADSIDE and close_in > 0.15 and absf(hold) < 0.05,
		"矢石将尽守进惜弹射距 %d：相距 400 往敌船靠（得 %s，船首向敌分量 %.2f；满弹 %.2f）" % [int(SAVE_RANGE), ai.state, close_in, hold])
	# 矢石打光：白刃比够得上本档案拼接舷的线（desperate）就贴、够不上就走，不在中间兜空舷——哨船线 1.3、比 1.0 该走；海寇线 0.85、比 1.0 该贴
	ai = _fresh("yuan_patrol")
	ai.volleys = 0
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	var dry_patrol := "%s %s" % [ai.state, ai.reason]
	var patrol_left: bool = ai.state == DISENGAGE and ai.reason.find("矢石告罄") >= 0
	ai = _fresh("pirate_boat")
	ai.volleys = 0
	ai.tick(_sit({"pos": Vector2(0, -400)}), 0.1)
	_want(bad, patrol_left and ai.state == BOARD,
		"矢石打光：够不上拼接舷就走、够得上就贴（哨船比 1.0 得 %s；海寇比 1.0 得 %s %s）" % [dry_patrol, ai.state, ai.reason])
	# 受风角与桨
	var w := Vector2(0, 1)
	var run := builtin_sail_factor(w, w, 80.0)
	var beam := builtin_sail_factor(Vector2(1, 0), w, 80.0)
	var close := builtin_sail_factor(-w.rotated(TACK), w, 80.0)
	var irons := builtin_sail_factor(-w, w, 80.0)
	_want(bad, irons < close and close < beam and beam < run, "受风角：顶风 < 近迎风 < 横风 < 顺风")
	var oar = _fresh("pirate_boat")
	var sail = _fresh()
	oar._g = {"wind": w}
	sail._g = {"wind": w}
	_want(bad, oar._drive_factor(-w, {}) > 0.5 and sail._drive_factor(-w, {}) < 0.2, "多桨船逆风摇得动，帆船不行")
	var h := beam_heading(Vector2.RIGHT, 1, 0.0)
	_want(bad, absf(h.angle_to(Vector2.RIGHT) - PI * 0.5) < 0.01, "右舷正横航向：目标在船首右 90°")
	return bad


static func _fresh(ship_type := "fu_ship_medium", morale0 := 60.0):
	var ai = new()
	ai.force_builtin()
	ai.setup(ship_type, ship_type, 1.0, 60, morale0, 2)
	return ai


## 假局势：敌（玩家）在原点、船首朝北不动；北风 80；我 60 人满员满血
static func _sit(over: Dictionary) -> Dictionary:
	var s := {
		"pos": Vector2(0, -400), "heading": Vector2.RIGHT, "vel": Vector2.ZERO, "max_speed": 250.0,
		"target_pos": Vector2.ZERO, "target_vel": Vector2(0, -60), "target_heading": Vector2.UP,
		"target_max_speed": 300.0, "target_hull": 1.0,
		"wind": Vector2(0, 1), "wind_strength": 80.0, "current": Vector2.ZERO,
		"hull": 1.0, "crew": 60, "morale": 60, "own_strength": 50.0, "target_strength": 50.0,
		"consorts": 0, "consorts_gone": 0, "consorts_struck": 0, "host_boarding": false, "frozen": false,
	}
	for k in over:
		s[k] = over[k]
	return s


static func _want(bad: Array, ok: bool, what: String) -> void:
	if not ok:
		bad.append(what)
