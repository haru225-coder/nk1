extends Control
class_name MarketScreenController

signal scene_requested(scene_id: String)
signal status_updated
signal message_logged(msg: String)

var port_id: String = ""
var market_snapshot: Dictionary = {}

var title_label: Label
var money_label: Label
var cargo_label: Label
var inventory_container: VBoxContainer
var market_container: VBoxContainer
var preview_label: Label
var confirm_button: Button
var back_button: Button

var pending_intent: Intent = null

func _ready() -> void:
	# 强行构建全代码 UI 树 (临时替代 tscn)
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vbox)
	add_child(margin)
	
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title_label)
	
	var info_hbox = HBoxContainer.new()
	info_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_hbox.add_theme_constant_override("separation", 50)
	vbox.add_child(info_hbox)
	
	money_label = Label.new()
	info_hbox.add_child(money_label)
	cargo_label = Label.new()
	info_hbox.add_child(cargo_label)
	
	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(split)
	
	var left_panel = PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left_scroll = ScrollContainer.new()
	inventory_container = VBoxContainer.new()
	inventory_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(inventory_container)
	left_panel.add_child(left_scroll)
	split.add_child(left_panel)
	
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_scroll = ScrollContainer.new()
	market_container = VBoxContainer.new()
	market_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(market_container)
	right_panel.add_child(right_scroll)
	split.add_child(right_panel)
	
	preview_label = Label.new()
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(preview_label)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_hbox)
	
	confirm_button = Button.new()
	confirm_button.text = "确认交易"
	confirm_button.custom_minimum_size = Vector2(150, 50)
	confirm_button.pressed.connect(_on_confirm_pressed)
	btn_hbox.add_child(confirm_button)
	
	back_button = Button.new()
	back_button.text = "离开市集"
	back_button.custom_minimum_size = Vector2(150, 50)
	back_button.pressed.connect(_on_back_pressed)
	btn_hbox.add_child(back_button)

func setup(_port_id: String) -> void:
	port_id = _port_id
	refresh_ui()

func refresh_ui() -> void:
	market_snapshot = EconomySystem.get_market_snapshot(port_id)
	
	title_label.text = "市舶司 / 互市 - " + GameManager.get_port_data(port_id).get("name", "")
	money_label.text = "铜钱: %d" % LedgerSystem.get_balance()
	
	cargo_label.text = "货舱: %d / %d" % [CargoSystem.get_total_cargo(), GameState.max_cargo]
	
	for child in inventory_container.get_children(): child.queue_free()
	for child in market_container.get_children(): child.queue_free()
	
	pending_intent = null
	preview_label.text = "请选择要交易的商品 (每次默认 10 单位)"
	confirm_button.disabled = true
	
	# 左侧：玩家库存 (只显示能卖的)
	var inv_title = Label.new()
	inv_title.text = "--- 你的货舱 (点击卖出) ---"
	inventory_container.add_child(inv_title)
	for good_id in GameState.cargo.keys():
		var amount = GameState.cargo[good_id]
		if amount <= 0: continue
		var g_data = GameManager.get_good_data(good_id)
		var btn = Button.new()
		var price = _get_price_from_snapshot(good_id)
		btn.text = "%s (数量: %d) - 卖出价: %d" % [g_data.get("name", "未知"), amount, price]
		btn.pressed.connect(_on_item_selected.bind(good_id, "sell", price))
		inventory_container.add_child(btn)
		
	# 右侧：港口特产 (只显示能买的)
	var mkt_title = Label.new()
	mkt_title.text = "--- 港口特产 (点击买入) ---"
	market_container.add_child(mkt_title)
	for g in market_snapshot.get("goods", []):
		var btn = Button.new()
		btn.text = "%s - 买入价: %d" % [g.name, g.price]
		btn.pressed.connect(_on_item_selected.bind(g.id, "buy", g.price))
		market_container.add_child(btn)

func _get_price_from_snapshot(good_id: String) -> int:
	for g in market_snapshot.get("goods", []):
		if g.id == good_id: return g.price
	return 0

func _on_item_selected(good_id: String, action: String, price: int) -> void:
	var g_data = GameManager.get_good_data(good_id)
	
	# MVP：如果卖出，最多只能卖现有的库存；买入默认10，或按需调整。
	var amount = 10
	if action == "sell":
		amount = min(10, GameState.cargo.get(good_id, 0))
		
	var total = price * amount
	if action == "buy":
		preview_label.text = "预计买入 %d %s，花费: %d 钱\n剩余: %d 钱" % [amount, g_data.name, total, LedgerSystem.get_balance() - total]
		pending_intent = Intent.new("market_buy", "player", "market", {"good_id": good_id, "amount": amount}, {"port_id": port_id})
	else:
		preview_label.text = "预计卖出 %d %s，收入: %d 钱\n结余: %d 钱" % [amount, g_data.name, total, LedgerSystem.get_balance() + total]
		pending_intent = Intent.new("market_sell", "player", "market", {"good_id": good_id, "amount": amount}, {"port_id": port_id})
		
	confirm_button.disabled = false

func _on_confirm_pressed() -> void:
	if pending_intent != null:
		var result = IntentResolver.process(pending_intent)
		var txt = GameManager.get_text(result.message_key, result.message_key)
		# 如果字典没找到，直接输出 message_key (对于 TradeHandler 中的 msg，暂且直接显示)
		if result.message_key.begins_with("intent.") or result.message_key.begins_with("error."):
			pass # 需要翻译
		else:
			# TradeHandler 中的 execute_buy/sell 会打出中文，暂时妥协直接抓 log
			pass
		message_logged.emit(txt + "\n")
		status_updated.emit()
		refresh_ui()

func _on_back_pressed() -> void:
	queue_free()
