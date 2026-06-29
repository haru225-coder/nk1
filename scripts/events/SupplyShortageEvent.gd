class_name SupplyShortageEvent extends BaseEconomicEvent

## NK1-P5-ECON-003: 供应短缺 — 特定商品在产出港及关联港口同时短缺
## 激活时降低产出港和同区域港口该商品库存，触发供应链连锁反应
## 价格修正：目标商品 ×2.0 满效果（仅影响特定商品），其他商品不受影响
## 结束时部分恢复库存 + 设置恢复事件链偏置
## NK1-P6-POLISH-002/003: 数值参数从 events_config.json 读取

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const _PEAK_LOCAL_MOD := 2.0
const _PEAK_REGIONAL_MOD := 1.4
const _SHORTAGE_RATIO := 0.25
const _REGIONAL_SHORTAGE_MULT := 1.8
const _REGIONAL_DECAY_MULT := 0.6
const _ACTIVATE_PROSPERITY_SHOCK := 0.08
const _EXPIRE_PARTIAL_RECOVERY := 0.7
const _EXPIRE_PROSPERITY_BOOST := 0.04
const _EXPIRE_CHAIN_BIAS_RECOVERY := 2.0

## 短缺影响的特定商品 ID（空 = 影响所有货物）
var target_good: String = ""

func _init(port: String, days: int) -> void:
	super("supply_shortage", port, days)
	EventConfigLoader.apply_config(self, "supply_shortage")

func activate(market = null) -> void:
	if market == null:
		return
	# 对目标港口的特定商品施加短缺
	_apply_shortage_to_port(market, target_port)
	# NK1-P6-POLISH-002: 繁荣度冲击从配置读取
	var cfg: Dictionary = EventConfigLoader.get_event_config("supply_shortage")
	var shock: float = float(cfg.get("activate_prosperity_shock", _ACTIVATE_PROSPERITY_SHOCK))
	market.apply_prosperity_shock(target_port, shock)
	# 对同区域港口施加较轻的短缺（供应链连锁）
	var gm := _get_game_manager()
	var regional_ratio: float = float(cfg.get("shortage_ratio", _SHORTAGE_RATIO)) * float(cfg.get("regional_shortage_multiplier", _REGIONAL_SHORTAGE_MULT))
	if gm == null:
		# 无 autoload 时仍记录经济日志（使用 GameState）
		_log_activation(null)
		return
	var port_data: Dictionary = gm.get_port_data(target_port)
	var region: String = port_data.get("region", "")
	if region.is_empty():
		_log_activation(gm)
		return
	var ports = gm.ports_data.get("ports", [])
	for p in ports:
		var pid: String = p.get("id", "")
		if pid == target_port or pid.is_empty():
			continue
		if p.get("region", "") == region:
			_apply_shortage_to_port(market, pid, regional_ratio)
	# 经济日志
	_log_activation(gm)

func _apply_shortage_to_port(market, port_id: String, ratio: float = _SHORTAGE_RATIO) -> void:
	if not market.port_stocks.has(port_id):
		return
	for g_id in market.port_stocks[port_id]:
		# 如果指定了目标商品，只影响该商品
		if not target_good.is_empty() and g_id != target_good:
			continue
		var base = market.port_stocks[port_id][g_id].get("base_stock", 100)
		market.port_stocks[port_id][g_id]["stock"] = int(base * ratio)

func _log_activation(gm: Node) -> void:
	var gs := _get_game_state()
	if gs == null or gs.economy_log == null:
		return
	var port_name = target_port
	var good_name = ""
	if gm != null:
		port_name = gm.get_port_data(target_port).get("name", target_port)
		if not target_good.is_empty():
			var g_data: Dictionary = gm.get_good_data(target_good)
			good_name = g_data.get("name", target_good)
	if good_name.is_empty():
		gs.economy_log.log("【商情急报】%s遭遇供应短缺，多港物资告急，供应链受阻！" % port_name)
	else:
		gs.economy_log.log("【商情急报】%s的%s供应短缺，货源紧张，多地价格飙升！" % [port_name, good_name])

func on_expire(_market = null) -> void:
	var gs := _get_game_state()
	if gs == null:
		return
	var cfg: Dictionary = EventConfigLoader.get_event_config("supply_shortage")
	var market = gs.market
	if market != null:
		var recovery: float = float(cfg.get("expire_partial_recovery", _EXPIRE_PARTIAL_RECOVERY))
		var boost: float = float(cfg.get("expire_prosperity_boost", _EXPIRE_PROSPERITY_BOOST))
		market.apply_partial_recovery(target_port, recovery)
		market.apply_prosperity_boost(target_port, boost)
	# 设置恢复事件链偏置
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var wet = tree.root.get_node_or_null("WorldEventTracker")
		if wet != null:
			var bias: float = float(cfg.get("expire_chain_bias", {}).get("trade_recovery", _EXPIRE_CHAIN_BIAS_RECOVERY))
			wet.set_chain_bias(target_port, "trade_recovery", bias)
	# 经济日志
	if gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log("【商情快讯】%s供应短缺缓解，货源逐步恢复。" % port_name)

func get_price_modifier(port_id: String, good_id: String) -> float:
	# 如果指定了目标商品，只影响该商品
	if not target_good.is_empty() and good_id != target_good:
		return 1.0
	if port_id == target_port:
		return lerp(1.0, _PEAK_LOCAL_MOD, get_decay_factor())
	# 同区域港口受波及
	if _is_same_region(port_id):
		var cfg: Dictionary = EventConfigLoader.get_event_config("supply_shortage")
		var decay_mult: float = float(cfg.get("regional_decay_multiplier", _REGIONAL_DECAY_MULT))
		return lerp(1.0, _PEAK_REGIONAL_MOD, get_decay_factor() * decay_mult)
	return 1.0

func _is_same_region(port_id: String) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	var my_data: Dictionary = gm.get_port_data(target_port)
	var other_data: Dictionary = gm.get_port_data(port_id)
	if my_data.is_empty() or other_data.is_empty():
		return false
	return my_data.get("region", "") == other_data.get("region", "")

## 序列化：包含 target_good 字段
func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["target_good"] = target_good
	return d

static func from_dict(d: Dictionary) -> SupplyShortageEvent:
	var ev := SupplyShortageEvent.new(
		d.get("target_port", ""),
		int(d.get("duration_days", 0))
	)
	ev._initial_duration = int(d.get("initial_duration", ev.duration_days))
	ev.target_good = d.get("target_good", "")
	return ev
