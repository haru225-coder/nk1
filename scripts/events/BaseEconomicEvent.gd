class_name BaseEconomicEvent extends RefCounted

# 事件类型注册表：全项目唯一来源（event_id → 脚本 + 显示名）。
const _PirateAttackEvent = preload(ResourcePaths.SCRIPT_PIRATE_ATTACK)
const _TradeDisasterEvent = preload(ResourcePaths.SCRIPT_TRADE_DISASTER)
const _TradeRecoveryEvent = preload(ResourcePaths.SCRIPT_TRADE_RECOVERY)
const _SupplyShortageEvent = preload(ResourcePaths.SCRIPT_SUPPLY_SHORTAGE)
const _TradeBoomEvent = preload(ResourcePaths.SCRIPT_TRADE_BOOM)
const _EconomicRippleEvent = preload(ResourcePaths.SCRIPT_ECONOMIC_RIPPLE)

const _EVENT_REGISTRY: Array = [
	{"id": "pirate_attack",    "script": _PirateAttackEvent,    "name": "海盗袭击"},
	{"id": "trade_disaster",   "script": _TradeDisasterEvent,   "name": "贸易灾难"},
	{"id": "trade_recovery",   "script": _TradeRecoveryEvent,   "name": "经济恢复"},
	{"id": "supply_shortage",  "script": _SupplyShortageEvent,  "name": "供应短缺"},
	{"id": "trade_boom",       "script": _TradeBoomEvent,       "name": "贸易繁荣"},
	{"id": "economic_ripple",  "script": _EconomicRippleEvent,  "name": "经济涟漪"},
]

var event_id: String = "base_event"
var target_port: String = ""
var duration_days: int = 0

# 配置化参数（NK1-P3-WORLDEVENT-003）
var base_weight: float = 1.0
var cooldown_days: int = 20
var use_global_cooldown: bool = false
var max_triggers: int = -1

## 事件初始最大持续时间（用于梯度衰减计算）
var _initial_duration: int = 0

func _init(id: String, port: String, days: int) -> void:
	event_id = id
	target_port = port
	duration_days = days
	_initial_duration = days

func tick_day() -> bool:
	duration_days -= 1
	if duration_days <= 0:
		on_expire()
		return false
	return true

# 返回一个扰动倍率，如果不受影响返回 1.0
func get_price_modifier(port_id: String, good_id: String) -> float:
	return 1.0

## 事件衰减因子：随剩余天数递减，效果在事件末期逐步回归正常。
## 返回 0.0~1.0，初期=1.0（满效果），末期接近 0.3（效果衰减但持续）。
func get_decay_factor() -> float:
	if _initial_duration <= 0:
		return 1.0
	var progress := 1.0 - float(duration_days) / float(_initial_duration)
	return 1.0 - progress * 0.7

# 预告池转正时的副作用。market 由调用方注入，避免事件类直接依赖 GameManager autoload。
func activate(_market = null) -> void:
	pass

## 事件自然结束时调用（由 tick_day 触发），子类可重写以执行收尾（如库存恢复）。
## NK1-P5-ECON-003: 接受可选 market 参数，便于测试时注入 mock market。
func on_expire(_market = null) -> void:
	pass

## ── Autoload 运行时解析（避免 -s 脚本模式编译期找不到 autoload 标识符）───
func _get_game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("GameManager")
	return null

func _get_game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("GameState")
	return null

## ── 注册表查询接口 ───────────────────────────────────────

static func create(event_id: String, port: String, days: int) -> BaseEconomicEvent:
	for entry in _EVENT_REGISTRY:
		if entry["id"] == event_id:
			return entry["script"].new(port, days)
	return BaseEconomicEvent.new(event_id, port, days)

static func all_samples() -> Array[BaseEconomicEvent]:
	var samples: Array[BaseEconomicEvent] = []
	for entry in _EVENT_REGISTRY:
		samples.append(entry["script"].new("", 0))
	return samples

static func get_display_name(event_id: String) -> String:
	for entry in _EVENT_REGISTRY:
		if entry["id"] == event_id:
			return entry["name"]
	return event_id

## ── 序列化支持 ───────────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"target_port": target_port,
		"duration_days": duration_days,
		"initial_duration": _initial_duration,
	}

static func from_dict(d: Dictionary) -> BaseEconomicEvent:
	var eid: String = d.get("event_id", "base_event")
	var port: String = d.get("target_port", "")
	var days: int = int(d.get("duration_days", 0))
	var ev := create(eid, port, days)
	# 恢复初始持续时间（用于衰减计算），兼容旧存档无此字段
	ev._initial_duration = int(d.get("initial_duration", days))
	return ev
