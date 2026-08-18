class_name EconomySystem extends RefCounted

## 经济系统统一入口：所有价格计算走 PriceEngine（含跨港口联动）。
## 事件修正通过 active_events 注入，库存联动通过 neighbor_ratios 注入。

## 卖出价相对成交参考价的买卖价差（先按成交后库存定价，再打 bid/ask）。
const SELL_PRICE_RATIO := 0.85

static func get_market_snapshot(port_id: String) -> Dictionary:
	var port = GameManager.get_port_data(port_id)
	if port.is_empty(): return {}

	var snapshot = {
		"port_id": port_id,
		"goods": []
	}

	var all_goods = GameManager.goods_data.get("goods", [])
	for g in all_goods:
		var g_id = g.get("id", "")
		if g_id.is_empty(): continue
		if g.get("category", "") != "货物": continue

		var p_price = get_trade_price(port_id, g_id, 1, true)

		snapshot["goods"].append({
			"id": g_id,
			"name": g.get("name", ""),
			"base_value": g.get("base_value", 50),
			"price": p_price,
			"available": GameManager.state.market.get_stock(port_id, g_id)
		})

	return snapshot

static func get_price(port_id: String, good_id: String, for_buy: bool = true) -> int:
	var port = GameManager.get_port_data(port_id)
	return _get_price_with_port(port, good_id, for_buy)

## 成交价：按本笔交易完成后的库存询价。买入付稀缺价，卖出收过剩价。
static func get_trade_price(port_id: String, good_id: String, amount: int, is_buy: bool) -> int:
	var qty := maxi(amount, 0)
	var market = GameManager.state.market if GameManager.state != null else null
	var price: int
	if market != null and qty > 0:
		var delta := -qty if is_buy else qty
		price = market.preview_price_stock(port_id, good_id, delta, is_buy)
	else:
		price = get_price(port_id, good_id, is_buy)
	if not is_buy:
		price = maxi(1, int(round(float(price) * SELL_PRICE_RATIO))) if price > 0 else 0
	return price

# 内部方法：统一走 PriceEngine 跨港口联动版本
# NK1-P5-ECON-002: 升级为 calculate_price_deep，增加供应链+区域压力+饱和+繁荣度
static func _get_price_with_port(port: Dictionary, good_id: String, for_buy: bool = true) -> int:
	var good = GameManager.get_good_data(good_id)

	if good.is_empty() or port.is_empty(): return 0

	var base_price = good.get("base_value", 50)
	var prod_mod = 1.0
	var demand_mod = 1.0
	var dist_mod = 1.0

	var prod_dict = port.get("production", {})
	var is_producer: bool = prod_dict.has(good_id)
	if is_producer:
		prod_mod = float(prod_dict[good_id])

	var demand_dict = port.get("demand", {})
	var is_consumer: bool = demand_dict.has(good_id)
	if is_consumer:
		demand_mod = float(demand_dict[good_id])

	var port_id = port.get("id", "")
	var market = GameManager.state.market
	var local_ratio = market.get_stock_ratio(port_id, good_id)
	prod_mod *= local_ratio

	# 收集邻近港口库存比率（跨港口联动）
	var neighbor_ratios := _collect_neighbor_ratios(port_id, good_id)

	# NK1-P5-ECON-002: 供应链修正
	var upstream_ratio := _get_upstream_ratio(good_id, port_id)
	var downstream_avg := _get_downstream_avg_ratio(good_id, port_id)
	var supply_chain_mod := PriceEngine.compute_supply_chain_mod(
		is_producer, is_consumer, upstream_ratio, downstream_avg
	)

	# NK1-P5-ECON-002: 区域压力修正
	var regional_avg := _get_regional_avg_ratio(port, good_id)
	var regional_pressure_mod := PriceEngine.compute_regional_pressure_mod(regional_avg)

	# NK1-P5-ECON-002: 饱和修正 + 繁荣度修正
	var saturation_mod: float = market.get_saturation_mod(port_id, good_id)
	var prosperity_mod: float = _compute_prosperity_price_mod(market.get_prosperity(port_id))
	# NK1-P5-ECON-003: 港口好感度修正
	var affinity_mod: float = market.get_affinity_price_mod(port_id, for_buy)

	var active_events = WorldEventTracker.get_active_events()
	var result = PriceEngine.calculate_price_deep(
		base_price, prod_mod, demand_mod, dist_mod,
		active_events, port_id, good_id,
		local_ratio, neighbor_ratios,
		supply_chain_mod, regional_pressure_mod,
		saturation_mod, prosperity_mod * affinity_mod
	)

	return result["final_price"]

## 收集邻近港口同商品的库存比率
static func _collect_neighbor_ratios(port_id: String, good_id: String) -> Array:
	var port = GameManager.get_port_data(port_id)
	var connections: Array = port.get("connections", [])
	var market = GameManager.state.market
	var ratios: Array = []
	for neighbor_id in connections:
		ratios.append(market.get_stock_ratio(neighbor_id, good_id))
	return ratios

## NK1-P5-ECON-002: 获取产出港库存比率（供应链上游）
## 遍历所有港口，找到该货物的产出港，返回其库存比率（取最高的，即最紧缺的）
static func _get_upstream_ratio(good_id: String, exclude_port: String) -> float:
	var ports = GameManager.ports_data.get("ports", [])
	var market = GameManager.state.market
	var worst_ratio := 1.0
	for p in ports:
		var pid: String = p.get("id", "")
		if pid == exclude_port or pid.is_empty():
			continue
		var prod_dict = p.get("production", {})
		if prod_dict.has(good_id):
			var ratio: float = market.get_stock_ratio(pid, good_id)
			if ratio > worst_ratio:
				worst_ratio = ratio
	return worst_ratio

## NK1-P5-ECON-002: 获取消费港平均库存比率（供应链下游）
## 遍历所有港口，找到该货物的需求港，返回平均库存比率
static func _get_downstream_avg_ratio(good_id: String, exclude_port: String) -> float:
	var ports = GameManager.ports_data.get("ports", [])
	var market = GameManager.state.market
	var sum := 0.0
	var count := 0
	for p in ports:
		var pid: String = p.get("id", "")
		if pid == exclude_port or pid.is_empty():
			continue
		var demand_dict = p.get("demand", {})
		if demand_dict.has(good_id):
			sum += market.get_stock_ratio(pid, good_id)
			count += 1
	return sum / float(count) if count > 0 else 1.0

## NK1-P5-ECON-002: 获取同区域所有港口该货物的平均库存比率
static func _get_regional_avg_ratio(port: Dictionary, good_id: String) -> float:
	var region: String = port.get("region", "")
	if region.is_empty():
		return 1.0
	var ports = GameManager.ports_data.get("ports", [])
	var market = GameManager.state.market
	var sum := 0.0
	var count := 0
	for p in ports:
		if p.get("region", "") != region:
			continue
		var pid: String = p.get("id", "")
		if pid.is_empty():
			continue
		# 只统计有此货物库存数据的港口
		if market.port_stocks.has(pid) and market.port_stocks[pid].has(good_id):
			sum += market.get_stock_ratio(pid, good_id)
			count += 1
	return sum / float(count) if count > 0 else 1.0

## NK1-P5-ECON-002: 繁荣度→价格修正（繁荣港价格略高，萧条港略低）
## 范围 0.97~1.03，影响温和
static func _compute_prosperity_price_mod(prosperity: float) -> float:
	var deviation := prosperity - 1.0
	return clampf(1.0 + deviation * 0.1, 0.97, 1.03)
