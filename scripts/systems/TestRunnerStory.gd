extends RefCounted

var _runner = null
var root = null
var _captured_storybook_route_scene_id: String = ""
var _captured_storybook_route_focus_action_id: String = ""

func _init(runner = null) -> void:
	_runner = runner
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		root = (loop as SceneTree).root

func run() -> void:
	_test_story_event_chains()
	_test_story_tables()
	_test_storybook_presenter()
	_test_story_unlock_gates()
	_test_chapter1_navigation_line_hook()
	_test_story_branch_unlock_choices()
	_test_story_relationship_depth()
	_test_trade_effect_preview()
	_test_auto_grant_feedback()
	_test_story_unlock_feedback()
	_test_story_unlock_visible_feedback()
	_test_story_unlock_toast_feedback()
	_test_story_unlock_toast_categories()
	_test_story_unlock_toast_storybook_jump()
	_test_story_unlock_toast_storybook_focus()
	_test_storybook_detail_panel()
	_test_storybook_route_action_focus()
	_test_storybook_route_action_focus_guidance()
	_test_storybook_completed_route_action_state()
	_test_storybook_task_chain_view()
	_test_event_kernel_mvp()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _load_script_or_fail(path: String, msg: String):
	return _runner._load_script_or_fail(path, msg)

func _story_event_chain_engine():
	return _load_script_or_fail("res://scripts/systems/StoryEventChainEngine.gd", "StoryEventChainEngine 脚本可加载")

# ── NK1-P6: 配置化事件链测试 ───────────────────────────────

func _test_story_event_chains() -> void:
	print("[Story Event Chains]")

	var chain_engine = _story_event_chain_engine()
	_assert_true(chain_engine != null, "StoryEventChainEngine 脚本可加载")
	if chain_engine == null:
		print("")
		return

	chain_engine.reload()
	var ids: Array = chain_engine.get_chain_ids()
	_assert_true(ids.size() >= 2, "story_event_chains: 至少 2 条链")

	var lin_chain: Dictionary = chain_engine.get_chain("ev_lin_boyuan_formal_quanzhou")
	_assert_true(not lin_chain.is_empty(), "林伯渊正式会面链存在")
	var triggers: Array = lin_chain.get("trigger_on", [])
	_assert_true("enter_port" in triggers, "林伯渊链: enter_port 触发")
	var conds: Dictionary = lin_chain.get("conditions", {})
	_assert_eq(str(conds.get("port_id", "")), "quanzhou", "林伯渊链: 泉州条件")

	var rumor_chain: Dictionary = chain_engine.get_chain("ev_post_chapter1_pu_rumor")
	_assert_true("day_advance" in rumor_chain.get("trigger_on", []), "蒲氏传闻链: day_advance 触发")

	var tavern_chain: Dictionary = chain_engine.get_chain("ev_quanzhou_tavern_trade_card")
	_assert_true("enter_facility" in tavern_chain.get("trigger_on", []), "泉州酒馆链: enter_facility 触发")
	_assert_eq(str(tavern_chain.get("conditions", {}).get("facility_id", "")), "city_tavern", "泉州酒馆链: 设施条件")

	var title_chain: Dictionary = chain_engine.get_chain("ev_rookie_merchant_title")
	_assert_true("trade_completed" in title_chain.get("trigger_on", []), "称号链: trade_completed 触发")

	_assert_eq(
		ResourcePaths.DATA_STORY_EVENT_CHAINS,
		"res://data/story_event_chains.json",
		"ResourcePaths.DATA_STORY_EVENT_CHAINS"
	)

	print("")

# ── 太阁式札/称号/关系表测试 ───────────────────────────────

func _test_story_tables() -> void:
	print("[Story Tables]")

	var file := FileAccess.open("res://data/story_tables.json", FileAccess.READ)
	_assert_true(file != null, "story_tables.json 文件存在")

	var parsed = JSON.parse_string(file.get_as_text()) if file != null else {}
	_assert_true(parsed is Dictionary, "story_tables.json 可解析")
	if not parsed is Dictionary:
		print("")
		return

	var cards: Dictionary = parsed.get("cards", {})
	var titles: Dictionary = parsed.get("titles", {})
	var relationships: Dictionary = parsed.get("relationships", {})
	var facility_triggers: Dictionary = parsed.get("facility_triggers", {})

	_assert_true(cards.has("card_zaitong_trade_intro"), "札表: 刺桐商路札已定义")
	_assert_true(titles.has("title_rookie_merchant"), "称号表: 初露锋芒海商已定义")
	_assert_true(relationships.has("lin_boyuan"), "人物关系表: 林伯渊已定义")
	_assert_true(facility_triggers.has("quanzhou_tavern_trade_intro"), "设施触发表: 泉州酒馆触发已定义")

	_assert_eq(ResourcePaths.DATA_STORY_TABLES, "res://data/story_tables.json", "ResourcePaths.DATA_STORY_TABLES")

	var registry = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY, "StoryTableRegistry 脚本可加载")
	registry.reload()
	var schema_errors: Array = registry.validate_schema(parsed)
	_assert_eq(schema_errors.size(), 0, "StoryTableRegistry schema: 当前 story_tables.json 无校验错误")
	var invalid_table := {
		"cards": {
			"bad_card": {
				"effects": [
					{"id": "", "type": "unlock_action", "target_scene_id": "city_tavern", "target_action_id": "zaitong_trade_route_asked"},
					{"id": "dup:bad", "type": "unknown_bonus"},
					{"id": "dup:bad", "type": "money_bonus", "trigger_on": "trade_completed", "target_stat": "fame", "delta": 50},
					{"id": "bonus:no_delta", "type": "fame_bonus", "trigger_on": "trade_completed", "target_stat": "fame"},
					{"id": "bonus:no_npc", "type": "npc_relationship_bonus", "trigger_on": "trade_completed", "target_stat": "npc_relationship", "delta": 1},
					{"id": "bonus:no_port", "type": "port_affinity_bonus", "trigger_on": "trade_completed", "target_stat": "port_affinity", "delta": 0.5},
					{"id": "unlock:missing_scene", "type": "unlock_action", "target_scene_id": "missing_scene", "target_action_id": "zaitong_trade_route_asked"},
					{"id": "unlock:missing_action", "type": "unlock_action", "target_scene_id": "city_tavern", "target_action_id": "missing_action"}
				],
				"task_chain": [
					{"id": "task:no_story_flag", "completed_by": "story_flag", "scene_id": "city_tavern", "focus_action_id": "zaitong_trade_route_asked"},
					{"id": "task:bad_focus", "completed_by": "story_flag", "story_flag": "bad_focus_done", "scene_id": "city_tavern", "focus_action_id": "missing_action"}
				]
			}
		}
	}
	var invalid_errors: Array = registry.validate_schema(invalid_table)
	var invalid_error_text := str(invalid_errors)
	_assert_true(invalid_error_text.contains("effects[0].id"), "StoryTableRegistry schema: effect id 必须非空")
	_assert_true(invalid_error_text.contains("unknown_bonus"), "StoryTableRegistry schema: effect type 必须在白名单内")
	_assert_true(invalid_error_text.contains("duplicate effect id"), "StoryTableRegistry schema: effect id 必须唯一")
	_assert_true(invalid_error_text.contains("expected target_stat money"), "StoryTableRegistry schema: 数值效果 target_stat 必须匹配类型")
	_assert_true(invalid_error_text.contains("delta or amount"), "StoryTableRegistry schema: 数值效果必须声明 delta/amount")
	_assert_true(invalid_error_text.contains("target_npc_id"), "StoryTableRegistry schema: npc_relationship_bonus 必须声明 target_npc_id")
	_assert_true(invalid_error_text.contains("target_port_id"), "StoryTableRegistry schema: port_affinity_bonus 必须声明 target_port_id")
	_assert_true(invalid_error_text.contains("missing scene"), "StoryTableRegistry schema: target_scene_id 必须指向已配置场景")
	_assert_true(invalid_error_text.contains("missing action"), "StoryTableRegistry schema: target_action_id/focus_action_id 必须指向场景行动")
	_assert_true(invalid_error_text.contains("story_flag"), "StoryTableRegistry schema: task_chain story_flag 步骤必须声明 story_flag")
	var card: Dictionary = registry.get_card("card_zaitong_trade_intro")
	var card_auto_grant: Dictionary = card.get("auto_grant", {})
	_assert_eq(str(card_auto_grant.get("trigger_on", "")), "enter_facility", "StoryTableRegistry: 刺桐商路札配置进入设施自动获得条件")
	var configured_title_for_auto: Dictionary = registry.get_title("title_rookie_merchant")
	var title_auto_grant: Dictionary = configured_title_for_auto.get("auto_grant", {})
	_assert_eq(str(title_auto_grant.get("trigger_on", "")), "trade_completed", "StoryTableRegistry: 初露锋芒称号配置交易完成自动获得条件")
	var auto_story := StoryState.new()
	var auto_card_ctx := {
		"trigger_on": "enter_facility",
		"port_id": "quanzhou",
		"facility_id": "city_tavern",
		"scene_id": "city_tavern",
		"game_state": auto_story,
	}
	auto_story.set_story_flag("chapter1_complete", true)
	var auto_card_grants: Array = registry.get_auto_grants(auto_story, auto_card_ctx)
	_assert_true(_has_story_table_grant(auto_card_grants, "cards", "card_zaitong_trade_intro"), "StoryTableRegistry: 进入泉州酒馆满足条件时列出刺桐商路札自动获得")
	registry.apply_auto_grants(auto_story, auto_card_ctx)
	_assert_true(auto_story.has_card("card_zaitong_trade_intro"), "StoryTableRegistry: apply_auto_grants 自动授予刺桐商路札")
	var auto_title_ctx := {
		"trigger_on": "trade_completed",
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": auto_story,
	}
	var auto_title_grants: Array = registry.get_auto_grants(auto_story, auto_title_ctx)
	_assert_true(_has_story_table_grant(auto_title_grants, "titles", "title_rookie_merchant"), "StoryTableRegistry: 完成首笔商路交易满足条件时列出初露锋芒称号自动获得")
	registry.apply_auto_grants(auto_story, auto_title_ctx)
	_assert_true(auto_story.has_title("title_rookie_merchant"), "StoryTableRegistry: apply_auto_grants 自动授予初露锋芒称号")
	_assert_eq(str(card.get("name", "")), "刺桐商路札", "StoryTableRegistry: 可读取札定义")
	var card_effects: Array = card.get("effects", [])
	_assert_eq(card_effects.size(), 2, "StoryTableRegistry: 刺桐商路札定义行动解锁+数值修正两个主动效果")
	if card_effects.size() >= 2:
		_assert_eq(str(card_effects[0].get("id", "")), "unlock:zaitong_trade_route_asked", "StoryTableRegistry: 札效果 id 指向酒馆行动解锁")
		_assert_eq(str(card_effects[0].get("type", "")), "unlock_action", "StoryTableRegistry: 札效果类型为行动解锁")
		_assert_eq(str(card_effects[1].get("id", "")), "bonus:zaitong_trade_fame", "StoryTableRegistry: 札数值效果 id 指向商路名声加成")
		_assert_eq(str(card_effects[1].get("type", "")), "fame_bonus", "StoryTableRegistry: 札数值效果类型为名声加成")
	var effect_story := StoryState.new()
	_assert_true(not registry.has_active_effect(effect_story, "unlock:zaitong_trade_route_asked"), "StoryTableRegistry: 未获札时行动解锁效果未激活")
	_assert_eq(registry.get_effect_bonus(effect_story, "fame", {"trigger_on": "trade_completed"}), 0, "StoryTableRegistry: 未获札时无交易名声加成")
	effect_story.grant_card("card_zaitong_trade_intro")
	_assert_true(registry.has_active_effect(effect_story, "unlock:zaitong_trade_route_asked"), "StoryTableRegistry: 获札后行动解锁效果激活")
	_assert_eq(registry.get_effect_bonus(effect_story, "fame", {"trigger_on": "trade_completed"}), 1, "StoryTableRegistry: 获札后交易名声加成生效")
	_assert_eq(registry.get_effect_bonus(effect_story, "fame", {"trigger_on": "enter_facility"}), 0, "StoryTableRegistry: 名声加成只匹配交易完成触发")
	var numeric_story := StoryState.new()
	numeric_story.grant_title("title_rookie_merchant")
	_assert_eq(registry.get_effect_bonus(numeric_story, "money", {"trigger_on": "trade_completed"}), 50, "StoryTableRegistry: money_bonus 可按 target_stat 查询")
	_assert_eq(registry.get_effect_bonus(numeric_story, "money", {"trigger_on": "enter_facility"}), 0, "StoryTableRegistry: money_bonus 受 trigger_on 限制")
	_assert_eq(registry.get_effect_delta(numeric_story, "port_affinity", {"trigger_on": "trade_completed", "port_id": "quanzhou"}), 0.5, "StoryTableRegistry: port_affinity_bonus 保留浮点加成")
	_assert_eq(registry.get_effect_delta(numeric_story, "port_affinity", {"trigger_on": "trade_completed", "port_id": "linan"}), 0.0, "StoryTableRegistry: port_affinity_bonus 匹配目标港口")
	numeric_story.adjust_npc_relationship("lin_boyuan", 10)
	_assert_eq(registry.get_effect_bonus(numeric_story, "npc_relationship", {"trigger_on": "trade_completed", "npc_id": "lin_boyuan"}), 1, "StoryTableRegistry: npc_relationship_bonus 匹配目标人物")
	_assert_eq(registry.get_effect_bonus(numeric_story, "npc_relationship", {"trigger_on": "trade_completed", "npc_id": "jia_scholar"}), 0, "StoryTableRegistry: npc_relationship_bonus 不匹配其他人物")
	var configured_task_chain: Array = card.get("task_chain", [])
	_assert_eq(configured_task_chain.size(), 2, "StoryTableRegistry: 刺桐商路札任务链由表配置两步")
	if configured_task_chain.size() >= 2:
		_assert_eq(str(configured_task_chain[0].get("completed_by", "")), "acquired", "StoryTableRegistry: 前置步骤使用 acquired 完成条件")
		_assert_eq(str(configured_task_chain[1].get("completed_by", "")), "story_flag", "StoryTableRegistry: 后续步骤使用 story_flag 完成条件")
	var configured_title: Dictionary = registry.get_title("title_rookie_merchant")
	var configured_title_chain: Array = configured_title.get("task_chain", [])
	_assert_eq(configured_title_chain.size(), 2, "StoryTableRegistry: 初露锋芒称号任务链由表配置两步")
	if configured_title_chain.size() >= 2:
		_assert_eq(str(configured_title_chain[0].get("completed_by", "")), "acquired", "StoryTableRegistry: 称号前置步骤使用 acquired 完成条件")
		_assert_eq(str(configured_title_chain[1].get("completed_by", "")), "story_flag", "StoryTableRegistry: 称号后续步骤使用 story_flag 完成条件")
	var configured_relationship: Dictionary = registry.get_relationship("lin_boyuan")
	var configured_relationship_chain: Array = configured_relationship.get("task_chain", [])
	_assert_eq(configured_relationship_chain.size(), 2, "StoryTableRegistry: 林伯渊关系任务链由表配置两步")
	if configured_relationship_chain.size() >= 2:
		_assert_eq(str(configured_relationship_chain[0].get("completed_by", "")), "relationship_min", "StoryTableRegistry: 关系前置步骤使用 relationship_min 完成条件")
		_assert_eq(int(configured_relationship_chain[0].get("relationship_min", -1)), 10, "StoryTableRegistry: 关系前置步骤阈值为10")
		_assert_eq(str(configured_relationship_chain[1].get("completed_by", "")), "story_flag", "StoryTableRegistry: 关系后续步骤使用 story_flag 完成条件")
	var matched_triggers: Array = registry.get_facility_triggers_for("quanzhou", "city_tavern")
	_assert_eq(matched_triggers.size(), 1, "StoryTableRegistry: 可按港口+设施查触发表")
	_assert_eq(str(matched_triggers[0].get("chain_id", "")), "ev_quanzhou_tavern_trade_card", "设施触发表指向事件链")

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 4)
	var restored := StoryState.new()
	restored.from_dict(story.to_dict())
	_assert_true(restored.has_card("card_zaitong_trade_intro"), "StoryState: 札存档往返")
	_assert_true(restored.has_title("title_rookie_merchant"), "StoryState: 称号存档往返")
	_assert_eq(restored.get_npc_relationship("lin_boyuan"), 4, "StoryState: 人物关系存档往返")

	print("")

# ── 太阁式札册展示测试 ────────────────────────────────────

func _test_storybook_presenter() -> void:
	print("[Storybook Presenter]")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	if presenter == null:
		print("")
		return

	var empty_story := StoryState.new()
	var empty_text: String = presenter.build_text(empty_story)
	_assert_true(empty_text.contains("未获得札"), "札册: 空状态显示未获得札")
	_assert_true(empty_text.contains("初识"), "札册: 空关系显示初识档")

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 12)
	var text: String = presenter.build_text(story)
	_assert_true(text.contains("刺桐商路札"), "札册: 显示已获得札名称")
	_assert_true(text.contains("初露锋芒的海商"), "札册: 显示已获得称号名称")
	_assert_true(text.contains("林伯渊"), "札册: 显示人物关系对象")
	_assert_true(text.contains("赏识"), "札册: 按关系值显示关系档位")

	var empty_model: Dictionary = presenter.build_view_model(empty_story)
	_assert_eq(empty_model.get("card_total", -1), 2, "札册模型: 包含配置表全部札")
	_assert_eq(empty_model.get("card_acquired", -1), 0, "札册模型: 空状态已获札为0")
	var empty_cards: Array = empty_model.get("cards", [])
	var has_locked_intro_card := false
	for card: Dictionary in empty_cards:
		if card.get("id", "") == "card_zaitong_trade_intro" and card.get("acquired", true) == false and str(card.get("display_name", "")) == "？？？":
			has_locked_intro_card = true
	_assert_true(has_locked_intro_card, "札册模型: 未获得札显示为？？？灰卡")

	var model: Dictionary = presenter.build_view_model(story)
	_assert_eq(model.get("card_acquired", -1), 1, "札册模型: 已获札计数")
	_assert_eq(model.get("title_acquired", -1), 1, "札册模型: 已获称号计数")
	_assert_true(model.get("tabs", []).has("札"), "札册模型: 含札页签")
	_assert_true(model.get("tabs", []).has("称号"), "札册模型: 含称号页签")
	_assert_true(model.get("tabs", []).has("人物关系"), "札册模型: 含人物关系页签")
	var found_acquired_intro_card := false
	for card: Dictionary in model.get("cards", []):
		if card.get("id", "") == "card_zaitong_trade_intro" and card.get("acquired", false) == true and card.get("display_name", "") == "刺桐商路札":
			found_acquired_intro_card = true
	_assert_true(found_acquired_intro_card, "札册模型: 已获得札显示真名")
	var found_relationship_row := false
	for row: Dictionary in model.get("relationships", []):
		if row.get("id", "") == "lin_boyuan" and row.get("value", 0) == 12 and row.get("level", "") == "赏识":
			found_relationship_row = true
	_assert_true(found_relationship_row, "札册模型: 人物关系含数值与档位")

	var view_builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if view_builder != null:
		var view: Control = view_builder.build(story)
		_assert_true(view is TabContainer, "札册UI: 根节点是 TabContainer")
		_assert_eq(view.get_child_count(), 3, "札册UI: 三个页签")
		_assert_true(view.find_child("CardsGrid", true, false) != null, "札册UI: 含札卡片网格")
		_assert_true(view.find_child("TitlesGrid", true, false) != null, "札册UI: 含称号卡片网格")
		_assert_true(view.find_child("RelationshipsList", true, false) != null, "札册UI: 含人物关系列表")
		_assert_true(view.find_child("Card_card_zaitong_trade_intro", true, false) != null, "札册UI: 含刺桐商路札卡片节点")
		_assert_true(view.find_child("Relationship_lin_boyuan", true, false) != null, "札册UI: 含林伯渊关系节点")
		view.free()

	var ui_file := FileAccess.open("res://data/ui_commands.json", FileAccess.READ)
	var ui_data = JSON.parse_string(ui_file.get_as_text()) if ui_file != null else {}
	var port_actions: Array = ui_data.get("templates", {}).get("port", {}).get("static_actions", []) if ui_data is Dictionary else []
	var has_storybook_action := false
	for action: Dictionary in port_actions:
		if action.get("id", "") == "storybook" and action.get("type", "") == "open_storybook":
			has_storybook_action = true
	_assert_true(has_storybook_action, "CommandBar: 港口模板含札册入口")

	print("")

# ── 太阁式札/称号/关系解锁行动测试 ───────────────────────

func _test_story_unlock_gates() -> void:
	print("[Story Unlock Gates]")

	var gm: Variant = root.get_node_or_null("/root/GameManager")
	_assert_true(gm != null, "解锁行动: GameManager autoload 存在")
	var tavern: Dictionary = gm.get_scene_by_id("city_tavern") if gm != null else {}
	var yamen: Dictionary = gm.get_scene_by_id("city_yamen") if gm != null else {}
	var guild: Dictionary = gm.get_scene_by_id("city_guild") if gm != null else {}
	_assert_true(not tavern.is_empty(), "解锁行动: 酒馆场景存在")
	_assert_true(not yamen.is_empty(), "解锁行动: 市舶司/衙门场景存在")
	_assert_true(not guild.is_empty(), "解锁行动: 工会场景存在")

	var card_action := _find_investigation_by_label(tavern, "打听刺桐商路")
	var title_action := _find_investigation_by_label(yamen, "海商称号")
	var relationship_action := _find_investigation_by_label(guild, "林伯渊")
	_assert_true(not card_action.is_empty(), "刺桐商路札: 酒馆特殊行动已配置")
	_assert_true(card_action.get("conditions", {}).get("effects_required", []).has("unlock:zaitong_trade_route_asked"), "刺桐商路札: 酒馆行动由札效果解锁")
	_assert_true(not title_action.is_empty(), "初露锋芒称号: 市舶司身份行动已配置")
	_assert_true(not relationship_action.is_empty(), "林伯渊关系: 深层市舶司消息行动已配置")
	_assert_true(str(relationship_action.get("text", "")).contains("林伯渊愿意透露更深的市舶司消息"), "林伯渊关系行动: 文案提示深层消息")

	var gate_state := KernelFakeState.new()
	_assert_true(not ConditionEvaluator.matches({"effects_required": ["unlock:zaitong_trade_route_asked"]}, {"game_state": gate_state}), "无刺桐商路札: 札效果权限未激活")
	_assert_true(not ConditionEvaluator.matches(card_action.get("conditions", {}), {"game_state": gate_state}), "无刺桐商路札: 酒馆特殊行动隐藏")
	gate_state.grant_card("card_zaitong_trade_intro")
	_assert_true(ConditionEvaluator.matches({"effects_required": ["unlock:zaitong_trade_route_asked"]}, {"game_state": gate_state}), "有刺桐商路札: 札效果权限激活")
	_assert_true(ConditionEvaluator.matches(card_action.get("conditions", {}), {"game_state": gate_state}), "有刺桐商路札: 酒馆特殊行动出现")

	gate_state = KernelFakeState.new()
	_assert_true(not ConditionEvaluator.matches(title_action.get("conditions", {}), {"game_state": gate_state}), "无初露锋芒称号: 市舶司身份行动隐藏")
	gate_state.grant_title("title_rookie_merchant")
	_assert_true(ConditionEvaluator.matches(title_action.get("conditions", {}), {"game_state": gate_state}), "有初露锋芒称号: 市舶司身份行动出现")

	gate_state = KernelFakeState.new()
	gate_state.adjust_npc_relationship("lin_boyuan", 9)
	_assert_true(not ConditionEvaluator.matches(relationship_action.get("conditions", {}), {"game_state": gate_state}), "林伯渊关系9: 深层消息隐藏")
	gate_state.adjust_npc_relationship("lin_boyuan", 1)
	_assert_true(ConditionEvaluator.matches(relationship_action.get("conditions", {}), {"game_state": gate_state}), "林伯渊关系10: 深层消息出现")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 10)
	var model: Dictionary = presenter.build_view_model(story)
	var card_row: Dictionary = _find_row_by_id(model.get("cards", []), "card_zaitong_trade_intro")
	var title_row: Dictionary = _find_row_by_id(model.get("titles", []), "title_rookie_merchant")
	var rel_row: Dictionary = _find_row_by_id(model.get("relationships", []), "lin_boyuan")
	_assert_true(str(card_row.get("unlock_text", "")).contains("打听刺桐商路"), "札册: 刺桐商路札显示用途")
	_assert_true(str(card_row.get("effect_text", "")).contains("打听刺桐商路"), "札册: 刺桐商路札显示效果摘要")
	_assert_true(str(title_row.get("unlock_text", "")).contains("市舶司"), "札册: 初露锋芒称号显示解锁内容")
	_assert_true(str(rel_row.get("unlock_text", "")).contains("更深的市舶司消息"), "札册: 林伯渊关系显示解锁内容")

	print("")

# ── 太阁式剧情分支解锁测试 ───────────────────────────────

func _test_chapter1_navigation_line_hook() -> void:
	print("[Chapter1 Navigation Line Hook]")

	var gm: Variant = root.get_node_or_null("/root/GameManager")
	_assert_true(gm != null, "航海线 hook: GameManager autoload 存在")
	if gm == null:
		print("")
		return

	var lin_ship: Dictionary = gm.get_scene_by_id("scene03_lin_ship")
	var hook: Dictionary = gm.get_scene_by_id("scene03b_navigation_line_hook")
	var departure: Dictionary = gm.get_scene_by_id("scene04_departure")
	_assert_true(not lin_ship.is_empty(), "航海线 hook: 林伯渊登船场景存在")
	_assert_true(not hook.is_empty(), "航海线 hook: 海上立身场景存在")
	_assert_true(not departure.is_empty(), "航海线 hook: 出港场景存在")
	if lin_ship.is_empty() or hook.is_empty() or departure.is_empty():
		print("")
		return

	for raw_choice in lin_ship.get("choices", []):
		if not raw_choice is Dictionary:
			continue
		var choice: Dictionary = raw_choice
		_assert_eq(str(choice.get("next", "")), "scene03b_navigation_line_hook", "航海线 hook: 林伯渊选择先进入身份 hook")

	var path_specs := {
		"nav_path_sea_merchant": "海商",
		"nav_path_private_fleet": "私人舰队",
		"nav_path_trade_merchant": "贸易商人",
		"nav_path_crewman": "船员",
	}
	var hook_choices: Array = hook.get("choices", [])
	_assert_eq(hook_choices.size(), path_specs.size(), "航海线 hook: 提供四个身份选择")

	var flags_by_choice := {}
	for raw_choice in hook_choices:
		if not raw_choice is Dictionary:
			continue
		var choice: Dictionary = raw_choice
		var effects: Dictionary = choice.get("effects", {})
		_assert_eq(str(choice.get("next", "")), "scene04_departure", "航海线 hook: 身份选择后进入出港")
		_assert_true(_effects_contain_story_flag(effects, "chapter1_navigation_identity_chosen"), "航海线 hook: 身份选择写入通用旗标")
		for flag in path_specs.keys():
			if _effects_contain_story_flag(effects, str(flag)):
				flags_by_choice[str(flag)] = choice

	var departure_inv_flags := {}
	for raw_inv in departure.get("investigations", []):
		if raw_inv is Dictionary:
			var inv: Dictionary = raw_inv
			var req := str(inv.get("requires_story_flag", ""))
			if req != "":
				departure_inv_flags[req] = inv

	for flag in path_specs.keys():
		var flag_text := str(flag)
		var label_part := str(path_specs[flag])
		_assert_true(flags_by_choice.has(flag_text), "航海线 hook: 写入身份旗标 %s" % flag_text)
		if flags_by_choice.has(flag_text):
			_assert_true(str(flags_by_choice[flag_text].get("label", "")).contains(label_part), "航海线 hook: %s 选择文案可识别" % label_part)
		_assert_true(departure_inv_flags.has(flag_text), "航海线 hook: 出港场景有 %s 身份回响" % label_part)

	print("")


func _effects_contain_story_flag(effects: Dictionary, flag: String) -> bool:
	for key in ["story_flag", "story_flag2", "story_flag3"]:
		if not effects.has(key):
			continue
		var raw = effects[key]
		if raw is String and raw == flag:
			return true
		if raw is Dictionary and bool((raw as Dictionary).get(flag, false)):
			return true
		if raw is Array and raw.has(flag):
			return true
	return false


func _test_story_branch_unlock_choices() -> void:
	print("[Story Branch Unlock Choices]")

	var gm: Variant = root.get_node_or_null("/root/GameManager")
	_assert_true(gm != null, "剧情分支: GameManager autoload 存在")
	var guild: Dictionary = gm.get_scene_by_id("city_guild") if gm != null else {}
	_assert_true(not guild.is_empty(), "剧情分支: 工会场景存在")

	var branch_choice := _find_choice_by_label(guild, "蒲氏私库")
	_assert_true(not branch_choice.is_empty(), "林伯渊深层消息: 蒲氏私库剧情分支已配置")
	_assert_eq(str(branch_choice.get("next", "")), "scene_quanzhou_pu_private_store_hint", "蒲氏私库分支: 指向专属剧情场景")
	var target_scene: Dictionary = gm.get_scene_by_id(str(branch_choice.get("next", ""))) if gm != null else {}
	_assert_true(not target_scene.is_empty(), "蒲氏私库分支: 目标剧情场景存在")

	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "剧情分支: GameState autoload 存在")
	var old_story = game_state.story if game_state != null else null
	if game_state != null:
		game_state.story = StoryState.new()
	var choice_handler_script = _load_script_or_fail("res://scripts/controllers/ChoiceHandler.gd", "ChoiceHandler 脚本可加载")
	if choice_handler_script == null:
		print("")
		return
	var handler = choice_handler_script.new()
	_assert_true(not handler._choice_available(branch_choice), "无深层消息/关系: 蒲氏私库分支隐藏")
	if game_state != null:
		game_state.story.set_story_flag("lin_boyuan_customs_deep_hint")
		game_state.story.adjust_npc_relationship("lin_boyuan", 9)
	_assert_true(not handler._choice_available(branch_choice), "林伯渊关系9: 蒲氏私库分支隐藏")
	if game_state != null:
		game_state.story.adjust_npc_relationship("lin_boyuan", 1)
	_assert_true(handler._choice_available(branch_choice), "林伯渊关系10+深层消息: 蒲氏私库分支出现")
	if game_state != null:
		game_state.story = old_story
	handler.free()

	print("")


# ── 太阁式人物关系深化测试 ───────────────────────────────

func _test_story_relationship_depth() -> void:
	print("[Story Relationship Depth]")

	var gm: Variant = root.get_node_or_null("/root/GameManager")
	_assert_true(gm != null, "人物关系深化: GameManager autoload 存在")
	var guild: Dictionary = gm.get_scene_by_id("city_guild") if gm != null else {}
	_assert_true(not guild.is_empty(), "人物关系深化: 工会场景存在")

	var visit_action := _find_investigation_by_label(guild, "拜访林伯渊")
	var gift_action := _find_investigation_by_label(guild, "送还《春秋》")
	var study_action := _find_investigation_by_label(guild, "请教接舷战术")
	_assert_true(not visit_action.is_empty(), "人物关系深化: 工会配置拜访林伯渊行动")
	_assert_true(not gift_action.is_empty(), "人物关系深化: 工会配置送还《春秋》行动")
	_assert_true(not study_action.is_empty(), "人物关系深化: 工会配置请教接舷战术行动")

	_assert_eq(str(visit_action.get("id", "")), "lin_boyuan_visit_guild", "拜访林伯渊: action id 稳定可聚焦")
	_assert_eq(str(visit_action.get("once_flag", "")), "lin_boyuan_visit_guild", "拜访林伯渊: 使用 once_flag 防重复")
	_assert_eq(str(visit_action.get("requires_story_flag", "")), "met_lin_boyuan", "拜访林伯渊: 需要先结识林伯渊")
	_assert_eq(str(visit_action.get("effects", {}).get("npc_relationship", {}).get("npc_id", "")), "lin_boyuan", "拜访林伯渊: 调整林伯渊关系")
	_assert_eq(int(visit_action.get("effects", {}).get("npc_relationship", {}).get("delta", 0)), 2, "拜访林伯渊: 关系 +2")

	_assert_eq(str(gift_action.get("id", "")), "lin_boyuan_gift_spring_autumn", "送还《春秋》: action id 稳定可聚焦")
	_assert_eq(str(gift_action.get("once_flag", "")), "lin_boyuan_gift_spring_autumn", "送还《春秋》: 使用 once_flag 防重复")
	_assert_eq(str(gift_action.get("requires_item", "")), "spring_autumn_scroll", "送还《春秋》: 需要持有《春秋》")
	_assert_eq(str(gift_action.get("effects", {}).get("item_removed", "")), "spring_autumn_scroll", "送还《春秋》: 归还后移除道具")
	_assert_eq(str(gift_action.get("effects", {}).get("npc_relationship", {}).get("npc_id", "")), "lin_boyuan", "送还《春秋》: 调整林伯渊关系")
	_assert_eq(int(gift_action.get("effects", {}).get("npc_relationship", {}).get("delta", 0)), 6, "送还《春秋》: 关系 +6")

	var study_conditions: Dictionary = study_action.get("conditions", {})
	_assert_eq(str(study_action.get("id", "")), "lin_boyuan_study_boarding", "请教接舷战术: action id 稳定可聚焦")
	_assert_eq(str(study_action.get("once_flag", "")), "learned_skill_boarding_tactics", "请教接舷战术: 学会后防重复")
	_assert_eq(str(study_conditions.get("relationship_npc_id", "")), "lin_boyuan", "请教接舷战术: 检查林伯渊关系")
	_assert_eq(int(study_conditions.get("npc_relationship_min", 0)), 15, "请教接舷战术: 关系门槛 15")
	_assert_true(study_conditions.get("story_flags_absent", []).has("learned_skill_boarding_tactics"), "请教接舷战术: 已学会后隐藏")
	_assert_eq(str(study_action.get("effects", {}).get("story_flag", "")), "learned_skill_boarding_tactics", "请教接舷战术: 写入学会旗标")
	_assert_eq(int(study_action.get("effects", {}).get("swordplay", 0)), 2, "请教接舷战术: 剑术/接舷能力 +2")
	_assert_eq(int(study_action.get("effects", {}).get("npc_relationship", {}).get("delta", 0)), 1, "请教接舷战术: 请教后关系 +1")

	var rel_state := KernelFakeState.new()
	rel_state.adjust_npc_relationship("lin_boyuan", 14)
	_assert_true(not ConditionEvaluator.matches(study_conditions, {"game_state": rel_state}), "请教接舷战术: 关系14时隐藏")
	rel_state.adjust_npc_relationship("lin_boyuan", 1)
	_assert_true(ConditionEvaluator.matches(study_conditions, {"game_state": rel_state}), "请教接舷战术: 关系15时出现")
	rel_state.set_story_flag("learned_skill_boarding_tactics", true)
	_assert_true(not ConditionEvaluator.matches(study_conditions, {"game_state": rel_state}), "请教接舷战术: 学会后隐藏")

	var registry = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY, "StoryTableRegistry 脚本可加载")
	registry.reload()
	var configured_relationship: Dictionary = registry.get_relationship("lin_boyuan")
	var relationship_actions: Array = configured_relationship.get("actions", [])
	var visit_table_action := _find_story_table_action_by_id(relationship_actions, "lin_boyuan_visit_guild")
	var gift_table_action := _find_story_table_action_by_id(relationship_actions, "lin_boyuan_gift_spring_autumn")
	var study_table_action := _find_story_table_action_by_id(relationship_actions, "lin_boyuan_study_boarding")
	_assert_true(not visit_table_action.is_empty(), "关系表: 记录拜访行动")
	_assert_true(not gift_table_action.is_empty(), "关系表: 记录送礼行动")
	_assert_true(not study_table_action.is_empty(), "关系表: 记录请教行动")
	_assert_eq(int(visit_table_action.get("relationship_delta", 0)), 2, "关系表: 拜访关系 +2")
	_assert_eq(str(gift_table_action.get("requires_item", "")), "spring_autumn_scroll", "关系表: 送礼需要《春秋》")
	_assert_eq(int(gift_table_action.get("relationship_delta", 0)), 6, "关系表: 送礼关系 +6")
	_assert_eq(int(study_table_action.get("relationship_min", 0)), 15, "关系表: 请教关系门槛 15")
	_assert_eq(str(study_table_action.get("story_flag", "")), "learned_skill_boarding_tactics", "关系表: 请教写入战术旗标")

	print("")

func _find_choice_by_label(scene_data: Dictionary, label_part: String) -> Dictionary:
	for raw in scene_data.get("choices", []):
		if raw is Dictionary and str(raw.get("label", "")).contains(label_part):
			return raw
	return {}


# ── 太阁式交易前收益预览测试 ───────────────────────────────

func _test_trade_effect_preview() -> void:
	print("[Trade Effect Preview]")

	var old_loaded = _story_event_chain_engine()._loaded
	var old_chains: Dictionary = _story_event_chain_engine()._chains.duplicate(true)
	_story_event_chain_engine()._loaded = true
	_story_event_chain_engine()._chains = {
		"test_trade_preview": {
			"trigger_on": ["trade_completed"],
			"conditions": {
				"port_id": "quanzhou",
				"trade_action": "sell",
				"good_id": "fujian_porcelain",
				"amount_min": 3,
			},
			"effects": [
				{"type": "apply_effects", "effects": {"fame": 2, "money": 100}},
				{"type": "npc_relationship", "npc_id": "lin_boyuan", "delta": 2},
				{"type": "port_affinity", "port_id": "quanzhou", "delta": 1.0},
			],
		},
	}

	var preview_state := KernelFakeState.new()
	preview_state.grant_card("card_zaitong_trade_intro")
	preview_state.grant_title("title_rookie_merchant")
	preview_state.adjust_npc_relationship("lin_boyuan", 10)
	var preview_ctx := {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": preview_state,
	}
	var preview_text: String = _story_event_chain_engine().build_trigger_preview_text("trade_completed", preview_ctx)
	_assert_true(preview_text.contains("预计收益"), "交易前预览: 输出标题")
	_assert_true(preview_text.contains("基础：") and preview_text.contains("名声+2") and preview_text.contains("银两+100"), "交易前预览: 显示基础名声与银两")
	_assert_true(preview_text.contains("林伯渊关系+2") and preview_text.contains("泉州好感+1"), "交易前预览: 显示基础关系与港口好感")
	_assert_true(preview_text.contains("札效：") and preview_text.contains("名声+1"), "交易前预览: 显示札效名声加成")
	_assert_true(preview_text.contains("称号：") and preview_text.contains("银两+50") and preview_text.contains("泉州好感+0.5"), "交易前预览: 显示称号银两与港口好感加成")
	_assert_true(preview_text.contains("关系：") and preview_text.contains("林伯渊关系+1"), "交易前预览: 显示人物关系加成")
	_assert_true(preview_text.contains("合计：") and preview_text.contains("名声+3") and preview_text.contains("银两+150"), "交易前预览: 显示合计名声与银两")
	_assert_true(preview_text.contains("林伯渊关系+3") and preview_text.contains("泉州好感+1.5"), "交易前预览: 显示合计关系与港口好感")

	var grant_state := KernelFakeState.new()
	grant_state.grant_card("card_zaitong_trade_intro")
	var grant_text: String = _story_event_chain_engine().build_trigger_preview_text("trade_completed", {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": grant_state,
	})
	_assert_true(grant_text.contains("预计获得") and grant_text.contains("称号「初露锋芒的海商」"), "交易前预览: 显示本次交易将自动获得称号")
	_assert_true(not grant_state.has_title("title_rookie_merchant"), "交易前预览: 只预览自动获得，不提前授予称号")

	var wrong_text: String = _story_event_chain_engine().build_trigger_preview_text("trade_completed", {
		"port_id": "quanzhou",
		"trade_action": "buy",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": preview_state,
	})
	_assert_eq(wrong_text, "", "交易前预览: 不匹配交易条件时不显示")

	_story_event_chain_engine()._chains = old_chains
	_story_event_chain_engine()._loaded = old_loaded
	print("")

# ── 太阁式自动获得反馈测试 ───────────────────────────────

func _test_auto_grant_feedback() -> void:
	print("[Auto Grant Feedback]")

	var old_loaded = _story_event_chain_engine()._loaded
	var old_chains: Dictionary = _story_event_chain_engine()._chains.duplicate(true)
	_story_event_chain_engine()._loaded = true
	_story_event_chain_engine()._chains = {}

	var callback_state := KernelFakeState.new()
	callback_state.grant_card("card_zaitong_trade_intro")
	var captured: Array[String] = []
	var callback := func(msg: String) -> void:
		captured.append(msg)
	_story_event_chain_engine().check_triggers("trade_completed", {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": callback_state,
		"message_callback": callback,
	})
	var captured_text := "".join(captured)
	_assert_true(callback_state.has_title("title_rookie_merchant"), "自动获得反馈: 满足条件时仍自动授予称号")
	_assert_true(captured_text.contains("自动获得") and captured_text.contains("称号「初露锋芒的海商」"), "自动获得反馈: callback 输出称号获得提示")
	var captured_count := captured.size()
	_story_event_chain_engine().check_triggers("trade_completed", {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": callback_state,
		"message_callback": callback,
	})
	_assert_eq(captured.size(), captured_count, "自动获得反馈: 已拥有称号时不重复输出提示")

	var log_state := KernelFakeState.new()
	log_state.game_log = GameLog.new()
	log_state.set_story_flag("chapter1_complete", true)
	_story_event_chain_engine().check_triggers("enter_facility", {
		"port_id": "quanzhou",
		"facility_id": "city_tavern",
		"scene_id": "city_tavern",
		"game_state": log_state,
	})
	var latest: String = log_state.game_log.get_latest(GameLog.Category.EVENT)
	_assert_true(log_state.has_card("card_zaitong_trade_intro"), "自动获得反馈: 满足条件时仍自动授予札")
	_assert_true(latest.contains("自动获得") and latest.contains("札「刺桐商路札」"), "自动获得反馈: 无 callback 时写入事件日志")

	_story_event_chain_engine()._chains = old_chains
	_story_event_chain_engine()._loaded = old_loaded
	print("")

# ── 太阁式解锁反馈日志测试 ───────────────────────────────

func _test_story_unlock_feedback() -> void:
	print("[Story Unlock Feedback]")

	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "解锁反馈: GameState autoload 存在")
	if game_state == null:
		print("")
		return

	var old_story = game_state.story
	var old_log = game_state.game_log
	game_state.story = StoryState.new()
	game_state.game_log = GameLog.new()

	game_state.grant_card("card_zaitong_trade_intro")
	var latest: String = game_state.game_log.get_latest(GameLog.Category.EVENT)
	_assert_true(latest.contains("获得札") and latest.contains("刺桐商路札"), "解锁反馈: 获得札写入事件日志")
	_assert_true(latest.contains("打听刺桐商路"), "解锁反馈: 札日志包含用途")
	var event_count: int = game_state.game_log.get_entries(GameLog.Category.EVENT).size()
	game_state.grant_card("card_zaitong_trade_intro")
	_assert_eq(game_state.game_log.get_entries(GameLog.Category.EVENT).size(), event_count, "解锁反馈: 重复获得札不重复记日志")

	game_state.grant_title("title_rookie_merchant")
	latest = game_state.game_log.get_latest(GameLog.Category.EVENT)
	_assert_true(latest.contains("获得称号") and latest.contains("初露锋芒的海商"), "解锁反馈: 获得称号写入事件日志")
	_assert_true(latest.contains("市舶司"), "解锁反馈: 称号日志包含解锁内容")

	event_count = game_state.game_log.get_entries(GameLog.Category.EVENT).size()
	game_state.adjust_npc_relationship("lin_boyuan", 9)
	_assert_eq(game_state.game_log.get_entries(GameLog.Category.EVENT).size(), event_count, "解锁反馈: 未跨关系档位不写突破日志")
	game_state.adjust_npc_relationship("lin_boyuan", 1)
	latest = game_state.game_log.get_latest(GameLog.Category.EVENT)
	_assert_true(latest.contains("关系突破") and latest.contains("林伯渊") and latest.contains("赏识"), "解锁反馈: 关系档位突破写入事件日志")
	_assert_true(latest.contains("更深的市舶司消息"), "解锁反馈: 关系突破日志包含解锁内容")

	game_state.story = old_story
	game_state.game_log = old_log
	print("")

# ── 太阁式解锁反馈可见化测试 ─────────────────────────────

func _test_story_unlock_visible_feedback() -> void:
	print("[Story Unlock Visible Feedback]")

	var game_state = root.get_node_or_null("/root/GameState")
	_assert_true(game_state != null, "可见解锁反馈: GameState autoload 存在")
	if game_state == null:
		print("")
		return

	_assert_true(game_state.has_signal("story_unlock_notified"), "可见解锁反馈: GameState 定义 story_unlock_notified 信号")
	var captured: Array[String] = []
	var callback := func(msg: String) -> void:
		captured.append(msg)

	var old_story = game_state.story
	var old_log = game_state.game_log
	game_state.story = StoryState.new()
	game_state.game_log = GameLog.new()
	if game_state.has_signal("story_unlock_notified"):
		game_state.story_unlock_notified.connect(callback)
	game_state.grant_card("card_zaitong_trade_intro")
	if game_state.has_signal("story_unlock_notified") and game_state.story_unlock_notified.is_connected(callback):
		game_state.story_unlock_notified.disconnect(callback)
	game_state.story = old_story
	game_state.game_log = old_log

	_assert_eq(captured.size(), 1, "可见解锁反馈: 获得札时发出一条界面提示")
	var visible_msg := captured[0] if not captured.is_empty() else ""
	_assert_true(visible_msg.contains("【解锁】") and visible_msg.contains("刺桐商路札"), "可见解锁反馈: 提示含解锁前缀与札名")
	_assert_true(visible_msg.contains("打听刺桐商路"), "可见解锁反馈: 提示含新行动用途")

	var main_file := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text() if main_file != null else ""
	_assert_true(main_text.contains("story_unlock_notified.connect(_prepend_event_log"), "可见解锁反馈: Main 将解锁提示接入事件栏")

	print("")

# ── 太阁式解锁 Toast 高亮测试 ─────────────────────────────

func _test_story_unlock_toast_feedback() -> void:
	print("[Story Unlock Toast Feedback]")

	var main_file := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text() if main_file != null else ""
	var toast_file := FileAccess.open(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, FileAccess.READ)
	var toast_text := toast_file.get_as_text() if toast_file != null else ""
	_assert_true(main_text.contains("StoryUnlockToastControllerScript"), "解锁Toast: Main 创建 Toast 控制器")
	_assert_true(main_text.contains("_setup_story_unlock_toast()"), "解锁Toast: Main ready 阶段创建 Toast 层")
	_assert_true(main_text.contains("story_unlock_notified.connect(_show_story_unlock_toast"), "解锁Toast: 解锁信号接入 Toast 动画")
	_assert_true(toast_text.contains("STORY_UNLOCK_TOAST_NAME"), "解锁Toast: 控制器定义 Toast 节点常量")
	_assert_true(toast_text.contains("StoryUnlockToastLabel"), "解锁Toast: Toast 含专用文本 Label")
	_assert_true(toast_text.contains("theme_type_variation = &\"PortTitleBanner\""), "解锁Toast: 面板复用主题变体")
	_assert_true(toast_text.contains("theme_type_variation = &\"MarketTitle\""), "解锁Toast: 文本复用高亮标题主题")
	_assert_true(toast_text.contains("create_tween()"), "解锁Toast: 使用 Tween 播放短暂高亮")
	_assert_true(toast_text.contains("modulate:a"), "解锁Toast: Tween 包含淡入淡出")
	_assert_true(toast_text.contains("tween_interval(STORY_UNLOCK_TOAST_HOLD"), "解锁Toast: Toast 保持短暂停留")

	var toast_script = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, "StoryUnlockToastController 脚本可加载")
	var toast_controller = toast_script.new() if toast_script != null else null
	_assert_true(toast_controller != null, "解锁Toast: 控制器脚本可实例化")
	if toast_controller != null and toast_controller.has_method("_setup_story_unlock_toast"):
		toast_controller.call("_setup_story_unlock_toast")
		var toast = toast_controller.get_node_or_null("StoryUnlockToast")
		_assert_true(toast is PanelContainer, "解锁Toast: 创建 PanelContainer Toast 节点")
		_assert_true(toast != null and toast.visible == false, "解锁Toast: 初始隐藏")
		_assert_true(toast != null and toast.mouse_filter == Control.MOUSE_FILTER_STOP, "解锁Toast: 可点击并拦截鼠标")
		var label = toast.find_child("StoryUnlockToastLabel", true, false) if toast != null else null
		_assert_true(label is Label, "解锁Toast: 创建文本 Label")
	else:
		_assert_true(false, "解锁Toast: 控制器暴露 _setup_story_unlock_toast")
	if toast_controller != null:
		toast_controller.free()

	print("")

# ── 太阁式解锁 Toast 分类测试 ─────────────────────────────

func _test_story_unlock_toast_categories() -> void:
	print("[Story Unlock Toast Categories]")

	var toast_script = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, "StoryUnlockToastController 脚本可加载")
	var toast_controller = toast_script.new() if toast_script != null else null
	_assert_true(toast_controller != null, "分类Toast: 控制器脚本可实例化")
	if toast_controller == null:
		print("")
		return

	_assert_true(toast_controller.has_method("_format_story_unlock_toast"), "分类Toast: 控制器暴露 Toast 分类格式化")
	if toast_controller.has_method("_format_story_unlock_toast"):
		var card: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得札「刺桐商路札」：打听刺桐商路")
		_assert_eq(card.get("badge", ""), "札入手", "分类Toast: 获得札显示札入手")
		_assert_eq(card.get("icon", ""), "◆", "分类Toast: 札使用札图标")
		_assert_true(str(card.get("text", "")).contains("刺桐商路札"), "分类Toast: 札正文保留札名")
		_assert_true(not str(card.get("text", "")).contains("【解锁】"), "分类Toast: 正文移除通用解锁前缀")

		var title: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
		_assert_eq(title.get("badge", ""), "称号获得", "分类Toast: 获得称号显示称号获得")
		_assert_eq(title.get("icon", ""), "★", "分类Toast: 称号使用星标图标")

		var relationship: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】关系突破「林伯渊」→ 赏识：更深的市舶司消息")
		_assert_eq(relationship.get("badge", ""), "关系进展", "分类Toast: 关系突破显示关系进展")
		_assert_eq(relationship.get("icon", ""), "◎", "分类Toast: 关系使用环形图标")

		var fallback: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】新的剧情线索")
		_assert_eq(fallback.get("badge", ""), "解锁", "分类Toast: 未知解锁使用默认分类")
		_assert_eq(fallback.get("icon", ""), "◇", "分类Toast: 未知解锁使用默认图标")

	toast_controller.call("_setup_story_unlock_toast")
	var toast = toast_controller.get_node_or_null("StoryUnlockToast")
	var badge = toast.find_child("StoryUnlockToastBadge", true, false) if toast != null else null
	var label = toast.find_child("StoryUnlockToastLabel", true, false) if toast != null else null
	_assert_true(badge is Label, "分类Toast: Toast 创建分类徽标 Label")
	if toast_controller.has_method("_show_story_unlock_toast"):
		toast_controller.call("_show_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
		_assert_true(badge != null and str(badge.text).contains("称号获得"), "分类Toast: 徽标显示称号分类")
		_assert_true(badge != null and str(badge.text).contains("★"), "分类Toast: 徽标显示称号图标")
		_assert_true(label != null and str(label.text).contains("初露锋芒的海商"), "分类Toast: 正文显示称号名")
		_assert_true(label != null and not str(label.text).contains("【解锁】"), "分类Toast: 正文不重复通用前缀")

	toast_controller.free()
	print("")

# ── 太阁式解锁 Toast 点击札册跳转测试 ─────────────────────

func _test_story_unlock_toast_storybook_jump() -> void:
	print("[Story Unlock Toast Storybook Jump]")

	var main_file := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text() if main_file != null else ""
	var toast_file := FileAccess.open(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, FileAccess.READ)
	var toast_text := toast_file.get_as_text() if toast_file != null else ""
	_assert_true(main_text.contains("StoryUnlockToastControllerScript"), "Toast跳札册: Main 使用 Toast 控制器")
	_assert_true(toast_text.contains("_unlock_toast_tab"), "Toast跳札册: 控制器保存目标页签")
	_assert_true(toast_text.contains("gui_input.connect(_on_story_unlock_toast_gui_input"), "Toast跳札册: Toast 接入点击事件")
	_assert_true(toast_text.contains("_game_shell.show_storybook(_unlock_toast_tab"), "Toast跳札册: 点击后调用札册目标页签")

	var shell_file := FileAccess.open("res://scripts/GameShell.gd", FileAccess.READ)
	var shell_text := shell_file.get_as_text() if shell_file != null else ""
	_assert_true(shell_text.contains("func show_storybook(initial_tab: int = 0"), "Toast跳札册: GameShell 支持指定页签打开札册")
	_assert_true(shell_text.contains("STORYBOOK_VIEW_BUILDER.build(GameState.story, initial_tab"), "Toast跳札册: GameShell 将目标页签传给札册 UI")

	var toast_script = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, "StoryUnlockToastController 脚本可加载")
	var toast_controller = toast_script.new() if toast_script != null else null
	_assert_true(toast_controller != null, "Toast跳札册: 控制器脚本可实例化")
	if toast_controller != null and toast_controller.has_method("_format_story_unlock_toast"):
		var card: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得札「刺桐商路札」：打听刺桐商路")
		var title: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
		var relationship: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】关系突破「林伯渊」→ 赏识：更深的市舶司消息")
		_assert_eq(card.get("tab", -1), 0, "Toast跳札册: 札入手跳到札页")
		_assert_eq(title.get("tab", -1), 1, "Toast跳札册: 称号获得跳到称号页")
		_assert_eq(relationship.get("tab", -1), 2, "Toast跳札册: 关系进展跳到人物关系页")
		toast_controller.call("_setup_story_unlock_toast")
		var toast = toast_controller.get_node_or_null("StoryUnlockToast")
		_assert_true(toast != null and toast.mouse_filter == Control.MOUSE_FILTER_STOP, "Toast跳札册: Toast 可点击且拦截鼠标")
		toast_controller.call("_show_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
		_assert_eq(toast_controller.get("_unlock_toast_tab"), 1, "Toast跳札册: 显示称号 Toast 后保存称号页签")
	else:
		_assert_true(false, "Toast跳札册: 控制器暴露 Toast 格式化")
	if toast_controller != null:
		toast_controller.free()

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder != null:
		var story := StoryState.new()
		var title_view: Control = builder.build(story, 1)
		_assert_true(title_view is TabContainer and int(title_view.get_meta("initial_tab", -1)) == 1, "Toast跳札册: 札册记录默认打开称号页")
		title_view.free()
		var relationship_view: Control = builder.build(story, 2)
		_assert_true(relationship_view is TabContainer and int(relationship_view.get_meta("initial_tab", -1)) == 2, "Toast跳札册: 札册记录默认打开人物关系页")
		relationship_view.free()

	print("")

# ── 太阁式解锁 Toast 札册定位测试 ───────────────────────

func _test_story_unlock_toast_storybook_focus() -> void:
	print("[Story Unlock Toast Storybook Focus]")

	var main_file := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text() if main_file != null else ""
	var toast_file := FileAccess.open(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, FileAccess.READ)
	var toast_text := toast_file.get_as_text() if toast_file != null else ""
	_assert_true(main_text.contains("StoryUnlockToastControllerScript"), "Toast定位: Main 使用 Toast 控制器")
	_assert_true(toast_text.contains("_unlock_toast_target_id"), "Toast定位: 控制器保存札册目标条目 id")
	_assert_true(toast_text.contains("_game_shell.show_storybook(_unlock_toast_tab, _unlock_toast_target_id"), "Toast定位: 点击后传递目标条目 id")

	var shell_file := FileAccess.open("res://scripts/GameShell.gd", FileAccess.READ)
	var shell_text := shell_file.get_as_text() if shell_file != null else ""
	_assert_true(shell_text.contains("func show_storybook(initial_tab: int = 0, focus_id: String = \"\")"), "Toast定位: GameShell 支持指定札册聚焦条目")
	_assert_true(shell_text.contains("STORYBOOK_VIEW_BUILDER.build(GameState.story, initial_tab, focus_id"), "Toast定位: GameShell 将聚焦条目传给札册 UI")

	var toast_script = _load_script_or_fail(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER, "StoryUnlockToastController 脚本可加载")
	var toast_controller = toast_script.new() if toast_script != null else null
	_assert_true(toast_controller != null, "Toast定位: 控制器脚本可实例化")
	if toast_controller != null and toast_controller.has_method("_format_story_unlock_toast"):
		var card: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得札「刺桐商路札」：打听刺桐商路")
		var title: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
		var relationship: Dictionary = toast_controller.call("_format_story_unlock_toast", "【解锁】关系突破「林伯渊」→ 赏识：更深的市舶司消息")
		_assert_eq(str(card.get("target_id", "")), "card_zaitong_trade_intro", "Toast定位: 札消息解析到札 id")
		_assert_eq(str(title.get("target_id", "")), "title_rookie_merchant", "Toast定位: 称号消息解析到称号 id")
		_assert_eq(str(relationship.get("target_id", "")), "lin_boyuan", "Toast定位: 关系消息解析到人物 id")
		if toast_text.contains("_unlock_toast_target_id") and toast_controller.has_method("_show_story_unlock_toast"):
			toast_controller.call("_setup_story_unlock_toast")
			toast_controller.call("_show_story_unlock_toast", "【解锁】获得称号「初露锋芒的海商」：可向市舶司递话")
			_assert_eq(str(toast_controller.get("_unlock_toast_target_id")), "title_rookie_merchant", "Toast定位: 显示称号 Toast 后保存目标称号 id")
		else:
			_assert_true(false, "Toast定位: 控制器暴露并保存目标条目 id")
	else:
		_assert_true(false, "Toast定位: 控制器暴露 Toast 格式化")
	if toast_controller != null:
		toast_controller.free()

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder != null and shell_text.contains("focus_id"):
		var story := StoryState.new()
		story.grant_card("card_zaitong_trade_intro")
		story.grant_title("title_rookie_merchant")
		story.adjust_npc_relationship("lin_boyuan", 12)

		var card_view: Control = builder.build(story, 0, "card_zaitong_trade_intro")
		_assert_eq(str(card_view.get_meta("focus_id", "")), "card_zaitong_trade_intro", "札册定位: 根节点记录聚焦札 id")
		var focused_card = card_view.find_child("Card_card_zaitong_trade_intro", true, false)
		_assert_true(focused_card != null and focused_card.get_meta("storybook_focus_target", false) == true, "札册定位: 目标札节点被标记高亮")
		_assert_true(focused_card != null and str(focused_card.theme_type_variation) == UITheme.CARD_FACILITY_QUEST, "札册定位: 目标札使用高亮卡片主题")
		var cards_page = card_view.find_child("CardsPage", true, false)
		_assert_eq(str(cards_page.get_meta("focus_target_id", "")), "card_zaitong_trade_intro", "札册定位: 札页记录滚动目标")
		card_view.free()

		var title_view: Control = builder.build(story, 1, "title_rookie_merchant")
		var focused_title = title_view.find_child("Title_title_rookie_merchant", true, false)
		_assert_true(focused_title != null and focused_title.get_meta("storybook_focus_target", false) == true, "札册定位: 目标称号节点被标记高亮")
		title_view.free()

		var relationship_view: Control = builder.build(story, 2, "lin_boyuan")
		var focused_relationship = relationship_view.find_child("Relationship_lin_boyuan", true, false)
		_assert_true(focused_relationship != null and focused_relationship.get_meta("storybook_focus_target", false) == true, "札册定位: 目标人物关系节点被标记高亮")
		relationship_view.free()
	else:
		_assert_true(false, "札册定位: StorybookViewBuilder 支持 focus_id 参数")

	print("")

# ── 太阁式札册条目详情测试 ───────────────────────────────

func _test_storybook_detail_panel() -> void:
	print("[Storybook Detail Panel]")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	if presenter == null:
		print("")
		return

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 12)
	var model: Dictionary = presenter.build_view_model(story)
	var card_row: Dictionary = _find_row_by_id(model.get("cards", []), "card_zaitong_trade_intro")
	var title_row: Dictionary = _find_row_by_id(model.get("titles", []), "title_rookie_merchant")
	var rel_row: Dictionary = _find_row_by_id(model.get("relationships", []), "lin_boyuan")
	_assert_eq(str(card_row.get("source_event", "")), "ev_quanzhou_tavern_trade_card", "札册详情模型: 札记录来源事件")
	_assert_true(str(card_row.get("effect_text", "")).contains("打听刺桐商路"), "札册详情模型: 札记录效果说明")
	_assert_true(str(card_row.get("active_bonus_text", "")).contains("名声额外+1"), "札册详情模型: 札记录当前可生效名声加成")
	_assert_true(str(title_row.get("active_bonus_text", "")).contains("银两额外+50"), "札册详情模型: 称号记录当前可生效银两加成")
	_assert_true(str(rel_row.get("active_bonus_text", "")).contains("林伯渊关系额外+1"), "札册详情模型: 关系记录当前可生效关系加成")
	_assert_eq(str(card_row.get("route_scene_id", "")), "city_tavern", "札册详情模型: 札记录直达场景")
	_assert_eq(str(title_row.get("source_event", "")), "ev_rookie_merchant_title", "札册详情模型: 称号记录来源事件")
	_assert_eq(str(title_row.get("route_scene_id", "")), "city_yamen", "札册详情模型: 称号记录直达场景")
	_assert_eq(str(rel_row.get("route_scene_id", "")), "city_guild", "札册详情模型: 人物关系记录直达场景")

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder == null:
		print("")
		return

	var view: Control = builder.build(story, 0, "card_zaitong_trade_intro")
	var cards_detail = view.find_child("CardsDetailPanel", true, false)
	var cards_detail_text = view.find_child("CardsDetailText", true, false)
	var cards_route_button = view.find_child("CardsDetailRouteButton", true, false)
	_assert_true(cards_detail is PanelContainer, "札册详情UI: 札页含详情面板")
	_assert_true(cards_detail_text is RichTextLabel, "札册详情UI: 札页含详情文本")
	_assert_true(cards_route_button is Button, "札册详情UI: 札页含直达按钮")
	_assert_true(cards_detail_text != null and str(cards_detail_text.text).contains("来源事件") and str(cards_detail_text.text).contains("ev_quanzhou_tavern_trade_card"), "札册详情UI: 详情显示来源事件")
	_assert_true(cards_detail_text != null and str(cards_detail_text.text).contains("解锁行动") and str(cards_detail_text.text).contains("打听刺桐商路"), "札册详情UI: 详情显示解锁行动")
	_assert_true(cards_detail_text != null and str(cards_detail_text.text).contains("效果") and str(cards_detail_text.text).contains("打听刺桐商路"), "札册详情UI: 详情显示札效果")
	_assert_true(cards_detail_text != null and str(cards_detail_text.text).contains("当前可生效加成") and str(cards_detail_text.text).contains("名声额外+1"), "札册详情UI: 详情显示当前可生效加成")
	_assert_eq(str(cards_route_button.get_meta("scene_id", "")) if cards_route_button != null else "", "city_tavern", "札册详情UI: 札页直达按钮记录场景")

	var titles_detail_text = view.find_child("TitlesDetailText", true, false)
	var titles_route_button = view.find_child("TitlesDetailRouteButton", true, false)
	var title_card = view.find_child("Title_title_rookie_merchant", true, false)
	_assert_true(title_card != null and title_card.mouse_filter == Control.MOUSE_FILTER_STOP, "札册详情UI: 称号条目可点击")
	if title_card != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		title_card.emit_signal("gui_input", click)
	_assert_true(titles_detail_text != null and str(titles_detail_text.text).contains("初露锋芒的海商"), "札册详情UI: 点击称号后更新详情文本")
	_assert_true(titles_detail_text != null and str(titles_detail_text.text).contains("当前可生效加成") and str(titles_detail_text.text).contains("银两额外+50"), "札册详情UI: 称号详情显示当前可生效加成")
	_assert_eq(str(titles_route_button.get_meta("scene_id", "")) if titles_route_button != null else "", "city_yamen", "札册详情UI: 称号直达按钮记录场景")

	var rel_detail_text = view.find_child("RelationshipsDetailText", true, false)
	var rel_route_button = view.find_child("RelationshipsDetailRouteButton", true, false)
	var rel_card = view.find_child("Relationship_lin_boyuan", true, false)
	_assert_true(rel_card != null and rel_card.mouse_filter == Control.MOUSE_FILTER_STOP, "札册详情UI: 人物关系条目可点击")
	if rel_card != null:
		var rel_click := InputEventMouseButton.new()
		rel_click.button_index = MOUSE_BUTTON_LEFT
		rel_click.pressed = true
		rel_card.emit_signal("gui_input", rel_click)
	_assert_true(rel_detail_text != null and str(rel_detail_text.text).contains("林伯渊") and str(rel_detail_text.text).contains("更深的市舶司消息"), "札册详情UI: 点击人物关系后更新详情文本")
	_assert_eq(str(rel_route_button.get_meta("scene_id", "")) if rel_route_button != null else "", "city_guild", "札册详情UI: 人物关系直达按钮记录场景")
	view.free()

	var shell_file := FileAccess.open("res://scripts/GameShell.gd", FileAccess.READ)
	var shell_text := shell_file.get_as_text() if shell_file != null else ""
	_assert_true(shell_text.contains("_on_storybook_route_requested"), "札册详情直达: GameShell 接收札册直达请求")
	_assert_true(shell_text.contains("navigation_requested.emit(scene_id)"), "札册详情直达: GameShell 通过 navigation_requested 直达场景")

	print("")

func _capture_storybook_route(scene_id: String, focus_action_id: String = "") -> void:
	_captured_storybook_route_scene_id = scene_id
	_captured_storybook_route_focus_action_id = focus_action_id

# ── 太阁式札册直达行动高亮测试 ─────────────────────────────

func _test_storybook_route_action_focus() -> void:
	print("[Storybook Route Action Focus]")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	if presenter == null:
		print("")
		return

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 12)
	var model: Dictionary = presenter.build_view_model(story)
	var card_row: Dictionary = _find_row_by_id(model.get("cards", []), "card_zaitong_trade_intro")
	var title_row: Dictionary = _find_row_by_id(model.get("titles", []), "title_rookie_merchant")
	var rel_row: Dictionary = _find_row_by_id(model.get("relationships", []), "lin_boyuan")
	_assert_eq(str(card_row.get("route_focus_action_id", "")), "zaitong_trade_route_asked", "札册直达行动模型: 札记录目标行动 id")
	_assert_eq(str(title_row.get("route_focus_action_id", "")), "rookie_merchant_yamen_recognized", "札册直达行动模型: 称号记录目标行动 id")
	_assert_eq(str(rel_row.get("route_focus_action_id", "")), "lin_boyuan_customs_deep_hint", "札册直达行动模型: 人物关系记录目标行动 id")

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder == null:
		print("")
		return

	_captured_storybook_route_scene_id = ""
	_captured_storybook_route_focus_action_id = ""
	var view: Control = builder.build(story, 0, "card_zaitong_trade_intro", Callable(self, "_capture_storybook_route"))
	var route_button = view.find_child("CardsDetailRouteButton", true, false)
	_assert_eq(str(route_button.get_meta("scene_id", "")) if route_button != null else "", "city_tavern", "札册直达行动UI: 直达按钮记录场景")
	_assert_eq(str(route_button.get_meta("focus_action_id", "")) if route_button != null else "", "zaitong_trade_route_asked", "札册直达行动UI: 直达按钮记录目标行动")
	if route_button != null:
		route_button.emit_signal("pressed")
	_assert_eq(_captured_storybook_route_scene_id, "city_tavern", "札册直达行动UI: 点击按钮回调目标场景")
	_assert_eq(_captured_storybook_route_focus_action_id, "zaitong_trade_route_asked", "札册直达行动UI: 点击按钮回调目标行动")
	view.free()

	var shell_file := FileAccess.open("res://scripts/GameShell.gd", FileAccess.READ)
	var shell_text := shell_file.get_as_text() if shell_file != null else ""
	_assert_true(shell_text.contains("signal storybook_route_requested(scene_id: String, focus_action_id: String)"), "札册直达行动: GameShell 暴露带行动焦点的直达信号")
	_assert_true(shell_text.contains("storybook_route_requested.emit(scene_id, focus_action_id)"), "札册直达行动: GameShell 发出场景+行动焦点")

	var main_file := FileAccess.open("res://scripts/Main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text() if main_file != null else ""
	_assert_true(main_text.contains("_pending_route_focus_action_id"), "札册直达行动: Main 暂存目标行动焦点")
	_assert_true(main_text.contains("storybook_route_requested.connect(_on_storybook_route_requested)"), "札册直达行动: Main 连接札册直达信号")
	_assert_true(main_text.contains("func _on_storybook_route_requested(scene_id: String, focus_action_id: String)"), "札册直达行动: Main 接收场景+行动焦点")
	_assert_true(main_text.contains("present_scene(scene_data, scene_id, focus_action_id)"), "札册直达行动: Main 将行动焦点交给场景呈现器")

	var presenter_file := FileAccess.open("res://scripts/MainScenePresenter.gd", FileAccess.READ)
	var presenter_text := presenter_file.get_as_text() if presenter_file != null else ""
	_assert_true(presenter_text.contains("setup_investigation\", scene_data, scene_id, focus_action_id"), "札册直达行动: 场景呈现器将行动焦点传给调查设施")

	var facility_file := FileAccess.open("res://scripts/FacilityController.gd", FileAccess.READ)
	var facility_text := facility_file.get_as_text() if facility_file != null else ""
	_assert_true(facility_text.contains("func setup_investigation(scene_data: Dictionary, scene_id: String, focus_action_id: String = \"\")"), "札册直达行动: FacilityController 支持行动焦点参数")

	var investigation_file := FileAccess.open("res://scripts/controllers/InvestigationController.gd", FileAccess.READ)
	var investigation_text := investigation_file.get_as_text() if investigation_file != null else ""
	_assert_true(investigation_text.contains("func setup_investigation(scene_data: Dictionary, scene_id: String, focus_action_id: String = \"\")"), "札册直达行动: InvestigationController 支持行动焦点参数")
	_assert_true(investigation_text.contains("_focus_action_id"), "札册直达行动: InvestigationController 保存行动焦点")

	var investigation_controller = _load_script_or_fail("res://scripts/controllers/InvestigationController.gd", "InvestigationController 脚本可加载")
	if investigation_controller == null:
		print("")
		return
	var ctrl = investigation_controller.new()
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
	ctrl.bind_ui(
		scene_title, body_text,
		interactive_container, interactive_label,
		choices_container, choices_label,
		city_nav_panel, city_nav_label, city_nav_flow,
		content_root
	)
	ctrl.call("setup_investigation", {
		"id": "test_focus_scene",
		"title": "测试设施",
		"body": "",
		"investigations": [
			{"label": "普通互动", "once_flag": "normal_flag"},
			{"label": "目标互动", "once_flag": "focus_flag"}
		],
		"choices": []
	}, "test_focus_scene", "focus_flag")
	var focused_button: Button = null
	for child in interactive_container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == "focus_flag":
			focused_button = child
	_assert_true(focused_button != null, "札册直达行动: 调查设施创建目标行动按钮")
	_assert_true(focused_button != null and focused_button.get_meta("route_focus_target", false) == true, "札册直达行动: 目标行动按钮被标记高亮")
	_assert_true(focused_button != null and str(focused_button.theme_type_variation) == UITheme.BTN_SET_SAIL, "札册直达行动: 目标行动按钮使用醒目主题")
	_assert_eq(focused_button.name if focused_button != null else "", "InvestigationAction_focus_flag", "札册直达行动: 目标行动按钮有稳定节点名")
	ctrl.free()
	scene_title.free()
	body_text.free()
	interactive_container.free()
	interactive_label.free()
	choices_container.free()
	choices_label.free()
	city_nav_panel.free()
	city_nav_label.free()
	city_nav_flow.free()
	content_root.free()

	print("")

# ── 太阁式札册直达行动引导脉冲测试 ───────────────────────

func _test_storybook_route_action_focus_guidance() -> void:
	print("[Storybook Route Action Guidance]")

	var investigation_file := FileAccess.open("res://scripts/controllers/InvestigationController.gd", FileAccess.READ)
	var investigation_text := investigation_file.get_as_text() if investigation_file != null else ""
	_assert_true(investigation_text.contains("ROUTE_FOCUS_PULSE_COUNT"), "札册直达行动引导: 定义脉冲次数常量")
	_assert_true(investigation_text.contains("_start_route_focus_pulse"), "札册直达行动引导: 有启动脉冲函数")
	_assert_true(investigation_text.contains("_ensure_route_focus_action_visible"), "札册直达行动引导: 有确保目标行动可见函数")
	_assert_true(investigation_text.contains("ensure_control_visible"), "札册直达行动引导: ScrollContainer 场景会自动滚动到目标行动")

	var investigation_controller = _load_script_or_fail("res://scripts/controllers/InvestigationController.gd", "InvestigationController 脚本可加载")
	if investigation_controller == null:
		print("")
		return
	var ctrl = investigation_controller.new()
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
	ctrl.bind_ui(
		scene_title, body_text,
		interactive_container, interactive_label,
		choices_container, choices_label,
		city_nav_panel, city_nav_label, city_nav_flow,
		content_root
	)
	ctrl.call("setup_investigation", {
		"id": "test_guidance_scene",
		"title": "测试引导设施",
		"body": "",
		"investigations": [
			{"label": "普通互动一", "once_flag": "normal_flag_1"},
			{"label": "普通互动二", "once_flag": "normal_flag_2"},
			{"label": "目标互动", "once_flag": "focus_flag"}
		],
		"choices": []
	}, "test_guidance_scene", "focus_flag")

	var focused_button: Button = null
	var normal_button: Button = null
	for child in interactive_container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == "focus_flag":
			focused_button = child
		elif child is Button and str(child.get_meta("action_id", "")) == "normal_flag_1":
			normal_button = child
	_assert_true(focused_button != null, "札册直达行动引导: 找到目标行动按钮")
	_assert_true(focused_button != null and focused_button.get_meta("route_focus_pulse_pending", false) == true, "札册直达行动引导: 目标按钮标记待播放脉冲")
	_assert_true(focused_button != null and focused_button.get_meta("route_focus_scroll_target", false) == true, "札册直达行动引导: 目标按钮标记为滚动定位目标")
	_assert_eq(str(interactive_container.get_meta("route_focus_target_node_name", "")), "InvestigationAction_focus_flag", "札册直达行动引导: 容器记录目标按钮节点名")
	_assert_eq(str(interactive_container.get_meta("route_focus_target_action_id", "")), "focus_flag", "札册直达行动引导: 容器记录目标行动 id")
	_assert_true(normal_button != null and normal_button.get_meta("route_focus_pulse_pending", false) != true, "札册直达行动引导: 非目标按钮不播放脉冲")

	ctrl.free()
	scene_title.free()
	body_text.free()
	interactive_container.free()
	interactive_label.free()
	choices_container.free()
	choices_label.free()
	city_nav_panel.free()
	city_nav_label.free()
	city_nav_flow.free()
	content_root.free()

	print("")

# ── 太阁式札册已完成直达行动状态测试 ─────────────────────

func _test_storybook_completed_route_action_state() -> void:
	print("[Storybook Completed Route Action State]")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	if presenter == null:
		print("")
		return

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	story.grant_title("title_rookie_merchant")
	story.adjust_npc_relationship("lin_boyuan", 12)
	story.set_story_flag("zaitong_trade_route_asked")
	var model: Dictionary = presenter.build_view_model(story)
	var card_row: Dictionary = _find_row_by_id(model.get("cards", []), "card_zaitong_trade_intro")
	var title_row: Dictionary = _find_row_by_id(model.get("titles", []), "title_rookie_merchant")
	_assert_true(card_row.get("route_action_completed", false) == true, "札册已处理行动模型: 已执行 once_flag 的札直达行动标记完成")
	_assert_eq(str(card_row.get("route_action_status", "")), "已处理", "札册已处理行动模型: 已执行 once_flag 显示已处理")
	_assert_true(title_row.get("route_action_completed", true) == false, "札册已处理行动模型: 未执行 once_flag 的称号直达行动仍待处理")
	_assert_eq(str(title_row.get("route_action_status", "")), "待处理", "札册已处理行动模型: 未执行 once_flag 显示待处理")

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder == null:
		print("")
		return

	_captured_storybook_route_scene_id = ""
	_captured_storybook_route_focus_action_id = ""
	var view: Control = builder.build(story, 0, "card_zaitong_trade_intro", Callable(self, "_capture_storybook_route"))
	var cards_detail_text = view.find_child("CardsDetailText", true, false)
	var cards_route_button = view.find_child("CardsDetailRouteButton", true, false)
	_assert_true(cards_detail_text != null and str(cards_detail_text.text).contains("行动状态：已处理"), "札册已处理行动UI: 详情显示行动已处理")
	_assert_true(cards_route_button != null and cards_route_button.visible == true, "札册已处理行动UI: 已处理直达按钮仍显示状态")
	_assert_true(cards_route_button != null and cards_route_button.disabled == true, "札册已处理行动UI: 已处理直达按钮置灰")
	_assert_true(cards_route_button != null and str(cards_route_button.text).contains("已处理"), "札册已处理行动UI: 已处理直达按钮文案置为已处理")
	_assert_true(cards_route_button != null and cards_route_button.get_meta("route_action_completed", false) == true, "札册已处理行动UI: 直达按钮记录已处理 meta")
	if cards_route_button != null:
		cards_route_button.emit_signal("pressed")
	_assert_eq(_captured_storybook_route_scene_id, "", "札册已处理行动UI: 已处理按钮不会再次触发直达场景")

	var titles_route_button = view.find_child("TitlesDetailRouteButton", true, false)
	_assert_true(titles_route_button != null and titles_route_button.disabled == false, "札册已处理行动UI: 未处理称号直达按钮仍可点击")
	_assert_true(titles_route_button != null and titles_route_button.get_meta("route_action_completed", true) == false, "札册已处理行动UI: 未处理按钮记录未完成 meta")
	view.free()

	print("")


# ── 太阁式札册任务链视图测试 ─────────────────────────────

func _test_storybook_task_chain_view() -> void:
	print("[Storybook Task Chain View]")

	var presenter = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "StorybookPresenter 脚本可加载")
	if presenter == null:
		print("")
		return

	var story := StoryState.new()
	story.grant_card("card_zaitong_trade_intro")
	var model: Dictionary = presenter.build_view_model(story)
	var card_row: Dictionary = _find_row_by_id(model.get("cards", []), "card_zaitong_trade_intro")
	var task_chain: Array = card_row.get("task_chain", [])
	_assert_eq(task_chain.size(), 2, "札册任务链模型: 刺桐商路札含前置+后续两步")
	if task_chain.size() >= 2:
		var pre_step: Dictionary = task_chain[0]
		var next_step: Dictionary = task_chain[1]
		_assert_eq(str(pre_step.get("id", "")), "acquire_card_zaitong_trade_intro", "札册任务链模型: 前置步骤 id 来自 story_tables 配置")
		_assert_eq(str(pre_step.get("source_event", "")), "ev_quanzhou_tavern_trade_card", "札册任务链模型: 前置步骤保留配置来源事件")
		_assert_eq(str(pre_step.get("phase", "")), "前置", "札册任务链模型: 第一步标为前置行动")
		_assert_true(pre_step.get("completed", false) == true, "札册任务链模型: 已获札前置行动完成")
		_assert_eq(str(next_step.get("completed_by", "")), "story_flag", "札册任务链模型: 后续步骤记录配置完成条件")
		_assert_eq(str(next_step.get("phase", "")), "后续", "札册任务链模型: 第二步标为后续行动")
		_assert_true(str(next_step.get("label", "")).contains("打听刺桐商路"), "札册任务链模型: 后续行动显示可读行动名")
		_assert_true(next_step.get("completed", true) == false, "札册任务链模型: 未执行 once_flag 的后续行动待处理")
	_assert_eq(int(card_row.get("task_progress_done", -1)), 1, "札册任务链模型: 已完成 1 步")
	_assert_eq(int(card_row.get("task_progress_total", -1)), 2, "札册任务链模型: 总计 2 步")
	_assert_eq(str(card_row.get("task_progress_text", "")), "1/2", "札册任务链模型: 进度文本 1/2")
	_assert_true(str(card_row.get("next_recommendation", "")).contains("打听刺桐商路"), "札册任务链模型: 下一步推荐后续行动")

	var title_story := StoryState.new()
	title_story.grant_title("title_rookie_merchant")
	var title_model: Dictionary = presenter.build_view_model(title_story)
	var title_row: Dictionary = _find_row_by_id(title_model.get("titles", []), "title_rookie_merchant")
	var title_chain: Array = title_row.get("task_chain", [])
	_assert_eq(title_chain.size(), 2, "札册任务链模型: 称号任务链由配置生成两步")
	if title_chain.size() >= 2:
		_assert_eq(str(title_chain[0].get("id", "")), "acquire_title_rookie_merchant", "札册任务链模型: 称号前置步骤 id 来自配置")
		_assert_eq(str(title_chain[1].get("id", "")), "rookie_merchant_yamen_recognized", "札册任务链模型: 称号后续步骤 id 来自配置")
	_assert_eq(str(title_row.get("task_progress_text", "")), "1/2", "札册任务链模型: 称号进度 1/2")

	var low_rel_story := StoryState.new()
	low_rel_story.adjust_npc_relationship("lin_boyuan", 9)
	var low_rel_model: Dictionary = presenter.build_view_model(low_rel_story)
	var low_rel_row: Dictionary = _find_row_by_id(low_rel_model.get("relationships", []), "lin_boyuan")
	var low_rel_chain: Array = low_rel_row.get("task_chain", [])
	_assert_eq(low_rel_chain.size(), 2, "札册任务链模型: 人物关系任务链由配置生成两步")
	if low_rel_chain.size() >= 2:
		_assert_eq(str(low_rel_chain[0].get("id", "")), "relationship_lin_boyuan_10", "札册任务链模型: 关系前置步骤 id 来自配置")
		_assert_eq(str(low_rel_chain[0].get("completed_by", "")), "relationship_min", "札册任务链模型: 关系前置步骤记录配置完成条件")
		_assert_true(low_rel_chain[0].get("completed", true) == false, "札册任务链模型: 关系9未完成赏识前置步骤")

	var rel_story := StoryState.new()
	rel_story.adjust_npc_relationship("lin_boyuan", 12)
	var rel_model: Dictionary = presenter.build_view_model(rel_story)
	var rel_row: Dictionary = _find_row_by_id(rel_model.get("relationships", []), "lin_boyuan")
	var rel_chain: Array = rel_row.get("task_chain", [])
	if rel_chain.size() >= 2:
		_assert_true(rel_chain[0].get("completed", false) == true, "札册任务链模型: 关系12完成赏识前置步骤")
		_assert_eq(str(rel_chain[1].get("id", "")), "lin_boyuan_customs_deep_hint", "札册任务链模型: 关系后续步骤 id 来自配置")
	_assert_eq(str(rel_row.get("task_progress_text", "")), "1/2", "札册任务链模型: 关系进度 1/2")

	var builder = _load_script_or_fail(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "StorybookViewBuilder 脚本可加载")
	if builder == null:
		print("")
		return
	var view: Control = builder.build(story, 0, "card_zaitong_trade_intro")
	var detail_text = view.find_child("CardsDetailText", true, false)
	_assert_true(detail_text != null and str(detail_text.text).contains("任务链：1/2"), "札册任务链UI: 详情显示任务链进度")
	_assert_true(detail_text != null and str(detail_text.text).contains("前置行动：获得刺桐商路札（已完成）"), "札册任务链UI: 详情显示前置行动状态")
	_assert_true(detail_text != null and str(detail_text.text).contains("后续行动：打听刺桐商路（待处理）"), "札册任务链UI: 详情显示后续行动状态")
	_assert_true(detail_text != null and str(detail_text.text).contains("下一步推荐：打听刺桐商路"), "札册任务链UI: 详情显示下一步推荐")
	var card_node = view.find_child("Card_card_zaitong_trade_intro", true, false)
	var progress_label = card_node.find_child("ItemTaskProgress", true, false) if card_node != null else null
	_assert_true(progress_label != null and str(progress_label.text).contains("任务链：1/2"), "札册任务链UI: 卡片显示任务链摘要")
	var steps_list = view.find_child("CardsTaskSteps", true, false)
	_assert_true(steps_list is VBoxContainer, "札册任务链UI: 详情显示可交互步骤列表")
	var steps_title = steps_list.find_child("TaskStepsTitle", true, false) if steps_list != null else null
	_assert_true(steps_title != null and str(steps_title.text).contains("1/2") and str(steps_title.text).contains("下一步：打听刺桐商路"), "札册任务链UI: 步骤列表标题显示进度与下一步")
	var pre_step_button = view.find_child("TaskStep_acquire_card_zaitong_trade_intro", true, false)
	var next_step_button = view.find_child("TaskStep_zaitong_trade_route_asked", true, false)
	_assert_true(pre_step_button is Button and pre_step_button.mouse_filter == Control.MOUSE_FILTER_STOP, "札册任务链UI: 已完成前置步骤是可点击节点")
	_assert_true(pre_step_button != null and str(pre_step_button.text).contains("已完成") and str(pre_step_button.text).contains("获得刺桐商路札"), "札册任务链UI: 前置步骤按钮显示状态与名称")
	_assert_true(next_step_button is Button and next_step_button.disabled == false, "札册任务链UI: 未完成后续步骤可点击直达")
	_assert_eq(str(next_step_button.get_meta("scene_id", "")) if next_step_button != null else "", "city_tavern", "札册任务链UI: 后续步骤记录直达场景")
	_assert_eq(str(next_step_button.get_meta("focus_action_id", "")) if next_step_button != null else "", "zaitong_trade_route_asked", "札册任务链UI: 后续步骤记录目标行动")

	_captured_storybook_route_scene_id = ""
	_captured_storybook_route_focus_action_id = ""
	view.free()
	view = builder.build(story, 0, "card_zaitong_trade_intro", Callable(self, "_capture_storybook_route"))
	next_step_button = view.find_child("TaskStep_zaitong_trade_route_asked", true, false)
	if next_step_button != null:
		next_step_button.emit_signal("pressed")
	_assert_eq(_captured_storybook_route_scene_id, "city_tavern", "札册任务链UI: 点击未完成后续步骤直达场景")
	_assert_eq(_captured_storybook_route_focus_action_id, "zaitong_trade_route_asked", "札册任务链UI: 点击未完成后续步骤聚焦行动")

	var review_text = view.find_child("CardsDetailText", true, false)
	pre_step_button = view.find_child("TaskStep_acquire_card_zaitong_trade_intro", true, false)
	if pre_step_button != null:
		pre_step_button.emit_signal("pressed")
	_assert_true(review_text != null and str(review_text.text).contains("任务回顾") and str(review_text.text).contains("ev_quanzhou_tavern_trade_card"), "札册任务链UI: 点击已完成步骤显示来源回顾")
	view.free()

	_captured_storybook_route_scene_id = ""
	_captured_storybook_route_focus_action_id = ""
	view = builder.build(title_story, 1, "title_rookie_merchant", Callable(self, "_capture_storybook_route"))
	var title_steps_list = view.find_child("TitlesTaskSteps", true, false)
	_assert_true(title_steps_list is VBoxContainer, "札册任务链UI: 称号页显示可交互步骤列表")
	var title_steps_title = title_steps_list.find_child("TaskStepsTitle", true, false) if title_steps_list != null else null
	_assert_true(title_steps_title != null and str(title_steps_title.text).contains("1/2") and str(title_steps_title.text).contains("下一步：以海商称号递话"), "札册任务链UI: 称号步骤列表标题显示进度与下一步")
	var title_pre_step_button = view.find_child("TaskStep_acquire_title_rookie_merchant", true, false)
	var title_next_step_button = view.find_child("TaskStep_rookie_merchant_yamen_recognized", true, false)
	_assert_true(title_pre_step_button is Button and title_pre_step_button.mouse_filter == Control.MOUSE_FILTER_STOP, "札册任务链UI: 称号已完成前置步骤是可点击节点")
	_assert_true(title_pre_step_button != null and str(title_pre_step_button.text).contains("已完成") and str(title_pre_step_button.text).contains("获得初露锋芒的海商"), "札册任务链UI: 称号前置步骤按钮显示状态与名称")
	_assert_true(title_next_step_button is Button and title_next_step_button.disabled == false, "札册任务链UI: 称号未完成后续步骤可点击直达")
	_assert_eq(str(title_next_step_button.get_meta("scene_id", "")) if title_next_step_button != null else "", "city_yamen", "札册任务链UI: 称号后续步骤记录直达场景")
	_assert_eq(str(title_next_step_button.get_meta("focus_action_id", "")) if title_next_step_button != null else "", "rookie_merchant_yamen_recognized", "札册任务链UI: 称号后续步骤记录目标行动")
	if title_next_step_button != null:
		title_next_step_button.emit_signal("pressed")
	_assert_eq(_captured_storybook_route_scene_id, "city_yamen", "札册任务链UI: 点击称号未完成后续步骤直达场景")
	_assert_eq(_captured_storybook_route_focus_action_id, "rookie_merchant_yamen_recognized", "札册任务链UI: 点击称号未完成后续步骤聚焦行动")
	var title_review_text = view.find_child("TitlesDetailText", true, false)
	if title_pre_step_button != null:
		title_pre_step_button.emit_signal("pressed")
	_assert_true(title_review_text != null and str(title_review_text.text).contains("任务回顾") and str(title_review_text.text).contains("ev_rookie_merchant_title"), "札册任务链UI: 点击称号已完成步骤显示来源回顾")
	view.free()

	_captured_storybook_route_scene_id = ""
	_captured_storybook_route_focus_action_id = ""
	view = builder.build(rel_story, 2, "lin_boyuan", Callable(self, "_capture_storybook_route"))
	var rel_steps_list = view.find_child("RelationshipsTaskSteps", true, false)
	_assert_true(rel_steps_list is VBoxContainer, "札册任务链UI: 人物关系页显示可交互步骤列表")
	var rel_steps_title = rel_steps_list.find_child("TaskStepsTitle", true, false) if rel_steps_list != null else null
	_assert_true(rel_steps_title != null and str(rel_steps_title.text).contains("1/2") and str(rel_steps_title.text).contains("下一步：借林伯渊关系追问市舶司"), "札册任务链UI: 关系步骤列表标题显示进度与下一步")
	var rel_pre_step_button = view.find_child("TaskStep_relationship_lin_boyuan_10", true, false)
	var rel_next_step_button = view.find_child("TaskStep_lin_boyuan_customs_deep_hint", true, false)
	_assert_true(rel_pre_step_button is Button and rel_pre_step_button.mouse_filter == Control.MOUSE_FILTER_STOP, "札册任务链UI: 关系已完成前置步骤是可点击节点")
	_assert_true(rel_pre_step_button != null and str(rel_pre_step_button.text).contains("已完成") and str(rel_pre_step_button.text).contains("关系达到赏识"), "札册任务链UI: 关系前置步骤按钮显示状态与名称")
	_assert_true(rel_next_step_button is Button and rel_next_step_button.disabled == false, "札册任务链UI: 关系未完成后续步骤可点击直达")
	_assert_eq(str(rel_next_step_button.get_meta("scene_id", "")) if rel_next_step_button != null else "", "city_guild", "札册任务链UI: 关系后续步骤记录直达场景")
	_assert_eq(str(rel_next_step_button.get_meta("focus_action_id", "")) if rel_next_step_button != null else "", "lin_boyuan_customs_deep_hint", "札册任务链UI: 关系后续步骤记录目标行动")
	if rel_next_step_button != null:
		rel_next_step_button.emit_signal("pressed")
	_assert_eq(_captured_storybook_route_scene_id, "city_guild", "札册任务链UI: 点击关系未完成后续步骤直达场景")
	_assert_eq(_captured_storybook_route_focus_action_id, "lin_boyuan_customs_deep_hint", "札册任务链UI: 点击关系未完成后续步骤聚焦行动")
	var rel_review_text = view.find_child("RelationshipsDetailText", true, false)
	if rel_pre_step_button != null:
		rel_pre_step_button.emit_signal("pressed")
	_assert_true(rel_review_text != null and str(rel_review_text.text).contains("任务回顾") and str(rel_review_text.text).contains("ev_quanzhou_tavern_trade_card"), "札册任务链UI: 点击关系已完成步骤显示来源回顾")
	view.free()

	story.set_story_flag("zaitong_trade_route_asked")
	var completed_model: Dictionary = presenter.build_view_model(story)
	var completed_card: Dictionary = _find_row_by_id(completed_model.get("cards", []), "card_zaitong_trade_intro")
	_assert_eq(str(completed_card.get("task_progress_text", "")), "2/2", "札册任务链模型: 完成后进度 2/2")
	_assert_eq(str(completed_card.get("next_recommendation", "")), "已完成全部链路", "札册任务链模型: 完成后推荐收束")
	view = builder.build(story, 0, "card_zaitong_trade_intro")
	var completed_steps_list = view.find_child("CardsTaskSteps", true, false)
	var completed_steps_title = completed_steps_list.find_child("TaskStepsTitle", true, false) if completed_steps_list != null else null
	_assert_true(completed_steps_title != null and str(completed_steps_title.text).contains("2/2") and str(completed_steps_title.text).contains("已完成全部链路"), "札册任务链UI: 完成后步骤列表标题显示完成状态")
	view.free()

	print("")

func _has_story_table_grant(grants: Array, section: String, entry_id: String) -> bool:
	for raw_grant in grants:
		if not raw_grant is Dictionary:
			continue
		var grant: Dictionary = raw_grant
		if str(grant.get("section", "")) == section and str(grant.get("id", "")) == entry_id:
			return true
	return false


func _find_story_table_action_by_id(actions: Array, action_id: String) -> Dictionary:
	for raw_action in actions:
		if raw_action is Dictionary and str(raw_action.get("id", "")) == action_id:
			return raw_action
	return {}

func _find_investigation_by_label(scene_data: Dictionary, label_part: String) -> Dictionary:
	for raw in scene_data.get("investigations", []):
		if raw is Dictionary and str(raw.get("label", "")).contains(label_part):
			return raw
	return {}

func _find_row_by_id(rows: Array, row_id: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and str(raw.get("id", "")) == row_id:
			return raw
	return {}

# ── 太阁式事件内核 MVP 测试 ───────────────────────────────

class KernelFakeStory:
	var story_flags: Dictionary = {}
	var story_items: Dictionary = {}
	var cards: Dictionary = {}
	var titles: Dictionary = {}
	var npc_relationships: Dictionary = {}

	func get_npc_affinity(npc_id: String) -> int:
		return int(story_flags.get("npc_affinity_" + npc_id, 0))

	func adjust_npc_affinity(npc_id: String, delta: int) -> void:
		story_flags["npc_affinity_" + npc_id] = get_npc_affinity(npc_id) + delta

	func unlock_chapter(chapter_id: String) -> void:
		story_flags["chapter_unlock:" + chapter_id] = true

	func remove_item(item_id: String) -> void:
		story_items.erase(item_id)

class KernelFakeState:
	var fame: int = 0
	var money: int = 0
	var pu_attention: int = 0
	var story := KernelFakeStory.new()
	var flags: Dictionary = {}
	var market = null
	var game_log = null

	func has_story_flag(key: String) -> bool:
		return story.story_flags.has(key) and story.story_flags[key] == true

	func set_story_flag(key: String, value = true) -> void:
		story.story_flags[key] = value

	func has_flag(key: String) -> bool:
		return flags.has(key) and flags[key] == true

	func set_flag(key: String) -> void:
		flags[key] = true

	func clear_flag(key: String) -> void:
		flags.erase(key)

	func has_item_flag(item_id: String) -> bool:
		return story.story_items.has(item_id) and story.story_items[item_id] == true

	func acquire_item(item_id: String) -> void:
		story.story_items[item_id] = true

	func has_card(card_id: String) -> bool:
		return story.cards.has(card_id) and story.cards[card_id] == true

	func grant_card(card_id: String) -> void:
		story.cards[card_id] = true

	func has_title(title_id: String) -> bool:
		return story.titles.has(title_id) and story.titles[title_id] == true

	func grant_title(title_id: String) -> void:
		story.titles[title_id] = true

	func get_npc_relationship(npc_id: String) -> int:
		return int(story.npc_relationships.get(npc_id, 0))

	func adjust_npc_relationship(npc_id: String, delta: int) -> void:
		story.npc_relationships[npc_id] = get_npc_relationship(npc_id) + delta

	func apply_effects(effects: Dictionary) -> void:
		if effects.has("fame"):
			fame += int(effects["fame"])
		if effects.has("money"):
			money += int(effects["money"])
		if effects.has("npc_affinity"):
			var payload: Dictionary = effects["npc_affinity"]
			story.adjust_npc_affinity(str(payload.get("npc_id", "")), int(payload.get("delta", 0)))
		if effects.has("npc_relationship"):
			var payload: Dictionary = effects["npc_relationship"]
			adjust_npc_relationship(str(payload.get("npc_id", "")), int(payload.get("delta", 0)))
		if effects.has("chapter_unlock"):
			story.unlock_chapter(str(effects["chapter_unlock"]))

func _test_event_kernel_mvp() -> void:
	print("[Event Kernel MVP]")

	var data_gs := KernelFakeState.new()
	data_gs.set_story_flag("chapter1_complete", true)
	_story_event_chain_engine().reload()
	var data_fired: Array = _story_event_chain_engine().check_triggers("enter_facility", {
		"port_id": "quanzhou",
		"facility_id": "city_tavern",
		"scene_id": "city_tavern",
		"game_state": data_gs,
	})
	_assert_true("ev_quanzhou_tavern_trade_card" in data_fired, "真实 JSON: 泉州酒馆设施事件可触发")
	_assert_true(data_gs.has_card("card_zaitong_trade_intro"), "真实 JSON: 设施事件自动授予刺桐商路札")
	_assert_eq(data_gs.get_npc_relationship("lin_boyuan"), 3, "真实 JSON: 设施事件调整林伯渊关系")
	var real_title_chain: Dictionary = _story_event_chain_engine().get_chain("ev_rookie_merchant_title")
	var real_title_has_direct_grant := false
	for raw_effect in real_title_chain.get("effects", []):
		if raw_effect is Dictionary and str(raw_effect.get("type", "")) == "grant_title":
			real_title_has_direct_grant = true
	_assert_true(not real_title_has_direct_grant, "真实 JSON: 初露锋芒称号不再由事件链直接 grant_title")
	var real_title_fired: Array = _story_event_chain_engine().check_triggers("trade_completed", {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": data_gs,
	})
	_assert_true("ev_rookie_merchant_title" in real_title_fired, "真实 JSON: 首笔商路交易称号事件可触发")
	_assert_true(data_gs.has_title("title_rookie_merchant"), "真实 JSON: trade_completed 自动授予初露锋芒称号")

	var gs := KernelFakeState.new()

	var old_loaded = _story_event_chain_engine()._loaded
	var old_chains: Dictionary = _story_event_chain_engine()._chains.duplicate(true)
	var old_fame: int = gs.fame
	var story = gs.story
	story.story_flags.erase("test_trade_kernel_fired")
	story.story_flags.erase("test_trade_kernel_once")

	_story_event_chain_engine()._loaded = true
	_story_event_chain_engine()._chains = {
		"test_trade_kernel": {
			"trigger_on": ["trade_completed"],
			"once": true,
			"trigger_flag": "test_trade_kernel_once",
			"conditions": {
				"port_id": "quanzhou",
				"trade_action": "sell",
				"good_id": "fujian_porcelain",
				"amount_min": 3,
			},
			"effects": [
				{"type": "set_story_flag", "key": "test_trade_kernel_fired"},
				{"type": "apply_effects", "effects": {"fame": 2, "money": 100}},
				{"type": "npc_relationship", "npc_id": "lin_boyuan", "delta": 2},
				{"type": "port_affinity", "port_id": "quanzhou", "delta": 1.0},
			],
		},
	}

	var wrong_ctx := {
		"port_id": "quanzhou",
		"trade_action": "buy",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": gs,
	}
	var wrong_fired: Array = _story_event_chain_engine().check_triggers("trade_completed", wrong_ctx)
	_assert_eq(wrong_fired.size(), 0, "trade_completed: trade_action 不匹配时不触发")
	_assert_true(not gs.has_story_flag("test_trade_kernel_fired"), "未触发时不写入 story flag")

	var ok_ctx := {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": gs,
	}
	var ok_fired: Array = _story_event_chain_engine().check_triggers("trade_completed", ok_ctx)
	_assert_eq(ok_fired, ["test_trade_kernel"], "trade_completed: 条件匹配时触发指定事件")
	_assert_true(gs.has_story_flag("test_trade_kernel_fired"), "事件 effect 写入 story flag")
	_assert_eq(gs.fame, old_fame + 2, "apply_effects effect 能委托状态 apply_effects")
	_assert_eq(gs.money, 100, "apply_effects effect 能结算 money")
	_assert_eq(gs.get_npc_relationship("lin_boyuan"), 2, "npc_relationship effect 能结算基础关系")

	var dup_fired: Array = _story_event_chain_engine().check_triggers("trade_completed", ok_ctx)
	_assert_eq(dup_fired.size(), 0, "once=true 的事件不会重复触发")
	_assert_eq(gs.fame, old_fame + 2, "once=true 防止 effect 重复结算")

	var bonus_gs := KernelFakeState.new()
	bonus_gs.grant_card("card_zaitong_trade_intro")
	bonus_gs.grant_title("title_rookie_merchant")
	bonus_gs.adjust_npc_relationship("lin_boyuan", 10)
	bonus_gs.market = MarketState.new()
	var bonus_logs: Array[String] = []
	var bonus_log_callback := func(msg: String) -> void:
		bonus_logs.append(msg)
	var bonus_ctx := {
		"port_id": "quanzhou",
		"trade_action": "sell",
		"good_id": "fujian_porcelain",
		"amount": 3,
		"game_state": bonus_gs,
		"message_callback": bonus_log_callback,
	}
	var bonus_fired: Array = _story_event_chain_engine().check_triggers("trade_completed", bonus_ctx)
	_assert_eq(bonus_fired, ["test_trade_kernel"], "trade_completed: 有札时仍触发指定事件")
	_assert_eq(bonus_gs.fame, 3, "札数值效果: trade_completed 名声结算获得 +1 加成")
	_assert_eq(bonus_gs.money, 150, "札数值效果: trade_completed 银两结算获得 +50 加成")
	_assert_eq(bonus_gs.get_npc_relationship("lin_boyuan"), 13, "札数值效果: trade_completed 人物关系结算获得 +1 加成")
	_assert_eq(bonus_gs.market.get_affinity("quanzhou"), 1.5, "札数值效果: trade_completed 港口好感结算获得 +0.5 加成")
	var bonus_log_text := "\n".join(bonus_logs)
	_assert_true(bonus_log_text.contains("札效生效"), "札效反馈: trade_completed 输出札效生效提示")
	_assert_true(bonus_log_text.contains("名声额外+1"), "札效反馈: 明细包含名声加成来源")
	_assert_true(bonus_log_text.contains("银两额外+50"), "札效反馈: 明细包含银两加成来源")
	_assert_true(bonus_log_text.contains("林伯渊关系额外+1"), "札效反馈: 明细包含人物关系加成来源")
	_assert_true(bonus_log_text.contains("港口好感额外+0.5"), "札效反馈: 明细包含港口好感加成来源")

	var nav := NavigationState.new()
	nav.world_day = 30
	nav.world_month = 2
	var saved_nav := nav.to_dict()
	var restored_nav := NavigationState.new()
	restored_nav.from_dict(saved_nav)
	_assert_eq(restored_nav.world_day, 30, "NavigationState: world_day 存档往返")
	_assert_eq(restored_nav.world_month, 2, "NavigationState: world_month 存档往返")

	gs.story.npc_relationships.erase("lin_boyuan")
	_story_event_chain_engine()._chains = {
		"test_facility_kernel": {
			"trigger_on": "enter_facility",
			"once": true,
			"trigger_flag": "test_facility_kernel_once",
			"conditions": {
				"port_id": "quanzhou",
				"facility_id": "city_tavern",
				"cards_absent": ["card_zaitong_trade_intro"],
				"titles_absent": ["title_rookie_merchant"],
			},
			"effects": [
				{"type": "grant_card", "card_id": "card_zaitong_trade_intro"},
				{"type": "grant_title", "title_id": "title_rookie_merchant"},
				{"type": "npc_relationship", "npc_id": "lin_boyuan", "delta": 4},
			],
		},
	}
	var facility_ctx := {
		"port_id": "quanzhou",
		"facility_id": "city_tavern",
		"game_state": gs,
	}
	var facility_fired: Array = _story_event_chain_engine().check_triggers("enter_facility", facility_ctx)
	_assert_eq(facility_fired, ["test_facility_kernel"], "enter_facility: 设施条件匹配时触发")
	_assert_true(gs.has_card("card_zaitong_trade_intro"), "grant_card effect 能授予札")
	_assert_true(gs.has_title("title_rookie_merchant"), "grant_title effect 能授予称号")
	_assert_eq(gs.get_npc_relationship("lin_boyuan"), 4, "npc_relationship effect 能调整人物关系")

	var card_gated := ConditionEvaluator.matches({
		"cards_required": ["card_zaitong_trade_intro"],
		"titles_required": ["title_rookie_merchant"],
		"relationship_npc_id": "lin_boyuan",
		"npc_relationship_min": 4,
	}, {"game_state": gs})
	_assert_true(card_gated, "ConditionEvaluator: 札/称号/人物关系条件可匹配")

	gs.fame = old_fame
	story.story_flags.erase("test_trade_kernel_fired")
	story.story_flags.erase("test_trade_kernel_once")
	story.story_flags.erase("test_facility_kernel_once")
	_story_event_chain_engine()._chains = old_chains
	_story_event_chain_engine()._loaded = old_loaded

	print("")
