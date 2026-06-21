extends Control
class_name CommandBar

signal command_pressed(action: Dictionary)

const BUTTON_MIN_SIZE := Vector2(68, 72)
const ICON_SIZE := 36

@onready var _flow: HBoxContainer = $Margin/Scroll/Flow

var _templates: Dictionary = {}

func _ready() -> void:
	_templates = GameManager.ui_commands_data.get("templates", {})

func build(command_spec: Dictionary) -> void:
	_clear()
	var template_key: String = command_spec.get("template", "")
	if template_key == "" or not _templates.has(template_key):
		visible = false
		return

	var template: Dictionary = _templates[template_key]
	var scene_data: Dictionary = command_spec.get("scene_data", {})
	var port_location: String = command_spec.get("port_location", "")
	var town_map: Dictionary = scene_data.get("town_map", {})
	var hotspot_by_facility := _hotspot_index(town_map)

	_add_facility_buttons(template, scene_data, port_location, hotspot_by_facility)
	_add_static_actions(template.get("static_actions", []))
	_add_choice_buttons(template, scene_data)

	visible = _flow.get_child_count() > 0

func _hotspot_index(town_map: Dictionary) -> Dictionary:
	var linked: Dictionary = {}
	for hotspot in town_map.get("hotspots", []):
		var fac_id: String = hotspot.get("facility_id", "")
		if fac_id != "":
			linked[fac_id] = hotspot
	return linked

func _add_facility_buttons(
	template: Dictionary,
	scene_data: Dictionary,
	port_location: String,
	hotspot_by_facility: Dictionary,
) -> void:
	if not template.has("facility_source"):
		return
	for fac: Dictionary in scene_data.get("facilities", []):
		if not GameManager.facility_available(fac):
			continue
		var fac_id: String = fac.get("id", "")
		var target: String
		if hotspot_by_facility.has(fac_id):
			target = GameManager.resolve_hotspot_scene(hotspot_by_facility[fac_id], fac, port_location)
		else:
			target = GameManager.resolve_facility_scene(fac, port_location)
		if target == "":
			continue
		var display := GameManager.resolve_facility_subtitle(fac)
		var is_quest: bool = str(display.get("state", "")) == "quest"
		var label: String = fac.get("title", "地点")
		if is_quest:
			label = "★ " + label
		_add_button(
			label,
			GameManager.resolve_facility_icon(fac),
			{"type": "navigate", "target": target},
			is_quest,
		)

func _add_static_actions(actions: Array) -> void:
	for raw: Dictionary in actions:
		if not raw.get("always_visible", true):
			continue
		var icon_path: String = raw.get("icon", "")
		var tex: Texture2D = null
		if icon_path != "":
			tex = AssetPlaceholder.load_texture(icon_path, "texture")
		_add_button(
			raw.get("label", ""),
			tex,
			{
				"type": raw.get("type", "navigate"),
				"id": raw.get("id", ""),
				"target": raw.get("target", ""),
			},
			false,
		)

func _add_choice_buttons(template: Dictionary, scene_data: Dictionary) -> void:
	if not template.has("choice_source"):
		return
	for choice: Dictionary in scene_data.get("choices", []):
		if not GameManager.choice_available(choice):
			continue
		var style: String = GameManager.resolve_choice_style(choice)
		var label: String = choice.get("label", "继续")
		if style == "sail" or style == "travel":
			label = "★ " + label
		var action := {
			"type": "navigate",
			"target": choice.get("next", ""),
			"effects": choice.get("effects", {}),
			"narration": choice.get("narration", ""),
		}
		_add_button(label, null, action, style == "sail")

func _add_button(label_text: String, icon: Texture2D, action: Dictionary, highlight: bool) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = BUTTON_MIN_SIZE
	btn.theme_type_variation = "SetSailButton" if highlight else "ChoiceButton"
	btn.tooltip_text = label_text

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)

	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = icon
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon_rect)

	var caption := Label.new()
	caption.text = label_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if highlight:
		caption.add_theme_color_override("font_color", Color(0.98, 0.84, 0.42, 1))
	vbox.add_child(caption)

	btn.add_child(vbox)
	btn.pressed.connect(_on_button_pressed.bind(action))
	_flow.add_child(btn)

func _on_button_pressed(action: Dictionary) -> void:
	if GameManager.input_locked:
		return
	command_pressed.emit(action)

func _clear() -> void:
	for child in _flow.get_children():
		child.queue_free()