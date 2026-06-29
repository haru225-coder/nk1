class_name PortMarketController extends Node

## 市场交易子控制器
## 负责市场 UI 创建、买卖逻辑（调用 Intent）、库存显示。
## 通过信号与父控制器通信，不直接引用父控制器。

signal message_logged(msg: String)
signal status_updated

var _port_id: String = ""

func setup(port_id: String, interactive_container: HFlowContainer, choices_container: VBoxContainer, choices_label: Label) -> void:
	_port_id = port_id
	_setup_market_goods(interactive_container, choices_container, choices_label)

func _setup_market_goods(interactive_container: HFlowContainer, choices_container: VBoxContainer, choices_label: Label) -> void:
	var snapshot = EconomySystem.get_market_snapshot(_port_id)
	var added = 0
	for item in snapshot.get("goods", []):
		var good_id = item.get("id", "")
		var item_name = item.get("name", good_id)
		var price = item.get("price", 0)
		if good_id.is_empty():
			continue
		var btn = UIBuilder.make_action_button("购入：%s (%d钱)" % [item_name, price])
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(_on_buy_pressed.bind(good_id, item_name, price))
		interactive_container.add_child(btn)
		added += 1
		if added >= 4:
			break

	var sell_btn = UIBuilder.make_choice_button("抛售所有货物")
	sell_btn.pressed.connect(_on_sell_all_pressed)
	choices_container.add_child(sell_btn)
	choices_label.visible = true

func _on_buy_pressed(good_id: String, item_name: String, price: int) -> void:
	var intent = Intent.new(
		IntentTypes.MARKET_BUY, "player", "market",
		{"good_id": good_id, "amount": 1},
		{"port_id": _port_id}
	)
	var result = IntentResolver.process(intent)
	if result.success:
		message_logged.emit("成功买入 1 份 " + item_name + "\n\n")
		status_updated.emit()
	else:
		var reason = GameManager.get_text(result.message_key, "【交易失败】金钱不足或货舱已满。")
		message_logged.emit(reason + "\n\n")

func _on_sell_all_pressed() -> void:
	var res = GameState.sell_all_cargo(_port_id)
	message_logged.emit(res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()
