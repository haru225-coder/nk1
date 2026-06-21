extends Node

# [C3-STABLE]
# INTERFACE FROZEN. DO NOT MODIFY API OR ADD NEW RESPONSIBILITIES.

var active_events: Array[BaseEconomicEvent] = []

func add_event(event: BaseEconomicEvent) -> void:
	# 防止事件重复叠加 (Stacking Bug)
	for e in active_events:
		if e.event_id == event.event_id and e.target_port == event.target_port:
			e.duration_days = max(e.duration_days, event.duration_days) # 刷新持续时间
			return
			
	active_events.append(event)

func process_day() -> void:
	var remaining: Array[BaseEconomicEvent] = []
	for e in active_events:
		if e.tick_day():
			remaining.append(e)
	active_events = remaining

func get_active_events() -> Array[BaseEconomicEvent]:
	return active_events
