class_name EventSystem extends RefCounted

# 从 GameManager 加载的事件库中，根据当前 GameState 抽取一个合法事件
static func get_random_event() -> Dictionary:
	var all_events = GameManager.events_data.get("events", [])
	var valid_events = []
	
	for e in all_events:
		if _check_conditions(e.get("conditions", {})):
			valid_events.append(e)
			
	if valid_events.is_empty():
		return {}
		
	# 简单随机抽取（未来可在此处引入 weights 权重计算）
	return valid_events[randi() % valid_events.size()]

# 检查单个事件是否满足触发条件
static func _check_conditions(conds: Dictionary) -> bool:
	if conds.has("pu_attention_min"):
		if GameState.pu_attention < conds["pu_attention_min"]: return false
		
	if conds.has("fame_min"):
		if GameState.fame < conds["fame_min"]: return false
		
	# 未来可扩展更多条件：如 cargo_has, weather_is 等
	return true
