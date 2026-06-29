class_name GiftNPCHandler extends RefCounted

const DEFAULT_PREFERRED_DELTA := 10
const DEFAULT_NEUTRAL_DELTA := 5

func handle(intent: Intent) -> IntentResult:
	var npc_id := str(intent.target)
	if npc_id.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_GIFT_NO_NPC, IntentTypes.GIFT_NPC)

	var npc_data := GameManager.get_npc_data(npc_id)
	if npc_data.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_GIFT_UNKNOWN_NPC, IntentTypes.GIFT_NPC)

	var item_id := str(intent.parameters.get("item_id", ""))
	if item_id.is_empty():
		item_id = _pick_best_gift(npc_data)
	if item_id.is_empty():
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_GIFT_NO_ITEM, IntentTypes.GIFT_NPC)

	if not _player_has_item(item_id):
		return IntentResult.error(IntentErrorCodes.INVALID_STATE, TextKeys.ERROR_GIFT_NO_ITEM, IntentTypes.GIFT_NPC)

	_consume_item(item_id)
	var delta := _compute_affinity_delta(item_id, npc_data)
	GameState.story.adjust_npc_affinity(npc_id, delta)

	var r := IntentResult.ok({
		"npc_id": npc_id,
		"item_id": item_id,
		"affinity_delta": delta,
		"affinity": GameState.story.get_npc_affinity(npc_id),
		"item_name": _resolve_item_name(item_id),
	}, TextKeys.INTENT_GIFT_SUCCESS)
	r.type = IntentTypes.GIFT_NPC
	return r

static func _pick_best_gift(npc_data: Dictionary) -> String:
	for item_id in npc_data.get("gift_preferences", []):
		var id := str(item_id)
		if _player_has_item(id):
			return id
	return ""

static func _player_has_item(item_id: String) -> bool:
	if GameState.has_item_flag(item_id):
		return true
	return CargoSystem.has_item(item_id, 1)

static func _consume_item(item_id: String) -> void:
	if GameState.has_item_flag(item_id):
		GameState.story.remove_item(item_id)
	elif CargoSystem.has_item(item_id, 1):
		CargoSystem.remove_item(item_id, 1)

static func _compute_affinity_delta(item_id: String, npc_data: Dictionary) -> int:
	var gift_affinity: Dictionary = npc_data.get("gift_affinity", {})
	if gift_affinity.has(item_id):
		return int(gift_affinity[item_id])
	var preferences: Array = npc_data.get("gift_preferences", [])
	if item_id in preferences:
		return DEFAULT_PREFERRED_DELTA
	return DEFAULT_NEUTRAL_DELTA

static func _resolve_item_name(item_id: String) -> String:
	var good := GameManager.get_good_data(item_id)
	if not good.is_empty():
		return str(good.get("name", item_id))
	var item := GameManager.get_item_data(item_id)
	if not item.is_empty():
		return str(item.get("name", item_id))
	return item_id