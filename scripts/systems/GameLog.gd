class_name GameLog extends RefCounted

## NK1-P6-POLISH-001: 统一分类日志系统
## 区分 Info / Warning / Debug 三级，按分类（经济/战斗/事件/航行/系统）记录
## 替代散布各处的 print() 和 ad-hoc 日志

enum Level { INFO, WARNING, DEBUG }
enum Category { ECONOMY, COMBAT, EVENT, VOYAGE, SYSTEM }

const _MAX_ENTRIES_PER_CATEGORY := 20
const _LEVEL_PREFIXES: Array[String] = ["[INFO] ", "[WARN] ", "[DEBUG] "]
const _CATEGORY_PREFIXES: Array[String] = ["经济", "战斗", "事件", "航行", "系统"]

var _logs: Dictionary = {}  # Category -> Array[String]

func _init() -> void:
	for cat in [Category.ECONOMY, Category.COMBAT, Category.EVENT, Category.VOYAGE, Category.SYSTEM]:
		_logs[cat] = []

## 记录一条日志
func add_entry(category: int, level: int, msg: String) -> void:
	var entry: String = "%s【%s】%s" % [_LEVEL_PREFIXES[level], _CATEGORY_PREFIXES[category], msg]
	if not _logs.has(category):
		_logs[category] = []
	_logs[category].append(entry)
	if (_logs[category] as Array).size() > _MAX_ENTRIES_PER_CATEGORY:
		(_logs[category] as Array).pop_front()

## 便捷方法
func info(category: int, msg: String) -> void:
	add_entry(category, Level.INFO, msg)

func warning(category: int, msg: String) -> void:
	add_entry(category, Level.WARNING, msg)

func debug(category: int, msg: String) -> void:
	add_entry(category, Level.DEBUG, msg)

## 获取指定分类的最近 N 条日志
func get_entries(category: int, count: int = -1) -> Array[String]:
	if not _logs.has(category):
		return [] as Array[String]
	var raw: Variant = _logs[category]
	var arr: Array = raw if raw is Array else []
	if count < 0 or count >= arr.size():
		var result: Array[String] = []
		for item in arr:
			result.append(str(item))
		return result
	var start: int = arr.size() - count
	var sliced: Array = arr.slice(start)
	var result2: Array[String] = []
	for item in sliced:
		result2.append(str(item))
	return result2

## 获取指定分类的最新一条
func get_latest(category: int) -> String:
	var arr: Array = _logs.get(category, [])
	if arr.is_empty():
		return ""
	return arr[-1]

## 获取所有分类的最新一条（用于综合日志面板）
func get_latest_all() -> Array[String]:
	var result: Array[String] = []
	for cat in [Category.ECONOMY, Category.COMBAT, Category.EVENT, Category.VOYAGE, Category.SYSTEM]:
		var latest: String = get_latest(cat)
		if not latest.is_empty():
			result.append(latest)
	return result

## 清空指定分类
func clear_category(category: int) -> void:
	if _logs.has(category):
		_logs[category] = []

## 清空所有
func clear_all() -> void:
	for cat in _logs.keys():
		_logs[cat] = []

## 序列化
func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for cat in _logs.keys():
		result[str(cat)] = _logs[cat].duplicate()
	return result

func from_dict(d: Dictionary) -> void:
	clear_all()
	for key in d.keys():
		var cat: int = int(key)
		_logs[cat] = []
		for entry in d[key]:
			_logs[cat].append(str(entry))
