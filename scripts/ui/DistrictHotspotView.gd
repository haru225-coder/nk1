extends Control
class_name DistrictHotspotView

signal hotspot_selected(id)
signal confirmation_requested(id)
signal brief_dismissed
signal option_requested(id, option_id)

var _port_id: String = ""
var _dist_id: String = ""
var _bg_path: String = ""
var _hotspots: Array = []
var _hotspots_by_id: Dictionary = {}
var _interactions_view: Dictionary = {}
var _bg: Texture2D = null
var _bg_rect: Rect2 = Rect2()

var _built: bool = false
var _brief_panel: PanelContainer
var _brief_box: VBoxContainer
var _brief_title: Label
var _brief_body: Label
var _brief_actions: HBoxContainer
var _confirm_button: Button
var _close_button: Button
var _choice_buttons: Array = []

var _brief_id: String = ""
var _brief_closed: bool = false
var _mode: String = "idle"
var _selected_id: String = ""
var _hover_id: String = ""
var _focus_id: String = ""
var _pressed_id: String = ""
var _visited: Dictionary = {}
var _mark_points: Dictionary = {}
var _mark_radius: float = 16.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_build_brief_panel()
	_built = true
	resized.connect(_layout)
	mouse_exited.connect(_on_mouse_exited)
	_layout()
	show_idle()

func setup(port_id: String, dist_id: String, bg_path: String, hotspots: Array, interactions_view) -> void:
	_port_id = port_id
	_dist_id = dist_id
	_bg_path = bg_path
	_hotspots = hotspots.duplicate(true)
	if interactions_view is Dictionary:
		_interactions_view = interactions_view.duplicate(true)
	else:
		_interactions_view = {}
	_visited.clear()
	_selected_id = ""
	_focus_id = ""
	_hover_id = ""
	_pressed_id = ""
	_bg = null
	if not _bg_path.is_empty() and ResourceLoader.exists(_bg_path):
		var resource = ResourceLoader.load(_bg_path)
		if resource is Texture2D:
			_bg = resource
	_rebuild_marks()
	if _built:
		_layout()
		show_idle()
	queue_redraw()

func _build_brief_panel() -> void:
	_brief_panel = PanelContainer.new()
	_brief_panel.name = "BriefPanel"
	_brief_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_brief_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_brief_panel.add_child(margin)
	_brief_box = VBoxContainer.new()
	_brief_box.add_theme_constant_override("separation", 12)
	margin.add_child(_brief_box)
	_brief_title = Label.new()
	_brief_title.add_theme_color_override("font_color", UiTheme.TEXT)
	_brief_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_box.add_child(_brief_title)
	_brief_body = Label.new()
	_brief_body.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_brief_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_brief_box.add_child(_brief_body)
	_brief_actions = HBoxContainer.new()
	_brief_actions.add_theme_constant_override("separation", 8)
	_brief_box.add_child(_brief_actions)
	_close_button = Button.new()
	_close_button.text = "关闭"
	_close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_button.pressed.connect(_on_close_pressed)
	_brief_actions.add_child(_close_button)
	_confirm_button = Button.new()
	_confirm_button.text = "确认"
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(_on_confirmation_pressed)
	_brief_actions.add_child(_confirm_button)
	_confirm_button.hide()
	_brief_panel.hide()

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var available := Rect2(Vector2.ZERO, size)
	if _bg == null:
		_bg_rect = available
	else:
		var texture_size := _bg.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y)
			var draw_size := texture_size * scale_factor
			_bg_rect = Rect2((size - draw_size) * 0.5, draw_size)
		else:
			_bg_rect = available
	if is_instance_valid(_brief_panel):
		var wide := size.x >= 760.0
		if wide:
			var panel_width := clampf(size.x * 0.30, 260.0, 360.0)
			_brief_panel.custom_minimum_size = Vector2(panel_width, 0.0)
			_brief_panel.position = Vector2(size.x - panel_width - 16.0, 16.0)
			_brief_panel.size = Vector2(panel_width, maxf(size.y - 32.0, 160.0))
		else:
			_brief_panel.custom_minimum_size = Vector2(maxf(size.x - 32.0, 0.0), 0.0)
			_brief_panel.position = Vector2(16.0, size.y * 0.60)
			_brief_panel.size = Vector2(maxf(size.x - 32.0, 0.0), maxf(size.y * 0.36, 120.0))
	_layout_marks()
	queue_redraw()

func _draw() -> void:
	if _bg != null:
		draw_texture_rect(_bg, _bg_rect, false)
	else:
		draw_rect(_bg_rect, UiTheme.INK_SOFT)
	for id in _hotspots_by_id:
		var hotspot: Dictionary = _hotspots_by_id[id]
		if not _mark_points.has(id):
			continue
		var state := _state_for(id)
		var color := _color_for_state(state)
		var point: Vector2 = _mark_points[id]
		draw_circle(point, _mark_radius, color)
		if state == "selected":
			draw_arc(point, _mark_radius + 6.0, 0.0, TAU, 40, UiTheme.GOLD_HI, 2.0, true)
		elif state == "focus" or state == "hover":
			draw_arc(point, _mark_radius + 4.0, 0.0, TAU, 40, UiTheme.GOLD_HI, 2.0, true)

func _rebuild_marks() -> void:
	_hotspots_by_id.clear()
	_mark_points.clear()
	for raw in _hotspots:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		_hotspots_by_id[id] = entry
	_refresh_marks()

func _layout_marks() -> void:
	_mark_points.clear()
	if _bg_rect.size.x <= 0.0 or _bg_rect.size.y <= 0.0:
		return
	_mark_radius = clampf(minf(_bg_rect.size.x, _bg_rect.size.y) * 0.018, 12.0, 20.0)
	for id in _hotspots_by_id:
		var hotspot: Dictionary = _hotspots_by_id[id]
		var x := clampf(float(hotspot.get("x", 0.5)), 0.0, 1.0)
		var y := clampf(float(hotspot.get("y", 0.5)), 0.0, 1.0)
		_mark_points[id] = _bg_rect.position + Vector2(x * _bg_rect.size.x, y * _bg_rect.size.y)

func _refresh_marks() -> void:
	_layout_marks()
	queue_redraw()

func _state_for(id: String) -> String:
	if id == _pressed_id:
		return "pressed"
	if id == _selected_id:
		return "selected"
	if has_focus() and id == _focus_id:
		return "focus"
	if id == _hover_id:
		return "hover"
	if _visited.has(id):
		return "visited"
	return "normal"

func _color_for_state(state: String) -> Color:
	match state:
		"hover":
			return UiTheme.GOLD
		"focus":
			return UiTheme.GOLD_HI
		"pressed":
			return UiTheme.BTN_HI
		"visited":
			return UiTheme.INK_SOFT
		"selected":
			return UiTheme.GOLD_HI
		_:
			return UiTheme.INK

func _hotspot_at(point: Vector2) -> String:
	var nearest_id := ""
	var nearest_distance := 1000000.0
	for id in _mark_points:
		var mark_point: Vector2 = _mark_points[id]
		var distance := point.distance_to(mark_point)
		if distance <= _mark_radius + 8.0 and distance < nearest_distance:
			nearest_id = id
			nearest_distance = distance
	return nearest_id

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var next_hover := _hotspot_at(event.position)
		if next_hover != _hover_id:
			_hover_id = next_hover
			_refresh_marks()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var id := _hotspot_at(event.position)
			if id.is_empty():
				return
			_focus_id = id
			grab_focus()
			_pressed_id = id
		else:
			var released_id := _pressed_id
			_pressed_id = ""
			if not released_id.is_empty() and _hotspot_at(event.position) == released_id:
				_activate_hotspot(released_id)
		_refresh_marks()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			if is_instance_valid(_brief_panel) and _brief_panel.visible:
				_dismiss_brief()
				get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_UP:
			_move_focus(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_move_focus(1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_move_focus(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if is_instance_valid(_brief_panel) and _brief_panel.visible:
				if _mode == "confirmation":
					_on_confirmation_pressed()
				else:
					_dismiss_brief()
			else:
				_activate_hotspot(_focus_id)
			get_viewport().set_input_as_handled()

func _move_focus(step: int) -> void:
	if _hotspots_by_id.is_empty():
		return
	var ids: Array = _hotspots_by_id.keys()
	var index := ids.find(_focus_id)
	if index < 0:
		index = 0 if step >= 0 else ids.size() - 1
	else:
		index = posmod(index + step, ids.size())
	_focus_id = str(ids[index])
	grab_focus()
	_refresh_marks()

func _activate_hotspot(id: String) -> void:
	if id.is_empty() or not _hotspots_by_id.has(id):
		return
	_selected_id = id
	_focus_id = id
	_visited[id] = true
	_brief_closed = false
	show_brief(id)
	hotspot_selected.emit(id)
	_refresh_marks()

func _on_mouse_exited() -> void:
	_hover_id = ""
	_pressed_id = ""
	_refresh_marks()

func _on_close_pressed() -> void:
	_dismiss_brief()

func _on_confirmation_pressed() -> void:
	if _brief_id.is_empty():
		return
	_mode = "result"
	_confirm_button.hide()
	confirmation_requested.emit(_brief_id)

func _dismiss_brief() -> void:
	if is_instance_valid(_brief_panel):
		_brief_panel.hide()
	_brief_closed = true
	_mode = "closed"
	_brief_id = ""
	brief_dismissed.emit()

func show_idle() -> void:
	_clear_choice_buttons()
	_mode = "idle"
	_brief_id = ""
	_brief_closed = false
	if is_instance_valid(_brief_panel):
		_brief_panel.hide()

func show_choices(id: String, options: Array) -> void:
	_clear_choice_buttons()
	for option in options:
		if not option is Dictionary:
			continue
		var option_id := str(option.get("id", ""))
		var button := Button.new()
		button.text = str(option.get("label", option_id))
		button.disabled = not bool(option.get("open", true))
		button.tooltip_text = str(option.get("reason", ""))
		UiTheme.style_choice_button(button)
		button.pressed.connect(func() -> void:
			option_requested.emit(id, option_id)
		)
		_brief_actions.add_child(button)
		_brief_actions.move_child(button, _close_button.get_index())
		_choice_buttons.append(button)

func show_brief(id: String) -> void:
	_clear_choice_buttons()
	if not _hotspots_by_id.has(id):
		show_idle()
		return
	_selected_id = id
	_focus_id = id
	_visited[id] = true
	_brief_closed = false
	var info := _view_info(id)
	var title := str(info.get("title", info.get("name", id)))
	var body := _interaction_text(info, "这里没什么可说的。")
	_show_brief(id, title, body, false)
	_refresh_marks()

func show_confirmation(id: String) -> void:
	_clear_choice_buttons()
	if not _hotspots_by_id.has(id):
		return
	_selected_id = id
	_focus_id = id
	_visited[id] = true
	var info := _view_info(id)
	var title := str(info.get("title", info.get("name", id)))
	var body := _interaction_text(info, "办这件事？")
	_show_brief(id, title, body, true)
	_mode = "confirmation"
	_refresh_marks()

func show_result(id: String, lines: Array = []) -> void:
	_clear_choice_buttons()
	_selected_id = id
	_focus_id = id
	if not id.is_empty():
		_visited[id] = true
	var title := "短讯"
	var body := _show_lines(lines)
	if _hotspots_by_id.has(id):
		var info := _view_info(id)
		title = str(info.get("name", info.get("title", title)))
	if body.is_empty():
		body = "事情已经有了结果。"
	_show_brief(id, title, body, false)
	_mode = "result"
	_refresh_marks()

func _clear_choice_buttons() -> void:
	for button in _choice_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_choice_buttons.clear()

func clear_selection() -> void:
	_selected_id = ""
	_focus_id = ""
	_hover_id = ""
	_pressed_id = ""
	_brief_id = ""
	_mode = "idle"
	_refresh_marks()

func _show_brief(id: String, title: String, body: String, with_confirmation: bool) -> void:
	_brief_id = id
	_brief_closed = false
	_mode = "confirmation" if with_confirmation else "brief"
	_brief_title.text = title
	_brief_body.text = body
	_confirm_button.text = str(_find_interaction(id).get("label", "办"))
	_confirm_button.visible = with_confirmation
	_close_button.visible = true
	_brief_actions.show()
	_brief_panel.show()
	_layout()

func _view_info(id: String) -> Dictionary:
	var result: Dictionary = {}
	if _hotspots_by_id.has(id):
		result = (_hotspots_by_id[id] as Dictionary).duplicate(true)
	var interaction := _find_interaction(id)
	for key in interaction:
		result[key] = interaction[key]
	return result

func _find_interaction(id: String) -> Dictionary:
	if not _interactions_view.has(id):
		return {}
	var value = _interactions_view[id]
	if value is Dictionary:
		return value
	return {}

func _interaction_text(info: Dictionary, fallback: String) -> String:
	for field in ["brief", "text", "description", "body", "result"]:
		if not info.has(field):
			continue
		var value = info[field]
		if value is Array:
			var lines := _show_lines(value)
			if not lines.is_empty():
				return lines
		elif not str(value).is_empty():
			return str(value)
	return fallback

func _show_lines(lines: Array) -> String:
	var parts: PackedStringArray = []
	for line in lines:
		var text := str(line).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return "\n".join(parts)

func _update_brief_for(id: String) -> void:
	show_brief(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		if _built:
			_refresh_marks()

func _exit_tree() -> void:
	_hotspots_by_id.clear()
	_mark_points.clear()
	_interactions_view.clear()
