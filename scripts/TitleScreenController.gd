extends Control

signal scene_requested(scene_id: String)

@onready var main_title: Label = $TitlePanel/VBoxContainer/MainTitle
@onready var sub_title: Label = $TitlePanel/VBoxContainer/SubTitle
@onready var button_container: VBoxContainer = $TitlePanel/VBoxContainer/ButtonContainer

func setup(scene_data: Dictionary) -> void:
	main_title.text = scene_data.get("cg_title", "南海立志传")
	sub_title.text = scene_data.get("cg_sub", "")

	for child in button_container.get_children():
		child.queue_free()

	# 继续旅程（有存档时显示）
	if SaveManager.has_save():
		var continue_btn = Button.new()
		continue_btn.text = "继续旅程"
		continue_btn.custom_minimum_size = Vector2(240, 48)
		continue_btn.theme_type_variation = "TitleMenuButton"
		continue_btn.pressed.connect(_on_continue_pressed)
		button_container.add_child(continue_btn)

	var choices = scene_data.get("choices", [])
	if choices.is_empty():
		var btn = Button.new()
		btn.text = "开始旅程"
		btn.custom_minimum_size = Vector2(240, 52)
		btn.theme_type_variation = "TitleMenuButton"
		btn.pressed.connect(func(): scene_requested.emit("scene01_xianghua_school"))
		button_container.add_child(btn)
	else:
		for choice in choices:
			var btn = Button.new()
			btn.text = choice.get("label", "继续")
			btn.custom_minimum_size = Vector2(240, 48)
			btn.theme_type_variation = "TitleMenuButton"
			var next = choice.get("next", "scene01_xianghua_school")
			btn.pressed.connect(func(): scene_requested.emit(next))
			button_container.add_child(btn)

func _on_continue_pressed() -> void:
	var result = SaveManager.load_game()
	if result["success"]:
		scene_requested.emit(result["scene_id"])
	else:
		# 加载失败，静默忽略（按钮下次会隐藏）
		push_warning("[TitleScreen] 读档失败: " + result.get("msg", ""))