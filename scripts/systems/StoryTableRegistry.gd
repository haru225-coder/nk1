class_name StoryTableRegistry extends RefCounted

## 太阁式札/称号/关系/设施触发表读取器。
## 只负责读取配置，不直接修改 GameState。

const DATA_PATH := ResourcePaths.DATA_STORY_TABLES

static var _data: Dictionary = {}
static var _loaded := false

const DATA_NPCS_PATH := ResourcePaths.DATA_NPCS
const SCENES_DIR_PATH := ResourcePaths.DIR_DATA_SCENES
const SCENES_FALLBACK_PATH := ResourcePaths.DATA_SCENES
const VALID_EFFECT_TYPES := [
	"unlock_action",
	"fame_bonus",
	"money_bonus",
	"npc_relationship_bonus",
	"port_affinity_bonus",
]
const BONUS_EFFECT_TARGET_STATS := {
	"fame_bonus": "fame",
	"money_bonus": "money",
	"npc_relationship_bonus": "npc_relationship",
	"port_affinity_bonus": "port_affinity",
}
const AUTO_GRANT_SECTIONS := ["cards", "titles"]

static func reload() -> void:
	_loaded = false
	_data.clear()
	_ensure_loaded()

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[StoryTableRegistry] 无法加载: " + DATA_PATH)
		_loaded = true
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_data = parsed
	_loaded = true

static func get_card(card_id: String) -> Dictionary:
	return _get_entry("cards", card_id)

static func get_title(title_id: String) -> Dictionary:
	return _get_entry("titles", title_id)

static func get_relationship(npc_id: String) -> Dictionary:
	return _get_entry("relationships", npc_id)

static func get_facility_trigger(trigger_id: String) -> Dictionary:
	return _get_entry("facility_triggers", trigger_id)

static func get_entries(section: String) -> Dictionary:
	_ensure_loaded()
	var entries = _data.get(section, {})
	if entries is Dictionary:
		return entries.duplicate(true)
	return {}

static func validate_schema(table_data: Dictionary = {}) -> Array:
	var data := table_data
	if data.is_empty():
		_ensure_loaded()
		data = _data
	var errors: Array = []
	var refs := {
		"scene_actions": _load_scene_action_index(),
		"ports": _load_id_set(ResourcePaths.DATA_PORTS, "ports"),
		"npcs": _load_id_set(DATA_NPCS_PATH, "npcs"),
	}
	var seen_effect_ids := {}
	for section in ["cards", "titles", "relationships"]:
		var raw_entries = data.get(section, {})
		if not raw_entries is Dictionary:
			errors.append("%s must be Dictionary" % section)
			continue
		var entries: Dictionary = raw_entries
		for raw_entry_id in entries.keys():
			var entry_id := str(raw_entry_id)
			var entry_path := "%s.%s" % [section, entry_id]
			var raw_entry = entries.get(raw_entry_id, {})
			if not raw_entry is Dictionary:
				errors.append("%s must be Dictionary" % entry_path)
				continue
			var entry: Dictionary = raw_entry
			_validate_entry_effects(errors, entry_path, entry, seen_effect_ids, refs)
			_validate_entry_task_chain(errors, entry_path, entry, refs)
			_validate_entry_route(errors, entry_path, entry, refs)
			_validate_entry_auto_grant(errors, entry_path, section, entry)
	return errors

static func get_auto_grants(story_state, ctx: Dictionary = {}) -> Array:
	_ensure_loaded()
	var out: Array = []
	for section in AUTO_GRANT_SECTIONS:
		_append_auto_grants(out, section, story_state, ctx)
	return out

static func apply_auto_grants(story_state, ctx: Dictionary = {}) -> Array:
	var grants := get_auto_grants(story_state, ctx)
	for raw_grant in grants:
		if raw_grant is Dictionary:
			_apply_auto_grant(story_state, raw_grant)
	return grants

static func get_active_effects(story_state) -> Array:
	_ensure_loaded()
	var out: Array = []
	_append_owned_effects(out, "cards", story_state)
	_append_owned_effects(out, "titles", story_state)
	_append_relationship_effects(out, story_state)
	return out

static func has_active_effect(story_state, effect_id: String) -> bool:
	if effect_id == "":
		return false
	for raw_effect in get_active_effects(story_state):
		if raw_effect is Dictionary and str(raw_effect.get("id", "")) == effect_id:
			return true
	return false

static func get_effect_delta(story_state, target_stat: String, ctx: Dictionary = {}) -> float:
	var total := 0.0
	for raw_effect in get_active_effects(story_state):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if not _effect_targets_stat(effect, target_stat):
			continue
		if not _effect_matches_context(effect, ctx):
			continue
		total += _effect_delta(effect)
	return total

static func get_effect_bonus_details(story_state, target_stat: String, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for raw_effect in get_active_effects(story_state):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if not _effect_targets_stat(effect, target_stat):
			continue
		if not _effect_matches_context(effect, ctx):
			continue
		var detail: Dictionary = effect.duplicate(true)
		detail["delta"] = _effect_delta(effect)
		out.append(detail)
	return out

static func get_effect_bonus(story_state, target_stat: String, ctx: Dictionary = {}) -> int:
	return int(get_effect_delta(story_state, target_stat, ctx))

static func _effect_delta(effect: Dictionary) -> float:
	return float(effect.get("amount", effect.get("delta", 0)))

static func _effect_targets_stat(effect: Dictionary, target_stat: String) -> bool:
	if target_stat == "":
		return false
	if str(effect.get("target_stat", "")) == target_stat:
		return true
	if str(effect.get("stat", "")) == target_stat:
		return true
	return str(effect.get("type", "")) == target_stat + "_bonus"

static func _effect_matches_context(effect: Dictionary, ctx: Dictionary) -> bool:
	if effect.has("trigger_on"):
		var ctx_trigger := str(ctx.get("trigger_on", ""))
		if ctx_trigger == "":
			return false
		var raw_trigger = effect.get("trigger_on", "")
		if raw_trigger is Array:
			if not ctx_trigger in raw_trigger:
				return false
		elif ctx_trigger != str(raw_trigger):
			return false
	if not _effect_context_matches(effect, ctx, ["target_port_id", "port_id"], "port_id"):
		return false
	if not _effect_context_matches(effect, ctx, ["target_npc_id", "npc_id"], "npc_id"):
		return false
	if not _effect_context_matches(effect, ctx, ["target_good_id", "good_id"], "good_id"):
		return false
	for key in ["facility_id", "scene_id", "trade_action", "intent_type"]:
		if not _effect_context_matches(effect, ctx, [key], key):
			return false
	return true

static func _effect_context_matches(effect: Dictionary, ctx: Dictionary, effect_keys: Array, ctx_key: String) -> bool:
	var expected := ""
	for key in effect_keys:
		if effect.has(key):
			expected = str(effect.get(key, ""))
			break
	if expected == "":
		return true
	if not ctx.has(ctx_key):
		return false
	return str(ctx.get(ctx_key, "")) == expected

static func _append_auto_grants(out: Array, section: String, story_state, ctx: Dictionary) -> void:
	var entries: Dictionary = _data.get(section, {})
	for raw_id in entries.keys():
		var entry_id := str(raw_id)
		if _state_has_entry(story_state, section, entry_id):
			continue
		var entry = entries.get(raw_id, {})
		if not entry is Dictionary:
			continue
		for raw_rule in _auto_grant_rules(entry):
			if raw_rule is Dictionary and _auto_grant_rule_matches(story_state, raw_rule, ctx):
				out.append({
					"section": section,
					"id": entry_id,
					"entry": entry.duplicate(true),
					"rule": raw_rule.duplicate(true),
				})
				break

static func _auto_grant_rules(entry: Dictionary) -> Array:
	var raw_rules = entry.get("auto_grant", entry.get("grant_conditions", null))
	if raw_rules == null:
		return []
	if raw_rules is Array:
		return raw_rules
	if raw_rules is Dictionary:
		return [raw_rules]
	return []

static func _auto_grant_rule_matches(story_state, rule: Dictionary, ctx: Dictionary) -> bool:
	if not _auto_grant_trigger_matches(rule, ctx):
		return false
	var conditions := _auto_grant_conditions(rule)
	var match_ctx := ctx.duplicate(true)
	if not match_ctx.has("game_state"):
		match_ctx["game_state"] = story_state
	var evaluator = load(ResourcePaths.SCRIPT_CONDITION_EVALUATOR)
	if evaluator != null:
		return evaluator.matches(conditions, match_ctx)
	return conditions.is_empty()

static func _auto_grant_trigger_matches(rule: Dictionary, ctx: Dictionary) -> bool:
	var ctx_trigger := str(ctx.get("trigger_on", ""))
	if ctx_trigger == "" or not rule.has("trigger_on"):
		return false
	var raw_trigger = rule.get("trigger_on", "")
	if raw_trigger is Array:
		return ctx_trigger in raw_trigger
	return ctx_trigger == str(raw_trigger)

static func _auto_grant_conditions(rule: Dictionary) -> Dictionary:
	var raw_conditions = rule.get("conditions", {})
	if raw_conditions is Dictionary:
		return raw_conditions
	return {}

static func _apply_auto_grant(story_state, grant: Dictionary) -> void:
	if story_state == null or not story_state is Object:
		return
	var section := str(grant.get("section", ""))
	var entry_id := str(grant.get("id", ""))
	if entry_id == "":
		return
	if section == "cards" and story_state.has_method("grant_card"):
		story_state.grant_card(entry_id)
	elif section == "titles" and story_state.has_method("grant_title"):
		story_state.grant_title(entry_id)

static func _validate_entry_effects(errors: Array, entry_path: String, entry: Dictionary, seen_effect_ids: Dictionary, refs: Dictionary) -> void:
	var raw_effects = entry.get("effects", [])
	if raw_effects == null:
		return
	if not raw_effects is Array:
		errors.append("%s.effects must be Array" % entry_path)
		return
	var effects: Array = raw_effects
	for index in range(effects.size()):
		var effect_path := "%s.effects[%d]" % [entry_path, index]
		var raw_effect = effects[index]
		if not raw_effect is Dictionary:
			errors.append("%s must be Dictionary" % effect_path)
			continue
		var effect: Dictionary = raw_effect
		_validate_effect(errors, effect_path, effect, seen_effect_ids, refs)

static func _validate_effect(errors: Array, effect_path: String, effect: Dictionary, seen_effect_ids: Dictionary, refs: Dictionary) -> void:
	var effect_id := str(effect.get("id", "")).strip_edges()
	if effect_id == "":
		errors.append("%s.id must be non-empty" % effect_path)
	elif seen_effect_ids.has(effect_id):
		errors.append("%s.id duplicate effect id: %s" % [effect_path, effect_id])
	else:
		seen_effect_ids[effect_id] = effect_path

	var effect_type := str(effect.get("type", "")).strip_edges()
	if effect_type == "":
		errors.append("%s.type must be non-empty" % effect_path)
		return
	if effect_type not in VALID_EFFECT_TYPES:
		errors.append("%s.type invalid effect type: %s" % [effect_path, effect_type])
		return
	if effect_type == "unlock_action":
		_validate_unlock_effect(errors, effect_path, effect, refs)
		return
	_validate_bonus_effect(errors, effect_path, effect, str(BONUS_EFFECT_TARGET_STATS.get(effect_type, "")), refs)

static func _validate_unlock_effect(errors: Array, effect_path: String, effect: Dictionary, refs: Dictionary) -> void:
	var scene_id := str(effect.get("target_scene_id", "")).strip_edges()
	var action_id := str(effect.get("target_action_id", "")).strip_edges()
	if scene_id == "":
		errors.append("%s.target_scene_id must be non-empty" % effect_path)
	elif not _schema_scene_exists(refs, scene_id):
		errors.append("%s.target_scene_id missing scene: %s" % [effect_path, scene_id])
	if action_id == "":
		errors.append("%s.target_action_id must be non-empty" % effect_path)
	elif scene_id != "" and _schema_scene_exists(refs, scene_id):
		_validate_action_ref(errors, "%s.target_action_id" % effect_path, scene_id, action_id, refs)

static func _validate_bonus_effect(errors: Array, effect_path: String, effect: Dictionary, expected_stat: String, refs: Dictionary) -> void:
	_validate_trigger_on(errors, effect_path, effect)
	var actual_stat := str(effect.get("target_stat", effect.get("stat", ""))).strip_edges()
	if actual_stat == "":
		errors.append("%s.target_stat must be non-empty (expected target_stat %s)" % [effect_path, expected_stat])
	elif actual_stat != expected_stat:
		errors.append("%s.target_stat expected target_stat %s, got %s" % [effect_path, expected_stat, actual_stat])
	if not effect.has("delta") and not effect.has("amount"):
		errors.append("%s.delta or amount must be numeric" % effect_path)
	else:
		var raw_delta = effect.get("delta", effect.get("amount", 0))
		if not _schema_is_number(raw_delta):
			errors.append("%s.delta or amount must be numeric" % effect_path)
	if expected_stat == "npc_relationship":
		_validate_id_ref(errors, effect_path, effect, "target_npc_id", "npc", refs.get("npcs", {}))
	elif expected_stat == "port_affinity":
		_validate_id_ref(errors, effect_path, effect, "target_port_id", "port", refs.get("ports", {}))

static func _validate_trigger_on(errors: Array, effect_path: String, effect: Dictionary) -> void:
	if not effect.has("trigger_on"):
		errors.append("%s.trigger_on must be non-empty" % effect_path)
		return
	var raw_trigger = effect.get("trigger_on")
	if raw_trigger is String:
		if str(raw_trigger).strip_edges() == "":
			errors.append("%s.trigger_on must be non-empty" % effect_path)
		return
	if raw_trigger is Array:
		var triggers: Array = raw_trigger
		if triggers.is_empty():
			errors.append("%s.trigger_on must be non-empty" % effect_path)
		for index in range(triggers.size()):
			if str(triggers[index]).strip_edges() == "":
				errors.append("%s.trigger_on[%d] must be non-empty" % [effect_path, index])
		return
	errors.append("%s.trigger_on must be String or Array" % effect_path)

static func _validate_id_ref(errors: Array, path: String, data: Dictionary, key: String, label: String, known_ids: Dictionary) -> void:
	var value := str(data.get(key, "")).strip_edges()
	if value == "":
		errors.append("%s.%s must be non-empty" % [path, key])
		return
	if not known_ids.is_empty() and not known_ids.has(value):
		errors.append("%s.%s missing %s: %s" % [path, key, label, value])

static func _validate_entry_auto_grant(errors: Array, entry_path: String, section: String, entry: Dictionary) -> void:
	if not entry.has("auto_grant") and not entry.has("grant_conditions"):
		return
	if section not in AUTO_GRANT_SECTIONS:
		errors.append("%s.auto_grant unsupported section: %s" % [entry_path, section])
		return
	var rules := _auto_grant_rules(entry)
	if rules.is_empty():
		errors.append("%s.auto_grant must be Dictionary or Array" % entry_path)
		return
	for index in range(rules.size()):
		var rule_path := "%s.auto_grant[%d]" % [entry_path, index]
		var raw_rule = rules[index]
		if not raw_rule is Dictionary:
			errors.append("%s must be Dictionary" % rule_path)
			continue
		var rule: Dictionary = raw_rule
		_validate_trigger_on(errors, rule_path, rule)
		if rule.has("conditions") and not rule.get("conditions") is Dictionary:
			errors.append("%s.conditions must be Dictionary" % rule_path)

static func _validate_entry_task_chain(errors: Array, entry_path: String, entry: Dictionary, refs: Dictionary) -> void:
	var raw_chain = entry.get("task_chain", [])
	if raw_chain == null:
		return
	if not raw_chain is Array:
		errors.append("%s.task_chain must be Array" % entry_path)
		return
	var chain: Array = raw_chain
	for index in range(chain.size()):
		var step_path := "%s.task_chain[%d]" % [entry_path, index]
		var raw_step = chain[index]
		if not raw_step is Dictionary:
			errors.append("%s must be Dictionary" % step_path)
			continue
		var step: Dictionary = raw_step
		_validate_task_step(errors, step_path, step, refs)

static func _validate_task_step(errors: Array, step_path: String, step: Dictionary, refs: Dictionary) -> void:
	if str(step.get("id", "")).strip_edges() == "":
		errors.append("%s.id must be non-empty" % step_path)
	var completed_by := str(step.get("completed_by", "")).strip_edges()
	if completed_by == "":
		errors.append("%s.completed_by must be non-empty" % step_path)
	elif completed_by == "story_flag":
		if str(step.get("story_flag", "")).strip_edges() == "":
			errors.append("%s.story_flag must be non-empty" % step_path)
	elif completed_by == "relationship_min":
		if not step.has("relationship_min") or not _schema_is_number(step.get("relationship_min")):
			errors.append("%s.relationship_min must be numeric" % step_path)
	elif completed_by != "acquired":
		errors.append("%s.completed_by unsupported value: %s" % [step_path, completed_by])

	var scene_id := str(step.get("scene_id", "")).strip_edges()
	var focus_action_id := str(step.get("focus_action_id", "")).strip_edges()
	if focus_action_id != "" and scene_id == "":
		errors.append("%s.scene_id must be non-empty when focus_action_id is set" % step_path)
	if scene_id != "":
		if not _schema_scene_exists(refs, scene_id):
			errors.append("%s.scene_id missing scene: %s" % [step_path, scene_id])
		elif focus_action_id != "":
			_validate_action_ref(errors, "%s.focus_action_id" % step_path, scene_id, focus_action_id, refs)

static func _validate_entry_route(errors: Array, entry_path: String, entry: Dictionary, refs: Dictionary) -> void:
	var scene_id := str(entry.get("route_scene_id", "")).strip_edges()
	var focus_action_id := str(entry.get("route_focus_action_id", "")).strip_edges()
	if focus_action_id != "" and scene_id == "":
		errors.append("%s.route_scene_id must be non-empty when route_focus_action_id is set" % entry_path)
	if scene_id == "":
		return
	if not _schema_scene_exists(refs, scene_id):
		errors.append("%s.route_scene_id missing scene: %s" % [entry_path, scene_id])
	elif focus_action_id != "":
		_validate_action_ref(errors, "%s.route_focus_action_id" % entry_path, scene_id, focus_action_id, refs)

static func _schema_scene_exists(refs: Dictionary, scene_id: String) -> bool:
	var scene_actions: Dictionary = refs.get("scene_actions", {})
	var scenes: Dictionary = scene_actions.get("scenes", {})
	return scenes.has(scene_id)

static func _validate_action_ref(errors: Array, path: String, scene_id: String, action_id: String, refs: Dictionary) -> void:
	var scene_actions: Dictionary = refs.get("scene_actions", {})
	var actions_by_scene: Dictionary = scene_actions.get("actions", {})
	var actions: Dictionary = actions_by_scene.get(scene_id, {})
	if not actions.has(action_id):
		errors.append("%s missing action: %s in scene %s" % [path, action_id, scene_id])

static func _load_scene_action_index() -> Dictionary:
	var index := {"scenes": {}, "actions": {}}
	var dir := DirAccess.open(SCENES_DIR_PATH)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				_append_scenes_to_index(index, _load_json_dict(SCENES_DIR_PATH + file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
	var scenes: Dictionary = index.get("scenes", {})
	if scenes.is_empty():
		_append_scenes_to_index(index, _load_json_dict(SCENES_FALLBACK_PATH))
	return index

static func _append_scenes_to_index(index: Dictionary, data: Dictionary) -> void:
	var scenes: Dictionary = index.get("scenes", {})
	var actions_by_scene: Dictionary = index.get("actions", {})
	for raw_scene in data.get("scenes", []):
		if not raw_scene is Dictionary:
			continue
		var scene: Dictionary = raw_scene
		var scene_id := str(scene.get("id", "")).strip_edges()
		if scene_id == "":
			continue
		scenes[scene_id] = true
		var actions: Dictionary = actions_by_scene.get(scene_id, {})
		for raw_inv in scene.get("investigations", []):
			if not raw_inv is Dictionary:
				continue
			var action_id := _schema_action_id(raw_inv)
			if action_id != "":
				actions[action_id] = true
		actions_by_scene[scene_id] = actions
	index["scenes"] = scenes
	index["actions"] = actions_by_scene

static func _schema_action_id(inv: Dictionary) -> String:
	var explicit := str(inv.get("id", "")).strip_edges()
	if explicit != "":
		return explicit
	var once_flag := str(inv.get("once_flag", "")).strip_edges()
	if once_flag != "":
		return once_flag
	return str(inv.get("label", "")).strip_edges()

static func _load_id_set(path: String, list_key: String) -> Dictionary:
	var out := {}
	var data := _load_json_dict(path)
	var raw_items = data.get(list_key, [])
	if not raw_items is Array:
		return out
	for raw_item in raw_items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		var item_id := str(item.get("id", "")).strip_edges()
		if item_id != "":
			out[item_id] = true
	return out

static func _load_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

static func _schema_is_number(value) -> bool:
	var value_type := typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT

static func get_facility_triggers_for(port_id: String, facility_id: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	var triggers: Dictionary = _data.get("facility_triggers", {})
	for trigger_id in triggers.keys():
		var entry = triggers[trigger_id]
		if not entry is Dictionary:
			continue
		if str(entry.get("port_id", "")) != port_id:
			continue
		if str(entry.get("facility_id", "")) != facility_id:
			continue
		var copied: Dictionary = entry.duplicate(true)
		copied["id"] = trigger_id
		out.append(copied)
	return out

static func _append_owned_effects(out: Array, section: String, story_state) -> void:
	var entries: Dictionary = _data.get(section, {})
	for raw_id in entries.keys():
		var entry_id := str(raw_id)
		if not _state_has_entry(story_state, section, entry_id):
			continue
		var entry = entries.get(raw_id, {})
		if entry is Dictionary:
			_append_entry_effects(out, section, entry_id, entry)

static func _append_relationship_effects(out: Array, story_state) -> void:
	var entries: Dictionary = _data.get("relationships", {})
	for raw_id in entries.keys():
		var npc_id := str(raw_id)
		var entry = entries.get(raw_id, {})
		if not entry is Dictionary:
			continue
		var value := _state_relationship_value(story_state, npc_id)
		for raw_effect in entry.get("effects", []):
			if not raw_effect is Dictionary:
				continue
			var threshold := int(raw_effect.get("relationship_min", _relationship_unlock_min(entry)))
			if value < threshold:
				continue
			var effect: Dictionary = raw_effect.duplicate(true)
			effect["source_section"] = "relationships"
			effect["source_id"] = npc_id
			effect["active"] = true
			out.append(effect)

static func _append_entry_effects(out: Array, section: String, entry_id: String, entry: Dictionary) -> void:
	for raw_effect in entry.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect.duplicate(true)
		if str(effect.get("id", "")) == "":
			continue
		effect["source_section"] = section
		effect["source_id"] = entry_id
		effect["active"] = true
		out.append(effect)

static func _state_has_entry(story_state, section: String, entry_id: String) -> bool:
	if story_state == null:
		return false
	if section == "cards" and story_state is Object and story_state.has_method("has_card"):
		return story_state.has_card(entry_id)
	if section == "titles" and story_state is Object and story_state.has_method("has_title"):
		return story_state.has_title(entry_id)
	var values := _field_dict(story_state, section)
	return values.get(entry_id, false) == true

static func _state_relationship_value(story_state, npc_id: String) -> int:
	if story_state == null:
		return 0
	if story_state is Object and story_state.has_method("get_npc_relationship"):
		return int(story_state.get_npc_relationship(npc_id))
	return int(_field_dict(story_state, "npc_relationships").get(npc_id, 0))

static func _relationship_unlock_min(entry: Dictionary) -> int:
	for raw_level in entry.get("levels", []):
		if raw_level is Dictionary and int(raw_level.get("min", 0)) > 0:
			return int(raw_level.get("min", 0))
	return 0

static func _field_dict(source, key: String) -> Dictionary:
	if source == null:
		return {}
	var value = source.get(key, {}) if source is Dictionary else source.get(key)
	if value is Dictionary:
		return value
	return {}

static func _get_entry(section: String, entry_id: String) -> Dictionary:
	_ensure_loaded()
	var entries: Dictionary = _data.get(section, {})
	var entry = entries.get(entry_id, {})
	if entry is Dictionary:
		return entry
	return {}
