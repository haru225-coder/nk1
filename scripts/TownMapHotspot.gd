extends Control
class_name TownMapHotspot

signal activated

var _scene_id: String = ""
var _hovered := false

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/Margin/Title
@onready var _hit_button: Button = $HitButton
@onready var _quest_badge: PanelContainer = $QuestBadge

func _ready() -> void:
	_hit_button.pressed.connect(_on_hit_button_pressed)
	_hit_button.mouse_entered.connect(_on_hover.bind(true))
	_hit_button.mouse_exited.connect(_on_hover.bind(false))
	_panel.modulate.a = 0.72

func setup(hotspot: Dictionary, display: Dictionary, scene_id: String) -> void:
	_scene_id = scene_id
	var rect: Array = hotspot.get("rect", [0.0, 0.0, 0.1, 0.1])
	if rect.size() < 4:
		rect = [0.0, 0.0, 0.1, 0.1]

	layout_mode = 1  # Control.LayoutMode.ANCHORS — numeric for Godot 4.6 GDScript compat
	anchor_left = float(rect[0])
	anchor_top = float(rect[1])
	anchor_right = float(rect[0]) + float(rect[2])
	anchor_bottom = float(rect[1]) + float(rect[3])
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var label_text: String = hotspot.get("label", "地点")
	var hint: String = hotspot.get("hint", display.get("text", ""))
	var state: String = display.get("state", "default")
	var is_quest := state == "quest"

	_title.text = label_text
	_panel.theme_type_variation = "FacilityQuestBadge" if is_quest else "FacilityIconFrame"
	_quest_badge.visible = is_quest
	_hit_button.tooltip_text = label_text + (" — " + hint if hint != "" else "")

	if is_quest:
		_title.add_theme_color_override("font_color", Color(0.98, 0.84, 0.42, 1))
	elif state == "done":
		_title.add_theme_color_override("font_color", Color(0.62, 0.6, 0.52, 1))
	else:
		_title.remove_theme_color_override("font_color")

func _on_hover(hovered: bool) -> void:
	_hovered = hovered
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0 if hovered else 0.72, 0.12)
	tween.parallel().tween_property(self, "scale", Vector2(1.06, 1.06) if hovered else Vector2.ONE, 0.12)

func _on_hit_button_pressed() -> void:
	activated.emit()