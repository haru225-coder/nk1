class_name ShipyardController extends Node

## 船坞子控制器
## 负责船只修理、改装、招募水手、补给、升帆出港。
## 通过信号与父控制器通信。

signal message_logged(msg: String)
signal status_updated
signal scene_requested(scene_id: String)

const SHIPYARD_REPAIR_COST_PER_HP := 2.0
const HIRE_CREW_COST_PER := HireCrewHandler.DEFAULT_COST_PER_CREW
const SUPPLY_FULL_COST := BuySuppliesHandler.SUPPLY_FILL_FLAT_COST
const SUPPLY_PARTIAL_AMOUNT := 20.0
const SUPPLY_PARTIAL_COST := 10

var _interactive_container: HFlowContainer
var _choices_container: VBoxContainer
var _choices_label: Label
var _dialogue_box: Control
var _pending_scene_id: String = ""

func setup(interactive_container: HFlowContainer, choices_container: VBoxContainer, choices_label: Label, dialogue_box: Control, pending_scene_id: String) -> void:
	_interactive_container = interactive_container
	_choices_container = choices_container
	_choices_label = choices_label
	_dialogue_box = dialogue_box
	_pending_scene_id = pending_scene_id
	_build_options()

## 动作成功后刷新船坞选项（与旧 FacilityController._refresh_shipyard_options 行为一致）
func refresh() -> void:
	for child in _choices_container.get_children():
		child.queue_free()
	_build_options()

func _build_options() -> void:
	# 特殊剧情：泉州船坞寻林伯渊
	if GameState.last_port == "quanzhou" \
			and GameState.has_story_flag("spring_autumn_scroll") \
			and not GameState.has_story_flag("met_lin_boyuan"):
		var lin_btn = UIBuilder.make_action_button("★ 按址寻林伯渊的船")
		lin_btn.pressed.connect(func():
			scene_requested.emit("scene03_lin_ship")
		)
		_interactive_container.add_child(lin_btn)

	# NK1-P6: 一键整备按钮 — 自动补满水粮+全量修理（省去逐项点击）
	var needs_prep := (GameState.food < GameState.max_food or GameState.water < GameState.max_water) or GameState.ship_hp < GameState.ship_max_hp
	if needs_prep:
		var prep_cost := 0
		if GameState.food < GameState.max_food or GameState.water < GameState.max_water:
			prep_cost += SUPPLY_FULL_COST
		if GameState.ship_hp < GameState.ship_max_hp:
			prep_cost += ceili((GameState.ship_max_hp - GameState.ship_hp) * SHIPYARD_REPAIR_COST_PER_HP)
		var prep_btn = UIBuilder.make_action_button("⚡ 一键整备 (补给+修理, 共 %d 钱)" % prep_cost)
		prep_btn.pressed.connect(_on_one_click_prepare)
		_choices_container.add_child(prep_btn)

	_setup_shipyard_summary()
	_setup_shipyard_repair_options(_choices_container)
	_setup_shipyard_crew_supply_options(_choices_container)
	_setup_shipyard_hull_options(_choices_container)
	_setup_shipyard_refit_sail(_choices_container, _choices_label)

	# 升帆出港按钮
	var set_sail_btn = UIBuilder.make_set_sail_button("🚢 升帆出港 (出海)")
	set_sail_btn.pressed.connect(_on_set_sail_pressed.bind(set_sail_btn, _dialogue_box))
	_choices_container.add_child(set_sail_btn)
	_choices_label.visible = true

func _setup_shipyard_summary() -> void:
	var flagship := GameState.fleet.get_flagship()
	if flagship == null or _choices_label == null:
		return
	_choices_label.text = ShipSystem.format_ship_summary(flagship)
	_choices_label.visible = true


func _setup_shipyard_repair_options(choices_container: VBoxContainer) -> void:
	var fleet := GameState.fleet
	for i in range(fleet.ships.size()):
		var ship: ShipState = fleet.ships[i]
		if ship.hp >= ship.max_hp:
			continue
		var hp_pct := int(ship.hp / ship.max_hp * 100.0) if ship.max_hp > 0.0 else 0
		for ratio in [0.5, 1.0]:
			var cost := _estimate_repair_cost(i, ratio)
			if cost <= 0:
				continue
			var ratio_label := "半数" if is_equal_approx(ratio, 0.5) else "全量"
			var repair_gain := int((ship.max_hp - ship.hp) * ratio)
			var repair_btn = UIBuilder.make_action_button("🔧 %s 修理%s (耐久 %d%% → +%d HP, %d 钱)" % [ship.name, ratio_label, hp_pct, repair_gain, cost])
			repair_btn.pressed.connect(_on_repair_ship_pressed.bind(i, ratio))
			choices_container.add_child(repair_btn)

func _setup_shipyard_crew_supply_options(choices_container: VBoxContainer) -> void:
	var space := GameState.max_crew - GameState.crew_count
	if space > 0:
		var max_btn = UIBuilder.make_action_button("👥 招募水手 (尽可能多, %d钱/人, 空位%d)" % [HIRE_CREW_COST_PER, space])
		max_btn.pressed.connect(_on_hire_crew_pressed.bind(0, true))
		choices_container.add_child(max_btn)

		var one_btn = UIBuilder.make_action_button("👤 招募 1 名水手 (%d 钱)" % HIRE_CREW_COST_PER)
		one_btn.pressed.connect(_on_hire_crew_pressed.bind(1, false))
		choices_container.add_child(one_btn)

	if GameState.food < GameState.max_food or GameState.water < GameState.max_water:
		var supply_btn = UIBuilder.make_action_button("🍚 补满水粮 (%d 钱)" % SUPPLY_FULL_COST)
		supply_btn.pressed.connect(_on_buy_supplies_pressed.bind("food_water", 0.0, SUPPLY_FULL_COST, true))
		choices_container.add_child(supply_btn)

	if GameState.max_food - GameState.food >= SUPPLY_PARTIAL_AMOUNT:
		var food_btn = UIBuilder.make_action_button("🌾 购买粮食 (+%.0f, %d 钱)" % [SUPPLY_PARTIAL_AMOUNT, SUPPLY_PARTIAL_COST])
		food_btn.pressed.connect(_on_buy_supplies_pressed.bind("food", SUPPLY_PARTIAL_AMOUNT, SUPPLY_PARTIAL_COST, false))
		choices_container.add_child(food_btn)

	if GameState.max_water - GameState.water >= SUPPLY_PARTIAL_AMOUNT:
		var water_btn = UIBuilder.make_action_button("💧 购买淡水 (+%.0f, %d 钱)" % [SUPPLY_PARTIAL_AMOUNT, SUPPLY_PARTIAL_COST])
		water_btn.pressed.connect(_on_buy_supplies_pressed.bind("water", SUPPLY_PARTIAL_AMOUNT, SUPPLY_PARTIAL_COST, false))
		choices_container.add_child(water_btn)

func _setup_shipyard_hull_options(choices_container: VBoxContainer) -> void:
	var flagship := GameState.fleet.get_flagship()
	if flagship == null:
		return
	for offer in ShipSystem.list_shipyard_hull_offers(
		flagship.hull_id, GameState.fame, GameState.has_story_flag
	):
		var hull: Dictionary = offer.get("hull", {})
		var locked: bool = offer.get("locked", false)
		var hull_id := str(hull.get("id", ""))
		var hull_name := str(hull.get("name", hull_id))
		var cost := int(hull.get("change_cost", ShipSystem.get_hull_change_cost(hull_id)))
		var desc := str(hull.get("description", ""))
		var delta := ShipSystem.format_hull_change_delta(flagship, hull_id)
		var label := "🛠 换%s (%d 钱)" % [hull_name, cost]
		if locked:
			var hint := str(offer.get("unlock_hint", ""))
			label = "🔒 换%s — %s" % [hull_name, hint]
		elif not delta.is_empty():
			label += " [%s]" % delta
		elif not desc.is_empty():
			label += " — %s" % desc
		var hull_btn := UIBuilder.make_action_button(label)
		if locked:
			hull_btn.disabled = true
		else:
			hull_btn.pressed.connect(_on_change_hull_pressed.bind(hull_id, cost))
		choices_container.add_child(hull_btn)


func _setup_shipyard_refit_sail(choices_container: VBoxContainer, choices_label: Label) -> void:
	var refit_btn: Button
	var current_type := GameState.sail_type
	var target_type := "lateen" if current_type == "square" else "square"
	var hull_default := ""
	var flagship := GameState.fleet.get_flagship()
	if flagship != null:
		hull_default = str(ShipSystem.get_hull(flagship.hull_id).get("sail_type", ""))
	var restoring := not hull_default.is_empty() and target_type == hull_default
	var cost := 500
	if target_type == "lateen":
		if restoring:
			refit_btn = UIBuilder.make_action_button(
				"💰 %d 恢复船型默认纵帆 (广船等船型的原厂帆装)" % cost
			)
		else:
			refit_btn = UIBuilder.make_action_button(
				"💰 %d 改装为纵帆 (提升逆风/侧风机动，降低顺风极速)" % cost
			)
	else:
		if restoring:
			refit_btn = UIBuilder.make_action_button(
				"💰 %d 恢复船型默认横帆 (福船等船型的原厂帆装)" % cost
			)
		else:
			refit_btn = UIBuilder.make_action_button(
				"💰 %d 改装为横帆 (极大提升顺风航速，但逆风寸步难行)" % cost
			)
	refit_btn.pressed.connect(_on_refit_ship_pressed.bind(cost))
	choices_container.add_child(refit_btn)

func _estimate_repair_cost(ship_index: int, repair_ratio: float) -> int:
	var ship: ShipState = GameState.fleet.ships[ship_index]
	var missing_hp: float = ship.max_hp - ship.hp
	if missing_hp <= 0.0:
		return 0
	return ceili(missing_hp * repair_ratio * SHIPYARD_REPAIR_COST_PER_HP)

func _format_intent_failure(result: IntentResult, fallback: String) -> String:
	if result.error_code == IntentErrorCodes.INSUFFICIENT_FUNDS:
		return GameManager.get_text(result.message_key, "【金钱不足】余额不足以完成此操作。")
	var txt := GameManager.get_text(result.message_key, "")
	return txt if txt != "" else fallback

func _on_repair_ship_pressed(ship_index: int, repair_ratio: float) -> void:
	var intent := Intent.new(
		IntentTypes.REPAIR_SHIP, "player", "shipyard",
		{
			"ship_index": ship_index,
			"repair_ratio": repair_ratio,
			"cost_per_hp": SHIPYARD_REPAIR_COST_PER_HP,
		}
	)
	var result := IntentResolver.resolve(intent)
	if result.success:
		var ship: ShipState = GameState.fleet.ships[ship_index]
		var repaired := float(result.data.get("repaired", 0.0))
		if repaired > 0.0:
			message_logged.emit(
				"【造船厂】%s 修理完成，恢复 %.0f 点耐久，花费 %d 钱。\n\n" % [
					ship.name, repaired, int(result.data.get("cost", 0))
				]
			)
		else:
			message_logged.emit("【造船厂】%s 船体完好，无需修理。\n\n" % ship.name)
		status_updated.emit()
		refresh()
	else:
		message_logged.emit(_format_intent_failure(result, "【造船厂】修理失败。") + "\n\n")

func _on_hire_crew_pressed(crew_count: int, recruit_max: bool) -> void:
	var params := {"cost_per_crew": HIRE_CREW_COST_PER}
	if recruit_max:
		params["recruit_max"] = true
	else:
		params["crew_count"] = crew_count
		params["total_cost"] = crew_count * HIRE_CREW_COST_PER
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.HIRE_CREW, "player", "shipyard", params, {"port_id": GameState.last_port}
	))
	if result.success:
		message_logged.emit(
			"【船坞】招募了 %d 名水手，当前船员 %d/%d。\n\n" % [
				int(result.data.get("crew_count", 0)),
				GameState.crew_count,
				GameState.max_crew,
			]
		)
		status_updated.emit()
		refresh()
	else:
		message_logged.emit(_format_intent_failure(result, "【船坞】招募失败。") + "\n\n")

func _on_buy_supplies_pressed(supply_type: String, amount: float, total_cost: int, fill_to_max: bool) -> void:
	var params := {
		"supply_type": supply_type,
		"total_cost": total_cost,
		"fill_to_max": fill_to_max,
	}
	if not fill_to_max and amount > 0.0:
		params["amount"] = amount
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.BUY_SUPPLIES, "player", "shipyard", params, {"port_id": GameState.last_port}
	))
	if result.success:
		if supply_type == "food_water" and fill_to_max:
			message_logged.emit("【船坞】水粮已全部补满！\n\n")
		elif supply_type == "food":
			message_logged.emit("【船坞】购入粮食，当前存粮 %.0f/%.0f。\n\n" % [GameState.food, GameState.max_food])
		elif supply_type == "water":
			message_logged.emit("【船坞】购入淡水，当前蓄水 %.0f/%.0f。\n\n" % [GameState.water, GameState.max_water])
		else:
			message_logged.emit("【船坞】补给购买成功。\n\n")
		status_updated.emit()
		refresh()
	else:
		message_logged.emit(_format_intent_failure(result, "【船坞】补给购买失败。") + "\n\n")

func _on_refit_ship_pressed(cost: int) -> void:
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.REFIT_SHIP, "player", "shipyard", {"cost": cost, "refit_mode": "sail"}
	))
	if result.success:
		var sail_name := "纵帆" if GameState.sail_type == "lateen" else "横帆"
		message_logged.emit("【造船厂】改装完毕！你的船现在挂起了%s。\n\n" % sail_name)
		status_updated.emit()
		refresh()
	else:
		message_logged.emit(_format_intent_failure(result, "【造船厂】改装失败。") + "\n\n")


func _on_change_hull_pressed(hull_id: String, cost: int) -> void:
	var result := IntentResolver.resolve(Intent.new(
		IntentTypes.REFIT_SHIP, "player", "shipyard",
		{"refit_mode": "hull", "hull_id": hull_id, "cost": cost}
	))
	if result.success:
		var hull_name := str(result.data.get("hull_name", hull_id))
		message_logged.emit("【造船厂】换船完毕！旗舰现为「%s」。\n\n" % hull_name)
		status_updated.emit()
		refresh()
	else:
		message_logged.emit(_format_intent_failure(result, "【造船厂】换船失败。") + "\n\n")

func _on_set_sail_pressed(set_sail_btn: Button, dialogue_box: Control) -> void:
	if GameManager.input_locked:
		return
	var res = GameState.customs_inspection()
	message_logged.emit(res["msg"] + "\n\n")
	status_updated.emit()
	if not res.get("passed", false):
		return
	if res.get("was_smuggling", false):
		set_sail_btn.text = "正在强行出港..."
		GameManager.set_input_locked(true)
		get_tree().create_timer(2.5, false).timeout.connect(func():
			GameManager.set_input_locked(false)
			scene_requested.emit("world_map")
		)
		return
	scene_requested.emit("world_map")

## NK1-P6: 一键整备 — 自动执行补给+修理，省去逐项点击
func _on_one_click_prepare() -> void:
	if GameManager.input_locked:
		return
	var messages: Array[String] = []
	var any_success := false

	# 1. 补满水粮
	if GameState.food < GameState.max_food or GameState.water < GameState.max_water:
		var supply_result := IntentResolver.resolve(Intent.new(
			IntentTypes.BUY_SUPPLIES, "player", "shipyard",
			{"supply_type": "food_water", "total_cost": SUPPLY_FULL_COST, "fill_to_max": true},
			{"port_id": GameState.last_port}
		))
		if supply_result.success:
			messages.append("水粮已补满")
			any_success = true
		else:
			messages.append("水粮补给失败（金钱不足）")

	# 2. 全量修理
	if GameState.ship_hp < GameState.ship_max_hp:
		var repair_result := IntentResolver.resolve(Intent.new(
			IntentTypes.REPAIR_SHIP, "player", "shipyard",
			{"ship_index": 0, "repair_ratio": 1.0, "cost_per_hp": SHIPYARD_REPAIR_COST_PER_HP},
			{"port_id": GameState.last_port}
		))
		if repair_result.success:
			var repaired := float(repair_result.data.get("repaired", 0.0))
			if repaired > 0.0:
				messages.append("修理恢复 %.0f HP" % repaired)
				any_success = true
			else:
				messages.append("船体已完好")
		else:
			messages.append("修理失败（金钱不足）")

	if any_success:
		message_logged.emit("【整备】%s。\n\n" % "，".join(messages))
	else:
		message_logged.emit("【整备】%s。\n\n" % "，".join(messages))
	status_updated.emit()
	refresh()
