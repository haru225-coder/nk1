class_name TradeDisasterEvent extends BaseEconomicEvent

## 贸易灾难：目标港口物价暴涨（×2.5 满效果），邻近港口受波及（×1.3 满效果）。
## 激活时清空目标港口库存（突发断供），效果随时间梯度衰减。
## NK1-P6-POLISH-002: 数值参数从 events_config.json 读取

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const _PEAK_LOCAL_MOD := 2.5
const _PEAK_NEIGHBOR_MOD := 1.3
const _NEIGHBOR_DECAY := 0.6
const _ACTIVATE_PROSPERITY_SHOCK := 0.15
const _EXPIRE_PARTIAL_RECOVERY := 0.8
const _EXPIRE_PROSPERITY_BOOST := 0.08
const _EXPIRE_CHAIN_BIAS_RECOVERY := 3.0

func _init(port: String, days: int) -> void:
	super("trade_disaster", port, days)
	EventConfigLoader.apply_config(self, "trade_disaster")

func activate(market = null) -> void:
	if market != null:
		market.apply_disaster_zero(target_port)
		# NK1-P5-ECON-002: 灾难降低港口繁荣度
		var cfg: Dictionary = EventConfigLoader.get_event_config("trade_disaster")
		var shock: float = float(cfg.get("activate_prosperity_shock", _ACTIVATE_PROSPERITY_SHOCK))
		market.apply_prosperity_shock(target_port, shock)
	# NK1-P5-ECON-003: 灾难激活经济日志
	var gs := _get_game_state()
	if gs != null and gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log(EconomyLog.make_disaster_notice(port_name))

## 事件结束时部分恢复库存（模拟灾后物资逐步回流至 80%），价格逐步回归。
## NK1-P5-ECON-002: 设置恢复事件链偏置 + 繁荣度恢复 + 经济日志
func on_expire(_market = null) -> void:
	var gs := _get_game_state()
	if gs == null:
		return
	var cfg: Dictionary = EventConfigLoader.get_event_config("trade_disaster")
	var market = gs.market
	if market != null:
		var recovery: float = float(cfg.get("expire_partial_recovery", _EXPIRE_PARTIAL_RECOVERY))
		var boost: float = float(cfg.get("expire_prosperity_boost", _EXPIRE_PROSPERITY_BOOST))
		market.apply_partial_recovery(target_port, recovery)
		market.apply_prosperity_boost(target_port, boost)
	# 灾难结束后恢复事件更容易触发（链式联动）
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var wet = tree.root.get_node_or_null("WorldEventTracker")
		if wet != null:
			var bias: float = float(cfg.get("expire_chain_bias", {}).get("trade_recovery", _EXPIRE_CHAIN_BIAS_RECOVERY))
			wet.set_chain_bias(target_port, "trade_recovery", bias)
	# 经济日志
	if gs != null and gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log("【商情快讯】%s贸易灾难结束，物资逐步回流，市价趋于平稳。" % port_name)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return lerp(1.0, _PEAK_LOCAL_MOD, get_decay_factor())
	if _is_neighbor(port_id):
		var decay: float = get_decay_factor()
		var neighbor_decay: float = lerp(1.0, 0.3, decay)
		return lerp(1.0, _PEAK_NEIGHBOR_MOD, neighbor_decay * _NEIGHBOR_DECAY)
	return 1.0

func _is_neighbor(port_id: String) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	var port_data: Dictionary = gm.get_port_data(target_port)
	if port_data.is_empty():
		return false
	var conns: Array = port_data.get("connections", [])
	return port_id in conns
