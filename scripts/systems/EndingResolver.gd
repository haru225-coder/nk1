class_name EndingResolver extends RefCounted

## P7-E 结局判定模块
## 职责：读取 endings.json，在 CareerState apex 后选择并标记一个终局。

const DATA_PATH := ResourcePaths.DATA_ENDINGS

var _endings: Array = []
var _state = null
var _cutscene_player = null
var _loaded: bool = false
## 最近一次成功 evaluate 的结果（供结算屏读取）
var last_result: Dictionary = {}


func load_defs(path: String = DATA_PATH) -> void:
	_loaded = true
	_endings.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		load_from_data(parsed)


func load_from_data(data: Dictionary) -> void:
	_loaded = true
	_endings.clear()
	var raw_endings = data.get("endings", [])
	if not raw_endings is Array:
		return
	for raw_ending in raw_endings:
		if not raw_ending is Dictionary:
			continue
		var ending: Dictionary = raw_ending
		var ending_id := str(ending.get("id", "")).strip_edges()
		if ending_id == "":
			continue
		_endings.append(ending.duplicate(true))


func bind(state, cutscene_player = null) -> void:
	_state = state
	_cutscene_player = cutscene_player


func get_ending_count() -> int:
	_ensure_loaded()
	return _endings.size()


func evaluate(state = null, cutscene_player = null) -> IntentResult:
	_ensure_loaded()
	var target_state = state if state != null else _get_state()
	if target_state == null:
		return IntentResult.error("ending.no_state", "EndingResolver: missing state", "ending")
	if not _is_rank_apex(target_state):
		return IntentResult.error("ending.not_apex", "EndingResolver: rank apex required", "ending")

	var candidates: Array = []
	for raw_ending in _endings:
		if not raw_ending is Dictionary:
			continue
		var ending: Dictionary = raw_ending
		if _conditions_met(ending, target_state):
			candidates.append(ending)
	if candidates.is_empty():
		return IntentResult.error("ending.no_match", "EndingResolver: no ending matched", "ending")

	candidates.sort_custom(Callable(self, "_sort_endings"))
	var selected: Dictionary = candidates[0]
	_apply_terminal_state(selected, target_state)

	var player = cutscene_player if cutscene_player != null else _cutscene_player
	var cutscene_id := str(selected.get("cutscene", "")).strip_edges()
	var played := false
	if cutscene_id != "" and player != null and player.has_method("play"):
		player.play(cutscene_id)
		played = true

	last_result = {
		"ending_id": str(selected.get("id", "")),
		"cutscene": cutscene_id,
		"terminal_state": str(selected.get("terminal_state", "")),
		"cutscene_played": played,
		"title": str(selected.get("title", "")),
		"subtitle": str(selected.get("subtitle", "")),
		"summary": str(selected.get("summary", "")),
		"epilogue": str(selected.get("epilogue", "")),
	}
	return IntentResult.ok(last_result.duplicate(true), "ending.completed")


func get_last_result() -> Dictionary:
	return last_result.duplicate(true)


func get_ending_def(ending_id: String) -> Dictionary:
	_ensure_loaded()
	var id := ending_id.strip_edges()
	if id == "":
		return {}
	for raw in _endings:
		if not raw is Dictionary:
			continue
		if str(raw.get("id", "")) == id:
			return (raw as Dictionary).duplicate(true)
	return {}


## 供结算屏：合并 defs + 状态上的秩禄/日期
func build_display(state = null, ending_id: String = "") -> Dictionary:
	_ensure_loaded()
	var target_state = state if state != null else _get_state()
	var id := ending_id.strip_edges()
	if id == "" and not last_result.is_empty():
		id = str(last_result.get("ending_id", ""))
	if id == "" and target_state != null and target_state.has_method("get_story_flag"):
		var raw_id = target_state.get_story_flag("ending_id", "")
		if raw_id != null and str(raw_id) != "true" and str(raw_id) != "1":
			id = str(raw_id)
	var def := get_ending_def(id)
	var display: Dictionary = {}
	if not last_result.is_empty() and (id == "" or str(last_result.get("ending_id", "")) == id):
		display = last_result.duplicate(true)
		id = str(display.get("ending_id", id))
	if display.is_empty() and not def.is_empty():
		display = {
			"ending_id": id,
			"title": str(def.get("title", "")),
			"subtitle": str(def.get("subtitle", "")),
			"summary": str(def.get("summary", "")),
			"epilogue": str(def.get("epilogue", "")),
			"cutscene": str(def.get("cutscene", "")),
			"terminal_state": str(def.get("terminal_state", "")),
		}
	elif not def.is_empty():
		for k in ["title", "subtitle", "summary", "epilogue"]:
			if str(display.get(k, "")) == "" and def.has(k):
				display[k] = def[k]
	display["ending_id"] = id
	if str(display.get("title", "")) == "":
		display["title"] = id if id != "" else "终章"
	if target_state != null:
		var career = target_state.get("career")
		if career != null and career.has_method("get_title"):
			display["rank_title"] = str(career.get_title())
		var calendar = target_state.get("calendar")
		if calendar != null and calendar.has_method("date_key"):
			display["date_key"] = str(calendar.date_key())
	return display


func _ensure_loaded() -> void:
	if not _loaded:
		load_defs()


func _sort_endings(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa == pb:
		return str(a.get("id", "")) < str(b.get("id", ""))
	return pa > pb


func _conditions_met(ending: Dictionary, state) -> bool:
	var raw_condition = ending.get("condition", {})
	if not raw_condition is Dictionary:
		return true
	var condition: Dictionary = raw_condition
	if bool(condition.get("rank_apex", false)) and not _is_rank_apex(state):
		return false
	if condition.has("flag") and not _has_any_flag_or_item(state, str(condition.get("flag", ""))):
		return false
	if condition.has("flags"):
		for raw_flag in condition.get("flags", []):
			if not _has_any_flag_or_item(state, str(raw_flag)):
				return false
	if condition.has("item") and not _has_item(state, str(condition.get("item", ""))):
		return false
	if condition.has("items"):
		for raw_item in condition.get("items", []):
			if not _has_item(state, str(raw_item)):
				return false
	if condition.has("linboyuan_gte") and _get_relationship(state, "lin_boyuan") < int(condition.get("linboyuan_gte", 0)):
		return false
	if condition.has("jia_gte") and _get_relationship(state, "jia") < int(condition.get("jia_gte", 0)):
		return false
	if condition.has("relationship_gte") and not _relationship_condition_met(condition.get("relationship_gte"), state):
		return false
	return true


func _relationship_condition_met(raw_condition, state) -> bool:
	if raw_condition is Dictionary:
		var rels: Dictionary = raw_condition
		for raw_npc_id in rels.keys():
			var npc_id := str(raw_npc_id)
			if _get_relationship(state, npc_id) < int(rels[raw_npc_id]):
				return false
		return true
	return _get_relationship(state, "lin_boyuan") >= int(raw_condition)


func _apply_terminal_state(ending: Dictionary, state) -> void:
	if state == null or not state.has_method("set_story_flag"):
		return
	var ending_id := str(ending.get("id", ""))
	state.set_story_flag("game_completed", true)
	state.set_story_flag("ending_id", ending_id)
	if ending_id != "":
		state.set_story_flag("ending:" + ending_id, true)
	var terminal_state := str(ending.get("terminal_state", ""))
	if terminal_state != "":
		state.set_story_flag(terminal_state, true)


func _is_rank_apex(state) -> bool:
	if state == null:
		return false
	var career = state.get("career")
	if career != null and career.has_method("is_apex"):
		return bool(career.is_apex())
	if state.has_method("is_apex"):
		return bool(state.is_apex())
	return false


func _has_any_flag_or_item(state, key: String) -> bool:
	if key == "":
		return false
	if _has_story_flag(state, key) or _has_flag(state, key):
		return true
	return _has_item(state, key)


func _has_story_flag(state, key: String) -> bool:
	return state != null and state.has_method("has_story_flag") and bool(state.has_story_flag(key))


func _has_flag(state, key: String) -> bool:
	return state != null and state.has_method("has_flag") and bool(state.has_flag(key))


func _has_item(state, item_id: String) -> bool:
	return state != null and item_id != "" and state.has_method("has_item_flag") and bool(state.has_item_flag(item_id))


func _get_relationship(state, npc_id: String) -> int:
	if state == null or npc_id == "":
		return 0
	var value := 0
	if state.has_method("get_npc_relationship"):
		value = int(state.get_npc_relationship(npc_id))
	if npc_id == "lin_boyuan":
		value = max(value, _get_int_property(state, "linboyuan_relationship"))
	elif npc_id == "jia":
		value = max(value, _get_int_property(state, "jia_relationship"))
	return value


func _get_int_property(obj, property_name: String) -> int:
	if obj == null:
		return 0
	var raw = obj.get(property_name)
	return int(raw) if raw != null else 0


func _get_state():
	if _state != null:
		return _state
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/GameState")
	return null
