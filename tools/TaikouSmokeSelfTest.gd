extends Node
## 人工冒烟走查的自动化替身：泉州进港 → 投资 → 送礼/求教 → 事件链 → 决斗

func _ready() -> void:
	var ok := run()
	print("[TaikouSmokeSelfTest] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func run() -> bool:
	var ok := true
	ok = ok and _smoke_invest_unlock()
	ok = ok and _smoke_gift_and_study()
	ok = ok and _smoke_story_chains()
	ok = ok and _smoke_duel_flow()
	return ok

func _smoke_invest_unlock() -> bool:
	IdempotencyGuard.processed_intents.clear()
	LedgerSystem.from_save_dict({"balance": 5000})
	GameState.market = MarketState.new()
	GameState.market.init_from_ports(
		[{"id": "quanzhou", "production": {"fujian_porcelain": 1.0}, "demand": {}}],
		[{"id": "fujian_porcelain", "category": "货物", "base_value": 100}]
	)
	GameState.set_story_flag(InvestPortHandler.INVEST_COOLDOWN_FLAG_PREFIX + "quanzhou", false)

	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.INVEST_PORT, "player", "quanzhou", {"tier": "large"}
	))
	if not result.success:
		push_error("投资失败")
		return false
	if str(result.data.get("unlocked_specialty", "")) != "fujian_porcelain":
		push_error("未解锁福建瓷")
		return false
	if not GameState.market.is_specialty_unlocked("quanzhou", "fujian_porcelain"):
		push_error("market 未记录特产解锁")
		return false
	return true

func _smoke_gift_and_study() -> bool:
	IdempotencyGuard.processed_intents.clear()
	GameState.story_items = {}
	GameState.story_flags.erase("npc_affinity_lin_boyuan")
	GameState.acquire_item("spring_autumn_scroll")

	var gift := IntentResolver.resolve(Intent.new(IntentTypes.GIFT_NPC, "player", "lin_boyuan", {}))
	if not gift.success or int(gift.data.get("affinity_delta", 0)) != 15:
		push_error("送礼失败或好感不对")
		return false
	if GameState.story.get_npc_affinity("lin_boyuan") != 15:
		push_error("好感未写入")
		return false

	IdempotencyGuard.processed_intents.clear()
	GameState.story.adjust_npc_affinity("lin_boyuan", 85)
	var study := IntentResolver.resolve(Intent.new(
		IntentTypes.STUDY_SKILL, "player", "lin_boyuan",
		{"skill_id": "skill_boarding_tactics", "difficulty": 0}
	))
	if not study.success or not GameState.has_story_flag("learned_skill_boarding_tactics"):
		push_error("求教失败")
		return false
	return true

func _smoke_story_chains() -> bool:
	StoryEventChainEngine.reload()
	var saved: Dictionary = GameState.story_flags.duplicate(true)

	GameState.set_story_flag("chapter1_complete", true)
	GameState.set_story_flag("met_lin_boyuan", true)
	GameState.story_flags.erase("met_lin_boyuan_formal")
	GameState.story_flags.erase("chain_ev_lin_boyuan_formal_fired")

	var port_fired: Array = StoryEventChainEngine.check_triggers("enter_port", {"port_id": "quanzhou"})
	if port_fired.size() != 1 or not GameState.has_story_flag("met_lin_boyuan_formal"):
		push_error("林伯渊正式会面链未触发")
		GameState.story_flags = saved
		return false

	GameState.story_flags.erase("heard_pu_rumor")
	GameState.story_flags.erase("chain_ev_pu_rumor_fired")
	GameState.set_story_flag("chapter1_complete", true)
	var day_fired: Array = StoryEventChainEngine.check_triggers("day_advance", {})
	if day_fired.size() != 1 or not GameState.has_story_flag("heard_pu_rumor"):
		push_error("蒲氏传闻链未触发")
		GameState.story_flags = saved
		return false

	GameState.story_flags = saved
	return true

func _smoke_duel_flow() -> bool:
	var combat := CombatState.new()
	combat.player_fleet = FleetState.new()
	combat.enemy_fleet = FleetState.new()
	combat.player_fleet.ships[0].crew = 40
	combat.enemy_fleet.ships[0].crew = 40
	combat.phase = CombatState.Phase.BOARDING

	var enter := combat.execute_round(CombatState.Tactic.DUEL, CombatState.Tactic.BOARD)
	if combat.phase != CombatState.Phase.DUEL:
		push_error("未进入 DUEL 阶段")
		return false

	combat.ki_points = 3
	var special := combat.execute_duel_action(CombatState.DuelAction.SPECIAL, CombatState.DuelAction.PARRY)
	if int(special.get("clash_winner", 0)) != 1:
		push_error("必杀未克制招架")
		return false

	combat.ki_points = 0
	var clash := combat.execute_duel_action(CombatState.DuelAction.SLASH, CombatState.DuelAction.DODGE)
	if int(clash.get("clash_winner", 0)) != 1:
		push_error("猛攻未克制闪避")
		return false
	if combat.ki_points < 1:
		push_error("克制后未积攒气力")
		return false

	if enter.get("is_over", true):
		push_error("进入决斗不应立即结束")
		return false
	return true