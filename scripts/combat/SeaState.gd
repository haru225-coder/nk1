extends RefCounted
## 海战海况（lane combat02）：风（来向 / 风力 / 阵风 / 风向缓转）+ 流（季风海流、定向洋流、潮流）。
## WorldMap 开战时按月令季风与海域建一份（setup），逐物理帧 step(dt)；ManeuverModel 拿它的读数算帆向、风压差与流压差。
## 本件只存数、只演化：不碰节点、不读 autoload——季风方位 / 强度由调用方从 Calendar 取来传入，探针可以直接 new 一份。
##
## 方位与 Calendar 同一口径：方位角 0 = 正北、90 = 正东（顺时针）；风按「吹向」存（Calendar.NE_MONSOON_BEARING = 225
## 即东北风吹向西南）。海战场面 −y 为北、+x 为东，吹向单位向量 = (sin b, −cos b)，与 Ship.wind_vector 同义
## （Vector2(0, 1) = 吹向正南 = 北风）。叫法照舟师：风按来向叫（东北风），流按去向叫（流向西南）。
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
## 本场主风向（吹向方位，度）、缓转幅度、当前缓转（度）与阵风（标准差为 1 的无量纲量）
var _base_bearing := 180.0
var _veer_amp := VEER_DEG
var _veer := 0.0
var _gust := 0.0
var _rng := RandomNumberGenerator.new()


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
	_setup_current(sea_name)
	_apply_wind()


## 剧情 / 探针定风：bearing_to 为吹向方位（度），strength 为风力（封顶 WIND_CAP）；缓转与阵风照常叠在上面
func force_wind(bearing_to: float, strength: float) -> void:
	_base_bearing = fposmod(bearing_to, 360.0)
	wind_mean = clampf(strength, WIND_FLOOR, WIND_CAP)
	_veer = 0.0
	_gust = 0.0
	_apply_wind()


## 定流：flow 为流速向量（px/s，封顶 CURRENT_CAP），kind 为叫法
func force_current(flow: Vector2, kind := "季风流") -> void:
	current = flow.limit_length(CURRENT_CAP)
	current_kind = kind


## 推进 dt 秒：风向缓转、阵风起落（Ornstein–Uhlenbeck，向本场主风回拉）；流一场之内不变
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_veer = clampf(_ou(_veer, _veer_amp, VEER_TAU, dt), -1.6 * _veer_amp, 1.6 * _veer_amp)
	_gust = clampf(_ou(_gust, 1.0, GUST_TAU, dt), -1.5, 1.5)
	_apply_wind()


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
