extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	_test_condition_evaluator()
	_test_facility_resolver_rules()
	_test_investigation_clear_containers_signal_safe()
	_test_invest_port_handler()
	_test_effects_already_consumed()
	_test_npc_affinity_handlers()
	_test_duel_action_matrix()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

func _test_investigation_clear_containers_signal_safe() -> void:
	print("[InvestigationController cleanup]")

	var host := Node.new()
	_runner.root.add_child(host)

	var controller := InvestigationController.new()
	host.add_child(controller)

	var scene_title := Label.new()
	var body_text := RichTextLabel.new()
	var interactive_container := HFlowContainer.new()
	var interactive_label := Label.new()
	var choices_container := VBoxContainer.new()
	var choices_label := Label.new()
	var city_nav_panel := PanelContainer.new()
	var city_nav_label := Label.new()
	var city_nav_flow := HFlowContainer.new()
	var content_root := MarginContainer.new()

	for node in [
		scene_title,
		body_text,
		interactive_container,
		interactive_label,
		choices_container,
		choices_label,
		city_nav_panel,
		city_nav_label,
		city_nav_flow,
		content_root,
	]:
		host.add_child(node)

	controller.bind_ui(
		scene_title,
		body_text,
		interactive_container,
		interactive_label,
		choices_container,
		choices_label,
		city_nav_panel,
		city_nav_label,
		city_nav_flow,
		content_root,
	)

	var signal_button := Button.new()
	var choice_button := Button.new()
	interactive_container.add_child(signal_button)
	choices_container.add_child(choice_button)

	signal_button.pressed.connect(Callable(controller, "clear_containers"))
	signal_button.emit_signal("pressed")

	_assert_true(signal_button.is_queued_for_deletion(), "clear_containers: signal sender queued for deletion")
	_assert_true(choice_button.is_queued_for_deletion(), "clear_containers: choice child queued for deletion")

	host.queue_free()
	print("")

class KernelFakeState:
	var fame: int = 0
	var market = null
	var _story_flags: Dictionary = {}
	var _flags: Dictionary = {}
	var _npc_relationships: Dictionary = {}

	func has_story_flag(key: String) -> bool:
		return bool(_story_flags.get(key, false))

	func set_story_flag(key: String, value = true) -> void:
		_story_flags[key] = value

	func has_flag(key: String) -> bool:
		return bool(_flags.get(key, false))

	func get_npc_relationship(npc_id: String) -> int:
		return int(_npc_relationships.get(npc_id, 0))

	func adjust_npc_relationship(npc_id: String, delta: int) -> void:
		_npc_relationships[npc_id] = get_npc_relationship(npc_id) + delta

	func apply_effects(effects: Dictionary) -> void:
		if effects.has("fame"):
			fame += int(effects["fame"])
		if effects.has("npc_relationship"):
			var payload: Dictionary = effects["npc_relationship"]
			adjust_npc_relationship(str(payload.get("npc_id", "")), int(payload.get("delta", 0)))

# ── NK1-P6: ConditionEvaluator 测试 ───────────────────────

func _test_condition_evaluator() -> void:
	print("[ConditionEvaluator]")

	_assert_true(ConditionEvaluator.matches({}), "空条件 => true")
	_assert_true(ConditionEvaluator.matches({"story_flags_required": []}), "空 required 列表 => true")

	var story := StoryState.new()
	story.set_story_flag("test_cond_flag", true)
	story.adjust_npc_affinity("test_npc", 10)
	_assert_eq(story.get_npc_affinity("test_npc"), 10, "StoryState: npc 好感 +10")
	story.adjust_npc_affinity("test_npc", 5)
	_assert_eq(story.get_npc_affinity("test_npc"), 15, "StoryState: npc 好感累加")
	_assert_true(ConditionEvaluator.matches({"trade_count_min": 2}, {"trade_count": 2}), "ConditionEvaluator: trade_count_min 支持自动获得条件")
	_assert_true(not ConditionEvaluator.matches({"trade_count_min": 3}, {"trade_count": 2}), "ConditionEvaluator: trade_count_min 未达标时失败")
	var affinity_state := KernelFakeState.new()
	affinity_state.market = MarketState.new()
	affinity_state.market.adjust_affinity("quanzhou", 5.0)
	_assert_true(ConditionEvaluator.matches({"port_affinity_min": 5.0}, {"port_id": "quanzhou", "game_state": affinity_state}), "ConditionEvaluator: port_affinity_min 支持自动获得条件")
	_assert_true(not ConditionEvaluator.matches({"port_affinity_min": 6.0}, {"port_id": "quanzhou", "game_state": affinity_state}), "ConditionEvaluator: port_affinity_min 未达标时失败")

	print("")

# ── FacilityResolver tests ────────────────────────────────

func _test_facility_resolver_rules() -> void:
	print("[FacilityResolver]")

	var resolver = _load_script_or_fail(ResourcePaths.SCRIPT_FACILITY_RESOLVER, "FacilityResolver script loads")
	if resolver == null:
		print("")
		return

	var unlock_flag := "facility_resolver_test_unlock"
	var block_flag := "facility_resolver_test_block"
	GameState.set_story_flag(unlock_flag, false)
	GameState.set_story_flag(block_flag, false)

	var gated_fac := {"requires_story_flag": unlock_flag}
	_assert_true(not resolver.facility_available(gated_fac), "facility_available: requires flag blocks when absent")
	GameState.set_story_flag(unlock_flag, true)
	_assert_true(resolver.facility_available(gated_fac), "facility_available: requires flag opens when present")

	var blocked_choice := {"unless_story_flag": block_flag}
	_assert_true(resolver.choice_available(blocked_choice), "choice_available: unless flag absent")
	GameState.set_story_flag(block_flag, true)
	_assert_true(not resolver.choice_available(blocked_choice), "choice_available: unless flag blocks")

	_assert_eq(resolver.resolve_facility_scene({"id": "city_market"}, "quanzhou"), "quanzhou_market", "resolve_facility_scene: city_ prefix")
	_assert_eq(resolver.resolve_facility_scene({"id": "custom_scene"}, "quanzhou"), "custom_scene", "resolve_facility_scene: explicit id passthrough")
	_assert_eq(resolver.resolve_hotspot_scene({"scene_id": "hotspot_scene"}, {"id": "city_market"}, "quanzhou"), "hotspot_scene", "resolve_hotspot_scene: explicit scene_id")
	_assert_eq(resolver.resolve_hotspot_scene({}, {"id": "city_market"}, "quanzhou"), "quanzhou_market", "resolve_hotspot_scene: fallback facility scene")
	_assert_eq(resolver.resolve_choice_style({"next": "world_map"}), "sail", "resolve_choice_style: world_map sail")
	_assert_eq(resolver.resolve_choice_style({"choice_style": "quest", "next": "world_map"}), "quest", "resolve_choice_style: configured style wins")

	var display: Dictionary = resolver.resolve_facility_subtitle({
		"subtitle": {
			"default": "默认",
			"state": "default",
			"rules": [{"requires_story_flag": unlock_flag, "text": "开启", "state": "quest"}],
		},
	})
	_assert_eq(display.get("text", ""), "开启", "resolve_facility_subtitle: rule text")
	_assert_eq(display.get("state", ""), "quest", "resolve_facility_subtitle: rule state")
	_assert_eq(GameManager.resolve_facility_scene({"id": "city_inn"}, "keelung"), "keelung_inn", "GameManager delegates facility resolver")
	_assert_true(GameManager.resolve_facility_icon({"id": "city_market"}) != null, "GameManager delegates facility icon resolver")

	GameState.set_story_flag(unlock_flag, false)
	GameState.set_story_flag(block_flag, false)
	print("")

# ── NK1-P6: 港口投资 Handler 测试 ─────────────────────────

func _test_invest_port_handler() -> void:
	print("[InvestPortHandler]")

	var invest_port_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_INVEST_PORT, "InvestPortHandler 脚本可加载")
	if invest_port_handler == null:
		print("")
		return

	_assert_eq(invest_port_handler.INVEST_TIERS["small"]["amount"], 100, "小额投资 100")
	_assert_eq(invest_port_handler.INVEST_TIERS["medium"]["amount"], 500, "中额投资 500")
	_assert_eq(invest_port_handler.INVEST_TIERS["large"]["amount"], 2000, "大额投资 2000")
	_assert_true(invest_port_handler.SPECIALTY_UNLOCK_RULES.has("quanzhou"), "泉州解锁规则已定义")

	var msg := EconomyLog.make_port_invest("泉州", "大额", 2000)
	_assert_true(msg.contains("泉州"), "EconomyLog: 投资消息含港口名")
	var unlock_msg := EconomyLog.make_specialty_unlock("泉州", "福建瓷")
	_assert_true(unlock_msg.contains("福建瓷"), "EconomyLog: 解锁消息含特产名")

	_assert_eq(TextKeys.INTENT_INVEST_SUCCESS, "intent.invest_port.success", "TextKeys.INTENT_INVEST_SUCCESS")
	_assert_eq(TextKeys.ERROR_INVEST_COOLDOWN, "error.invest.cooldown", "TextKeys.ERROR_INVEST_COOLDOWN")

	var port_file := FileAccess.open("res://scripts/PortScreenController.gd", FileAccess.READ)
	var port_src := port_file.get_as_text() if port_file != null else ""
	_assert_true(not port_src.is_empty(), "PortScreenController.gd 可读")
	var setup_src := _extract_func_source(port_src, "setup")
	_assert_true(not setup_src.is_empty(), "PortScreenController.setup 可定位")
	_assert_true(not setup_src.contains("_clear_port_invest_cooldown"), "setup 不再调用 _clear_port_invest_cooldown")
	_assert_true(not setup_src.contains("port_invested_this_visit"), "setup 不触碰 port_invested_this_visit")

	var gs_file := FileAccess.open("res://scripts/GameState.gd", FileAccess.READ)
	var gs_src := gs_file.get_as_text() if gs_file != null else ""
	_assert_true(not gs_src.is_empty(), "GameState.gd 可读")
	var sail_src := _extract_func_source(gs_src, "_do_sail_world_map")
	_assert_true(not sail_src.is_empty(), "GameState._do_sail_world_map 可定位")
	_assert_true(
		sail_src.contains("clear_visit_cooldown") or sail_src.contains("port_invested_this_visit"),
		"出港路径清除港口投资冷却"
	)

	var handler_file := FileAccess.open(ResourcePaths.SCRIPT_HANDLER_INVEST_PORT, FileAccess.READ)
	var handler_src := handler_file.get_as_text() if handler_file != null else ""
	_assert_true(handler_src.contains("static func clear_visit_cooldown"), "InvestPortHandler.clear_visit_cooldown 已定义")

	_test_invest_port_handler_live(invest_port_handler)

	print("")

# ── NK1-P6: NPC 好感 / 送礼 / 求教测试 ───────────────────

func _test_npc_affinity_handlers() -> void:
	print("[NPC Affinity Handlers]")

	var gift_npc_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_GIFT_NPC, "GiftNPCHandler 脚本可加载")
	var study_skill_handler = _load_script_or_fail(ResourcePaths.SCRIPT_HANDLER_STUDY_SKILL, "StudySkillHandler 脚本可加载")
	if gift_npc_handler == null or study_skill_handler == null:
		print("")
		return

	_assert_eq(gift_npc_handler.DEFAULT_PREFERRED_DELTA, 10, "GiftNPCHandler: 偏好礼物默认 +10")
	_assert_true(study_skill_handler.SKILL_EFFECTS.has("skill_boarding_tactics"), "StudySkillHandler: 接舷战术已定义")

	var lin := _load_npc_fixture("lin_boyuan")
	_assert_true(not lin.is_empty(), "lin_boyuan NPC 数据可读")
	_assert_eq(int(lin.get("affinity_threshold", 0)), 30, "lin_boyuan: 好感阈值 30")
	var prefs: Array = lin.get("gift_preferences", [])
	_assert_true("spring_autumn_scroll" in prefs, "lin_boyuan: 偏好《春秋》")

	_assert_eq(TextKeys.INTENT_GIFT_SUCCESS, "intent.gift_npc.success", "TextKeys.INTENT_GIFT_SUCCESS")
	_assert_eq(TextKeys.ERROR_STUDY_AFFINITY_LOW, "error.study.affinity_low", "TextKeys.ERROR_STUDY_AFFINITY_LOW")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_GIFT_NPC, "res://scripts/systems/handlers/GiftNPCHandler.gd", "ResourcePaths.GIFT_NPC")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_STUDY_SKILL, "res://scripts/systems/handlers/StudySkillHandler.gd", "ResourcePaths.STUDY_SKILL")

	var story := StoryState.new()
	story.acquire_item("spring_autumn_scroll")
	_assert_true(story.has_item_flag("spring_autumn_scroll"), "story item 可持有")

	print("")

# ── NK1-P6: 决斗克制矩阵测试 ─────────────────────────────

func _test_duel_action_matrix() -> void:
	print("[Duel Action Matrix]")

	var combat_state = _load_script_or_fail("res://scripts/state/CombatState.gd", "CombatState 脚本可加载")
	if combat_state == null:
		print("")
		return

	_assert_eq(combat_state.DUEL_KI_MAX, 3, "CombatState: 气力上限 3")
	_assert_eq(combat_state.DUEL_KI_SPECIAL_COST, 3, "CombatState: 必杀消耗 3")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.SLASH, combat_state.DuelAction.DODGE), 1, "猛攻克闪避")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.DODGE, combat_state.DuelAction.PARRY), 1, "闪避克招架")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.PARRY, combat_state.DuelAction.SLASH), 1, "招架克猛攻")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.SLASH, combat_state.DuelAction.PARRY), -1, "猛攻被招架")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.DODGE, combat_state.DuelAction.SLASH), -1, "闪避败于猛攻")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.SLASH, combat_state.DuelAction.SLASH), 0, "同招平局")
	_assert_eq(combat_state.resolve_duel_clash(combat_state.DuelAction.SPECIAL, combat_state.DuelAction.SLASH), 1, "必杀克猛攻")
	_assert_eq(combat_state.get_duel_action_name(combat_state.DuelAction.PARRY), "招架", "决斗出招名称")

	var combat = _make_duel_test_combat(combat_state)
	combat.phase = combat_state.Phase.BOARDING
	var enter = combat.execute_round(combat_state.Tactic.DUEL, combat_state.Tactic.BOARD)
	_assert_eq(combat.phase, combat_state.Phase.DUEL, "发起单挑进入 DUEL 阶段")
	_assert_true(not enter.get("is_over", true), "进入决斗不立即结束")

	combat.ki_points = 0
	var clash = combat.execute_duel_action(combat_state.DuelAction.SLASH, combat_state.DuelAction.DODGE)
	_assert_eq(int(clash.get("clash_winner", 0)), 1, "交互决斗：玩家克制获胜")
	_assert_eq(combat.ki_points, 1, "克制获胜积攒气力 +1")

	combat.ki_points = 3
	var special = combat.execute_duel_action(combat_state.DuelAction.SPECIAL, combat_state.DuelAction.PARRY)
	_assert_eq(int(special.get("clash_winner", 0)), 1, "必杀克制招架")
	_assert_eq(combat.ki_points, 1, "必杀后剩余气力（获胜+1）")

	print("")

func _extract_func_source(src: String, func_name: String) -> String:
	var marker := "func " + func_name
	var start := src.find(marker)
	if start < 0:
		return ""
	var search_from := start + marker.length()
	var next_func := src.find("\nfunc ", search_from)
	if next_func < 0:
		return src.substr(start)
	return src.substr(start, next_func - start)

func _test_invest_port_handler_live(invest_port_handler) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ledger = tree.root.get_node_or_null("/root/LedgerSystem") if tree != null else null
	var gs = tree.root.get_node_or_null("/root/GameState") if tree != null else null
	if ledger == null or gs == null or invest_port_handler == null:
		print("  SKIP: InvestPortHandler live cooldown (autoloads unavailable)")
		return

	var test_port := "test_invest_visit_cd"
	var cd_key := str(invest_port_handler.INVEST_COOLDOWN_FLAG_PREFIX) + test_port
	var had_flag := GameState.story_flags.has(cd_key)
	var saved_flag = GameState.story_flags.get(cd_key, null)
	var saved_market = GameState.market
	var saved_balance := int(LedgerSystem.get_balance())

	GameState.market = MarketState.new()
	LedgerSystem.from_save_dict({"balance": 1000})
	invest_port_handler.clear_visit_cooldown(test_port)

	var handler = invest_port_handler.new()
	var first = handler.handle(Intent.new(IntentTypes.INVEST_PORT, "player", test_port, {"tier": "small"}))
	_assert_true(first.success, "同访: 首次投资成功")
	var second = handler.handle(Intent.new(IntentTypes.INVEST_PORT, "player", test_port, {"tier": "small"}))
	_assert_true(not second.success, "同访: 二次投资被冷却拒绝")
	_assert_eq(second.message, TextKeys.ERROR_INVEST_COOLDOWN, "同访: 冷却错误文案")
	invest_port_handler.clear_visit_cooldown(test_port)
	_assert_true(not GameState.has_story_flag(cd_key), "clear_visit_cooldown 后冷却已清除")
	var third = handler.handle(Intent.new(IntentTypes.INVEST_PORT, "player", test_port, {"tier": "small"}))
	_assert_true(third.success, "离港清冷却后: 第三次投资成功")

	GameState.market = saved_market
	LedgerSystem.from_save_dict({"balance": saved_balance})
	if had_flag:
		GameState.set_story_flag(cd_key, saved_flag)
	else:
		GameState.story_flags.erase(cd_key)

func _test_effects_already_consumed() -> void:
	print("[GameState.effects_already_consumed]")
	if GameState == null:
		_assert_true(false, "GameState autoload 可取得")
		return
	_assert_true(GameState.has_method("effects_already_consumed"), "GameState 暴露 effects_already_consumed")
	var flag := "test_effect_consumed_flag"
	var item_id := "test_effect_consumed_item"
	var had_flag := GameState.has_story_flag(flag)
	var had_item := GameState.has_item_flag(item_id)
	GameState.story_flags.erase(flag)
	GameState.story.story_items.erase(item_id)
	_assert_true(not GameState.effects_already_consumed({"money": 120, "story_flag": flag}), "旗标未立: 未消费")
	GameState.set_story_flag(flag, true)
	_assert_true(GameState.effects_already_consumed({"money": 120, "story_flag": flag}), "旗标已立: 视为已消费")
	_assert_true(GameState.effects_already_consumed({"story_flag2": {flag: true}}), "story_flag2 字典旗标已立")
	GameState.story_flags.erase(flag)
	GameState.acquire_item(item_id)
	_assert_true(GameState.effects_already_consumed({"money": 5, "item_acquired": item_id}), "已获物品: 视为已消费")
	if had_flag:
		GameState.set_story_flag(flag, true)
	else:
		GameState.story_flags.erase(flag)
	if had_item:
		GameState.acquire_item(item_id)
	else:
		GameState.story.story_items.erase(item_id)
	print("")

func _load_npc_fixture(npc_id: String) -> Dictionary:
	var file := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for n in parsed.get("npcs", []):
			if str(n.get("id", "")) == npc_id:
				return n
	return {}

func _make_duel_test_combat(combat_state = null):
	if combat_state == null:
		combat_state = _load_script_or_fail("res://scripts/state/CombatState.gd", "CombatState 脚本可加载")
	var combat = combat_state.new()
	combat.player_fleet = FleetState.new()
	combat.enemy_fleet = FleetState.new()
	combat.player_fleet.ships[0].crew = 40
	combat.player_fleet.ships[0].max_crew = 40
	combat.enemy_fleet.ships[0].name = "敌旗舰"
	combat.enemy_fleet.ships[0].crew = 40
	combat.enemy_fleet.ships[0].max_crew = 40
	return combat
