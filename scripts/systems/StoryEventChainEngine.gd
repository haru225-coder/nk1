class_name StoryEventChainEngine extends RefCounted

## 太阁式前置条件事件链：加载配置 → 检测条件 → 应用 effects
## 消费者模式：不修改 WorldEventTracker [C3-STABLE]

const DATA_PATH := ResourcePaths.DATA_STORY_EVENT_CHAINS

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
		_fire_chain(chain_id, chain, ctx)
		fired.append(chain_id)
	return fired

static func _once_flag(chain_id: String, chain: Dictionary) -> String:
	return str(chain.get("trigger_flag", "chain_%s_fired" % chain_id))

static func _should_trigger(chain_id: String, chain: Dictionary, trigger_on: String, ctx: Dictionary) -> bool:
	var triggers: Array = chain.get("trigger_on", [])
	if trigger_on not in triggers:
		return false
	if chain.get("once", false) and GameState.has_story_flag(_once_flag(chain_id, chain)):
		return false
	var conds: Dictionary = chain.get("conditions", {})
	return ConditionEvaluator.matches(conds, ctx)

static func _fire_chain(chain_id: String, chain: Dictionary, ctx: Dictionary) -> void:
	if chain.get("once", false):
		GameState.set_story_flag(_once_flag(chain_id, chain), true)
	for raw_effect in chain.get("effects", []):
		if raw_effect is Dictionary:
			_apply_effect(raw_effect, ctx)

static func _apply_effect(effect: Dictionary, ctx: Dictionary) -> void:
	var effect_type := str(effect.get("type", ""))
	match effect_type:
		"set_story_flag":
			var key := str(effect.get("key", ""))
			if key != "":
				GameState.set_story_flag(key, effect.get("value", true))
		"npc_affinity":
			GameState.apply_effects({
				"npc_affinity": {
					"npc_id": str(effect.get("npc_id", "")),
					"delta": int(effect.get("delta", 0)),
				},
			})
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

static func _emit_log(text: String, ctx: Dictionary) -> void:
	if text.is_empty():
		return
	var callback = ctx.get("message_callback")
	if callback is Callable and callback.is_valid():
		callback.call(text + "\n")
		return
	if GameState.game_log != null:
		GameState.game_log.info(GameLog.Category.EVENT, text)