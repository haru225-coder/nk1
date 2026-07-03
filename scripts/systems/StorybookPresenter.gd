class_name StorybookPresenter extends RefCounted

## 将 StoryState + story_tables.json 格式化为玩家可读的太阁式札册数据/文本。
## 纯展示层：不修改状态，不触发事件。

const StoryTables := preload(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY)
const LOCKED_DISPLAY_NAME := "？？？"
const TAB_CARDS := "札"
const TAB_TITLES := "称号"
const TAB_RELATIONSHIPS := "人物关系"

static func build_text(story_state) -> String:
	var lines := PackedStringArray()
	lines.append("【情报札记】")
	lines.append("")
	_append_cards(lines, story_state)
	lines.append("")
	_append_titles(lines, story_state)
	lines.append("")
	_append_relationships(lines, story_state)
	return "\n".join(lines)

static func build_view_model(story_state) -> Dictionary:
	var cards := _build_item_rows("cards", _field_dict(story_state, "cards"), "card", story_state)
	var titles := _build_item_rows("titles", _field_dict(story_state, "titles"), "title", story_state)
	var relationships := _build_relationship_rows(story_state)
	return {
		"tabs": [TAB_CARDS, TAB_TITLES, TAB_RELATIONSHIPS],
		"cards": cards,
		"titles": titles,
		"relationships": relationships,
		"card_total": cards.size(),
		"card_acquired": _count_acquired(cards),
		"title_total": titles.size(),
		"title_acquired": _count_acquired(titles),
		"relationship_total": relationships.size(),
	}

static func _append_cards(lines: PackedStringArray, story_state) -> void:
	lines.append("◆ 札")
	var card_ids := _truthy_keys(_field_dict(story_state, "cards"))
	if card_ids.is_empty():
		lines.append("（未获得札）")
		return
	for card_id in card_ids:
		var entry := StoryTables.get_card(card_id)
		var name := str(entry.get("name", card_id))
		var category := str(entry.get("category", "札"))
		var desc := str(entry.get("description", ""))
		var suffix := " — " + desc if desc != "" else ""
		lines.append("・%s [%s]%s" % [name, category, suffix])

static func _append_titles(lines: PackedStringArray, story_state) -> void:
	lines.append("◆ 称号")
	var title_ids := _truthy_keys(_field_dict(story_state, "titles"))
	if title_ids.is_empty():
		lines.append("（未获得称号）")
		return
	for title_id in title_ids:
		var entry := StoryTables.get_title(title_id)
		var name := str(entry.get("name", title_id))
		var rank := int(entry.get("rank", 0))
		var desc := str(entry.get("description", ""))
		var rank_text := " ★%d" % rank if rank > 0 else ""
		var suffix := " — " + desc if desc != "" else ""
		lines.append("・%s%s%s" % [name, rank_text, suffix])

static func _append_relationships(lines: PackedStringArray, story_state) -> void:
	lines.append("◆ 人物关系")
	var rows := _build_relationship_rows(story_state)
	if rows.is_empty():
		lines.append("（暂无人物关系）")
		return
	for row: Dictionary in rows:
		lines.append("・%s：%d（%s）" % [row.get("label", ""), int(row.get("value", 0)), row.get("level", "初识")])

static func _build_item_rows(section: String, owned: Dictionary, item_type: String, story_state) -> Array:
	var entries := StoryTables.get_entries(section)
	var ids: Array = []
	for raw_id in entries.keys():
		ids.append(str(raw_id))
	for raw_id in owned.keys():
		var item_id := str(raw_id)
		if owned.get(raw_id, false) == true and item_id not in ids:
			ids.append(item_id)
	ids.sort()

	var out: Array = []
	for item_id in ids:
		var entry: Dictionary = entries.get(item_id, {})
		var acquired: bool = owned.get(item_id, false) == true
		var real_name := str(entry.get("name", item_id))
		var rank := int(entry.get("rank", 0))
		var category := str(entry.get("category", item_type))
		var desc := str(entry.get("description", ""))
		var unlock_text := str(entry.get("unlock_text", "")) if acquired else ""
		var active_effects := _entry_active_effects(entry, acquired)
		var route_action_id := str(entry.get("route_focus_action_id", ""))
		var route_completed := _route_action_completed(story_state, route_action_id)
		var task_chain := _build_item_task_chain(item_id, item_type, real_name, acquired, entry, route_action_id, route_completed, story_state)
		var task_progress := _task_progress(task_chain)
		out.append({
			"id": item_id,
			"type": item_type,
			"name": real_name,
			"display_name": real_name if acquired else LOCKED_DISPLAY_NAME,
			"category": category,
			"rank": rank,
			"description": desc if acquired else "未获得：继续推进剧情、设施、交易或人物事件。",
			"unlock_text": unlock_text,
			"effects": active_effects,
			"effect_text": _effect_summary(active_effects),
			"active_bonus_text": _active_bonus_summary(active_effects),
			"source_event": str(entry.get("source_event", "")),
			"source_text": str(entry.get("source_text", "")),
			"route_scene_id": str(entry.get("route_scene_id", "")),
			"route_label": str(entry.get("route_label", "")),
			"route_focus_action_id": route_action_id,
			"route_action_completed": route_completed,
			"route_action_status": _route_action_status(route_action_id, route_completed),
			"task_chain": task_chain,
			"task_progress_done": int(task_progress.get("done", 0)),
			"task_progress_total": int(task_progress.get("total", 0)),
			"task_progress_text": _task_progress_text(task_progress),
			"next_recommendation": _next_recommendation(task_chain),
			"acquired": acquired,
			"status": "已获得" if acquired else "未获得",
		})
	return out

static func _build_relationship_rows(story_state) -> Array:
	var relationships := _field_dict(story_state, "npc_relationships")
	var entries := StoryTables.get_entries("relationships")
	var npc_ids: Array = []
	for npc_id in entries.keys():
		npc_ids.append(str(npc_id))
	for npc_id in relationships.keys():
		var sid := str(npc_id)
		if sid not in npc_ids:
			npc_ids.append(sid)
	npc_ids.sort()

	var out: Array = []
	for npc_id in npc_ids:
		var entry: Dictionary = entries.get(npc_id, {})
		var value := int(relationships.get(npc_id, 0))
		var active_effects := _relationship_active_effects(entry, value)
		var route_action_id := str(entry.get("route_focus_action_id", ""))
		var route_completed := _route_action_completed(story_state, route_action_id)
		var task_chain := _build_relationship_task_chain(npc_id, entry, value, route_action_id, route_completed, story_state)
		var task_progress := _task_progress(task_chain)
		out.append({
			"id": npc_id,
			"type": "relationship",
			"label": str(entry.get("label", npc_id)),
			"value": value,
			"level": _relationship_level(entry, value),
			"description": str(entry.get("description", "")),
			"unlock_text": str(entry.get("unlock_text", "")),
			"effects": active_effects,
			"effect_text": _effect_summary(active_effects),
			"active_bonus_text": _active_bonus_summary(active_effects),
			"source_event": str(entry.get("source_event", "")),
			"source_text": str(entry.get("source_text", "")),
			"route_scene_id": str(entry.get("route_scene_id", "")),
			"route_label": str(entry.get("route_label", "")),
			"route_focus_action_id": route_action_id,
			"route_action_completed": route_completed,
			"route_action_status": _route_action_status(route_action_id, route_completed),
			"task_chain": task_chain,
			"task_progress_done": int(task_progress.get("done", 0)),
			"task_progress_total": int(task_progress.get("total", 0)),
			"task_progress_text": _task_progress_text(task_progress),
			"next_recommendation": _next_recommendation(task_chain),
			"portrait": str(entry.get("portrait", "")),
		})
	return out

static func _entry_active_effects(entry: Dictionary, acquired: bool) -> Array:
	if not acquired:
		return []
	return _copy_effects(entry.get("effects", []))

static func _relationship_active_effects(entry: Dictionary, value: int) -> Array:
	var out: Array = []
	for raw_effect in entry.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var threshold := int(raw_effect.get("relationship_min", _relationship_unlock_min(entry)))
		if value < threshold:
			continue
		out.append(raw_effect.duplicate(true))
	return out

static func _copy_effects(raw_effects) -> Array:
	var out: Array = []
	if not raw_effects is Array:
		return out
	for raw_effect in raw_effects:
		if raw_effect is Dictionary:
			out.append(raw_effect.duplicate(true))
	return out

static func _effect_summary(effects: Array) -> String:
	var labels := PackedStringArray()
	for raw_effect in effects:
		if not raw_effect is Dictionary:
			continue
		var label := _effect_label(raw_effect)
		if label != "":
			labels.append(label)
	return "；".join(labels)

static func _active_bonus_summary(effects: Array) -> String:
	var labels := PackedStringArray()
	for raw_effect in effects:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if not _is_numeric_bonus_effect(effect):
			continue
		var label := _effect_label(effect)
		if label == "":
			label = _generated_bonus_label(effect)
		if label != "":
			labels.append(label)
	return "；".join(labels)

static func _is_numeric_bonus_effect(effect: Dictionary) -> bool:
	return str(effect.get("type", "")).ends_with("_bonus") and (effect.has("delta") or effect.has("amount"))

static func _generated_bonus_label(effect: Dictionary) -> String:
	var stat := _effect_target_stat(effect)
	if stat == "":
		return ""
	var amount := _format_signed_bonus(effect.get("amount", effect.get("delta", 0)))
	var trigger := str(effect.get("trigger_on", ""))
	var suffix := "" if trigger == "" else "（" + trigger + "）"
	return "%s %s%s" % [stat, amount, suffix]

static func _effect_target_stat(effect: Dictionary) -> String:
	var target := str(effect.get("target_stat", effect.get("stat", "")))
	if target != "":
		return target
	var effect_type := str(effect.get("type", ""))
	if effect_type.ends_with("_bonus"):
		return effect_type.substr(0, effect_type.length() - 6)
	return ""

static func _format_signed_bonus(value) -> String:
	var amount := float(value)
	var prefix := "+" if amount >= 0.0 else ""
	if is_equal_approx(amount, float(int(amount))):
		return prefix + str(int(amount))
	return prefix + "%.1f" % amount

static func _effect_label(effect: Dictionary) -> String:
	var label := str(effect.get("label", ""))
	if label != "":
		return label
	if str(effect.get("type", "")) == "unlock_action":
		var action_id := str(effect.get("target_action_id", ""))
		return "解锁行动" if action_id == "" else "解锁行动：" + action_id
	return str(effect.get("id", ""))

static func _build_item_task_chain(item_id: String, item_type: String, item_name: String, acquired: bool, entry: Dictionary, route_action_id: String, route_completed: bool, story_state) -> Array:
	var configured := _build_configured_task_chain(entry, story_state, acquired)
	if not configured.is_empty():
		return configured
	var has_source := str(entry.get("source_event", "")) != ""
	if not has_source and route_action_id == "":
		return []
	var out: Array = []
	out.append(_make_task_step("acquire:" + item_id, "前置", _item_acquire_label(item_type, item_name), acquired))
	if route_action_id != "":
		out.append(_make_task_step(
			route_action_id,
			"后续",
			_task_action_label(entry, route_action_id),
			route_completed,
			str(entry.get("route_scene_id", "")),
			route_action_id
		))
	return out

static func _build_relationship_task_chain(npc_id: String, entry: Dictionary, value: int, route_action_id: String, route_completed: bool, story_state) -> Array:
	var threshold := _relationship_unlock_min(entry)
	var configured := _build_configured_task_chain(entry, story_state, false, value, threshold)
	if not configured.is_empty():
		return configured
	var has_source := str(entry.get("source_event", "")) != ""
	if not has_source and route_action_id == "":
		return []
	var out: Array = []
	var level_name := _relationship_level(entry, threshold)
	var pre_label := "关系达到" + level_name if level_name != "" else "提升人物关系"
	out.append(_make_task_step("relationship:" + npc_id, "前置", pre_label, value >= threshold))
	if route_action_id != "":
		out.append(_make_task_step(
			route_action_id,
			"后续",
			_task_action_label(entry, route_action_id),
			route_completed,
			str(entry.get("route_scene_id", "")),
			route_action_id
		))
	return out

static func _make_task_step(step_id: String, phase: String, label: String, completed: bool, scene_id: String = "", focus_action_id: String = "") -> Dictionary:
	var step := {
		"id": step_id,
		"phase": phase,
		"label": label,
		"completed": completed,
		"status": "已完成" if completed else "待处理",
	}
	if scene_id != "":
		step["scene_id"] = scene_id
	if focus_action_id != "":
		step["focus_action_id"] = focus_action_id
	return step

static func _build_configured_task_chain(entry: Dictionary, story_state, acquired: bool, relationship_value: int = 0, relationship_threshold: int = 0) -> Array:
	var raw_chain = entry.get("task_chain", [])
	if not raw_chain is Array:
		return []
	var out: Array = []
	for raw_step in raw_chain:
		if not raw_step is Dictionary:
			continue
		var step_entry: Dictionary = raw_step
		var step_id := str(step_entry.get("id", ""))
		if step_id == "":
			continue
		var label := str(step_entry.get("label", step_id))
		var step := _make_task_step(
			step_id,
			str(step_entry.get("phase", "任务")),
			label,
			_configured_task_step_completed(step_entry, story_state, acquired, relationship_value, relationship_threshold),
			str(step_entry.get("scene_id", "")),
			str(step_entry.get("focus_action_id", ""))
		)
		_copy_task_step_metadata(step, step_entry)
		out.append(step)
	return out

static func _configured_task_step_completed(step_entry: Dictionary, story_state, acquired: bool, relationship_value: int, relationship_threshold: int) -> bool:
	var completed_by := str(step_entry.get("completed_by", ""))
	if completed_by == "acquired":
		return acquired
	if completed_by == "story_flag":
		var flag_id := str(step_entry.get("story_flag", ""))
		if flag_id == "":
			flag_id = str(step_entry.get("focus_action_id", ""))
		if flag_id == "":
			flag_id = str(step_entry.get("id", ""))
		return _route_action_completed(story_state, flag_id)
	if completed_by == "relationship_min":
		var threshold := int(step_entry.get("relationship_min", relationship_threshold))
		return relationship_value >= threshold
	if completed_by == "always":
		return true
	return false

static func _copy_task_step_metadata(step: Dictionary, step_entry: Dictionary) -> void:
	for key in ["completed_by", "source_event", "source_text", "story_flag"]:
		var value := str(step_entry.get(key, ""))
		if value != "":
			step[key] = value
	if step_entry.has("relationship_min"):
		step["relationship_min"] = int(step_entry.get("relationship_min", 0))

static func _item_acquire_label(item_type: String, item_name: String) -> String:
	if item_name == "":
		return "获得条目"
	if item_type == "relationship":
		return "建立关系：" + item_name
	return "获得" + item_name

static func _task_action_label(entry: Dictionary, fallback_action_id: String) -> String:
	var unlock_text := str(entry.get("unlock_text", ""))
	var quoted := _extract_chinese_quote(unlock_text)
	if quoted != "":
		return quoted
	if unlock_text != "":
		return unlock_text.trim_suffix("。")
	return fallback_action_id

static func _extract_chinese_quote(text: String) -> String:
	var start := text.find("「")
	if start < 0:
		return ""
	var end := text.find("」", start + 1)
	if end <= start:
		return ""
	return text.substr(start + 1, end - start - 1)

static func _task_progress(chain: Array) -> Dictionary:
	var done := 0
	for raw_step in chain:
		if raw_step is Dictionary and raw_step.get("completed", false) == true:
			done += 1
	return {"done": done, "total": chain.size()}

static func _task_progress_text(progress: Dictionary) -> String:
	var total := int(progress.get("total", 0))
	if total <= 0:
		return ""
	return "%d/%d" % [int(progress.get("done", 0)), total]

static func _next_recommendation(chain: Array) -> String:
	if chain.is_empty():
		return ""
	for raw_step in chain:
		if raw_step is Dictionary and raw_step.get("completed", false) != true:
			return str(raw_step.get("label", ""))
	return "已完成全部链路"

static func _relationship_unlock_min(entry: Dictionary) -> int:
	var fallback := 0
	for raw_level in entry.get("levels", []):
		if not raw_level is Dictionary:
			continue
		var min_value := int(raw_level.get("min", 0))
		if min_value > 0:
			return min_value
		fallback = min_value
	return fallback

static func _route_action_completed(story_state, action_id: String) -> bool:
	if action_id == "" or story_state == null:
		return false
	if story_state is Object and story_state.has_method("has_story_flag"):
		return story_state.has_story_flag(action_id)
	var story_flags := _field_dict(story_state, "story_flags")
	if not story_flags.has(action_id):
		return false
	var value = story_flags[action_id]
	if value is bool:
		return value
	return value != null

static func _route_action_status(action_id: String, completed: bool) -> String:
	if action_id == "":
		return ""
	return "已处理" if completed else "待处理"

static func _count_acquired(items: Array) -> int:
	var count := 0
	for item: Dictionary in items:
		if item.get("acquired", false) == true:
			count += 1
	return count

static func _relationship_level(entry: Dictionary, value: int) -> String:
	var current := "初识"
	for raw_level in entry.get("levels", []):
		if not raw_level is Dictionary:
			continue
		if value >= int(raw_level.get("min", 0)):
			current = str(raw_level.get("name", current))
	return current

static func _field_dict(source, key: String) -> Dictionary:
	if source == null:
		return {}
	var value = source.get(key, {}) if source is Dictionary else source.get(key)
	if value is Dictionary:
		return value
	return {}

static func _truthy_keys(values: Dictionary) -> Array:
	var out: Array = []
	for key in values.keys():
		if values[key] == true:
			out.append(str(key))
	out.sort()
	return out
