extends Control

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)

@onready var port_title: Label = $PortTitle
@onready var left_facilities: VBoxContainer = $LeftFacilities
@onready var right_facilities: VBoxContainer = $RightFacilities

var _current_port_id: String = ""

func setup(scene_data: Dictionary, port_id: String) -> void:
	_current_port_id = port_id
	port_title.text = scene_data.get("title", "未知港口")
	
	for child in left_facilities.get_children(): child.queue_free()
	for child in right_facilities.get_children(): child.queue_free()
		
	var facilities = scene_data.get("facilities", [])
	for i in range(facilities.size()):
		var fac = facilities[i]
		
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 90)
		card.theme_type_variation = "PortFacilityCard"
		
		var hbox = HBoxContainer.new()
		card.add_child(hbox)
		
		# [豁免说明] 反模式 #7 临时豁免：由于 scenes.json 中暂未包含 facilities 的 icon 字段，
		# 现阶段提供 fallback 动态拼接，一旦配置表完善即可全面移除
		var icon_id = fac.get("id", "").replace("city_", "")
		var icon_path = fac.get("icon", "res://assets/icon_" + icon_id + ".png")
		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		var icon_tex = load(icon_path) as Texture2D
		if not icon_tex and FileAccess.file_exists(icon_path):
			var img = Image.load_from_file(icon_path)
			if img: icon_tex = ImageTexture.create_from_image(img)
		if icon_tex:
			tex_rect.texture = icon_tex
		
		var icon_margin = MarginContainer.new()
		icon_margin.theme_type_variation = "FacilityIconMargin"
		icon_margin.add_child(tex_rect)
		hbox.add_child(icon_margin)
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(vbox)
		
		var title_lbl = Label.new()
		title_lbl.text = fac.get("title", "未命名设施")
		title_lbl.theme_type_variation = "FacilityTitle"
		vbox.add_child(title_lbl)
		
		var sub_lbl = Label.new()
		sub_lbl.text = fac.get("subtitle", "")
		sub_lbl.theme_type_variation = "FacilitySubtitle"
		vbox.add_child(sub_lbl)
		
		var btn = Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_facility_pressed.bind(fac))
		btn.theme_type_variation = "FacilityCardButton"
		
		card.add_child(btn)
		
		if i % 2 == 0: left_facilities.add_child(card)
		else: right_facilities.add_child(card)

	# ==========================================
	# 添加核心出海按钮
	# ==========================================
	var set_sail_btn = Button.new()
	set_sail_btn.text = "🚢 升帆出海 (World Map)"
	set_sail_btn.custom_minimum_size = Vector2(250, 80)
	set_sail_btn.theme_type_variation = "SetSailButton"
	
	set_sail_btn.pressed.connect(func():
		var res = GameState.customs_inspection()
		message_logged.emit(res["msg"] + "\n\n")
		status_updated.emit()
		
		if res["passed"]:
			if res.get("was_smuggling", false):
				set_sail_btn.text = "正在强行出港..."
				set_sail_btn.disabled = true
				await get_tree().create_timer(2.5).timeout
				
			get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
	)
	right_facilities.add_child(set_sail_btn)

func _on_facility_pressed(fac: Dictionary) -> void:
	var target_scene = fac.get("id", "")
	if target_scene.begins_with("city_"):
		var suffix = target_scene.replace("city_", "")
		target_scene = _current_port_id + "_" + suffix
	if target_scene != "":
		scene_requested.emit(target_scene)
