extends Control

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)

@onready var port_title: Label = $TitleBanner/PortTitle
@onready var facility_grid: HBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid
@onready var left_column: VBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid/LeftColumn
@onready var right_column: VBoxContainer = $FacilityHub/Margin/VBox/FacilityGrid/RightColumn
@onready var facility_hint: Label = $FacilityHub/Margin/VBox/FacilityHint
@onready var town_map_view: TownMapView = $FacilityHub/Margin/VBox/TownMapView
@onready var port_actions_label: Label = $FacilityHub/Margin/VBox/PortActionsLabel
@onready var port_choices_container: VBoxContainer = $FacilityHub/Margin/VBox/PortChoicesContainer

var _current_port_id: String = ""
var _use_town_map: bool = false

func setup(scene_data: Dictionary, port_id: String) -> void:
	_current_port_id = scene_data.get("location", port_id.replace("port_", ""))
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

	_clear_port_choices()
	status_updated.emit()

func _show_town_map(town_map: Dictionary, facilities: Array) -> int:
	facility_grid.visible = false
	town_map_view.visible = true
	facility_hint.visible = false
	return town_map_view.setup(town_map, facilities, _current_port_id)

func _show_facility_grid(facilities: Array) -> void:
	_use_town_map = false
	town_map_view.visible = false
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

func _populate_column(column: VBoxContainer, facs: Array) -> void:
	for fac in facs:
		var slot := _make_facility_slot(fac)
		column.add_child(slot)

func _make_facility_slot(fac: Dictionary) -> Control:
	var available: bool = GameManager.facility_available(fac)
	var display: Dictionary = GameManager.resolve_facility_subtitle(fac)
	var icon: Texture2D = GameManager.resolve_facility_icon(fac)
	var state: String = display.get("state", "default")
	var is_quest := state == "quest"
	var is_done := state == "done"

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(0, 88)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme_type_variation = &"PortFacilityCardQuest" if is_quest else &"PortFacilityCard"

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(72, 72)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture = icon
	if available:
		if is_done:
			tex_rect.modulate = Color(0.72, 0.72, 0.72, 1)
		else:
			tex_rect.modulate = Color(1, 1, 1, 1.0)
	else:
		tex_rect.modulate = Color(0.5, 0.5, 0.5, 0.7)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_lbl := Label.new()
	title_lbl.theme_type_variation = &"FacilityTitle"
	title_lbl.text = fac.get("name", fac.get("title", fac.get("id", "")))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sub_lbl := Label.new()
	sub_lbl.theme_type_variation = &"FacilitySubtitle"
	sub_lbl.text = display.get("text", "").replace("★ ", "")
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_quest:
		sub_lbl.add_theme_color_override("font_color", Color(0.98, 0.84, 0.42, 1))
	elif is_done:
		sub_lbl.add_theme_color_override("font_color", Color(0.62, 0.6, 0.52, 1))

	vbox.add_child(title_lbl)
	vbox.add_child(sub_lbl)
	hbox.add_child(tex_rect)
	hbox.add_child(vbox)
	margin.add_child(hbox)
	panel.add_child(margin)

	var hit_button := Button.new()
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_button.flat = true
	hit_button.theme_type_variation = &"FacilityCardButton"
	hit_button.disabled = not available
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit_button.pressed.connect(_on_facility_pressed.bind(fac))

	wrapper.add_child(panel)
	wrapper.add_child(hit_button)
	return wrapper

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