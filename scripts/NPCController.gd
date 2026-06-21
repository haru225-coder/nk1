extends Control

signal status_updated
signal npc_finished

var dialogue_box: Control

func bind_dialogue_box(box: Control) -> void:
	dialogue_box = box

func setup(npc_id: String, fallback_name: String) -> void:
	if dialogue_box == null:
		push_warning("[NPCController] dialogue_box 未绑定，无法展示对话。")
		npc_finished.emit()
		return

	var npc_data: Dictionary = {}
	for n in GameManager.npcs_data.get("npcs", []):
		if n.get("id") == npc_id:
			npc_data = n
			break

	var n_name: String = npc_data.get("name", fallback_name)
	var avatar_path: String = npc_data.get("avatar", "")
	var intro_text: String = npc_data.get(
		"function",
		"（这人看起来有些眼熟，但什么也没说...）"
	)
	dialogue_box.show_persistent(n_name, intro_text, avatar_path)

	var actions: HBoxContainer = dialogue_box.get_actions_slot()
	for child in actions.get_children():
		child.queue_free()

	var intel_btn := Button.new()
	intel_btn.text = "打听情报"
	intel_btn.theme_type_variation = "ActionButton"
	intel_btn.custom_minimum_size = Vector2(120, 40)
	intel_btn.pressed.connect(func():
		var goods = GameManager.goods_data.get("goods", [])
		if goods.size() > 0:
			var random_g = goods[randi() % goods.size()]
			dialogue_box.show_persistent(
				n_name,
				n_name + " 压低声音说：“听说最近 %s 的买卖很赚，你要不要试试？”" % random_g.get("name", "这行"),
				avatar_path
			)
	)
	actions.add_child(intel_btn)

	if npc_id == "customs_official":
		var bribe_btn := Button.new()
		bribe_btn.text = "塞钱买通 (50钱)"
		bribe_btn.theme_type_variation = "ActionButton"
		bribe_btn.custom_minimum_size = Vector2(150, 40)
		bribe_btn.pressed.connect(func():
			var res = GameState.handle_special_action("bribe_official_50")
			if res["success"]:
				status_updated.emit()
				dialogue_box.show_persistent(
					n_name,
					n_name + " 颠了颠手里的碎银：“算你懂事。文牒拿好，路上小心。”",
					avatar_path
				)
			else:
				dialogue_box.show_persistent(
					n_name,
					n_name + " 满脸鄙夷：“就这点钱也想打通关节？滚滚滚！”",
					avatar_path
				)
		)
		actions.add_child(bribe_btn)

	var leave_btn := Button.new()
	leave_btn.text = "离开"
	leave_btn.theme_type_variation = "ChoiceButton"
	leave_btn.custom_minimum_size = Vector2(100, 40)
	leave_btn.pressed.connect(func():
		dialogue_box.hide_dialogue()
		npc_finished.emit()
	)
	actions.add_child(leave_btn)

func _exit_tree() -> void:
	if dialogue_box and dialogue_box.has_method("hide_dialogue"):
		dialogue_box.hide_dialogue()