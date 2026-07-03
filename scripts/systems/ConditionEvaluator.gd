class_name ConditionEvaluator extends RefCounted

## 统一条件检测：EventSystem、StoryEventChainEngine、NPC special_actions 共用

const StoryTables := preload(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY)

static func matches(conds: Dictionary, ctx: Dictionary = {}) -> bool:
	if conds.is_empty():
		return true

	if conds.has("port_id"):
		if str(ctx.get("port_id", "")) != str(conds["port_id"]):
			return false

	for key in ["scene_id", "route_scene_id", "facility_id", "npc_id", "good_id", "trade_action", "intent_type"]:
		if conds.has(key) and str(ctx.get(key, "")) != str(conds[key]):
			return false

	if conds.has("amount_min"):
		if int(ctx.get("amount", 0)) < int(conds["amount_min"]):
			return false

	if conds.has("amount_max"):
		if int(ctx.get("amount", 0)) > int(conds["amount_max"]):
			return false

	if conds.has("trade_count_min"):
		if int(ctx.get("trade_count", ctx.get("trade_completed_count", 0))) < int(conds["trade_count_min"]):
			return false

	if conds.has("trade_count_max"):
		if int(ctx.get("trade_count", ctx.get("trade_completed_count", 0))) > int(conds["trade_count_max"]):
			return false

	if conds.has("is_player_win"):
		if bool(ctx.get("is_player_win", false)) != bool(conds["is_player_win"]):
			return false

	if conds.has("victory_type"):
		if int(ctx.get("victory_type", -1)) != int(conds["victory_type"]):
			return false

	if conds.has("pu_attention_min"):
		var state = _get_state(ctx)
		if state == null or int(state.get("pu_attention")) < int(conds["pu_attention_min"]):
			return false

	if conds.has("fame_min"):
		var state = _get_state(ctx)
		if state == null or int(state.get("fame")) < int(conds["fame_min"]):
			return false

	if conds.has("port_affinity_min") or conds.has("port_affinity_max"):
		var affinity_port_id := str(conds.get("affinity_port_id", ctx.get("port_id", "")))
		if affinity_port_id.is_empty():
			return false
		var state = _get_state(ctx)
		var market = state.get("market") if state != null else null
		if market == null or not market.has_method("get_affinity"):
			return false
		var affinity := float(market.get_affinity(affinity_port_id))
		if conds.has("port_affinity_min") and affinity < float(conds["port_affinity_min"]):
			return false
		if conds.has("port_affinity_max") and affinity > float(conds["port_affinity_max"]):
			return false

	var req_flag: String = str(conds.get("requires_story_flag", ""))
	if req_flag.is_empty() and conds.has("story_flags_required"):
		var state = _get_state(ctx)
		if state == null:
			return false
		var required: Array = conds["story_flags_required"]
		for flag in required:
			if not state.has_story_flag(str(flag)):
				return false
	elif req_flag != "":
		var state = _get_state(ctx)
		if state == null or not state.has_story_flag(req_flag):
			return false

	var unless_flag: String = str(conds.get("unless_story_flag", ""))
	if unless_flag.is_empty() and conds.has("story_flags_absent"):
		var state = _get_state(ctx)
		if state == null:
			return false
		var absent: Array = conds["story_flags_absent"]
		for flag in absent:
			if state.has_story_flag(str(flag)):
				return false
	elif unless_flag != "":
		var state = _get_state(ctx)
		if state != null and state.has_story_flag(unless_flag):
			return false

	for flag in conds.get("flags_required", []):
		var state = _get_state(ctx)
		if state == null or not state.has_flag(str(flag)):
			return false

	for flag in conds.get("flags_absent", []):
		var state = _get_state(ctx)
		if state != null and state.has_flag(str(flag)):
			return false

	for item_id in conds.get("items_required", []):
		var state = _get_state(ctx)
		if state == null or not state.has_item_flag(str(item_id)):
			return false

	for item_id in conds.get("items_absent", []):
		var state = _get_state(ctx)
		if state != null and state.has_item_flag(str(item_id)):
			return false

	for card_id in conds.get("cards_required", []):
		var state = _get_state(ctx)
		if state == null or not state.has_card(str(card_id)):
			return false

	for card_id in conds.get("cards_absent", []):
		var state = _get_state(ctx)
		if state != null and state.has_card(str(card_id)):
			return false

	for effect_id in conds.get("effects_required", []):
		var state = _get_state(ctx)
		if state == null or not StoryTables.has_active_effect(state, str(effect_id)):
			return false

	for effect_id in conds.get("effects_absent", []):
		var state = _get_state(ctx)
		if state != null and StoryTables.has_active_effect(state, str(effect_id)):
			return false

	for title_id in conds.get("titles_required", []):
		var state = _get_state(ctx)
		if state == null or not state.has_title(str(title_id)):
			return false

	for title_id in conds.get("titles_absent", []):
		var state = _get_state(ctx)
		if state != null and state.has_title(str(title_id)):
			return false

	if conds.has("npc_affinity_min"):
		var npc_id := str(ctx.get("npc_id", ""))
		if npc_id.is_empty():
			return false
		var state = _get_state(ctx)
		var story = state.get("story") if state != null else null
		if story == null or story.get_npc_affinity(npc_id) < int(conds["npc_affinity_min"]):
			return false

	if conds.has("npc_relationship_min") or conds.has("npc_relationship_max"):
		var rel_npc_id := str(conds.get("relationship_npc_id", ctx.get("npc_id", "")))
		if rel_npc_id.is_empty():
			return false
		var state = _get_state(ctx)
		if state == null or not state.has_method("get_npc_relationship"):
			return false
		var rel_value := int(state.get_npc_relationship(rel_npc_id))
		if conds.has("npc_relationship_min") and rel_value < int(conds["npc_relationship_min"]):
			return false
		if conds.has("npc_relationship_max") and rel_value > int(conds["npc_relationship_max"]):
			return false

	return true

static func _get_state(ctx: Dictionary):
	if ctx.has("game_state"):
		return ctx["game_state"]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/GameState")
