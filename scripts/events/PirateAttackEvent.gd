class_name PirateAttackEvent extends BaseEconomicEvent

func _init(port: String, days: int) -> void:
	super("pirate_attack", port, days)

# 海盗袭击会导致物资短缺，所有商品物价飞涨，特别是粮食和武器（暂未细分种类，先全局涨价）
func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return 1.5 # 50% 物价上涨扰动
	return 1.0
