extends Control
class_name CommandBar

signal command_pressed(action: Dictionary)

const BUTTON_MIN_SIZE := Vector2(88, 84)
const ICON_SIZE := 42
const ICON_BASE := "res://assets/ui/icons/icon_%s.png"
const ICON_FALLBACK_DIR := "res://assets/icons_128/"

@onready var _flow: HBoxContainer = $Background/Margin/Scroll/Flow

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
	var scene_type: String = scene_data.get("type", template_key)

	_add_facility_buttons(template, scene_data, port_location, hotspot_by_facility)
	_add_static_actions(template.get("static_actions", []), scene_type)
	_add_choice_buttons(template, scene_data)
	_add_mode_actions(scene_type, port_location)

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
		var icon := _resolve_command_icon(fac_id, fac)
		_add_button(
			label,
			icon,
			{"type": "navigate", "target": target},
			is_quest,
		)

func _add_static_actions(actions: Array, scene_type: String) -> void:
	for raw: Dictionary in actions:
		if not raw.get("always_visible", true):
			continue
		var id: String = raw.get("id", "")
		var icon_path: String = raw.get("icon", "")
		var tex: Texture2D = null
		if icon_path != "":
			tex = AssetPlaceholder.load_texture(icon_path, "texture")
		if tex == null and id != "":
			tex = _resolve_command_icon(id, {})
		var label: String = raw.get("label", "")
		_add_button(
			label,
			tex,
			{
				"type": raw.get("type", "navigate"),
				"id": id,
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

## 根据当前场景模式追加常用操作（如返回港口）
func _add_mode_actions(scene_type: String, port_location: String) -> void:
	if scene_type == "investigation" or scene_type == "facility":
		var return_target := ""
		if GameState.last_port != "":
			return_target = GameManager.get_port_scene_id(GameState.last_port)
		if return_target == "":
			return_target = "port_quanzhou"
		_add_button(
			"返港",
			_resolve_command_icon("return", {}),
			{"type": "navigate", "target": return_target},
			false,
		)

func _resolve_command_icon(id: String, fac: Dictionary) -> Texture2D:
	# 1. 新 UI 图标目录
	var tex := AssetPlaceholder.load_texture(ICON_BASE % id, "texture")
	if tex:
		return tex

	# 2. 设施显式配置
	var configured: String = fac.get("icon", "") if fac else ""
	if configured != "":
		tex = AssetPlaceholder.load_texture(configured, "texture")
		if tex:
			return tex

	# 3. 128x128 KOEI 风格图标目录
	var fallback_path: String = ICON_FALLBACK_DIR + "icon_" + id + "_koei.png"
	tex = AssetPlaceholder.load_texture(fallback_path, "texture")
	if tex:
		return tex

	# 4. 静态图标兜底（地图、返回等）
	var static_paths := {
		"log": "res://assets/icons_stat/icon_stat_location.png",
		"sail": "res://assets/icon_shipyard_koei.png",
		"return": "res://assets/icon_wharf_koei.png",
	}
	if static_paths.has(id):
		tex = AssetPlaceholder.load_texture(static_paths[id], "texture")
		if tex:
			return tex

	return null

func _add_button(label_text: String, icon: Texture2D, action: Dictionary, highlight: bool) -> void:
	var btn := UIBuilder.make_button("", UITheme.BTN_COMMAND)
	btn.custom_minimum_size = BUTTON_MIN_SIZE
	btn.tooltip_text = label_text
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if highlight:
		btn.modulate = Color(1.15, 1.08, 0.88, 1.0)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 3)

	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = icon
		icon_rect.modulate = Color(1.0, 0.96, 0.82, 1.0) if highlight else Color(0.94, 0.9, 0.78, 1.0)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon_rect)

	var caption := Label.new()
	caption.custom_minimum_size = Vector2(BUTTON_MIN_SIZE.x - 14.0, 28.0)
	caption.text = label_text
	caption.theme_type_variation = UITheme.LABEL_COMMAND_CAPTION_HIGHLIGHT if highlight else UITheme.LABEL_COMMAND_CAPTION
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.clip_text = true
	caption.max_lines_visible = 2
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
