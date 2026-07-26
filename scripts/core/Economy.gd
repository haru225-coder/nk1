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

## {port_id: {good_id: rate}}
var rates: Dictionary = {}

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


func _unit_value(port_id: String, good_id: String) -> float:
	var base: float = float(_good_def(good_id).get("base_value", 0))
	var role: String = get_role(port_id, good_id)
	var mod: float = ROLE_MOD.get(role, 1.0)
	return base * mod * get_rate(port_id, good_id)


## 玩家买入单价（含抽解）
func buy_price(port_id: String, good_id: String) -> int:
	return int(round(_unit_value(port_id, good_id) * (1.0 + tariff_rate)))


## 玩家卖出单价（扣牙人佣金）
func sell_price(port_id: String, good_id: String) -> int:
	return int(round(_unit_value(port_id, good_id) * (1.0 - broker_fee)))


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
	var saved: float = get_rate(port_id, good_id)
	var total := 0
	var depth := _depth(port_id)
	var r := saved
	for i in range(amount):
		var base: float = float(_good_def(good_id).get("base_value", 0))
		var mod: float = ROLE_MOD.get(get_role(port_id, good_id), 1.0)
		total += int(round(base * mod * r * (1.0 - broker_fee)))
		r = clampf(r - 1.0 / depth, RATE_MIN, RATE_MAX)
	return total


## 预估买入总支出
func estimate_buy_cost(port_id: String, good_id: String, amount: int) -> int:
	var total := 0
	var depth := _depth(port_id)
	var r := get_rate(port_id, good_id)
	for i in range(amount):
		var base: float = float(_good_def(good_id).get("base_value", 0))
		var mod: float = ROLE_MOD.get(get_role(port_id, good_id), 1.0)
		total += int(round(base * mod * r * (1.0 + tariff_rate)))
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
