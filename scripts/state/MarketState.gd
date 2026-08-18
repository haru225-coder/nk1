class_name MarketState extends RefCounted

## 【P7-B 边界冻结】字段集冻结。
## 新经济机制进 EconomySystem / PriceEngine / events/*，
## 不要再往 MarketState 加第三类字典（库存/繁荣/好感/特产已够）。

# port_stocks[port_id][good_id] = {"stock": 800, "base_stock": 1000}
var port_stocks: Dictionary = {}

# 预告池：尚未爆发、正在倒计时的贸易事件
# 元素结构：{"event": BaseEconomicEvent, "days_left": int}
var upcoming_events: Array[Dictionary] = []

# ── NK1-P5-ECON-002: 玩家长期行为追踪 ──────────────────────
# trade_history[port_id][good_id] = {"net_flow": int, "total_volume": int}
# net_flow > 0: 玩家净倾销（卖出多于买入）；net_flow < 0: 玩家净采购
var trade_history: Dictionary = {}

# 港口繁荣度：1.0=正常，>1.0=繁荣（交易活跃），<1.0=萧条（受灾难影响）
# 范围 [0.7, 1.3]，影响库存恢复速度和基础价格倾向
var port_prosperity: Dictionary = {}

# ── NK1-P5-ECON-003: 港口好感度（玩家声誉）──────────────────
# port_affinity[port_id] = float，范围 [-20, 20]，0=中立
# >0: 好感度高，交易价格优惠（买入便宜、卖出划算）
# <0: 好感度低，交易价格惩罚（买入贵、卖出便宜）
var port_affinity: Dictionary = {}

# unlocked_specialties[port_id] = Array[String] 已解锁的隐藏特产 good_id
var unlocked_specialties: Dictionary = {}

# ── 常量参数 ───────────────────────────────────────────────
const _PROSPERITY_MIN := 0.7
const _PROSPERITY_MAX := 1.3
const _SATURATION_IMPACT := 0.0003   # 每单位净流入对饱和度的影响系数
const _SATURATION_MAX_EFFECT := 0.30 # 饱和最多压低 30% 基础价
const _PROSPERITY_TRADE_GAIN := 0.002  # 每笔交易对繁荣度的增益
const _PROSPERITY_DAILY_DECAY := 0.001 # 每日繁荣度自然回归
# NK1-P5-ECON-003: 好感度参数
const _AFFINITY_MIN := -20.0
const _AFFINITY_MAX := 20.0
const _AFFINITY_TRADE_GAIN := 0.05   # 每笔交易好感度增益
const _AFFINITY_DAILY_DECAY := 0.02  # 每日好感度自然回归
const _AFFINITY_PRICE_IMPACT := 0.003 # 每点好感度对价格的影响系数
const _STOCK_REGEN_RATE := 0.05       # 每日库存向 base_stock 回归的缺口比例

func init_from_ports(ports: Array, goods: Array) -> void:
	for port in ports:
		var port_id = port.get("id", "")
		if port_id.is_empty():
			continue
			
		port_stocks[port_id] = {}
		
		for good in goods:
			var good_id = good.get("id", "")
			if good_id.is_empty() or good.get("category", "") != "货物":
				continue
				
			var base_value = good.get("base_value", 50)
			var base_stock = base_value * 8 # Default
			
			var prod_dict = port.get("production", {})
			if prod_dict.has(good_id):
				base_stock = base_value * 15 # Producer
				
			var demand_dict = port.get("demand", {})
			if demand_dict.has(good_id):
				base_stock = base_value * 3 # Consumer
				
			port_stocks[port_id][good_id] = {
				"stock": base_stock,
				"base_stock": base_stock
			}

func get_stock(port_id: String, good_id: String) -> int:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return 0
	return port_stocks[port_id][good_id]["stock"]

func get_base_stock(port_id: String, good_id: String) -> int:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return 0
	return port_stocks[port_id][good_id]["base_stock"]

func get_stock_ratio(port_id: String, good_id: String) -> float:
	var stock = float(get_stock(port_id, good_id))
	if stock <= 0:
		return 5.0 # Max price
	var base_stock = float(get_base_stock(port_id, good_id))
	var ratio = base_stock / stock
	return clampf(ratio, 0.2, 5.0)

## 临时按 delta 调整库存后询价，再还原。不写 trade_history，避免预览污染。
## 运行时 load EconomySystem，避免 MarketState ↔ EconomySystem 编译期环依赖。
func preview_price_stock(port_id: String, good_id: String, delta: int, for_buy: bool = true) -> int:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return _query_live_price(port_id, good_id, for_buy)
	var entry: Dictionary = port_stocks[port_id][good_id]
	var original: int = int(entry.get("stock", 0))
	entry["stock"] = maxi(0, original + delta)
	var price := _query_live_price(port_id, good_id, for_buy)
	entry["stock"] = original
	return price

func _query_live_price(port_id: String, good_id: String, for_buy: bool = true) -> int:
	var es = load("res://scripts/systems/EconomySystem.gd")
	if es != null and es.has_method("get_price"):
		return int(es.get_price(port_id, good_id, for_buy))
	return 0

func adjust_stock(port_id: String, good_id: String, delta: int) -> void:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return
	var current = port_stocks[port_id][good_id]["stock"]
	port_stocks[port_id][good_id]["stock"] = maxi(0, current + delta)
	# NK1-P5-ECON-002: 记录贸易历史（delta>0=卖出/倾销, delta<0=买入/采购）
	_record_trade(port_id, good_id, delta)

func reset_stock(port_id: String, good_id: String) -> void:
	if not port_stocks.has(port_id) or not port_stocks[port_id].has(good_id):
		return
	port_stocks[port_id][good_id]["stock"] = port_stocks[port_id][good_id]["base_stock"]

# ── NK1-P5-ECON-002: 贸易历史与长期影响 ───────────────────

## 记录玩家交易行为（由 adjust_stock 自动调用）
func _record_trade(port_id: String, good_id: String, delta: int) -> void:
	if not trade_history.has(port_id):
		trade_history[port_id] = {}
	if not trade_history[port_id].has(good_id):
		trade_history[port_id][good_id] = {"net_flow": 0, "total_volume": 0}
	trade_history[port_id][good_id]["net_flow"] += delta
	trade_history[port_id][good_id]["total_volume"] += absi(delta)
	# 交易活跃→繁荣度提升
	_adjust_prosperity(port_id, _PROSPERITY_TRADE_GAIN * (1.0 if delta > 0 else 0.5))
	# NK1-P5-ECON-003: 交易提升港口好感度（买入提升更多，因为给港口带来货源）
	_adjust_affinity(port_id, _AFFINITY_TRADE_GAIN * (1.2 if delta < 0 else 0.8))

## 获取市场饱和修正因子（持续倾销压低基础价）
## 返回 0.7~1.0，net_flow 越高（倾销越多）修正越低
func get_saturation_mod(port_id: String, good_id: String) -> float:
	if not trade_history.has(port_id) or not trade_history[port_id].has(good_id):
		return 1.0
	var net_flow: int = trade_history[port_id][good_id].get("net_flow", 0)
	if net_flow <= 0:
		return 1.0  # 净采购不影响基础价
	var reduction = clampf(float(net_flow) * _SATURATION_IMPACT, 0.0, _SATURATION_MAX_EFFECT)
	return 1.0 - reduction

## 获取港口繁荣度（默认 1.0）
func get_prosperity(port_id: String) -> float:
	return clampf(float(port_prosperity.get(port_id, 1.0)), _PROSPERITY_MIN, _PROSPERITY_MAX)

## 调整繁荣度（内部，自动 clamp）
func _adjust_prosperity(port_id: String, delta: float) -> void:
	var current := get_prosperity(port_id)
	port_prosperity[port_id] = clampf(current + delta, _PROSPERITY_MIN, _PROSPERITY_MAX)

## 灾难事件降低繁荣度（由事件 on_expire / activate 调用）
func apply_prosperity_shock(port_id: String, magnitude: float) -> void:
	_adjust_prosperity(port_id, -absf(magnitude))

## 恢复事件提升繁荣度
func apply_prosperity_boost(port_id: String, magnitude: float) -> void:
	_adjust_prosperity(port_id, absf(magnitude))

# ── NK1-P5-ECON-003: 港口好感度 API ────────────────────────

## 获取港口好感度（默认 0.0 = 中立）
func get_affinity(port_id: String) -> float:
	return clampf(float(port_affinity.get(port_id, 0.0)), _AFFINITY_MIN, _AFFINITY_MAX)

## 调整好感度（内部，自动 clamp）
func _adjust_affinity(port_id: String, delta: float) -> void:
	var current := get_affinity(port_id)
	port_affinity[port_id] = clampf(current + delta, _AFFINITY_MIN, _AFFINITY_MAX)

## 外部调整好感度（事件可调用）
func adjust_affinity(port_id: String, delta: float) -> void:
	_adjust_affinity(port_id, delta)

func is_specialty_unlocked(port_id: String, good_id: String) -> bool:
	var list: Array = unlocked_specialties.get(port_id, [])
	return good_id in list

func unlock_specialty(port_id: String, good_id: String) -> void:
	if not unlocked_specialties.has(port_id):
		unlocked_specialties[port_id] = []
	var list: Array = unlocked_specialties[port_id]
	if good_id not in list:
		list.append(good_id)

## 获取好感度对价格的影响因子
## 好感度 > 0: 买入更便宜（mod < 1.0），卖出更划算（mod > 1.0）
## 好感度 < 0: 买入更贵（mod > 1.0），卖出更便宜（mod < 1.0）
## 返回 [0.88, 1.12] 范围的价格修正
func get_affinity_price_mod(port_id: String, for_buy: bool = true) -> float:
	var aff := get_affinity(port_id)
	var signed := aff * _AFFINITY_PRICE_IMPACT
	if for_buy:
		return clampf(1.0 - signed, 0.88, 1.12)
	return clampf(1.0 + signed, 0.88, 1.12)

## 获取好感度等级描述（用于 UI 显示）
func get_affinity_label(port_id: String) -> String:
	var aff := get_affinity(port_id)
	return get_affinity_label_when(aff)

## 静态方法：根据好感度数值返回标签（便于测试）
static func get_affinity_label_when(aff: float) -> String:
	if aff >= 15.0:
		return "敬重"
	if aff >= 8.0:
		return "友善"
	if aff >= 2.0:
		return "好感"
	if aff > -2.0:
		return "中立"
	if aff > -8.0:
		return "冷淡"
	if aff > -15.0:
		return "排斥"
	return "敌意"

## 每日经济处理：繁荣度自然回归 + 贸易历史衰减 + 好感度回归
func process_daily_economy() -> void:
	for port_id in port_prosperity.keys():
		var current := float(port_prosperity[port_id])
		if absf(current - 1.0) > 0.001:
			# 向 1.0 自然回归
			var direction := 1.0 if current < 1.0 else -1.0
			port_prosperity[port_id] = clampf(current + direction * _PROSPERITY_DAILY_DECAY, _PROSPERITY_MIN, _PROSPERITY_MAX)
	# 贸易历史缓慢衰减（每日衰减 2%，模拟市场消化）
	for port_id in trade_history.keys():
		for good_id in trade_history[port_id]:
			var net_flow: int = trade_history[port_id][good_id].get("net_flow", 0)
			trade_history[port_id][good_id]["net_flow"] = int(float(net_flow) * 0.98)
	# NK1-P5-ECON-003: 好感度每日向 0 自然回归
	for port_id in port_affinity.keys():
		var current_aff := float(port_affinity[port_id])
		if absf(current_aff) > 0.01:
			var direction := 1.0 if current_aff < 0.0 else -1.0
			port_affinity[port_id] = clampf(current_aff + direction * _AFFINITY_DAILY_DECAY, _AFFINITY_MIN, _AFFINITY_MAX)
	# 库存向 base_stock 缓慢回归（短缺回补、过剩消化），不立刻重置
	_regenerate_daily_stock()

func _regenerate_daily_stock() -> void:
	for port_id in port_stocks.keys():
		var goods: Dictionary = port_stocks[port_id]
		for good_id in goods.keys():
			var entry: Dictionary = goods[good_id]
			var stock: int = int(entry.get("stock", 0))
			var base: int = int(entry.get("base_stock", stock))
			var gap: int = base - stock
			if gap == 0:
				continue
			var step: int = int(round(float(gap) * _STOCK_REGEN_RATE))
			if step == 0:
				step = 1 if gap > 0 else -1
			if absi(step) > absi(gap):
				step = gap
			entry["stock"] = maxi(0, stock + step)

## 查询当前生效的世界事件对价格的影响（为 UI 反馈价格变化原因准备）
## active_events 由调用方注入（通常为 WorldEventTracker.get_active_events()），
## 使 MarketState 不直接依赖 WorldEventTracker autoload，便于单元测试。
func get_active_price_modifiers(port_id: String, good_id: String, active_events: Array[BaseEconomicEvent] = []) -> Dictionary:
	var total_mod := 1.0
	var reasons: Array = []
	for e in active_events:
		var m := e.get_price_modifier(port_id, good_id)
		if abs(m - 1.0) > 0.001:
			total_mod *= m
			reasons.append({
				"event_id": e.event_id,
				"target_port": e.target_port,
				"modifier": m,
				"duration_days": e.duration_days
			})
	return {
		"total_multiplier": total_mod,
		"reasons": reasons
	}

## 获取当前活跃世界事件影响的具体原因描述列表
func get_active_event_reasons(port_id: String, good_id: String, active_events: Array[BaseEconomicEvent] = []) -> Array[String]:
	var reasons: Array[String] = []
	for e in active_events:
		var m := e.get_price_modifier(port_id, good_id)
		if abs(m - 1.0) > 0.001:
			var event_name := BaseEconomicEvent.get_display_name(e.event_id)
			var percent = int((m - 1.0) * 100)
			var sign_str = "+" if percent >= 0 else ""
			reasons.append("%s (价格 %s%d%%)" % [event_name, sign_str, percent])
	return reasons

## 委托接口：事件效果的 stock 变更现在通过 MarketState 实现（清晰委托）
## 灾难事件：库存骤降至 20%（模拟严重短缺但非完全断供），避免价格永久封顶。
func apply_disaster_zero(port_id: String) -> void:
	if not port_stocks.has(port_id):
		return
	for g_id in port_stocks[port_id]:
		var base = port_stocks[port_id][g_id].get("base_stock", 100)
		port_stocks[port_id][g_id]["stock"] = int(base * 0.2)

func apply_recovery_restore(port_id: String) -> void:
	if not port_stocks.has(port_id):
		return
	for g_id in port_stocks[port_id]:
		var current = port_stocks[port_id][g_id]["stock"]
		var base = port_stocks[port_id][g_id].get("base_stock", current)
		if current < base:
			if float(current) / float(base) < 0.3:
				port_stocks[port_id][g_id]["stock"] = int(base * 0.5)
			else:
				port_stocks[port_id][g_id]["stock"] = base
		# 若 current >= base (说明玩家倾销，库存过剩)，不执行向下重置以保留溢出物流量

## 部分恢复库存至指定比例（灾后逐步回流），不触发套利判定。
## NK1-P5-ECON-002: 恢复速度受港口繁荣度影响（繁荣港恢复更快）。
func apply_partial_recovery(port_id: String, ratio: float) -> void:
	if not port_stocks.has(port_id):
		return
	var prosperity := get_prosperity(port_id)
	var effective_ratio := clampf(ratio * prosperity, 0.0, 1.0)
	for g_id in port_stocks[port_id]:
		var base = port_stocks[port_id][g_id].get("base_stock", 100)
		var current = port_stocks[port_id][g_id]["stock"]
		var target = int(base * effective_ratio)
		if current < target:
			port_stocks[port_id][g_id]["stock"] = target

func to_dict() -> Dictionary:
	var upcoming_serialized: Array = []
	for item in upcoming_events:
		var e = item.get("event") as BaseEconomicEvent
		var serialized_item := {
			"days_left": item.get("days_left", 0),
			"type": item.get("type", ""),
			"port_name": item.get("port_name", ""),
			"purchased": item.get("purchased", false),
		}
		if e != null and e.has_method("to_dict"):
			serialized_item["event"] = e.to_dict()
		upcoming_serialized.append(serialized_item)
	return {
		"port_stocks": port_stocks,
		"upcoming_events": upcoming_serialized,
		"trade_history": trade_history,
		"port_prosperity": port_prosperity,
		"port_affinity": port_affinity,
		"unlocked_specialties": unlocked_specialties,
	}

func from_dict(d: Dictionary) -> void:
	var loaded_stocks = d.get("port_stocks", {})
	if not loaded_stocks.is_empty():
		port_stocks = loaded_stocks
		_sanitize_port_stocks()
	# else keep previously initialized stocks (for old saves without full market data)
	
	# NK1-P5-ECON-002: 恢复贸易历史与繁荣度（兼容旧存档无此字段）
	var loaded_history = d.get("trade_history", {})
	if not loaded_history.is_empty():
		trade_history = loaded_history
	var loaded_prosperity = d.get("port_prosperity", {})
	if not loaded_prosperity.is_empty():
		port_prosperity = loaded_prosperity
		for port_id in port_prosperity.keys():
			var p := float(port_prosperity[port_id])
			if is_nan(p) or is_inf(p):
				p = 1.0
			port_prosperity[port_id] = clampf(p, _PROSPERITY_MIN, _PROSPERITY_MAX)
	# NK1-P5-ECON-003: 恢复港口好感度
	var loaded_affinity = d.get("port_affinity", {})
	if not loaded_affinity.is_empty():
		port_affinity = loaded_affinity
		for port_id in port_affinity.keys():
			var a := float(port_affinity[port_id])
			if is_nan(a) or is_inf(a):
				a = 0.0
			port_affinity[port_id] = clampf(a, _AFFINITY_MIN, _AFFINITY_MAX)
	unlocked_specialties = d.get("unlocked_specialties", {})
	
	upcoming_events.clear()
	if d.has("upcoming_events"):
		for item in d.get("upcoming_events", []):
			if not (item is Dictionary):
				continue
			var ed = item.get("event", {})
			var e: BaseEconomicEvent = null
			if ed is Dictionary and ed.size() > 0:
				e = BaseEconomicEvent.from_dict(ed)
			var restored := {
				"event": e,
				"days_left": int(item.get("days_left", 0)),
				"type": item.get("type", ""),
				"port_name": item.get("port_name", ""),
				"purchased": bool(item.get("purchased", false))
			}
			upcoming_events.append(restored)
	# else: old save without upcoming key -> no pending events (correct for compatibility)
	# 注：port_stocks 的空数据兜底再初始化由 SaveManager.load_game 统一负责，
	# MarketState 不在此直接依赖 GameManager autoload，保持可单元测试。

func _sanitize_port_stocks() -> void:
	var cleaned_ports: Dictionary = {}
	for port_id in port_stocks.keys():
		var goods = port_stocks[port_id]
		if not (goods is Dictionary):
			continue
		var cleaned_goods: Dictionary = {}
		for good_id in goods.keys():
			var entry = goods[good_id]
			if not (entry is Dictionary):
				continue
			var stock := maxi(0, int(entry.get("stock", 0)))
			var base := maxi(0, int(entry.get("base_stock", stock)))
			cleaned_goods[str(good_id)] = {"stock": stock, "base_stock": base}
		cleaned_ports[str(port_id)] = cleaned_goods
	port_stocks = cleaned_ports
