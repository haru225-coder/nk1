extends Control
class_name MarketScreenController

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)
signal market_closed

const _THEME_PATH := ResourcePaths.THEME_MAIN
const DEFAULT_TRADE_AMOUNT := 10

var port_id: String = ""
var market_snapshot: Dictionary = {}
var _selected_good_id: String = ""
var _selected_action: String = ""
var _trade_amount: int = DEFAULT_TRADE_AMOUNT

var title_label: Label
var stock_alert_label: Label
var economy_info_label: Label
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
	bg.color = GameColors.MARKET_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(1040, 640)
	shell.theme_type_variation = UITheme.MARKET_SHELL
	center.add_child(shell)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	shell.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.theme_type_variation = UITheme.MARKET_TITLE
	vbox.add_child(title_label)

	stock_alert_label = Label.new()
	stock_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_alert_label.theme_type_variation = UITheme.MARKET_ALERT
	stock_alert_label.visible = false
	vbox.add_child(stock_alert_label)

	# NK1-P5-ECON-002: 经济信息栏 — 显示事件影响原因与经济动态
	economy_info_label = Label.new()
	economy_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	economy_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	economy_info_label.custom_minimum_size = Vector2(960, 110)
	economy_info_label.max_lines_visible = 7
	economy_info_label.theme_type_variation = UITheme.MARKET_PREVIEW
	economy_info_label.visible = false
	vbox.add_child(economy_info_label)

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
	preview_label.custom_minimum_size = Vector2(0, 56)
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.max_lines_visible = 3
	preview_label.theme_type_variation = UITheme.MARKET_PREVIEW
	vbox.add_child(preview_label)

	amount_row = HBoxContainer.new()
	amount_row.alignment = BoxContainer.ALIGNMENT_CENTER
	amount_row.add_theme_constant_override("separation", 8)
	amount_row.visible = false
	vbox.add_child(amount_row)
	var amount_caption := Label.new()
	amount_caption.text = "数量"
	amount_caption.theme_type_variation = UITheme.MARKET_PREVIEW
	amount_row.add_child(amount_caption)
	var minus_btn := UIBuilder.make_button("－", UITheme.BTN_CHOICE, 36)
	minus_btn.custom_minimum_size = Vector2(40, 36)
	minus_btn.pressed.connect(func(): _adjust_trade_amount(-1))
	amount_row.add_child(minus_btn)
	amount_value_label = Label.new()
	amount_value_label.custom_minimum_size = Vector2(64, 0)
	amount_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_value_label.theme_type_variation = UITheme.MARKET_PREVIEW
	amount_row.add_child(amount_value_label)
	var plus_btn := UIBuilder.make_button("＋", UITheme.BTN_CHOICE, 36)
	plus_btn.custom_minimum_size = Vector2(40, 36)
	plus_btn.pressed.connect(func(): _adjust_trade_amount(1))
	amount_row.add_child(plus_btn)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	confirm_button = UIBuilder.make_button("确认交易", UITheme.BTN_SET_SAIL, 48)
	confirm_button.custom_minimum_size = Vector2(180, 48)
	confirm_button.pressed.connect(_on_confirm_pressed)
	btn_hbox.add_child(confirm_button)
 
	back_button = UIBuilder.make_button("离开市集", UITheme.BTN_CHOICE, 48)
	back_button.custom_minimum_size = Vector2(180, 48)
	back_button.pressed.connect(_on_back_pressed)
	btn_hbox.add_child(back_button)

func _make_stat_chip(caption: String, value: String, id: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = UITheme.CHIP_PORT_STAT
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)
	var cap_lbl := Label.new()
	cap_lbl.text = caption
	cap_lbl.theme_type_variation = UITheme.LABEL_PORT_STAT
	col.add_child(cap_lbl)
	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.theme_type_variation = UITheme.VALUE_PORT_STAT
	col.add_child(val_lbl)
	if id == "money":
		money_value = val_lbl
	elif id == "cargo":
		cargo_value = val_lbl
	return chip

func _make_market_column(section_title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.theme_type_variation = UITheme.MARKET_PANEL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var header := Label.new()
	header.text = section_title
	header.theme_type_variation = UITheme.SECTION_LABEL
	col.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 340)
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
		var base_val = g_data.get("base_value", 50)
		var trend_info = _get_trend_info(price, base_val)
		var btn := _make_item_button(
			"%s  ×%d   卖出 %d %s" % [g_data.get("name", "未知"), amount, price, trend_info.text],
			"sell"
		)
		if trend_info.color != Color.TRANSPARENT:
			# [Code Audit Exemption] 颜色基于运行时价格走势动态计算，无法在 theme 中静态定义
			btn.add_theme_color_override("font_color", trend_info.color)
			btn.add_theme_color_override("font_hover_color", trend_info.color.lightened(0.2))
		btn.pressed.connect(_on_item_selected.bind(good_id, "sell"))
		inventory_container.add_child(btn)
	if inv_empty:
		inventory_container.add_child(_make_empty_label("货舱空空，尚无货物可售"))

	var mkt_empty := true
	for g in market_snapshot.get("goods", []):
		mkt_empty = false
		var live_price := _get_live_price(g.id)
		var base_val = g.get("base_value", 50)
		var trend_info = _get_trend_info(live_price, base_val)
		var btn := _make_item_button("%s   买入 %d %s" % [g.name, live_price, trend_info.text], "buy")
		if trend_info.color != Color.TRANSPARENT:
			# [Code Audit Exemption] 颜色基于运行时价格走势动态计算，无法在 theme 中静态定义
			btn.add_theme_color_override("font_color", trend_info.color)
			btn.add_theme_color_override("font_hover_color", trend_info.color.lightened(0.2))
		btn.pressed.connect(_on_item_selected.bind(g.id, "buy"))
		market_container.add_child(btn)
	if mkt_empty:
		market_container.add_child(_make_empty_label("今日港口暂无特产上架"))

	_check_stock_alert()
	_update_economy_info()

func _check_stock_alert() -> void:
	var all_goods: Array = GameManager.goods_data.get("goods", [])
	var alert := false
	for g in all_goods:
		var g_id: String = g.get("id", "")
		if g.get("category", "") != "货物" or g_id.is_empty():
			continue
		var ratio: float = GameManager.state.market.get_stock_ratio(port_id, g_id)
		if ratio > 2.5:
			alert = true
			break
	stock_alert_label.text = "【市集异动】此港部分商品库存紧张，价格已有明显波动。"
	stock_alert_label.visible = alert

## 经济信息栏：港情 + 三策（稳/赌/搬）+ 最近动态
func _update_economy_info() -> void:
	var lines: Array[String] = []

	# 1. 港口经济状态（繁荣度+好感度）
	var market = GameManager.state.market
	if market != null:
		var prosperity: float = market.get_prosperity(port_id)
		var affinity_label: String = market.get_affinity_label(port_id)
		var prosperity_str := "平稳"
		if prosperity > 1.1:
			prosperity_str = "繁荣"
		elif prosperity < 0.9:
			prosperity_str = "萧条"
		lines.append("港市：%s · 声誉：%s" % [prosperity_str, affinity_label])

	# 2. 三策（时间/空间/风险 — fun-economy 可感知）
	var Feel = load(ResourcePaths.SCRIPT_ECONOMY_FEEL)
	if Feel != null and Feel.has_method("strategy_triad"):
		for tip in Feel.strategy_triad(port_id):
			lines.append(str(tip))

	# 3. 活跃事件原因（最多 1 条，避免淹没三策）
	if market != null:
		var all_goods: Array = GameManager.goods_data.get("goods", [])
		var event_added := false
		for g in all_goods:
			if event_added:
				break
			var g_id: String = g.get("id", "")
			if g.get("category", "") != "货物" or g_id.is_empty():
				continue
			var reasons = market.get_active_event_reasons(port_id, g_id, WorldEventTracker.get_active_events())
			for r in reasons:
				lines.append(str(r))
				event_added = true
				break

	# 4. 已购情报（信息差资产）
	if GameState.intel_notes != null and GameState.intel_notes.has_method("list_recent"):
		var notes: Array = GameState.intel_notes.list_recent(2)
		if notes.size() > 0:
			var block: String = IntelNotes.format_notes_block(notes, 2)
			if block != "":
				for line in block.split("\n"):
					if str(line).strip_edges() != "":
						lines.append(str(line))

	# 5. 最近经济动态（1 条）
	if GameState.economy_log != null and GameState.economy_log.has_method("get_entries"):
		var recent: Array = GameState.economy_log.get_entries(1)
		for line in recent:
			var s := str(line).strip_edges()
			if s != "":
				lines.append(s)

	if lines.is_empty():
		economy_info_label.visible = false
	else:
		economy_info_label.text = "\n".join(lines)
		economy_info_label.visible = true

func _make_item_button(text: String, kind: String) -> Button:
	var theme_var = UITheme.BTN_ACTION if kind == "buy" else UITheme.BTN_CHOICE
	var btn := UIBuilder.make_button(text, theme_var, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = text
	btn.clip_text = true
	return btn

func _make_empty_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(0, 48)
	lbl.theme_type_variation = UITheme.MARKET_PREVIEW
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			IntentTypes.MARKET_BUY, "player", "market",
			{"good_id": _selected_good_id, "amount": _trade_amount},
			{"port_id": port_id}
		)
	else:
		preview_label.text = "卖出 %d 单位「%s」\n收入 %d 钱 · 结余 %d" % [
			_trade_amount, g_data.get("name", _selected_good_id), total, LedgerSystem.get_balance() + total
		]
		pending_intent = Intent.new(
			IntentTypes.MARKET_SELL, "player", "market",
			{"good_id": _selected_good_id, "amount": _trade_amount},
			{"port_id": port_id}
		)
	var effect_preview := _build_trade_effect_preview_text()
	if effect_preview != "":
		preview_label.text += "\n" + effect_preview
	# 商策：稳/赌/搬 针对当前选货
	var Feel = load(ResourcePaths.SCRIPT_ECONOMY_FEEL)
	if Feel != null and Feel.has_method("trade_decision_hint"):
		var hint: String = Feel.trade_decision_hint(port_id, _selected_good_id, _selected_action, _trade_amount)
		if hint != "":
			preview_label.text += "\n" + hint
	confirm_button.disabled = false

func _build_trade_effect_preview_text() -> String:
	if _selected_good_id.is_empty() or _selected_action.is_empty() or _trade_amount <= 0:
		return ""
	var intent_type := IntentTypes.MARKET_BUY if _selected_action == "buy" else IntentTypes.MARKET_SELL
	return StoryEventChainEngine.build_trigger_preview_text("trade_completed", {
		"port_id": port_id,
		"trade_action": _selected_action,
		"good_id": _selected_good_id,
		"amount": _trade_amount,
		"intent_type": intent_type,
		"game_state": GameState,
	})

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

func _get_trend_info(price: int, base: int) -> Dictionary:
	if base <= 0: return {"text": "", "color": Color.TRANSPARENT}
	var ratio := float(price) / float(base)
	if ratio >= 2.0:
		return {"text": "↑↑暴涨", "color": Color(1.0, 0.4, 0.4)}
	if ratio >= 1.2:
		return {"text": "↑涨", "color": GameColors.WARNING_SOFT}
	if ratio <= 0.5:
		return {"text": "↓↓暴跌", "color": GameColors.PRICE_CRASH}
	if ratio <= 0.8:
		return {"text": "↓跌", "color": GameColors.PRICE_DROP}
	return {"text": "", "color": Color.TRANSPARENT}
