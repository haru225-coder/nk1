class_name CalendarEventScheduler extends RefCounted

## P7-S 月历事件调度器
## 职责：读取 data/calendar_events.json，按 CalendarState 月份 + 条件选择到期事件。

const DATA_PATH := ResourcePaths.DATA_CALENDAR_EVENTS
const IDEMPOTENCY_PREFIX := "calendar_event:"

signal scene_requested(scene_id: String)
signal cutscene_requested(cutscene_id: String)
signal event_fired(event_id: String, action: Dictionary)

var _events: Array = []
var _fired_once: Dictionary = {}
var _calendar = null
var _state = null
var _base_ctx: Dictionary = {}


func load_events(path: String = DATA_PATH) -> void:
	_events.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		load_from_data(parsed)


func load_from_data(data: Dictionary) -> void:
	_events.clear()
	var raw_events = data.get("events", [])
	if not raw_events is Array:
		return
	for raw_event in raw_events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var event_id := str(event.get("id", "")).strip_edges()
		if event_id == "":
			continue
		_events.append(event.duplicate(true))


func get_event_count() -> int:
	return _events.size()


func bind_calendar(calendar, state = null, base_ctx: Dictionary = {}) -> void:
	var cb := Callable(self, "_on_month_changed")
	if _calendar != null and _calendar.has_signal("month_changed") and _calendar.month_changed.is_connected(cb):
		_calendar.month_changed.disconnect(cb)
	_calendar = calendar
	_state = state
	_base_ctx = base_ctx.duplicate(true)
	if _calendar != null and _calendar.has_signal("month_changed") and not _calendar.month_changed.is_connected(cb):
		_calendar.month_changed.connect(cb)


func get_bound_calendar():
	return _calendar


func check_and_fire(ctx: Dictionary = {}) -> Array:
	if _events.is_empty():
		load_events()
	var calendar = ctx.get("calendar", _calendar)
	var due: Array = []
	for raw_event in _events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		if _once_blocked(event):
			continue
		if not _is_due(event, calendar):
			continue
		if not _conditions_met(event, ctx):
			continue
		due.append(event)
	if due.is_empty():
		return []
	due.sort_custom(Callable(self, "_sort_due_events"))
	var selected: Dictionary = due[0]
	if not _mark_once(selected):
		return []
	_apply_action(selected, ctx)
	return [str(selected.get("id", ""))]


func to_dict() -> Dictionary:
	return {"fired_once": _fired_once.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	var raw = data.get("fired_once", {})
	_fired_once = raw.duplicate(true) if raw is Dictionary else {}


func _on_month_changed(month_key: String) -> void:
	var ctx := _base_ctx.duplicate(true)
	ctx["calendar"] = _calendar
	ctx["month_key"] = month_key
	if _state != null:
		ctx["state"] = _state
	check_and_fire(ctx)


func _sort_due_events(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa == pb:
		return str(a.get("id", "")) < str(b.get("id", ""))
	return pa > pb


func _is_due(event: Dictionary, calendar) -> bool:
	if calendar == null:
		return false
	var fire = event.get("fire", {})
	if not fire is Dictionary:
		return false
	if fire.has("month_offset"):
		if not calendar.has_method("months_elapsed"):
			return false
		return int(calendar.months_elapsed()) >= int(fire.get("month_offset", 0))
	if fire.has("date"):
		var date = fire.get("date", {})
		if not date is Dictionary:
			return false
		var due_year := int(date.get("year", 0))
		var due_month := int(date.get("month", 1))
		return int(calendar.get("year")) > due_year or (int(calendar.get("year")) == due_year and int(calendar.get("month")) >= due_month)
	return false


func _conditions_met(event: Dictionary, ctx: Dictionary) -> bool:
	var cond = event.get("condition", {})
	if not cond is Dictionary:
		return true
	var condition: Dictionary = cond
	if condition.has("flag"):
		var flag := str(condition.get("flag", "")).strip_edges()
		if flag != "" and not _state_has_flag(_get_state(ctx), flag):
			return false
	if condition.has("rank_gte") and _resolve_rank(ctx) < int(condition.get("rank_gte", 0)):
		return false
	if condition.has("relationship_gte") and not _relationship_condition_met(condition.get("relationship_gte"), ctx):
		return false
	return true


func _relationship_condition_met(raw_condition, ctx: Dictionary) -> bool:
	var state = _get_state(ctx)
	if state == null:
		return false
	if raw_condition is Dictionary:
		var rels: Dictionary = raw_condition
		for raw_npc_id in rels.keys():
			var npc_id := str(raw_npc_id)
			if _get_relationship(state, npc_id) < int(rels[raw_npc_id]):
				return false
		return true
	var npc := str(ctx.get("npc_id", "lin_boyuan"))
	return _get_relationship(state, npc) >= int(raw_condition)


func _state_has_flag(state, flag: String) -> bool:
	if state == null:
		return false
	if state.has_method("has_story_flag") and bool(state.has_story_flag(flag)):
		return true
	if state.has_method("has_flag") and bool(state.has_flag(flag)):
		return true
	return false


func _resolve_rank(ctx: Dictionary) -> int:
	if ctx.has("rank"):
		return int(ctx.get("rank", 0))
	var state = _get_state(ctx)
	if state == null:
		return 0
	var career = state.get("career")
	if career != null:
		if career.has_method("get_rank"):
			return int(career.get_rank())
		if "rank" in career:
			return int(career.get("rank"))
	if "rank" in state:
		return int(state.get("rank"))
	return 0


func _get_relationship(state, npc_id: String) -> int:
	if state == null or npc_id == "":
		return 0
	if state.has_method("get_npc_relationship"):
		return int(state.get_npc_relationship(npc_id))
	return 0


func _once_blocked(event: Dictionary) -> bool:
	if not bool(event.get("once", false)):
		return false
	var event_id := str(event.get("id", ""))
	return _fired_once.has(event_id) or IdempotencyGuard.is_processed(_intent_id(event_id))


func _mark_once(event: Dictionary) -> bool:
	if not bool(event.get("once", false)):
		return true
	var event_id := str(event.get("id", ""))
	if not IdempotencyGuard.check_and_record(_intent_id(event_id)):
		return false
	_fired_once[event_id] = true
	return true


func _intent_id(event_id: String) -> String:
	return IDEMPOTENCY_PREFIX + event_id


func _apply_action(event: Dictionary, ctx: Dictionary) -> void:
	var raw_action = event.get("action", {})
	if not raw_action is Dictionary:
		return
	var action: Dictionary = raw_action
	var action_type := str(action.get("type", ""))
	if action_type == "scene":
		var target := str(action.get("target", action.get("scene_id", ""))).strip_edges()
		if target != "":
			_call_optional(ctx.get("scene_callback", Callable()), target)
			scene_requested.emit(target)
	elif action_type == "cutscene":
		var cutscene_id := str(action.get("target", action.get("cutscene_id", ""))).strip_edges()
		if cutscene_id != "":
			var cutscene_player = ctx.get("cutscene_player")
			if cutscene_player != null and cutscene_player.has_method("play"):
				cutscene_player.play(cutscene_id)
			cutscene_requested.emit(cutscene_id)
	elif action_type == "effect":
		var effects = action.get("effects", {})
		var state = _get_state(ctx)
		if effects is Dictionary and state != null:
			if state.has_method("apply_effects"):
				state.apply_effects(effects)
			_apply_story_flag_fallback(state, effects)
	event_fired.emit(str(event.get("id", "")), action)


func _apply_story_flag_fallback(state, effects: Dictionary) -> void:
	if state == null or not effects.has("story_flag") or not state.has_method("set_story_flag"):
		return
	var flag_value = effects["story_flag"]
	if flag_value is String:
		state.set_story_flag(flag_value, true)
	elif flag_value is Dictionary:
		for key in flag_value.keys():
			state.set_story_flag(str(key), flag_value[key])

func _call_optional(cb, value: String) -> void:
	if cb is Callable and cb.is_valid():
		cb.call(value)


func _get_state(ctx: Dictionary):
	if ctx.has("state") and ctx.get("state") != null:
		return ctx.get("state")
	if _state != null:
		return _state
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/GameState")
	return null
