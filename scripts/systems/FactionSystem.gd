class_name FactionSystem extends RefCounted

static func get_faction_data(faction_id: String) -> Dictionary:
	var factions = GameManager.factions_data.get("factions", [])
	for f in factions:
		if f.get("id") == faction_id:
			return f
	return {}

# 根据玩家当前状态与势力行为，判定是否具有敌意
static func is_hostile(faction_id: String) -> bool:
	var faction = get_faction_data(faction_id)
	if faction.is_empty(): return false
	
	var f_type = faction.get("type", "")
	
	# 海盗默认敌对
	if f_type == "pirate":
		return true
		
	# 官军：根据玩家走私状态判定
	if f_type == "government":
		if GameState.pu_attention > 50 and not GameState.has_customs_permit:
			return true
			
	# 商人：通常非敌对，未来可结合声望系统
	if f_type == "merchant" or f_type == "foreign_trade":
		return false
		
	return false
