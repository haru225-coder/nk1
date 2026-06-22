class_name TradeDisasterEvent extends BaseEconomicEvent

func _init(port: String, days: int) -> void:
	super("trade_disaster", port, days)

func activate() -> void:
	var all_goods = GameManager.goods_data.get("goods", [])
	for g in all_goods:
		var g_id = g.get("id", "")
		if not g_id.is_empty():
			var stock = GameManager.state.market.get_stock(target_port, g_id)
			GameManager.state.market.adjust_stock(target_port, g_id, -stock)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return 2.5
	return 1.0
