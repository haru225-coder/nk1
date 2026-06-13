extends Control

@onready var background: TextureRect = $Background
@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var status_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var message_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel

@onready var title_mode: Control = $HBoxContainer/CenterArea/TitleMode
@onready var main_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/MainTitle
@onready var sub_title: Label = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/SubTitle
@onready var start_button: Button = $HBoxContainer/CenterArea/TitleMode/VBoxContainer/StartButton

@onready var investigation_mode: PanelContainer = $HBoxContainer/CenterArea/InvestigationMode
@onready var scene_title: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/BodyText
@onready var interactive_container: HFlowContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesLabel

@onready var port_mode: Control = $HBoxContainer/CenterArea/PortMode
@onready var left_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/LeftFacilities
@onready var right_facilities: VBoxContainer = $HBoxContainer/CenterArea/PortMode/RightFacilities
@onready var port_title: Label = $HBoxContainer/CenterArea/PortMode/PortTitle

@onready var npc_mode: Control = $HBoxContainer/CenterArea/NPCMode
@onready var npc_name_lbl: Label = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCName
@onready var npc_dialog_lbl: RichTextLabel = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCDialog
@onready var npc_actions: VBoxContainer = $HBoxContainer/CenterArea/NPCMode/HBox/DialogPanel/NPCActions
@onready var npc_portrait: TextureRect = $HBoxContainer/CenterArea/NPCMode/HBox/PortraitRect

var current_scene_id: String = ""
var items_investigated: int = 0
var total_items_to_investigate: int = 0
var title_button_connected: bool = false

func _ready() -> void:
	message_label.text = ""
	update_status_panel()
	call_deferred("start_game")

func _add_npc_button(npc_id: String, fallback_name: String) -> void:
	var btn = Button.new()
	btn.text = "【遇见人物】 " + fallback_name
	btn.pressed.connect(func(): _show_npc_mode(npc_id, fallback_name))
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.4, 0.6, 1.0)
	btn.add_theme_stylebox_override("normal", sb)
	choices_container.add_child(btn)

func _show_npc_mode(npc_id: String, fallback_name: String) -> void:
	investigation_mode.visible = false
	npc_mode.visible = true
	
	var npc_data = {}
	var npcs = GameManager.npcs_data.get("npcs", [])
	for n in npcs:
		if n.get("id") == npc_id:
			npc_data = n
			break
			
	var n_name = npc_data.get("name", fallback_name)
	npc_name_lbl.text = n_name
	npc_dialog_lbl.text = npc_data.get("function", "（这人看起来有些眼熟，但什么也没说...）")
	
	# Load Portrait
	var tex_path = "res://assets/sprite_" + npc_id.replace("pilot_", "").replace("merchant_", "") + ".png"
	if FileAccess.file_exists(tex_path):
		var img = Image.load_from_file(tex_path)
		if img: npc_portrait.texture = ImageTexture.create_from_image(img)
	else:
		npc_portrait.texture = null
		
	# Clear previous actions
	for child in npc_actions.get_children(): child.queue_free()
	
	# Action: Gather Intel
	var intel_btn = Button.new()
	intel_btn.text = "打听情报"
	intel_btn.pressed.connect(func():
		var goods = GameManager.goods_data.get("goods", [])
		if goods.size() > 0:
			var random_g = goods[randi() % goods.size()]
			npc_dialog_lbl.text = n_name + " 压低声音说：“听说最近 %s 的买卖很赚，你要不要试试？”" % random_g.get("name", "这行")
	)
	npc_actions.add_child(intel_btn)
	
	# Action: Bribe (Only for Yamen official)
	if npc_id == "customs_official":
		var bribe_btn = Button.new()
		bribe_btn.text = "塞钱买通 (50钱)"
		bribe_btn.pressed.connect(func():
			if GameState.cargo.get("金钱", 0) >= 50:
				GameState.cargo["金钱"] -= 50
				GameState.has_customs_permit = true
				update_status_panel()
				npc_dialog_lbl.text = n_name + " 颠了颠手里的碎银：“算你懂事。文牒拿好，路上小心。”"
			else:
				npc_dialog_lbl.text = n_name + " 满脸鄙夷：“就这点钱也想打通关节？滚滚滚！”"
		)
		npc_actions.add_child(bribe_btn)
		
	var leave_btn = Button.new()
	leave_btn.text = "离开"
	leave_btn.pressed.connect(func():
		npc_mode.visible = false
		investigation_mode.visible = true
	)
	npc_actions.add_child(leave_btn)

func start_game() -> void:
	if GameState.has_flag("return_to_port"):
		GameState.flags.erase("return_to_port")
		load_scene(GameState.last_port)
	else:
		var start_id = GameManager.scenes_data.get("start_scene", "cg_title")
		load_scene(start_id)

func update_status_panel() -> void:
	var cargo_str = ""
	for key in GameState.cargo.keys():
		cargo_str += key + " x" + str(GameState.cargo[key]) + "\n"
	if cargo_str == "": cargo_str = "空\n"
		
	var t = "金钱：%d\n名声：%d\n\n[走私与市舶]\n蒲氏关注度：%d\n市舶司货引：%s\n\n[船舱货物]\n%s" % [
		GameState.money,
		GameState.fame,
		GameState.pu_attention,
		"【有】合法" if GameState.has_customs_permit else "【无】黑市",
		cargo_str
	]
	status_label.text = t

func load_scene(scene_id: String) -> void:
	current_scene_id = scene_id
	
	# === 动态场景拦截 (动态市场、动态衙门) ===
	if scene_id.ends_with("_market") or scene_id.ends_with("_yamen") or scene_id.ends_with("_shipyard") or scene_id.ends_with("_tavern"):
		_setup_dynamic_scene(scene_id)
		return
		
	var scene_data = GameManager.get_scene_by_id(scene_id)
	
	if scene_data.is_empty():
		# Fallback to generic scenes if local ones are missing
		for suffix in ["_guild", "_residence", "_inn", "_exam"]:
			if scene_id.ends_with(suffix):
				var generic_id = "city" + suffix
				scene_data = GameManager.get_scene_by_id(generic_id)
				break
				
	if scene_data.is_empty():
		_setup_missing_scene(scene_id)
		return
		
	# Load visual assets (Background)
	var type = scene_data.get("type", "scene")
	var loc = scene_data.get("location", "")
	var bg_path = "res://assets/bg_sea_route.jpg" # Default
	
	if type == "title":
		bg_path = "res://assets/bg_world_map.png"
	elif loc == "xinghua_harbor":
		bg_path = "res://assets/bg_xinghua_wine_shed.jpg"
	elif loc == "xinghua":
		bg_path = "res://assets/bg_xinghua_study.jpg"
	elif loc == "quanzhou":
		bg_path = "res://assets/bg_quanzhou_harbor.jpg"
	elif loc == "hakata":
		bg_path = "res://assets/bg_arab_mosque.jpg"
	elif loc == "ryukyu":
		bg_path = "res://assets/bg_reef_bay.jpg"
		
	var tex = load(bg_path) as Texture2D
	if tex:
		background.texture = tex
	else:
		if FileAccess.file_exists(bg_path):
			var img = Image.load_from_file(bg_path)
			if img != null: background.texture = ImageTexture.create_from_image(img)
	
	if type == "title":
		_setup_title_mode(scene_data)
	elif type == "port":
		GameState.last_port = scene_id
		_setup_port_mode(scene_data)
	else:
		_setup_investigation_mode(scene_data)

func _setup_missing_scene(scene_id: String) -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	investigation_mode.visible = true
	
	for child in interactive_container.get_children(): child.queue_free()
	for child in choices_container.get_children(): child.queue_free()
	choices_label.visible = false
	
	scene_title.text = "区域施工中..."
	body_text.text = "该区域（" + scene_id + "）尚未实装，请耐心等待后续版本更新。"
	
	var base_loc = GameState.last_port
	_add_leave_button(base_loc)

func _setup_dynamic_scene(scene_id: String) -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	investigation_mode.visible = true
	
	for child in interactive_container.get_children(): child.queue_free()
	for child in choices_container.get_children(): child.queue_free()
	choices_label.visible = false
	npc_mode.visible = false
	
	var base_loc = scene_id
	for suffix in ["_market", "_tavern", "_yamen", "_shipyard"]:
		if base_loc.ends_with(suffix):
			base_loc = base_loc.replace(suffix, "")
			break
	
	if scene_id.ends_with("_market"):
		scene_title.text = "市场牙行"
		body_text.text = "蕃坊牙行里挤着各色商人，没有人说官话，只用手势、算筹和一把碎银落地就要捡的速度说话。"
		
		var goods_list = GameManager.goods_data.get("goods", [])
		var added = 0
		for g in goods_list:
			if g.get("category") == "货物":
				var price = g.get("base_value", 20)
				# 稍微随机一点价格波动
				var fluctuate = price + (price % 5) 
				_add_buy_button(g.get("name"), fluctuate)
				added += 1
				if added >= 4: break # 最多显示4个商品
				
		_add_sell_all_button()
		_add_leave_button(base_loc)

	elif scene_id.ends_with("_tavern"):
		scene_title.text = "酒馆"
		body_text.text = "这里充斥着劣质酒水的味道和水手们的大声喧哗。"
		if scene_id.begins_with("quanzhou"):
			_add_npc_button("merchant_lin", "林阿舶")
		elif scene_id.begins_with("ryukyu"):
			_add_npc_button("pilot_ana", "阿那")
			
		# Load the normal interior cards for tavern
		var s_data = GameManager.get_scene_by_id(scene_id)
		if s_data.is_empty():
			s_data = GameManager.get_scene_by_id("city_tavern")
		if not s_data.is_empty():
			for inv in s_data.get("investigations", []):
				var ibtn = Button.new()
				ibtn.text = "★ " + inv.get("label", "互动")
				ibtn.pressed.connect(_on_investigate_pressed.bind(inv, ibtn))
				interactive_container.add_child(ibtn)
				
		_add_leave_button(base_loc)

	elif scene_id.ends_with("_yamen"):
		scene_title.text = "市舶司 / 衙门"
		body_text.text = "官府重地。几名差役正在慵懒地打瞌睡。"
		_add_npc_button("customs_official", "市舶司小吏")
		_add_leave_button(base_loc)
		
		var btn1 = Button.new()
		btn1.text = "【正规】市舶司验引 (安全放行)"
		btn1.pressed.connect(func():
			GameState.has_customs_permit = true
			message_label.text = "【市舶司】你办理了正规货引，合法离港。\n\n" + message_label.text
			update_status_panel()
		)
		choices_container.add_child(btn1)
		
		var btn2 = Button.new()
		btn2.text = "【走私】塞钱走暗关免验 (贿赂 50 钱)"
		btn2.pressed.connect(func():
			var res = GameState.customs_inspection()
			message_label.text = res["msg"] + "\n\n" + message_label.text
			update_status_panel()
		)
		choices_container.add_child(btn2)
		choices_label.visible = true
		
		_add_leave_button(base_loc)

	elif scene_id.ends_with("_shipyard"):
		scene_title.text = "船屋"
		body_text.text = "船坞里散发着桐油与海水的味道。这是修补海船、补充水手的地方。"
		
		var recruit_btn = Button.new()
		recruit_btn.text = "招募水手 (10钱/人)"
		recruit_btn.pressed.connect(func():
			var space = GameState.max_crew - GameState.crew_count
			if space > 0 and GameState.money >= 10:
				var cost = min(space * 10, GameState.money - (GameState.money % 10))
				var amount = cost / 10
				GameState.money -= cost
				GameState.crew_count += amount
				message_label.text = "招募了 %d 名水手！\n\n" % amount + message_label.text
				update_status_panel()
			else:
				message_label.text = "无法招募！钱不够或船只已满员。\n\n" + message_label.text
		)
		choices_container.add_child(recruit_btn)
		
		var supply_btn = Button.new()
		supply_btn.text = "补充水粮 (20钱/满载)"
		supply_btn.pressed.connect(func():
			if GameState.money >= 20:
				GameState.money -= 20
				GameState.food = GameState.max_food
				GameState.water = GameState.max_water
				message_label.text = "水粮已全部补满！\n\n" + message_label.text
				update_status_panel()
			else:
				message_label.text = "【补充失败】金钱不足 20！\n\n" + message_label.text
		)
		choices_container.add_child(supply_btn)
		
		var btn = Button.new()
		btn.text = "★ 扬帆起航 (进入航海模式)"
		btn.pressed.connect(func():
			message_label.text = "【大航海】扬帆起航！目前航海物理核心(WASD)尚未完全接入 Godot 界面，敬请期待！\n\n" + message_label.text
		)
		choices_container.add_child(btn)
		
		# Also load the normal interior cards for shipyard
		var s_data = GameManager.get_scene_by_id("city_shipyard")
		if not s_data.is_empty():
			for inv in s_data.get("investigations", []):
				var ibtn = Button.new()
				ibtn.text = "★ " + inv.get("label", "互动")
				ibtn.pressed.connect(_on_investigate_pressed.bind(inv, ibtn))
				interactive_container.add_child(ibtn)
		
		_add_leave_button(base_loc)

func _add_buy_button(item_name: String, price: int) -> void:
	var btn = Button.new()
	btn.text = "购入：%s (%d钱)" % [item_name, price]
	btn.pressed.connect(func():
		if GameState.buy_goods(item_name, 1, price):
			message_label.text = "成功买入 1 份 " + item_name + "\n\n" + message_label.text
			update_status_panel()
		else:
			message_label.text = "【交易失败】囊中羞涩，金钱不足！\n\n" + message_label.text
	)
	interactive_container.add_child(btn)

func _add_sell_all_button() -> void:
	var btn = Button.new()
	btn.text = "抛售所有货物"
	btn.pressed.connect(func():
		if GameState.cargo.is_empty():
			message_label.text = "船舱空空如也，无货可卖。\n\n" + message_label.text
			return
			
		var total_earned = 0
		for key in GameState.cargo.keys().duplicate():
			var amt = GameState.cargo[key]
			var sell_price = 10
			
			var goods_list = GameManager.goods_data.get("goods", [])
			for g in goods_list:
				if g.get("name") == key:
					var base = g.get("base_value", 20)
					var origin = g.get("origin", "")
					var cur_port = GameState.last_port
					var is_local = false
					if cur_port.begins_with("quanzhou") and ("泉州" in origin or "福建" in origin): is_local = true
					elif cur_port.begins_with("xinghua") and ("兴化" in origin or "福建" in origin): is_local = true
					
					if is_local:
						sell_price = int(base * 1.1)
					else:
						sell_price = int(base * 2.5) # 暴利
					break
			
			GameState.sell_goods(key, amt, sell_price)
			total_earned += amt * sell_price
			
		message_label.text = "全部抛售，获利 %d 钱！\n\n" % total_earned + message_label.text
		update_status_panel()
	)
	choices_container.add_child(btn)
	choices_label.visible = true

func _add_leave_button(port_id: String) -> void:
	var btn = Button.new()
	btn.text = "离开"
	btn.pressed.connect(func(): load_scene(port_id))
	choices_container.add_child(btn)

func _setup_title_mode(scene_data: Dictionary) -> void:
	left_panel.visible = false
	investigation_mode.visible = false
	port_mode.visible = false
	title_mode.visible = true
	
	main_title.text = scene_data.get("cg_title", "南海立志传")
	sub_title.text = scene_data.get("cg_sub", "")
	
	if title_button_connected:
		var conns = start_button.pressed.get_connections()
		for c in conns:
			start_button.pressed.disconnect(c.callable)
			
	var choices = scene_data.get("choices", [])
	var next_scene = "prologue_tabletop"
	if choices.size() > 0:
		start_button.text = choices[0].get("label", "开始旅程")
		next_scene = choices[0].get("next", "prologue_tabletop")
		
	start_button.pressed.connect(_on_start_game_pressed.bind(next_scene))
	title_button_connected = true

func _on_start_game_pressed(next_scene: String) -> void:
	load_scene(next_scene)

func _setup_port_mode(scene_data: Dictionary) -> void:
	left_panel.visible = true
	title_mode.visible = false
	investigation_mode.visible = false
	port_mode.visible = true
	port_title.text = scene_data.get("title", "未知港口")
	
	for child in left_facilities.get_children(): child.queue_free()
	for child in right_facilities.get_children(): child.queue_free()
		
	var facilities = scene_data.get("facilities", [])
	for i in range(facilities.size()):
		var fac = facilities[i]
		
		# Create a container for the card
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 90)
		
		# Setup stylebox for glass/card effect
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.3, 0.5)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		style.corner_radius_bottom_left = 6
		card.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		card.add_child(hbox)
		
		# Left: Icon
		var icon_id = fac.get("id", "").replace("city_", "")
		var icon_path = "res://assets/icon_" + icon_id + ".png"
		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		var icon_tex = load(icon_path) as Texture2D
		if not icon_tex and FileAccess.file_exists(icon_path):
			var img = Image.load_from_file(icon_path)
			if img: icon_tex = ImageTexture.create_from_image(img)
		if icon_tex:
			tex_rect.texture = icon_tex
		
		var icon_margin = MarginContainer.new()
		icon_margin.add_theme_constant_override("margin_left", 5)
		icon_margin.add_theme_constant_override("margin_right", 5)
		icon_margin.add_child(tex_rect)
		hbox.add_child(icon_margin)
		
		# Right: Title & Subtitle
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(vbox)
		
		var title_lbl = Label.new()
		title_lbl.text = fac.get("title", "未命名设施")
		title_lbl.add_theme_font_size_override("font_size", 22)
		vbox.add_child(title_lbl)
		
		var sub_lbl = Label.new()
		sub_lbl.text = fac.get("subtitle", "")
		sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		sub_lbl.add_theme_font_size_override("font_size", 14)
		vbox.add_child(sub_lbl)
		
		# Invisible button to handle clicks
		var btn = Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_facility_pressed.bind(fac))
		
		btn.mouse_entered.connect(func(): style.bg_color = Color(0.25, 0.25, 0.3, 0.8))
		btn.mouse_exited.connect(func(): style.bg_color = Color(0.1, 0.1, 0.1, 0.6))
		
		card.add_child(btn)
		
		if i % 2 == 0: left_facilities.add_child(card)
		else: right_facilities.add_child(card)

	# ==========================================
	# 添加核心出海按钮 (防查漏补缺)
	# ==========================================
	var set_sail_btn = Button.new()
	set_sail_btn.text = "🚢 升帆出海 (World Map)"
	set_sail_btn.custom_minimum_size = Vector2(250, 80)
	set_sail_btn.add_theme_font_size_override("font_size", 24)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.8, 0.2, 0.2, 1.0) # 显眼的红色
	set_sail_btn.add_theme_stylebox_override("normal", sb)
	
	set_sail_btn.pressed.connect(func():
		var res = GameState.customs_inspection()
		message_label.text = res["msg"] + "\n\n" + message_label.text
		update_status_panel()
		
		if res["passed"]:
			if not GameState.has_customs_permit:
				set_sail_btn.text = "正在强行出港..."
				set_sail_btn.disabled = true
				await get_tree().create_timer(2.5).timeout
				
			GameState.has_customs_permit = false
			get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
	)
	right_facilities.add_child(set_sail_btn)

func _on_facility_pressed(fac: Dictionary) -> void:
	var target_scene = fac.get("id", "")
	if target_scene.begins_with("city_"):
		var suffix = target_scene.replace("city_", "")
		target_scene = current_scene_id + "_" + suffix
	if target_scene != "":
		load_scene(target_scene)

func _setup_investigation_mode(scene_data: Dictionary) -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	investigation_mode.visible = true
	
	scene_title.text = scene_data.get("title", "未命名地点")
	body_text.text = scene_data.get("body", "")
	
	for child in interactive_container.get_children(): child.queue_free()
	for child in choices_container.get_children(): child.queue_free()
		
	var investigations = scene_data.get("investigations", [])
	
	if investigations.size() > 0:
		for inv in investigations:
			var btn = Button.new()
			btn.text = "★ " + inv.get("label", "互动")
			btn.pressed.connect(_on_investigate_pressed.bind(inv, btn))
			interactive_container.add_child(btn)
			
	# Always show choices
	show_choices(scene_data.get("choices", []))

func _on_investigate_pressed(inv_data: Dictionary, btn: Button) -> void:
	var msg = inv_data.get("text", "")
	if msg != "":
		body_text.text += "\n\n" + msg
	apply_effects(inv_data.get("effects", {}))
	
	var next_sc = inv_data.get("next", "")
	if next_sc == "last_port":
		next_sc = GameState.last_port
	if next_sc != "":
		load_scene(next_sc)
	else:
		btn.disabled = true

func show_choices(choices: Array) -> void:
	choices_label.visible = true
	for choice in choices:
		var btn = Button.new()
		btn.text = choice.get("label", "继续")
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_container.add_child(btn)

func _on_choice_pressed(choice_data: Dictionary) -> void:
	apply_effects(choice_data.get("effects", {}))
	var next_scene = choice_data.get("next", "")
	if next_scene == "last_port":
		next_scene = GameState.last_port
	if next_scene != "": load_scene(next_scene)

func apply_effects(effects: Dictionary) -> void:
	for key in effects.keys():
		var val = effects[key]
		if key == "money": GameState.money += val
		elif key == "fame": GameState.fame += val
		# Tendencies logic removed for v0.5.3 integration
	update_status_panel()
