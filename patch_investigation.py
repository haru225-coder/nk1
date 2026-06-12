import re
with open("/Users/snowchan27/nk-1/scripts/Main.gd", "r", encoding="utf-8") as f:
    code = f.read()

new_inv_mode = """func _setup_investigation_mode(scene_data: Dictionary) -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	investigation_mode.visible = true
	
	scene_title.text = scene_data.get("title", "未命名地点")
	body_text.text = scene_data.get("body", "")
	
	for child in interactive_container.get_children(): child.queue_free()
	for child in choices_container.get_children(): child.queue_free()
		
	var investigations = scene_data.get("investigations", [])
	
	if investigations.size() > 0:
		for inv in investigations:
			var btn = Button.new()
			btn.text = "★ " + inv.get("label", "互动")
			btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
			interactive_container.add_child(btn)
			
	# Always show choices
	show_choices(scene_data.get("choices", []))

func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	var msg = inv_data.get("text", "")
	if msg != "":
		body_text.text += "\\n\\n" + msg
	apply_effects(inv_data.get("effects", {}))
	
	var next_sc = inv_data.get("next", "")
	if next_sc != "":
		load_scene(next_sc)
	else:
		btn.disabled = true"""

code = re.sub(r'func _setup_investigation_mode\(scene_data: Dictionary\) -> void:.*?(?=func show_choices)', new_inv_mode + '\n\n', code, flags=re.DOTALL)

with open("/Users/snowchan27/nk-1/scripts/Main.gd", "w", encoding="utf-8") as f:
    f.write(code)
