extends Control
## 公开接口：
## setup(title_mode, title, subtitle, start_button, background)
## 接收 TitlePage 已有的题名、副标题、开卷按钮和底图；不复制或重接开卷按钮，
## 不改四个剧情路由，也不读取或写入存档。title_mode 仅用于记录本次局部查看上下文。
##
## 生命周期契约：
## 1. setup 可在 add_child 前后调用；每次 setup 都视为一次进入，清空本组件局部查看状态。
## 2. leave() 用于暂时离开首页：隐藏探索界面、释放组件内焦点、恢复底图 modulate。
##    组件保留，可再次 setup；不会改动题名、副标题、开卷按钮及其原连接。
## 3. dispose() 用于节点不再复用时：先执行 leave() 的恢复，再 queue_free()。
##    TitlePage 在离开首页时至少调用 leave()；若直接释放节点，_exit_tree 也会恢复底图。
## 4. 注记、已看标记、计数和当前展开项均为局部状态，不读档、不写入存档。
## 5. 本组件只调底图 modulate，不创建或修改 Veil、TitleStage、shader 及其他私有节点。
##
## 注记统一为四注。每条数据只使用 id、title、anchor、quote 四种键；
## quote 是展开后显示的完整原引，按钮只显示短题名。

const DATA: Array[Dictionary] = [
	{
		"id": 0,
		"title": "水涯",
		"anchor": Vector2(0.16, 0.35),
		"quote": "溯洄从之，道阻且长。溯游从之，宛在水中央。"
	},
	{
		"id": 1,
		"title": "山行",
		"anchor": Vector2(0.82, 0.29),
		"quote": "高山仰止，景行行止。",
	},
	{
		"id": 2,
		"title": "灯影",
		"anchor": Vector2(0.20, 0.72),
		"quote": "今夕何夕，见此良人？子兮子兮，如此良人何！"
	},
	{
		"id": 3,
		"title": "归途",
		"anchor": Vector2(0.77, 0.68),
		"quote": "昔我往矣，杨柳依依。今我来思，雨雪霏霏。"
	}
]

var _title_mode: Variant = null
var _title: Label = null
var _subtitle: Label = null
var _start_button: Button = null
var _background: TextureRect = null

var _background_modulate: Color = Color.WHITE
var _has_background_state := false
var _active := false
var _built := false

var _spot_layer: Control = null
var _info_panel: PanelContainer = null
var _status: Label = null
var _hint: Label = null
var _spot_buttons: Array[Button] = []
var _detail: PanelContainer = null
var _detail_title: Label = null
var _quote: RichTextLabel = null
var _reset_button: Button = null
var _collapse_button: Button = null

var _visited: Dictionary = {}
var _selected := -1


func setup(
	title_mode: Variant,
	title: Label,
	subtitle: Label,
	start_button: Button,
	background: TextureRect
) -> void:
	if _active:
		leave()

	_title_mode = title_mode
	_title = title
	_subtitle = subtitle
	_start_button = start_button
	_background = background

	set_meta("title_mode", _title_mode)
	_active = true
	visible = true

	if is_inside_tree():
		_ensure_built()
		_apply_background()
		_reset_view(false)
		_layout()


func leave() -> void:
	_active = false
	_release_focus()
	_restore_background()
	_visited.clear()
	_selected = -1

	if is_instance_valid(_detail):
		_detail.hide()
	if is_instance_valid(_quote):
		_quote.clear()
	if is_instance_valid(_detail_title):
		_detail_title.text = ""

	visible = false


func dispose() -> void:
	leave()
	queue_free()


func is_exploring() -> bool:
	return _active and visible


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_built()
	resized.connect(_layout)

	visible = _active
	if _active:
		_apply_background()
		_reset_view(false)
		_layout()


func _exit_tree() -> void:
	_restore_background()
	_active = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not _active or not visible:
		return

	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if not is_instance_valid(_detail) or not _detail.visible:
		return

	_collapse_detail(true)
	get_viewport().set_input_as_handled()


func _ensure_built() -> void:
	if not _built:
		_build()


func _build() -> void:
	if _built:
		return
	_built = true

	_spot_layer = Control.new()
	_spot_layer.name = "InkSpots"
	_spot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spot_layer)

	for index in range(DATA.size()):
		var spot: Dictionary = DATA[index]
		var button := Button.new()
		button.name = "InkSpot%d" % index
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.custom_minimum_size = Vector2(108.0, 42.0)
		button.tooltip_text = "查看「%s」的完整原引" % str(spot["title"])
		button.pressed.connect(_select.bind(index))
		button.focus_entered.connect(_focus.bind(index))
		button.mouse_entered.connect(_hover.bind(index))
		button.mouse_exited.connect(_hover_end)
		_spot_layer.add_child(button)
		_spot_buttons.append(button)

	_info_panel = PanelContainer.new()
	_info_panel.name = "ExplorerHint"
	_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_panel.add_theme_stylebox_override("panel", _panel_style(0.78))
	add_child(_info_panel)

	var info_margin := MarginContainer.new()
	info_margin.add_theme_constant_override("margin_left", 14)
	info_margin.add_theme_constant_override("margin_right", 14)
	info_margin.add_theme_constant_override("margin_top", 11)
	info_margin.add_theme_constant_override("margin_bottom", 11)
	_info_panel.add_child(info_margin)

	var info_rows := VBoxContainer.new()
	info_rows.add_theme_constant_override("separation", 5)
	info_margin.add_child(info_rows)

	var heading := Label.new()
	heading.text = "四注可寻"
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", UiTheme.TEXT)
	info_rows.add_child(heading)

	_status = Label.new()
	_status.add_theme_color_override("font_color", UiTheme.GOLD)
	info_rows.add_child(_status)

	_hint = Label.new()
	_hint.text = "墨点可聚焦，查看后留泥金标记。也可直接开卷。"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	info_rows.add_child(_hint)

	_detail = PanelContainer.new()
	_detail.name = "InkDetail"
	_detail.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail.add_theme_stylebox_override("panel", _panel_style(0.96))
	add_child(_detail)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 16)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 16)
	detail_margin.add_theme_constant_override("margin_bottom", 13)
	_detail.add_child(detail_margin)

	var detail_rows := VBoxContainer.new()
	detail_rows.add_theme_constant_override("separation", 10)
	detail_margin.add_child(detail_rows)

	_detail_title = Label.new()
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.add_theme_font_size_override("font_size", 22)
	_detail_title.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	detail_rows.add_child(_detail_title)

	var original_caption := Label.new()
	original_caption.text = "原引"
	original_caption.add_theme_font_size_override("font_size", 13)
	original_caption.add_theme_color_override("font_color", UiTheme.GOLD)
	detail_rows.add_child(original_caption)

	_quote = RichTextLabel.new()
	_quote.bbcode_enabled = false
	_quote.fit_content = false
	_quote.scroll_active = true
	_quote.selection_enabled = true
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.custom_minimum_size = Vector2(0.0, 118.0)
	_quote.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quote.add_theme_font_size_override("normal_font_size", 18)
	_quote.add_theme_color_override("default_color", UiTheme.TEXT)
	detail_rows.add_child(_quote)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	detail_rows.add_child(actions)

	_reset_button = Button.new()
	_reset_button.text = "复位"
	_reset_button.tooltip_text = "清除本次查看与泥金计数；不影响存档和原开卷"
	_reset_button.focus_mode = Control.FOCUS_ALL
	_style_command_button(_reset_button)
	_reset_button.pressed.connect(_on_reset_pressed)
	actions.add_child(_reset_button)

	_collapse_button = Button.new()
	_collapse_button.text = "收起"
	_collapse_button.tooltip_text = "收起原引，保留已查看的泥金标记"
	_collapse_button.focus_mode = Control.FOCUS_ALL
	_style_command_button(_collapse_button)
	_collapse_button.pressed.connect(_collapse_detail)
	actions.add_child(_collapse_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	_detail.hide()
	_update_all_spots()
	_update_status()

func _apply_background() -> void:
	if not _active or not is_instance_valid(_background):
		return
	if not _background_saved:
		_original_modulate = _background.modulate
		_background_saved = true

	# 仅提亮底图。原有暗色 Veil 和着色器保持原样，退出时恢复原 modulate。
	_background.modulate = Color(
		minf(_original_modulate.r * 1.16 + 0.12, 1.0),
		minf(_original_modulate.g * 1.16 + 0.12, 1.0),
		minf(_original_modulate.b * 1.16 + 0.12, 1.0),
		_original_modulate.a
	)


func _restore_background() -> void:
	if _background_saved and is_instance_valid(_background):
		_background.modulate = _original_modulate
	_background_saved = false


func _select(index: int) -> void:
	if not _active or index < 0 or index >= DATA.size():
		return
	if not is_instance_valid(_quote) or not is_instance_valid(_detail):
		return

	_selected = index
	_visited[index] = true
	var spot: Dictionary = DATA[index]
	_detail_title.text = str(spot["title"])
	_quote.clear()
	_quote.append_text(str(spot["quote"]))
	_detail.show()
	_update_all_spots()
	_update_status()
	_layout()


func _focus(index: int) -> void:
	if index < 0 or index >= DATA.size():
		return
	var spot: Dictionary = DATA[index]
	_hint.text = "Enter 查看「%s」；Tab 移焦，Esc 收起。" % str(spot["title"])


func _hover(index: int) -> void:
	if index < 0 or index >= DATA.size():
		return
	var spot: Dictionary = DATA[index]
	_hint.text = "查看「%s」的完整原引" % str(spot["title"])


func _hover_end() -> void:
	if _selected >= 0 and _selected < DATA.size():
		_hint.text = "原引已展开；可复位、收起，或继续查看其他墨点。"
	else:
		_hint.text = "墨点可聚焦查看；不探索也可直接开卷。"


func _update_all_spots() -> void:
	for index in range(_spot_buttons.size()):
		_update_spot(index)


func _update_spot(index: int) -> void:
	if index < 0 or index >= _spot_buttons.size():
		return

	var button: Button = _spot_buttons[index]
	var spot: Dictionary = DATA[index]
	var visited: bool = _visited.has(index)
	var selected: bool = index == _selected
	button.text = ("✦ " if visited else "・ ") + str(spot["title"])
	button.add_theme_font_size_override("font_size", 17)

	var base: Color = Color(UiTheme.INK, 0.90) if visited else Color(UiTheme.INK, 0.88)
	if selected:
		base = Color(UiTheme.BTN_HI, 0.96)

	button.add_theme_stylebox_override("normal", _chip_style(base, UiTheme.GOLD if visited else UiTheme.TEXT_DIM, 1))
	button.add_theme_stylebox_override("hover", _chip_style(Color(UiTheme.INK_SOFT, 0.96), UiTheme.GOLD, 2))
	button.add_theme_stylebox_override("focus", _focus_style())
	button.add_theme_stylebox_override("pressed", _chip_style(Color(UiTheme.BTN_HI, 0.96), UiTheme.GOLD_HI, 2))
	button.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	button.add_theme_color_override("font_hover_color", UiTheme.GOLD_HI)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _on_reset_pressed() -> void:
	_reset_view(true)


func _reset_view(restore_focus: bool = false) -> void:
	_release_focus()
	_visited.clear()
	_selected = -1

	if is_instance_valid(_detail):
		_detail.hide()
	if is_instance_valid(_detail_title):
		_detail_title.text = ""
	if is_instance_valid(_quote):
		_quote.clear()
	if is_instance_valid(_hint):
		_hint.text = "墨点可聚焦查看；不探索也可直接开卷。"

	_update_all_spots()
	_update_status()
	_layout()

	if restore_focus and _active and not _spot_buttons.is_empty():
		_spot_buttons[0].grab_focus()


func _collapse_detail(restore_focus: bool = true) -> void:
	var previous := _selected
	_selected = -1

	if is_instance_valid(_reset_button) and _reset_button.has_focus():
		_reset_button.release_focus()
	if is_instance_valid(_collapse_button) and _collapse_button.has_focus():
		_collapse_button.release_focus()
	if is_instance_valid(_detail):
		_detail.hide()
	if is_instance_valid(_quote):
		_quote.clear()
	if is_instance_valid(_detail_title):
		_detail_title.text = ""
	if is_instance_valid(_hint):
		_hint.text = "原引已收起；泥金标记保留，也可直接开卷。"

	_update_all_spots()
	if restore_focus and previous >= 0 and previous < _spot_buttons.size():
		_spot_buttons[previous].grab_focus()


func _release_focus() -> void:
	for button in _spot_buttons:
		if is_instance_valid(button) and button.has_focus():
			button.release_focus()
	if is_instance_valid(_reset_button) and _reset_button.has_focus():
		_reset_button.release_focus()
	if is_instance_valid(_collapse_button) and _collapse_button.has_focus():
		_collapse_button.release_focus()


func _update_status() -> void:
	if not is_instance_valid(_status):
		return
	_status.text = "已看 %d / %d　泥金留记" % [_visited.size(), DATA.size()]


func _layout() -> void:
	if not _built or not is_instance_valid(_spot_layer):
		return

	var area := size
	if area.x <= 1.0 or area.y <= 0.0:
		if is_inside_tree():
			area = get_viewport_rect().size
		else:
			area = Vector2(1152.0, 648.0)
	if area.x <= 0.0 or area.y <= 0.0:
		return

	_spot_layer.position = Vector2.ZERO
	_spot_layer.size = area

	for index in range(_spot_buttons.size()):
		var button: Button = _spot_buttons[index]
		var anchor: Vector2 = DATA[index]["anchor"]
		button.size = button.get_combined_minimum_size()
		var desired := Vector2(
			area.x * anchor.x - button.size.x * 0.5,
			area.y * anchor.y - button.size.y * 0.5
		)
		button.position = Vector2(
			clampf(desired.x, 8.0, maxf(8.0, area.x - button.size.x - 8.0)),
			clampf(desired.y, 8.0, maxf(8.0, area.y - 8.0))
		)

	var margin := clampf(area.x * 0.035, 14.0, 42.0)
	var info_width := minf(390.0, maxf(220.0, area.x - margin * 2.0))
	_info_panel.custom_minimum_size.x = info_width
	_info_panel.size = Vector2(info_width, 0.0)
	var info_height := _info_panel.get_combined_minimum_size().y
	_info_panel.size = Vector2(info_width, info_height)
	_info_panel.position = Vector2(
		margin,
		maxf(12.0, area.y - _info_panel.size.y - 20.0)
	)

	if not _detail.visible:
		return

	var detail_width := minf(510.0, maxf(260.0, area.x - 40.0))
	_detail.custom_minimum_size.x = detail_width
	_detail.size = Vector2(detail_width, 0.0)
	var detail_height := _detail.get_combined_minimum_size().y
	detail_height = clampf(detail_height, 210.0, maxf(210.0, area.y - 40.0))
	_detail.size = Vector2(detail_width, detail_height)

	var detail_x := (area.x - detail_width) * 0.5
	if area.x >= 1050.0:
		detail_x = area.x - detail_width - 42.0
	_detail.position = Vector2(
		maxf(16.0, detail_x),
		maxf(20.0, (area.y - detail_height) * 0.5)
	)


func _panel_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.INK, alpha)
	style.border_color = UiTheme.TEXT_DIM
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 2.0
	style.content_margin_top = 2.0
	style.content_margin_right = 2.0
	style.content_margin_bottom = 2.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _chip_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 7.0
	return style


func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = UiTheme.GOLD_HI
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.expand_margin_left = 3.0
	style.expand_margin_top = 3.0
	style.expand_margin_right = 3.0
	style.expand_margin_bottom = 3.0
	return style


func _style_command_button(button: Button) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", UiTheme.TEXT)
	button.add_theme_color_override("font_hover_color", UiTheme.GOLD_HI)
	button.add_theme_color_override("font_pressed_color", UiTheme.GOLD_HI)
	button.add_theme_stylebox_override("normal", _chip_style(Color(UiTheme.INK, 0.88), UiTheme.TEXT_DIM, 1))
	button.add_theme_stylebox_override("hover", _chip_style(Color(UiTheme.INK_SOFT, 0.96), UiTheme.GOLD, 1))
	button.add_theme_stylebox_override("pressed", _chip_style(Color(UiTheme.BTN_HI, 0.96), UiTheme.GOLD_HI, 1))
	button.add_theme_stylebox_override("focus", _focus_style())


var _original_modulate: Color = Color.WHITE
var _background_saved := false
