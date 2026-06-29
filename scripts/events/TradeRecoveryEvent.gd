class_name TradeRecoveryEvent extends BaseEconomicEvent

## 经济恢复：目标港口物价回落（×0.8 满效果，促进低价买入），邻近港口轻微回落（×0.9）。
## 激活时恢复目标港口库存，效果随时间衰减回归正常。
## NK1-P5-ECON-003: 激活时繁荣度提升 + 经济日志；结束时繁荣度微调
## NK1-P6-POLISH-002: 数值参数从 events_config.json 读取

const _PEAK_LOCAL_MOD := 0.8
const _PEAK_NEIGHBOR_MOD := 0.9
const _NEIGHBOR_DECAY := 0.5
const _ACTIVATE_PROSPERITY_BOOST := 0.05
const _EXPIRE_PROSPERITY_BOOST := 0.02

func _init(port: String, days: int) -> void:
	super("trade_recovery", port, days)
	EventConfigLoader.apply_config(self, "trade_recovery")

## NK1-P5-ECON-003: 恢复事件激活时提升繁荣度 + 经济日志
func activate(market = null) -> void:
	if market != null:
		market.apply_recovery_restore(target_port)
		var cfg: Dictionary = EventConfigLoader.get_event_config("trade_recovery")
		var boost: float = float(cfg.get("activate_prosperity_boost", _ACTIVATE_PROSPERITY_BOOST))
		market.apply_prosperity_boost(target_port, boost)
	# 经济日志
	var gs := _get_game_state()
	if gs != null and gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log(EconomyLog.make_recovery_notice(port_name))

## NK1-P5-ECON-003: 恢复事件结束时繁荣度微调
func on_expire(_market = null) -> void:
	var gs := _get_game_state()
	if gs == null:
		return
	var market = gs.market
	if market != null:
		var cfg: Dictionary = EventConfigLoader.get_event_config("trade_recovery")
		var boost: float = float(cfg.get("expire_prosperity_boost", _EXPIRE_PROSPERITY_BOOST))
		market.apply_prosperity_boost(target_port, boost)

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
