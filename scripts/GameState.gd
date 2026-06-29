extends Node

# ═══════════════════════════════════════════════════════════
# GameState — 全局玩家状态 Autoload
# 重构版：内部拆分为职责单一的状态模块，外部 API 完全兼容
# ═══════════════════════════════════════════════════════════

## ── 状态模块实例 ─────────────────────────────────────────

var fleet: FleetState = FleetState.new()
var survival: SurvivalState = SurvivalState.new()
var trade: TradeState = TradeState.new()
var story: StoryState = StoryState.new()
var navigation: NavigationState = NavigationState.new()
var market: MarketState = MarketState.new()
var economy_log: EconomyLog = EconomyLog.new()
var game_log: GameLog = GameLog.new()

## ── 幂等守卫定期清理 ─────────────────────────────────────

var _last_cleanup := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_cleanup > 60000:
		IdempotencyGuard.cleanup_old_records()
		_last_cleanup = now

## ── 船只属性代理 ─────────────────────────────────────────

var ship_hp: float:
	get: return fleet.get_flagship().hp
	set(v): fleet.get_flagship().hp = v

var ship_max_hp: float:
	get: return fleet.get_flagship().max_hp
	set(v): fleet.get_flagship().max_hp = v

var armor_level: int:
	get: return fleet.get_flagship().armor_level
	set(v): fleet.get_flagship().armor_level = v

var sail_level: int:
	get: return fleet.get_flagship().sail_level
	set(v): fleet.get_flagship().sail_level = v

var sail_type: String:
	get: return fleet.get_flagship().sail_type
	set(v): fleet.get_flagship().sail_type = v

var artillery: int:
	get: return fleet.get_flagship().artillery
	set(v): fleet.get_flagship().artillery = v

var swordplay: int:
	get: return fleet.get_flagship().swordplay
	set(v): fleet.get_flagship().swordplay = v

var maneuverability: int:
	get: return fleet.get_flagship().maneuverability
	set(v): fleet.get_flagship().maneuverability = v

## ── 生存属性代理 ─────────────────────────────────────────

var crew_count: int:
	get: return fleet.get_total_crew()
	set(v): 
		var diff = v - fleet.get_total_crew()
		fleet.modify_crew(diff)

var max_crew: int:
	get: return fleet.get_max_crew()
	set(v): fleet.get_flagship().max_crew = v

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
	set(v): trade.pu_attention = clampi(v, 0, 20)

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

var jia_relationship: int:
	get: return story.jia_relationship
	set(v): story.jia_relationship = v

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
	var deaths = survival.process_daily_consumption(crew_count)
	if deaths > 0:
		modify_crew(-deaths)

func sell_goods(item_id: String, amount: int, price_per_unit: int) -> bool:
	return trade.sell_goods(item_id, amount, price_per_unit)

func sell_all_cargo(port_id: String) -> Dictionary:
	return trade.sell_all_cargo(port_id, _resolve_good_id, _calc_bulk_sell_price)

func customs_inspection() -> Dictionary:
	var result := trade.customs_inspection()
	if result.get("passed", false):
		if result.get("was_smuggling", false):
			set_flag("smuggled_out")
		else:
			set_flag("departure_authorized")
	return result

func can_depart_port() -> Dictionary:
	var survival_check = survival.can_depart(crew_count)
	if not survival_check["success"]:
		return survival_check
	if (
		not has_customs_permit
		and not flags.has("smuggled_out")
		and not flags.has("departure_authorized")
	):
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
	_sync_world_map_ship_hp()

func _sync_world_map_ship_hp() -> void:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var scene_tree := tree as SceneTree
		var ships: Array = scene_tree.get_nodes_in_group("player_ship")
		if ships.is_empty():
			return
		var ship_node: Node = ships[0]
		if not is_instance_valid(ship_node):
			return
		if "hull_hp" in ship_node:
			ship_node.hull_hp = ship_hp
		if ship_node.has_method("_sync_from_flagship"):
			ship_node._sync_from_flagship()

func modify_crew(amount: int) -> void:
	crew_count = max(0, crew_count + amount)

func set_navigation_flag(flag_name: String) -> void:
	story.set_flag(flag_name)

func set_return_port(port_id: String) -> void:
	navigation.return_port(port_id)
	story.set_flag("return_to_port")

func save_world_map_ship_pose(pos: Vector2, rot: float) -> void:
	navigation.save_world_map_pose(pos, rot)

func clear_world_map_ship_pose() -> void:
	navigation.clear_world_map_pose()

func has_world_map_ship_pose() -> bool:
	return navigation.world_map_pose_saved

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
	return GameManager.get_good_by_name(key)

func _calc_bulk_sell_price(port_id: String, g_data: Dictionary) -> int:
	return EconomySystem.get_price(port_id, g_data.get("id", ""))

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
		"drop_cargo_half":      return _do_drop_cargo_half()
		_:
			return {"success": false, "msg": ""}

## ── 效果处理器映射表 ───────────────────────────────────────
var _effect_handlers: Dictionary = {}

func _init_effect_handlers() -> void:
	_effect_handlers = {
		"fame":                     _apply_fame,
		"food":                     _apply_food,
		"water":                    _apply_water,
		"crew_count":               _apply_crew_count,
		"pu_attention":             _apply_pu_attention,
		"flag":                     _apply_flag,
		"flag2":                    _apply_flag,
		"story_flag":               _apply_story_flag,
		"story_flag2":              _apply_story_flag,
		"item_acquired":            _apply_item_acquired,
		"acquire_item":             _apply_item_acquired,
		"chapter_unlock":           _apply_chapter_unlock,
		"linboyuan_relationship":   _apply_linboyuan_rel,
		"jia_relationship":         _apply_jia_rel,
		"item_removed":             _apply_item_removed,
		"navigation_position":      _apply_nav_position,
		"smuggled_out":             _apply_smuggled_out,
		"money":                    _apply_money,
		"hull_hp":                  _apply_hull_hp,
		"cargo":                    _apply_cargo,
		"artillery":                _apply_artillery,
		"swordplay":                _apply_swordplay,
		"maneuverability":          _apply_maneuverability,
		"npc_affinity":             _apply_npc_affinity,
	}

const _SILENT_KEYS := ["sea_tendency", "scholar_tendency", "merchant_credit", "ledger_note"]

func apply_effects(effects: Dictionary) -> void:
	if _effect_handlers.is_empty():
		_init_effect_handlers()
	for key in effects.keys():
		var val = effects[key]
		if _effect_handlers.has(key):
			_effect_handlers[key].call(val)
		elif not key in _SILENT_KEYS:
			push_warning("[GameState] apply_effects: unknown key '" + key + "'")

## ── 各效果处理器 ───────────────────────────────────────────

func _apply_fame(val) -> void:
	fame = max(0, fame + int(val))

func _apply_food(val) -> void:
	food = clamp(food + float(val), 0.0, max_food)

func _apply_water(val) -> void:
	water = clamp(water + float(val), 0.0, max_water)

func _apply_crew_count(val) -> void:
	crew_count = max(0, crew_count + int(val))

func _apply_pu_attention(val) -> void:
	pu_attention = clampi(pu_attention + int(val), 0, 20)

func _apply_flag(val) -> void:
	if val is String:
		set_flag(val)

func _apply_story_flag(val) -> void:
	if val is String:
		set_story_flag(val)
	elif val is Dictionary:
		for k in val.keys():
			set_story_flag(str(k), val[k])

func _apply_item_acquired(val) -> void:
	if val is String:
		acquire_item(val)

func _apply_chapter_unlock(val) -> void:
	if val is String:
		story.unlock_chapter(val)

func _apply_linboyuan_rel(val) -> void:
	linboyuan_relationship += int(val)

func _apply_jia_rel(val) -> void:
	jia_relationship += int(val)

func _apply_item_removed(val) -> void:
	if val is String:
		story.remove_item(val)

func _apply_nav_position(val) -> void:
	if val is String:
		navigation_position = val

func _apply_smuggled_out(_val) -> void:
	set_flag("smuggled_out")

func _apply_money(val) -> void:
	if val != 0:
		# INTENT_DEFERRED: 剧情 apply_effects 金钱变动 — 场景脚本副作用，保留直连 Ledger
		LedgerSystem.apply({"amount": int(val), "source": "scene", "reason": "scene_effect", "actor": "GameState"})

func _apply_hull_hp(val) -> void:
	modify_hp(float(val))

func _apply_cargo(val) -> void:
	if val is float or val is int:
		var ratio := absf(float(val))
		if float(val) < 0.0:
			CargoSystem.remove_fraction(ratio)

func _apply_artillery(val) -> void:
	artillery = max(0, artillery + int(val))

func _apply_swordplay(val) -> void:
	swordplay = max(0, swordplay + int(val))

func _apply_maneuverability(val) -> void:
	maneuverability = max(0, maneuverability + int(val))

func _apply_npc_affinity(val) -> void:
	if val is Dictionary:
		var npc_id := str(val.get("npc_id", ""))
		if npc_id.is_empty():
			return
		story.adjust_npc_affinity(npc_id, int(val.get("delta", 0)))

## ── Dispatcher 私有实现 ───────────────────────────────────

func _do_customs_permit() -> Dictionary:
	has_customs_permit = true
	return {"success": true, "msg": "【市舶司】你办理了正规货引，合法离港。"}

func _do_sea_customs_check() -> Dictionary:
	var insp = customs_inspection()
	return {"success": insp["passed"], "msg": insp["msg"]}

func _do_bribe_official() -> Dictionary:
	var intent := Intent.new(
		IntentTypes.BRIBE, "player", "customs_officer",
		{"amount": 50, "attention_delta": 0, "grant_permit": true}
	)
	var result := IntentResolver.resolve(intent)
	if result.success:
		return {"success": true, "msg": "贿赂成功，拿到通关凭证。"}
	if result.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS:
		return {"success": false, "msg": "金钱不足！"}
	return {"success": false, "msg": "贿赂失败。"}

func repair_ship_via_intent(
	ship_index: int = 0,
	repair_ratio: float = 1.0,
	cost_per_hp: float = 1.0
) -> IntentResult:
	return IntentResolver.resolve(Intent.new(
		IntentTypes.REPAIR_SHIP, "player", "shipyard",
		{"ship_index": ship_index, "repair_ratio": repair_ratio, "cost_per_hp": cost_per_hp}
	))

func _do_recruit_crew() -> Dictionary:
	return _intent_action_to_dict(IntentResolver.resolve(Intent.new(
		IntentTypes.HIRE_CREW, "player", "shipyard",
		{"cost_per_crew": 10, "recruit_max": true},
		{"port_id": last_port}
	)), "招募了 %d 名水手！" % 0, "无法招募！钱不够或船只已满员。")

func _do_supply_ship() -> Dictionary:
	return _intent_action_to_dict(IntentResolver.resolve(Intent.new(
		IntentTypes.BUY_SUPPLIES, "player", "shipyard",
		{"supply_type": "food_water", "total_cost": 20, "fill_to_max": true},
		{"port_id": last_port}
	)), "水粮已全部补满！", "【补充失败】金钱不足 20！")

func _intent_action_to_dict(result: IntentResult, ok_msg: String, fail_msg: String) -> Dictionary:
	if result.success:
		if result.type == IntentTypes.HIRE_CREW:
			return {"success": true, "msg": "招募了 %d 名水手！" % int(result.data.get("crew_count", 0))}
		return {"success": true, "msg": ok_msg}
	if result.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS:
		return {"success": false, "msg": fail_msg}
	if result.error_code == IntentErrorCodes.CREW_LIMIT_REACHED:
		return {"success": false, "msg": "无法招募！船只已满员。"}
	if result.error_code == IntentErrorCodes.SUPPLY_LIMIT_REACHED:
		return {"success": false, "msg": "【补充失败】水粮已满，无需购买。"}
	if result.error_code == IntentErrorCodes.PORT_RECRUIT_BLOCKED:
		return {"success": false, "msg": "【招募失败】当前港口无法招募水手。"}
	return {"success": false, "msg": fail_msg}

func _do_sail_world_map() -> Dictionary:
	var check = can_depart_port()
	if not check["success"]:
		return check
	var depart_result := navigation.depart_port(check)
	if not depart_result.get("success", false):
		return depart_result
	if has_customs_permit:
		has_customs_permit = false
	if flags.has("smuggled_out"):
		flags.erase("smuggled_out")
	if flags.has("departure_authorized"):
		flags.erase("departure_authorized")
	return depart_result

func _do_confiscate_contraband() -> Dictionary:
	var to_remove = CargoSystem.get_contraband_keys()
	for good_id in to_remove:
		CargoSystem.remove_all_of(good_id)
	return {"success": true, "msg": "【法网】查获的所有违禁品已被没收！"}

func _do_drop_cargo_half() -> Dictionary:
	CargoSystem.remove_fraction(0.5)
	return {"success": true, "msg": ""}

func _do_trigger_combat() -> Dictionary:
	# INTENT_DEFERRED: 旧 stub — 战斗现由 IntentResolver → CombatHandler → CombatSessionController 统一管理。
	# 保留此方法作为安全兜底，不再扣减玩家资源。
	return {"success": true, "msg": "【警告】战斗应通过 Intent 管道（combat_request）触发。"}

## ── 存档序列化 ───────────────────────────────────────────

func to_save_dict() -> Dictionary:
	return {
		"fleet": fleet.to_dict() if fleet else {},
		"survival": survival.to_dict() if survival else {},
		"trade": trade.to_dict() if trade else {},
		"story": story.to_dict() if story else {},
		"navigation": navigation.to_dict() if navigation else {},
		"market": market.to_dict() if market else {},
		"economy_log": economy_log.to_dict() if economy_log else {},
		"game_log": game_log.to_dict() if game_log else {},
	}

func from_save_dict(data: Dictionary) -> void:
	if data.has("fleet") and fleet:
		fleet.from_dict(data["fleet"])
	if data.has("survival") and survival:
		survival.from_dict(data["survival"])
	if data.has("trade") and trade:
		trade.from_dict(data["trade"])
	if data.has("story") and story:
		story.from_dict(data["story"])
	if data.has("navigation") and navigation:
		navigation.from_dict(data["navigation"])
	if data.has("market") and market:
		market.from_dict(data["market"])
	if data.has("economy_log") and economy_log:
		economy_log.from_dict(data["economy_log"])
	if data.has("game_log") and game_log:
		game_log.from_dict(data["game_log"])
