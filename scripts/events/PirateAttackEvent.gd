class_name PirateAttackEvent extends BaseEconomicEvent

## 海盗袭击：目标港口物价飞涨（+50%满效果），邻近港口受波及（+15%满效果）。
## 效果随持续时间梯度衰减，末期仍有持续影响。
## NK1-P5-ECON-003: 激活时降低繁荣度 + 设置恢复事件链偏置 + 经济日志
## NK1-P6-POLISH-002: 数值参数（base_weight/cooldown/peak mods/prosperity）从 events_config.json 读取

## NK1-P6-POLISH-002: 默认值（无 JSON 时的 fallback）
const _PEAK_LOCAL_MOD := 1.5
const _PEAK_NEIGHBOR_MOD := 1.15
const _NEIGHBOR_DECAY := 0.5  ## 邻近港口效果衰减更快
const _ACTIVATE_PROSPERITY_SHOCK := 0.10
const _EXPIRE_PROSPERITY_BOOST := 0.05
const _EXPIRE_CHAIN_BIAS_RECOVERY := 2.0

func _init(port: String, days: int) -> void:
	super("pirate_attack", port, days)
	# NK1-P6-POLISH-002: 从 JSON 配置加载（fallback 保留兼容）
	EventConfigLoader.apply_config(self, "pirate_attack")

## NK1-P5-ECON-003: 海盗袭击激活时降低繁荣度 + 经济日志
func activate(market = null) -> void:
	if market != null:
		var cfg: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
		var shock: float = float(cfg.get("activate_prosperity_shock", _ACTIVATE_PROSPERITY_SHOCK))
		market.apply_prosperity_shock(target_port, shock)
	# 经济日志
	var gs := _get_game_state()
	if gs != null and gs.economy_log != null:
		var gm := _get_game_manager()
		var port_name = target_port
		if gm != null:
			port_name = gm.get_port_data(target_port).get("name", target_port)
		gs.economy_log.log("【商情急报】%s遭海盗袭击，商船受阻，物价飞涨！" % port_name)

## NK1-P5-ECON-003: 海盗袭击结束时恢复繁荣度 + 链偏置
func on_expire(_market = null) -> void:
	var gs := _get_game_state()
	if gs == null:
		return
	var market = gs.market
	if market != null:
		var cfg: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
		var boost: float = float(cfg.get("expire_prosperity_boost", _EXPIRE_PROSPERITY_BOOST))
		market.apply_prosperity_boost(target_port, boost)
	# 恢复事件链偏置
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var wet = tree.root.get_node_or_null("WorldEventTracker")
		if wet != null:
			var cfg2: Dictionary = EventConfigLoader.get_event_config("pirate_attack")
			var bias: float = float(cfg2.get("expire_chain_bias", {}).get("trade_recovery", _EXPIRE_CHAIN_BIAS_RECOVERY))
			wet.set_chain_bias(target_port, "trade_recovery", bias)

func get_price_modifier(port_id: String, good_id: String) -> float:
	if port_id == target_port:
		return lerp(1.0, _PEAK_LOCAL_MOD, get_decay_factor())
	# 邻近港口波及：用更快的衰减
	if _is_neighbor(port_id):
		var decay: float = get_decay_factor()
		var neighbor_decay: float = lerp(1.0, 0.3, decay)
		return lerp(1.0, _PEAK_NEIGHBOR_MOD, neighbor_decay * _NEIGHBOR_DECAY)
	return 1.0

## 邻近港口判定：通过 GameManager 查询 connections
func _is_neighbor(port_id: String) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	var port_data: Dictionary = gm.get_port_data(target_port)
	if port_data.is_empty():
		return false
	var conns: Array = port_data.get("connections", [])
	return port_id in conns
