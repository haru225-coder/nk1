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

# ======= 常规 Investigation ========

func setup_investigation(scene_data: Dictionary, scene_id: String) -> void:
	scene_title.text = scene_data.get("title", "未命名地点")
	body_text.text = scene_data.get("body", "")
	_clear_containers()
		
	var investigations = scene_data.get("investigations", [])
	if investigations.size() > 0:
		for inv in investigations:
			var btn = Button.new()
			btn.text = "★ " + inv.get("label", "互动")
			btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
			interactive_container.add_child(btn)
			
	# 如果是市场，自动追加动态商品选项
	if scene_data.get("id", "") == "city_market":
		_setup_market_goods()
		
	# 检查是否存在 npc_encounter 字段
	if scene_data.has("npc_encounter"):
		var npc_id = scene_data.get("npc_encounter")
		var fallback_name = "神秘人物"
		if "lin" in npc_id: fallback_name = "林阿舶"
		elif "ana" in npc_id: fallback_name = "阿那"
		elif "official" in npc_id: fallback_name = "市舶司小吏"
		_add_npc_button(npc_id, fallback_name)
		
	show_choices(scene_data.get("choices", []))

# ======= 缺失场景 ========

func setup_missing(scene_id: String) -> void:
	_clear_containers()
	choices_label.visible = false
	
	scene_title.text = "区域施工中..."
	body_text.text = "该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"
	
	var btn = Button.new()
	btn.text = "离开"
	btn.pressed.connect(func(): scene_requested.emit(GameState.last_port))
	choices_container.add_child(btn)

# ======== 市场货品生成 ========

func _setup_market_goods() -> void:
	var market_items = GameState.get_market_prices(GameState.last_port)
	var added = 0
	for item in market_items:
		var item_name = item["name"]
		var price = item["price"]
		var btn = Button.new()
		btn.text = "购入：%s (%d钱)" % [item_name, price]
		btn.pressed.connect(_on_buy_pressed.bind(item_name, price))
		interactive_container.add_child(btn)
		
		added += 1
		if added >= 4: break
		
	var sell_btn = Button.new()
	sell_btn.text = "抛售所有货物"
	sell_btn.pressed.connect(_on_sell_all_pressed)
	choices_container.add_child(sell_btn)
	choices_label.visible = true

func _on_buy_pressed(item_name: String, price: int) -> void:
	if GameState.buy_goods(item_name, 1, price):
		message_logged.emit("成功买入 1 份 " + item_name + "\n\n")
		status_updated.emit()
	else:
		message_logged.emit("【交易失败】囊中羞涩，金钱不足！\n\n")

func _on_sell_all_pressed() -> void:
	var res = GameState.sell_all_cargo(GameState.last_port)
	message_logged.emit(res["msg"] + "\n\n")
	if res["success"]:
		status_updated.emit()

# ======== 辅助方法 ========

func _clear_containers() -> void:
	for child in interactive_container.get_children(): child.queue_free()
	for child in choices_container.get_children(): child.queue_free()

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	var btn = Button.new()
	btn.text = "【遇见人物】 " + fallback_name
	btn.pressed.connect(func(): show_npc_requested.emit(npc_id, fallback_name))
	btn.theme_type_variation = "NPCButton"
	choices_container.add_child(btn)

func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	var msg = inv_data.get("text", "")
	if msg != "":
		body_text.text += "\n\n" + msg
	apply_effects(inv_data.get("effects", {}))
	
	var next_sc = inv_data.get("next", "")
	if next_sc == "last_port":
		next_sc = GameState.last_port
	if next_sc != "":
		scene_requested.emit(next_sc)
	else:
		btn.disabled = true

func show_choices(choices: Array) -> void:
	choices_label.visible = true
	for choice in choices:
		var btn = Button.new()
		btn.text = choice.get("label", "继续")
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_container.add_child(btn)

# ======== 特殊业务核心分发 ========

func _on_choice_pressed(choice_data: Dictionary) -> void:
	apply_effects(choice_data.get("effects", {}))
	
	# 处理特殊业务逻辑
	if choice_data.has("special_action"):
		_handle_special_action(choice_data.get("special_action"))
		return
		
	var next_scene = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameState.last_port
	if next_scene != "": scene_requested.emit(next_scene)

func _handle_special_action(action: String) -> void:
	if action == "bribe_customs":
		var res = GameState.customs_inspection()
		message_logged.emit(res["msg"] + "\n\n")
		status_updated.emit()
	else:
		var res = GameState.handle_special_action(action)
		message_logged.emit(res["msg"] + "\n\n")
		if res["success"]:
			status_updated.emit()
			if action == "sail_world_map":
				scene_requested.emit("world_map")

func apply_effects(effects: Dictionary) -> void:
	GameState.apply_effects(effects)
	status_updated.emit()
