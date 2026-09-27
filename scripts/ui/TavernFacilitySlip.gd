class_name TavernFacilitySlip
extends PanelContainer
## 设施页用的独立纸笺。Main 可在酒馆/岸门页直接实例化，不承担路由或数值。

signal selected(facility_id: String)

@export var facility_id := "tavern"
@export var port_name := "泉州"
@export var facility_name := "酒馆"
@export var facility_subtitle := "闻讯・募人"
@export var status_text := "本日开放"
@export var record_text := "酒气与潮气同在。邻桌谈及远港价目。"
@export var action_text := "进入酒馆"
@export var icon_name := "tavern"

func _ready() -> void:
	_render()

func _render() -> void:
	for child in get_children():
		child.queue_free()
	UiTheme.paper_card(self)
	custom_minimum_size = Vector2(380, 248)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(54, 54)
	frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := load("res://assets/icon_%s.png" % icon_name) as Texture2D
	if texture != null:
		icon.texture = texture
	frame.add_child(icon)
	heading.add_child(frame)

	var title_column := VBoxContainer.new()
	title_column.alignment = BoxContainer.ALIGNMENT_CENTER
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(title_column)

	var title := Label.new()
	title.text = "%s・%s" % [port_name, facility_name]
	title.add_theme_font_override("font", UiTheme.title_font() if UiTheme.IS_JUANBEN else UiTheme.font())
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TIDE))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = facility_subtitle
	UiTheme.style_footnote(subtitle)
	subtitle.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_column.add_child(subtitle)

	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	var status := Label.new()
	status.text = "记录状态　%s" % status_text
	status.add_theme_font_override("font", UiTheme.font())
	status.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	status.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.MOSS))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)

	var record_head := Label.new()
	record_head.text = "现场记录"
	record_head.add_theme_font_override("font", UiTheme.title_font() if UiTheme.IS_JUANBEN else UiTheme.font())
	record_head.add_theme_font_size_override("font_size", 18)
	record_head.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.GOLD))
	record_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(record_head)

	var record := Label.new()
	record.text = record_text
	record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	record.custom_minimum_size = Vector2(0, 42)
	record.add_theme_font_override("font", UiTheme.font())
	record.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT)
	record.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT))
	record.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(record)

	var action := Button.new()
	action.text = action_text
	action.custom_minimum_size = Vector2(0, 38)
	action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	action.pressed.connect(func() -> void: selected.emit(facility_id))
	UiTheme.style_button(action, facility_id == "tavern")
	column.add_child(action)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(facility_id)
