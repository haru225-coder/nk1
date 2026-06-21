class_name EncounterSystem extends RefCounted

# 仅作为感知器 (Sensor)，收集上下文并请求 EncounterResolver 裁决
static func resolve_encounter(fleet_id: String) -> Dictionary:
	var fleet = null
	for f in FleetSystem.active_fleets:
		if f["id"] == fleet_id:
			fleet = f
			break
			
	if fleet == null: return {}
	
	var faction_id = fleet.get("faction", "")
	var faction_data = FactionSystem.get_faction_data(faction_id)
	var behaviors = faction_data.get("behavior", [])
	
	# 构建上下文环境
	var context = {
		"aggressor_id": fleet_id,
		"faction_id": faction_id,
		"behaviors": behaviors,
		"violation": calculate_cargo_violation()
	}
	
	# 将状态移交遭遇决议器
	return EncounterResolver.get_encounter_data(context)

# 货物合法性嗅探（海上盘查 / InspectionHandler 共用）
static func calculate_cargo_violation() -> String:
	var has_contraband = false
	var has_goods = false
	
	for good_id in CargoSystem.get_keys():
		if CargoSystem.get_amount(good_id) > 0:
			has_goods = true
			var g_data = GameManager.get_good_data(good_id)
			if g_data.get("legality") == "contraband":
				has_contraband = true
				break
				
	if has_contraband:
		return "contraband"
		
	if has_goods and not GameState.has_customs_permit:
		return "illegal_trade"
		
	return "legal"
