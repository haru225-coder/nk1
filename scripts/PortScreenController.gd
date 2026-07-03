extends Control

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)

@onready var title_banner: PanelContainer = $TitleBanner
@onready var port_title: Label = $TitleBanner/PortTitle
@onready var facility_hub: PanelContainer = $FacilityHub
@onready var facility_margin: MarginContainer = $FacilityHub/Margin
@onready var facility_grid: HBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid
@onready var left_column: VBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid/LeftColumn
@onready var right_column: VBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid/RightColumn
@onready var facility_hint: Label = $FacilityHub/Margin/VBox/FacilityHint
@onready var town_map_view: TownMapView = $FacilityHub/Margin/VBox/TownMapView
@onready var port_actions_label: Label = $FacilityHub/Margin/VBox/PortActionsLabel
@onready var port_choices_container: VBoxContainer = $FacilityHub/Margin/VBox/PortChoicesContainer

var _current_port_id: String = ""
var _use_town_map: bool = false

## ── 生命周期 ─────────────────────────────────────────────

func _ready() -> void:
	port_actions_label.visible = false
	port_choices_container.visible = false
	# 为设施提示文本加入呼吸灯效果，提示玩家点击交互
	var tween := create_tween().set_loops()
	tween.tween_property(facility_hint, "modulate:a", 0.45, 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(facility_hint, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

## ── 港口入口 ─────────────────────────────────────────────

func setup(scene_data: Dictionary, port_id: String) -> void:
	_current_port_id = scene_data.get("location", port_id.replace("port_", ""))
	_clear_port_invest_cooldown(_current_port_id)
	port_title.text = scene_data.get("title", "未知港口")

	var facilities: Array = scene_data.get("facilities", [])
	var town_map: Dictionary = scene_data.get("town_map", {})
	_use_town_map = not town_map.is_empty()

	if _use_town_map:
		var hotspot_count := _show_town_map(town_map, facilities)
		if hotspot_count == 0 and town_map.get("fallback_mode", "") == "cards":
			_show_facility_grid(facilities)
	else:
		_show_facility_grid(facilities)

	# NK1-P6: 港口快捷操作栏 — 补给/出港一键直达
	_show_quick_actions()

	# NK1-P6: 显示港口经济状态摘要
	_show_economy_summary()

	_clear_port_choices()
	_check_story_event_chains()
	status_updated.emit()

## ── Town Map ──────────────────────────────────────────────

func _show_town_map(town_map: Dictionary, facilities: Array) -> int:
	_use_town_map = true
	# 城镇地图模式：全屏插画，隐藏标题横幅与设施卡片面板背景
	title_banner.visible = false
	facility_hub.theme_type_variation = &""
	facility_hub.offset_left = 0.0
	facility_hub.offset_top = 0.0
	facility_hub.offset_right = 0.0
	facility_hub.offset_bottom = 0.0
	facility_margin.add_theme_constant_override("margin_left", 0)
	facility_margin.add_theme_constant_override("margin_top", 0)
	facility_margin.add_theme_constant_override("margin_right", 0)
	facility_margin.add_theme_constant_override("margin_bottom", 0)
	facility_grid.visible = false
	town_map_view.visible = true
	facility_hint.visible = false
	port_actions_label.visible = false
	port_choices_container.visible = false
	return town_map_view.setup(town_map, facilities, _current_port_id)

## ── 设施网格 ─────────────────────────────────────────────

func _show_facility_grid(facilities: Array) -> void:
	_use_town_map = false
	# 恢复卡片模式布局
	title_banner.visible = true
	facility_hub.theme_type_variation = &"InvestigationContent"
	facility_hub.offset_left = 20.0
	facility_hub.offset_top = 172.0
	facility_hub.offset_right = -20.0
	facility_hub.offset_bottom = -24.0
	facility_margin.add_theme_constant_override("margin_left", 16)
	facility_margin.add_theme_constant_override("margin_top", 12)
	facility_margin.add_theme_constant_override("margin_right", 16)
	facility_margin.add_theme_constant_override("margin_bottom", 12)
	facility_grid.visible = true
	facility_hint.visible = true
	facility_hint.text = "▸ 点击建筑进入地点"

	for child in left_column.get_children():
		child.queue_free()
	for child in right_column.get_children():
		child.queue_free()

	const LEFT_IDS := ["tavern", "inn", "guild", "yamen"]
	const RIGHT_IDS := ["market", "shipyard", "wharf", "ruins"]

	var left_facs: Array = []
	var right_facs: Array = []
	var rest_facs: Array = []

	for fac in facilities:
		var fid: String = fac.get("id", "")
		var matched := false
		for key in LEFT_IDS:
			if fid.contains(key):
				left_facs.append(fac)
				matched = true
				break
		if matched:
			continue
		for key in RIGHT_IDS:
			if fid.contains(key):
				right_facs.append(fac)
				matched = true
				break
		if not matched:
			rest_facs.append(fac)

	for i in rest_facs.size():
		if i % 2 == 0:
			left_facs.append(rest_facs[i])
		else:
			right_facs.append(rest_facs[i])

	_populate_column(left_column, left_facs)
	_populate_column(right_column, right_facs)

	# 出场瀑布交错依次滑入动效
	var index := 0
	var delay_step := 0.05
	var max_rows: int = int(max(left_column.get_child_count(), right_column.get_child_count()))
	for i in max_rows:
		if i < left_column.get_child_count():
			_animate_slot_entry(left_column.get_child(i), index * delay_step)
			index += 1
		if i < right_column.get_child_count():
			_animate_slot_entry(right_column.get_child(i), index * delay_step)
			index += 1

func _populate_column(column: VBoxContainer, facs: Array) -> void:
	for fac in facs:
		var slot := FacilitySlotBuilder.make_slot(fac, _on_facility_pressed)
		column.add_child(slot)

func _animate_slot_entry(slot: Control, delay: float) -> void:
	var panel = slot.get_node_or_null("CardPanel")
	if panel == null:
		return
	var tween := slot.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.28).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", 0.0, 0.32).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## ── 港口选择支 ────────────────────────────────────────────

func _clear_port_choices() -> void:
	for child in port_choices_container.get_children():
		child.queue_free()
	port_actions_label.visible = false
	port_choices_container.visible = false

func _on_facility_pressed(fac: Dictionary) -> void:
	if GameManager.input_locked:
		return
	var target_scene: String = GameManager.resolve_facility_scene(fac, _current_port_id)
	if target_scene != "":
		scene_requested.emit(target_scene)

## ── NK1-P6: 港口快捷操作 ─────────────────────────────────

## 在港口主界面显示快捷操作栏（补给/出港），减少 3-click 操作到 1-click
func _show_quick_actions() -> void:
	for child in port_choices_container.get_children():
		child.queue_free()

	# 城镇地图全屏模式下不显示快捷操作栏（出港已由底部 CommandBar 提供）
	if _use_town_map:
		port_actions_label.visible = false
		port_choices_container.visible = false
		return

	var needs_supply := GameState.food < GameState.max_food or GameState.water < GameState.max_water
	var needs_repair := GameState.ship_hp < GameState.ship_max_hp
	var has_actions := false
	var supply_cost := 20  ## NK1-P6: 补满水粮固定费用
	var missing_hp: float = 0.0
	var repair_cost: int = 0

	if needs_repair:
		missing_hp = GameState.ship_max_hp - GameState.ship_hp
		repair_cost = ceili(missing_hp * 2.0)

	# 快捷补给按钮
	if needs_supply:
		var supply_btn := UIBuilder.make_button("🍚 一键补满水粮 (%d 钱)" % supply_cost, UITheme.BTN_ACTION, 44)
		supply_btn.pressed.connect(_on_quick_supply)
		port_choices_container.add_child(supply_btn)
		has_actions = true

	# 快捷修理按钮
	if needs_repair:
		var repair_btn := UIBuilder.make_button("🔧 一键全量修理 (+%d HP, %d 钱)" % [int(missing_hp), repair_cost], UITheme.BTN_ACTION, 44)
		repair_btn.pressed.connect(_on_quick_repair)
		port_choices_container.add_child(repair_btn)
		has_actions = true

	# 太阁式月历：休整至下月
	var calendar = GameState.get("calendar")
	if calendar != null and calendar.has_method("days_until_next_month"):
		var days_to_next := int(calendar.days_until_next_month())
		var rest_btn := UIBuilder.make_button("🗓 休整至下月 (%d日)" % days_to_next, UITheme.BTN_ACTION, 44)
		rest_btn.pressed.connect(_on_rest_to_next_month)
		port_choices_container.add_child(rest_btn)
		has_actions = true

	# 港口投资按钮（三档）
	for tier_key in ["small", "medium", "large"]:
		var tier: Dictionary = InvestPortHandler.INVEST_TIERS[tier_key]
		var invest_btn := UIBuilder.make_button(
			"💰 %s投资港口 (%d 钱)" % [tier["label"], int(tier["amount"])],
			UITheme.BTN_ACTION, 44
		)
		invest_btn.pressed.connect(_on_quick_invest.bind(tier_key))
		port_choices_container.add_child(invest_btn)
		has_actions = true

	# 快捷出港按钮
	var sail_btn := UIBuilder.make_button("🚢 升帆出港", UITheme.BTN_SET_SAIL, 44)
	sail_btn.pressed.connect(_on_quick_sail)
	port_choices_container.add_child(sail_btn)
	has_actions = true

	port_actions_label.visible = has_actions
	port_choices_container.visible = has_actions

## NK1-P6: 显示当前港口经济状态摘要（繁荣度+好感度+活跃事件）
func _show_economy_summary() -> void:
	var market = GameState.market
	if market == null:
		return
	var prosperity: float = market.get_prosperity(_current_port_id)
	var affinity_label: String = market.get_affinity_label(_current_port_id)
	var prosperity_str := "平稳"
	if prosperity > 1.1:
		prosperity_str = "繁荣"
	elif prosperity < 0.9:
		prosperity_str = "萧条"

	# 检查活跃事件
	var active_events := WorldEventTracker.get_active_events()
	var event_count := 0
	for e in active_events:
		if e.target_port == _current_port_id:
			event_count += 1

	var summary := "港市：%s · 声誉：%s" % [prosperity_str, affinity_label]
	if event_count > 0:
		summary += " · 异动×%d" % event_count

	# 如果有经济日志，追加最新动态
	if GameState.economy_log != null:
		var latest: String = GameState.economy_log.get_latest()
		if not latest.is_empty():
			summary += "\n" + latest

	message_logged.emit(summary + "\n")

## 快捷补给：直接调用 BuySuppliesHandler
func _on_quick_supply() -> void:
	if GameManager.input_locked:
		return
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.BUY_SUPPLIES, "player", "shipyard",
		{"supply_type": "food_water", "total_cost": 20, "fill_to_max": true},
		{"port_id": _current_port_id}
	))
	if result.success:
		message_logged.emit("【补给】水粮已全部补满！\n")
		status_updated.emit()
		_show_quick_actions()  # 刷新按钮
	else:
		var msg := GameManager.get_text(result.message_key, "补给失败，金钱不足。")
		message_logged.emit(msg + "\n")

## 快捷修理：直接调用 RepairHandler
func _on_quick_repair() -> void:
	if GameManager.input_locked:
		return
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.REPAIR_SHIP, "player", "shipyard",
		{"ship_index": 0, "repair_ratio": 1.0, "cost_per_hp": 2.0},
		{"port_id": _current_port_id}
	))
	if result.success:
		var repaired := float(result.data.get("repaired", 0.0))
		if repaired > 0.0:
			message_logged.emit("【修理】恢复 %.0f 点耐久，花费 %d 钱。\n" % [repaired, int(result.data.get("cost", 0))])
		else:
			message_logged.emit("【修理】船体完好，无需修理。\n")
		status_updated.emit()
		_show_quick_actions()
	else:
		var msg := GameManager.get_text(result.message_key, "修理失败，金钱不足。")
		message_logged.emit(msg + "\n")

func _check_story_event_chains() -> void:
	var ctx := {
		"port_id": _current_port_id,
		"dialogue_box": _find_dialogue_box(),
		"cutscene_player": _find_cutscene_player(),
		"message_callback": Callable(self, "_on_chain_log_message"),
	}
	var fired: Array = StoryEventChainEngine.check_triggers("enter_port", ctx)
	if not fired.is_empty():
		_show_economy_summary()

func _on_chain_log_message(text: String) -> void:
	message_logged.emit(text)

func _find_dialogue_box() -> Control:
	return get_tree().root.find_child("DialogueBox", true, false) as Control

func _find_cutscene_player() -> CutscenePlayer:
	return get_tree().root.find_child("CutscenePlayer", true, false) as CutscenePlayer

func _clear_port_invest_cooldown(port_id: String) -> void:
	var cooldown_key := InvestPortHandler.INVEST_COOLDOWN_FLAG_PREFIX + port_id
	if GameState.has_story_flag(cooldown_key):
		GameState.set_story_flag(cooldown_key, false)

## 太阁式月历：在港休整至下月
func _on_rest_to_next_month() -> void:
	if GameManager.input_locked:
		return
	if not GameState.has_method("rest_to_next_month"):
		return
	var days := int(GameState.rest_to_next_month())
	var calendar = GameState.get("calendar")
	var date_text: String = "下月"
	if calendar != null and calendar.has_method("date_key"):
		date_text = str(calendar.date_key())
	message_logged.emit("【休整】在港中休整 %d 日，已至 %s。\n" % [days, date_text])
	status_updated.emit()
	_show_economy_summary()
	_show_quick_actions()
	# P7-S: CalendarEventScheduler 通过 CalendarState.month_changed 自动调度

## 快捷投资：调用 InvestPortHandler
func _on_quick_invest(tier_key: String) -> void:
	if GameManager.input_locked:
		return
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.INVEST_PORT, "player", _current_port_id,
		{"tier": tier_key},
		{"port_id": _current_port_id}
	))
	if result.success:
		var tier: Dictionary = InvestPortHandler.INVEST_TIERS[tier_key]
		var specialty_id := str(result.data.get("unlocked_specialty", ""))
		var msg := "【投资】向港口投入%s %d 钱，声誉与商贸提升。\n" % [tier["label"], int(tier["amount"])]
		if specialty_id != "":
			var gname := str(GameManager.get_good_data(specialty_id).get("name", specialty_id))
			msg += "【解锁】新特产已开放交易：%s\n" % gname
		message_logged.emit(msg)
		status_updated.emit()
		_show_economy_summary()
		_show_quick_actions()
	else:
		var msg := GameManager.get_text(result.message_key, "投资失败。")
		message_logged.emit(msg + "\n")

## 快捷出港：执行出港检查后切换到世界地图
func _on_quick_sail() -> void:
	if GameManager.input_locked:
		return
	var res = GameState.customs_inspection()
	if res.get("msg", "") != "":
		message_logged.emit(res["msg"] + "\n")
	status_updated.emit()
	if not res.get("passed", false):
		return
	scene_requested.emit("world_map")
