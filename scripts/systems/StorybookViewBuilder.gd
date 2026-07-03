class_name StorybookViewBuilder extends RefCounted

## 根据 StorybookPresenter 的只读模型构造太阁式札册界面。
## 仅创建 Control 节点，不修改 GameState。

const Presenter := preload(ResourcePaths.SCRIPT_STORYBOOK_PRESENTER)

const CARD_MIN_SIZE := Vector2(210, 154)
const RELATIONSHIP_ROW_MIN_SIZE := Vector2(0, 88)
const PORTRAIT_SIZE := Vector2(64, 64)

static func build(story_state, initial_tab: int = 0, focus_id: String = "", route_callback: Callable = Callable()) -> Control:
	var model: Dictionary = Presenter.build_view_model(story_state)
	var tabs := TabContainer.new()
	tabs.name = "StorybookTabs"
	tabs.custom_minimum_size = Vector2(780, 520)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.set_meta("focus_id", focus_id)

	var cards_page := _build_collection_page("CardsPage", "CardsGrid", "Cards", model.get("cards", []), "Card", focus_id, route_callback)
	tabs.add_child(cards_page)
	tabs.set_tab_title(0, "札 %d/%d" % [int(model.get("card_acquired", 0)), int(model.get("card_total", 0))])

	var titles_page := _build_collection_page("TitlesPage", "TitlesGrid", "Titles", model.get("titles", []), "Title", focus_id, route_callback)
	tabs.add_child(titles_page)
	tabs.set_tab_title(1, "称号 %d/%d" % [int(model.get("title_acquired", 0)), int(model.get("title_total", 0))])

	var relationships_page := _build_relationship_page(model.get("relationships", []), focus_id, route_callback)
	tabs.add_child(relationships_page)
	tabs.set_tab_title(2, "人物关系")

	var clamped_tab := clampi(initial_tab, 0, tabs.get_child_count() - 1)
	tabs.set_meta("initial_tab", clamped_tab)
	tabs.call_deferred("set_current_tab", clamped_tab)
	return tabs

static func _build_collection_page(page_name: String, grid_name: String, detail_prefix: String, items: Array, node_prefix: String, focus_id: String = "", route_callback: Callable = Callable()) -> Control:
	var page := VBoxContainer.new()
	page.name = page_name
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.name = page_name + "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var detail_panel := _make_detail_panel(detail_prefix, route_callback)
	page.add_child(detail_panel)
	var detail_text := detail_panel.find_child(detail_prefix + "DetailText", true, false) as RichTextLabel
	var task_steps := detail_panel.find_child(detail_prefix + "TaskSteps", true, false) as VBoxContainer
	var route_button := detail_panel.find_child(detail_prefix + "DetailRouteButton", true, false) as Button

	if items.is_empty():
		var empty := UIBuilder.make_label("尚无条目", UITheme.SUBTITLE_FACILITY)
		empty.name = grid_name + "Empty"
		grid.add_child(empty)
		_update_detail_panel({}, detail_text, route_button, task_steps, route_callback)
		return page

	var default_item: Dictionary = {}
	for item: Dictionary in items:
		var card := _make_collection_card(item, node_prefix, focus_id)
		_bind_detail_interaction(card, item, detail_text, route_button, task_steps, route_callback)
		grid.add_child(card)
		_record_focus_target(page, scroll, card, focus_id)
		if default_item.is_empty() or str(item.get("id", "")) == focus_id:
			default_item = item
	_update_detail_panel(default_item, detail_text, route_button, task_steps, route_callback)
	return page

static func _make_collection_card(item: Dictionary, node_prefix: String, focus_id: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.name = "%s_%s" % [node_prefix, _safe_node_id(str(item.get("id", "unknown")))]
	panel.theme_type_variation = UITheme.CARD_FACILITY
	panel.custom_minimum_size = CARD_MIN_SIZE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if item.get("acquired", false) != true:
		panel.modulate = GameColors.TEXT_ICON_AVAILABLE
	if str(item.get("id", "")) == focus_id:
		_apply_focus_to_panel(panel)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	var title := UIBuilder.make_label(str(item.get("display_name", "？？？")), UITheme.TITLE_FACILITY)
	title.name = "ItemName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var meta := UIBuilder.make_label(_format_item_meta(item), UITheme.SUBTITLE_FACILITY)
	meta.name = "ItemMeta"
	box.add_child(meta)

	var desc := UIBuilder.make_label(str(item.get("description", "")), UITheme.BODY_EVENT)
	desc.name = "ItemDesc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)

	var unlock_text := str(item.get("unlock_text", ""))
	if unlock_text != "":
		var unlock := UIBuilder.make_label("用途：" + unlock_text, UITheme.SUBTITLE_FACILITY)
		unlock.name = "ItemUnlock"
		unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(unlock)

	var effect_text := str(item.get("effect_text", ""))
	if effect_text != "":
		var effect := UIBuilder.make_label("效果：" + effect_text, UITheme.SUBTITLE_FACILITY)
		effect.name = "ItemEffect"
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(effect)

	var active_bonus_text := str(item.get("active_bonus_text", ""))
	if active_bonus_text != "":
		var active_bonus := UIBuilder.make_label("当前可生效加成：" + active_bonus_text, UITheme.SUBTITLE_FACILITY)
		active_bonus.name = "ItemActiveBonus"
		active_bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(active_bonus)

	var task_progress := str(item.get("task_progress_text", ""))
	if task_progress != "":
		var progress_text := "任务链：" + task_progress
		var next_recommendation := str(item.get("next_recommendation", ""))
		if next_recommendation != "":
			progress_text += "｜下一步：" + next_recommendation
		var task_label := UIBuilder.make_label(progress_text, UITheme.SUBTITLE_FACILITY)
		task_label.name = "ItemTaskProgress"
		task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(task_label)

	var status := UIBuilder.make_label(str(item.get("status", "")), UITheme.SUBTITLE_FACILITY)
	status.name = "ItemStatus"
	box.add_child(status)
	return panel

static func _build_relationship_page(rows: Array, focus_id: String = "", route_callback: Callable = Callable()) -> Control:
	var page := VBoxContainer.new()
	page.name = "RelationshipsPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.name = "RelationshipsPageScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "RelationshipsList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var detail_panel := _make_detail_panel("Relationships", route_callback)
	page.add_child(detail_panel)
	var detail_text := detail_panel.find_child("RelationshipsDetailText", true, false) as RichTextLabel
	var task_steps := detail_panel.find_child("RelationshipsTaskSteps", true, false) as VBoxContainer
	var route_button := detail_panel.find_child("RelationshipsDetailRouteButton", true, false) as Button

	if rows.is_empty():
		var empty := UIBuilder.make_label("暂无人物关系", UITheme.SUBTITLE_FACILITY)
		empty.name = "RelationshipsEmpty"
		list.add_child(empty)
		_update_detail_panel({}, detail_text, route_button, task_steps, route_callback)
		return page

	var default_row: Dictionary = {}
	for row: Dictionary in rows:
		var relationship_row := _make_relationship_row(row, focus_id)
		_bind_detail_interaction(relationship_row, row, detail_text, route_button, task_steps, route_callback)
		list.add_child(relationship_row)
		_record_focus_target(page, scroll, relationship_row, focus_id)
		if default_row.is_empty() or str(row.get("id", "")) == focus_id:
			default_row = row
	_update_detail_panel(default_row, detail_text, route_button, task_steps, route_callback)
	return page

static func _make_relationship_row(row: Dictionary, focus_id: String = "") -> Control:
	var panel := PanelContainer.new()
	panel.name = "Relationship_%s" % _safe_node_id(str(row.get("id", "unknown")))
	panel.theme_type_variation = UITheme.CARD_FACILITY
	panel.custom_minimum_size = RELATIONSHIP_ROW_MIN_SIZE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if str(row.get("id", "")) == focus_id:
		_apply_focus_to_panel(panel)

	var hbox := HBoxContainer.new()
	hbox.name = "Content"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var portrait_path := str(row.get("portrait", ""))
	if portrait_path != "":
		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.custom_minimum_size = PORTRAIT_SIZE
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = AssetPlaceholder.load_texture(portrait_path, "avatar")
		hbox.add_child(portrait)

	var col := VBoxContainer.new()
	col.name = "Info"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)

	var name_label := UIBuilder.make_label(str(row.get("label", "")), UITheme.TITLE_FACILITY)
	name_label.name = "RelationshipName"
	col.add_child(name_label)

	var value_label := UIBuilder.make_label("关系 %d（%s）" % [int(row.get("value", 0)), str(row.get("level", "初识"))], UITheme.SUBTITLE_FACILITY)
	value_label.name = "RelationshipValue"
	col.add_child(value_label)

	var meter := ProgressBar.new()
	meter.name = "RelationshipMeter"
	meter.min_value = 0
	meter.max_value = 30
	meter.value = clamp(int(row.get("value", 0)), 0, 30)
	meter.show_percentage = false
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(meter)

	var unlock_text := str(row.get("unlock_text", ""))
	if unlock_text != "":
		var unlock := UIBuilder.make_label("用途：" + unlock_text, UITheme.SUBTITLE_FACILITY)
		unlock.name = "RelationshipUnlock"
		unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(unlock)

	var row_active_bonus_text := str(row.get("active_bonus_text", ""))
	if row_active_bonus_text != "":
		var row_active_bonus := UIBuilder.make_label("当前可生效加成：" + row_active_bonus_text, UITheme.SUBTITLE_FACILITY)
		row_active_bonus.name = "RelationshipActiveBonus"
		row_active_bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(row_active_bonus)

	var task_progress := str(row.get("task_progress_text", ""))
	if task_progress != "":
		var progress_text := "任务链：" + task_progress
		var next_recommendation := str(row.get("next_recommendation", ""))
		if next_recommendation != "":
			progress_text += "｜下一步：" + next_recommendation
		var task_label := UIBuilder.make_label(progress_text, UITheme.SUBTITLE_FACILITY)
		task_label.name = "RelationshipTaskProgress"
		task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(task_label)
	return panel


static func _apply_focus_to_panel(panel: PanelContainer) -> void:
	panel.set_meta("storybook_focus_target", true)
	panel.theme_type_variation = UITheme.CARD_FACILITY_QUEST
	panel.modulate = GameColors.TEXT_GOLD_BRIGHT

static func _record_focus_target(page: Control, scroll: ScrollContainer, target: Control, focus_id: String) -> void:
	if focus_id == "" or target.get_meta("storybook_focus_target", false) != true:
		return
	page.set_meta("focus_target_id", focus_id)
	page.set_meta("focus_target_node_name", target.name)
	if scroll.has_method("ensure_control_visible"):
		scroll.call_deferred("ensure_control_visible", target)


static func _make_detail_panel(prefix: String, route_callback: Callable = Callable()) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = prefix + "DetailPanel"
	panel.theme_type_variation = UITheme.CARD_FACILITY
	panel.custom_minimum_size = Vector2(0, 150)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.name = "Content"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	var title := UIBuilder.make_label("条目详情", UITheme.TITLE_FACILITY)
	title.name = prefix + "DetailTitle"
	box.add_child(title)

	var detail := RichTextLabel.new()
	detail.name = prefix + "DetailText"
	detail.theme_type_variation = UITheme.BODY_EVENT
	detail.bbcode_enabled = false
	detail.fit_content = true
	detail.scroll_active = false
	detail.custom_minimum_size = Vector2(0, 86)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(detail)

	var task_steps := VBoxContainer.new()
	task_steps.name = prefix + "TaskSteps"
	task_steps.visible = false
	task_steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(task_steps)

	var route_button := UIBuilder.make_choice_button("直达场景")
	route_button.name = prefix + "DetailRouteButton"
	route_button.disabled = true
	route_button.visible = false
	route_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if route_callback.is_valid():
		route_button.pressed.connect(func():
			var scene_id := str(route_button.get_meta("scene_id", ""))
			var focus_action_id := str(route_button.get_meta("focus_action_id", ""))
			if scene_id != "" and not route_button.disabled:
				route_callback.call(scene_id, focus_action_id)
		)
	box.add_child(route_button)
	return panel

static func _bind_detail_interaction(target: Control, item: Dictionary, detail_text: RichTextLabel, route_button: Button, task_steps: VBoxContainer, route_callback: Callable = Callable()) -> void:
	target.set_meta("storybook_detail_id", str(item.get("id", "")))
	target.set_meta("storybook_detail_text", _format_detail_text(item))
	target.set_meta("storybook_route_scene_id", str(item.get("route_scene_id", "")))
	target.set_meta("storybook_route_focus_action_id", str(item.get("route_focus_action_id", "")))
	target.gui_input.connect(_on_storybook_item_gui_input.bind(item, detail_text, route_button, task_steps, route_callback))

static func _on_storybook_item_gui_input(event: InputEvent, item: Dictionary, detail_text: RichTextLabel, route_button: Button, task_steps: VBoxContainer, route_callback: Callable = Callable()) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_update_detail_panel(item, detail_text, route_button, task_steps, route_callback)

static func _update_detail_panel(item: Dictionary, detail_text: RichTextLabel, route_button: Button, task_steps: VBoxContainer = null, route_callback: Callable = Callable()) -> void:
	if detail_text != null:
		detail_text.text = _format_detail_text(item)
	_update_task_steps(item, detail_text, task_steps, route_callback)
	if route_button == null:
		return
	var scene_id := str(item.get("route_scene_id", ""))
	if scene_id == "":
		route_button.visible = false
		route_button.disabled = true
		route_button.set_meta("scene_id", "")
		route_button.set_meta("focus_action_id", "")
		route_button.set_meta("route_action_completed", false)
		return
	var route_label := str(item.get("route_label", ""))
	if route_label == "":
		route_label = "前往 " + scene_id
	var route_completed: bool = item.get("route_action_completed", false) == true
	route_button.visible = true
	route_button.disabled = route_completed
	route_button.text = "已处理：" + route_label if route_completed else route_label
	route_button.set_meta("scene_id", scene_id)
	route_button.set_meta("focus_action_id", str(item.get("route_focus_action_id", "")))
	route_button.set_meta("route_action_completed", route_completed)

static func _update_task_steps(item: Dictionary, detail_text: RichTextLabel, task_steps: VBoxContainer, route_callback: Callable = Callable()) -> void:
	if task_steps == null:
		return
	for child in task_steps.get_children():
		child.free()
	var chain: Array = item.get("task_chain", [])
	task_steps.visible = not item.is_empty() and not chain.is_empty()
	if not task_steps.visible:
		return
	var title := UIBuilder.make_label(_format_task_steps_title(item), UITheme.SUBTITLE_FACILITY)
	title.name = "TaskStepsTitle"
	task_steps.add_child(title)
	for raw_step in chain:
		if not raw_step is Dictionary:
			continue
		var step: Dictionary = raw_step
		var step_button := _make_task_step_button(step)
		step_button.pressed.connect(_on_task_step_pressed.bind(step, item, detail_text, route_callback))
		task_steps.add_child(step_button)

static func _format_task_steps_title(item: Dictionary) -> String:
	var title := "任务链步骤"
	var progress_text := str(item.get("task_progress_text", ""))
	if progress_text == "":
		return title
	title += "（" + progress_text
	var next_recommendation := str(item.get("next_recommendation", ""))
	if next_recommendation != "":
		title += "｜" + next_recommendation if next_recommendation == "已完成全部链路" else "｜下一步：" + next_recommendation
	title += "）"
	return title

static func _make_task_step_button(step: Dictionary) -> Button:
	var button := UIBuilder.make_choice_button(_format_task_step_button_text(step))
	button.name = "TaskStep_" + _safe_node_id(str(step.get("id", "unknown")))
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var completed: bool = step.get("completed", false) == true
	var scene_id := str(step.get("scene_id", ""))
	var focus_action_id := str(step.get("focus_action_id", ""))
	button.disabled = not completed and scene_id == ""
	button.set_meta("step_id", str(step.get("id", "")))
	button.set_meta("completed", completed)
	button.set_meta("scene_id", scene_id)
	button.set_meta("focus_action_id", focus_action_id)
	button.tooltip_text = "点击回顾来源事件" if completed else "点击直达目标行动"
	return button

static func _format_task_step_button_text(step: Dictionary) -> String:
	var completed: bool = step.get("completed", false) == true
	var icon := "✓" if completed else "→"
	var phase := str(step.get("phase", "任务"))
	var label := str(step.get("label", ""))
	var status := str(step.get("status", ""))
	return "%s %s行动：%s（%s）" % [icon, phase, label, status]

static func _on_task_step_pressed(step: Dictionary, item: Dictionary, detail_text: RichTextLabel, route_callback: Callable = Callable()) -> void:
	var completed: bool = step.get("completed", false) == true
	if completed:
		if detail_text != null:
			detail_text.text = _format_task_step_review(step, item)
		return
	var scene_id := str(step.get("scene_id", ""))
	if scene_id == "" or not route_callback.is_valid():
		return
	route_callback.call(scene_id, str(step.get("focus_action_id", "")))

static func _format_task_step_review(step: Dictionary, item: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("【任务回顾】")
	lines.append("%s行动：%s（%s）" % [str(step.get("phase", "任务")), str(step.get("label", "")), str(step.get("status", ""))])
	var source_event := str(step.get("source_event", ""))
	if source_event == "":
		source_event = str(item.get("source_event", ""))
	var source_text := str(step.get("source_text", ""))
	if source_text == "":
		source_text = str(item.get("source_text", ""))
	if source_event != "" or source_text != "":
		var source_line := "来源事件："
		if source_event != "":
			source_line += source_event
		if source_text != "":
			source_line += " — " + source_text if source_event != "" else source_text
		lines.append(source_line)
	var scene_id := str(step.get("scene_id", ""))
	if scene_id != "":
		lines.append("关联场景：" + scene_id)
	var focus_action_id := str(step.get("focus_action_id", ""))
	if focus_action_id != "":
		lines.append("关联行动：" + focus_action_id)
	return "\n".join(lines)

static func _format_detail_text(item: Dictionary) -> String:
	if item.is_empty():
		return "选择一个条目查看来源、用途与可直达场景。"
	var display_name := _detail_display_name(item)
	var lines := PackedStringArray()
	lines.append("【%s】" % display_name)
	var status := _detail_status(item)
	if status != "":
		lines.append("状态：" + status)
	var desc := str(item.get("description", ""))
	if desc != "":
		lines.append("说明：" + desc)
	var source_event := str(item.get("source_event", ""))
	var source_text := str(item.get("source_text", ""))
	if source_event != "" or source_text != "":
		var source_line := "来源事件："
		if source_event != "":
			source_line += source_event
		if source_text != "":
			source_line += " — " + source_text if source_event != "" else source_text
		lines.append(source_line)
	var unlock_text := str(item.get("unlock_text", ""))
	if unlock_text != "":
		lines.append("解锁行动：" + unlock_text)
	var effect_text := str(item.get("effect_text", ""))
	if effect_text != "":
		lines.append("效果：" + effect_text)
	var active_bonus_text := str(item.get("active_bonus_text", ""))
	if active_bonus_text != "":
		lines.append("当前可生效加成：" + active_bonus_text)
	var route_scene_id := str(item.get("route_scene_id", ""))
	if route_scene_id != "":
		var route_label := str(item.get("route_label", ""))
		if route_label == "":
			route_label = route_scene_id
		lines.append("直达场景：%s（%s）" % [route_label, route_scene_id])
	var route_focus_action_id := str(item.get("route_focus_action_id", ""))
	if route_focus_action_id != "":
		lines.append("直达行动：" + route_focus_action_id)
	var route_action_status := str(item.get("route_action_status", ""))
	if route_action_status != "":
		lines.append("行动状态：" + route_action_status)
	_append_task_chain_lines(lines, item)
	return "\n".join(lines)

static func _append_task_chain_lines(lines: PackedStringArray, item: Dictionary) -> void:
	var progress_text := str(item.get("task_progress_text", ""))
	if progress_text == "":
		return
	lines.append("任务链：" + progress_text)
	for raw_step in item.get("task_chain", []):
		if not raw_step is Dictionary:
			continue
		var phase := str(raw_step.get("phase", "任务"))
		var label := str(raw_step.get("label", ""))
		var status := str(raw_step.get("status", ""))
		if label == "":
			continue
		lines.append("%s行动：%s（%s）" % [phase, label, status])
	var next_recommendation := str(item.get("next_recommendation", ""))
	if next_recommendation != "":
		lines.append("下一步推荐：" + next_recommendation)

static func _detail_display_name(item: Dictionary) -> String:
	var display_name := str(item.get("display_name", ""))
	if display_name != "":
		return display_name
	var label := str(item.get("label", ""))
	if label != "":
		return label
	var name := str(item.get("name", ""))
	if name != "":
		return name
	return str(item.get("id", "未知条目"))

static func _detail_status(item: Dictionary) -> String:
	if item.has("value"):
		return "关系 %d（%s）" % [int(item.get("value", 0)), str(item.get("level", "初识"))]
	return str(item.get("status", ""))

static func _format_item_meta(item: Dictionary) -> String:
	var parts: Array[String] = []
	var category := str(item.get("category", ""))
	if category != "":
		parts.append(category)
	var rank := int(item.get("rank", 0))
	if rank > 0:
		parts.append("★%d" % rank)
	return " / ".join(parts) if not parts.is_empty() else "—"

static func _safe_node_id(value: String) -> String:
	return value.replace(":", "_").replace("/", "_").replace(".", "_").replace(" ", "_")
