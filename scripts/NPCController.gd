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

	var intel_btn := UIBuilder.make_button("打听情报", UITheme.BTN_ACTION, 40)
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

	_inject_special_actions(actions, npc_data, npc_id, n_name, avatar_path)

	var leave_btn := UIBuilder.make_button("离开", UITheme.BTN_CHOICE, 40)
	leave_btn.custom_minimum_size = Vector2(100, 40)
	leave_btn.pressed.connect(func():
		dialogue_box.hide_dialogue()
		npc_finished.emit()
	)
	actions.add_child(leave_btn)

func _inject_special_actions(
	actions: HBoxContainer,
	npc_data: Dictionary,
	npc_id: String,
	n_name: String,
	avatar_path: String
) -> void:
	var special_actions: Array = npc_data.get("special_actions", [])
	var ctx := {"npc_id": npc_id}
	for action_data in special_actions:
		if not (action_data is Dictionary):
			continue
		var enabled_when: Dictionary = action_data.get("enabled_when", {})
		var enabled := ConditionEvaluator.matches(enabled_when, ctx)
		var show_unmet := bool(action_data.get("show_when_unmet", false))
		if not enabled and not show_unmet:
			continue

		var label: String = str(action_data.get("label", "行动"))
		if not enabled:
			label = str(action_data.get("disabled_label", label))

		var btn := UIBuilder.make_button(label, UITheme.BTN_ACTION, 40)
		btn.custom_minimum_size = Vector2(150, 40)
		if not enabled:
			btn.disabled = true
			btn.modulate = Color(0.55, 0.55, 0.55)
		else:
			btn.pressed.connect(_on_special_action_pressed.bind(action_data, npc_id, n_name, avatar_path))
		actions.add_child(btn)

func _on_special_action_pressed(
	action_data: Dictionary,
	npc_id: String,
	n_name: String,
	avatar_path: String
) -> void:
	var intent_type := str(action_data.get("intent_type", ""))
	if intent_type.is_empty():
		push_warning("[NPCController] special_action 缺少 intent_type")
		return

	var intent_target := str(action_data.get("intent_target", npc_id))
	var parameters: Dictionary = action_data.get("parameters", {}).duplicate(true)
	var result := IntentResolver.resolve(Intent.new(intent_type, "player", intent_target, parameters))

	var success_dialogue := str(action_data.get("success_dialogue", ""))
	var failure_dialogue := str(action_data.get("failure_dialogue", "此事未能如愿。"))

	if result.success:
		status_updated.emit()
		var dialogue := success_dialogue
		if intent_type == IntentTypes.GIFT_NPC and success_dialogue.contains("%s"):
			var item_name := str(result.data.get("item_name", ""))
			if not item_name.is_empty():
				dialogue = success_dialogue % item_name
		if not dialogue.is_empty():
			dialogue_box.show_persistent(n_name, n_name + " " + dialogue, avatar_path)
	else:
		var fallback_msg := GameManager.get_text(result.message_key, failure_dialogue)
		var msg := failure_dialogue if result.message_key.is_empty() else fallback_msg
		dialogue_box.show_persistent(n_name, n_name + " " + msg, avatar_path)

func _exit_tree() -> void:
	if dialogue_box and dialogue_box.has_method("hide_dialogue"):
		dialogue_box.hide_dialogue()