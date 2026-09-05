extends Node
## 港口行情。大航海时代 II 式的供需模型：
##   价格 = 基准价 × 产地/消费地系数 × 行情指数
## 玩家大量买卖会冲击行情指数，随日期推移向 1.0 回归。

## 产地便宜、消费地昂贵——差价的唯一来源。
const ROLE_MOD := {"origin": 0.65, "normal": 1.0, "consumer": 1.75}

const RATE_MIN := 0.40
const RATE_MAX := 2.20
## 每日向 1.0 回归的比例。0.045 约合 15 日回复一半——跑一趟近海回来行情已缓过大半，
## 否则同一条商路走两次就废了。
const RECOVERY := 0.045

## 市舶司抽解（进口税），随货物与港口可调
var tariff_rate: float = 0.10
## 牙人佣金，卖出时扣
var broker_fee: float = 0.05

## 同港价差地板。通事的议价是双向的（压买价又抬卖价），杂事又同时缩小抽解与佣金，
## 而抽解与佣金正是唯一阻止「原地买入立刻卖出」的价差——10%+5% 的毛价差撑不起满级
## 通事 ±21% 的双向议价，满编时同港卖价会高过买价，站着不动就能无限印钱，且不出港
## 故 customs_inspection 永不触发。与城墙无上限（GameState.SIEGE_WALL_MAX）是同一类错误。
## 这条不靠调参维持、靠结构维持：任何修饰组合下同港买价恒 ≥ 卖价 × 此值。
const PRICE_SPREAD_MIN := 1.08

## {port_id: {good_id: rate}}
var rates: Dictionary = {}

## ── 战况 ──────────────────────────────────────────────
## 港口战况是 Calendar 的纯函数：ports.json 每港 `war: {"YYYY-MM": status}`，取 ≤ 当月的最新一条。
## 不入存档；读档后按日期自然复原。状态只改参数（抽解、缉私、开市、可达），不开场景。
const WAR_STATUSES := ["loyal", "contested", "besieged", "fallen", "closed"]
const WAR_LABEL := {
	"loyal": "", "contested": "对峙", "besieged": "围城", "fallen": "已降元", "closed": "封港",
}
## 抽解倍率：降元港口抽解加倍；对峙期两边都要打点
const WAR_TARIFF := {"loyal": 1.0, "contested": 1.2, "besieged": 1.0, "fallen": 2.0, "closed": 1.0}
## 缉私倍率（GameState.customs_inspection 读）
const WAR_INSPECTION := {"loyal": 1.0, "contested": 1.3, "besieged": 1.0, "fallen": 2.0, "closed": 1.0}

var _initialized: bool = false


func _ready() -> void:
	# GameManager 是先注册的 autoload，此时 JSON 已加载
	initialize()


func initialize() -> void:
	if _initialized:
		return
	var ports: Array = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return
	for p in ports:
		var pid: String = p.get("id", "")
		var market: Dictionary = p.get("market", {})
		var port_rates := {}
		for gid in market.keys():
			# 开局给每个港口一点随机扰动，避免所有存档行情一致
			port_rates[gid] = randf_range(0.85, 1.15)
		rates[pid] = port_rates
	_initialized = true


# ── 查询 ──────────────────────────────────────────────

func _port_def(port_id: String) -> Dictionary:
	for p in GameManager.ports_data.get("ports", []):
		if p.get("id") == port_id:
			return p
	return {}


func _good_def(good_id: String) -> Dictionary:
	for g in GameManager.goods_data.get("goods", []):
		if g.get("id") == good_id:
			return g
	return {}


## 该港是否交易此货
func is_traded(port_id: String, good_id: String) -> bool:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.has(good_id)


## 该港交易的所有货物 id
func goods_at(port_id: String) -> Array:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.keys()


func get_role(port_id: String, good_id: String) -> String:
	var market: Dictionary = _port_def(port_id).get("market", {})
	return market.get(good_id, "normal")


func get_rate(port_id: String, good_id: String) -> float:
	return rates.get(port_id, {}).get(good_id, 1.0)


## 抽解的港口部分（战况倍率 + 世界线旗标），不含任何职事修正。
## 同港价差地板拿它当「光杆基准」，好让地板只压职事加成、不与战况机制打架。
func _base_tariff(port_id: String = "") -> float:
	var war_mul: float = WAR_TARIFF.get(war_status(port_id), 1.0) if port_id != "" else 1.0
	# 对峙期站了蒲家：泉州抽解永久八折——「都是一家人」
	if port_id == "quanzhou" and GameState.has_flag("sided_pu"):
		war_mul *= 0.8
	return tariff_rate * war_mul


## 杂事压低抽解与佣金；通事在异国港口另有议价之利；降元港口抽解加倍
func _effective_tariff(port_id: String = "") -> float:
	return _base_tariff(port_id) * Crew.trade_cost_factor()


func _effective_broker() -> float:
	return broker_fee * Crew.trade_cost_factor()


## 定价的唯一出处。estimate_* 逐单位推演时也走这里，避免公式分叉。
##
## 价差地板的裁法（改公式时 tools/verify_economy.py 的 price_with_crew 必须同步）：
## 卖价先封顶在「光杆买价 ÷ 地板」，超出的部分改从买价折扣里扣回来；且买、卖两侧
## 都不得劣于光杆——只压卖价的话，雇齐 400 钱/月的杂事通事反而比光杆赚得少。
func price_at_rate(port_id: String, good_id: String, rate: float, is_buy: bool) -> int:
	var base: float = float(_good_def(good_id).get("base_value", 0))
	var mod: float = ROLE_MOD.get(get_role(port_id, good_id), 1.0)
	var edge := Crew.interpreter_edge(port_id)
	var v := base * mod * rate
	var bare_buy := v * (1.0 + _base_tariff(port_id))
	var bare_sell := v * (1.0 - broker_fee)
	var cap := bare_buy / PRICE_SPREAD_MIN
	var sell_v: float = minf(v * (1.0 - _effective_broker()) * (1.0 + edge), cap)
	sell_v = maxf(sell_v, minf(bare_sell, cap))
	if not is_buy:
		return int(round(sell_v))
	var buy_v: float = maxf(v * (1.0 + _effective_tariff(port_id)) * (1.0 - edge), sell_v * PRICE_SPREAD_MIN)
	return int(round(minf(buy_v, maxf(bare_buy, sell_v * PRICE_SPREAD_MIN))))


## 玩家买入单价（含抽解）
func buy_price(port_id: String, good_id: String) -> int:
	return price_at_rate(port_id, good_id, get_rate(port_id, good_id), true)


## 玩家卖出单价（扣牙人佣金）
func sell_price(port_id: String, good_id: String) -> int:
	return price_at_rate(port_id, good_id, get_rate(port_id, good_id), false)


## 给玩家看的行情标签
func price_hint(port_id: String, good_id: String) -> String:
	var role: String = get_role(port_id, good_id)
	var rate: float = get_rate(port_id, good_id)
	var base_hint := ""
	match role:
		"origin":
			base_hint = "本地所产"
		"consumer":
			base_hint = "此地紧缺"
		_:
			base_hint = ""
	var rate_hint := ""
	if rate >= 1.35:
		rate_hint = "价腾"
	elif rate >= 1.12:
		rate_hint = "价昂"
	elif rate <= 0.65:
		rate_hint = "价贱"
	elif rate <= 0.88:
		rate_hint = "价平偏低"
	if base_hint != "" and rate_hint != "":
		return base_hint + "・" + rate_hint
	return base_hint + rate_hint


# ── 战况 ──────────────────────────────────────────────

func _ym_now() -> String:
	return "%04d-%02d" % [Calendar.year, Calendar.month]


## 当前战况。无 war 表或尚未到任何节点则 loyal。
func war_status(port_id: String) -> String:
	var war: Dictionary = _port_def(port_id).get("war", {})
	if war.is_empty():
		return "loyal"
	var now := _ym_now()
	var best_date := ""
	var best := "loyal"
	for ym in war.keys():
		var k := str(ym)
		if k <= now and k > best_date:
			best_date = k
			best = str(war[ym])
	return best


func war_label(port_id: String) -> String:
	return WAR_LABEL.get(war_status(port_id), "")


## 围城 / 封港时牙行闭门
func is_market_open(port_id: String) -> bool:
	return not (war_status(port_id) in ["besieged", "closed"])


## 封港不可抵达（文永之役后的博多等）
func is_port_reachable(port_id: String) -> bool:
	return war_status(port_id) != "closed" and not GameState.is_port_banned(port_id)


func inspection_factor(port_id: String) -> float:
	return WAR_INSPECTION.get(war_status(port_id), 1.0)


## 月初由 GameManager 调用：本月进入新战况的港口，给一次行情冲击，并返回通告文本。
## 冲击是一次性的，之后仍按 RECOVERY 回归——战争抬高的米价会慢慢落，但税不会。
func on_month_changed() -> Array:
	var notices := []
	var now := _ym_now()
	for p in GameManager.ports_data.get("ports", []):
		var war: Dictionary = p.get("war", {})
		if not war.has(now):
			continue
		var pid: String = p.get("id", "")
		var status := str(war[now])
		match status:
			"besieged":
				_shift_rate(pid, "grain", 0.8)
				notices.append("【战况】%s被围。城中米价腾贵，牙行闭门。" % p.get("name", pid))
			"fallen":
				_shift_rate(pid, "grain", 0.5)
				for gid in goods_at(pid):
					if gid != "grain":
						_shift_rate(pid, gid, -0.15)
				notices.append("【战况】%s已降元。市舶司换了旗，抽解加倍，缉私加严。" % p.get("name", pid))
			"contested":
				notices.append("【战况】%s两军对峙，港内船只都在名册上。" % p.get("name", pid))
			"closed":
				notices.append("【战况】%s封港，海路不通。" % p.get("name", pid))
			"loyal":
				notices.append("【战况】%s复归宋土。" % p.get("name", pid))
	return notices


# ── 交易冲击 ──────────────────────────────────────────

func _depth(port_id: String) -> float:
	return float(_port_def(port_id).get("depth", 100))


func _shift_rate(port_id: String, good_id: String, delta: float) -> void:
	if not rates.has(port_id):
		return
	var r: float = rates[port_id].get(good_id, 1.0)
	rates[port_id][good_id] = clampf(r + delta, RATE_MIN, RATE_MAX)


## 玩家买入 amount 单位后推高价格
func apply_buy_impact(port_id: String, good_id: String, amount: int) -> void:
	_shift_rate(port_id, good_id, float(amount) / _depth(port_id))


## 玩家卖出 amount 单位后压低价格——一次性倾销会砸盘
func apply_sell_impact(port_id: String, good_id: String, amount: int) -> void:
	_shift_rate(port_id, good_id, -float(amount) / _depth(port_id))


## 预估卖出总收入，逐单位结算以体现砸盘效应
func estimate_sell_revenue(port_id: String, good_id: String, amount: int) -> int:
	var total := 0
	var depth := _depth(port_id)
	var r := get_rate(port_id, good_id)
	for i in range(amount):
		total += price_at_rate(port_id, good_id, r, false)
		r = clampf(r - 1.0 / depth, RATE_MIN, RATE_MAX)
	return total


## 预估买入总支出
func estimate_buy_cost(port_id: String, good_id: String, amount: int) -> int:
	var total := 0
	var depth := _depth(port_id)
	var r := get_rate(port_id, good_id)
	for i in range(amount):
		total += price_at_rate(port_id, good_id, r, true)
		r = clampf(r + 1.0 / depth, RATE_MIN, RATE_MAX)
	return total


# ── 日推进 ────────────────────────────────────────────

func on_day_passed() -> void:
	for pid in rates.keys():
		var port_rates: Dictionary = rates[pid]
		for gid in port_rates.keys():
			var r: float = port_rates[gid]
			port_rates[gid] = r + (1.0 - r) * RECOVERY


# ── 存档 ──────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {"rates": rates, "tariff": tariff_rate, "broker": broker_fee}


func from_dict(d: Dictionary) -> void:
	rates = d.get("rates", {})
	tariff_rate = d.get("tariff", 0.10)
	broker_fee = d.get("broker", 0.05)
	_initialized = true
