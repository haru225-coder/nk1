extends Control

signal scene_requested(scene_id: String)

@onready var main_title: Label = $TitlePanel/VBoxContainer/MainTitle
@onready var sub_title: Label = $TitlePanel/VBoxContainer/SubTitle
@onready var button_container: VBoxContainer = $TitlePanel/VBoxContainer/ButtonContainer
@onready var title_panel: PanelContainer = $TitlePanel

var _scene_data: Dictionary = {}
var _koei_frame: NinePatchRect = null
var _title_divider: ColorRect = null

func _ready() -> void:
	_ensure_koei_chrome()

func setup(scene_data: Dictionary) -> void:
	_scene_data = scene_data
	_ensure_koei_chrome()
	main_title.text = scene_data.get("cg_title", "南海立志传")
	sub_title.text = scene_data.get("cg_sub", "")
	_ensure_title_divider()

	for child in button_container.get_children():
		child.queue_free()

	_build_save_list()
	_add_choices(scene_data)

func _ensure_koei_chrome() -> void:
	if _koei_frame != null and is_instance_valid(_koei_frame):
		return
	if has_node("KoeiOuterFrame"):
		_koei_frame = $KoeiOuterFrame as NinePatchRect
		return

	var frame_tex: Texture2D = load(ResourcePaths.FRAME_KOEI) as Texture2D
	if frame_tex == null:
		return

	_koei_frame = NinePatchRect.new()
	_koei_frame.name = "KoeiOuterFrame"
	_koei_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_koei_frame.texture = frame_tex
	# 与 DialogueBox / TownMap 同款 patch（源资源九宫格 margin）
	_koei_frame.patch_margin_left = 40
	_koei_frame.patch_margin_top = 40
	_koei_frame.patch_margin_right = 40
	_koei_frame.patch_margin_bottom = 40
	_koei_frame.layout_mode = 1
	_koei_frame.anchors_preset = Control.PRESET_CENTER
	_koei_frame.anchor_left = 0.5
	_koei_frame.anchor_top = 0.5
	_koei_frame.anchor_right = 0.5
	_koei_frame.anchor_bottom = 0.5
	# 比 TitlePanel（±380×±280）略大，露出木框外缘
	_koei_frame.offset_left = -408.0
	_koei_frame.offset_top = -308.0
	_koei_frame.offset_right = 408.0
	_koei_frame.offset_bottom = 308.0
	_koei_frame.z_index = -1
	add_child(_koei_frame)
	move_child(_koei_frame, 0)

	# 内层 TitlePanel 略抬高，压在木框中心
	if title_panel:
		title_panel.z_index = 0

func _ensure_title_divider() -> void:
	var vbox := title_panel.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	if vbox.has_node("TitleDivider"):
		_title_divider = vbox.get_node("TitleDivider") as ColorRect
		return

	# 主金线 + 两侧淡入感：中心亮、两端略短（用三截近似）
	var wrap := HBoxContainer.new()
	wrap.name = "TitleDividerWrap"
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 0)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(48, 1)
	left.color = Color(0.88, 0.68, 0.28, 0.25)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(left)

	_title_divider = ColorRect.new()
	_title_divider.name = "TitleDivider"
	_title_divider.custom_minimum_size = Vector2(160, 2)
	_title_divider.color = Color(0.92, 0.74, 0.32, 0.88)
	_title_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_title_divider)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(48, 1)
	right.color = Color(0.88, 0.68, 0.28, 0.25)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(right)

	var sub_idx := sub_title.get_index() if sub_title else 1
	vbox.add_child(wrap)
	vbox.move_child(wrap, sub_idx + 1)

func _build_save_list() -> void:
	var header := Label.new()
	header.text = "— 航行记录 —"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.theme_type_variation = UITheme.TEXT_TITLE_SAVE_HEADER
	button_container.add_child(header)

	var save_list := VBoxContainer.new()
	save_list.add_theme_constant_override("separation", 8)
	save_list.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(save_list)

	for info in SaveManager.get_all_saves_info():
		save_list.add_child(_make_save_row(info))

func _make_save_row(info: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var slot: int = info.get("slot", 0)
	var slot_label := "存档 %d" % (slot + 1)

	if info.get("exists", false):
		var loc: String = info.get("current_location_name", info.get("current_scene_id", ""))
		var balance: int = info.get("balance", 0)
		var ts: String = info.get("timestamp", "")
		var load_btn_text := "%s · %s · %d贯" % [slot_label, loc, balance]
		if ts != "":
			load_btn_text += " · %s" % ts
		var load_btn := UIBuilder.make_button(load_btn_text, UITheme.BTN_TITLE_MENU, 44)
		load_btn.custom_minimum_size = Vector2(360, 44)
		load_btn.pressed.connect(func(): _on_load_slot(slot))
		row.add_child(load_btn)

		var del_btn := UIBuilder.make_button("删", UITheme.BTN_TITLE_MENU, 44)
		del_btn.custom_minimum_size = Vector2(44, 44)
		del_btn.pressed.connect(func(): _on_delete_slot(slot))
		row.add_child(del_btn)
	else:
		var empty_label := Label.new()
		empty_label.text = "%s · 空存档" % slot_label
		empty_label.custom_minimum_size = Vector2(360, 44)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.theme_type_variation = UITheme.TEXT_TITLE_SUB
		row.add_child(empty_label)

	return row

func _on_load_slot(slot: int) -> void:
	if not SaveManager.load_game(slot):
		push_warning("[TitleScreen] 读档失败 slot=%d" % slot)

func _on_delete_slot(slot: int) -> void:
	if not SaveManager.delete_save(slot):
		push_warning("[TitleScreen] 删除失败 slot=%d" % slot)
		return
	_refresh_save_list()

func _refresh_save_list() -> void:
	for child in button_container.get_children():
		child.queue_free()
	_build_save_list()
	_add_choices(_scene_data)

func _add_choices(scene_data: Dictionary) -> void:
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	button_container.add_child(sep)

	var choices = scene_data.get("choices", [])
	if choices.is_empty():
		var btn := UIBuilder.make_button("开始旅程", UITheme.BTN_TITLE_MENU, 52)
		btn.custom_minimum_size = Vector2(280, 52)
		btn.pressed.connect(func(): scene_requested.emit("scene01_xianghua_school"))
		button_container.add_child(btn)
	else:
		for choice in choices:
			var label_text = choice.get("label", "继续")
			var btn := UIBuilder.make_button(label_text, UITheme.BTN_TITLE_MENU, 48)
			btn.custom_minimum_size = Vector2(280, 48)
			var next = choice.get("next", "scene01_xianghua_school")
			btn.pressed.connect(func(): scene_requested.emit(next))
			button_container.add_child(btn)
