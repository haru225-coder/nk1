class_name FacilitySlotBuilder extends RefCounted

## 设施卡片 UI 构建器
## 从 PortScreenController 提取的纯 UI 构建逻辑。

static func make_slot(fac: Dictionary, on_pressed: Callable) -> Control:
	var available: bool = GameManager.facility_available(fac)
	var display: Dictionary = GameManager.resolve_facility_subtitle(fac)
	var icon: Texture2D = GameManager.resolve_facility_icon(fac)
	var state: String = display.get("state", "default")
	var is_quest := state == "quest"
	var is_done := state == "done"

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(0, 88)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	panel.name = "CardPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme_type_variation = &"PortFacilityCardQuest" if is_quest else &"PortFacilityCard"
	
	# 初始设为透明并向下偏离 20 像素，供出场交错滑入动效使用
	panel.modulate.a = 0.0
	panel.position.y = 20.0

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(72, 72)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture = icon
	if available:
		tex_rect.modulate = GameColors.TEXT_ICON_DIM if is_done else Color(1, 1, 1, 1.0)
	else:
		tex_rect.modulate = GameColors.TEXT_ICON_AVAILABLE
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_lbl := Label.new()
	title_lbl.theme_type_variation = UITheme.TITLE_FACILITY
	title_lbl.text = fac.get("name", fac.get("title", fac.get("id", "")))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sub_lbl := Label.new()
	sub_lbl.theme_type_variation = UITheme.SUBTITLE_FACILITY
	sub_lbl.text = display.get("text", "").replace("★ ", "")
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_quest:
		sub_lbl.add_theme_color_override("font_color", GameColors.TEXT_GOLD)
	elif is_done:
		sub_lbl.add_theme_color_override("font_color", GameColors.TEXT_DIM)

	vbox.add_child(title_lbl)
	vbox.add_child(sub_lbl)
	hbox.add_child(tex_rect)
	hbox.add_child(vbox)
	margin.add_child(hbox)
	panel.add_child(margin)

	var hit_button := Button.new()
	hit_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_button.flat = true
	hit_button.theme_type_variation = UITheme.BTN_FACILITY_CARD
	hit_button.disabled = not available
	hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit_button.pressed.connect(on_pressed.bind(fac))

	wrapper.add_child(panel)
	wrapper.add_child(hit_button)

	if available:
		tex_rect.pivot_offset = Vector2(36, 36)
		var active_tweens: Array[Tween] = []
		
		hit_button.mouse_entered.connect(func():
			for t in active_tweens:
				if t and t.is_valid():
					t.kill()
			active_tweens.clear()
			
			var tween := wrapper.create_tween().set_parallel(true)
			active_tweens.append(tween)
			tween.tween_property(tex_rect, "scale", Vector2(1.06, 1.06), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(title_lbl, "modulate", Color(1.15, 1.08, 0.65, 1.0), 0.12)
			tween.tween_property(panel, "modulate", Color(1.06, 1.06, 1.06, 1.0), 0.12)
		)
		
		hit_button.mouse_exited.connect(func():
			for t in active_tweens:
				if t and t.is_valid():
					t.kill()
			active_tweens.clear()
			
			var tween := wrapper.create_tween().set_parallel(true)
			active_tweens.append(tween)
			tween.tween_property(tex_rect, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tween.tween_property(title_lbl, "modulate", Color.WHITE, 0.12)
			tween.tween_property(panel, "modulate", Color.WHITE, 0.12)
		)

		hit_button.button_down.connect(func():
			var tween := wrapper.create_tween()
			tween.tween_property(panel, "position:y", 2.0, 0.05).set_trans(Tween.TRANS_SINE)
		)
		
		hit_button.button_up.connect(func():
			var tween := wrapper.create_tween()
			tween.tween_property(panel, "position:y", 0.0, 0.05).set_trans(Tween.TRANS_SINE)
		)

	return wrapper
