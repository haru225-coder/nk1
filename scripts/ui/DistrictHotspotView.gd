extends Control
class_name DistrictHotspotView

signal hotspot_selected(id)
signal confirmation_requested(id)
signal option_chosen(id, option_id)
signal brief_dismissed

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
var _choice_index: int = 0
var _name_tip: Label
var _name_chip: PanelContainer
var _marks_alpha: float = 1.0
var _enter_left: float = 0.0

const _ENTER_SEC := 1.2

var _brief_id: String = ""
var _brief_closed: bool = false
var _mode: String = "idle"
var _selected_id: String = ""
var _hover_id: String = ""
var _focus_id: String = ""
var _pressed_id: String = ""
var _visited: Dictionary = {}
var _looked: Dictionary = {}
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
	_looked.clear()
	_selected_id = ""
	_focus_id = ""
	_hover_id = ""
	_pressed_id = ""
	_bg = null
	var path := _bg_path
	if not path.is_empty() and not path.begins_with("res://"):
		path = "res://assets/" + path
	if not path.is_empty():
		_bg = GameManager.load_texture(path)
	_rebuild_marks()
	_enter_left = _ENTER_SEC
	_marks_alpha = 0.0
	set_process(true)
	if _built:
		_layout()
		show_idle()
	queue_redraw()

func _build_brief_panel() -> void:
	_brief_panel = PanelContainer.new()
	_brief_panel.name = "BriefPanel"
	_brief_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_brief_panel.add_theme_stylebox_override("panel", UiTheme.card())
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
	_brief_title.add_theme_color_override("font_color", UiTheme.PAPER_TEXT)
	_brief_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_box.add_child(_brief_title)
	_brief_body = Label.new()
	_brief_body.add_theme_color_override("font_color", UiTheme.PAPER_DIM)
	_brief_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	_name_chip = PanelContainer.new()
	_name_chip.name = "NameTip"
	_name_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_chip.add_theme_stylebox_override("panel", UiTheme.card())
	_name_tip = Label.new()
	_name_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tip.add_theme_color_override("font_color", UiTheme.PAPER_TEXT)
	_name_chip.add_child(_name_tip)
	add_child(_name_chip)
	_name_chip.hide()

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
	if _enter_left > 0.0 and _bg_rect.size.x > 0.0:
		var zoom := 1.0 + 0.055 * (_enter_left / _ENTER_SEC)
		var center := _bg_rect.get_center()
		var drawn := _bg_rect.size * zoom
		_bg_rect = Rect2(center - drawn * 0.5, drawn)
	if is_instance_valid(_brief_panel):
		var wide := size.x >= 760.0
		var mark := _selected_mark()
		var placed := mark.x >= 0.0
		if wide:
			var panel_width := clampf(size.x * 0.30, 260.0, 360.0)
			var inner_w := maxf(panel_width - 28.0, 80.0)
			_brief_panel.custom_minimum_size = Vector2(panel_width, 0.0)
			var panel_height := clampf(_fit_brief_text(inner_w), 72.0, size.y - 32.0)
			var on_left := placed and mark.x > size.x * 0.62
			var x := 16.0 if on_left else size.x - panel_width - 16.0
			var y := 16.0
			if placed and mark.y < size.y * 0.45:
				y = size.y - panel_height - 16.0
			_brief_panel.position = Vector2(x, y)
			_brief_panel.size = Vector2(panel_width, panel_height)
		else:
			var panel_width := maxf(size.x - 32.0, 0.0)
			var inner_w := maxf(panel_width - 28.0, 80.0)
			_brief_panel.custom_minimum_size = Vector2(panel_width, 0.0)
			var panel_height := clampf(_fit_brief_text(inner_w), 72.0, size.y - 32.0)
			var on_top := placed and mark.y > size.y * 0.55
			_brief_panel.position = Vector2(16.0, 16.0 if on_top else size.y - panel_height - 16.0)
			_brief_panel.size = Vector2(panel_width, panel_height)
	_layout_marks()
	queue_redraw()


func _selected_mark() -> Vector2:
	if _selected_id == "" or not _mark_points.has(_selected_id):
		return Vector2(-1, -1)
	return _mark_points[_selected_id]


func _fit_brief_text(inner_w: float) -> float:
	var title_h := _wrapped_height(_brief_title, inner_w)
	var body_h := _wrapped_height(_brief_body, inner_w)
	_brief_title.custom_minimum_size = Vector2(inner_w, title_h)
	_brief_body.custom_minimum_size = Vector2(inner_w, body_h)
	var height := title_h + body_h + 52.0
	if is_instance_valid(_brief_actions) and _brief_actions.visible:
		height += 40.0
	return height


func _wrapped_height(label: Label, width: float) -> float:
	if label == null or label.text.is_empty():
		return 0.0
	var font := label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var font_size := label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = 16
	return font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.859, 0.792, 0.659, 1.0))
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
		color.a *= _marks_alpha
		var point: Vector2 = _mark_points[id]
		if _marks_alpha <= 0.01:
			continue
		var halo := Color(0.914, 0.863, 0.753, 0.92 * _marks_alpha)
		draw_circle(point, _mark_radius + 3.0, halo)
		draw_circle(point, _mark_radius, color)
		var ring := UiTheme.GOLD_HI
		ring.a *= _marks_alpha
		if state == "selected":
			draw_arc(point, _mark_radius + 6.0, 0.0, TAU, 40, ring, 2.0, true)
		elif state == "focus" or state == "hover":
			draw_arc(point, _mark_radius + 4.0, 0.0, TAU, 40, ring, 2.0, true)
		_draw_mark_tag(id, point)

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
	_place_name_tip()
	queue_redraw()


func _place_name_tip() -> void:
	if not is_instance_valid(_name_chip):
		return
	var tip_id := _hover_id
	if tip_id == "":
		tip_id = _focus_id
	if tip_id == "" or not _mark_points.has(tip_id) or _marks_alpha < 0.45:
		_name_chip.hide()
		return
	var info := _view_info(tip_id)
	var name := _short_name(info, tip_id)
	if name == "" or name == tip_id:
		_name_chip.hide()
		return
	_name_tip.text = name
	var font := _name_tip.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var font_size := _name_tip.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = 16
	var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var chip_size := text_size + Vector2(16.0, 10.0)
	var point: Vector2 = _mark_points[tip_id]
	var pos := point + Vector2(_mark_radius + 6.0, -chip_size.y - 4.0)
	if pos.x + chip_size.x > size.x - 8.0:
		pos.x = point.x - _mark_radius - 6.0 - chip_size.x
	if pos.x < 4.0:
		pos.x = 4.0
	if pos.y < 4.0:
		pos.y = point.y + _mark_radius + 4.0
	_name_chip.position = pos
	_name_chip.size = chip_size
	_name_chip.show()

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

func _marks_ready() -> bool:
	return _marks_alpha >= 0.45


func _hotspot_at(point: Vector2) -> String:
	if not _marks_ready():
		return ""
	var nearest_id := ""
	var nearest_distance := 1000000.0
	for id in _mark_points:
		var mark_point: Vector2 = _mark_points[id]
		var distance := point.distance_to(mark_point)
		if distance <= _mark_radius + 16.0 and distance < nearest_distance:
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
				if _marks_ready() and is_instance_valid(_brief_panel) and _brief_panel.visible:
					_dismiss_brief()
			else:
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


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _mode != "choice" or not is_instance_valid(_brief_panel) or not _brief_panel.visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT:
			_focus_choice(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_focus_choice(1)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_press_choice()
			get_viewport().set_input_as_handled()


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
		KEY_LEFT:
			_nudge(Vector2.LEFT)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_nudge(Vector2.RIGHT)
			get_viewport().set_input_as_handled()
		KEY_UP:
			_nudge(Vector2.UP)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_nudge(Vector2.DOWN)
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if is_instance_valid(_brief_panel) and _brief_panel.visible:
				if _mode == "confirmation":
					_on_confirmation_pressed()
				elif _mode == "choice":
					_press_choice()
				else:
					_dismiss_brief()
			else:
				_activate_hotspot(_focus_id)
			get_viewport().set_input_as_handled()

func _nudge(dir: Vector2) -> void:
	if not _marks_ready():
		return
	var before := _focus_id
	_move_focus(dir)
	if _focus_id.is_empty() or _focus_id == before:
		return
	if is_instance_valid(_brief_panel) and _brief_panel.visible:
		_activate_hotspot(_focus_id)


func _move_focus(dir: Vector2) -> void:
	if _mark_points.is_empty():
		return
	var origin := _bg_rect.get_center()
	if _focus_id != "" and _mark_points.has(_focus_id):
		origin = _mark_points[_focus_id]
	var best := _focus_toward(origin, dir, true)
	if best.is_empty():
		best = _focus_toward(origin, dir, false)
	if best.is_empty():
		return
	_focus_id = best
	grab_focus()
	_refresh_marks()


func _focus_toward(origin: Vector2, dir: Vector2, narrow: bool) -> String:
	var best := ""
	var best_distance := 1000000.0
	for id in _mark_points:
		if id == _focus_id:
			continue
		var delta: Vector2 = (_mark_points[id] as Vector2) - origin
		var along := delta.dot(dir)
		if along <= 8.0:
			continue
		if narrow and absf(delta.cross(dir)) > along:
			continue
		var distance := delta.length()
		if distance < best_distance:
			best_distance = distance
			best = str(id)
	return best

func _activate_hotspot(id: String) -> void:
	if not _marks_ready():
		return
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
	if _brief_id.is_empty() or _confirm_button.disabled:
		return
	_mode = "result"
	_confirm_button.hide()
	confirmation_requested.emit(_brief_id)


func _on_option_pressed(option_id: String) -> void:
	if _brief_id.is_empty():
		return
	_mode = "result"
	option_chosen.emit(_brief_id, option_id)

func _dismiss_brief() -> void:
	if is_instance_valid(_brief_panel):
		_brief_panel.hide()
	_brief_closed = true
	_mode = "closed"
	_brief_id = ""
	brief_dismissed.emit()

func skip_enter() -> void:
	_enter_left = 0.0
	_marks_alpha = 1.0
	set_process(false)
	if _built:
		_layout()


func _process(delta: float) -> void:
	if _enter_left <= 0.0:
		_marks_alpha = 1.0
		set_process(false)
		queue_redraw()
		return
	_enter_left = maxf(0.0, _enter_left - delta)
	var elapsed := _ENTER_SEC - _enter_left
	if elapsed < 1.0:
		_marks_alpha = 0.0
	else:
		_marks_alpha = clampf((elapsed - 1.0) / 0.35, 0.0, 1.0)
	_layout()


func show_idle() -> void:
	_mode = "idle"
	_brief_id = ""
	_brief_closed = true
	_clear_choices()
	if is_instance_valid(_brief_panel):
		_brief_panel.hide()
	_refresh_marks()

func show_brief(id: String) -> void:
	if not _hotspots_by_id.has(id):
		show_idle()
		return
	_selected_id = id
	_focus_id = id
	_visited[id] = true
	_brief_closed = false
	var info := _view_info(id)
	var title := _short_name(info, id)
	var body := _body_for(id, info)
	_show_brief(id, title, body, false)
	_refresh_marks()

func show_confirmation(id: String) -> void:
	if not _hotspots_by_id.has(id):
		return
	_selected_id = id
	_focus_id = id
	_visited[id] = true
	var info := _view_info(id)
	var title := _short_name(info, id)
	var body := _two_sentences(_without_routes(_interaction_text(info, "")))
	if body.is_empty():
		body = _two_sentences(str(info.get("text", "")))
	_show_brief(id, title, body, true)
	if str(info.get("mode", "")) == "dismiss":
		_confirm_button.text = "辞退"
		_confirm_button.disabled = false
		_mode = "confirmation"
	elif str(info.get("mode", "")) == "chip" and not bool(info.get("affordable", true)):
		var why := str(info.get("note", "囊中不足"))
		_confirm_button.text = why if why != "" else "囊中不足"
		_confirm_button.disabled = true
		_mode = "brief"
	else:
		_confirm_button.text = str(info.get("label", "确认"))
		_confirm_button.disabled = false
		_mode = "confirmation"
	_refresh_marks()


func show_choices(id: String, options: Array) -> void:
	show_brief(id)
	_clear_choices()
	_confirm_button.hide()
	for opt in options:
		if typeof(opt) != TYPE_DICTIONARY:
			continue
		var button := Button.new()
		button.text = str(opt.get("label", "就这样"))
		button.disabled = not bool(opt.get("open", false))
		if button.disabled:
			var why := str(opt.get("reason", ""))
			button.tooltip_text = why if why != "" else "眼下办不了"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var opt_id := str(opt.get("id", ""))
		button.pressed.connect(_on_option_pressed.bind(opt_id))
		_brief_actions.add_child(button)
		_choice_buttons.append(button)
	_mode = "choice"
	_choice_index = 0
	_focus_choice(0)
	_layout()


func _focus_choice(step: int) -> void:
	if _choice_buttons.is_empty():
		return
	var count := _choice_buttons.size()
	if step == 0:
		for i in count:
			var first: Button = _choice_buttons[i]
			if not first.disabled and is_instance_valid(first):
				_choice_index = i
				first.grab_focus()
				return
		return
	for _i in count:
		_choice_index = posmod(_choice_index + step, count)
		var button: Button = _choice_buttons[_choice_index]
		if is_instance_valid(button) and not button.disabled:
			button.grab_focus()
			return


func _press_choice() -> void:
	if _mode != "choice":
		return
	if _choice_index < 0 or _choice_index >= _choice_buttons.size():
		return
	var button: Button = _choice_buttons[_choice_index]
	if not is_instance_valid(button) or button.disabled:
		return
	_mode = "result"
	button.pressed.emit()

func show_result(id: String, lines: Array = []) -> void:
	_selected_id = id
	_focus_id = id
	if not id.is_empty():
		_visited[id] = true
	var title := "短讯"
	var body := _show_lines(lines)
	if _hotspots_by_id.has(id):
		title = _short_name(_view_info(id), id)
	if body.is_empty():
		body = "事情已经有了结果。"
	_show_brief(id, title, body, false)
	_mode = "result"
	_refresh_marks()

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
	_clear_choices()
	_brief_title.text = title
	_brief_body.text = body
	_confirm_button.text = "确认"
	_confirm_button.disabled = false
	_confirm_button.visible = with_confirmation
	_close_button.visible = true
	_brief_actions.show()
	_brief_panel.show()
	_layout()


func _clear_choices() -> void:
	for button in _choice_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_choice_buttons.clear()
	_choice_index = 0


func _body_for(id: String, info: Dictionary) -> String:
	var again := str(info.get("again", ""))
	var mode := str(info.get("mode", ""))
	if mode == "read":
		var body := again if _looked.has(id) and again != "" else str(info.get("text", ""))
		_looked[id] = true
		return _two_sentences(body)
	if mode == "stamp":
		var reason := str(info.get("reason", info.get("note", "眼下办不了")))
		if again != "" and reason in ["已经办过", "过些日子再来"]:
			return _two_sentences(again)
		if reason == "过些日子再来":
			return _two_sentences(str(info.get("text", reason)))
		return reason
	var body := _interaction_text(info, "")
	if body.is_empty():
		body = str(info.get("text", ""))
	return _two_sentences(_without_routes(body))


func _two_sentences(line: String) -> String:
	var sentences: PackedStringArray = []
	var buf := ""
	var quoted := false
	for i in line.length():
		var ch := line[i]
		if ch == "「":
			quoted = true
		buf += ch
		if ch == "」":
			quoted = false
		elif ch == "。" and not quoted:
			var piece := buf.strip_edges()
			if not piece.is_empty():
				sentences.append(piece)
			buf = ""
			if sentences.size() >= 2:
				break
	if sentences.size() < 2:
		var rest := buf.strip_edges()
		if not rest.is_empty():
			sentences.append(rest)
	if sentences.is_empty():
		return line
	var out := "".join(sentences)
	if not out.ends_with("。") and not out.ends_with("」"):
		out += "。"
	return out


func _without_routes(line: String) -> String:
	var cut := line.find("两路")
	if cut <= 0:
		return line
	var kept := line.substr(0, cut).strip_edges()
	if kept.is_empty():
		return line
	if not kept.ends_with("。") and not kept.ends_with("」"):
		kept += "。"
	return kept


func _draw_mark_tag(id: String, point: Vector2) -> void:
	var tag := str(_view_info(id).get("mark", ""))
	if tag == "":
		return
	var font := ThemeDB.fallback_font
	var font_size := 16
	var text_size := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := point + Vector2(_mark_radius + 8.0, 4.0)
	if pos.x + text_size.x > size.x - 12.0:
		pos.x = point.x - _mark_radius - 8.0 - text_size.x
	if pos.x < 8.0:
		pos.x = 8.0
	var plate := Rect2(pos + Vector2(-4.0, -font_size), text_size + Vector2(8.0, 6.0))
	draw_rect(plate, Color(0.914, 0.863, 0.753, 0.94 * _marks_alpha), true)
	draw_string(font, pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(UiTheme.PAPER_TEXT, _marks_alpha))


func _short_name(info: Dictionary, id: String) -> String:
	var name := str(info.get("name", ""))
	if name != "":
		return name
	var source := str(info.get("source_label", ""))
	if source != "":
		return source
	return str(info.get("label", id))

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
