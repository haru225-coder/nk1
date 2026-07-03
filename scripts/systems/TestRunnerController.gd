extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run() -> void:
	_test_condition_evaluator()
	_test_invest_port_handler()
	_test_npc_affinity_handlers()
	_test_duel_action_matrix()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

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
