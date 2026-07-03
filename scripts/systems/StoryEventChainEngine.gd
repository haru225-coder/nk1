class_name StoryEventChainEngine extends RefCounted

## 太阁式前置条件事件链：加载配置 → 检测条件 → 应用 effects
## 消费者模式：不修改 WorldEventTracker [C3-STABLE]

const DATA_PATH := ResourcePaths.DATA_STORY_EVENT_CHAINS
const StoryTables := preload(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY)

static var _chains: Dictionary = {}
static var _loaded := false

static func reload() -> void:
	_loaded = false
	_chains.clear()
	_ensure_loaded()

static func _ensure_loaded() -> void:
	if _loaded:
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[StoryEventChainEngine] 无法加载: " + DATA_PATH)
		_loaded = true
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_chains = parsed.get("chains", {})
	_loaded = true

static func get_chain_ids() -> Array:
	_ensure_loaded()
	return _chains.keys()

static func get_chain(chain_id: String) -> Dictionary:
	_ensure_loaded()
	var chain = _chains.get(chain_id, {})
	if chain is Dictionary:
		return chain
	return {}

static func check_triggers(trigger_on: String, ctx: Dictionary = {}) -> Array:
	_ensure_loaded()
	var fired: Array = []
	for chain_id in _chains.keys():
		var chain: Dictionary = _chains[chain_id]
		if not _should_trigger(chain_id, chain, trigger_on, ctx):
			continue
		var fire_ctx := ctx.duplicate()
		fire_ctx["trigger_on"] = trigger_on
		_fire_chain(chain_id, chain, fire_ctx)
		fired.append(chain_id)
	var grant_ctx := ctx.duplicate()
	grant_ctx["trigger_on"] = trigger_on
	var grants := StoryTables.apply_auto_grants(_get_state(grant_ctx), grant_ctx)
	_emit_auto_grant_feedback(grants, grant_ctx)
	return fired


static func build_trigger_preview_text(trigger_on: String, ctx: Dictionary = {}) -> String:
	return str(preview_triggers(trigger_on, ctx).get("text", ""))

static func preview_triggers(trigger_on: String, ctx: Dictionary = {}) -> Dictionary:
	_ensure_loaded()
	var preview_ctx := ctx.duplicate()
	preview_ctx["trigger_on"] = trigger_on
	var state = _get_state(preview_ctx)
	var auto_grants: Array = []
	if state != null:
		auto_grants = StoryTables.get_auto_grants(state, preview_ctx)
	var chain_ids: Array = []
	var base_stats := {}
	for chain_id in _chains.keys():
		var chain: Dictionary = _chains[chain_id]
		if not _should_trigger(str(chain_id), chain, trigger_on, ctx):
			continue
		chain_ids.append(str(chain_id))
		for raw_effect in chain.get("effects", []):
			if raw_effect is Dictionary:
				_preview_accumulate_effect(base_stats, raw_effect, preview_ctx)
	if base_stats.is_empty() and auto_grants.is_empty():
		return {"chains": chain_ids, "base": base_stats, "bonus_groups": {}, "totals": {}, "auto_grants": auto_grants, "text": ""}

	var bonus_groups := {}
	var totals: Dictionary = base_stats.duplicate(true)
	if state != null:
		for raw_key in base_stats.keys():
			var entry: Dictionary = base_stats[raw_key]
			var stat := str(entry.get("stat", ""))
			var stat_ctx := _preview_ctx_for_entry(preview_ctx, entry)
			var details := StoryTables.get_effect_bonus_details(state, stat, stat_ctx)
			for raw_detail in details:
				if not raw_detail is Dictionary:
					continue
				var detail: Dictionary = raw_detail
				var delta := float(detail.get("delta", 0.0))
				if is_zero_approx(delta):
					continue
				var section := _preview_detail_section(detail)
				if not bonus_groups.has(section):
					bonus_groups[section] = {}
				_preview_add_stat(bonus_groups[section], stat, delta, stat_ctx)
				_preview_add_stat(totals, stat, delta, stat_ctx)

	return {
		"chains": chain_ids,
		"base": base_stats,
		"bonus_groups": bonus_groups,
		"totals": totals,
		"auto_grants": auto_grants,
		"text": _preview_build_text(base_stats, bonus_groups, totals, auto_grants),
	}

static func _preview_accumulate_effect(stats: Dictionary, effect: Dictionary, ctx: Dictionary) -> void:
	var effect_type := str(effect.get("type", ""))
	match effect_type:
		"apply_effects":
			var effects: Dictionary = effect.get("effects", {})
			for raw_key in effects.keys():
				_preview_accumulate_effect_value(stats, str(raw_key), effects[raw_key], ctx)
		"money":
			_preview_add_stat(stats, "money", float(effect.get("amount", effect.get("delta", 0))))
		"fame":
			_preview_add_stat(stats, "fame", float(effect.get("amount", effect.get("delta", 0))))
		"npc_relationship":
			_preview_add_stat(stats, "npc_relationship", float(effect.get("delta", 0)), {"npc_id": str(effect.get("npc_id", ""))})
		"port_affinity":
			_preview_add_stat(stats, "port_affinity", float(effect.get("delta", 0.0)), {"port_id": str(effect.get("port_id", ctx.get("port_id", "")))})

static func _preview_accumulate_effect_value(stats: Dictionary, stat: String, value, ctx: Dictionary) -> void:
	if stat == "fame" or stat == "money":
		if value is int or value is float:
			_preview_add_stat(stats, stat, float(value))
	elif stat == "npc_relationship" and value is Dictionary:
		var payload: Dictionary = value
		_preview_add_stat(stats, "npc_relationship", float(payload.get("delta", 0)), {"npc_id": str(payload.get("npc_id", ""))})
	elif stat == "port_affinity" and value is Dictionary:
		var payload: Dictionary = value
		_preview_add_stat(stats, "port_affinity", float(payload.get("delta", 0.0)), {"port_id": str(payload.get("port_id", ctx.get("port_id", "")))})

static func _preview_add_stat(stats: Dictionary, stat: String, delta: float, meta: Dictionary = {}) -> void:
	if stat == "" or is_zero_approx(delta):
		return
	var key := stat
	if stat == "npc_relationship":
		var npc_id := str(meta.get("npc_id", ""))
		if npc_id == "":
			return
		key = "npc_relationship:" + npc_id
	elif stat == "port_affinity":
		var port_id := str(meta.get("port_id", ""))
		if port_id == "":
			return
		key = "port_affinity:" + port_id
	if not stats.has(key):
		stats[key] = {"stat": stat, "delta": 0.0}
		if meta.has("npc_id"):
			stats[key]["npc_id"] = str(meta.get("npc_id", ""))
		if meta.has("port_id"):
			stats[key]["port_id"] = str(meta.get("port_id", ""))
	stats[key]["delta"] = float(stats[key].get("delta", 0.0)) + delta

static func _preview_ctx_for_entry(ctx: Dictionary, entry: Dictionary) -> Dictionary:
	var out := ctx.duplicate()
	if str(entry.get("npc_id", "")) != "":
		out["npc_id"] = str(entry.get("npc_id", ""))
	if str(entry.get("port_id", "")) != "":
		out["port_id"] = str(entry.get("port_id", ""))
	return out

static func _preview_detail_section(detail: Dictionary) -> String:
	var section := str(detail.get("source_section", ""))
	if section in ["cards", "titles", "relationships"]:
		return section
	return "other"

static func _preview_build_text(base_stats: Dictionary, bonus_groups: Dictionary, totals: Dictionary, auto_grants: Array = []) -> String:
	var lines: Array[String] = ["预计收益："]
	var base_text := _preview_format_stats(base_stats)
	if base_text != "":
		lines.append("基础：" + base_text)
	for section in ["cards", "titles", "relationships", "other"]:
		if not bonus_groups.has(section):
			continue
		var group_text := _preview_format_stats(bonus_groups[section])
		if group_text != "":
			lines.append(_preview_group_label(section) + "：" + group_text)
	var grant_text := _preview_format_auto_grants(auto_grants)
	if grant_text != "":
		lines.append("预计获得：" + grant_text)
	var total_text := _preview_format_stats(totals)
	if total_text != "":
		lines.append("合计：" + total_text)
	return "\n".join(lines)

static func _preview_format_auto_grants(grants: Array) -> String:
	var parts: Array[String] = []
	for raw_grant in grants:
		if not raw_grant is Dictionary:
			continue
		var grant: Dictionary = raw_grant
		var section := str(grant.get("section", ""))
		var entry_id := str(grant.get("id", ""))
		var raw_entry = grant.get("entry", {})
		var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
		var name := str(entry.get("name", entry.get("label", entry_id)))
		if name == "":
			name = entry_id
		if section == "cards":
			parts.append("札「%s」" % name)
		elif section == "titles":
			parts.append("称号「%s」" % name)
	return "，".join(parts)

static func _preview_group_label(section: String) -> String:
	match section:
		"cards":
			return "札效"
		"titles":
			return "称号"
		"relationships":
			return "关系"
		_:
			return "效果"

static func _preview_format_stats(stats: Dictionary) -> String:
	var parts: Array[String] = []
	for stat in ["fame", "money", "npc_relationship", "port_affinity"]:
		var keys := stats.keys()
		keys.sort()
		for raw_key in keys:
			var key := str(raw_key)
			var entry: Dictionary = stats[key]
			if str(entry.get("stat", "")) != stat:
				continue
			var delta := float(entry.get("delta", 0.0))
			if is_zero_approx(delta):
				continue
			parts.append(_preview_stat_label(entry) + _preview_signed_number(delta))
	return "，".join(parts)

static func _preview_stat_label(entry: Dictionary) -> String:
	var stat := str(entry.get("stat", ""))
	match stat:
		"fame":
			return "名声"
		"money":
			return "银两"
		"npc_relationship":
			return _preview_npc_label(str(entry.get("npc_id", ""))) + "关系"
		"port_affinity":
			return _preview_port_label(str(entry.get("port_id", ""))) + "好感"
		_:
			return stat

static func _preview_npc_label(npc_id: String) -> String:
	if npc_id == "":
		return "人物"
	var rel := StoryTables.get_relationship(npc_id)
	var label := str(rel.get("label", ""))
	return label if label != "" else npc_id

static func _preview_port_label(port_id: String) -> String:
	if port_id == "":
		return "港口"
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var gm = tree.root.get_node_or_null("/root/GameManager")
		if gm != null and gm.has_method("get_port_data"):
			var port_data = gm.get_port_data(port_id)
			if port_data is Dictionary:
				var name := str(port_data.get("name", ""))
				if name != "":
					return name
	return port_id

static func _preview_signed_number(value: float) -> String:
	var sign := "+" if value >= 0.0 else "-"
	return sign + _preview_format_number(absf(value))

static func _preview_format_number(value: float) -> String:
	var rounded: float = round(value)
	if is_equal_approx(value, rounded):
		return str(int(rounded))
	var text := "%.1f" % value
	while text.contains(".") and text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text

static func _once_flag(chain_id: String, chain: Dictionary) -> String:
	return str(chain.get("trigger_flag", "chain_%s_fired" % chain_id))

static func _should_trigger(chain_id: String, chain: Dictionary, trigger_on: String, ctx: Dictionary) -> bool:
	var raw_triggers = chain.get("trigger_on", [])
	var triggers: Array = [raw_triggers] if raw_triggers is String else raw_triggers
	if trigger_on not in triggers:
		return false
	if chain.get("once", false):
		var state = _get_state(ctx)
		if state == null or state.has_story_flag(_once_flag(chain_id, chain)):
			return false
	var conds: Dictionary = chain.get("conditions", {})
	return ConditionEvaluator.matches(conds, ctx)

static func _fire_chain(chain_id: String, chain: Dictionary, ctx: Dictionary) -> void:
	var state = _get_state(ctx)
	if state == null:
		return
	if chain.get("once", false):
		state.set_story_flag(_once_flag(chain_id, chain), true)
	for raw_effect in chain.get("effects", []):
		if raw_effect is Dictionary:
			_apply_effect(raw_effect, ctx)

static func _apply_effect(effect: Dictionary, ctx: Dictionary) -> void:
	var state = _get_state(ctx)
	if state == null:
		return
	var effect_type := str(effect.get("type", ""))
	match effect_type:
		"apply_effects":
			var effects: Dictionary = effect.get("effects", {})
			if not effects.is_empty():
				state.apply_effects(_apply_effect_bonuses(effects, ctx))
		"set_story_flag":
			var key := str(effect.get("key", ""))
			if key != "":
				state.set_story_flag(key, effect.get("value", true))
		"clear_story_flag":
			var key := str(effect.get("key", ""))
			if key != "":
				state.set_story_flag(key, false)
		"set_flag":
			var key := str(effect.get("key", ""))
			if key != "":
				state.set_flag(key)
		"clear_flag":
			var key := str(effect.get("key", ""))
			if key != "":
				state.clear_flag(key)
		"acquire_item":
			var item_id := str(effect.get("item_id", effect.get("key", "")))
			if item_id != "":
				state.acquire_item(item_id)
		"grant_card":
			var card_id := str(effect.get("card_id", effect.get("key", "")))
			if card_id != "":
				state.grant_card(card_id)
		"grant_title":
			var title_id := str(effect.get("title_id", effect.get("key", "")))
			if title_id != "":
				state.grant_title(title_id)
		"unlock_chapter":
			var chapter_id := str(effect.get("chapter_id", effect.get("key", "")))
			if chapter_id != "":
				state.apply_effects({"chapter_unlock": chapter_id})
		"money":
			var money_effects := {"money": int(effect.get("amount", effect.get("delta", 0)))}
			state.apply_effects(_apply_effect_bonuses(money_effects, ctx))
		"fame":
			var fame_effects := {"fame": int(effect.get("amount", effect.get("delta", 0)))}
			state.apply_effects(_apply_effect_bonuses(fame_effects, ctx))
		"npc_affinity":
			state.apply_effects({
				"npc_affinity": {
					"npc_id": str(effect.get("npc_id", "")),
					"delta": int(effect.get("delta", 0)),
				},
			})
		"npc_relationship":
			var npc_id := str(effect.get("npc_id", ""))
			if npc_id != "":
				var rel_ctx := _bonus_ctx_with(ctx, "npc_id", npc_id)
				var rel_details := StoryTables.get_effect_bonus_details(state, "npc_relationship", rel_ctx)
				var rel_delta := int(effect.get("delta", 0)) + int(_sum_bonus_delta(rel_details))
				_emit_bonus_feedback(rel_details, ctx)
				state.adjust_npc_relationship(npc_id, rel_delta)
		"port_affinity":
			var market = state.get("market")
			if market != null:
				var port_id := str(effect.get("port_id", ctx.get("port_id", "")))
				if port_id != "":
					var port_ctx := _bonus_ctx_with(ctx, "port_id", port_id)
					var port_details := StoryTables.get_effect_bonus_details(state, "port_affinity", port_ctx)
					var port_delta := float(effect.get("delta", 0.0)) + _sum_bonus_delta(port_details)
					_emit_bonus_feedback(port_details, ctx)
					market.adjust_affinity(port_id, port_delta)
		"play_cutscene":
			var cutscene_player = ctx.get("cutscene_player")
			if cutscene_player != null and cutscene_player.has_method("play"):
				cutscene_player.play(str(effect.get("cutscene_id", "")))
		"play_dialogue":
			var dialogue_box = ctx.get("dialogue_box")
			if dialogue_box != null and dialogue_box.has_method("start_sequence"):
				var body := str(effect.get("body", ""))
				dialogue_box.start_sequence(DialogueParser.parse_body(body))
		"log_message":
			_emit_log(str(effect.get("text", "")), ctx)
		_:
			push_warning("[StoryEventChainEngine] 未知 effect type: " + effect_type)

static func _apply_effect_bonuses(effects: Dictionary, ctx: Dictionary) -> Dictionary:
	var state = _get_state(ctx)
	var out := effects.duplicate(true)
	if state == null:
		return out
	for raw_key in out.keys():
		var key := str(raw_key)
		if key == "npc_relationship" and out[raw_key] is Dictionary:
			var payload: Dictionary = out[raw_key].duplicate(true)
			var npc_id := str(payload.get("npc_id", ""))
			var rel_ctx := _bonus_ctx_with(ctx, "npc_id", npc_id)
			var rel_details := StoryTables.get_effect_bonus_details(state, "npc_relationship", rel_ctx)
			payload["delta"] = int(payload.get("delta", 0)) + int(_sum_bonus_delta(rel_details))
			_emit_bonus_feedback(rel_details, ctx)
			out[raw_key] = payload
		else:
			out[raw_key] = _apply_numeric_bonus(out[raw_key], state, key, ctx)
	return out

static func _apply_numeric_bonus(value, state, target_stat: String, ctx: Dictionary):
	if value is int:
		var int_details := StoryTables.get_effect_bonus_details(state, target_stat, ctx)
		_emit_bonus_feedback(int_details, ctx)
		return int(value) + int(_sum_bonus_delta(int_details))
	if value is float:
		var float_details := StoryTables.get_effect_bonus_details(state, target_stat, ctx)
		_emit_bonus_feedback(float_details, ctx)
		return float(value) + _sum_bonus_delta(float_details)
	return value

static func _sum_bonus_delta(details: Array) -> float:
	var total := 0.0
	for raw_detail in details:
		if raw_detail is Dictionary:
			total += float(raw_detail.get("delta", 0.0))
	return total

static func _emit_auto_grant_feedback(grants: Array, ctx: Dictionary) -> void:
	var callback = ctx.get("message_callback")
	if not (callback is Callable and callback.is_valid()):
		var state = _get_state(ctx)
		if state != null and state is Object and state.has_signal("story_unlock_notified"):
			return
	for raw_grant in grants:
		if not raw_grant is Dictionary:
			continue
		var text := _format_auto_grant_feedback(raw_grant)
		if text != "":
			_emit_log(text, ctx)

static func _format_auto_grant_feedback(grant: Dictionary) -> String:
	var section := str(grant.get("section", ""))
	var entry_id := str(grant.get("id", ""))
	var raw_entry = grant.get("entry", {})
	var entry: Dictionary = raw_entry if raw_entry is Dictionary else {}
	var name := str(entry.get("name", entry.get("label", entry_id)))
	if name == "":
		name = entry_id
	var unlock_text := str(entry.get("unlock_text", ""))
	var suffix := "：" + unlock_text if unlock_text != "" else ""
	if section == "cards":
		return "自动获得：札「%s」%s" % [name, suffix]
	if section == "titles":
		return "自动获得：称号「%s」%s" % [name, suffix]
	return ""

static func _emit_bonus_feedback(details: Array, ctx: Dictionary) -> void:
	for raw_detail in details:
		if not raw_detail is Dictionary:
			continue
		var detail: Dictionary = raw_detail
		if is_zero_approx(float(detail.get("delta", 0.0))):
			continue
		var label := str(detail.get("label", ""))
		if label == "":
			label = str(detail.get("id", ""))
		if label != "":
			_emit_log("札效生效：" + label, ctx)

static func _bonus_ctx_with(ctx: Dictionary, key: String, value) -> Dictionary:
	var out := ctx.duplicate()
	if str(value) != "":
		out[key] = value
	return out

static func _emit_log(text: String, ctx: Dictionary) -> void:
	if text.is_empty():
		return
	var callback = ctx.get("message_callback")
	if callback is Callable and callback.is_valid():
		callback.call(text + "\n")
		return
	var state = _get_state(ctx)
	var game_log = state.get("game_log") if state != null else null
	if game_log != null:
		game_log.info(GameLog.Category.EVENT, text)

static func _get_state(ctx: Dictionary):
	if ctx.has("game_state"):
		return ctx["game_state"]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/GameState")
