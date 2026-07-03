extends RefCounted

var _runner = null

func _init(runner = null) -> void:
	_runner = runner

func run_ui_theme_constants() -> void:
	_test_ui_theme_constants()

func run_resource_paths() -> void:
	_test_resource_paths()

func run_ui_builder() -> void:
	_test_ui_builder()

func run_game_colors() -> void:
	_test_game_colors()

func run_floating_text_config() -> void:
	_test_floating_text_config()

func run_map_visual_style() -> void:
	_test_map_visual_style()

func _assert_true(condition: bool, msg: String) -> void:
	_runner._assert_true(condition, msg)

func _assert_eq(actual, expected, msg: String) -> void:
	_runner._assert_eq(actual, expected, msg)

func _assert_not_null(value, msg: String) -> void:
	_runner._assert_not_null(value, msg)

# ── NK1-P6-POLISH-002: UITheme 常量类测试 ─────────────────

func _test_ui_theme_constants() -> void:
	print("[UITheme Constants]")

	# 按钮常量
	_assert_eq(UITheme.BTN_ACTION, "ActionButton", "UITheme.BTN_ACTION")
	_assert_eq(UITheme.BTN_CHOICE, "ChoiceButton", "UITheme.BTN_CHOICE")
	_assert_eq(UITheme.BTN_SET_SAIL, "SetSailButton", "UITheme.BTN_SET_SAIL")
	_assert_eq(UITheme.BTN_TITLE_MENU, "TitleMenuButton", "UITheme.BTN_TITLE_MENU")
	_assert_eq(UITheme.BTN_NPC, "NPCButton", "UITheme.BTN_NPC")

	# 市集常量
	_assert_eq(UITheme.MARKET_SHELL, "MarketShell", "UITheme.MARKET_SHELL")
	_assert_eq(UITheme.MARKET_TITLE, "MarketTitle", "UITheme.MARKET_TITLE")
	_assert_eq(UITheme.MARKET_ALERT, "MarketAlert", "UITheme.MARKET_ALERT")
	_assert_eq(UITheme.MARKET_PANEL, "MarketPanel", "UITheme.MARKET_PANEL")
	_assert_eq(UITheme.MARKET_PREVIEW, "MarketPreview", "UITheme.MARKET_PREVIEW")

	# 设施卡片常量
	_assert_eq(UITheme.CARD_FACILITY, "PortFacilityCard", "UITheme.CARD_FACILITY")
	_assert_eq(UITheme.CARD_FACILITY_QUEST, "PortFacilityCardQuest", "UITheme.CARD_FACILITY_QUEST")
	_assert_eq(UITheme.TITLE_FACILITY, "FacilityTitle", "UITheme.TITLE_FACILITY")
	_assert_eq(UITheme.SUBTITLE_FACILITY, "FacilitySubtitle", "UITheme.SUBTITLE_FACILITY")

	# 事件/对话常量
	_assert_eq(UITheme.TITLE_EVENT, "EventTitle", "UITheme.TITLE_EVENT")
	_assert_eq(UITheme.BODY_EVENT, "EventBody", "UITheme.BODY_EVENT")
	_assert_eq(UITheme.PANEL_DIALOGUE_INNER, "DialoguePanelInner", "UITheme.PANEL_DIALOGUE_INNER")
	_assert_eq(UITheme.TEXT_DIALOGUE_NARRATION, "DialogueNarrationText", "UITheme.TEXT_DIALOGUE_NARRATION")
	_assert_eq(UITheme.TEXT_DIALOGUE_SPEECH, "DialogueSpeechText", "UITheme.TEXT_DIALOGUE_SPEECH")

	# assert_all_known 验证
	_assert_true(UITheme.assert_all_known("ActionButton"), "assert_all_known: ActionButton")
	_assert_true(UITheme.assert_all_known("SetSailButton"), "assert_all_known: SetSailButton")
	_assert_true(not UITheme.assert_all_known("FakeTheme"), "assert_all_known: FakeTheme 不存在")
	_assert_true(not UITheme.assert_all_known(""), "assert_all_known: 空字符串不存在")

	# 总数验证（28 个唯一常量）
	var known_count := 0
	var all_themes := [
		UITheme.BTN_ACTION, UITheme.BTN_CHOICE, UITheme.BTN_SET_SAIL, UITheme.BTN_TITLE_MENU, UITheme.BTN_NPC,
		UITheme.MARKET_SHELL, UITheme.MARKET_TITLE, UITheme.MARKET_ALERT, UITheme.MARKET_PANEL, UITheme.MARKET_PREVIEW,
		UITheme.CARD_FACILITY, UITheme.CARD_FACILITY_QUEST, UITheme.TITLE_FACILITY, UITheme.SUBTITLE_FACILITY,
		UITheme.BTN_FACILITY_CARD, UITheme.BADGE_FACILITY_QUEST, UITheme.FRAME_FACILITY_ICON,
		UITheme.CHIP_PORT_STAT, UITheme.LABEL_PORT_STAT, UITheme.VALUE_PORT_STAT,
		UITheme.SECTION_LABEL, UITheme.TITLE_EVENT, UITheme.BODY_EVENT, UITheme.PANEL_DIALOGUE_INNER,
		UITheme.TEXT_DIALOGUE_NARRATION, UITheme.TEXT_DIALOGUE_SPEECH, UITheme.TEXT_TITLE_SUB,
		UITheme.LABEL_SEA_HUD_FLEET,
	]
	for t in all_themes:
		if UITheme.assert_all_known(t):
			known_count += 1
	_assert_eq(known_count, 28, "UITheme: 共 28 个唯一常量")

	print("")

# ── NK1-P6-POLISH-002: ResourcePaths 常量类测试 ─────────────

func _test_resource_paths() -> void:
	print("[ResourcePaths]")

	# 主题与样式
	_assert_eq(ResourcePaths.THEME_MAIN, "res://assets/main_theme.tres", "ResourcePaths.THEME_MAIN")
	_assert_eq(ResourcePaths.FRAME_KOEI, "res://assets/ui_frame_koei.png", "ResourcePaths.FRAME_KOEI")
	_assert_eq(ResourcePaths.GRADIENT_SHADER, "res://assets/ui_bottom_gradient.gdshader", "ResourcePaths.GRADIENT_SHADER")

	# 纹理
	_assert_eq(ResourcePaths.TEX_SHIP_TOPDOWN, "res://assets/ship_topdown.png", "ResourcePaths.TEX_SHIP_TOPDOWN")
	_assert_eq(ResourcePaths.TEX_SEAGULL, "res://assets/seagull.png", "ResourcePaths.TEX_SEAGULL")
	_assert_eq(ResourcePaths.TEX_WHALE_SHADOW, "res://assets/whale_shadow.png", "ResourcePaths.TEX_WHALE_SHADOW")
	_assert_eq(ResourcePaths.TEX_MAP_NANHAI, "res://assets/map_nanhai.png", "ResourcePaths.TEX_MAP_NANHAI")
	_assert_eq(ResourcePaths.TEX_MAP_SEA_MASK, "res://assets/map_nanhai_sea_mask.png", "ResourcePaths.TEX_MAP_SEA_MASK")
	_assert_eq(ResourcePaths.TEX_ICON_PORT, "res://assets/icons_128/icon_shipyard_koei.png", "ResourcePaths.TEX_ICON_PORT")
	_assert_eq(ResourcePaths.TEX_UI_FRAME_KOEI, "res://assets/ui_frame_koei.png", "ResourcePaths.TEX_UI_FRAME_KOEI")
	_assert_eq(ResourcePaths.TEX_OCEAN_WATER, "res://assets/ocean_water.png", "ResourcePaths.TEX_OCEAN_WATER")
	_assert_eq(ResourcePaths.SHADER_OCEAN_MASKED, "res://assets/ocean_masked_shader.gdshader", "ResourcePaths.SHADER_OCEAN_MASKED")
	_assert_eq(ResourcePaths.TEX_ICON_MARKET, "res://assets/icon_market_koei.png", "ResourcePaths.TEX_ICON_MARKET")
	_assert_eq(ResourcePaths.BG_DEFAULT, "res://assets/bg_sea_route_koei.png", "ResourcePaths.BG_DEFAULT")

	# 场景
	_assert_eq(ResourcePaths.SCENE_MAIN, "res://scenes/Main.tscn", "ResourcePaths.SCENE_MAIN")
	_assert_eq(ResourcePaths.SCENE_WORLD_MAP, "res://scenes/WorldMap.tscn", "ResourcePaths.SCENE_WORLD_MAP")
	_assert_eq(ResourcePaths.SCENE_STRATEGIC_MAP_OVERLAY, "res://scenes/StrategicMapOverlay.tscn", "ResourcePaths.SCENE_STRATEGIC_OVERLAY")
	_assert_eq(ResourcePaths.SCENE_FLOATING_TEXT, "res://scenes/FloatingText.tscn", "ResourcePaths.SCENE_FLOATING_TEXT")
	_assert_eq(ResourcePaths.SCENE_CRATE, "res://scenes/Crate.tscn", "ResourcePaths.SCENE_CRATE")
	_assert_eq(ResourcePaths.SCENE_PORT_ZONE, "res://scenes/PortZone.tscn", "ResourcePaths.SCENE_PORT_ZONE")
	_assert_eq(ResourcePaths.SCENE_MAP_FLEET, "res://scenes/MapFleetNode.tscn", "ResourcePaths.SCENE_MAP_FLEET")
	_assert_eq(ResourcePaths.SCENE_COMMAND_BAR, "res://scenes/CommandBar.tscn", "ResourcePaths.SCENE_COMMAND_BAR")
	_assert_eq(ResourcePaths.SCENE_TOWN_MAP_HOTSPOT, "res://scenes/TownMapHotspot.tscn", "ResourcePaths.SCENE_TOWN_MAP_HOTSPOT")
	_assert_eq(ResourcePaths.SCENE_PORT_STATUS_BAR, "res://scenes/PortStatusBar.tscn", "ResourcePaths.SCENE_PORT_STATUS_BAR")

	# 事件脚本
	_assert_eq(ResourcePaths.SCRIPT_PIRATE_ATTACK, "res://scripts/events/PirateAttackEvent.gd", "ResourcePaths.SCRIPT_PIRATE_ATTACK")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_DISASTER, "res://scripts/events/TradeDisasterEvent.gd", "ResourcePaths.SCRIPT_TRADE_DISASTER")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_RECOVERY, "res://scripts/events/TradeRecoveryEvent.gd", "ResourcePaths.SCRIPT_TRADE_RECOVERY")
	_assert_eq(ResourcePaths.SCRIPT_SUPPLY_SHORTAGE, "res://scripts/events/SupplyShortageEvent.gd", "ResourcePaths.SCRIPT_SUPPLY_SHORTAGE")
	_assert_eq(ResourcePaths.SCRIPT_TRADE_BOOM, "res://scripts/events/TradeBoomEvent.gd", "ResourcePaths.SCRIPT_TRADE_BOOM")
	_assert_eq(ResourcePaths.SCRIPT_ECONOMIC_RIPPLE, "res://scripts/events/EconomicRippleEvent.gd", "ResourcePaths.SCRIPT_ECONOMIC_RIPPLE")

	# Handler 脚本
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_PAYMENT, "res://scripts/systems/handlers/PaymentHandler.gd", "ResourcePaths.SCRIPT_HANDLER_PAYMENT")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_REPAIR, "res://scripts/systems/handlers/RepairHandler.gd", "ResourcePaths.SCRIPT_HANDLER_REPAIR")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES, "res://scripts/systems/handlers/BuySuppliesHandler.gd", "ResourcePaths.SCRIPT_HANDLER_BUY_SUPPLIES")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_BUY_INTEL, "res://scripts/systems/handlers/BuyIntelHandler.gd", "ResourcePaths.SCRIPT_HANDLER_BUY_INTEL")
	_assert_eq(ResourcePaths.SCRIPT_HANDLER_INVEST_PORT, "res://scripts/systems/handlers/InvestPortHandler.gd", "ResourcePaths.SCRIPT_HANDLER_INVEST_PORT")
	_assert_eq(ResourcePaths.SCRIPT_CONDITION_EVALUATOR, "res://scripts/systems/ConditionEvaluator.gd", "ResourcePaths.SCRIPT_CONDITION_EVALUATOR")
	_assert_eq(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY, "res://scripts/systems/StoryTableRegistry.gd", "ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY")
	_assert_eq(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER, "res://scripts/systems/StorybookPresenter.gd", "ResourcePaths.SCRIPT_STORYBOOK_PRESENTER")
	_assert_eq(ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER, "res://scripts/systems/StorybookViewBuilder.gd", "ResourcePaths.SCRIPT_STORYBOOK_VIEW_BUILDER")

	# 数据文件
	_assert_eq(ResourcePaths.DATA_SCENES, "res://data/scenes.json", "ResourcePaths.DATA_SCENES")
	_assert_eq(ResourcePaths.DIR_DATA_SCENES, "res://data/scenes/", "ResourcePaths.DIR_DATA_SCENES")
	_assert_eq(ResourcePaths.DATA_NPCS, "res://data/npcs.json", "ResourcePaths.DATA_NPCS")

	# 资源目录
	_assert_eq(ResourcePaths.DIR_ASSETS, "res://assets/", "ResourcePaths.DIR_ASSETS")
	_assert_eq(ResourcePaths.DIR_PORTRAITS, "res://assets/portraits/", "ResourcePaths.DIR_PORTRAITS")
	_assert_eq(ResourcePaths.DIR_ICONS_STAT, "res://assets/icons_stat/", "ResourcePaths.DIR_ICONS_STAT")

	print("")

# ── NK1-P6-POLISH-002: UIBuilder 测试 ──────────────────────

func _test_ui_builder() -> void:
	print("[UIBuilder]")

	# 按钮创建
	var btn := UIBuilder.make_action_button("测试按钮")
	_assert_true(btn is Button, "make_action_button 返回 Button")
	_assert_eq(btn.text, "测试按钮", "按钮文本正确")
	_assert_eq(btn.theme_type_variation, UITheme.BTN_ACTION, "按钮主题 = BTN_ACTION")
	_assert_eq(int(btn.custom_minimum_size.y), 52, "操作按钮高度=52")

	var choice_btn := UIBuilder.make_choice_button("选择")
	_assert_eq(choice_btn.theme_type_variation, UITheme.BTN_CHOICE, "选择按钮主题 = BTN_CHOICE")
	_assert_eq(int(choice_btn.custom_minimum_size.y), 40, "选择按钮高度=40")

	var sail_btn := UIBuilder.make_set_sail_button("升帆")
	_assert_eq(sail_btn.theme_type_variation, UITheme.BTN_SET_SAIL, "升帆按钮主题 = BTN_SET_SAIL")
	_assert_eq(int(sail_btn.custom_minimum_size.y), 60, "升帆按钮高度=60")

	# 标签创建
	var lbl := UIBuilder.make_market_preview("预览文本")
	_assert_true(lbl is Label, "make_market_preview 返回 Label")
	_assert_eq(lbl.text, "预览文本", "标签文本正确")
	_assert_eq(lbl.theme_type_variation, UITheme.MARKET_PREVIEW, "标签主题 = MARKET_PREVIEW")
	_assert_eq(lbl.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "市场预览居中对齐")

	var alert_lbl := UIBuilder.make_market_alert("告警")
	_assert_eq(alert_lbl.theme_type_variation, UITheme.MARKET_ALERT, "告警标签主题 = MARKET_ALERT")

	var title_lbl := UIBuilder.make_market_title("市集")
	_assert_eq(title_lbl.theme_type_variation, UITheme.MARKET_TITLE, "市集标题主题 = MARKET_TITLE")

	# 面板创建
	var panel := UIBuilder.make_market_panel()
	_assert_true(panel is PanelContainer, "make_market_panel 返回 PanelContainer")
	_assert_eq(panel.theme_type_variation, UITheme.MARKET_PANEL, "市集面板主题 = MARKET_PANEL")

	var shell := UIBuilder.make_market_shell()
	_assert_eq(shell.theme_type_variation, UITheme.MARKET_SHELL, "市集外壳主题 = MARKET_SHELL")

	var card := UIBuilder.make_facility_card(false)
	_assert_eq(card.theme_type_variation, UITheme.CARD_FACILITY, "普通设施卡主题")

	var quest_card := UIBuilder.make_facility_card(true)
	_assert_eq(quest_card.theme_type_variation, UITheme.CARD_FACILITY_QUEST, "任务设施卡主题")

	# 港状态栏芯片
	var chip := UIBuilder.make_port_stat_chip("铜钱", "1000")
	_assert_true(chip is PanelContainer, "make_port_stat_chip 返回 PanelContainer")
	_assert_eq(chip.theme_type_variation, UITheme.CHIP_PORT_STAT, "港状态栏芯片背景主题")
	# 芯片内部应有 2 个标签（标题+值）
	_assert_eq(chip.get_child_count(), 1, "芯片含 1 个 VBox 子节点")
	var vbox = chip.get_child(0)
	_assert_eq(vbox.get_child_count(), 2, "VBox 含 2 个标签")
	_assert_true(vbox.get_child(0) is Label, "子节点 0 是 Label（标题）")
	_assert_true(vbox.get_child(1) is Label, "子节点 1 是 Label（值）")

	# RichText 创建
	var rtl := UIBuilder.make_rich_text("富文本", UITheme.MARKET_PREVIEW, true)
	_assert_true(rtl is RichTextLabel, "make_rich_text 返回 RichTextLabel")
	_assert_true(rtl.bbcode_enabled, "BBCode 已启用")
	_assert_eq(rtl.theme_type_variation, UITheme.MARKET_PREVIEW, "富文本主题")

	# 区域标签
	var section_lbl := UIBuilder.make_section_label("区域标题")
	_assert_eq(section_lbl.theme_type_variation, UITheme.SECTION_LABEL, "区域标签主题")

	# 自定义按钮
	var custom_btn := UIBuilder.make_button("自定义", UITheme.BTN_SET_SAIL, 80)
	_assert_eq(int(custom_btn.custom_minimum_size.y), 80, "自定义高度=80")
	_assert_eq(custom_btn.theme_type_variation, UITheme.BTN_SET_SAIL, "自定义主题")

	# NPC 按钮
	var npc_btn := UIBuilder.make_npc_button("对话")
	_assert_eq(npc_btn.theme_type_variation, UITheme.BTN_NPC, "NPC 按钮主题")
	_assert_eq(int(npc_btn.custom_minimum_size.y), 48, "NPC 按钮高度=48")

	for node in [
		btn, choice_btn, sail_btn, custom_btn, npc_btn,
		lbl, alert_lbl, title_lbl, section_lbl,
		panel, shell, card, quest_card, chip, rtl,
	]:
		if node != null and is_instance_valid(node):
			node.free()

	print("")

# ── NK1-P6-POLISH-003: GameColors 常量类测试 ───────────────

func _test_game_colors() -> void:
	print("[GameColors]")

	# 警告/危险色
	_assert_eq(GameColors.WARNING, Color(1, 0.3, 0.3), "GameColors.WARNING")
	_assert_eq(GameColors.DAMAGE, Color(1, 0.28, 0.22), "GameColors.DAMAGE")
	_assert_eq(GameColors.WARNING_SOFT, Color(1.0, 0.7, 0.4), "GameColors.WARNING_SOFT")
	_assert_eq(GameColors.PIRATE_RED, Color(1.0, 0.45, 0.4), "GameColors.PIRATE_RED")
	_assert_eq(GameColors.ENEMY_BLIP, Color(1.0, 0.35, 0.35), "GameColors.ENEMY_BLIP")
	_assert_eq(GameColors.DANGER_TEXT, Color(0.95, 0.55, 0.45), "GameColors.DANGER_TEXT")

	# 成功色
	_assert_eq(GameColors.SUCCESS, Color(0.2, 1.0, 0.2), "GameColors.SUCCESS")
	_assert_eq(GameColors.PERMIT_OK, Color(0.55, 0.95, 0.7), "GameColors.PERMIT_OK")
	_assert_eq(GameColors.PRICE_CRASH, Color(0.4, 1.0, 0.4), "GameColors.PRICE_CRASH")
	_assert_eq(GameColors.PRICE_DROP, Color(0.7, 1.0, 0.7), "GameColors.PRICE_DROP")
	_assert_eq(GameColors.PORT_BLIP, Color.GREEN, "GameColors.PORT_BLIP")

	# 信息色
	_assert_eq(GameColors.INFO, Color(0.5, 0.8, 1), "GameColors.INFO")
	_assert_eq(GameColors.SCENERY, Color(0.7, 0.85, 1.0, 0.9), "GameColors.SCENERY")
	_assert_eq(GameColors.PATROL_BLUE, Color(0.55, 0.75, 1.0), "GameColors.PATROL_BLUE")
	_assert_eq(GameColors.NAVY_HUD, Color(0, 0.1, 0.2, 0.8), "GameColors.NAVY_HUD")
	_assert_eq(GameColors.RADAR_RING, Color(0.2, 0.5, 0.8), "GameColors.RADAR_RING")

	# UI 文字色
	_assert_eq(GameColors.TEXT_GOLD, Color(0.98, 0.84, 0.42, 1), "GameColors.TEXT_GOLD")
	_assert_eq(GameColors.TEXT_GOLD_BRIGHT, Color(0.98, 0.92, 0.72, 1), "GameColors.TEXT_GOLD_BRIGHT")
	_assert_eq(GameColors.TEXT_WARN, Color(1.0, 0.75, 0.4, 1), "GameColors.TEXT_WARN")
	_assert_eq(GameColors.TEXT_DIM, Color(0.62, 0.6, 0.52, 1), "GameColors.TEXT_DIM")
	_assert_eq(GameColors.TEXT_ICON_DIM, Color(0.72, 0.72, 0.72, 1), "GameColors.TEXT_ICON_DIM")
	_assert_eq(GameColors.FLEET_DEFAULT, Color(0.85, 0.85, 0.9), "GameColors.FLEET_DEFAULT")

	# 港状态栏色
	_assert_eq(GameColors.METER_NORMAL, Color(0.82, 0.62, 0.24, 1), "GameColors.METER_NORMAL")
	_assert_eq(GameColors.METER_WARN, Color(0.95, 0.72, 0.28, 1), "GameColors.METER_WARN")
	_assert_eq(GameColors.METER_DANGER, Color(0.92, 0.38, 0.32, 1), "GameColors.METER_DANGER")

	# 浮文色
	_assert_eq(GameColors.FLOATING_ECONOMY, Color(1.0, 0.9, 0.6, 0.85), "GameColors.FLOATING_ECONOMY")
	_assert_eq(GameColors.FLOATING_PORT_NEAR, Color(0.9, 1.0, 0.8, 0.95), "GameColors.FLOATING_PORT_NEAR")
	_assert_eq(GameColors.FLOATING_CREW_LOSS, Color.RED, "GameColors.FLOATING_CREW_LOSS")
	_assert_eq(GameColors.FLOATING_PICKUP, Color(0.2, 1.0, 0.2), "GameColors.FLOATING_PICKUP")

	# 天气/时间色
	_assert_eq(GameColors.LIGHT_NOON, Color(1, 1, 1, 1), "GameColors.LIGHT_NOON")
	_assert_eq(GameColors.LIGHT_NIGHT, Color(0.2, 0.2, 0.4, 1.0), "GameColors.LIGHT_NIGHT")
	_assert_eq(GameColors.LIGHT_DAWN, Color(0.8, 0.5, 0.4, 1.0), "GameColors.LIGHT_DAWN")
	_assert_eq(GameColors.LIGHT_DUSK, Color(0.8, 0.4, 0.2, 1.0), "GameColors.LIGHT_DUSK")
	_assert_eq(GameColors.LIGHT_STORM, Color(0.3, 0.3, 0.4, 1.0), "GameColors.LIGHT_STORM")
	_assert_eq(GameColors.WEATHER_CLEAR, Color(0.5, 0.8, 1), "GameColors.WEATHER_CLEAR")
	_assert_eq(GameColors.WEATHER_STORM, Color(1, 0.3, 0.3), "GameColors.WEATHER_STORM")
	_assert_eq(GameColors.MAP_LINE, Color(1, 1, 1, 0.3), "GameColors.MAP_LINE")
	_assert_eq(GameColors.MAP_LABEL, Color(0.8, 0.8, 0.8, 0.8), "GameColors.MAP_LABEL")

	# 模态遮罩
	_assert_eq(GameColors.MODAL_TOP, Color(0.02, 0.02, 0.03, 0.72), "GameColors.MODAL_TOP")
	_assert_eq(GameColors.MODAL_BOTTOM, Color(0.01, 0.01, 0.02, 0.88), "GameColors.MODAL_BOTTOM")
	_assert_eq(GameColors.MODAL_DIM, Color(0.02, 0.02, 0.02, 0.82), "GameColors.MODAL_DIM")
	_assert_eq(GameColors.MARKET_BG, Color(0.02, 0.02, 0.02, 0.88), "GameColors.MARKET_BG")

	# 通用
	_assert_eq(GameColors.WHITE, Color.WHITE, "GameColors.WHITE")
	_assert_eq(GameColors.TRANSPARENT, Color.TRANSPARENT, "GameColors.TRANSPARENT")

	# 辅助方法：价格趋势色
	var trend_color: Color = GameColors.get_price_trend_color(2.5)
	_assert_eq(trend_color, GameColors.WARNING, "价格趋势 ≥2.0: WARNING")
	trend_color = GameColors.get_price_trend_color(1.3)
	_assert_eq(trend_color, GameColors.WARNING_SOFT, "价格趋势 1.2-2.0: WARNING_SOFT")
	trend_color = GameColors.get_price_trend_color(1.0)
	_assert_eq(trend_color, GameColors.TRANSPARENT, "价格趋势 0.8-1.2: TRANSPARENT")
	trend_color = GameColors.get_price_trend_color(0.4)
	_assert_eq(trend_color, GameColors.PRICE_CRASH, "价格趋势 ≤0.5: PRICE_CRASH")
	trend_color = GameColors.get_price_trend_color(0.6)
	_assert_eq(trend_color, GameColors.PRICE_DROP, "价格趋势 0.5-0.8: PRICE_DROP")

	# 辅助方法：繁荣度色
	var p_color: Color = GameColors.get_prosperity_color(1.2)
	_assert_eq(p_color, GameColors.TEXT_GOLD, "繁荣度>1.1: TEXT_GOLD")
	p_color = GameColors.get_prosperity_color(1.0)
	_assert_eq(p_color, GameColors.TEXT_GOLD_BRIGHT, "繁荣度0.9-1.1: TEXT_GOLD_BRIGHT")
	p_color = GameColors.get_prosperity_color(0.8)
	_assert_eq(p_color, GameColors.WARNING, "繁荣度<0.9: WARNING")

	# 辅助方法：港状态栏色
	var r_color: Color = GameColors.get_ratio_status_color(0.05)
	_assert_eq(r_color, GameColors.WARNING, "比例 ≤0.1: WARNING")
	r_color = GameColors.get_ratio_status_color(0.2)
	_assert_eq(r_color, GameColors.WARNING_SOFT, "比例 0.1-0.25: WARNING_SOFT")
	r_color = GameColors.get_ratio_status_color(0.5)
	_assert_eq(r_color, GameColors.TEXT_GOLD_BRIGHT, "比例 >0.25: TEXT_GOLD_BRIGHT")

	print("")

# ── NK1-P6-POLISH-004: FloatingTextConfig 测试 ─────────────

func _test_floating_text_config() -> void:
	print("[FloatingTextConfig]")

	# 基础参数
	_assert_eq(FloatingTextConfig.DEFAULT_FLOAT_SPEED, 50.0, "DEFAULT_FLOAT_SPEED=50.0")
	_assert_eq(FloatingTextConfig.DEFAULT_LIFETIME, 1.5, "DEFAULT_LIFETIME=1.5")

	# 偏移量
	_assert_eq(FloatingTextConfig.OFFSET_CREW_LOSS, Vector2(-100, -100), "OFFSET_CREW_LOSS")
	_assert_eq(FloatingTextConfig.OFFSET_SCENERY, Vector2(-120, -80), "OFFSET_SCENERY")
	_assert_eq(FloatingTextConfig.OFFSET_ECONOMY, Vector2(-200, -120), "OFFSET_ECONOMY")
	_assert_eq(FloatingTextConfig.OFFSET_PORT_NEAR, Vector2(-150, -100), "OFFSET_PORT_NEAR")
	_assert_eq(FloatingTextConfig.OFFSET_PICKUP, Vector2(0, 0), "OFFSET_PICKUP")

	# 生命周期
	_assert_eq(FloatingTextConfig.LIFETIME_CREW_LOSS, 2.0, "LIFETIME_CREW_LOSS=2.0")
	_assert_eq(FloatingTextConfig.LIFETIME_SCENERY, 3.0, "LIFETIME_SCENERY=3.0")
	_assert_eq(FloatingTextConfig.LIFETIME_ECONOMY, 4.0, "LIFETIME_ECONOMY=4.0")
	_assert_eq(FloatingTextConfig.LIFETIME_PORT_NEAR, 3.5, "LIFETIME_PORT_NEAR=3.5")

	# 抖动
	_assert_eq(FloatingTextConfig.RANDOM_JITTER, 20.0, "RANDOM_JITTER=20.0")
	_assert_eq(FloatingTextConfig.Z_INDEX_DEFAULT, 100, "Z_INDEX_DEFAULT=100")

	# 航海风景池
	_assert_eq(FloatingTextConfig.VOYAGE_SCENERY.size(), 10, "VOYAGE_SCENERY 池: 10 条")
	_assert_true(FloatingTextConfig.VOYAGE_SCENERY[0].length() > 0, "VOYAGE_SCENERY[0] 非空")
	_assert_true(FloatingTextConfig.VOYAGE_SCENERY[9].length() > 0, "VOYAGE_SCENERY[9] 非空")

	print("")

# ── 太阁风地图视觉 / 航线样式 ────────────────────────────

func _test_map_visual_style() -> void:
	print("--- MapVisualStyle ---")
	_assert_eq(MapRoutePainter.route_key("quanzhou", "guangzhou"), "guangzhou|quanzhou", "route_key sorted")
	_assert_eq(MapRoutePainter.ROUTE_COLOR, Color(0.77, 0.66, 0.36, 0.55), "shared route color")
	_assert_eq(MapRoutePainter.ROUTE_WIDTH_WORLD, 4.0, "world route width")
	_assert_eq(MapRoutePainter.ROUTE_WIDTH_MINIMAP, 1.5, "minimap route width")
	_assert_eq(MapPortStyle.port_color("main"), MapPortStyle.PORT_MAIN, "main port color")
	_assert_eq(MapPortStyle.port_color("distant"), MapPortStyle.PORT_DISTANT, "distant port color")

	var port_zone: Node = load(ResourcePaths.SCENE_PORT_ZONE).instantiate()
	_assert_true(port_zone.has_node("Visual/Icon"), "PortZone has koei icon")
	_assert_true(port_zone.has_node("Visual/NameLabel"), "PortZone has name label")
	_assert_true(not port_zone.has_node("Polygon2D"), "PortZone removed yellow diamond")
	_assert_true(port_zone.has_method("setup"), "PortZone setup()")
	port_zone.free()

	var world_map: PackedScene = load(ResourcePaths.SCENE_WORLD_MAP)
	_assert_not_null(world_map, "WorldMap scene loads")
	var wm: Node = world_map.instantiate()
	_assert_true(wm.has_node("RouteLayer"), "WorldMap has RouteLayer")
	_assert_true(wm.get_node("RouteLayer").has_method("set_port_nodes"), "RouteLayer API")
	_assert_true(wm.has_node("CanvasLayer/HUD/MinimapPanel/MinimapFrame"), "Minimap koei frame")
	_assert_true(wm.has_node("CanvasLayer/HUD/StrategicMapOverlay"), "WorldMap strategic overlay")
	wm.free()

	var overlay_scene: PackedScene = load(ResourcePaths.SCENE_STRATEGIC_MAP_OVERLAY)
	_assert_not_null(overlay_scene, "StrategicMapOverlay scene loads")
	var overlay: Node = overlay_scene.instantiate()
	_assert_true(overlay.has_method("open"), "overlay open()")
	_assert_true(overlay.has_method("close"), "overlay close()")
	_assert_true(overlay.has_method("is_open"), "overlay is_open()")
	_assert_true(overlay.has_node("Center/MapFrame/Margin/VBox/MapView"), "overlay map view")
	overlay.free()
	print("")
