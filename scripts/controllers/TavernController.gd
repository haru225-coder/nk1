class_name TavernController extends Node

## 酒馆子控制器
## 负责传闻购买 UI、调用 buy_intel Intent。
## 通过信号与父控制器通信。

signal message_logged(msg: String)
signal status_updated

func setup(interactive_container: HFlowContainer, interactive_label: Label, dialogue_box: Control) -> void:
	# 无潜伏传闻时试生成一次，保证「信息可买」路径常在
	var entry := TradeEventGenerator.get_random_rumor_entry()
	if entry.is_empty():
		TradeEventGenerator.try_generate()
		entry = TradeEventGenerator.get_random_rumor_entry()
	if entry.is_empty():
		interactive_label.visible = true
		interactive_label.text = "今夜酒馆无人谈买卖——海上一时平静。"
		return
	interactive_label.visible = true
	interactive_label.text = "有人压低声音谈市舶……情报越贵，说得越准。"
	var rumor: Dictionary = entry.get("rumor", {})
	var event_index: int = int(entry.get("index", -1))
	_add_rumor_btn(rumor, event_index, 1, "★ 小道消息 (20 钱) · 模糊", interactive_container, dialogue_box)
	_add_rumor_btn(rumor, event_index, 2, "★★ 酒馆传言 (50 钱) · 有窗口", interactive_container, dialogue_box)
	_add_rumor_btn(rumor, event_index, 3, "★★★ 商人情报 (120 钱) · 点名港口", interactive_container, dialogue_box)

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
	var narration := _build_rumor_narration(rumor, tier, result)
	var beat = DialogueParser.beat_from_text(narration)
	dialogue_box.show_single_beat(beat)
	var summary := str(result.data.get("intel_summary", ""))
	if summary != "":
		message_logged.emit("【情报】已记入札记（%s 档）。\n%s\n\n" % ["★".repeat(tier), summary])
	else:
		message_logged.emit("【情报】已记入札记。\n\n")
	status_updated.emit()

func _build_rumor_narration(rumor: Dictionary, tier: int, result: IntentResult = null) -> String:
	# 优先用 IntelNotes 生成的摘要（与账本一致）
	if result != null and result.data.get("intel_summary", "") != "":
		var lead := ""
		match tier:
			1:
				lead = "喝醉的水手凑过来低声说："
			2:
				lead = "老水手压低声音："
			3:
				lead = "商人凑近低声道："
			_:
				lead = "有人低声说："
		return "%s「%s」" % [lead, str(result.data.get("intel_summary", ""))]
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
			var etype := str(rumor.get("type", ""))
			var label := IntelNotes.event_type_label(etype)
			return "商人凑近低声道：「%s那边，大约 %d 到 %d 天内会有「%s」，你自己掂量。」" % [
				port_name, maxi(1, days_low), days_high, label
			]
		_:
			return ""
