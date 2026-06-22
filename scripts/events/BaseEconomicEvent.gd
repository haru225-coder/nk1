class_name BaseEconomicEvent extends RefCounted

var event_id: String = "base_event"
var target_port: String = ""
var duration_days: int = 0

func _init(id: String, port: String, days: int) -> void:
	event_id = id
	target_port = port
	duration_days = days

func tick_day() -> bool:
	duration_days -= 1
	return duration_days > 0

# 返回一个扰动倍率，如果不受影响返回 1.0
func get_price_modifier(port_id: String, good_id: String) -> float:
	return 1.0

# 预告池转正时的副作用
func activate() -> void:
	pass
