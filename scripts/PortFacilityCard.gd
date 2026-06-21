extends Control
class_name PortFacilityCard

signal facility_pressed

const CARD_MIN_SIZE := Vector2(176, 212)

@onready var card_panel: PanelContainer = $CardPanel
@onready var icon_texture: TextureRect = %IconTexture
@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var hit_button: Button = $HitButton
@onready var quest_badge: PanelContainer = $QuestBadge

var _hover_tween: Tween
var _hovered := false

func _ready() -> void:
	custom_minimum_size = CARD_MIN_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pivot_offset = CARD_MIN_SIZE * 0.5
	hit_button.pressed.connect(func(): facility_pressed.emit())
	hit_button.mouse_entered.connect(_on_hover.bind(true))
	hit_button.mouse_exited.connect(_on_hover.bind(false))
	hit_button.button_down.connect(_on_press.bind(true))
	hit_button.button_up.connect(_on_press.bind(false))

func setup(fac: Dictionary, display: Dictionary, icon: Texture2D) -> void:
	var text: String = display.get("text", "点击进入")
	var state: String = display.get("state", "default")
	var is_quest := state == "quest"
	var is_done := state == "done"

	title_label.text = fac.get("title", "未命名地点")
	subtitle_label.text = text.replace("★ ", "")
	icon_texture.texture = icon
	if is_done:
		icon_texture.modulate = Color(0.72, 0.72, 0.72, 1)
	else:
		icon_texture.modulate = Color.WHITE

	card_panel.theme_type_variation = "PortFacilityCardQuest" if is_quest else "PortFacilityCard"
	quest_badge.visible = is_quest

	if is_quest:
		subtitle_label.add_theme_color_override("font_color", Color(0.98, 0.84, 0.42, 1))
	elif is_done:
		subtitle_label.add_theme_color_override("font_color", Color(0.62, 0.6, 0.52, 1))
	else:
		subtitle_label.remove_theme_color_override("font_color")

	set_meta("is_quest", is_quest)

func _kill_hover_tween() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null

func _on_hover(hovered: bool) -> void:
	_hovered = hovered
	_kill_hover_tween()
	var is_quest: bool = get_meta("is_quest", false)
	var target_scale := Vector2(1.07, 1.07) if hovered else Vector2.ONE
	var target_modulate := Color(1.12, 1.08, 0.98) if hovered else Color.WHITE
	if is_quest and hovered:
		target_modulate = Color(1.14, 1.1, 0.92)
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target_scale, 0.16)
	_hover_tween.tween_property(card_panel, "modulate", target_modulate, 0.16)
	z_index = 3 if hovered else 0

func _on_press(pressed: bool) -> void:
	if pressed:
		scale = Vector2(0.96, 0.96)
	else:
		scale = Vector2(1.07, 1.07) if _hovered else Vector2.ONE