class_name PriceEngine extends RefCounted

# [C3-STABLE]
# INTERFACE FROZEN. DO NOT MODIFY SIGNATURE OR ADD STATE.

# 纯计算引擎：无副作用，不触碰状态，完全基于输入参数计算价格

static func calculate_price(base_price: int, prod_mod: float, demand_mod: float, dist_mod: float, active_events: Array[BaseEconomicEvent], port_id: String, good_id: String) -> Dictionary:
	var event_mod: float = 1.0
	
	for event in active_events:
		event_mod *= event.get_price_modifier(port_id, good_id)
		
	var multiplier = prod_mod * demand_mod * dist_mod * event_mod
	var final_price = int(base_price * multiplier)
	
	# 保底逻辑，商品价格不能低于 1 钱
	if final_price < 1:
		final_price = 1
		
	print("[PriceEngine] base=%d multiplier=%.2f final=%d" % [base_price, multiplier, final_price])
		
	return {
		"base_price": base_price,
		"multiplier": multiplier,
		"event_mod": event_mod,
		"final_price": final_price
	}
