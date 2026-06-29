class_name TradeBoomEvent extends BaseEconomicEvent

## NK1-P5-ECON-003: 贸易繁荣 — 某区域短期内贸易量激增
## 激活时提升繁荣度 + 库存补充（模拟商队涌入）
## 价格修正：×0.85 满效果（价格略降促进交易，繁荣港有货）
## 结束时注入贸易历史（模拟繁荣期过度供货→市场饱和），繁荣度回落
## 与繁荣度系统深度绑定：繁荣度越高，库存补充越多；结束后饱和越明显
## NK1-P6-POLISH-002/003: 数值参数从 events_config.json 读取

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const _PEAK_LOCAL_MOD := 0.85
const _PEAK_REGIONAL_MOD := 0.92
const _BOOM_PROSPERITY_GAIN := 0.12
const _BOOM_STOCK_REPLENISH := 1.3
const _POST_BOOM_SATURATION := 300
const _REGIONAL_PROSPERITY_FACTOR := 0.5
const _REGIONAL_STOCK_FACTOR := 0.8
const _REGIONAL_DECAY_MULT := 0.5
const _EXPIRE_PROSPERITY_SHOCK := 0.06

func _init(port: String, days: int) -> void:
	super("trade_boom", port, days)
	EventConfigLoader.apply_config(self, "trade_boom")

func activate(market = null) -> void:
	if market == null:
		return
	# NK1-P6-POLISH-002: 繁荣度激增从配置读取
	var cfg: Dictionary = EventConfigLoader.get_event_config("trade_boom")
	var prosperity_gain: float = float(cfg.get("boom_prosperity_gain", _BOOM_PROSPERITY_GAIN))
	var stock_replenish: float = float(cfg.get("boom_stock_replenish", _BOOM_STOCK_REPLENISH))
	var regional_prosperity: float = float(cfg.get("regional_prosperity_gain_factor", _REGIONAL_PROSPERITY_FACTOR))
	var regional_stock: float = float(cfg.get("regional_stock_replenish_factor", _REGIONAL_STOCK_FACTOR))
	market.apply_prosperity_boost(target_port, prosperity_gain)
	_replenish_stock(market, target_port, stock_replenish)
	# 同区域港口也受惠
	var gm := _get_game_manager()
	if gm != null:
		var port_data: Dictionary = gm.get_port_data(target_port)
		var region: String = port_data.get("region", "")
		if not region.is_empty():
			var ports = gm.ports_data.get("ports", [])
			for p in ports:
				var pid: String = p.get("id", "")
				if pid == target_port or pid.is_empty():
					continue
				if p.get("region", "") == region:
					market.apply_prosperity_boost(pid, prosperity_gain * regional_prosperity)
					_replenish_stock(market, pid, stock_replenish * regional_stock)
	# 经济日志
	_log_activation()

func _replenish_stock(market, port_id: String, ratio: float) -> void:
	if not market.port_stocks.has(port_id):
		return
	for g_id in market.port_stocks[port_id]:
		var base = market.port_stocks[port_id][g_id].get("base_stock", 100)
		var current = market.port_stocks[port_id][g_id]["stock"]
		var target = int(base * clampf(ratio, 0.0, 2.0))
		# 繁荣期库存补充：只在当前低于目标时提升
		if current < target:
			market.port_stocks[port_id][g_id]["stock"] = target

func _log_activation() -> void:
	var gs := _get_game_state()
	if gs == null or gs.economy_log == null:
		return
	var gm := _get_game_manager()
	var port_name = target_port
	if gm != null:
		port_name = gm.get_port_data(target_port).get("name", target_port)
	gs.economy_log.log(EconomyLog.make_prosperity_rise(port_name))

## NK1-P5-ECON-003: on_expire 接受可选 market 参数（便于测试）
func on_expire(_market = null) -> void:
	var cfg: Dictionary = EventConfigLoader.get_event_config("trade_boom")
	var saturation_amount: int = int(cfg.get("post_boom_saturation", _POST_BOOM_SATURATION))
	var prosperity_shock: float = float(cfg.get("expire_prosperity_shock", _EXPIRE_PROSPERITY_SHOCK))
	var market = _market
	if market == null:
		var gs := _get_game_state()
		if gs == null:
			return
		market = gs.market
	if market != null:
		# 繁荣期结束：注入贸易历史，模拟繁荣期囤货后市场饱和
		if not market.trade_history.has(target_port):
			market.trade_history[target_port] = {}
		# 对所有货物注入净流入（模拟繁荣期过量供货）
		if market.port_stocks.has(target_port):
			for g_id in market.port_stocks[target_port]:
				if not market.trade_history[target_port].has(g_id):
					market.trade_history[target_port][g_id] = {"net_flow": 0, "total_volume": 0}
				market.trade_history[target_port][g_id]["net_flow"] += saturation_amount
		# 繁荣度回落（从高点下降）
		market.apply_prosperity_shock(target_port, prosperity_shock)
	# 经济日志
	var gs2 := _get_game_state()
	if gs2 != null and gs2.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs2.economy_log.log("【商情快讯】%s贸易繁荣期结束，市场供过于求，价格开始回落。" % port_name)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return lerp(1.0, _PEAK_LOCAL_MOD, get_decay_factor())
	if _is_same_region(port_id):
		var cfg: Dictionary = EventConfigLoader.get_event_config("trade_boom")
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
