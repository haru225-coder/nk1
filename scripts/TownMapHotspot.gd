extends Control
class_name TownMapHotspot

signal activated

const IDLE_ALPHA := 0.22           ## 太阁风格：默认状态下建筑轮廓微显
const HOVER_ALPHA := 0.92          ## 悬停时高亮
const DONE_ALPHA := 0.35           ## 已完成/不可用的建筑整体变淡
const QUEST_PULSE_MIN := 0.65      ## 任务呼吸灯最小 alpha
const QUEST_PULSE_MAX := 1.0       ## 任务呼吸灯最大 alpha

var _scene_id: String = ""
var _hovered := false
var _is_quest := false
var _is_done := false

@onready var _title_panel: PanelContainer = $TitlePanel
@onready var _title: Label = $TitlePanel/Title
@onready var _hit_button: Button = $HitButton
@onready var _hover_border: NinePatchRect = $HoverBorder
@onready var _quest_star: TextureRect = $QuestStar
@onready var _icon_rect: TextureRect = $IconRect

func _ready() -> void:
	_hit_button.pressed.connect(_on_hit_button_pressed)
	_hit_button.mouse_entered.connect(_on_hover.bind(true))
	_hit_button.mouse_exited.connect(_on_hover.bind(false))

	# 太阁风格：默认显示淡淡轮廓，让玩家感知到可交互建筑
	_hover_border.visible = true
	_hover_border.modulate.a = IDLE_ALPHA
	_title_panel.visible = true
	_title_panel.modulate.a = 0.0
	_title_panel.position.y = -8.0

func setup(hotspot: Dictionary, display: Dictionary, scene_id: String, fac: Dictionary = {}) -> void:
	_scene_id = scene_id
	var rect: Array = hotspot.get("rect", [0.0, 0.0, 0.1, 0.1])
	if rect.size() < 4:
		rect = [0.0, 0.0, 0.1, 0.1]

	layout_mode = 1
	anchor_left = float(rect[0])
	anchor_top = float(rect[1])
	anchor_right = float(rect[0]) + float(rect[2])
	anchor_bottom = float(rect[1]) + float(rect[3])
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	pivot_offset = size * 0.5

	var label_text: String = hotspot.get("label", "地点")
	var hint: String = hotspot.get("hint", display.get("text", ""))
	var state: String = display.get("state", "default")
	_is_quest = state == "quest"
	_is_done = state == "done"

	_title.text = label_text
	_hit_button.tooltip_text = label_text + (" — " + hint if hint != "" else "")

	# 太阁风格：在建筑中心显示设施小图标
	var icon_tex := _resolve_hotspot_icon(fac)
	if icon_tex:
		_icon_rect.texture = icon_tex
		_icon_rect.visible = true
		# 根据热点高度自适应图标大小，避免小热点溢出
		var icon_size := clampi(int(size.y * 0.42), 24, 40)
		_icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
	else:
		_icon_rect.visible = false

	if _is_quest:
		_title.add_theme_color_override("font_color", GameColors.TEXT_GOLD)
		_hover_border.modulate = GameColors.TEXT_GOLD
		_hover_border.modulate.a = IDLE_ALPHA + 0.12
		_quest_star.visible = true
	elif _is_done:
		_title.add_theme_color_override("font_color", GameColors.TEXT_DIM)
		modulate = Color(1, 1, 1, DONE_ALPHA)
		_hover_border.modulate.a = IDLE_ALPHA * 0.6
		_quest_star.visible = false
	else:
		_title.remove_theme_color_override("font_color")
		_hover_border.modulate = Color.WHITE
		_hover_border.modulate.a = IDLE_ALPHA
		_quest_star.visible = false

	_start_idle_effects()

func _resolve_hotspot_icon(fac: Dictionary) -> Texture2D:
	if fac.is_empty():
		return null
	var configured: String = fac.get("icon", "")
	if configured != "":
		var tex := AssetPlaceholder.load_texture(configured, "texture")
		if tex:
			return tex
	if GameManager.has_method("resolve_facility_icon"):
		return GameManager.resolve_facility_icon(fac)
	return null

func _start_idle_effects() -> void:
	# 任务建筑：金色呼吸灯 + 星标轻微浮动
	if _is_quest:
		var pulse := create_tween().set_loops()
		pulse.tween_property(_hover_border, "modulate:a", QUEST_PULSE_MAX, 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_hover_border, "modulate:a", QUEST_PULSE_MIN, 0.9).set_trans(Tween.TRANS_SINE)

		var star_float := create_tween().set_loops()
		star_float.tween_property(_quest_star, "position:y", _quest_star.position.y - 3.0, 0.7).set_trans(Tween.TRANS_SINE)
		star_float.tween_property(_quest_star, "position:y", _quest_star.position.y, 0.7).set_trans(Tween.TRANS_SINE)

func _on_hover(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered

	if has_meta("hover_tween"):
		var old_tween = get_meta("hover_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	var tween := create_tween().set_parallel(true)
	set_meta("hover_tween", tween)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 悬停放大 + 高亮；太阁风格建筑会被「托起来」
	var target_scale := Vector2(1.06, 1.06) if hovered else Vector2.ONE
	var target_border_alpha := HOVER_ALPHA if hovered else (IDLE_ALPHA + 0.12 if _is_quest else IDLE_ALPHA)
	var target_title_alpha := 1.0 if hovered else 0.0
	var target_title_y := 0.0 if hovered else -8.0

	tween.tween_property(self, "scale", target_scale, 0.14)
	tween.tween_property(_hover_border, "modulate:a", target_border_alpha, 0.14)
	tween.tween_property(_title_panel, "modulate:a", target_title_alpha, 0.12)
	tween.tween_property(_title_panel, "position:y", target_title_y, 0.12)

	if hovered and _is_quest:
		tween.tween_property(_quest_star, "scale", Vector2(1.15, 1.15), 0.14)
	elif not hovered:
		tween.tween_property(_quest_star, "scale", Vector2.ONE, 0.14)

func _on_hit_button_pressed() -> void:
	# 点击反馈：快速缩放后恢复
	var click_tween := create_tween()
	click_tween.tween_property(self, "scale", Vector2(0.96, 0.96), 0.05).set_trans(Tween.TRANS_CUBIC)
	click_tween.tween_property(self, "scale", Vector2.ONE if not _hovered else Vector2(1.06, 1.06), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	activated.emit()
