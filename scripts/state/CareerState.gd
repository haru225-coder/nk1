class_name CareerState extends RefCounted

## P7-C 秩禄状态模块
## 只负责秩禄阶梯、主命截止与存档；不直接驱动结局或过场。

const DATA_PATH := ResourcePaths.DATA_CAREER

var rank: int = 0
var current_mandate: Dictionary = {}
var mandate_deadline_month: int = -1

var _tiers: Array = []
var _loaded: bool = false

signal rank_changed(new_rank: int)


func load_defs(path: String = DATA_PATH) -> void:
	_loaded = true
	_tiers.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		load_from_data(parsed)


func load_from_data(data: Dictionary) -> void:
	_loaded = true
	_tiers.clear()
	var raw_tiers = data.get("tiers", [])
	if not raw_tiers is Array:
		return
	for raw_tier in raw_tiers:
		if not raw_tier is Dictionary:
			continue
		var tier: Dictionary = raw_tier
		_tiers.append(tier.duplicate(true))
	_tiers.sort_custom(Callable(self, "_sort_tiers"))
	if _get_tier(rank).is_empty() and not _tiers.is_empty():
		rank = int((_tiers[0] as Dictionary).get("rank", 0))


func get_rank() -> int:
	return rank


func get_title() -> String:
	_ensure_loaded()
	var tier := _get_tier(rank)
	return str(tier.get("title", "无名海商")) if not tier.is_empty() else "无名海商"


func check_promotion(state = null) -> bool:
	_ensure_loaded()
	if is_apex():
		return false
	var next_tier := _get_tier(rank + 1)
	if next_tier.is_empty():
		return false
	var req = next_tier.get("req", {})
	return _requirements_met(req if req is Dictionary else {}, state)


func promote(state = null, calendar = null) -> bool:
	if not check_promotion(state):
		return false
	rank += 1
	_assign_mandate(calendar)
	rank_changed.emit(rank)
	return true


func mandate_expired(calendar, state = null) -> bool:
	if current_mandate.is_empty() or mandate_deadline_month < 0:
		return false
	var month_now := _calendar_months_elapsed(calendar)
	if month_now <= mandate_deadline_month:
		return false
	var effects = current_mandate.get("on_fail_effects", current_mandate.get("fail_effects", {}))
	if effects is Dictionary and state != null and state.has_method("apply_effects"):
		state.apply_effects(effects)
	current_mandate.clear()
	mandate_deadline_month = -1
	return true


func is_apex() -> bool:
	_ensure_loaded()
	var tier := _get_tier(rank)
	return bool(tier.get("apex", false)) if not tier.is_empty() else false


func to_dict() -> Dictionary:
	return {
		"rank": rank,
		"current_mandate": current_mandate.duplicate(true),
		"mandate_deadline_month": mandate_deadline_month,
	}


func from_dict(data: Dictionary) -> void:
	rank = int(data.get("rank", 0))
	var raw_mandate = data.get("current_mandate", {})
	current_mandate = raw_mandate.duplicate(true) if raw_mandate is Dictionary else {}
	mandate_deadline_month = int(data.get("mandate_deadline_month", -1))


func _ensure_loaded() -> void:
	if not _loaded:
		load_defs()


func _sort_tiers(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("rank", 0)) < int(b.get("rank", 0))


func _get_tier(target_rank: int) -> Dictionary:
	for raw_tier in _tiers:
		if not raw_tier is Dictionary:
			continue
		var tier: Dictionary = raw_tier
		if int(tier.get("rank", -1)) == target_rank:
			return tier
	return {}


func _requirements_met(req: Dictionary, state) -> bool:
	if req.has("fame") and _get_fame(state) < int(req.get("fame", 0)):
		return false
	if req.has("flag"):
		var flag := str(req.get("flag", "")).strip_edges()
		if flag != "" and not _state_has_flag(state, flag):
			return false
	if req.has("relationship") and not _relationship_req_met(req.get("relationship"), state):
		return false
	if req.has("relationship_gte") and not _relationship_req_met(req.get("relationship_gte"), state):
		return false
	return true


func _get_fame(state) -> int:
	if state == null:
		return 0
	if state is Dictionary:
		return int(state.get("fame", 0))
	return int(state.get("fame"))


func _state_has_flag(state, flag: String) -> bool:
	if state == null:
		return false
	if state.has_method("has_story_flag") and bool(state.has_story_flag(flag)):
		return true
	if state.has_method("has_flag") and bool(state.has_flag(flag)):
		return true
	return false


func _relationship_req_met(raw_req, state) -> bool:
	if state == null:
		return false
	if raw_req is Dictionary:
		var req: Dictionary = raw_req
		for raw_npc_id in req.keys():
			var npc_id := str(raw_npc_id)
			if _get_relationship(state, npc_id) < int(req[raw_npc_id]):
				return false
		return true
	return _get_relationship(state, "lin_boyuan") >= int(raw_req)


func _get_relationship(state, npc_id: String) -> int:
	if state == null or npc_id == "":
		return 0
	if state.has_method("get_npc_relationship"):
		return int(state.get_npc_relationship(npc_id))
	return 0


func _assign_mandate(calendar) -> void:
	var tier := _get_tier(rank)
	var raw_mandate = tier.get("mandate", {})
	if not raw_mandate is Dictionary or (raw_mandate as Dictionary).is_empty():
		current_mandate.clear()
		mandate_deadline_month = -1
		return
	current_mandate = (raw_mandate as Dictionary).duplicate(true)
	mandate_deadline_month = _calendar_months_elapsed(calendar) + int(current_mandate.get("deadline_months", 0))


func _calendar_months_elapsed(calendar) -> int:
	if calendar != null and calendar.has_method("months_elapsed"):
		return int(calendar.months_elapsed())
	return 0
