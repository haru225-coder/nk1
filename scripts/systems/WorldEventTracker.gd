extends Node

# [C3-STABLE]
# INTERFACE FROZEN. DO NOT MODIFY API OR ADD NEW RESPONSIBILITIES.

var active_events: Array[BaseEconomicEvent] = []

func add_event(event: BaseEconomicEvent) -> void:
	# 防止事件重复叠加 (Stacking Bug)
	for e in active_events:
		if e.event_id == event.event_id and e.target_port == event.target_port:
			e.duration_days = max(e.duration_days, event.duration_days) # 刷新持续时间
			print("[WorldEventTracker] 事件已存在，刷新持续时间: ", event.event_id)
			return
			
	active_events.append(event)
	print("[WorldEventTracker] 新增事件: ", event.event_id, " 目标: ", event.target_port, " 持续时间: ", event.duration_days, " 天")

func process_day() -> void:
	var remaining: Array[BaseEconomicEvent] = []
	for e in active_events:
		if e.tick_day():
			remaining.append(e)
		else:
			print("[WorldEventTracker] 事件结束: ", e.event_id, " 目标: ", e.target_port)
	active_events = remaining

func get_active_events() -> Array[BaseEconomicEvent]:
	return active_events

func print_status() -> void:
	var names = []
	for e in active_events:
		names.append(e.event_id + " (port:" + e.target_port + ", " + str(e.duration_days) + "d)")
	print("[WorldEventTracker] 当前活跃事件: ", names if names.size() > 0 else "无")
