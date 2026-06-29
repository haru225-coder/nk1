class_name TradeEventGenerator extends RefCounted

## NK1-P6-POLISH-002: 事件生成器 — 参数从 events_config.json 读取
const PirateAttackEvent = preload(ResourcePaths.SCRIPT_PIRATE_ATTACK)
const TradeDisasterEvent = preload(ResourcePaths.SCRIPT_TRADE_DISASTER)
const TradeRecoveryEvent = preload(ResourcePaths.SCRIPT_TRADE_RECOVERY)
const SupplyShortageEvent = preload(ResourcePaths.SCRIPT_SUPPLY_SHORTAGE)
const TradeBoomEvent = preload(ResourcePaths.SCRIPT_TRADE_BOOM)
const EconomicRippleEvent = preload(ResourcePaths.SCRIPT_ECONOMIC_RIPPLE)

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const DAILY_EVENT_CHANCE := 0.08
const INTEL_TIER_COSTS := [20, 50, 120]
const _RUMOR_DELAY_MIN := 5
const _RUMOR_DELAY_MAX := 15
const _VALID_PORT_STATUSES := ["main", "thread"]
const _GOOD_CATEGORY := "货物"

static func try_generate() -> void:
	_try_safety_valve()

	# NK1-P6-POLISH-002: 概率从配置加载
	var gen_cfg: Dictionary = EventConfigLoader.get_generator_config()
	var daily_chance: float = float(gen_cfg.get("daily_event_chance", DAILY_EVENT_CHANCE))
	if randf() > daily_chance:
		return

	var ports = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return

	var valid_ports: Array = []
	var statuses: Array = gen_cfg.get("valid_port_statuses", _VALID_PORT_STATUSES)
	for p in ports:
		var status = p.get("status", "")
		if status in statuses:
			valid_ports.append(p)

	if valid_ports.is_empty():
		return

	var port = valid_ports[randi() % valid_ports.size()]
	var port_id = port.get("id", "")

	# 使用加权选择（考虑触发历史与冷却）
	var candidates := WorldEventTracker.get_weighted_event_candidates(port_id)
	var total_w := 0.0
	for c in candidates:
		total_w += c.get("weight", 0.0)
	if total_w <= 0.0:
		return

	var r := randf() * total_w
	var chosen := candidates[0]
	for c in candidates:
		r -= c.get("weight", 0.0)
		if r <= 0.0:
			chosen = c
			break

	var event: BaseEconomicEvent
	var ev_type := ""
	match chosen.get("event_id", ""):
		"trade_disaster":
			event = TradeDisasterEvent.new(port_id, EventConfigLoader.get_initial_duration("trade_disaster", 10))
			ev_type = "disaster"
		"trade_recovery":
			event = TradeRecoveryEvent.new(port_id, EventConfigLoader.get_initial_duration("trade_recovery", 10))
			ev_type = "recovery"
		"pirate_attack":
			event = PirateAttackEvent.new(port_id, EventConfigLoader.get_initial_duration("pirate_attack", 5))
			ev_type = "pirate"
		"supply_shortage":
			var ss_event := SupplyShortageEvent.new(port_id, EventConfigLoader.get_initial_duration("supply_shortage", 8))
			ss_event.target_good = _pick_shortage_good(port)
			event = ss_event
			ev_type = "shortage"
		"trade_boom":
			event = TradeBoomEvent.new(port_id, EventConfigLoader.get_initial_duration("trade_boom", 12))
			ev_type = "boom"
		"economic_ripple":
			event = EconomicRippleEvent.new(port_id, EventConfigLoader.get_initial_duration("economic_ripple", 8))
			ev_type = "ripple"
		_:
			return

	if not WorldEventTracker.can_trigger_event(event.event_id, port_id):
		return  # 已触发或冷却中，避免生成重复的待触发事件

	if is_event_upcoming(event.event_id, port_id):
		return  # 已有相同的潜伏事件，避免重复生成

	# NK1-P6-POLISH-002: 潜伏期从配置加载
	var delay_min: int = int(gen_cfg.get("rumor_delay_min", _RUMOR_DELAY_MIN))
	var delay_max: int = int(gen_cfg.get("rumor_delay_max", _RUMOR_DELAY_MAX))
	var delay: int = randi_range(delay_min, delay_max)
	GameManager.state.market.upcoming_events.append({"event": event, "days_left": delay, "type": ev_type, "port_name": port.get("name", port_id)})

## NK1-P5-ECON-003: 为供应短缺事件选择一个合适的商品
## 优先选择该港口生产的商品，否则随机选一个货物
static func _pick_shortage_good(port: Dictionary) -> String:
	var prod_dict = port.get("production", {})
	if not prod_dict.is_empty():
		var keys = prod_dict.keys()
		if not keys.is_empty():
			return keys[randi() % keys.size()]
	# 无产出则随机选一个货物
	var all_goods = GameManager.goods_data.get("goods", [])
	var cargo_goods: Array = []
	for g in all_goods:
		if g.get("category", "") == "货物":
			cargo_goods.append(g.get("id", ""))
	if not cargo_goods.is_empty():
		return cargo_goods[randi() % cargo_goods.size()]
	return ""

static func _try_safety_valve() -> void:
	var ports = GameManager.ports_data.get("ports", [])
	if ports.is_empty():
		return
		
	var valid_ports = []
	for p in ports:
		var status = p.get("status", "")
		if status == "main" or status == "thread":
			valid_ports.append(p)
			
	if valid_ports.is_empty():
		return
		
	var all_goods = GameManager.goods_data.get("goods", [])
	if all_goods.is_empty():
		return
		
	var total_ratio = 0.0
	var count = 0
	
	for p in valid_ports:
		var port_id = p.get("id", "")
		for g in all_goods:
			var g_id = g.get("id", "")
			if g.get("category", "") == "货物" and not g_id.is_empty():
				var stock = GameManager.state.market.get_stock(port_id, g_id)
				var base = GameManager.state.market.get_base_stock(port_id, g_id)
				# 弱化恶意操纵：截断倾销上限，计算比率时最大库存计为 4 倍基准
				var capped_stock = min(stock, base * 4.0)
				var ratio = float(base) / float(capped_stock) if capped_stock > 0 else 5.0
				total_ratio += clampf(ratio, 0.2, 5.0)
				count += 1
				
	if count > 0:
		var avg_ratio = total_ratio / count
		# 恢复为 0.3 阈值，已通过 capped_stock 在数学上杜绝了过度倾销控盘
		if avg_ratio < 0.3:
			var port = valid_ports[randi() % valid_ports.size()]
			var port_id = port.get("id", "")
			
			# 直接校验并尊重恢复事件的加权权重（冷却中或达上限则不触发）
			var candidates := WorldEventTracker.get_weighted_event_candidates(port_id)
			var rec_weight := 0.0
			for c in candidates:
				if c.get("event_id", "") == "trade_recovery":
					rec_weight = c.get("weight", 0.0)
					break
			if rec_weight < 0.1:
				return
				
			var event := TradeRecoveryEvent.new(port_id, 10)
			if not WorldEventTracker.can_trigger_event(event.event_id, port_id):
				return
			if is_event_upcoming(event.event_id, port_id):
				return
			var delay = randi_range(1, 3)
			GameManager.state.market.upcoming_events.append({"event": event, "days_left": delay, "type": "recovery", "port_name": port.get("name", port_id)})

static func process_day() -> void:
	var remaining: Array[Dictionary] = []
	for item in GameManager.state.market.upcoming_events:
		item["days_left"] -= 1
		if item["days_left"] <= 0:
			var event = item["event"] as BaseEconomicEvent
			if event != null:
				var pid: String = event.target_port
				if WorldEventTracker.can_trigger_event(event.event_id, pid):
					event.activate(GameState.market)
					WorldEventTracker.add_event(event)  # 使用事件自身配置的 cooldown_days
				# 已触发或冷却中则跳过激活效果，事件直接过期移除
		else:
			remaining.append(item)
	GameManager.state.market.upcoming_events = remaining

static func get_tier_cost(tier: int) -> int:
	if tier < 1 or tier > INTEL_TIER_COSTS.size():
		return 0
	return INTEL_TIER_COSTS[tier - 1]

static func get_random_rumor() -> Dictionary:
	var entry := get_random_rumor_entry()
	return entry.get("rumor", {})

static func get_random_rumor_entry() -> Dictionary:
	var events = GameManager.state.market.upcoming_events
	var candidates: Array[Dictionary] = []
	for i in range(events.size()):
		var item: Dictionary = events[i]
		if not item.get("purchased", false):
			candidates.append({"index": i, "rumor": item})
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]

static func get_event_at(index: int) -> Dictionary:
	var events = GameManager.state.market.upcoming_events
	if index < 0 or index >= events.size():
		return {}
	return events[index]

static func is_rumor_purchased(index: int) -> bool:
	var event := get_event_at(index)
	if event.is_empty():
		return false
	return bool(event.get("purchased", false))

static func mark_rumor_purchased(index: int) -> bool:
	var events = GameManager.state.market.upcoming_events
	if index < 0 or index >= events.size():
		return false
	if events[index].get("purchased", false):
		return false
	events[index]["purchased"] = true
	return true

static func is_event_upcoming(event_id: String, port_id: String) -> bool:
	var events = GameManager.state.market.upcoming_events
	for item in events:
		var event = item.get("event") as BaseEconomicEvent
		if event != null and event.event_id == event_id and event.target_port == port_id:
			return true
	return false
