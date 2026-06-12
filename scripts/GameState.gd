extends Node

# 玩家基础属性
var money: int = 1000
var fame: int = 0

# 走私跑商核心机制 v0.5.3
var cargo: Dictionary = {}
var pu_attention: int = 0
var has_customs_permit: bool = false
var last_port: String = "quanzhou"

# 旗标系统
var flags: Dictionary = {}

func _ready() -> void:
	pass

# 购买货物
func buy_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	var total_cost = amount * price_per_unit
	if money >= total_cost:
		money -= total_cost
		if cargo.has(item_id):
			cargo[item_id] += amount
		else:
			cargo[item_id] = amount
		return true
	return false

# 售卖货物
func sell_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	if cargo.has(item_id) and cargo[item_id] >= amount:
		cargo[item_id] -= amount
		if cargo[item_id] <= 0:
			cargo.erase(item_id)
		money += amount * price_per_unit
		return true
	return false

# 市舶司验引 / 蒲氏抽解 (Customs Inspection)
func customs_inspection() -> Dictionary:
	var result = {"passed": true, "msg": "", "confiscated": false}
	
	if has_customs_permit:
		result["passed"] = true
		result["msg"] = "【市舶司验引】出示了泉州货引，缴纳了正常抽解，安全放行。"
	else:
		if pu_attention > 50:
			result["passed"] = false
			result["confiscated"] = true
			result["msg"] = "【严重警告】蒲氏暗桩早已盯上你！市舶司当场查扣所有无证货物，并处于巨额罚款！"
			money = max(0, money - 500)
			cargo.clear()
		else:
			if money >= 50:
				result["passed"] = true
				result["msg"] = "【惊险过关】没有货引，但蒲氏目前并未留意到你，你塞了 50 钱贿赂小吏，强行出港。"
				money -= 50
				pu_attention += 20 # 引起了关注
			else:
				result["passed"] = false
				result["msg"] = "【遣返】你不仅没有货引，连塞给小吏的 50 钱都拿不出！小吏毫不客气地把你轰回了港口。"
			
	return result

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true

func has_flag(flag_name: String) -> bool:
	return flags.has(flag_name) and flags[flag_name] == true

# 战舰属性
var ship_hp: float = 100.0
var ship_max_hp: float = 100.0
var armor_level: int = 1
var sail_level: int = 1

func repair_ship() -> bool:
	var missing_hp = ship_max_hp - ship_hp
	if missing_hp <= 0: return false
	
	var cost = int(missing_hp * 2) # 2钱1血
	if money >= cost:
		money -= cost
		ship_hp = ship_max_hp
		return true
	return false

func upgrade_armor() -> bool:
	var cost = armor_level * 500
	if money >= cost:
		money -= cost
		armor_level += 1
		ship_max_hp += 50.0
		ship_hp += 50.0
		return true
	return false

func upgrade_sail() -> bool:
	var cost = sail_level * 600
	if money >= cost:
		money -= cost
		sail_level += 1
		return true
	return false
