extends Node

# 玩家基础属性
var fame: int = 0

# 走私跑商核心机制 v0.5.3
var cargo: Dictionary = {}
var pu_attention: int = 0
var has_customs_permit: bool = false
var last_port: String = "quanzhou"
var current_voyage_origin: String = "quanzhou"

# 旗标系统
var flags: Dictionary = {}

func _ready() -> void:
	pass

# 购买货物
@warning_ignore("unused_parameter")
func buy_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	var total_cost = amount * price_per_unit
	if LedgerSystem.get_balance() >= total_cost:
		LedgerSystem.apply({"amount": -total_cost, "source": "gameplay", "reason": "buy_goods", "actor": "GameState"})
		if cargo.has(item_id):
			cargo[item_id] += amount
		else:
			cargo[item_id] = amount
		return true
	return false

# 售卖货物 (单件)
@warning_ignore("unused_parameter")
func sell_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	if cargo.has(item_id) and cargo[item_id] >= amount:
		cargo[item_id] -= amount
		if cargo[item_id] <= 0:
			cargo.erase(item_id)
		LedgerSystem.apply({"amount": amount * price_per_unit, "source": "gameplay", "reason": "sell_goods", "actor": "GameState"})
		return true
	return false

# 获取当前港口的商品及价格
func get_market_prices(port_id: String) -> Array:
	var goods_list = GameManager.goods_data.get("goods", [])
	var market_items = []
	for g in goods_list:
		if g.get("category") == "货物":
			var base = g.get("base_value", 20)
			# 动态波动算法，未来可接入季节、战争等影响
			var fluctuate = base + (base % 5)
			market_items.append({
				"name": g.get("name"),
				"price": fluctuate,
				"base_value": base,
				"origin": g.get("origin", "")
			})
	return market_items

# 在指定港口抛售所有货物 (含暴利算法)
func sell_all_cargo(port_id: String) -> Dictionary:
	if cargo.is_empty():
		return {"success": false, "earned": 0, "msg": "船舱空空如也，无货可卖。"}
		
	var total_earned = 0
	var goods_list = GameManager.goods_data.get("goods", [])
	
	for key in cargo.keys().duplicate():
		var amt = cargo[key]
		var sell_price = 10
		
		for g in goods_list:
			if g.get("name") == key:
				var base = g.get("base_value", 20)
				var origin = g.get("origin", "")
				
				var is_local = false
				if port_id.begins_with("quanzhou") and ("泉州" in origin or "福建" in origin): is_local = true
				elif port_id.begins_with("xinghua") and ("兴化" in origin or "福建" in origin): is_local = true
				
				# 暴利规则独立化
				if is_local:
					sell_price = int(base * 1.1)
				else:
					sell_price = int(base * 2.5)
				break
		
		sell_goods(key, amt, sell_price)
		total_earned += amt * sell_price
		
	return {"success": true, "earned": total_earned, "msg": "全部抛售，获利 %d 钱！" % total_earned}

# 市舶司验引 / 蒲氏抽解 (Customs Inspection)
func customs_inspection() -> Dictionary:
	var result = {"passed": true, "msg": "", "confiscated": false, "was_smuggling": false}
	
	if has_customs_permit:
		result["passed"] = true
		result["msg"] = "【市舶司验引】出示了泉州货引，缴纳了正常抽解，安全放行。"
		has_customs_permit = false
	else:
		result["was_smuggling"] = true
		if pu_attention > 50:
			result["passed"] = false
			result["confiscated"] = true
			result["msg"] = "【严重警告】蒲氏暗桩早已盯上你！市舶司当场查扣所有无证货物，并处于巨额罚款！"
			var b = LedgerSystem.get_balance()
			var fine = min(b, 500)
			if fine > 0:
				LedgerSystem.apply({"amount": -fine, "source": "system", "reason": "customs_fine", "actor": "GameState"})
			cargo.clear()
		else:
			if LedgerSystem.get_balance() >= 50:
				result["passed"] = true
				result["msg"] = "【惊险过关】没有货引，但蒲氏目前并未留意到你，你塞了 50 钱贿赂小吏，强行出港。"
				LedgerSystem.apply({"amount": -50, "source": "gameplay", "reason": "bribe", "actor": "GameState"})
				pu_attention += 20 # 引起了关注
			else:
				result["passed"] = false
				result["msg"] = "【遣返】你不仅没有货引，连塞给小吏的 50 钱都拿不出！小吏毫不客气地把你轰回了港口。"
			
			
	return result

# 检查出港资格
func can_depart_port() -> Dictionary:
	var res = {"success": false, "msg": ""}
	
	if food <= 0 or water <= 0:
		res["msg"] = "【出港失败】船只水粮耗尽，无法出海！请前往船坞补充。"
		return res
		
	if crew_count <= 0:
		res["msg"] = "【出港失败】没有足够的水手开船！请前往船坞招募。"
		return res
		
	if not has_customs_permit and not flags.has("smuggled_out"):
		res["msg"] = "【出港被拒】没有正规市舶司货引，也未打通暗关，海防营拦住了你的去路！"
		return res
		
	res["success"] = true
	res["msg"] = "【获准出港】"
	return res

# 统一处理特殊业务请求
@warning_ignore("unused_parameter")
func handle_special_action(action: String) -> Dictionary:
	var res = {"success": false, "msg": ""}
	
	if action == "customs_permit":
		has_customs_permit = true
		res["success"] = true
		res["msg"] = "【市舶司】你办理了正规货引，合法离港。"
		
	elif action == "bribe_official_50":
		if LedgerSystem.get_balance() >= 50:
			LedgerSystem.apply({"amount": -50, "source": "gameplay", "reason": "bribe", "actor": "GameState"})
			has_customs_permit = true
			res["success"] = true
			res["msg"] = "贿赂成功，拿到通关凭证。"
		else:
			res["success"] = false
			res["msg"] = "金钱不足！"
			
	elif action == "recruit_crew":
		var space = max_crew - crew_count
		var b = LedgerSystem.get_balance()
		if space > 0 and b >= 10:
			var cost = min(space * 10, b - (b % 10))
			var amount = cost / 10
			LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "recruit_crew", "actor": "GameState"})
			crew_count += amount
			res["success"] = true
			res["msg"] = "招募了 %d 名水手！" % amount
		else:
			res["success"] = false
			res["msg"] = "无法招募！钱不够或船只已满员。"
			
	elif action == "supply_ship":
		if LedgerSystem.get_balance() >= 20:
			LedgerSystem.apply({"amount": -20, "source": "gameplay", "reason": "supply_ship", "actor": "GameState"})
			food = max_food
			water = max_water
			res["success"] = true
			res["msg"] = "水粮已全部补满！"
		else:
			res["success"] = false
			res["msg"] = "【补充失败】金钱不足 20！"
			
	elif action == "sail_world_map":
		var check = can_depart_port()
		if not check["success"]:
			return check
			
		# 出海成功，记录起点，消耗许可
		current_voyage_origin = last_port
		if has_customs_permit:
			has_customs_permit = false
		if flags.has("smuggled_out"):
			flags.erase("smuggled_out")
			
		res["success"] = true
		res["msg"] = "【大航海】文牒验讫，扬帆起航！"
			
	elif action == "confiscate_contraband":
		var to_remove = []
		for good_id in cargo.keys():
			var g_data = GameManager.get_good_data(good_id)
			if g_data.get("legality") == "contraband":
				to_remove.append(good_id)
		for good_id in to_remove:
			cargo.erase(good_id)
		res["success"] = true
		res["msg"] = "【法网】查获的所有违禁品已被没收！"
		
	elif action == "trigger_combat":
		res["success"] = true
		res["msg"] = "【战斗暂未实装】敌意舰队逼近！你只能仓皇撤退，付出了惨痛的代价！"
		fame -= 10
		crew_count = max(0, crew_count - 5)
		if LedgerSystem.get_balance() > 100: 
			LedgerSystem.apply({"amount": -100, "source": "system", "reason": "combat_loss", "actor": "GameState"})
			
	return res

func set_flag(flag_name: String) -> void:
	flags[flag_name] = true

func apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var val = effects[key]
		if key == "fame": fame += val

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
	if LedgerSystem.get_balance() >= cost:
		LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "repair_ship", "actor": "GameState"})
		ship_hp = ship_max_hp
		return true
	return false

func upgrade_armor() -> bool:
	var cost = armor_level * 500
	if LedgerSystem.get_balance() >= cost:
		LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "upgrade_armor", "actor": "GameState"})
		armor_level += 1
		ship_max_hp += 50.0
		ship_hp += 50.0
		return true
	return false

func upgrade_sail() -> bool:
	var cost = sail_level * 600
	if LedgerSystem.get_balance() >= cost:
		LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "upgrade_sail", "actor": "GameState"})
		sail_level += 1
		return true
	return false

# 生存与航海补给系统
var crew_count: int = 30
var max_crew: int = 50
var food: float = 30.0
var max_food: float = 100.0
var water: float = 30.0
var max_water: float = 100.0
var max_cargo: int = 200

func process_daily_consumption() -> void:
	if crew_count <= 0: return
	
	# 每10个水手每天消耗1份食物和1份水
	var daily_consume = float(crew_count) / 10.0
	
	food -= daily_consume
	water -= daily_consume
	
	if food < 0: food = 0
	if water < 0: water = 0
	
	if food == 0 or water == 0:
		# 饥渴状态下，每天饿死或病死 10% 的水手，至少死 1 个
		var deaths = max(1, int(float(crew_count) * 0.1))
		crew_count -= deaths
		if crew_count < 0: crew_count = 0
		print("补给不足！失去水手：", deaths, " 人，当前剩余水手：", crew_count)
