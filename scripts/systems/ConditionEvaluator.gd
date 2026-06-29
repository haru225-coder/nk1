class_name ConditionEvaluator extends RefCounted

## 统一条件检测：EventSystem、StoryEventChainEngine、NPC special_actions 共用

static func matches(conds: Dictionary, ctx: Dictionary = {}) -> bool:
	if conds.is_empty():
		return true

	if conds.has("port_id"):
		if str(ctx.get("port_id", "")) != str(conds["port_id"]):
			return false

	if conds.has("pu_attention_min"):
		if GameState.pu_attention < int(conds["pu_attention_min"]):
			return false

	if conds.has("fame_min"):
		if GameState.fame < int(conds["fame_min"]):
			return false

	var req_flag: String = str(conds.get("requires_story_flag", ""))
	if req_flag.is_empty() and conds.has("story_flags_required"):
		var required: Array = conds["story_flags_required"]
		for flag in required:
			if not GameState.has_story_flag(str(flag)):
				return false
	elif req_flag != "" and not GameState.has_story_flag(req_flag):
		return false

	var unless_flag: String = str(conds.get("unless_story_flag", ""))
	if unless_flag.is_empty() and conds.has("story_flags_absent"):
		var absent: Array = conds["story_flags_absent"]
		for flag in absent:
			if GameState.has_story_flag(str(flag)):
				return false
	elif unless_flag != "" and GameState.has_story_flag(unless_flag):
		return false

	if conds.has("npc_affinity_min"):
		var npc_id := str(ctx.get("npc_id", ""))
		if npc_id.is_empty():
			return false
		if GameState.story.get_npc_affinity(npc_id) < int(conds["npc_affinity_min"]):
			return false

	return true