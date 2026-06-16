class_name SurvivalState extends RefCounted

## 生存资源管理模块

var crew_count: int = 30
var max_crew: int = 50
var food: float = 30.0
var max_food: float = 100.0
var water: float = 30.0
var max_water: float = 100.0
var max_cargo: int = 200

signal crew_lost(amount: int)
signal resource_depleted(resource: String)

func process_daily_consumption() -> void:
	if crew_count <= 0: return
	var daily_consume = float(crew_count) / 10.0
	food -= daily_consume
	water -= daily_consume
	if food < 0: food = 0
	if water < 0: water = 0
	if food == 0 or water == 0:
		var deaths = max(1, int(float(crew_count) * 0.1))
		crew_count -= deaths
		if crew_count < 0: crew_count = 0
		crew_lost.emit(deaths)
		if food == 0:
			resource_depleted.emit("food")
		if water == 0:
			resource_depleted.emit("water")

func can_depart() -> Dictionary:
	var res = {"success": false, "msg": ""}
	if food <= 0 or water <= 0:
		res["msg"] = "【出港失败】船只水粮耗尽，无法出海！请前往船坞补充。"
		return res
	if crew_count <= 0:
		res["msg"] = "【出港失败】没有足够的水手开船！请前往船坞招募。"
		return res
	res["success"] = true
	return res
