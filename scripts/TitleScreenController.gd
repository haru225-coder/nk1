extends Control

signal scene_requested(scene_id: String)

@onready var main_title: Label = $TitlePanel/VBoxContainer/MainTitle
@onready var sub_title: Label = $TitlePanel/VBoxContainer/SubTitle
@onready var button_container: VBoxContainer = $TitlePanel/VBoxContainer/ButtonContainer

var _scene_data: Dictionary = {}

func setup(scene_data: Dictionary) -> void:
	_scene_data = scene_data
	main_title.text = scene_data.get("cg_title", "南海立志传")
	sub_title.text = scene_data.get("cg_sub", "")

	for child in button_container.get_children():
		child.queue_free()

	_build_save_list()
	_add_choices(scene_data)

func _build_save_list() -> void:
	var header := Label.new()
	header.text = "航行记录"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.theme_type_variation = "TitleSub"
	button_container.add_child(header)

	var save_list := VBoxContainer.new()
	save_list.theme_override_constants["separation"] = 8
	save_list.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(save_list)

	for info in SaveManager.get_all_saves_info():
		save_list.add_child(_make_save_row(info))

func _make_save_row(info: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.theme_override_constants["separation"] = 8

	var slot: int = info.get("slot", 0)
	var slot_label := "存档 %d" % (slot + 1)

	if info.get("exists", false):
		var loc: String = info.get("current_location_name", info.get("current_scene_id", ""))
		var balance: int = info.get("balance", 0)
		var ts: String = info.get("timestamp", "")
		var load_btn := Button.new()
		load_btn.text = "%s · %s · %d贯" % [slot_label, loc, balance]
		if ts != "":
			load_btn.text += " · %s" % ts
		load_btn.custom_minimum_size = Vector2(360, 44)
		load_btn.theme_type_variation = "TitleMenuButton"
		load_btn.pressed.connect(func(): _on_load_slot(slot))
		row.add_child(load_btn)

		var del_btn := Button.new()
		del_btn.text = "删"
		del_btn.custom_minimum_size = Vector2(44, 44)
		del_btn.theme_type_variation = "TitleMenuButton"
		del_btn.pressed.connect(func(): _on_delete_slot(slot))
		row.add_child(del_btn)
	else:
		var empty_label := Label.new()
		empty_label.text = "%s · 空存档" % slot_label
		empty_label.custom_minimum_size = Vector2(360, 44)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.theme_type_variation = "TitleSub"
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
		var btn := Button.new()
		btn.text = "开始旅程"
		btn.custom_minimum_size = Vector2(280, 52)
		btn.theme_type_variation = "TitleMenuButton"
		btn.pressed.connect(func(): scene_requested.emit("scene01_xianghua_school"))
		button_container.add_child(btn)
	else:
		for choice in choices:
			var btn := Button.new()
			btn.text = choice.get("label", "继续")
			btn.custom_minimum_size = Vector2(280, 48)
			btn.theme_type_variation = "TitleMenuButton"
			var next = choice.get("next", "scene01_xianghua_school")
			btn.pressed.connect(func(): scene_requested.emit(next))
			button_container.add_child(btn)