class_name EconomicRippleEvent extends BaseEconomicEvent

## NK1-P5-ECON-003: 经济涟漪 — 一个港口的重大经济事件波及整个区域
## 复合事件：在目标港口产生强价格冲击，同时通过供应链和区域联动影响整个区域
## 激活时：目标港口库存骤降 + 繁荣度冲击 + 同区域港口轻微库存下降
## 价格修正：目标港 ×1.8，同区域港口 ×1.25（涟漪效应）
## 结束时：目标港口恢复 + 设置恢复事件链偏置 + 区域繁荣度微恢复
## 与供应链修正深度联动：涟漪期间产出港短缺会自动通过供应链影响消费港
## NK1-P6-POLISH-002/003: 数值参数从 events_config.json 读取

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const _PEAK_LOCAL_MOD := 1.8
const _PEAK_REGIONAL_MOD := 1.25
const _RIPPLE_STOCK_CUT := 0.3
const _RIPPLE_REGIONAL_CUT := 0.6
const _REGIONAL_DECAY_MULT := 0.7
const _ACTIVATE_PROSPERITY_SHOCK := 0.12
const _ACTIVATE_REGIONAL_PROSPERITY_SHOCK := 0.04
const _ACTIVATE_CHAIN_BIAS_RECOVERY := 2.5
const _EXPIRE_PARTIAL_RECOVERY := 0.75
const _EXPIRE_PROSPERITY_BOOST := 0.06
const _EXPIRE_REGIONAL_PARTIAL_RECOVERY := 0.9

func _init(port: String, days: int) -> void:
	super("economic_ripple", port, days)
	EventConfigLoader.apply_config(self, "economic_ripple")

func activate(market = null) -> void:
	if market == null:
		return
	var cfg: Dictionary = EventConfigLoader.get_event_config("economic_ripple")
	# 目标港口：库存骤降 + 繁荣度冲击（在 GameManager 依赖之前执行）
	_apply_stock_cut(market, target_port, float(cfg.get("ripple_stock_cut", _RIPPLE_STOCK_CUT)))
	var shock: float = float(cfg.get("activate_prosperity_shock", _ACTIVATE_PROSPERITY_SHOCK))
	market.apply_prosperity_shock(target_port, shock)
	# 同区域港口：轻微库存下降 + 轻微繁荣度冲击
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
					_apply_stock_cut(market, pid, float(cfg.get("ripple_regional_cut", _RIPPLE_REGIONAL_CUT)))
					var regional_shock: float = float(cfg.get("activate_regional_prosperity_shock", _ACTIVATE_REGIONAL_PROSPERITY_SHOCK))
					market.apply_prosperity_shock(pid, regional_shock)
	# 设置灾难事件链偏置（涟漪可能引发后续恢复）
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var wet = tree.root.get_node_or_null("WorldEventTracker")
		if wet != null:
			var bias: float = float(cfg.get("activate_chain_bias", {}).get("trade_recovery", _ACTIVATE_CHAIN_BIAS_RECOVERY))
			wet.set_chain_bias(target_port, "trade_recovery", bias)
	# 经济日志
	_log_activation(gm)

func _apply_stock_cut(market, port_id: String, ratio: float) -> void:
	if not market.port_stocks.has(port_id):
		return
	for g_id in market.port_stocks[port_id]:
		var base = market.port_stocks[port_id][g_id].get("base_stock", 100)
		var current = market.port_stocks[port_id][g_id]["stock"]
		var target = int(base * ratio)
		# 只降不升（不覆盖玩家倾销的过量库存）
		if current > target:
			market.port_stocks[port_id][g_id]["stock"] = target

func _log_activation(gm: Node) -> void:
	var gs := _get_game_state()
	if gs == null or gs.economy_log == null:
		return
	var port_name = target_port
	if gm != null:
		port_name = gm.get_port_data(target_port).get("name", target_port)
	gs.economy_log.log("【商情急报】%s发生经济震荡，涟漪效应波及整个区域，多地物价波动！" % port_name)

func on_expire(_market = null) -> void:
	var gs := _get_game_state()
	if gs == null:
		return
	var cfg: Dictionary = EventConfigLoader.get_event_config("economic_ripple")
	var market = gs.market
	if market != null:
		# 目标港口恢复
		var recovery: float = float(cfg.get("expire_partial_recovery", _EXPIRE_PARTIAL_RECOVERY))
		var boost: float = float(cfg.get("expire_prosperity_boost", _EXPIRE_PROSPERITY_BOOST))
		market.apply_partial_recovery(target_port, recovery)
		market.apply_prosperity_boost(target_port, boost)
		# 同区域港口轻微恢复
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
						var regional_recovery: float = float(cfg.get("expire_regional_partial_recovery", _EXPIRE_REGIONAL_PARTIAL_RECOVERY))
						market.apply_partial_recovery(pid, regional_recovery)
	# 经济日志
	if gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log("【商情快讯】%s经济震荡平息，区域物价逐步回归常态。" % port_name)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return lerp(1.0, _PEAK_LOCAL_MOD, get_decay_factor())
	if _is_same_region(port_id):
		var cfg: Dictionary = EventConfigLoader.get_event_config("economic_ripple")
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
