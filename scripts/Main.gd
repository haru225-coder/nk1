extends Control

@onready var game_shell: GameShell = $GameShell
@onready var background: TextureRect = $GameShell/BackgroundLayer/Background
@onready var left_panel: PanelContainer = $GameShell/ContentLayer/HBoxContainer/LeftPanel
@onready var left_title: Label = $GameShell/ContentLayer/HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: RichTextLabel = $GameShell/ContentLayer/HBoxContainer/LeftPanel/MarginContainer/VBoxContainer/MessageLabel
@onready var status_bar: Control = $StatusLayer/PortStatusBar

@onready var title_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/TitleMode
@onready var investigation_mode: PanelContainer = $GameShell/ContentLayer/HBoxContainer/CenterArea/InvestigationMode
@onready var port_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/PortMode
@onready var npc_mode: Control = $GameShell/ContentLayer/HBoxContainer/CenterArea/NPCMode
@onready var dialogue_box: Control = $DialogueLayer/DialogueBox
@onready var cutscene_player: CutscenePlayer = $CutsceneLayer/CutscenePlayer

const MainMessagePanelScript := preload(ResourcePaths.SCRIPT_MAIN_MESSAGE_PANEL)
const MainScenePresenterScript := preload(ResourcePaths.SCRIPT_MAIN_SCENE_PRESENTER)
const PortIntroPlayerScript := preload(ResourcePaths.SCRIPT_PORT_INTRO_PLAYER)
const SceneRouterScript := preload(ResourcePaths.SCRIPT_SCENE_ROUTER)
const ModeStackScript := preload(ResourcePaths.SCRIPT_MODE_STACK)
const SceneBackgroundLoaderScript := preload(ResourcePaths.SCRIPT_SCENE_BACKGROUND_LOADER)
const StoryUnlockToastControllerScript := preload(ResourcePaths.SCRIPT_STORY_UNLOCK_TOAST_CONTROLLER)

var _message_panel: MainMessagePanel = MainMessagePanelScript.new()
var _scene_presenter: MainScenePresenter = MainScenePresenterScript.new()
var _port_intro_player: PortIntroPlayer = PortIntroPlayerScript.new()
var _scene_background_loader: SceneBackgroundLoader = SceneBackgroundLoaderScript.new()
var _story_unlock_toast: StoryUnlockToastController = null
var _pending_route_focus_action_id: String = ""

var current_scene_id: String = ""
var _market_ui: MarketScreenController = null

func _ready() -> void:
	# NK1-P6-POLISH: debug event spawning cleaned up — no hardcoded test events
	_message_panel.bind(left_panel, left_title, message_label, Callable(self, "_on_guide_link_clicked"))
	_scene_presenter.bind(title_mode, investigation_mode, port_mode, npc_mode, _message_panel, Callable(self, "_set_status_bar_visible"))
	_setup_story_unlock_toast()
	_set_status_bar_visible(false)
	game_shell.navigation_requested.connect(load_scene)
	game_shell.storybook_route_requested.connect(_on_storybook_route_requested)
	game_shell.log_requested.connect(_on_log_requested)
	game_shell.message_logged.connect(_prepend_event_log)
	if not GameState.story_unlock_notified.is_connected(_prepend_event_log):
		GameState.story_unlock_notified.connect(_prepend_event_log)
	if not GameState.story_unlock_notified.is_connected(_show_story_unlock_toast):
		GameState.story_unlock_notified.connect(_show_story_unlock_toast)
	
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
	_bind_calendar_scheduler()
	_bind_game_state_cutscene_request()

	SaveManager.save_completed.connect(_on_save_completed)
	SaveManager.load_completed.connect(_on_load_completed)
	
	call_deferred("start_game")

func _bind_calendar_scheduler() -> void:
	var scheduler = GameState.get("calendar_scheduler")
	if scheduler == null:
		return
	if scheduler.has_signal("scene_requested"):
		var scene_cb := Callable(self, "load_scene")
		if not scheduler.scene_requested.is_connected(scene_cb):
			scheduler.scene_requested.connect(scene_cb)
	var cs_player := _resolve_cutscene_player()
	if scheduler.has_method("bind_calendar"):
		scheduler.bind_calendar(GameState.calendar, GameState, {"cutscene_player": cs_player})
	if GameState.has_method("bind_ending_resolver"):
		GameState.bind_ending_resolver(cs_player)
	# P8-4: 月历 cutscene action 也可经壳层 ModeStack
	if scheduler.has_signal("cutscene_requested"):
		var cs_cb := Callable(self, "_on_scheduler_cutscene_requested")
		if not scheduler.cutscene_requested.is_connected(cs_cb):
			scheduler.cutscene_requested.connect(cs_cb)


func _resolve_cutscene_player() -> Node:
	var host = ModeStackScript.find_host(get_tree())
	if host != null and host.has_method("get_cutscene_player"):
		var shell_cs = host.call("get_cutscene_player")
		if shell_cs != null:
			return shell_cs
	return cutscene_player


func _on_scheduler_cutscene_requested(cutscene_id: String) -> void:
	if cutscene_id == "":
		return
	if ModeStackScript.play_cutscene(get_tree(), cutscene_id):
		return
	var cs := _resolve_cutscene_player()
	if cs != null and cs.has_method("play"):
		cs.call("play", cutscene_id)


func _bind_game_state_cutscene_request() -> void:
	# AppRoot 存在时由壳层唯一消费，避免 Main 与壳层重复播放。
	if ModeStackScript.find_host(get_tree()) != null:
		return
	var cb := Callable(self, "_on_game_state_cutscene_requested")
	if not GameState.cutscene_requested.is_connected(cb):
		GameState.cutscene_requested.connect(cb)


func _on_game_state_cutscene_requested(cutscene_id: String) -> void:
	_on_scheduler_cutscene_requested(cutscene_id)

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

func _prepend_event_log(msg: String) -> void:
	_message_panel.prepend_event_log(msg)


## P8: AppRoot / 航海壳写入同一消息栏（出海时 Main 可能被禁用，回港仍可见记录）
func append_shell_log(msg: String) -> void:
	_prepend_event_log(msg)

func _setup_story_unlock_toast() -> void:
	if _story_unlock_toast != null and is_instance_valid(_story_unlock_toast):
		return
	_story_unlock_toast = StoryUnlockToastControllerScript.new()
	_story_unlock_toast.name = "StoryUnlockToastController"
	_story_unlock_toast.bind_shell(game_shell)
	add_child(_story_unlock_toast)
	_story_unlock_toast._setup_story_unlock_toast()

func _show_story_unlock_toast(msg: String) -> void:
	_setup_story_unlock_toast()
	if _story_unlock_toast != null:
		_story_unlock_toast._show_story_unlock_toast(msg)

func _on_guide_link_clicked(meta: Variant) -> void:
	var target := str(meta)
	if target != "":
		load_scene(target)

func _on_storybook_route_requested(scene_id: String, focus_action_id: String) -> void:
	_pending_route_focus_action_id = focus_action_id
	load_scene(scene_id)

func load_scene(scene_id: String) -> void:
	var focus_action_id := _pending_route_focus_action_id
	_pending_route_focus_action_id = ""
	# preload 保证 headless 无 class cache 时也能解析
	var kind: String = SceneRouterScript.classify(scene_id)

	# 离开市场时清掉市场 overlay（进入市场本身由 market 分支处理）
	if kind != SceneRouterScript.KIND_MARKET:
		_close_market_ui()

	match kind:
		SceneRouterScript.KIND_WORLD_MAP:
			_route_world_map()
		SceneRouterScript.KIND_MARKET:
			_route_market(scene_id)
		_:
			_route_narrative(scene_id, focus_action_id)


func _close_market_ui() -> void:
	if _market_ui and is_instance_valid(_market_ui):
		_market_ui.queue_free()
	_market_ui = null


func _route_world_map() -> void:
	var sail_res = GameState.handle_special_action("sail_world_map")
	if sail_res.get("msg", "") != "":
		_prepend_event_log(sail_res["msg"] + "\n\n")
	if not sail_res.get("success", false):
		return
	SaveManager.set_current_scene_id("world_map")
	# P8: 优先 ModeStack（保留港内壳）；无 AppRoot 时回退 change_scene
	if not ModeStackScript.go_voyage(get_tree()):
		get_tree().change_scene_to_file(ResourcePaths.SCENE_WORLD_MAP)


func _route_market(scene_id: String) -> void:
	_close_market_ui()
	var market_ui = MarketScreenController.new()
	_market_ui = market_ui
	add_child(market_ui)
	market_ui.setup(SceneRouterScript.market_port_id(scene_id))
	market_ui.message_logged.connect(_prepend_event_log)
	market_ui.status_updated.connect(update_status_panel)
	market_ui.market_closed.connect(func(): _market_ui = null)


func _route_narrative(scene_id: String, focus_action_id: String) -> void:
	current_scene_id = scene_id
	SaveManager.set_current_scene_id(scene_id)

	var scene_data: Dictionary = SceneRouterScript.resolve_scene_data(scene_id)
	if scene_data.is_empty():
		_scene_presenter.present_missing(scene_id)
		update_status_panel()
		return

	_scene_background_loader.apply_background(background, scene_data)
	var type := str(scene_data.get("type", "investigation"))
	var mode_node := _scene_presenter.present_scene(scene_data, scene_id, focus_action_id)
	if type == "port":
		var cs_player := _resolve_cutscene_player()
		_port_intro_player.show_if_needed(scene_data, scene_id, cs_player, Callable(self, "_prepend_event_log"))
	game_shell.apply_scene(scene_id, scene_data, mode_node)
	update_status_panel()

func _on_log_requested() -> void:
	_message_panel.show_log(game_shell)
