extends Node

# ═══════════════════════════════════════════════════════════
# GameState — 全局玩家状态 Autoload
# 重构版：内部拆分为职责单一的状态模块，外部 API 完全兼容
# ═══════════════════════════════════════════════════════════

## ── 状态模块实例 ─────────────────────────────────────────

var ship: ShipState = ShipState.new()
var survival: SurvivalState = SurvivalState.new()
var trade: TradeState = TradeState.new()
var story: StoryState = StoryState.new()
var navigation: NavigationState = NavigationState.new()

## ── 船只属性代理 ─────────────────────────────────────────

var ship_hp: float:
	get: return ship.hp
	set(v): ship.hp = v

var ship_max_hp: float:
	get: return ship.max_hp
	set(v): ship.max_hp = v

var armor_level: int:
	get: return ship.armor_level
	set(v): ship.armor_level = v

var sail_level: int:
	get: return ship.sail_level
	set(v): ship.sail_level = v

## ── 生存属性代理 ─────────────────────────────────────────

var crew_count: int:
	get: return survival.crew_count
	set(v): survival.crew_count = v

var max_crew: int:
	get: return survival.max_crew
	set(v): survival.max_crew = v

var food: float:
	get: return survival.food
	set(v): survival.food = v

var max_food: float:
	get: return survival.max_food
	set(v): survival.max_food = v

var water: float:
	get: return survival.water
	set(v): survival.water = v

var max_water: float:
	get: return survival.max_water
	set(v): survival.max_water = v

var max_cargo: int:
	get: return survival.max_cargo
	set(v): survival.max_cargo = v

## ── 贸易属性代理 ─────────────────────────────────────────

var pu_attention: int:
	get: return trade.pu_attention
	set(v): trade.pu_attention = v

var has_customs_permit: bool:
	get: return trade.has_customs_permit
	set(v): trade.has_customs_permit = v

## ── 剧情属性代理 ─────────────────────────────────────────

var fame: int:
	get: return story.fame
	set(v): story.fame = v

var flags: Dictionary:
	get: return story.flags
	set(v): story.flags = v

var story_flags: Dictionary:
	get: return story.story_flags
	set(v): story.story_flags = v

var story_items: Dictionary:
	get: return story.story_items
	set(v): story.story_items = v

var linboyuan_relationship: int:
	get: return story.linboyuan_relationship
	set(v): story.linboyuan_relationship = v

var unlocked_chapters: Array:
	get: return story.unlocked_chapters
	set(v): story.unlocked_chapters = v

## ── 航行属性代理 ─────────────────────────────────────────

var last_port: String:
	get: return navigation.last_port
	set(v): navigation.last_port = v

var current_voyage_origin: String:
	get: return navigation.current_voyage_origin
	set(v): navigation.current_voyage_origin = v

var navigation_position: String:
	get: return navigation.navigation_position
	set(v): navigation.navigation_position = v

## ── 公开方法（委托给各模块）─────────────────────────────

func process_daily_consumption() -> void:
	survival.process_daily_consumption()

func sell_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	return trade.sell_goods(item_id, amount, price_per_unit)

func sell_all_cargo(port_id: String) -> Dictionary:
	return trade.sell_all_cargo(port_id, _resolve_good_id, _calc_bulk_sell_price)

func customs_inspection() -> Dictionary:
	return trade.customs_inspection()

func can_depart_port() -> Dictionary:
	var survival_check = survival.can_depart()
	if not survival_check["success"]:
		return survival_check
	if not has_customs_permit and not flags.has("smuggled_out"):
		return {"success": false, "msg": "【出港被拒】没有正规市舶司货引，也未打通暗关，海防营拦住了你的去路！"}
	return {"success": true, "msg": "【获准出港】"}

func set_flag(flag_name: String) -> void:
	story.set_flag(flag_name)

func clear_flag(flag_name: String) -> void:
	story.flags.erase(flag_name)

func has_flag(flag_name: String) -> bool:
	return story.has_flag(flag_name)

func set_story_flag(key: String, value = true) -> void:
	story.set_story_flag(key, value)

func get_story_flag(key: String, default = null):
	return story.get_story_flag(key, default)

func has_story_flag(key: String) -> bool:
	return story.has_story_flag(key)

func has_story_flag_value(key: String, expected) -> bool:
	return story.has_story_flag_value(key, expected)

func acquire_item(item_id: String) -> void:
	story.acquire_item(item_id)

func has_item_flag(item_id: String) -> bool:
	return story.has_item_flag(item_id)

## ── 领域操作方法（供 Handlers 调用）─────────────────────

func modify_fame(amount: int) -> void:
	fame = max(0, fame + amount)

func modify_hp(amount: float) -> void:
	ship_hp = max(0.0, ship_hp + amount)

func modify_crew(amount: int) -> void:
	crew_count = max(0, crew_count + amount)

func set_navigation_flag(flag_name: String) -> void:
	story.set_flag(flag_name)

func set_return_port(port_id: String) -> void:
	navigation.last_port = port_id
	story.set_flag("return_to_port")

func set_navigation_locked(locked: bool) -> void:
	if locked:
		story.set_flag("navigation_locked")
	else:
		story.flags.erase("navigation_locked")

## ── 私有辅助方法 ─────────────────────────────────────────

func _resolve_good_id(key: String) -> Dictionary:
	var g_data = GameManager.get_good_data(key)
	if not g_data.is_empty():
		return g_data
	for g in GameManager.goods_data.get("goods", []):
		if g.get("name") == key:
			return g
	return {}

func _calc_bulk_sell_price(port_id: String, g_data: Dictionary) -> int:
	var base = g_data.get("base_value", 20)
	var origin = g_data.get("origin", "")
	var is_local = false
	if port_id.begins_with("quanzhou") and ("泉州" in origin or "福建" in origin):
		is_local = true
	elif port_id.begins_with("xinghua") and ("兴化" in origin or "福建" in origin):
		is_local = true
	return int(base * 1.1) if is_local else int(base * 2.5)

## ── Dispatchers ───────────────────────────────────────────

func handle_special_action(action: String) -> Dictionary:
	match action:
		"customs_permit":       return _do_customs_permit()
		"sea_customs_check":    return _do_sea_customs_check()
		"bribe_official_50":    return _do_bribe_official()
		"recruit_crew":         return _do_recruit_crew()
		"supply_ship":          return _do_supply_ship()
		"sail_world_map":       return _do_sail_world_map()
		"confiscate_contraband":return _do_confiscate_contraband()
		"trigger_combat":       return _do_trigger_combat()
		_:
			return {"success": false, "msg": ""}

func apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var val = effects[key]
		match key:
			"fame":         fame += val
			"food":         food = clamp(food + float(val), 0.0, max_food)
			"water":        water = clamp(water + float(val), 0.0, max_water)
			"crew_count":   crew_count = max(0, crew_count + int(val))
			"pu_attention": pu_attention += int(val)
			"flag", "flag2":
				if val is String:
					set_flag(val)
			"story_flag", "story_flag2":
				if val is String:
					set_story_flag(val)
				elif val is Dictionary:
					for k in val.keys():
						set_story_flag(str(k), val[k])
			"item_acquired":
				if val is String:
					acquire_item(val)
			"chapter_unlock":
				if val is String:
					story.unlock_chapter(val)
			"linboyuan_relationship":
				linboyuan_relationship += int(val)
			"navigation_position":
				if val is String:
					navigation_position = val
			"smuggled_out": set_flag("smuggled_out")
			"money":
				if val != 0:
					LedgerSystem.apply({"amount": int(val), "source": "scene", "reason": "scene_effect", "actor": "GameState"})
			"acquire_item":
				if val is String:
					acquire_item(val)
			_:
				if not key in ["sea_tendency", "scholar_tendency", "merchant_credit", "ledger_note"]:
					push_warning("[GameState] apply_effects: unknown key '" + key + "'")

## ── Dispatcher 私有实现 ───────────────────────────────────

func _do_customs_permit() -> Dictionary:
	has_customs_permit = true
	return {"success": true, "msg": "【市舶司】你办理了正规货引，合法离港。"}

func _do_sea_customs_check() -> Dictionary:
	var insp = customs_inspection()
	return {"success": insp["passed"], "msg": insp["msg"]}

func _do_bribe_official() -> Dictionary:
	if LedgerSystem.get_balance() >= 50:
		LedgerSystem.apply({"amount": -50, "source": "gameplay", "reason": "bribe", "actor": "GameState"})
		has_customs_permit = true
		return {"success": true, "msg": "贿赂成功，拿到通关凭证。"}
	return {"success": false, "msg": "金钱不足！"}

func _do_recruit_crew() -> Dictionary:
	var space = max_crew - crew_count
	var b = LedgerSystem.get_balance()
	if space > 0 and b >= 10:
		var cost = min(space * 10, b - (b % 10))
		var amount = cost / 10
		LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "recruit_crew", "actor": "GameState"})
		crew_count += amount
		return {"success": true, "msg": "招募了 %d 名水手！" % amount}
	return {"success": false, "msg": "无法招募！钱不够或船只已满员。"}

func _do_supply_ship() -> Dictionary:
	if LedgerSystem.get_balance() >= 20:
		LedgerSystem.apply({"amount": -20, "source": "gameplay", "reason": "supply_ship", "actor": "GameState"})
		food = max_food
		water = max_water
		return {"success": true, "msg": "水粮已全部补满！"}
	return {"success": false, "msg": "【补充失败】金钱不足 20！"}

func _do_sail_world_map() -> Dictionary:
	var check = can_depart_port()
	if not check["success"]:
		return check
	current_voyage_origin = last_port
	if has_customs_permit:
		has_customs_permit = false
	if flags.has("smuggled_out"):
		flags.erase("smuggled_out")
	return {"success": true, "msg": "【大航海】文牒验讫，扬帆起航！"}

func _do_confiscate_contraband() -> Dictionary:
	var to_remove = CargoSystem.get_contraband_keys()
	for good_id in to_remove:
		CargoSystem.remove_all_of(good_id)
	return {"success": true, "msg": "【法网】查获的所有违禁品已被没收！"}

func _do_trigger_combat() -> Dictionary:
	modify_fame(-10)
	modify_crew(-5)
	if LedgerSystem.get_balance() > 100:
		LedgerSystem.apply({"amount": -100, "source": "system", "reason": "combat_loss", "actor": "GameState"})
	return {"success": true, "msg": "【战斗暂未实装】敌意舰队逼近！你只能仓皇撤退，付出了惨痛的代价！"}
