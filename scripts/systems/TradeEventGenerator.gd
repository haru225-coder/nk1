class_name TradeEventGenerator extends RefCounted

const DAILY_EVENT_CHANCE := 0.08  # 每天 8% 概率触发贸易事件

static func try_generate() -> void:
	_try_safety_valve()
	
	if randf() > DAILY_EVENT_CHANCE:
		return
		
	var ports = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return
		
	var valid_ports = []
	for p in ports:
		var status = p.get("status", "")
		if status == "main" or status == "thread":
			valid_ports.append(p)
			
	if valid_ports.is_empty():
		return
		
	var port = valid_ports[randi() % valid_ports.size()]
	var port_id = port.get("id", "")
	
	var is_disaster = randf() < 0.5
	if is_disaster:
		WorldEventTracker.add_event(TradeDisasterEvent.new(port_id, 10))
	else:
		WorldEventTracker.add_event(TradeRecoveryEvent.new(port_id, 10))

static func _try_safety_valve() -> void:
	var ports = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return
		
	var valid_ports = []
	for p in ports:
		var status = p.get("status", "")
		if status == "main" or status == "thread":
			valid_ports.append(p)
			
	if valid_ports.is_empty():
		return
		
	var all_goods = GameManager.goods_data.get("goods", [])
	if all_goods.is_empty():
		return
		
	var total_ratio = 0.0
	var count = 0
	
	for p in valid_ports:
		var port_id = p.get("id", "")
		for g in all_goods:
			var g_id = g.get("id", "")
			if g.get("category", "") == "货物" and not g_id.is_empty():
				total_ratio += GameManager.state.market.get_stock_ratio(port_id, g_id)
				count += 1
				
	if count > 0:
		var avg_ratio = total_ratio / count
		if avg_ratio < 0.3:
			# Safety valve trigger
			var port = valid_ports[randi() % valid_ports.size()]
			WorldEventTracker.add_event(TradeRecoveryEvent.new(port.get("id", ""), 10))
