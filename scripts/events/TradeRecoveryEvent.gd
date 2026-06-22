class_name TradeRecoveryEvent extends BaseEconomicEvent

func _init(port: String, days: int) -> void:
	super("trade_recovery", port, days)

func activate() -> void:
	var all_goods = GameManager.goods_data.get("goods", [])
	for g in all_goods:
		var g_id = g.get("id", "")
		if not g_id.is_empty():
			GameManager.state.market.reset_stock(target_port, g_id)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return 0.8
	return 1.0
