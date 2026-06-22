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
	var event: BaseEconomicEvent
	if is_disaster:
		event = TradeDisasterEvent.new(port_id, 10)
	else:
		event = TradeRecoveryEvent.new(port_id, 10)
		
	# 潜伏期 5-15 天
	var delay = randi_range(5, 15)
	GameManager.state.market.upcoming_events.append({"event": event, "days_left": delay, "type": "disaster" if is_disaster else "recovery", "port_name": port.get("name", port_id)})

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
			var event = TradeRecoveryEvent.new(port.get("id", ""), 10)
			# 紧急恢复，潜伏期缩短为 1-3 天
			var delay = randi_range(1, 3)
			GameManager.state.market.upcoming_events.append({"event": event, "days_left": delay, "type": "recovery", "port_name": port.get("name", port.get("id", ""))})

static func process_day() -> void:
	var remaining: Array[Dictionary] = []
	for item in GameManager.state.market.upcoming_events:
		item["days_left"] -= 1
		if item["days_left"] <= 0:
			var event = item["event"] as BaseEconomicEvent
			event.activate()
			WorldEventTracker.add_event(event)
		else:
			remaining.append(item)
	GameManager.state.market.upcoming_events = remaining

static func get_random_rumor() -> Dictionary:
	var events = GameManager.state.market.upcoming_events
	var available: Array[Dictionary] = []
	for item in events:
		if not item.get("purchased", false):
			available.append(item)
	if available.is_empty():
		return {}
	return available[randi() % available.size()]
