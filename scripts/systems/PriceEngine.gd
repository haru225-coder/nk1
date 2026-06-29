class_name PriceEngine extends RefCounted

# [C3-STABLE-CORE]
# calculate_price 签名保持兼容。新增 calculate_price_linked 为跨港口联动版本。
# NK1-P5-ECON-002: 新增 calculate_price_deep — 供应链+区域压力+饱和+繁荣度
# 纯计算引擎：无副作用，不触碰状态，完全基于输入参数计算价格。

## 跨港口联动强度：邻近港口库存偏差对本港价格的渗透比例（0~1）
const REGIONAL_BLEED := 0.25
## 联动生效的库存偏差阈值（ratio 偏离 1.0 超过此值才渗透）
const BLEED_THRESHOLD := 0.15
## NK1-P5-ECON-002: 供应链渗透强度（产出港短缺→消费港涨价）
const SUPPLY_CHAIN_BLEED := 0.20
## NK1-P5-ECON-002: 区域压力渗透强度（同区域整体短缺/过剩→本港价格）
const REGIONAL_PRESSURE_BLEED := 0.15
## NK1-P6-POLISH: 价格上下限与修正因子范围常量
const PRICE_FLOOR := 1                       ## 最低保底价
const PRICE_CAP_MULT := 5                    ## 最高价格倍率（base × 此值）
const SUPPLY_CHAIN_MOD_MIN := 0.7            ## 供应链修正下限
const SUPPLY_CHAIN_MOD_MAX := 1.3            ## 供应链修正上限
const REGIONAL_PRESSURE_MOD_MIN := 0.85      ## 区域压力修正下限
const REGIONAL_PRESSURE_MOD_MAX := 1.15      ## 区域压力修正上限
const DOWNSTREAM_DEMAND_SURGE_THRESHOLD := 1.2  ## 下游需求旺盛阈值
const DOWNSTREAM_DEMAND_SURGE_BLEED_FACTOR := 0.5 ## 下游需求旺盛时渗透衰减系数

## 原始价格计算（保持兼容，无跨港口联动）
static func calculate_price(base_price: int, prod_mod: float, demand_mod: float, dist_mod: float, active_events: Array[BaseEconomicEvent], port_id: String, good_id: String) -> Dictionary:
	var event_mod: float = 1.0

	for event in active_events:
		event_mod *= event.get_price_modifier(port_id, good_id)

	var multiplier = prod_mod * demand_mod * dist_mod * event_mod
	var final_price = int(base_price * multiplier)

	if final_price < PRICE_FLOOR:
		final_price = PRICE_FLOOR
	if final_price > base_price * PRICE_CAP_MULT:
		final_price = base_price * PRICE_CAP_MULT

	return {
		"base_price": base_price,
		"multiplier": multiplier,
		"event_mod": event_mod,
		"final_price": final_price
	}

## 跨港口联动价格计算
## neighbor_ratios: 邻近港口的库存比率数组（由调用方从 MarketState 收集）
## 当邻近港口库存偏离基准时，本港价格产生同向（短缺→涨 / 过剩→跌）的渗透修正。
static func calculate_price_linked(
	base_price: int, prod_mod: float, demand_mod: float, dist_mod: float,
	active_events: Array[BaseEconomicEvent], port_id: String, good_id: String,
	local_ratio: float, neighbor_ratios: Array
) -> Dictionary:
	var event_mod: float = 1.0
	for event in active_events:
		event_mod *= event.get_price_modifier(port_id, good_id)

	# 跨港口联动：邻近港口的平均库存偏差渗透到本港
	var regional_mod := _compute_regional_modifier(local_ratio, neighbor_ratios)

	var multiplier = prod_mod * demand_mod * dist_mod * event_mod * regional_mod
	var final_price = int(base_price * multiplier)

	if final_price < PRICE_FLOOR:
		final_price = PRICE_FLOOR
	if final_price > base_price * PRICE_CAP_MULT:
		final_price = base_price * PRICE_CAP_MULT

	return {
		"base_price": base_price,
		"multiplier": multiplier,
		"event_mod": event_mod,
		"regional_mod": regional_mod,
		"final_price": final_price
	}

## NK1-P5-ECON-002: 深度经济价格计算 — 供应链 + 区域压力 + 饱和 + 繁荣度
## 在 calculate_price_linked 基础上增加：
## - supply_chain_mod: 产出港短缺→消费港涨价，消费港过剩→产出港降价
## - regional_pressure_mod: 同区域整体库存偏差→本港价格
## - saturation_mod: 玩家持续倾销压低基础价（0.7~1.0）
## - prosperity_mod: 港口繁荣度影响价格倾向（0.97~1.03）
static func calculate_price_deep(
	base_price: int, prod_mod: float, demand_mod: float, dist_mod: float,
	active_events: Array[BaseEconomicEvent], port_id: String, good_id: String,
	local_ratio: float, neighbor_ratios: Array,
	supply_chain_mod: float, regional_pressure_mod: float,
	saturation_mod: float, prosperity_mod: float
) -> Dictionary:
	var event_mod: float = 1.0
	for event in active_events:
		event_mod *= event.get_price_modifier(port_id, good_id)

	var regional_mod := _compute_regional_modifier(local_ratio, neighbor_ratios)

	var multiplier = prod_mod * demand_mod * dist_mod * event_mod * regional_mod
	multiplier *= supply_chain_mod * regional_pressure_mod * saturation_mod * prosperity_mod
	var final_price = int(base_price * multiplier)

	if final_price < PRICE_FLOOR:
		final_price = PRICE_FLOOR
	if final_price > base_price * PRICE_CAP_MULT:
		final_price = base_price * PRICE_CAP_MULT

	return {
		"base_price": base_price,
		"multiplier": multiplier,
		"event_mod": event_mod,
		"regional_mod": regional_mod,
		"supply_chain_mod": supply_chain_mod,
		"regional_pressure_mod": regional_pressure_mod,
		"saturation_mod": saturation_mod,
		"prosperity_mod": prosperity_mod,
		"final_price": final_price
	}

## NK1-P5-ECON-002: 计算供应链修正因子
## is_producer: 本港是否为该货物的产出港
## upstream_ratio: 产出港的库存比率（若本港是消费港，看上游产出港）
## downstream_avg_ratio: 消费港的平均库存比率（若本港是产出港，看下游消费港）
## 产出港短缺→消费港涨价；消费港过剩→产出港降价
static func compute_supply_chain_mod(
	is_producer: bool, is_consumer: bool,
	upstream_ratio: float, downstream_avg_ratio: float
) -> float:
	var mod := 1.0
	# 消费港受产出港供应影响：产出港短缺(ratio>1)→消费港涨价
	if is_consumer and upstream_ratio > 1.0:
		var deviation := upstream_ratio - 1.0
		if deviation > BLEED_THRESHOLD:
			mod *= 1.0 + deviation * SUPPLY_CHAIN_BLEED
	# 产出港受消费港需求影响：消费港过剩(ratio<1)→产出港降价
	if is_producer and downstream_avg_ratio < 1.0:
		var deviation := 1.0 - downstream_avg_ratio
		if deviation > BLEED_THRESHOLD:
			mod *= 1.0 - deviation * SUPPLY_CHAIN_BLEED
	# 产出港短缺时自身价格已涨，下游需求仍旺(ratio>1)则额外拉升
	if is_producer and downstream_avg_ratio > DOWNSTREAM_DEMAND_SURGE_THRESHOLD:
		var deviation := downstream_avg_ratio - 1.0
		mod *= 1.0 + deviation * SUPPLY_CHAIN_BLEED * DOWNSTREAM_DEMAND_SURGE_BLEED_FACTOR
	return clampf(mod, SUPPLY_CHAIN_MOD_MIN, SUPPLY_CHAIN_MOD_MAX)

## NK1-P5-ECON-002: 计算区域压力修正因子
## regional_avg_ratio: 同区域所有港口该货物的平均库存比率
static func compute_regional_pressure_mod(regional_avg_ratio: float) -> float:
	var deviation := regional_avg_ratio - 1.0
	if abs(deviation) < BLEED_THRESHOLD:
		return 1.0
	return clampf(1.0 + deviation * REGIONAL_PRESSURE_BLEED, REGIONAL_PRESSURE_MOD_MIN, REGIONAL_PRESSURE_MOD_MAX)

## 计算跨港口联动修正因子
## local_ratio: 本港库存比率（base/current，>1=短缺，<1=过剩）
## neighbor_ratios: 邻近港口同商品库存比率
## 返回乘数：>1 表示联动推高本港价格，<1 表示联动压低
static func _compute_regional_modifier(local_ratio: float, neighbor_ratios: Array) -> float:
	if neighbor_ratios.is_empty():
		return 1.0
	var neighbor_avg: float = 0.0
	var count: int = 0
	for nr in neighbor_ratios:
		neighbor_avg += float(nr)
		count += 1
	if count == 0:
		return 1.0
	neighbor_avg /= float(count)

	# 邻近港口偏差方向（相对基准 1.0）
	var neighbor_deviation := neighbor_avg - 1.0
	# 只在偏差超过阈值时渗透，避免微小波动产生噪音
	if abs(neighbor_deviation) < BLEED_THRESHOLD:
		return 1.0
	# 渗透修正：偏差 × 强度，方向与邻近港口一致
	# 邻近短缺(>1) → 本港涨；邻近过剩(<1) → 本港跌
	var bleed := neighbor_deviation * REGIONAL_BLEED
	# 本港与邻近同向时不叠加（本港已短缺且邻近也短缺 → 联动减弱，避免双重计价）
	var local_deviation := local_ratio - 1.0
	if (local_deviation > 0 and neighbor_deviation > 0) or (local_deviation < 0 and neighbor_deviation < 0):
		bleed *= 0.5
	return 1.0 + bleed
