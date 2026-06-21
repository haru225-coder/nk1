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
	if conds.has("pu_attention_min"):
		if GameState.pu_attention < conds["pu_attention_min"]:
			return false
		
	if conds.has("fame_min"):
		if GameState.fame < conds["fame_min"]:
			return false

	var req_flag: String = conds.get("requires_story_flag", "")
	if req_flag != "" and not GameState.has_story_flag(req_flag):
		return false

	var unless_flag: String = conds.get("unless_story_flag", "")
	if unless_flag != "" and GameState.has_story_flag(unless_flag):
		return false

	return true