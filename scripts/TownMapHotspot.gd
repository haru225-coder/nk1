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

var _icon_plate: PanelContainer = null
var _pending_fac: Dictionary = {}

func _ready() -> void:
	_hit_button.pressed.connect(_on_hit_button_pressed)
	_hit_button.mouse_entered.connect(_on_hover.bind(true))
	_hit_button.mouse_exited.connect(_on_hover.bind(false))

	# 悬停边框：古风淡金，默认隐藏
	_hover_border.visible = false
	_hover_border.modulate = Color(1.0, 0.92, 0.55, 0.55)
	# 城镇界画风格：牌匾常驻显示
	_title_panel.visible = true
	_title_panel.modulate.a = 0.92

	_title_panel.theme_type_variation = UITheme.TOWN_HOTSPOT_PANEL
	_title.theme_type_variation = UITheme.TOWN_HOTSPOT_TITLE
	_title_panel.position.y = -24.0
	_title_panel.z_index = 2
	if _quest_star:
		_quest_star.z_index = 3
	if _icon_rect:
		_icon_rect.z_index = 1
	if _hover_border:
		_hover_border.z_index = 0

	_ensure_icon_plate()

func setup(hotspot: Dictionary, display: Dictionary, scene_id: String, fac: Dictionary = {}) -> void:
	_scene_id = scene_id
	_pending_fac = fac.duplicate(true) if fac is Dictionary else {}
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

	var label_text: String = hotspot.get("label", "地点")
	var hint: String = hotspot.get("hint", display.get("text", ""))
	var state: String = display.get("state", "default")
	_is_quest = state == "quest"
	_is_done = state == "done"

	_title.text = label_text
	_hit_button.tooltip_text = label_text + (" — " + hint if hint != "" else "")

	if _is_quest:
		_title.theme_type_variation = UITheme.TOWN_HOTSPOT_TITLE_QUEST
		_title_panel.theme_type_variation = UITheme.TOWN_HOTSPOT_PANEL_QUEST
		_title_panel.modulate = Color(1.15, 1.1, 1.0, 1.0)
		_quest_star.visible = true
	elif _is_done:
		_title.theme_type_variation = UITheme.TOWN_HOTSPOT_TITLE_DONE
		modulate = Color(1, 1, 1, DONE_ALPHA)
		_quest_star.visible = false
	else:
		_title.theme_type_variation = UITheme.TOWN_HOTSPOT_TITLE
		_quest_star.visible = false

	_start_idle_effects()
	# 等布局算完 size 再放图标，避免 size=0 导致图标过小/不可见
	call_deferred("_finalize_icon_layout")

func _finalize_icon_layout() -> void:
	pivot_offset = size * 0.5
	var icon_tex := _resolve_hotspot_icon(_pending_fac)
	if icon_tex == null:
		_icon_rect.visible = false
		if _icon_plate:
			_icon_plate.visible = false
		return
	var h := maxf(size.y, 56.0)
	# 略收图标，避免盖住建筑剪影
	var icon_size := clampi(int(h * 0.42), 28, 46)
	var half := icon_size * 0.5
	_icon_rect.texture = icon_tex
	_icon_rect.visible = true
	_icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
	_icon_rect.offset_left = -half
	_icon_rect.offset_top = -half
	_icon_rect.offset_right = half
	_icon_rect.offset_bottom = half
	if _is_done:
		_icon_rect.modulate = Color(0.75, 0.72, 0.68, 0.7)
	elif _is_quest:
		_icon_rect.modulate = Color(1.08, 1.0, 0.78, 1.0)
	else:
		_icon_rect.modulate = Color(1.0, 0.96, 0.82, 0.96)
	_icon_rect.pivot_offset = Vector2(half, half)
	_style_icon_plate(icon_size + 10)

func _ensure_icon_plate() -> void:
	if _icon_plate != null and is_instance_valid(_icon_plate):
		return
	_icon_plate = PanelContainer.new()
	_icon_plate.name = "IconPlate"
	_icon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_plate.layout_mode = 1
	_icon_plate.anchors_preset = Control.PRESET_CENTER
	_icon_plate.anchor_left = 0.5
	_icon_plate.anchor_top = 0.5
	_icon_plate.anchor_right = 0.5
	_icon_plate.anchor_bottom = 0.5
	_icon_plate.visible = false
	# 插在 IconRect 之前
	var idx := _icon_rect.get_index() if _icon_rect else get_child_count()
	add_child(_icon_plate)
	move_child(_icon_plate, maxi(idx, 0))

func _style_icon_plate(plate_size: int) -> void:
	_ensure_icon_plate()
	if _icon_plate == null:
		return
	var half := plate_size * 0.5
	_icon_plate.offset_left = -half
	_icon_plate.offset_top = -half
	_icon_plate.offset_right = half
	_icon_plate.offset_bottom = half
	_icon_plate.custom_minimum_size = Vector2(plate_size, plate_size)
	# [豁免] 图标盘直径和任务/完成状态在运行时由热点尺寸决定，无法静态定义。
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.055, 0.07, 0.82)
	if _is_quest:
		style.border_color = Color(0.98, 0.84, 0.42, 0.95)
		style.set_border_width_all(2)
	elif _is_done:
		style.border_color = Color(0.5, 0.45, 0.35, 0.55)
		style.set_border_width_all(1)
	else:
		style.border_color = Color(0.82, 0.62, 0.24, 0.88)
		style.set_border_width_all(2)
	style.set_corner_radius_all(plate_size)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 5
	_icon_plate.add_theme_stylebox_override("panel", style)
	_icon_plate.visible = true
	_icon_plate.modulate = Color(1, 1, 1, 0.9 if not _is_done else 0.65)
	_icon_plate.z_index = 0

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
		pulse.tween_property(_title_panel, "modulate:v", 1.5, 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(_title_panel, "modulate:v", 1.0, 0.9).set_trans(Tween.TRANS_SINE)

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
	var target_scale := Vector2(1.07, 1.07) if hovered else Vector2.ONE
	var target_title_alpha := 1.0 if hovered else 0.92
	var target_title_y := -28.0 if hovered else -24.0

	tween.tween_property(self, "scale", target_scale, 0.14)
	tween.tween_property(_title_panel, "modulate:a", target_title_alpha, 0.12)
	tween.tween_property(_title_panel, "position:y", target_title_y, 0.12)
	_hover_border.visible = hovered
	if _hover_border.visible:
		tween.tween_property(_hover_border, "modulate:a", 0.75 if hovered else 0.0, 0.12)

	var base_icon_mod := Color(1.0, 0.96, 0.82, 0.96)
	if _is_quest:
		base_icon_mod = Color(1.08, 1.0, 0.78, 1.0)
	elif _is_done:
		base_icon_mod = Color(0.75, 0.72, 0.68, 0.7)
	if _icon_rect and _icon_rect.visible:
		var icon_mod := Color(1.1, 1.04, 0.88, 1.0) if hovered else base_icon_mod
		var icon_sc := Vector2(1.1, 1.1) if hovered else Vector2.ONE
		tween.tween_property(_icon_rect, "modulate", icon_mod, 0.12)
		tween.tween_property(_icon_rect, "scale", icon_sc, 0.14)
	if _icon_plate and _icon_plate.visible:
		var plate_a := (1.0 if hovered else 0.9) if not _is_done else 0.65
		tween.tween_property(_icon_plate, "modulate:a", plate_a, 0.12)

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
