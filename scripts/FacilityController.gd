extends Control

signal scene_requested(scene_id: String)
signal status_updated
signal show_npc_requested(npc_id: String, fallback_name: String)
signal message_logged(msg: String)

@onready var scene_title: Label = $MarginContainer/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $MarginContainer/VBoxContainer/BodyText
@onready var interactive_container: HFlowContainer = $MarginContainer/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $MarginContainer/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $MarginContainer/VBoxContainer/ChoicesLabel
@onready var interactive_label: Label = $MarginContainer/VBoxContainer/InteractiveLabel
@onready var city_nav_panel: PanelContainer = $MarginContainer/VBoxContainer/CityNavPanel
@onready var city_nav_label: Label = $MarginContainer/VBoxContainer/CityNavPanel/CityNavMargin/CityNavVBox/CityNavLabel
@onready var city_nav_flow: HFlowContainer = $MarginContainer/VBoxContainer/CityNavPanel/CityNavMargin/CityNavVBox/CityNavFlow
var dialogue_box: Control
@onready var content_root: MarginContainer = $MarginContainer

var _pending_scene_data: Dictionary = {}
var _pending_scene_id: String = ""
var _dialogue_done: bool = false

func bind_dialogue_box(box: Control) -> void:
	dialogue_box = box
	if dialogue_box == null:
		return
	if not dialogue_box.sequence_finished.is_connected(_on_dialogue_sequence_finished):
		dialogue_box.sequence_finished.connect(_on_dialogue_sequence_finished)
	if dialogue_box.has_signal("active_changed") and not dialogue_box.active_changed.is_connected(_on_dialogue_active_changed):
		dialogue_box.active_changed.connect(_on_dialogue_active_changed)

func _ready() -> void:
	body_text.visible = false

func _on_dialogue_active_changed(is_active: bool) -> void:
	var content_target := Color(0.72, 0.72, 0.72, 1.0) if is_active else Color(1, 1, 1, 1)
	var title_alpha := 0.3 if is_active else 1.0
	var bottom_margin := int(GameUILayout.DIALOGUE_BAR_HEIGHT) if is_active else 12
	content_root.add_theme_constant_override("margin_bottom", bottom_margin)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(content_root, "modulate", content_target, 0.2)
	tween.tween_property(scene_title, "modulate:a", title_alpha, 0.2)

func _style_choice_button(btn: Button) -> void:
	btn.theme_type_variation = "ChoiceButton"
	btn.custom_minimum_size = Vector2(0, 44)

func _style_action_button(btn: Button) -> void:
	btn.theme_type_variation = "ActionButton"
	btn.custom_minimum_size = Vector2(0, 40)

# ======= 常规 Investigation ========

func setup_investigation(scene_data: Dictionary, scene_id: String) -> void:
	scene_data = _resolve_scene_variant(scene_data, scene_id)
	_pending_scene_data = scene_data
	_pending_scene_id = scene_id
	_dialogue_done = false
	scene_title.text = scene_data.get("title", "未命名地点")
	body_text.text = ""
	_clear_containers()
	_hide_post_dialogue_ui()
	var beats: Array = DialogueParser.parse_body(scene_data.get("body", ""))
	if beats.is_empty():
		_on_dialogue_sequence_finished()
	else:
		dialogue_box.start_sequence(beats)

func _on_dialogue_sequence_finished() -> void:
	if _dialogue_done or _pending_scene_data.is_empty():
		return
	_dialogue_done = true
	_setup_post_dialogue_content()

func _setup_post_dialogue_content() -> void:
	var scene_data: Dictionary = _pending_scene_data
	_clear_containers()
	_setup_city_nav()

	var investigations = scene_data.get("investigations", [])
	var added_inv := 0
	for inv in investigations:
		if not _investigation_available(inv):
			continue
		if added_inv == 0:
			interactive_label.visible = true
		var btn = Button.new()
		btn.text = "★ " + inv.get("label", "互动")
		_style_action_button(btn)
		btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
		interactive_container.add_child(btn)
		added_inv += 1
	if added_inv == 0:
		interactive_label.visible = false

	if _pending_scene_id.ends_with("_market") or scene_data.get("id", "") == "city_market":
		_setup_market_goods()

	if _pending_scene_id.ends_with("_shipyard") or scene_data.get("id", "") == "city_shipyard":
		_setup_shipyard_options()

	if _pending_scene_id.ends_with("_tavern") or scene_data.get("id", "").ends_with("_tavern"):
		_setup_tavern_rumors()

	if scene_data.has("npc_encounter"):
		var npc_id = scene_data.get("npc_encounter")
		var fallback_name = "神秘人物"
		if "lin_boyuan" in npc_id or "lin" in npc_id:
			fallback_name = "林伯渊"
		elif "abbas" in npc_id:
			fallback_name = "阿巴斯"
		elif "teacher" in npc_id:
			fallback_name = "先生"
		elif "jia" in npc_id:
			fallback_name = "贾府门生"
		elif "ketagalan" in npc_id:
			fallback_name = "凯达格兰人"
		elif "official" in npc_id:
			fallback_name = "市舶司小吏"
		_add_npc_button(npc_id, fallback_name)

	show_choices(scene_data.get("choices", []))

# ======= 缺失场景 ========

func setup_missing(scene_id: String) -> void:
	_clear_containers()
	_hide_post_dialogue_ui()
	_dialogue_done = false
	scene_title.text = "区域施工中..."
	var beat := DialogueParser.beat_from_text(
		"该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"
	)
	dialogue_box.start_sequence([beat])
	_pending_scene_data = {}
	await dialogue_box.sequence_finished
	var btn = Button.new()
	btn.text = "离开"
	_style_choice_button(btn)
	btn.pressed.connect(func(): scene_requested.emit(GameManager.get_port_scene_id(GameState.last_port)))
	choices_container.add_child(btn)
	choices_label.visible = true

# ======== 市场货品生成 ========

func _setup_market_goods() -> void:
	var snapshot = EconomySystem.get_market_snapshot(GameState.last_port)
	var added = 0
	for item in snapshot.get("goods", []):
		var good_id = item.get("id", "")
		var item_name = item.get("name", good_id)
		var price = item.get("price", 0)
		if good_id.is_empty():
			continue
		var btn = Button.new()
		btn.text = "购入：%s (%d钱)" % [item_name, price]
		_style_action_button(btn)
		btn.pressed.connect(_on_buy_pressed.bind(good_id, item_name, price))
		interactive_container.add_child(btn)
		added += 1
		if added >= 4:
			break

	var sell_btn = Button.new()
	sell_btn.text = "抛售所有货物"
	_style_choice_button(sell_btn)
	sell_btn.pressed.connect(_on_sell_all_pressed)
	choices_container.add_child(sell_btn)
	choices_label.visible = true

func _on_buy_pressed(good_id: String, item_name: String, price: int) -> void:
	var intent = Intent.new(
		"market_buy", "player", "market",
		{"good_id": good_id, "amount": 1},
		{"port_id": GameState.last_port}
	)
	var result = IntentResolver.process(intent)
	if result.success:
		message_logged.emit("成功买入 1 份 " + item_name + "\n\n")
		status_updated.emit()
	else:
		var reason = GameManager.get_text(result.message_key, "【交易失败】金钱不足或货舱已满。")
		message_logged.emit(reason + "\n\n")

func _on_sell_all_pressed() -> void:
	var res = GameState.sell_all_cargo(GameState.last_port)
	message_logged.emit(res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()

# ======== 码头功能 ========

const SHIPYARD_REPAIR_COST_PER_HP := 2.0

func _resolve_scene_variant(scene_data: Dictionary, scene_id: String) -> Dictionary:
	return SceneVariantResolver.resolve(scene_data, scene_id)

func _refresh_shipyard_options() -> void:
	for child in choices_container.get_children():
		child.queue_free()
	_setup_shipyard_options()

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
		"repair_ship", "player", "shipyard",
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
		_refresh_shipyard_options()
	else:
		message_logged.emit(_format_intent_failure(result, "【造船厂】修理失败。") + "\n\n")

func _on_refit_ship_pressed(cost: int) -> void:
	var result := IntentResolver.resolve(Intent.new(
		"refit_ship", "player", "shipyard", {"cost": cost}
	))
	if result.success:
		var sail_name := "纵帆" if GameState.sail_type == "lateen" else "横帆"
		message_logged.emit("【造船厂】改装完毕！你的船现在挂起了%s。\n\n" % sail_name)
		status_updated.emit()
		_refresh_shipyard_options()
	else:
		message_logged.emit(_format_intent_failure(result, "【造船厂】改装失败。") + "\n\n")

func _setup_shipyard_repair_options() -> void:
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
			var repair_btn := Button.new()
			repair_btn.text = "🔧 %s 修理%s (耐久 %d%% → +%d HP, %d 钱)" % [
				ship.name, ratio_label, hp_pct, repair_gain, cost
			]
			repair_btn.custom_minimum_size = Vector2(0, 52)
			repair_btn.theme_type_variation = "ActionButton"
			repair_btn.pressed.connect(_on_repair_ship_pressed.bind(i, ratio))
			choices_container.add_child(repair_btn)

func _setup_shipyard_options() -> void:
	if GameState.last_port == "quanzhou" \
			and GameState.has_story_flag("spring_autumn_scroll") \
			and not GameState.has_story_flag("met_lin_boyuan"):
		var lin_btn := Button.new()
		lin_btn.text = "★ 按址寻林伯渊的船"
		lin_btn.custom_minimum_size = Vector2(0, 52)
		lin_btn.theme_type_variation = "ActionButton"
		lin_btn.pressed.connect(func():
			scene_requested.emit("scene03_lin_ship")
		)
		interactive_container.add_child(lin_btn)
		interactive_label.visible = true

	_setup_shipyard_repair_options()

	var refit_btn = Button.new()
	var current_type = GameState.sail_type
	var cost = 500
	if current_type == "square":
		refit_btn.text = "💰 500 改装为纵帆 (提升逆风/侧风机动，降低顺风极速)"
	else:
		refit_btn.text = "💰 500 改装为横帆 (极大提升顺风航速，但逆风寸步难行)"
	refit_btn.custom_minimum_size = Vector2(0, 52)
	refit_btn.theme_type_variation = "ActionButton"
	refit_btn.pressed.connect(_on_refit_ship_pressed.bind(cost))
	choices_container.add_child(refit_btn)

	var set_sail_btn = Button.new()
	set_sail_btn.text = "🚢 升帆出港 (出海)"
	set_sail_btn.custom_minimum_size = Vector2(0, 60)
	set_sail_btn.theme_type_variation = "SetSailButton"

	set_sail_btn.pressed.connect(_on_set_sail_pressed.bind(set_sail_btn))
	choices_container.add_child(set_sail_btn)
	choices_label.visible = true

# ======== 辅助方法 ========

func _setup_city_nav() -> void:
	for child in city_nav_flow.get_children():
		child.queue_free()
	var port_id: String = GameState.last_port
	if port_id == "":
		city_nav_panel.visible = false
		return
	var sid: String = _pending_scene_id
	if sid.begins_with("scene0") or sid.begins_with("port_") or sid.begins_with("chapter2_") or sid == "cg_title":
		city_nav_panel.visible = false
		return
	var port_scene: Dictionary = GameManager.get_scene_by_id(GameManager.get_port_scene_id(port_id))
	var facilities: Array = port_scene.get("facilities", [])
	if facilities.is_empty():
		city_nav_panel.visible = false
		return
	city_nav_panel.visible = true
	city_nav_label.text = "▸ 当前：%s · 可前往" % scene_title.text
	var hub_btn := Button.new()
	hub_btn.text = "🏠 回城关"
	hub_btn.theme_type_variation = "ActionButton"
	hub_btn.custom_minimum_size = Vector2(128, 44)
	hub_btn.pressed.connect(func():
		scene_requested.emit(GameManager.get_port_scene_id(port_id))
	)
	city_nav_flow.add_child(hub_btn)
	for fac in facilities:
		if not GameManager.facility_available(fac):
			continue
		var target: String = GameManager.resolve_facility_scene(fac, port_id)
		if target == sid:
			continue
		var nav_btn := Button.new()
		nav_btn.text = fac.get("title", "地点")
		nav_btn.theme_type_variation = "ChoiceButton"
		nav_btn.custom_minimum_size = Vector2(112, 44)
		nav_btn.pressed.connect(func():
			scene_requested.emit(target)
		)
		city_nav_flow.add_child(nav_btn)

func _hide_post_dialogue_ui() -> void:
	choices_label.visible = false
	interactive_label.visible = false
	city_nav_panel.visible = false

func _clear_containers() -> void:
	for child in interactive_container.get_children():
		child.queue_free()
	for child in choices_container.get_children():
		child.queue_free()

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	var btn = Button.new()
	btn.text = "【遇见人物】 " + fallback_name
	btn.theme_type_variation = "NPCButton"
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(func(): show_npc_requested.emit(npc_id, fallback_name))
	choices_container.add_child(btn)

func _investigation_available(inv: Dictionary) -> bool:
	var once_flag: String = inv.get("once_flag", "")
	if once_flag != "" and GameState.has_story_flag(once_flag):
		return false
	var req: String = inv.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = inv.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	var req_item: String = inv.get("requires_item", "")
	if req_item != "" and not GameState.has_item_flag(req_item):
		return false
	return true

func _choice_available(choice: Dictionary) -> bool:
	var req: String = choice.get("requires_story_flag", "")
	if req != "" and not GameState.has_story_flag(req):
		return false
	var unless: String = choice.get("unless_story_flag", "")
	if unless != "" and GameState.has_story_flag(unless):
		return false
	var req_item: String = choice.get("requires_item", "")
	if req_item != "" and not GameState.has_item_flag(req_item):
		return false
	return true

func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	if GameManager.input_locked:
		return
	_set_interaction_locked(true)
	var msg = inv_data.get("text", "")
	if msg != "":
		var beat := DialogueParser.beat_from_text(msg)
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not is_instance_valid(self):
			return
	var once_flag: String = inv_data.get("once_flag", "")
	if once_flag != "":
		GameState.set_story_flag(once_flag)
	apply_effects(inv_data.get("effects", {}))

	var next_sc = inv_data.get("next", "")
	if next_sc == "last_port":
		next_sc = GameManager.get_port_scene_id(GameState.last_port)
	if next_sc != "":
		_set_interaction_locked(false)
		scene_requested.emit(next_sc)
	else:
		btn.disabled = true
		_set_interaction_locked(false)

func show_choices(choices: Array) -> void:
	var added := 0
	for choice in choices:
		if not _choice_available(choice):
			continue
		if added == 0:
			choices_label.visible = true
		var btn = Button.new()
		btn.text = choice.get("label", "继续")
		_style_choice_button(btn)
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_container.add_child(btn)
		added += 1
	if added == 0:
		choices_label.visible = false

# ======== 特殊业务核心分发 ========

func _on_choice_pressed(choice_data: Dictionary) -> void:
	if GameManager.input_locked:
		return
	_set_interaction_locked(true)
	if choice_data.has("random_roll"):
		await _resolve_random_roll_choice(choice_data)
		_set_interaction_locked(false)
		return
	apply_effects(choice_data.get("effects", {}))
	if choice_data.has("narration") and choice_data.get("narration", "") != "":
		var beat := DialogueParser.beat_from_text(choice_data.get("narration", ""))
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not is_instance_valid(self):
			return

	if choice_data.has("special_action"):
		_handle_special_action(choice_data.get("special_action"))
		_set_interaction_locked(false)
		return

	var next_scene = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameManager.get_port_scene_id(GameState.last_port)
	if next_scene != "":
		_set_interaction_locked(false)
		scene_requested.emit(next_scene)
	else:
		_set_interaction_locked(false)

func _handle_special_action(action: String) -> void:
	if action == "sail_world_map":
		scene_requested.emit("world_map")
		return
	if action == "bribe_customs":
		var res = GameState.customs_inspection()
		message_logged.emit(res["msg"] + "\n\n")
		status_updated.emit()
		return
	var res = GameState.handle_special_action(action)
	message_logged.emit(res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()

func apply_effects(effects: Dictionary) -> void:
	GameState.apply_effects(effects)
	status_updated.emit()

func _resolve_random_roll_choice(choice_data: Dictionary) -> void:
	var roll_cfg: Dictionary = choice_data.get("random_roll", {})
	var chance: float = float(roll_cfg.get("chance", 0.1))
	apply_effects(choice_data.get("effects", {}))
	var success := randf() < chance
	var branch_key := "success" if success else "fail"
	var branch: Dictionary = roll_cfg.get(branch_key, {})
	apply_effects(branch.get("effects", {}))
	var narr: String = branch.get("narration", "")
	if narr == "":
		narr = choice_data.get("narration", "")
	if narr != "":
		var beat := DialogueParser.beat_from_text(narr)
		dialogue_box.show_single_beat(beat)
		await dialogue_box.sequence_finished
		if not is_instance_valid(self):
			return
	var next_scene: String = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameManager.get_port_scene_id(GameState.last_port)
	if next_scene != "":
		scene_requested.emit(next_scene)

func _set_interaction_locked(locked: bool) -> void:
	GameManager.set_input_locked(locked)
	for container in [interactive_container, choices_container]:
		for child in container.get_children():
			if child is BaseButton:
				child.disabled = locked
	for child in city_nav_flow.get_children():
		if child is BaseButton:
			child.disabled = locked

func _on_set_sail_pressed(set_sail_btn: Button) -> void:
	if GameManager.input_locked:
		return
	var res = GameState.customs_inspection()
	message_logged.emit(res["msg"] + "\n\n")
	status_updated.emit()
	if not res.get("passed", false):
		return
	if res.get("was_smuggling", false):
		set_sail_btn.text = "正在强行出港..."
		_set_interaction_locked(true)
		get_tree().create_timer(2.5, false).timeout.connect(func():
			if not is_instance_valid(self):
				return
			_set_interaction_locked(false)
			scene_requested.emit("world_map")
		)
		return
	scene_requested.emit("world_map")

func _setup_tavern_rumors() -> void:
	var rumor = TradeEventGenerator.get_random_rumor()
	if rumor.is_empty():
		return
	interactive_label.visible = true
	_add_rumor_btn(rumor, 1, "★ 小道消息 (💰 20)")
	_add_rumor_btn(rumor, 2, "★★ 酒馆传言 (💰 50)")
	_add_rumor_btn(rumor, 3, "★★★ 商人情报 (💰 120)")

func _add_rumor_btn(rumor: Dictionary, tier: int, label: String) -> void:
	var btn = Button.new()
	btn.text = label
	_style_action_button(btn)
	btn.pressed.connect(_on_rumor_pressed.bind(rumor, tier, btn))
	btn.add_to_group("rumor_buttons")
	interactive_container.add_child(btn)

func _on_rumor_pressed(rumor: Dictionary, tier: int, btn: Button) -> void:
	if GameManager.input_locked:
		return
	var prices := [20, 50, 120]
	var cost: int = prices[tier - 1]
	if LedgerSystem.get_balance() < cost:
		message_logged.emit("【酒馆】你摸遍口袋也凑不出 %d 钱。\n\n" % cost)
		return
	LedgerSystem.apply({"amount": -cost, "source": "gameplay", "reason": "tavern_rumor", "actor": "FacilityController"})
	rumor["purchased"] = true
	get_tree().call_group("rumor_buttons", "set_disabled", true)
	var narration := _build_rumor_narration(rumor, tier)
	var beat = DialogueParser.beat_from_text(narration)
	dialogue_box.show_single_beat(beat)
	status_updated.emit()

func _build_rumor_narration(rumor: Dictionary, tier: int) -> String:
	var days_left: int = rumor.get("days_left", 7)
	match tier:
		1:
			return "喝醉的水手凑过来低声说：「听说最近某个方向的港口有点不寻常……要留心。」"
		2:
			var days_low: int = days_left - 2
			var days_high: int = days_left + 3
			return "老水手压低声音：「南边某港，大约 %d 到 %d 天内会有变故。你懂的。」" % [maxi(1, days_low), days_high]
		3:
			var port_name: String = rumor.get("port_name", "某港")
			var days_low: int = days_left - 1
			var days_high: int = days_left + 2
			return "商人凑近低声道：「%s那边，听说大约 %d 到 %d 天内会有大事，你自己掂量。」" % [port_name, maxi(1, days_low), days_high]
		_:
			return ""