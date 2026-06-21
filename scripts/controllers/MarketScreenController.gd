extends Control
class_name MarketScreenController

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)
signal market_closed

const _THEME_PATH := "res://assets/main_theme.tres"
const DEFAULT_TRADE_AMOUNT := 10

var port_id: String = ""
var market_snapshot: Dictionary = {}
var _selected_good_id: String = ""
var _selected_action: String = ""
var _trade_amount: int = DEFAULT_TRADE_AMOUNT

var title_label: Label
var money_value: Label
var cargo_value: Label
var inventory_container: VBoxContainer
var market_container: VBoxContainer
var preview_label: Label
var amount_row: HBoxContainer
var amount_value_label: Label
var confirm_button: Button
var back_button: Button

var pending_intent: Intent = null
var _game_theme: Theme

func _ready() -> void:
	_game_theme = load(_THEME_PATH) as Theme
	theme = _game_theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(1100, 680)
	shell.theme_type_variation = "MarketShell"
	center.add_child(shell)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	shell.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.theme_type_variation = "MarketTitle"
	vbox.add_child(title_label)

	var info_hbox := HBoxContainer.new()
	info_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(info_hbox)
	info_hbox.add_child(_make_stat_chip("铜钱", "0", "money"))
	info_hbox.add_child(_make_stat_chip("货舱", "0 / 0", "cargo"))

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	vbox.add_child(split)

	var left_panel := _make_market_column("▸ 你的货舱")
	split.add_child(left_panel)
	var right_panel := _make_market_column("▸ 港口特产")
	split.add_child(right_panel)

	preview_label = Label.new()
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.theme_type_variation = "MarketPreview"
	vbox.add_child(preview_label)

	amount_row = HBoxContainer.new()
	amount_row.alignment = BoxContainer.ALIGNMENT_CENTER
	amount_row.add_theme_constant_override("separation", 8)
	amount_row.visible = false
	vbox.add_child(amount_row)
	var amount_caption := Label.new()
	amount_caption.text = "数量"
	amount_caption.theme_type_variation = "MarketPreview"
	amount_row.add_child(amount_caption)
	var minus_btn := Button.new()
	minus_btn.text = "－"
	minus_btn.custom_minimum_size = Vector2(40, 36)
	minus_btn.theme_type_variation = "ChoiceButton"
	minus_btn.pressed.connect(func(): _adjust_trade_amount(-1))
	amount_row.add_child(minus_btn)
	amount_value_label = Label.new()
	amount_value_label.custom_minimum_size = Vector2(64, 0)
	amount_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_value_label.theme_type_variation = "MarketPreview"
	amount_row.add_child(amount_value_label)
	var plus_btn := Button.new()
	plus_btn.text = "＋"
	plus_btn.custom_minimum_size = Vector2(40, 36)
	plus_btn.theme_type_variation = "ChoiceButton"
	plus_btn.pressed.connect(func(): _adjust_trade_amount(1))
	amount_row.add_child(plus_btn)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	confirm_button = Button.new()
	confirm_button.text = "确认交易"
	confirm_button.custom_minimum_size = Vector2(180, 48)
	confirm_button.theme_type_variation = "SetSailButton"
	confirm_button.pressed.connect(_on_confirm_pressed)
	btn_hbox.add_child(confirm_button)

	back_button = Button.new()
	back_button.text = "离开市集"
	back_button.custom_minimum_size = Vector2(180, 48)
	back_button.theme_type_variation = "ChoiceButton"
	back_button.pressed.connect(_on_back_pressed)
	btn_hbox.add_child(back_button)

func _make_stat_chip(caption: String, value: String, id: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "PortStatChip"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)
	var cap_lbl := Label.new()
	cap_lbl.text = caption
	cap_lbl.theme_type_variation = "PortStatLabel"
	col.add_child(cap_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.theme_type_variation = "PortStatValue"
	col.add_child(val_lbl)
	if id == "money":
		money_value = val_lbl
	elif id == "cargo":
		cargo_value = val_lbl
	return chip

func _make_market_column(section_title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.theme_type_variation = "MarketPanel"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var header := Label.new()
	header.text = section_title
	header.theme_type_variation = "SectionLabel"
	col.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if section_title.contains("货舱"):
		inventory_container = list
	else:
		market_container = list
	return panel

func setup(_port_id: String) -> void:
	port_id = _port_id
	refresh_ui()

func refresh_ui() -> void:
	market_snapshot = EconomySystem.get_market_snapshot(port_id)
	title_label.text = "市舶互市 · " + GameManager.get_port_data(port_id).get("name", port_id)
	money_value.text = str(LedgerSystem.get_balance())
	cargo_value.text = "%d / %d" % [CargoSystem.get_total_cargo(), GameState.max_cargo]

	for child in inventory_container.get_children():
		child.queue_free()
	for child in market_container.get_children():
		child.queue_free()

	pending_intent = null
	_selected_good_id = ""
	_selected_action = ""
	_trade_amount = DEFAULT_TRADE_AMOUNT
	amount_row.visible = false
	preview_label.text = "选择商品预览交易"
	confirm_button.disabled = true

	var inv_empty := true
	for good_id in CargoSystem.get_keys():
		var amount := CargoSystem.get_amount(good_id)
		if amount <= 0:
			continue
		inv_empty = false
		var g_data := GameManager.get_good_data(good_id)
		var price := _get_live_price(good_id)
		var btn := _make_item_button(
			"%s  ×%d   卖出 %d" % [g_data.get("name", "未知"), amount, price],
			"sell"
		)
		btn.pressed.connect(_on_item_selected.bind(good_id, "sell"))
		inventory_container.add_child(btn)
	if inv_empty:
		inventory_container.add_child(_make_empty_label("货舱空空，尚无货物可售"))

	var mkt_empty := true
	for g in market_snapshot.get("goods", []):
		mkt_empty = false
		var live_price := _get_live_price(g.id)
		var btn := _make_item_button("%s   买入 %d" % [g.name, live_price], "buy")
		btn.pressed.connect(_on_item_selected.bind(g.id, "buy"))
		market_container.add_child(btn)
	if mkt_empty:
		market_container.add_child(_make_empty_label("今日港口暂无特产上架"))

func _make_item_button(text: String, kind: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 40)
	btn.theme_type_variation = "ActionButton" if kind == "buy" else "ChoiceButton"
	return btn

func _make_empty_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = "MarketPreview"
	return lbl

func _get_price_from_snapshot(good_id: String) -> int:
	for g in market_snapshot.get("goods", []):
		if g.id == good_id:
			return g.price
	return 0

func _get_live_price(good_id: String) -> int:
	var live := EconomySystem.get_price(port_id, good_id)
	if live > 0:
		return live
	return _get_price_from_snapshot(good_id)

func _on_item_selected(good_id: String, action: String) -> void:
	_selected_good_id = good_id
	_selected_action = action
	_trade_amount = min(DEFAULT_TRADE_AMOUNT, _max_trade_amount())
	if _trade_amount <= 0:
		preview_label.text = "无法交易该商品（货舱已满或余额不足）。"
		pending_intent = null
		confirm_button.disabled = true
		amount_row.visible = false
		return
	amount_row.visible = true
	_update_trade_preview()

func _max_trade_amount() -> int:
	if _selected_good_id.is_empty():
		return DEFAULT_TRADE_AMOUNT
	if _selected_action == "sell":
		return CargoSystem.get_amount(_selected_good_id)
	var price := _get_live_price(_selected_good_id)
	if price <= 0:
		return 0
	var by_balance := LedgerSystem.get_balance() / price
	var by_space := CargoSystem.get_available_space()
	return maxi(0, mini(by_balance, by_space))

func _adjust_trade_amount(delta: int) -> void:
	if _selected_good_id.is_empty():
		return
	var max_amt := _max_trade_amount()
	_trade_amount = clampi(_trade_amount + delta, 1, maxi(1, max_amt))
	_update_trade_preview()

func _update_trade_preview() -> void:
	var g_data := GameManager.get_good_data(_selected_good_id)
	var price := _get_live_price(_selected_good_id)
	var total := price * _trade_amount
	amount_value_label.text = str(_trade_amount)
	if _selected_action == "buy":
		preview_label.text = "买入 %d 单位「%s」\n花费 %d 钱 · 余额 %d" % [
			_trade_amount, g_data.get("name", _selected_good_id), total, LedgerSystem.get_balance() - total
		]
		pending_intent = Intent.new(
			"market_buy", "player", "market",
			{"good_id": _selected_good_id, "amount": _trade_amount},
			{"port_id": port_id}
		)
	else:
		preview_label.text = "卖出 %d 单位「%s」\n收入 %d 钱 · 结余 %d" % [
			_trade_amount, g_data.get("name", _selected_good_id), total, LedgerSystem.get_balance() + total
		]
		pending_intent = Intent.new(
			"market_sell", "player", "market",
			{"good_id": _selected_good_id, "amount": _trade_amount},
			{"port_id": port_id}
		)
	confirm_button.disabled = false

func _on_confirm_pressed() -> void:
	if pending_intent == null or confirm_button.disabled:
		return
	confirm_button.disabled = true
	back_button.disabled = true
	var result := IntentResolver.process(pending_intent)
	var txt := GameManager.get_text(result.message_key, "")
	if txt == "":
		txt = "交易成功。" if result.success else "交易失败。"
	message_logged.emit(txt + "\n")
	status_updated.emit()
	refresh_ui()
	back_button.disabled = false

func _on_back_pressed() -> void:
	market_closed.emit()
	queue_free()