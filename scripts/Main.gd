extends Control

@onready var background: TextureRect = $Background
@onready var left_panel: PanelContainer = $HBoxContainer/LeftPanel
@onready var status_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/StatusLabel
@onready var message_label: RichTextLabel = $HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel

@onready var title_mode: Control = $HBoxContainer/CenterArea/TitleMode

@onready var investigation_mode: PanelContainer = $HBoxContainer/CenterArea/InvestigationMode
@onready var scene_title: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/SceneTitle
@onready var body_text: RichTextLabel = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/BodyText
@onready var interactive_container: HFlowContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/InteractiveContainer
@onready var choices_container: VBoxContainer = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesContainer
@onready var choices_label: Label = $HBoxContainer/CenterArea/InvestigationMode/MarginContainer/VBoxContainer/ChoicesLabel

@onready var port_mode: Control = $HBoxContainer/CenterArea/PortMode

@onready var npc_mode: Control = $HBoxContainer/CenterArea/NPCMode

var current_scene_id: String = ""

func _ready() -> void:
	GameManager.load_data()
	
	# Seed initial event for testing UI
	if WorldEventTracker.get_active_events().size() == 0:
		WorldEventTracker.add_event(PirateAttackEvent.new("quanzhou", 3))
	
	message_label.text = ""
	update_status_panel()
	
	# 第一刀：接通 TitleScreenController
	title_mode.scene_requested.connect(load_scene)
	
	# 第二刀：接通 NPCController
	npc_mode.status_updated.connect(update_status_panel)
	npc_mode.npc_finished.connect(func():
		npc_mode.visible = false
		investigation_mode.visible = true
	)
	
	# 第三刀：接通 PortScreenController
	port_mode.scene_requested.connect(load_scene)
	port_mode.status_updated.connect(update_status_panel)
	port_mode.message_logged.connect(func(msg):
		message_label.text = msg + message_label.text
	)
	
	# 第四刀：接通 FacilityController
	investigation_mode.scene_requested.connect(load_scene)
	investigation_mode.status_updated.connect(update_status_panel)
	investigation_mode.message_logged.connect(func(msg):
		message_label.text = msg + message_label.text
	)
	investigation_mode.show_npc_requested.connect(func(npc_id, fallback_name):
		investigation_mode.visible = false
		npc_mode.visible = true
		npc_mode.setup(npc_id, fallback_name)
	)
	
	call_deferred("start_game")

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
		LedgerSystem.get_balance(),
		GameState.fame,
		GameState.pu_attention,
		"【有】合法" if GameState.has_customs_permit else "【无】黑市",
		cargo_str
	]
	status_label.text = t

func load_scene(scene_id: String) -> void:
	if scene_id == "world_map":
		get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
		return
		
	if scene_id.ends_with("_market"):
		var market_ui = MarketScreenController.new()
		add_child(market_ui)
		var port_to_open = GameState.last_port
		if port_to_open == "": port_to_open = scene_id.replace("_market", "")
		market_ui.setup(port_to_open)
		market_ui.message_logged.connect(_on_message_logged)
		market_ui.status_updated.connect(_on_status_updated)
		return
		
	current_scene_id = scene_id
	
	var scene_data = GameManager.get_scene_by_id(scene_id)
	
	if scene_data.is_empty():
		# Fallback to generic scenes if local ones are missing
		for suffix in ["_guild", "_residence", "_inn", "_exam", "_market", "_tavern", "_yamen", "_shipyard"]:
			if scene_id.ends_with(suffix):
				var generic_id = "city" + suffix
				scene_data = GameManager.get_scene_by_id(generic_id)
				break
				
	if scene_data.is_empty():
		_setup_missing_scene(scene_id)
		return
		
	# Load visual assets (Background)
	var bg_path = scene_data.get("bg", "res://assets/bg_sea_route.jpg")
		
	var tex = load(bg_path) as Texture2D
	if tex:
		background.texture = tex
	else:
		if FileAccess.file_exists(bg_path):
			var img = Image.load_from_file(bg_path)
			if img != null: background.texture = ImageTexture.create_from_image(img)
	
	var type = scene_data.get("type", "investigation")
	
	if type == "title":
		left_panel.visible = false
		investigation_mode.visible = false
		npc_mode.visible = false
		port_mode.visible = false
		title_mode.visible = true
		title_mode.setup(scene_data)
	elif type == "port":
		GameState.last_port = scene_id
		left_panel.visible = true
		title_mode.visible = false
		investigation_mode.visible = false
		npc_mode.visible = false
		port_mode.visible = true
		port_mode.setup(scene_data, scene_id)
	else:
		left_panel.visible = true
		title_mode.visible = false
		port_mode.visible = false
		npc_mode.visible = false
		investigation_mode.visible = true
		investigation_mode.setup_investigation(scene_data, scene_id)

func _setup_missing_scene(scene_id: String) -> void:
	left_panel.visible = true
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	investigation_mode.setup_missing(scene_id)
