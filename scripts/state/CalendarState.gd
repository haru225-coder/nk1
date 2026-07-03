class_name CalendarState extends RefCounted

## P7-T 日历状态模块
## 只负责年月日推进、年号显示与存档；不操作舰队/剧情/生存资源。

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const START_YEAR := 1255
const MAX_ADVANCE_DAYS := 400

var year: int = START_YEAR
var month: int = 1
var day: int = 1

var _eras_cache: Array = []
var _eras_loaded: bool = false

signal month_changed(month_key: String)
signal year_changed(year: int)

func advance_days(n: int) -> Dictionary:
	var days := clampi(n, 0, MAX_ADVANCE_DAYS)
	var months_crossed: Array = []
	for _i in range(days):
		day += 1
		if day <= DAYS_PER_MONTH:
			continue
		day = 1
		month += 1
		var crossed_year := false
		if month > MONTHS_PER_YEAR:
			month = 1
			year += 1
			crossed_year = true
		if crossed_year:
			year_changed.emit(year)
		var key := date_key()
		months_crossed.append(key)
		month_changed.emit(key)
	return {"months_crossed": months_crossed, "days_advanced": days}


func advance_to_next_month() -> int:
	var days := days_until_next_month()
	advance_days(days)
	return days


func days_until_next_month() -> int:
	return DAYS_PER_MONTH - day + 1


func date_key() -> String:
	var era := _lookup_era(year)
	if era.is_empty():
		return "Y%dM%d" % [year, month]
	return "%s%d年%d月" % [str(era.get("name", "")), int(era.get("year_in_era", 0)), month]


func months_elapsed() -> int:
	return (year - START_YEAR) * MONTHS_PER_YEAR + (month - 1)


func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


func from_dict(d: Dictionary) -> void:
	year = int(d.get("year", START_YEAR))
	month = clampi(int(d.get("month", 1)), 1, MONTHS_PER_YEAR)
	day = clampi(int(d.get("day", 1)), 1, DAYS_PER_MONTH)


func _lookup_era(abs_year: int) -> Dictionary:
	_load_eras()
	for raw in _eras_cache:
		if not raw is Dictionary:
			continue
		var era: Dictionary = raw
		var start_year := int(era.get("start_year", 0))
		var end_year := int(era.get("end_year", 0))
		if abs_year >= start_year and abs_year < end_year:
			return {
				"name": str(era.get("name", "")),
				"year_in_era": abs_year - start_year + int(era.get("start_era_year", 1)),
			}
	return {}


func _load_eras() -> void:
	if _eras_loaded:
		return
	_eras_loaded = true
	var file := FileAccess.open(ResourcePaths.DATA_CALENDAR_ERAS, FileAccess.READ)
	if file == null:
		_eras_cache = []
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var eras = parsed.get("eras", [])
		_eras_cache = eras if eras is Array else []
	else:
		_eras_cache = []
