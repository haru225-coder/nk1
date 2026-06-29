class_name EventConfigLoader extends RefCounted

## NK1-P6-POLISH-002: 事件配置加载器
## 从 data/events_config.json 读取事件参数并应用
## 事件子类的 _init() 调用 apply_config() 覆盖硬编码默认值
## 加载失败时优雅降级到脚本内默认值（行为不变）

const _CONFIG_PATH := "res://data/events_config.json"

static var _cache: Dictionary = {}

## 加载并缓存 JSON 配置
static func _load() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(_CONFIG_PATH):
		return {}
	var f := FileAccess.open(_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data = json.data
	if data is Dictionary:
		_cache = data
	return _cache

## 获取指定事件的配置字典（若不存在返回空 dict）
static func get_event_config(event_id: String) -> Dictionary:
	var data := _load()
	var events: Dictionary = data.get("events", {})
	return events.get(event_id, {})

## 获取生成器配置（rumor delays, safety valve 等）
static func get_generator_config() -> Dictionary:
	var data := _load()
	return data.get("generator", {})

## 清空缓存（用于热重载/测试）
static func clear_cache() -> void:
	_cache.clear()

## 将配置应用到事件实例（在 _init 末尾调用）
## event: BaseEconomicEvent 子类实例
## event_id: 事件的 event_id 字符串
static func apply_config(event: BaseEconomicEvent, event_id: String) -> void:
	var cfg: Dictionary = get_event_config(event_id)
	if cfg.is_empty():
		return
	if cfg.has("base_weight"):
		event.base_weight = float(cfg["base_weight"])
	if cfg.has("cooldown_days"):
		event.cooldown_days = int(cfg["cooldown_days"])
	if cfg.has("use_global_cooldown"):
		event.use_global_cooldown = bool(cfg["use_global_cooldown"])
	if cfg.has("max_triggers"):
		event.max_triggers = int(cfg["max_triggers"])

## 获取事件初始持续时间（用于 TradeEventGenerator 生成事件时）
## 返回配置中的 initial_duration，如果配置缺失返回 fallback
static func get_initial_duration(event_id: String, fallback: int) -> int:
	var cfg: Dictionary = get_event_config(event_id)
	if cfg.has("initial_duration"):
		return int(cfg["initial_duration"])
	return fallback
