import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

# 1. Intercept in load_scene
code = code.replace('scene_id.ends_with("_market") or scene_id.ends_with("_yamen")', 'scene_id.ends_with("_market") or scene_id.ends_with("_yamen") or scene_id.ends_with("_shipyard")')

# 2. Intercept in _on_facility_pressed
code = code.replace('elif target_scene == "city_yamen":', 'elif target_scene == "city_yamen":\n\t\ttarget_scene = current_scene_id + "_yamen"\n\telif target_scene == "city_shipyard":\n\t\ttarget_scene = current_scene_id + "_shipyard"\n\telif target_scene == "city_yamen":') # Wait, I'll use regex.

new_fac = """func _on_facility_pressed(fac: Dictionary) -> void:
	var target_scene = fac.get("id", "")
	if target_scene == "city_market":
		target_scene = current_scene_id + "_market"
	elif target_scene == "city_yamen":
		target_scene = current_scene_id + "_yamen"
	elif target_scene == "city_shipyard":
		target_scene = current_scene_id + "_shipyard"
	if target_scene != "":
		load_scene(target_scene)"""

code = re.sub(r'func _on_facility_pressed\(fac: Dictionary\) -> void:.*?(?=func _setup_investigation_mode)', new_fac + '\n\n', code, flags=re.DOTALL)

# 3. Add to _setup_dynamic_scene
new_dyn = """	elif scene_id.ends_with("_yamen"):
		scene_title.text = "市舶司与暗关"
		body_text.text = "市舶司抽解是朝廷的法度。但在这个港口，真正管事的是蒲氏的暗桩。你有几分斤两，全看你走的是明道还是暗关。"
		
		var btn1 = Button.new()
		btn1.text = "【正规】市舶司验引 (安全放行)"
		btn1.pressed.connect(func():
			GameState.has_customs_permit = true
			message_label.text = "【市舶司】你办理了正规货引，合法离港。\\n\\n" + message_label.text
			update_status_panel()
		)
		choices_container.add_child(btn1)
		
		var btn2 = Button.new()
		btn2.text = "【走私】塞钱走暗关免验 (贿赂 50 钱)"
		btn2.pressed.connect(func():
			var res = GameState.customs_inspection()
			message_label.text = res["msg"] + "\\n\\n" + message_label.text
			update_status_panel()
		)
		choices_container.add_child(btn2)
		choices_label.visible = true
		
		_add_leave_button(base_loc)

	elif scene_id.ends_with("_shipyard"):
		scene_title.text = "船屋"
		body_text.text = "船坞里散发着桐油与海水的味道。这是修补海船、补充水手的地方。"
		
		var btn = Button.new()
		btn.text = "★ 扬帆起航 (进入航海模式)"
		btn.pressed.connect(func():
			message_label.text = "【大航海】扬帆起航！目前航海物理核心(WASD)尚未完全接入 Godot 界面，敬请期待！\\n\\n" + message_label.text
		)
		choices_container.add_child(btn)
		
		# Also load the normal interior cards for shipyard
		var s_data = GameManager.get_scene_by_id("city_shipyard")
		if not s_data.is_empty():
			for inv in s_data.get("investigations", []):
				var ibtn = Button.new()
				ibtn.text = "★ " + inv.get("label", "互动")
				ibtn.pressed.connect(_on_investigate_pressed.bind(inv, ibtn))
				interactive_container.add_child(ibtn)
		
		_add_leave_button(base_loc)"""

code = re.sub(r'\telif scene_id.ends_with\("_yamen"\):.*?(?=func _add_buy_button)', new_dyn + '\n\n', code, flags=re.DOTALL)

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
