class_name MarketState extends RefCounted

# port_stocks[port_id][good_id] = {"stock": 800, "base_stock": 1000}
var port_stocks: Dictionary = {}

# 预告池：尚未爆发、正在倒计时的贸易事件
# 元素结构：{"event": BaseEconomicEvent, "days_left": int}
var upcoming_events: Array[Dictionary] = []

func init_from_ports(ports: Array, goods: Array) -> void:
	for port in ports:
		var port_id = port.get("id", "")
		if port_id.is_empty():
			continue
			
		port_stocks[port_id] = {}
		
		for good in goods:
			var good_id = good.get("id", "")
			if good_id.is_empty() or good.get("category", "") != "货物":
				continue
				
			var base_value = good.get("base_value", 50)
			var base_stock = base_value * 8 # Default
			
			var prod_dict = port.get("production", {})
			if prod_dict.has(good_id):
				base_stock = base_value * 15 # Producer
				
			var demand_dict = port.get("demand", {})
			if demand_dict.has(good_id):
				base_stock = base_value * 3 # Consumer
				
			port_stocks[port_id][good_id] = {
				"stock": base_stock,
				"base_stock": base_stock
			}

func get_stock(port_id: String, good_id: String) -> int:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return 999
	return port_stocks[port_id][good_id]["stock"]

func get_base_stock(port_id: String, good_id: String) -> int:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return 999
	return port_stocks[port_id][good_id]["base_stock"]

func get_stock_ratio(port_id: String, good_id: String) -> float:
	var stock = float(get_stock(port_id, good_id))
	if stock <= 0:
		return 5.0 # Max price
	var base_stock = float(get_base_stock(port_id, good_id))
	var ratio = base_stock / stock
	return clampf(ratio, 0.2, 5.0)

func adjust_stock(port_id: String, good_id: String, delta: int) -> void:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return
	var current = port_stocks[port_id][good_id]["stock"]
	port_stocks[port_id][good_id]["stock"] = maxi(0, current + delta)

func reset_stock(port_id: String, good_id: String) -> void:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return
	port_stocks[port_id][good_id]["stock"] = port_stocks[port_id][good_id]["base_stock"]
