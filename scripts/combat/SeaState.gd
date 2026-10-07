class_name SeaState
extends RefCounted
## 海战海况（lane combat02）：风（来向 / 风力 / 阵风 / 风向缓转）+ 流（季风海流、定向洋流、潮流）。
## WorldMap 开战时按月令季风与海域建一份（setup），逐物理帧 step(dt)；ManeuverModel 拿它的读数算帆向、风压差与流压差。
## 本件只存数、只演化：不碰节点、不读 autoload——季风方位 / 强度由调用方从 Calendar 取来传入，探针可以直接 new 一份。
##
## 方位与 Calendar 同一口径：方位角 0 = 正北、90 = 正东（顺时针）；风按「吹向」存（Calendar.NE_MONSOON_BEARING = 225
## 即东北风吹向西南）。海战场面 −y 为北、+x 为东，吹向单位向量 = (sin b, −cos b)，与 Ship.wind_vector 同义
## （Vector2(0, 1) = 吹向正南 = 北风）。叫法照舟师：风按来向叫（东北风），流按去向叫（流向西南）。
##
## 雷暴大风（lane w53-17 第一期「大风两散」）：setup 时若本场风均值过了种子线（GALE_SEED 那个常量，约七成风），
## 本场记雷暴大风，WorldMap 开战即收「两散」。作战的风上限不按数据曲线的七级线（140）——那场风按骤风攥到 130 仍挂着
## 六级风可战名，七级水上却照打；所以改按本场风均值过种子线（98）来迸，不按七级风速线。
##
## 火长提前报风（lane w53-17 二期，数据 officer_effects.huozhang.wind_shift_warn_s 5，报的是「风向要转」）：
## 风向缓转的 OU 噪声按 FORECAST_DT 秒一步预滚成一段缓冲（FORECAST_S 秒），step 不再现掷噪声，改逐半秒从缓冲
## 里取——所以 SeaState 事先真知道将来 FORECAST_S 秒里风向怎么走（wind_bearing_to_in(s)），预报说的「要转」
## 到点真转。预滚在 setup / force_wind 那一下算完；读数（wind_to / wind_speed / snapshot）的轨迹与改前
## 同一条分布（同种子逐帧一致——缓冲只是把将来才掷的噪声挪到开局一口气掷）。
##
## 读数（别的模块只读，不改）：wind_to 吹向单位向量 · wind_speed 风力（同 Ship.wind_strength 量纲）· wind_velocity()
##   · current_at(pos) 流速向量 px/s · wind_name()「东北风」· current_desc()「落潮　流向东南」· snapshot() 全部读数。
## 当前这一场：WorldMap 开战 bind_active、出战 / 离树 clear_active；别处 preload 本件后用 SeaState.active() 取，没开战为 null。

## 风力上下限。上限压在 Ship._process_storm_damage 的 150 以下：海战固定无风暴伤（tools/combat_probe_stage.gd 头注释一），
## 阵风也顶不过去
const WIND_CAP := 130.0
const WIND_FLOOR := 28.0
## 风向缓转幅度（度，距本场主风向）；转换期（三、四、九月）风向每场随机、摆得更大
const VEER_DEG := 14.0
const VEER_DEG_TRANSITION := 32.0
## 阵风幅度（风力比例）
const GUST_AMP := 0.14
## 缓转 / 阵风的相关时间（秒）：风向慢慢摆，阵风一阵一阵
const VEER_TAU := 24.0
const GUST_TAU := 5.0
## 海流合速上限（px/s）：旗舰满帆对水约 230–290，流取一成到一成半，显得出又不喧宾夺主
const CURRENT_CAP := 42.0
## 「雷暴大风」判定的线（开战那一刻的本场风均值）。寻常远航的季风场（盛季 80 × 1.0 × 上浮 1.12 ≤ 90）
## 照这个线记不出来；剧情递的风暴定场（pending_battle.wind_strength 或逼出的举年择月）才召得出来。
## 作战上限不按 wind_level_rule 折的七级线（140）：风上限 WIND_CAP 130，连阵风峰值都到不了七级线，
## 数据里「七级以上不能战」那条永远迸不出来——落成「开场本该收『两散』的风」这同一档。
const GALE_SEED_WIND := 98.0
## 「风暴海」起步风：base_strength ≥ 它才算风暴定场；寻常远航（WorldMap.base_wind_strength 80）走不到
const GALE_BASE_WIND := 100.0
## 火长「提前报风」：WorldMap 按（GALE_WARN_S × Crew.level_of("huozhang")）秒看风向前景（wind_bearing_to_in）
const GALE_WARN_S := 5.0
## 风向预滚：缓冲总长 / 步长。30 秒够三级火长（15 秒）翻一倍；半秒一步对 VEER_TAU 24 秒的缓转足够细
const FORECAST_S := 30.0
const FORECAST_DT := 0.5
## 潮时相位绝对值小于它算平潮（潮流几近停）
const SLACK := 0.3

## 海域流况。keys：sea_name 里认的港名字样（SeaChart._battle_sea_name 写「泉州外海」「澎湖外海」……）。
## season：季风吹出的顺岸海流 {ne 东北季风 / sw 西南季风: [流向方位, 流速]}，转换期没有；
## steady：终年定向洋流 [流向方位, 流速, 叫法]；tide：[涨潮流向方位, 流速]，落潮反向。流速单位 px/s。
## 南岛海道那股借《元史·瑠求传》的「落漈」（近瑠求「水趋下而不回」），东海外洋借今名黑潮。
const REGIONS := [
	{"id": "min", "name": "闽海", "keys": ["泉州", "漳州", "兴化", "福州"],
		"season": {"ne": [215.0, 12.0], "sw": [35.0, 9.0]}, "tide": [300.0, 20.0]},
	{"id": "penghu", "name": "澎湖水道", "keys": ["澎湖"],
		"season": {"ne": [200.0, 24.0], "sw": [20.0, 22.0]}, "tide": [0.0, 14.0]},
	{"id": "zhe", "name": "浙海", "keys": ["温州", "明州", "庆元"],
		"season": {"ne": [205.0, 10.0], "sw": [30.0, 8.0]}, "tide": [290.0, 26.0]},
	{"id": "luoji", "name": "南岛海道", "keys": ["南岛", "流求", "琉球"],
		"steady": [40.0, 30.0, "落漈"], "tide": [300.0, 8.0]},
	{"id": "kuroshio", "name": "东海外洋", "keys": ["萨摩", "博多", "耽罗"],
		"steady": [45.0, 20.0, "黑潮"], "tide": [320.0, 10.0]},
	{"id": "nanhai", "name": "南海", "keys": ["广州", "占城"],
		"season": {"ne": [225.0, 16.0], "sw": [45.0, 14.0]}, "tide": [330.0, 10.0]},
]
## 认不出海域（「外海」、探针布景）：只有一股潮流，流向每场随机
const OPEN_SEA := {"id": "open", "name": "外海", "tide": [-1.0, 10.0]}

const DIR8 := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]

## 当前这一场海战的 SeaState（WorldMap 开战 bind_active、出战 clear_active）
static var _active = null

var wind_to := Vector2(0, 1)
var wind_speed := 80.0
var wind_mean := 80.0
## ne 东北季风 / sw 西南季风 / mid 转换期
var monsoon := "mid"
var region_id := "open"
var region_name := "外海"
var current := Vector2.ZERO
## 当前流以哪一股为主：「涨潮」「落潮」「平潮」「季风流」「落漈」「黑潮」
var current_kind := "平潮"
## 本场潮时：1 涨潮最急 … 0 平潮 … −1 落潮最急（一场海战只几分钟，潮流视作不变）
var tide_phase := 0.0
## lane w53-17：本场算过雷暴大风（开局风均值过了种子线，WorldMap 照收「两散」）。
## 即便后来风转小也不再变回——种子量出的「这场风是这个势」。
var gale := false
## 本场主风向（吹向方位，度）、缓转幅度、当前缓转（度）与阵风（标准差为 1 的无量纲量）
var _base_bearing := 180.0
var _veer_amp := VEER_DEG
var _veer := 0.0
var _gust := 0.0
var _rng := RandomNumberGenerator.new()
## 预滚缓冲：将来 FORECAST_S 秒里 _veer / _gust 每 FORECAST_DT 秒一步的值；_forecast_i 是走到的步数（小数插值）
var _veer_path := PackedFloat32Array()
var _gust_path := PackedFloat32Array()
var _forecast_i := 0.0


## 按月令季风与海域定本场海况。monsoon_bearing：Calendar.wind_bearing_of(月)（吹向方位，转换期 −1）；
## monsoon_strength：Calendar.monsoon_strength_of(月)（0.3–1.0）；base_strength：参考风力（WorldMap.base_wind_strength）；
## sea_name：pending_battle.sea_name；rng_seed < 0 随机，给定则可复现。
func setup(monsoon_bearing: float, monsoon_strength: float, base_strength: float, sea_name := "", rng_seed := -1) -> void:
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if monsoon_bearing < 0.0:
		monsoon = "mid"
		_base_bearing = _rng.randf_range(0.0, 360.0)
		_veer_amp = VEER_DEG_TRANSITION
	else:
		var toward_sw := absf(angle_difference(deg_to_rad(monsoon_bearing), deg_to_rad(225.0))) < PI / 2.0
		monsoon = "ne" if toward_sw else "sw"
		_base_bearing = fposmod(monsoon_bearing + _rng.randf_range(-12.0, 12.0), 360.0)
		_veer_amp = VEER_DEG
	# 季风盛时风力约为参考值，转换期约七成；每场再上下浮一成多
	var strength := clampf(monsoon_strength, 0.0, 1.0)
	wind_mean = clampf(base_strength * (0.55 + 0.45 * strength) * _rng.randf_range(0.88, 1.12), WIND_FLOOR, WIND_CAP)
	_veer = _rng.randf_range(-0.5, 0.5) * _veer_amp
	_gust = 0.0
	# lane w53-17：雷暴大风判定（combat_phases.json t_gale）——开场风本均值太高才记。寻常远航的季风
	#（盛季 80 × 1.0 × 上浮 1.12 ≤ 90）照这个线记不出来；剧情 pending_battle 递的「gale_wind 定场」、
	# 本探针逼出的「举年择月」才召得出来。force_wind 是剧情 / 探针定场，不动 gale（探针另走 derive 推演的盘档）。
	gale = wind_mean >= GALE_SEED_WIND and float(monsoon_strength) >= 0.9 and base_strength >= GALE_BASE_WIND
	_setup_current(sea_name)
	_preroll_forecast()
	_apply_wind()


## 剧情 / 探针定风：bearing_to 为吹向方位（度），strength 为风力（封顶 WIND_CAP）；缓转与阵风照常叠在上面。
## 递到雷暴线的（pending_battle.wind_strength 的风暴定场）一并记 gale——setup 的盘面线越不过的场合
## （盛季远航 80 走不到 98），剧情照样递得出大风。
func force_wind(bearing_to: float, strength: float) -> void:
	_base_bearing = fposmod(bearing_to, 360.0)
	wind_mean = clampf(strength, WIND_FLOOR, WIND_CAP)
	_veer = 0.0
	_gust = 0.0
	gale = gale or wind_mean >= GALE_SEED_WIND
	_preroll_forecast()
	_apply_wind()


## 定流：flow 为流速向量（px/s，封顶 CURRENT_CAP），kind 为叫法
func force_current(flow: Vector2, kind := "季风流") -> void:
	current = flow.limit_length(CURRENT_CAP)
	current_kind = kind


## 推进 dt 秒：风向缓转、阵风起落（Ornstein–Uhlenbeck，向本场主风回拉）；流一场之内不变。
## 噪声不再现掷：setup / force_wind 那一下已按 FORECAST_DT 秒一步预滚成缓冲，这里逐 dt 从缓冲里取
## （非整步线性插值）。预滚耗尽的尾档（开战超过 FORECAST_S 秒）回落成开局掷定的末档常量——
## 风不再继续转；火长报的「转」都发生在预滚窗内。
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_forecast_i = minf(_forecast_i + dt / FORECAST_DT, float(maxi(0, _veer_path.size() - 1)))
	_veer = _path_at(_veer_path, _forecast_i)
	_gust = _path_at(_gust_path, _forecast_i)
	_apply_wind()


## s 秒后的吹向方位（度）。两个端点用同一时刻的 _veer（step 每物理帧写下、_apply_wind 用过的那个），
## 只是 s 秒那一头按 _forecast_i + s / FORECAST_DT 的插值取——与将来 step 真走的逐帧同一轨迹。
## 超出预滚窗给窗尾——再远就是「不知道」，火长只报窗内的转（warn_s ≤ FORECAST_S 恒成立，见 GALE_WARN_S）。
func wind_bearing_to_in(s: float) -> float:
	var idx := clampf(_forecast_i + s / FORECAST_DT, 0.0, float(maxi(0, _veer_path.size() - 1)))
	return fposmod(_base_bearing + _path_at(_veer_path, idx), 360.0)


## 从当下起 s 秒内吹向要转的度数（0–180，走圆最短弧）。当下这头取 step 写下的 _veer
##（_apply_wind 用过、探针量取也认的这一拍），s 秒那头按缓冲插值取——
## 触发（WorldMap._check_gale_warn）与量取（探针「报后真转」）同走这一条式、同一基准，
## 就不会差出档位边（各按各的基准，物理帧的小数步会差出半档）。
func wind_turn_deg_in(s: float) -> float:
	var b0 := bearing_of(wind_to)
	var b1 := fposmod(_base_bearing + _path_at(_veer_path,
		clampf(_forecast_i + s / FORECAST_DT, 0.0, float(maxi(0, _veer_path.size() - 1)))), 360.0)
	return rad_to_deg(absf(angle_difference(deg_to_rad(b0), deg_to_rad(b1))))


## 风速向量（吹向 × 风力）
func wind_velocity() -> Vector2:
	return wind_to * wind_speed


## 某处的风（战场小，风场视作均匀）
func wind_at(_pos := Vector2.ZERO) -> Vector2:
	return wind_velocity()


## 某处的流速向量（px/s；战场小，流场视作均匀）
func current_at(_pos := Vector2.ZERO) -> Vector2:
	return current


## 风名（按来向，八方）：「东北风」
func wind_name() -> String:
	return "%s风" % dir8(fposmod(bearing_of(wind_to) + 180.0, 360.0))


## 风势字：微风 / 和风 / 劲风 / 强风
func wind_word() -> String:
	if wind_speed < 45.0:
		return "微风"
	if wind_speed < 70.0:
		return "和风"
	if wind_speed < 95.0:
		return "劲风"
	return "强风"


## 流况短句（顶匾用）：「落潮　流向东南」「落漈　流向东北」；流速很小写「平潮　流缓」
func current_desc() -> String:
	if current.length() < 5.0:
		return "平潮　流缓"
	return "%s　流向%s" % [current_kind, dir8(bearing_of(current))]


## 全部读数（HUD / AI / 探针）
func snapshot() -> Dictionary:
	return {
		"wind_to": wind_to,
		"wind_speed": wind_speed,
		"wind_mean": wind_mean,
		"wind_bearing_to": bearing_of(wind_to),
		"wind_name": wind_name(),
		"wind_word": wind_word(),
		"monsoon": monsoon,
		"region": region_id,
		"region_name": region_name,
		"current": current,
		"current_speed": current.length(),
		"current_kind": current_kind,
		"current_desc": current_desc(),
		"tide_phase": tide_phase,
	}


# ── 当前这一场 ────────────────────────────────────────────

static func bind_active(s) -> void:
	_active = s


## 只清 s 这一份（别的场次已换上新的就不动；s 为空不动）
static func clear_active(s) -> void:
	if s != null and is_same(_active, s):
		_active = null


static func active():
	return _active


# ── 方位换算 ──────────────────────────────────────────────

## 方位角（度）→ 屏幕单位向量（−y 为北）
static func bearing_vector(bearing_deg: float) -> Vector2:
	var r := deg_to_rad(bearing_deg)
	return Vector2(sin(r), -cos(r))


## 屏幕向量 → 方位角（度，0–360）
static func bearing_of(v: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)


## 方位角 → 八方字（「东北」）
static func dir8(bearing_deg: float) -> String:
	return DIR8[int(round(fposmod(bearing_deg, 360.0) / 45.0)) % 8]


# ── 内部 ──────────────────────────────────────────────────

## 预滚：从当下的 _veer / _gust 起，按 FORECAST_DT 秒一步把 OU 噪声滚满 FORECAST_S 秒。
## 与改前的逐帧 step 同一条 OU（同 sigma、同 tau、同 clamp），只是把「将来才掷的噪声」挪到开局一口气掷——
## 所以预报读的缓冲 = step 将来真走的值，火长报的「要转」到点真转。
func _preroll_forecast() -> void:
	var n := int(round(FORECAST_S / FORECAST_DT))
	_veer_path = PackedFloat32Array()
	_gust_path = PackedFloat32Array()
	_veer_path.append(_veer)
	_gust_path.append(_gust)
	var v := _veer
	var g := _gust
	for _i in n:
		v = clampf(_ou(v, _veer_amp, VEER_TAU, FORECAST_DT), -1.6 * _veer_amp, 1.6 * _veer_amp)
		g = clampf(_ou(g, 1.0, GUST_TAU, FORECAST_DT), -1.5, 1.5)
		_veer_path.append(v)
		_gust_path.append(g)
	_forecast_i = 0.0


## 缓冲 idx（可为小数）处的线性插值；空缓冲回 0
static func _path_at(path: PackedFloat32Array, idx: float) -> float:
	if path.is_empty():
		return 0.0
	var i := int(clampf(idx, 0.0, float(path.size() - 1)))
	var j := mini(i + 1, path.size() - 1)
	return lerpf(path[i], path[j], clampf(idx - float(i), 0.0, 1.0))


func _apply_wind() -> void:
	wind_to = bearing_vector(_base_bearing + _veer)
	wind_speed = clampf(wind_mean * (1.0 + GUST_AMP * _gust), WIND_FLOOR * 0.8, WIND_CAP)


## OU 过程一步：向 0 回拉、带噪声，稳态标准差约 sigma
func _ou(x: float, sigma: float, tau: float, dt: float) -> float:
	var a := exp(-dt / tau)
	return x * a + sigma * sqrt(1.0 - a * a) * _rng.randfn(0.0, 1.0)


func _setup_current(sea_name: String) -> void:
	var reg: Dictionary = OPEN_SEA
	for r in REGIONS:
		var hit := false
		for k in r["keys"]:
			if sea_name.find(str(k)) >= 0:
				hit = true
				break
		if hit:
			reg = r
			break
	region_id = str(reg["id"])
	region_name = str(reg["name"])
	# [流速向量, 叫法] 逐股相加；叫法取最大的一股
	var parts: Array = []
	var season: Dictionary = reg.get("season", {})
	if season.has(monsoon):
		var s: Array = season[monsoon]
		parts.append([_flow(float(s[0]), float(s[1])), "季风流"])
	if reg.has("steady"):
		var st: Array = reg["steady"]
		parts.append([_flow(float(st[0]), float(st[1])), str(st[2])])
	var td: Array = reg.get("tide", [])
	tide_phase = cos(_rng.randf() * TAU)
	if td.size() >= 2:
		var tb := float(td[0]) if float(td[0]) >= 0.0 else _rng.randf_range(0.0, 360.0)
		var kind := "平潮"
		if tide_phase >= SLACK:
			kind = "涨潮"
		elif tide_phase <= -SLACK:
			kind = "落潮"
		parts.append([_flow(tb, float(td[1])) * tide_phase, kind])
	current = Vector2.ZERO
	current_kind = "平潮"
	var best := -1.0
	for p in parts:
		var v: Vector2 = p[0]
		current += v
		if v.length() > best:
			best = v.length()
			current_kind = str(p[1])
	current = current.limit_length(CURRENT_CAP)


## 一股流：方位上下摆 10°、流速上下浮两成
func _flow(bearing_deg: float, speed: float) -> Vector2:
	return bearing_vector(bearing_deg + _rng.randf_range(-10.0, 10.0)) * speed * _rng.randf_range(0.8, 1.2)
