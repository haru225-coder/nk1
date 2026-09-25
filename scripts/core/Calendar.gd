extends Node
## 历法与季风。游戏的时间基准；日推进的唯一入口是 GameManager.advance_days()。
## 采用农历简化历：每月 30 日，每年 12 月。

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12

## 开局：宝祐三年（1255）三月初一。与 npcs.json 中陈子龙档案的开局年份一致。
var year: int = 1255
var month: int = 3
var day: int = 1

## 南宋末年号表：[元年公元年, 末年公元年, 年号]，按起用先后排列；年号年数 = 公元年 − 元年 + 1。
## 改元当年两个年号各占一段：起用年月见 ERA_START，未列出的自元年正月起用。
## tools/art/import_cutscene_bgs.py 用正则读这里的三元组，行格式别改。
const ERAS := [
	[1253, 1258, "宝祐"],
	[1259, 1259, "开庆"],
	[1260, 1264, "景定"],
	[1265, 1274, "咸淳"],
	[1275, 1276, "德祐"],   # 至德祐二年四月
	[1276, 1278, "景炎"],   # 1276 年五月端宗福州即位改元，至景炎三年四月
	[1278, 1279, "祥兴"],   # 1278 年五月改元；崖山（1279 年二月）后本年仍记祥兴二年
	[1264, 1294, "至元"],   # 元世祖年号，1280 年起改用（至元十七年）
]

## 不在元年正月起用的年号：年号 → [起用公元年, 起用月]
const ERA_START := {
	"景炎": [1276, 5],
	"祥兴": [1278, 5],
	"至元": [1280, 1],
}

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


# ── 季风 ──────────────────────────────────────────────

## 指定月份的季风。史实：「北风下南洋，南风回唐山」。
func monsoon_of(month_num: int) -> Monsoon:
	if month_num >= 10 or month_num <= 2:
		return Monsoon.NORTHEAST
	elif month_num >= 5 and month_num <= 8:
		return Monsoon.SOUTHWEST
	return Monsoon.TRANSITION


func get_monsoon() -> Monsoon:
	return monsoon_of(month)


## 指定月份的季风强度。转换期风弱且多变。
func monsoon_strength_of(month_num: int) -> float:
	var m := monsoon_of(month_num)
	if m == Monsoon.NORTHEAST:
		# 冬月最盛
		return 1.0 if month_num in [11, 12, 1] else 0.8
	elif m == Monsoon.SOUTHWEST:
		return 1.0 if month_num in [6, 7] else 0.8
	return 0.3


func get_monsoon_strength() -> float:
	return monsoon_strength_of(month)


## 指定月份的风向方位角。转换期返回 -1，表示无稳定风向。
func wind_bearing_of(month_num: int) -> float:
	var m := monsoon_of(month_num)
	if m == Monsoon.NORTHEAST:
		return NE_MONSOON_BEARING
	elif m == Monsoon.SOUTHWEST:
		return SW_MONSOON_BEARING
	return -1.0


func get_wind_bearing() -> float:
	return wind_bearing_of(month)


func get_monsoon_desc() -> String:
	var m := get_monsoon()
	if m == Monsoon.NORTHEAST:
		return "东北季风　利南下"
	elif m == Monsoon.SOUTHWEST:
		return "西南季风　利北上"
	return "季风转换期・风微而多变"


# ── 显示 ──────────────────────────────────────────────

## 当前年月所用的年号行：已起用且未过末年的行里取最后一行（ERAS 按起用先后排）。表外返回空数组。
func _era_row() -> Array:
	var found: Array = []
	for e in ERAS:
		var start: Array = ERA_START.get(e[2], [e[0], 1])
		var started: bool = year > start[0] or (year == start[0] and month >= start[1])
		if started and year <= e[1]:
			found = e
	return found


func get_era() -> String:
	var e := _era_row()
	if e.is_empty():
		return "未纪"
	return e[2]


func get_era_year() -> int:
	var e := _era_row()
	if e.is_empty():
		return 0
	return year - e[0] + 1


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


## 自 1255 正月初一算起的绝对日，用于委办期限与行情传闻的保鲜。（云端 bed9）
func absolute_day() -> int:
	return ((year - 1255) * MONTHS_PER_YEAR + (month - 1)) * DAYS_PER_MONTH + (day - 1)


## 「宝祐三年　三月初一」
func get_date_string() -> String:
	var ey := get_era_year()
	var y_str := get_era() + ("元年" if ey == 1 else _cn_number(ey) + "年")
	return "%s　%s%s" % [y_str, get_month_name(), get_day_name()]


## 存档用
func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


func from_dict(d: Dictionary) -> void:
	year = d.get("year", 1255)
	month = d.get("month", 3)
	day = d.get("day", 1)
