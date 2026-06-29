extends Node

# [C3-STABLE]
# INTERFACE FROZEN. DO NOT MODIFY API OR ADD NEW RESPONSIBILITIES.
# 事件类型与权重来源统一委托 BaseEconomicEvent 注册表，本类不再持有并行的事件 match/列表。

var active_events: Array[BaseEconomicEvent] = []

## 测试/运行时覆盖 max_triggers (不污染正式配置)
var max_triggers_overrides: Dictionary = {}

## ── 触发历史与冷却控制（NK1-P3-WORLDEVENT-002）──────────────────
var triggered_events: Dictionary = {}   # event_id -> true（全局）
var port_triggered: Dictionary = {}     # port_id -> { event_id: true }
var cooldowns: Dictionary = {}          # "event_id" (global) 或 "port_id:event_id" -> remaining_days

func add_event(event: BaseEconomicEvent, cooldown_days: int = 0) -> bool:
	if event == null:
		return false
	return try_activate_event(event, cooldown_days)

func try_activate_event(event: BaseEconomicEvent, cooldown_days: int = 0) -> bool:
	if event == null:
		return false
	var eid := event.event_id
	var pid := event.target_port
	if not can_trigger_event(eid, pid):
		return false

	var cd := cooldown_days
	var use_global := false
	if "cooldown_days" in event and cd <= 0:
		cd = event.cooldown_days
	if "use_global_cooldown" in event:
		use_global = event.use_global_cooldown

	# 防止同一激活事件重复叠加（刷新持续时间）
	for e in active_events:
		if e.event_id == eid and e.target_port == pid:
			e.duration_days = max(e.duration_days, event.duration_days)
			record_trigger(eid, pid, cd, use_global)
			return true

	active_events.append(event)
	record_trigger(eid, pid, cd, use_global)
	return true

func process_day() -> void:
	var remaining: Array[BaseEconomicEvent] = []
	for e in active_events:
		if e.tick_day():
			remaining.append(e)
	active_events = remaining

	# 冷却倒计时
	var next: Dictionary = {}
	for k in cooldowns:
		var d := int(cooldowns[k]) - 1
		if d > 0:
			next[k] = d
	cooldowns = next

	# NK1-P5-ECON-002: 事件链偏置每日衰减
	_decay_chain_bias()

func get_active_events() -> Array[BaseEconomicEvent]:
	return active_events

## ── 触发控制 API ───────────────────────────────────────────
func can_trigger_event(event_id: String, port_id: String = "") -> bool:
	var max_t = _get_max_triggers(event_id)
	if max_t > 0:
		var use_g = _use_global_cooldown(event_id) or port_id == ""
		if use_g:
			# strictly respect global cooldown setting
			if int(triggered_events.get(event_id, 0)) >= max_t:
				return false
		else:
			# per-port only
			if port_id != "":
				var pmap = port_triggered.get(port_id, {})
				var pcount = int(pmap.get(event_id, 0))
				if pcount >= max_t:
					return false
	if is_on_cooldown(event_id, port_id):
		return false
	return true

func is_on_cooldown(event_id: String, port_id: String = "") -> bool:
	if cooldowns.get(event_id, 0) > 0:
		return true
	if port_id != "" and cooldowns.get(port_id + ":" + event_id, 0) > 0:
		return true
	return false

func is_event_triggered(event_id: String, port_id: String = "") -> bool:
	if int(triggered_events.get(event_id, 0)) > 0:
		return true
	if port_id != "" and port_triggered.has(port_id) and int(port_triggered[port_id].get(event_id, 0)) > 0:
		return true
	return false

func record_trigger(event_id: String, port_id: String = "", cooldown_days: int = 0, use_global: bool = false) -> void:
	# increment count for max_triggers support
	var gcount = int(triggered_events.get(event_id, 0))
	triggered_events[event_id] = gcount + 1

	if port_id != "":
		if not port_triggered.has(port_id):
			port_triggered[port_id] = {}
		var pcount = int(port_triggered[port_id].get(event_id, 0))
		port_triggered[port_id][event_id] = pcount + 1

	if cooldown_days > 0:
		var key := event_id if (use_global or port_id == "") else (port_id + ":" + event_id)
		cooldowns[key] = cooldown_days

## 调试与重置接口
func clear_trigger_history() -> void:
	triggered_events.clear()
	port_triggered.clear()

func clear_cooldowns() -> void:
	cooldowns.clear()

## NK1-P5-ECON-002: 事件链偏置 — 灾难结束后恢复事件权重提升
## event_chain_bias[port_id][event_id] = float（额外权重倍率）
var event_chain_bias: Dictionary = {}

## 设置事件链偏置（灾难结束后调用，提升恢复事件权重）
func set_chain_bias(port_id: String, event_id: String, bias: float) -> void:
	if not event_chain_bias.has(port_id):
		event_chain_bias[port_id] = {}
	event_chain_bias[port_id][event_id] = bias

## 获取事件链偏置
func get_chain_bias(port_id: String, event_id: String) -> float:
	if event_chain_bias.has(port_id) and event_chain_bias[port_id].has(event_id):
		return float(event_chain_bias[port_id][event_id])
	return 1.0

## 每日衰减事件链偏置（缓慢回归 1.0）
func _decay_chain_bias() -> void:
	for port_id in event_chain_bias.keys():
		for eid in event_chain_bias[port_id].keys():
			var current: float = float(event_chain_bias[port_id][eid])
			if absf(current - 1.0) < 0.01:
				event_chain_bias[port_id].erase(eid)
			else:
				event_chain_bias[port_id][eid] = lerpf(current, 1.0, 0.1)

func reset_event_trigger(event_id: String, port_id: String = "") -> void:
	triggered_events.erase(event_id)
	if port_id != "" and port_triggered.has(port_id):
		port_triggered[port_id].erase(event_id)
	cooldowns.erase(event_id)
	if port_id != "":
		cooldowns.erase(port_id + ":" + event_id)

func _get_event_sample(event_id: String) -> BaseEconomicEvent:
	# 委托 BaseEconomicEvent 注册表，避免此处重复维护事件 match
	var sample := BaseEconomicEvent.create(event_id, "", 0)
	if sample.event_id == event_id:
		return sample
	return null

func _get_max_triggers(event_id: String) -> int:
	if max_triggers_overrides.has(event_id):
		return int(max_triggers_overrides[event_id])
	var sample = _get_event_sample(event_id)
	return sample.max_triggers if sample != null else -1

func _use_global_cooldown(event_id: String) -> bool:
	var sample = _get_event_sample(event_id)
	return sample.use_global_cooldown if sample != null else false

## ── 权重与智能选择（NK1-P3-WORLDEVENT-003）─────────────────────
func get_adjusted_weight(base_weight: float, event_id: String, port_id: String = "") -> float:
	var w := base_weight
	var max_t = _get_max_triggers(event_id)
	if max_t > 0:
		var use_g = _use_global_cooldown(event_id) or port_id == ""
		var limit_reached := false
		if use_g:
			if int(triggered_events.get(event_id, 0)) >= max_t:
				limit_reached = true
		else:
			if port_id != "":
				var pmap = port_triggered.get(port_id, {})
				if int(pmap.get(event_id, 0)) >= max_t:
					limit_reached = true
		if limit_reached:
			w *= 0.001  # 已达最大次数，极低权重
	elif is_event_triggered(event_id, port_id):
		w *= 0.05  # 已触发大幅降低
	if is_on_cooldown(event_id, port_id):
		w *= 0.01  # 冷却中几乎排除
	# NK1-P5-ECON-002: 事件链偏置（灾难后恢复事件更容易触发）
	w *= get_chain_bias(port_id, event_id)
	return max(w, 0.001)

func get_weighted_event_candidates(port_id: String = "") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	# 候选来源委托 BaseEconomicEvent 注册表，新增事件自动纳入权重选择
	for ev in BaseEconomicEvent.all_samples():
		var eid: String = ev.event_id
		var bw: float = ev.base_weight
		var w := get_adjusted_weight(bw, eid, port_id)
		results.append({
			"event_id": eid,
			"port_id": port_id,
			"weight": w
		})
	return results

## ── 存档序列化（NK1-P3-WORLDEVENT-001 + 002）───────────────────
func to_save_dict() -> Dictionary:
	var event_list: Array = []
	for e in active_events:
		if e != null:
			if e.has_method("to_dict"):
				event_list.append(e.to_dict())
			else:
				event_list.append({
					"event_id": e.event_id,
					"target_port": e.target_port,
					"duration_days": e.duration_days
				})
	return {
		"active_events": event_list,
		"triggered_events": triggered_events.duplicate(),
		"port_triggered": port_triggered.duplicate(true),
		"cooldowns": cooldowns.duplicate(),
		"version": 2
	}

func from_save_dict(data: Dictionary) -> void:
	active_events.clear()
	for ed in data.get("active_events", []):
		if ed is Dictionary:
			var e := BaseEconomicEvent.from_dict(ed)
			if e != null:
				active_events.append(e)

	# support counts (int) and old bool data for compatibility
	var raw_triggered = data.get("triggered_events", {})
	triggered_events.clear()
	for k in raw_triggered:
		var v = raw_triggered[k]
		triggered_events[k] = int(v) if v is int or v is float else (1 if bool(v) else 0)

	var raw_port = data.get("port_triggered", {})
	port_triggered.clear()
	for p in raw_port:
		var inner = {}
		for eid in raw_port[p]:
			var v = raw_port[p][eid]
			inner[eid] = int(v) if v is int or v is float else (1 if bool(v) else 0)
		port_triggered[p] = inner

	var raw_cooldowns = data.get("cooldowns", {})
	cooldowns.clear()
	for k in raw_cooldowns:
		cooldowns[k] = int(raw_cooldowns[k])
	# 旧存档（version 1）字段缺失时自动使用空字典，保持兼容
