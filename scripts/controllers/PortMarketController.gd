class_name PortMarketController extends Node

## 市场交易子控制器 (双栏 UI 版本)
## NK1-P6-POLISH: 纯代码构建的沉浸式交易所面板，实现本地买卖实时联动

signal message_logged(msg: String)
signal status_updated

var _port_id: String = ""
var _interactive_container: Container
var _choices_container: Container
var _choices_label: Label

# 缓存 UI 根节点以便刷新
var _market_root: VBoxContainer

func setup(port_id: String, interactive_container: Container, choices_container: Container, choices_label: Label) -> void:
	_port_id = port_id
	_interactive_container = interactive_container
	_choices_container = choices_container
	_choices_label = choices_label

	_build_market_ui()

func _build_market_ui() -> void:
	# 清空容器
	for child in _interactive_container.get_children():
		child.queue_free()
	for child in _choices_container.get_children():
		child.queue_free()

	# 创建交易主面板 (VBox)
	_market_root = VBoxContainer.new()
	_market_root.custom_minimum_size = Vector2(900, 400) # 占据大部分交互空间
	_market_root.add_theme_constant_override("separation", 16)
	_interactive_container.add_child(_market_root)

	# 顶部状态栏（繁荣度、总资金、容量等）
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 24)
	_market_root.add_child(header_hbox)

	var prosperity: float = GameManager.state.market.get_prosperity(_port_id)
	var p_text = "繁荣度: 平稳"
	if prosperity > 1.1: p_text = "繁荣度: 兴盛"
	elif prosperity < 0.9: p_text = "繁荣度: 萧条"

	var funds: int = LedgerSystem.get_balance()
	var total_cargo: int = CargoSystem.get_total_cargo()
	var max_cargo: int = GameState.max_cargo

	header_hbox.add_child(UIBuilder.make_market_title("【市舶司大堂】 " + p_text))

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header_spacer)

	var fund_lbl := UIBuilder.make_market_title("资金: %d 贯" % funds)
	fund_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2)) # [豁免] 动态创建时指定字体高亮色
	header_hbox.add_child(fund_lbl)

	var cargo_lbl := UIBuilder.make_market_title("货舱: %d / %d" % [total_cargo, max_cargo])
	if total_cargo >= max_cargo:
		cargo_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3)) # [豁免] 运行时动态计算的满仓警告色
	header_hbox.add_child(cargo_lbl)

	# 下方双列布局
	var split_hbox := HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 32)
	_market_root.add_child(split_hbox)

	# ---- 左侧：港口货源 (Buy) ----
	var left_panel := UIBuilder.make_panel(UITheme.MARKET_PANEL)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_panel.add_child(left_vbox)
	left_vbox.add_child(UIBuilder.make_market_title("【港口挂牌】 (买入)"))
	left_vbox.add_child(HSeparator.new())

	var snapshot = EconomySystem.get_market_snapshot(_port_id)
	for item in snapshot.get("goods", []):
		var g_id = item.get("id", "")
		var i_name = item.get("name", g_id)
		var price = item.get("price", 0)
		var avail = item.get("available", 0)

		if avail <= 0: continue

		var item_hbox := HBoxContainer.new()
		left_vbox.add_child(item_hbox)

		var name_lbl := UIBuilder.make_label("%s" % i_name, UITheme.MARKET_PREVIEW)
		name_lbl.custom_minimum_size = Vector2(100, 0)
		item_hbox.add_child(name_lbl)

		var stock_lbl := UIBuilder.make_label("余 %d" % avail, UITheme.MARKET_PREVIEW)
		stock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stock_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6)) # [豁免] 纯代码生成的辅助灰字色
		item_hbox.add_child(stock_lbl)

		var price_lbl := UIBuilder.make_label("%d 钱" % price, UITheme.MARKET_PREVIEW)
		price_lbl.custom_minimum_size = Vector2(80, 0)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		item_hbox.add_child(price_lbl)

		var buy_btn := UIBuilder.make_button("买入", UITheme.BTN_ACTION, 32)
		buy_btn.custom_minimum_size = Vector2(60, 32)
		buy_btn.pressed.connect(_on_buy_pressed.bind(g_id, i_name, price))
		item_hbox.add_child(buy_btn)

	# ---- 右侧：本船货舱 (Sell) ----
	var right_panel := UIBuilder.make_panel(UITheme.MARKET_PANEL)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_panel.add_child(right_vbox)
	right_vbox.add_child(UIBuilder.make_market_title("【本船舱单】 (卖出)"))
	right_vbox.add_child(HSeparator.new())

	var any_cargo := false
	for g_id in CargoSystem.get_keys():
		var amt = CargoSystem.get_amount(g_id)
		if amt <= 0: continue
		any_cargo = true

		var good_data = GameManager.get_good_data(g_id)
		var i_name = good_data.get("name", g_id)
		# 获取当地收购价
		var sell_price = EconomySystem.get_price(_port_id, g_id)

		var item_hbox := HBoxContainer.new()
		right_vbox.add_child(item_hbox)

		var name_lbl := UIBuilder.make_label("%s" % i_name, UITheme.MARKET_PREVIEW)
		name_lbl.custom_minimum_size = Vector2(100, 0)
		item_hbox.add_child(name_lbl)

		var amt_lbl := UIBuilder.make_label("载 %d" % amt, UITheme.MARKET_PREVIEW)
		amt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amt_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6)) # [豁免] 纯代码生成的辅助灰字色
		item_hbox.add_child(amt_lbl)

		var price_lbl := UIBuilder.make_label("%d 钱" % sell_price, UITheme.MARKET_PREVIEW)
		price_lbl.custom_minimum_size = Vector2(80, 0)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		item_hbox.add_child(price_lbl)

		var sell_btn := UIBuilder.make_button("卖出", UITheme.BTN_ACTION, 32)
		sell_btn.custom_minimum_size = Vector2(60, 32)
		sell_btn.pressed.connect(_on_sell_pressed.bind(g_id, i_name, amt))
		item_hbox.add_child(sell_btn)

	if not any_cargo:
		var empty_lbl = UIBuilder.make_label("货舱空空如也", UITheme.MARKET_PREVIEW, HORIZONTAL_ALIGNMENT_CENTER)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5)) # [豁免] 纯代码生成的辅助灰字色
		right_vbox.add_child(empty_lbl)

	# ---- 底部快捷按键 ----
	var sell_all_btn = UIBuilder.make_choice_button("一键抛售全部")
	sell_all_btn.pressed.connect(_on_sell_all_pressed)
	_choices_container.add_child(sell_all_btn)
	_choices_label.visible = true

func _refresh_ui() -> void:
	_build_market_ui()

func _on_buy_pressed(good_id: String, item_name: String, _price: int) -> void:
	var intent = Intent.new(
		IntentTypes.MARKET_BUY, "player", "market",
		{"good_id": good_id, "amount": 1},
		{"port_id": _port_id}
	)
	var result = IntentResolver.process(intent)
	if result.success:
		# 极简飘字，不打断交易流
		message_logged.emit("✓ 购入 " + item_name + "\n")
		status_updated.emit()
		_refresh_ui()
	else:
		var reason = GameManager.get_text(result.message_key, "【失败】金钱不足或货舱已满。")
		message_logged.emit("✗ " + reason + "\n")

func _on_sell_pressed(good_id: String, item_name: String, _amount: int) -> void:
	# 只卖1个，供精细操作
	var intent = Intent.new(
		IntentTypes.MARKET_SELL, "player", "market",
		{"good_id": good_id, "amount": 1},
		{"port_id": _port_id}
	)
	var result = IntentResolver.process(intent)
	if result.success:
		message_logged.emit("✓ 卖出 " + item_name + "\n")
		status_updated.emit()
		_refresh_ui()
	else:
		message_logged.emit("✗ 卖出失败\n")

func _on_sell_all_pressed() -> void:
	var res = GameState.sell_all_cargo(_port_id)
	message_logged.emit("★ " + res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()
		_refresh_ui()
