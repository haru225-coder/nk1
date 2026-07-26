extends Node
## 历法与季风。游戏的时间基准，一切消耗与行情回归都挂在 day_passed 上。
## 采用农历简化历：每月 30 日，每年 12 月。

signal day_passed(y: int, m: int, d: int)
signal month_changed(y: int, m: int)
signal year_changed(y: int)

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12

## 开局：宝祐三年（1255）三月初一。与 npcs.json 中陈子龙档案的开局年份一致。
var year: int = 1255
var month: int = 3
var day: int = 1

## 南宋末年号表：[起始公元年, 结束公元年, 年号]
const ERAS := [
	[1253, 1258, "宝祐"],
	[1259, 1259, "开庆"],
	[1260, 1264, "景定"],
	[1265, 1274, "咸淳"],
	[1275, 1275, "德祐"],
	[1276, 1278, "景炎"],
]

const CN_NUM := ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

## 季风类型
enum Monsoon { NORTHEAST, SOUTHWEST, TRANSITION }

## 风吹向的方位角（度，0=正北 90=正东 180=正南 270=正西）
const NE_MONSOON_BEARING := 225.0   # 东北风吹向西南 → 利于南下
const SW_MONSOON_BEARING := 45.0    # 西南风吹向东北 → 利于北上


func advance_days(n: int) -> void:
	for i in range(n):
		_advance_one_day()


func _advance_one_day() -> void:
	day += 1
	if day > DAYS_PER_MONTH:
		day = 1
		month += 1
		if month > MONTHS_PER_YEAR:
			month = 1
			year += 1
			year_changed.emit(year)
		month_changed.emit(year, month)
	day_passed.emit(year, month, day)


# ── 季风 ──────────────────────────────────────────────

## 当前季风类型。史实：「北风下南洋，南风回唐山」。
func get_monsoon() -> Monsoon:
	if month >= 10 or month <= 2:
		return Monsoon.NORTHEAST
	elif month >= 5 and month <= 8:
		return Monsoon.SOUTHWEST
	return Monsoon.TRANSITION


## 季风强度系数，转换期风弱且多变。
func get_monsoon_strength() -> float:
	var m := get_monsoon()
	if m == Monsoon.NORTHEAST:
		# 冬月最盛
		return 1.0 if month in [11, 12, 1] else 0.8
	elif m == Monsoon.SOUTHWEST:
		return 1.0 if month in [6, 7] else 0.8
	return 0.3


## 当前季风吹向的方位角。转换期返回 -1 表示无稳定风向。
func get_wind_bearing() -> float:
	var m := get_monsoon()
	if m == Monsoon.NORTHEAST:
		return NE_MONSOON_BEARING
	elif m == Monsoon.SOUTHWEST:
		return SW_MONSOON_BEARING
	return -1.0


func get_monsoon_name() -> String:
	var m := get_monsoon()
	if m == Monsoon.NORTHEAST:
		return "东北季风"
	elif m == Monsoon.SOUTHWEST:
		return "西南季风"
	return "季风转换期"


func get_monsoon_desc() -> String:
	var m := get_monsoon()
	if m == Monsoon.NORTHEAST:
		return "东北季风（利南下）"
	elif m == Monsoon.SOUTHWEST:
		return "西南季风（利北上）"
	return "季风转换期（风微而多变）"


# ── 显示 ──────────────────────────────────────────────

func get_era() -> String:
	for e in ERAS:
		if year >= e[0] and year <= e[1]:
			return e[2]
	return "未纪"


func get_era_year() -> int:
	for e in ERAS:
		if year >= e[0] and year <= e[1]:
			return year - e[0] + 1
	return 0


func _cn_number(n: int) -> String:
	if n <= 0:
		return "零"
	if n <= 10:
		return CN_NUM[n]
	elif n < 20:
		return "十" + CN_NUM[n - 10]
	var tens: int = int(n / 10.0)
	if tens > 10:
		return str(n)
	elif n % 10 == 0:
		return CN_NUM[tens] + "十"
	return CN_NUM[tens] + "十" + CN_NUM[n % 10]


func get_month_name() -> String:
	if month == 1:
		return "正月"
	elif month == 11:
		return "冬月"
	elif month == 12:
		return "腊月"
	return _cn_number(month) + "月"


func get_day_name() -> String:
	if day <= 10:
		return "初" + CN_NUM[day]
	elif day == 20:
		return "二十"
	elif day == 30:
		return "三十"
	elif day < 20:
		return "十" + CN_NUM[day - 10]
	return "廿" + CN_NUM[day - 20]


## 「宝祐三年 三月初一」
func get_date_string() -> String:
	var ey := get_era_year()
	var y_str := get_era() + ("元年" if ey == 1 else _cn_number(ey) + "年")
	return "%s %s%s" % [y_str, get_month_name(), get_day_name()]


## 存档用
func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


func from_dict(d: Dictionary) -> void:
	year = d.get("year", 1255)
	month = d.get("month", 3)
	day = d.get("day", 1)
