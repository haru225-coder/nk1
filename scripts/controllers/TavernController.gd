class_name TavernController extends Node

## 酒馆子控制器
## 负责传闻购买 UI、调用 buy_intel Intent。
## 通过信号与父控制器通信。

signal message_logged(msg: String)
signal status_updated

func setup(interactive_container: HFlowContainer, interactive_label: Label, dialogue_box: Control) -> void:
	var entry := TradeEventGenerator.get_random_rumor_entry()
	if entry.is_empty():
		return
	interactive_label.visible = true
	var rumor: Dictionary = entry.get("rumor", {})
	var event_index: int = int(entry.get("index", -1))
	_add_rumor_btn(rumor, event_index, 1, "★ 小道消息 (💰 20)", interactive_container, dialogue_box)
	_add_rumor_btn(rumor, event_index, 2, "★★ 酒馆传言 (💰 50)", interactive_container, dialogue_box)
	_add_rumor_btn(rumor, event_index, 3, "★★★ 商人情报 (💰 120)", interactive_container, dialogue_box)

func _add_rumor_btn(rumor: Dictionary, event_index: int, tier: int, label: String, container: HFlowContainer, dialogue_box: Control) -> void:
	var btn = UIBuilder.make_action_button(label)
	btn.pressed.connect(_on_rumor_pressed.bind(rumor, event_index, tier, dialogue_box))
	btn.add_to_group("rumor_buttons")
	container.add_child(btn)

func _on_rumor_pressed(rumor: Dictionary, event_index: int, tier: int, dialogue_box: Control) -> void:
	if GameManager.input_locked:
		return
	var cost := TradeEventGenerator.get_tier_cost(tier)
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.BUY_INTEL, "player", "tavern",
		{"tier": tier, "total_cost": cost, "event_index": event_index},
		{"port_id": GameState.last_port}
	))
	if not result.success:
		if result.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS:
			message_logged.emit("【酒馆】你摸遍口袋也凑不出 %d 钱。\n\n" % cost)
		else:
			var txt := GameManager.get_text(result.message_key, "")
			message_logged.emit((txt if txt != "" else "【酒馆】情报购买失败。") + "\n\n")
		return
	# 禁用所有传闻按钮
	get_tree().call_group("rumor_buttons", "set_disabled", true)
	var narration := _build_rumor_narration(rumor, tier)
	var beat = DialogueParser.beat_from_text(narration)
	dialogue_box.show_single_beat(beat)
	status_updated.emit()

func _build_rumor_narration(rumor: Dictionary, tier: int) -> String:
	var days_left: int = rumor.get("days_left", 7)
	match tier:
		1:
			return "喝醉的水手凑过来低声说：「听说最近某个方向的港口有点不寻常……要留心。」"
		2:
			var days_low: int = days_left - 2
			var days_high: int = days_left + 3
			return "老水手压低声音：「南边某港，大约 %d 到 %d 天内会有变故。你懂的。」" % [maxi(1, days_low), days_high]
		3:
			var port_name: String = rumor.get("port_name", "某港")
			var days_low: int = days_left - 1
			var days_high: int = days_left + 2
			return "商人凑近低声道：「%s那边，听说大约 %d 到 %d 天内会有大事，你自己掂量。」" % [port_name, maxi(1, days_low), days_high]
		_:
			return ""
