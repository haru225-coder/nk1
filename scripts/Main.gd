extends Control

@onready var game_shell: GameShell = $GameShell
@onready var background: TextureRect = $GameShell/BackgroundLayer/Background
@onready var main_layout: HBoxContainer = $GameShell/ContentLayer/HBoxContainer
@onready var left_panel: PanelContainer = $GameShell/ContentLayer/HBoxContainer/LeftPanel
@onready var left_title: Label = $GameShell/ContentLayer/HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: RichTextLabel = $GameShell/ContentLayer/HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel
@onready var status_bar: Control = $StatusLayer/PortStatusBar

@onready var title_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/TitleMode

@onready var investigation_mode: PanelContainer = $GameShell/ContentLayer/HBoxContainer/CenterArea/InvestigationMode

@onready var port_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode

@onready var npc_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/NPCMode
@onready var dialogue_box: Control = $DialogueLayer/DialogueBox

const MAX_BG_CACHE_SIZE := 10
const MAX_LOG_LENGTH := 1000

var _bg_cache: Dictionary = {}
var _bg_cache_order: Array[String] = []
var _event_log: String = ""

var current_scene_id: String = ""
var _market_ui: MarketScreenController = null

func _ready() -> void:
	if OS.is_debug_build() and WorldEventTracker.get_active_events().size() == 0:
		WorldEventTracker.add_event(PirateAttackEvent.new("quanzhou", 3))
	
	left_panel.visible = false
	message_label.text = ""
	message_label.meta_clicked.connect(_on_guide_link_clicked)
	_set_status_bar_visible(false)
	game_shell.navigation_requested.connect(load_scene)
	game_shell.log_requested.connect(_on_log_requested)
	game_shell.message_logged.connect(_prepend_event_log)
	
	title_mode.scene_requested.connect(load_scene)
	
	npc_mode.status_updated.connect(update_status_panel)
	npc_mode.npc_finished.connect(func():
		npc_mode.visible = false
		investigation_mode.visible = true
	)
	
	port_mode.scene_requested.connect(load_scene)
	port_mode.status_updated.connect(update_status_panel)
	port_mode.message_logged.connect(_prepend_event_log)
	
	investigation_mode.scene_requested.connect(load_scene)
	investigation_mode.status_updated.connect(update_status_panel)
	investigation_mode.message_logged.connect(_prepend_event_log)
	investigation_mode.show_npc_requested.connect(func(npc_id, fallback_name):
		investigation_mode.visible = false
		npc_mode.visible = true
		npc_mode.setup(npc_id, fallback_name)
	)

	investigation_mode.bind_dialogue_box(dialogue_box)
	npc_mode.bind_dialogue_box(dialogue_box)
	if status_bar.has_signal("layout_changed"):
		status_bar.layout_changed.connect(_on_status_bar_layout_changed)

	SaveManager.save_completed.connect(_on_save_completed)
	SaveManager.load_completed.connect(_on_load_completed)
	
	call_deferred("start_game")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		SaveManager.quick_save()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		SaveManager.quick_load()
		get_viewport().set_input_as_handled()

func _on_save_completed(_slot: int, success: bool) -> void:
	if success:
		_prepend_event_log("【存档】进度已保存。\n")
	else:
		_prepend_event_log("【存档】保存失败！\n")

func _on_load_completed(_slot: int, success: bool, data: Dictionary) -> void:
	if success:
		load_scene(data.get("current_scene_id", "cg_title"))
		_prepend_event_log("【读档】进度已恢复。\n")
	else:
		_prepend_event_log("【读档】" + data.get("msg", "无存档。") + "\n")

func start_game() -> void:
	if GameState.has_flag("return_to_port"):
		GameState.clear_flag("return_to_port")
		load_scene(GameManager.get_port_scene_id(GameState.last_port))
	else:
		var start_id = GameManager.scenes_data.get("start_scene", "cg_title")
		load_scene(start_id)

func _set_status_bar_visible(show_bar: bool) -> void:
	status_bar.visible = show_bar
	_apply_status_bar_layout_offset()

func _on_status_bar_layout_changed(_height: float) -> void:
	_apply_status_bar_layout_offset()

func _apply_status_bar_layout_offset() -> void:
	var offset_top := 0.0
	if status_bar.visible and status_bar.has_method("get_layout_height"):
		offset_top = status_bar.get_layout_height()
	game_shell.set_status_bar_offset(offset_top)

func update_status_panel() -> void:
	if status_bar.visible and status_bar.has_method("refresh"):
		status_bar.refresh()
		_apply_status_bar_layout_offset()

func _touch_bg_cache(bg_path: String) -> void:
	var idx := _bg_cache_order.find(bg_path)
	if idx >= 0:
		_bg_cache_order.remove_at(idx)
	_bg_cache_order.append(bg_path)

func _prepend_event_log(msg: String) -> void:
	_event_log = msg + _event_log
	if _event_log.length() > MAX_LOG_LENGTH:
		_event_log = _event_log.substr(0, MAX_LOG_LENGTH)
	_refresh_message_panel()

func _on_guide_link_clicked(meta: Variant) -> void:
	var target := str(meta)
	if target != "":
		load_scene(target)

func load_scene(scene_id: String) -> void:
	if not scene_id.ends_with("_market"):
		if _market_ui and is_instance_valid(_market_ui):
			_market_ui.queue_free()
			_market_ui = null

	if scene_id == "world_map":
		var sail_res = GameState.handle_special_action("sail_world_map")
		if sail_res.get("msg", "") != "":
			_prepend_event_log(sail_res["msg"] + "\n\n")
		if not sail_res.get("success", false):
			return
		SaveManager.set_current_scene_id("world_map")
		get_tree().change_scene_to_file("res://scenes/WorldMap.tscn")
		return
		
	if scene_id.ends_with("_market"):
		if _market_ui and is_instance_valid(_market_ui):
			_market_ui.queue_free()
		var market_ui = MarketScreenController.new()
		_market_ui = market_ui
		add_child(market_ui)
		var port_to_open = GameState.last_port
		if port_to_open == "": port_to_open = scene_id.replace("_market", "")
		market_ui.setup(port_to_open)
		market_ui.message_logged.connect(_prepend_event_log)
		market_ui.status_updated.connect(update_status_panel)
		market_ui.market_closed.connect(func(): _market_ui = null)
		return
		
	current_scene_id = scene_id
	SaveManager.set_current_scene_id(scene_id)
	
	var scene_data = GameManager.get_scene_by_id(scene_id)
	
	if scene_data.is_empty():
		for suffix: String in ["_guild", "_residence", "_inn", "_exam", "_tavern", "_yamen", "_shipyard", "_temple"]:
			if scene_id.ends_with(suffix):
				var generic_id: String = "city" + suffix
				scene_data = GameManager.get_scene_by_id(generic_id)
				break
				
	if scene_data.is_empty():
		_setup_missing_scene(scene_id)
		return
		
	var bg_path: String = scene_data.get("bg", "res://assets/bg_sea_route_koei.png")
	if _bg_cache.has(bg_path):
		background.texture = _bg_cache[bg_path]
		_touch_bg_cache(bg_path)
	else:
		var tex := AssetPlaceholder.load_texture(bg_path, "bg")
		if tex:
			background.texture = tex
			_bg_cache[bg_path] = tex
			_bg_cache_order.append(bg_path)
			if _bg_cache_order.size() > MAX_BG_CACHE_SIZE:
				var evict: String = _bg_cache_order.pop_front()
				_bg_cache.erase(evict)

	var type = scene_data.get("type", "investigation")
	
	if type == "title":
		_set_status_bar_visible(false)
		left_panel.visible = false
		investigation_mode.visible = false
		npc_mode.visible = false
		port_mode.visible = false
		title_mode.visible = true
		title_mode.setup(scene_data)
	elif type == "port":
		GameState.last_port = scene_data.get("location", scene_id.replace("port_", ""))
		_set_status_bar_visible(true)
		left_panel.visible = false
		title_mode.visible = false
		investigation_mode.visible = false
		npc_mode.visible = false
		port_mode.visible = true
		port_mode.setup(scene_data, scene_id)
		_show_port_intro_if_needed(scene_data, scene_id)
		_set_port_guide(scene_data)
	else:
		_set_status_bar_visible(true)
		left_panel.visible = false
		title_mode.visible = false
		port_mode.visible = false
		npc_mode.visible = false
		investigation_mode.visible = true
		investigation_mode.setup_investigation(scene_data, scene_id)
		_set_investigation_guide(scene_data, scene_id)

	var mode_node: Node = investigation_mode
	if type == "title":
		mode_node = title_mode
	elif type == "port":
		mode_node = port_mode
	game_shell.apply_scene(scene_id, scene_data, mode_node)
	update_status_panel()

func _on_log_requested() -> void:
	game_shell.show_log(_event_log.strip_edges())

func _set_port_guide(scene_data: Dictionary) -> void:
	_guide_text = ""
	_refresh_message_panel()

func _set_investigation_guide(_scene_data: Dictionary, _scene_id: String) -> void:
	_guide_text = ""
	_refresh_message_panel()

var _guide_text: String = ""

func _refresh_message_panel() -> void:
	if not left_panel.visible:
		return
	var parts: PackedStringArray = PackedStringArray()
	if _guide_text != "":
		parts.append(_guide_text)
	if _event_log != "":
		if parts.size() > 0:
			parts.append("")
		parts.append(_event_log.strip_edges())
	message_label.text = "\n".join(parts)

func _show_port_intro_if_needed(scene_data: Dictionary, scene_id: String) -> void:
	var intro: String = scene_data.get("intro", "")
	if intro == "":
		return
	var flag := "intro_shown:" + scene_id
	if GameState.has_story_flag(flag):
		return
	GameState.set_story_flag(flag)
	_prepend_event_log("【抵达】%s\n\n" % intro)

func _setup_missing_scene(scene_id: String) -> void:
	_set_status_bar_visible(true)
	left_panel.visible = false
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	investigation_mode.setup_missing(scene_id)
	_guide_text = ""
	_refresh_message_panel()
	update_status_panel()