class_name EconomySystem extends RefCounted

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
		
		# 只展示"货物"类商品（排除文书、账目、寄物等非贸易类）
		if g.get("category", "") != "货物": continue
		
		# MVP: 只展示有合法定价且非隐藏的商品。
		# 未来：可以只展示港口生产或有库存的商品。
		var p_price = _get_price_with_port(port, g_id)
		
		snapshot["goods"].append({
			"id": g_id,
			"name": g.get("name", ""),
			"base_value": g.get("base_value", 50),
			"price": p_price,
			"available": 999 # MVP 暂时无限库存
		})
	
	return snapshot

static func get_price(port_id: String, good_id: String) -> int:
	var port = GameManager.get_port_data(port_id)
	return _get_price_with_port(port, good_id)

# 内部方法：接受已查询的 port 数据，避免重复查找
static func _get_price_with_port(port: Dictionary, good_id: String) -> int:
	var good = GameManager.get_good_data(good_id)
	
	if good.is_empty() or port.is_empty(): return 0
	
	var base_price = good.get("base_value", 50)
	var prod_mod = 1.0
	var demand_mod = 1.0
	var dist_mod = 1.0 # 距离修正预留接口
	
	var prod_dict = port.get("production", {})
	if prod_dict.has(good_id):
		prod_mod = float(prod_dict[good_id])
		
	var demand_dict = port.get("demand", {})
	if demand_dict.has(good_id):
		demand_mod = float(demand_dict[good_id])
		
	var active_events = WorldEventTracker.get_active_events()
	var port_id = port.get("id", "")
	var result = PriceEngine.calculate_price(base_price, prod_mod, demand_mod, dist_mod, active_events, port_id, good_id)
	
	return result["final_price"]
