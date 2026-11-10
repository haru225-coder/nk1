extends Control
class_name DistrictHotspotView

signal hotspot_selected(id)
signal confirmation_requested(id)
signal brief_dismissed

const UiTheme = preload("res://scripts/core/UiTheme.gd")
const IDLE_BRIEF := "后渚是泉州出洋的码头。"

var _port_id := ""
var _district_id := ""
var _hotspots: Array = []
var _interactions_view: Variant = null

var _background_layer: Control
var _hotspot_layer: Control
var _brief_layer: Control
var _background: TextureRect
var _brief: PanelContainer
var _brief_title: Label
var _brief_body: Label
var _actions: HBoxContainer
var _confirm_button: Button
var _cancel_button: Button
var _close_button: Button

var _marks: Dictionary = {}
var _visited: Dictionary = {}
var _selected_id := ""
var _background_rect := Rect2()
var _ready_built := false

class InkDotButton:
	extends Button

	var visited := false
	var selected := false
	var ink := Color("292722")
	var muted := Color("777064")
	var cinnabar := Color("a34832")
	var focus_ink := Color("386b68")

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var point := Vector2(18.0, size.y * 0.5)
		var state := _state()
		var color := _state_color(state)
		var radius := 5.0
		if state == "hover":
			radius = 6.5
		elif state == "pressed":
			radius = 4.0
			point.y += 1.0
		elif state == "selected":
			radius = 7.0
		elif state == "visited":
			radius = 4.5
		if state == "visited":
			draw_arc(point, radius, 0.0, TAU, 24, color, 1.4, true)
		else:
			draw_circle(point, radius, color)
		if state == "hover" or state == "focus" or state == "selected":
			draw_arc(point, radius + 4.0, 0.0, TAU, 40, color, 1.2, true)
		if state == "focus":
			draw_arc(point, radius + 7.0, 0.0, TAU, 32, focus_ink, 1.2)

	func _state() -> String:
		if is_pressed():
			return "pressed"
		if selected:
			return "selected"
		if has_focus():
			return "focus"
		if is_hovered():
			return "hover"
		if visited:
			return "visited"
		return "normal"

	func _state_color(state: String) -> Color:
		match state:
			"hover":
				return Color("9a4f37")
			"focus":
				return focus_ink
			"pressed":
				return Color("171512")
			"visited":
				return Color("746d60")
			"selected":
				return cinnabar
		return Color("302d28")

func _ready() -> void:
	_build()
	_ready_built = true
	_apply_setup()

func setup(port_id: String, dist_id: String, bg_path: String, hotspots: Array, interactions_view) -> void:
	_port_id = port_id
	_district_id = dist_id
	_bg_path = bg_path
	_hotspots = hotspots.duplicate(true)
	_interactions_view = interactions_view
	if _ready_built:
		_apply_setup()

func show_idle(text: String = IDLE_BRIEF) -> void:
	_selected_id = ""
	_refresh_marks()
	_show_brief("后渚码头", [text], "", "", "")

func show_brief(id: String, title: String, lines: Array) -> void:
	var clean: Array = []
	for line in lines.slice(0, 2):
		var text := str(line).strip_edges()
		if not text.is_empty():
			clean.append(text)
	_selected_id = id
	_refresh_marks()
	_show_brief(title, clean, "", "", "")

func show_confirmation(id: String, title: String, note: String, confirm_text: String, cancel_text: String = "取消") -> void:
	_selected_id = id
	_refresh_marks()
	_show_brief(title, [note] if not note.is_empty() else [], confirm_text, cancel_text, "")

func show_result(text: String) -> void:
	_show_brief(_brief_title.text, [_first_sentence(text)], "", "", "")

func clear_selection() -> void:
	_selected_id = ""
	show_idle()

func focus_hotspot(id: String) -> void:
	var button: Button = _marks.get(id)
	if is_instance_valid(button):
		button.grab_focus()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background_layer = Control.new()
	_background_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_layer)
	_background_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_layer.add_child(_background)

	_hotspot_layer = Control.new()
	_hotspot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotspot_layer)
	_hotspot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_brief_layer = Control.new()
	_brief_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_brief_layer)
	_brief_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_brief()

func _build_brief() -> void:
	_brief_panel = PanelContainer.new()
	_brief_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_brief_layer.add_child(_brief_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f2ead9")
	style.border_color = Color("9b8d75")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	_brief_panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_brief_panel.add_child(box)

	_brief_title = Label.new()
	_brief_title.add_theme_font_override("font", _font(20))
	box.add_child(_brief_title)

	_brief_body = Label.new()
	_brief_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_brief_body.add_theme_font_size_override("font_size", 16)
	_brief_body.add_theme_color_override("font_color", Color("332f29"))
	box.add_child(_brief_body)

	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	box.add_child(_actions)

	_confirm_button = Button.new()
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_actions.add_child(_confirm_button)

	_cancel_button = Button.new()
	_cancel_button.pressed.connect(func(): show_idle())
	_actions.add_child(_cancel_button)

	_close_button = Button.new()
	_close_button.text = "合上"
	_close_button.pressed.connect(func(): brief_closed.emit())
	_actions.add_child(_close_button)

func _apply_setup() -> void:
	if not is_instance_valid(_background):
		return
	_background.texture = null
	if not _bg_path.is_empty() and ResourceLoader.exists(_bg_path):
		var resource := load(_bg_path)
		if resource is Texture2D:
			_background.texture = resource
	_rebuild_marks()
	_layout()
	show_idle()

func _build_marks() -> void:
	_marks.clear()
	for child in _hotspot_layer.get_children():
		child.queue_free()
	for hotspot in _hotspots:
		var id := str(hotspot.get("id", ""))
		var button := InkDotButton.new()
		button.text = ""
		button.tooltip_text = str(hotspot.get("label", id))
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", _transparent_style())
		button.add_theme_style_override("hover", _transparent_style())
		button.add_theme_style_override("pressed", _transparent_style())
		button.add_theme_style_override("focus", _transparent_style())
		button.pressed.connect(_on_hotspot_pressed.bind(id))
		_hotspot_layer.add_child(button)
		var name_label := Label.new()
		name_label.text = str(hotspot.get("label", id))
		name_label.position = Vector2(32, 8)
		name_label.size = Vector2(144, 28)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_override("font", _font(16))
		name_label.add_theme_color_override("font_color", Color("f4eddc"))
		name_label.add_theme_color_override("font_shadow_color", Color("2b2822"))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		button.add_child(name_label)
		_marks[id] = button
	_layout_marks()

func _on_hotspot_pressed(id: String) -> void:
	_selected_id = id
	_visited[id] = true
	for mark_id in _marks:
		var mark: Button = _marks[mark_id]
		mark.selected = mark_id == id
		mark.queue_redraw()
	_update_brief_for(id)
	hotspot_selected.emit(id)

func _update_brief(id: String) -> void:
	var info := _view_info(id)
	if info.is_empty():
		_show_lines(id, [id, "此处可以问一声。"])
		return
	var title := str(info.get("title", info.get("label", id)))
	var lines: Array = info.get("lines", [])
	if lines.is_empty():
		var text := str(info.get("text", ""))
		lines = [_first_sentence(text)] if not text.is_empty() else ["此处可以问一声。"]
	_show_brief(title, lines, str(info.get("confirm_text", "")), str(info.get("cancel_text", "")))

func _show_brief(title: String, lines: Array, confirm_text: String, cancel_text: String) -> void:
	_brief_title.text = title
	_brief_body.text = "\n".join(lines.slice(0, 2))
	_confirm_button.text = confirm_text
	_cancel_button.text = cancel_text
	_actions.visible = not confirm_text.is_empty()
	_brief_panel.visible = true
	_layout_brief()

func _on_confirm_pressed() -> void:
	if not _brief_id.is_empty():
		confirmation_requested.emit(_selected_id)

func _on_brief_closed() -> void:
	brief_closed.emit()

func _layout() -> void:
	if not _built:
		return
	var texture := _background.texture
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		_background_rect = Rect2(Vector2.ZERO, size)
	else:
		var texture_size := texture.get_size()
		var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y)
		var shown := texture_size * scale_factor
		_background_rect = Rect2((size - shown) * 0.5, shown)
	_background.position = _background_rect.position
	_background.size = _background_rect.size
	for id in _marks:
		var mark := _marks[id]
		var data: Dictionary = _hotspots_by_id.get(id, {})
		var point := Vector2(float(data.get("x", 0.0)), float(data.get("y", data.get("x", 0.0))))
		mark.position = _background_rect.position + point * _background_rect.size - Vector2(18, 22)
		mark.custom_minimum_size = Vector2(190, 44)
		mark.size = Vector2(190, 44)
	_layout_brief()

func _layout_brief() -> void:
	if _brief_panel == null:
		return
	var minimum := _brief.get_combined_minimum_size()
	var wide := size.x >= 820.0 and size.x > size.y * 1.25
	var panel_size := Vector2(minf(350.0, size.x * 0.34), minf(maxf(minimum.y, 132.0), size.y - 32.0))
	var candidates: Array[Vector2] = []
	if wide:
		panel_size.x = clampf(size.x * 0.30, 280.0, 360.0)
		panel_size.y = minf(panel_size.y, size.y - 24.0)
		candidates.append(Vector2(size.x - panel_size.x - 16.0, (size.y - panel_size.y) * 0.5))
		candidates.append(Vector2(16.0, (size.y - panel_size.y) * 0.5))
	else:
		panel_size.x = maxf(0.0, size.x - 24.0)
		panel_size.y = minf(panel_size.y, maxf(96.0, size.y * 0.42))
		candidates.append(Vector2(12.0, size.y - panel_size.y - 12.0))
		candidates.append(Vector2(12.0, 12.0))
	var chosen := candidates[0]
	for candidate in candidates:
		var rect := Rect2(candidate, panel_size)
		if _selected_id.is_empty() or not rect.grow(10.0).has_point(_mark_point(_selected_id)):
			chosen = candidate
			break
	_brief.position = chosen.max(Vector2(8, 8))
	_brief.size = panel_size.min(size - _brief.position - Vector2(8, 8))

func _mark_point(id: String) -> Vector2:
	for hotspot in _hotspots:
		if str(hotspot.get("id", "")) == id:
			return _bg_rect.position + Vector2(float(hotspot.get("x", 0.0)), float(hotspot.get("y", 0.0))) * _bg.size
	return Vector2.ZERO

func _show_for_interaction(id: String) -> void:
	var item := _find_interaction(id)
	var title := str(item.get("label", id))
	var text := str(item.get("text", ""))
	if text.is_empty():
		text = str(item.get("label", id))
	_show_brief(title, [_first_sentence(text)], "", "")

func _find_interaction(id: String) -> Dictionary:
	if interactions_view is Dictionary:
		var value: Variant = interactions_view.get(id, {})
		return value if value is Dictionary else {}
	if interactions_view is Array:
		for item in interactions_view:
			if item is Dictionary and str(item.get("id", "")) == id:
				return item
	return {}

func _first_sentence(text: String) -> String:
	var end := text.length()
	for mark in ["。", "！", "？", "\n"]:
		var at := text.find(mark)
		if at >= 0:
			end = mini(end, at + 1)
	return text.substr(0, end).strip_edges()

func _apply_font(control: Control, font_size: int) -> void:
	if UiTheme.has_method("font"):
		var font: Variant = UiTheme.call("font", font_size)
		if font is Font:
			control.add_theme_font_override("font", font)
			return
	control.add_theme_font_override("font", ThemeDB.fallback_font)
	control.add_theme_font_size_override("font_size", font_size)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout()
