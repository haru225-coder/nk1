class_name EventSystem extends RefCounted

# 从 events.json 抽取海上随机事件（风暴、遇难商船等）
static func get_random_event() -> Dictionary:
	var all_events = GameManager.world_events_data.get("events", [])
	var valid_events: Array = []
	
	for e in all_events:
		if _check_conditions(e.get("conditions", {})):
			valid_events.append(e)
			
	if valid_events.is_empty():
		return {}
		
	var picked = valid_events[randi() % valid_events.size()]
	return {
		"title": picked.get("title", "未知事件"),
		"body": picked.get("body", ""),
		"choices": picked.get("choices", []).duplicate(true)
	}

static func _check_conditions(conds: Dictionary) -> bool:
	return ConditionEvaluator.matches(conds)