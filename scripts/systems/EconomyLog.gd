class_name EconomyLog extends RefCounted

## NK1-P5-ECON-002: 经济变化可感知反馈日志
## 记录玩家可感知的经济事件（价格异动、市场饱和、灾难/恢复、繁荣度变化）
## 被 MarketScreenController 和 Main.gd 航海日志接入

const _MAX_ENTRIES := 30
var _entries: Array[String] = []

## 记录一条经济日志
func log(msg: String) -> void:
	_entries.append(msg)
	if _entries.size() > _MAX_ENTRIES:
		_entries.pop_front()

## 获取最近 N 条日志（默认全部）
func get_entries(count: int = -1) -> Array[String]:
	if count < 0 or count >= _entries.size():
		return _entries.duplicate()
	var start := _entries.size() - count
	return _entries.slice(start)

## 获取最近一条日志
func get_latest() -> String:
	if _entries.is_empty():
		return ""
	return _entries[-1]

## 清空日志
func clear() -> void:
	_entries.clear()

func to_dict() -> Dictionary:
	return {"entries": _entries.duplicate()}

func from_dict(d: Dictionary) -> void:
	_entries.clear()
	var loaded = d.get("entries", [])
	for e in loaded:
		_entries.append(str(e))

## ── 便捷工厂方法：生成可读的经济事件描述 ──

static func make_dump_notice(port_name: String, good_name: String) -> String:
	return "【市井传闻】%s的%s因近期大量倾销，价格持续走低。" % [port_name, good_name]

static func make_disaster_notice(port_name: String) -> String:
	return "【商情急报】%s遭遇贸易灾难，物资骤缺，物价飞涨！" % port_name

static func make_recovery_notice(port_name: String) -> String:
	return "【商情快讯】%s经济逐渐恢复，物资回流，市价趋于平稳。" % port_name

static func make_prosperity_rise(port_name: String) -> String:
	return "【市井见闻】%s商贸繁荣，百业兴旺，港口日渐热闹。" % port_name

static func make_prosperity_decline(port_name: String) -> String:
	return "【市井见闻】%s商旅稀少，百业萧条，港口不复往日光景。" % port_name

static func make_port_invest(port_name: String, tier_label: String, amount: int) -> String:
	return "【港务】向%s投入%s投资 %d 钱，港口声誉与商贸日渐兴旺。" % [port_name, tier_label, amount]

static func make_specialty_unlock(port_name: String, good_name: String) -> String:
	return "【港务】%s商贾感念你的投资，特供「%s」现已开放交易！" % [port_name, good_name]

static func make_supply_chain_notice(consumer_port: String, producer_port: String, good_name: String) -> String:
	return "【商路消息】%s的%s货源紧张，%s等下游港口价格已受波及。" % [producer_port, good_name, consumer_port]

# ── NK1-P5-ECON-003: 新增事件工厂方法 ──

static func make_shortage_notice(port_name: String, good_name: String) -> String:
	if good_name.is_empty():
		return "【商情急报】%s遭遇供应短缺，多港物资告急，供应链受阻！" % port_name
	return "【商情急报】%s的%s供应短缺，货源紧张，多地价格飙升！" % [port_name, good_name]

static func make_shortage_relief_notice(port_name: String) -> String:
	return "【商情快讯】%s供应短缺缓解，货源逐步恢复。" % port_name

static func make_boom_notice(port_name: String) -> String:
	return "【市井见闻】%s商贸繁荣，百业兴旺，港口日渐热闹。" % port_name

static func make_boom_end_notice(port_name: String) -> String:
	return "【商情快讯】%s贸易繁荣期结束，市场供过于求，价格开始回落。" % port_name

static func make_ripple_notice(port_name: String) -> String:
	return "【商情急报】%s发生经济震荡，涟漪效应波及整个区域，多地物价波动！" % port_name

static func make_ripple_relief_notice(port_name: String) -> String:
	return "【商情快讯】%s经济震荡平息，区域物价逐步回归常态。" % port_name

static func make_pirate_notice(port_name: String) -> String:
	return "【商情急报】%s遭海盗袭击，商船受阻，物价飞涨！" % port_name

static func make_affinity_change_notice(port_name: String, label: String) -> String:
	return "【市井传闻】%s商人对你的态度变为「%s」。" % [port_name, label]
