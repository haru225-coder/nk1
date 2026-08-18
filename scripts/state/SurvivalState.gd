class_name SurvivalState extends RefCounted

## 生存资源管理模块

## ── 资源常量 ─────────────────────────────────────────────
const DEFAULT_FOOD := 30.0           ## 初始粮食
const DEFAULT_WATER := 30.0          ## 初始淡水
const MAX_FOOD := 100.0              ## 粮食上限
const MAX_WATER := 100.0             ## 淡水上限
const MAX_CARGO := 200               ## 货舱上限
const DAILY_CONSUME_DIVISOR := 10.0  ## 每日消耗除数（crew ÷ 此值）
const STARVATION_DEATH_RATIO := 0.1  ## 断粮/断水时水手死亡率

var food: float = DEFAULT_FOOD
var max_food: float = MAX_FOOD
var water: float = DEFAULT_WATER
var max_water: float = MAX_WATER
var max_cargo: int = MAX_CARGO

func to_dict() -> Dictionary:
	return {"food": food, "max_food": max_food, "water": water, "max_water": max_water, "max_cargo": max_cargo}

func from_dict(d: Dictionary) -> void:
	max_food = _clamp_max(_as_finite(d.get("max_food", MAX_FOOD), MAX_FOOD), 1.0, MAX_FOOD)
	max_water = _clamp_max(_as_finite(d.get("max_water", MAX_WATER), MAX_WATER), 1.0, MAX_WATER)
	food = clampf(_as_finite(d.get("food", DEFAULT_FOOD), DEFAULT_FOOD), 0.0, max_food)
	water = clampf(_as_finite(d.get("water", DEFAULT_WATER), DEFAULT_WATER), 0.0, max_water)
	max_cargo = clampi(int(d.get("max_cargo", MAX_CARGO)), 1, MAX_CARGO)

static func _as_finite(value, fallback: float) -> float:
	var n := float(value)
	if is_nan(n) or is_inf(n):
		return fallback
	return n

static func _clamp_max(value: float, lo: float, hi: float) -> float:
	return clampf(value, lo, hi)

signal crew_lost(amount: int)
signal resource_depleted(resource: String)

func process_daily_consumption(total_crew: int) -> int:
	if total_crew <= 0: return 0
	var daily_consume = float(total_crew) / DAILY_CONSUME_DIVISOR
	food -= daily_consume
	water -= daily_consume
	if food < 0: food = 0
	if water < 0: water = 0
	
	var deaths = 0
	if food == 0 or water == 0:
		deaths = max(1, int(float(total_crew) * STARVATION_DEATH_RATIO))
		crew_lost.emit(deaths)
		if food == 0:
			resource_depleted.emit("food")
		if water == 0:
			resource_depleted.emit("water")
	return deaths

func can_depart(total_crew: int) -> Dictionary:
	var res = {"success": false, "msg": ""}
	if food <= 0 or water <= 0:
		res["msg"] = "【出港失败】船只水粮耗尽，无法出海！请前往船坞补充。"
		return res
	if total_crew <= 0:
		res["msg"] = "【出港失败】没有足够的水手开船！请前往船坞招募。"
		return res
	res["success"] = true
	return res
