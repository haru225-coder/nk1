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
@onready var cutscene_player: CutscenePlayer = $CutsceneLayer/CutscenePlayer

const MAX_BG_CACHE_SIZE := 10
const MAX_LOG_LENGTH := 1000
const STORY_UNLOCK_TOAST_NAME := "StoryUnlockToast"
const STORY_UNLOCK_TOAST_WIDTH := 640.0
const STORY_UNLOCK_TOAST_HEIGHT := 96.0
const STORY_UNLOCK_TOAST_TOP := 72.0
const STORY_UNLOCK_TOAST_HOLD := 2.0
const STORY_TABLE_REGISTRY := preload(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY)

var _bg_cache: Dictionary = {}
var _bg_cache_order: Array[String] = []
var _event_log: String = ""
var _unlock_toast_panel: PanelContainer = null
var _unlock_toast_badge: Label = null
var _unlock_toast_label: Label = null
var _unlock_toast_tween: Tween = null
var _unlock_toast_tab: int = -1
var _unlock_toast_target_id: String = ""
var _pending_route_focus_action_id: String = ""

var current_scene_id: String = ""
var _market_ui: MarketScreenController = null

func _ready() -> void:
	# NK1-P6-POLISH: debug event spawning cleaned up — no hardcoded test events
	left_panel.visible = false
	message_label.text = ""
	message_label.meta_clicked.connect(_on_guide_link_clicked)
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
	if scheduler.has_method("bind_calendar"):
		scheduler.bind_calendar(GameState.calendar, GameState, {"cutscene_player": cutscene_player})

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


func _setup_story_unlock_toast() -> void:
	if _unlock_toast_panel != null and is_instance_valid(_unlock_toast_panel):
		return
	var panel := PanelContainer.new()
	panel.name = STORY_UNLOCK_TOAST_NAME
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme_type_variation = &"PortTitleBanner"
	panel.custom_minimum_size = Vector2(STORY_UNLOCK_TOAST_WIDTH, STORY_UNLOCK_TOAST_HEIGHT)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -STORY_UNLOCK_TOAST_WIDTH * 0.5
	panel.offset_right = STORY_UNLOCK_TOAST_WIDTH * 0.5
	panel.offset_top = STORY_UNLOCK_TOAST_TOP
	panel.offset_bottom = STORY_UNLOCK_TOAST_TOP + STORY_UNLOCK_TOAST_HEIGHT
	panel.pivot_offset = Vector2(STORY_UNLOCK_TOAST_WIDTH * 0.5, STORY_UNLOCK_TOAST_HEIGHT * 0.5)
	panel.modulate.a = 0.0
	panel.z_index = 80
	panel.gui_input.connect(_on_story_unlock_toast_gui_input)

	var row := HBoxContainer.new()
	row.name = "StoryUnlockToastContent"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(row)

	var badge := Label.new()
	badge.name = "StoryUnlockToastBadge"
	badge.theme_type_variation = &"MarketTitle"
	badge.custom_minimum_size = Vector2(168.0, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)

	var label := Label.new()
	label.name = "StoryUnlockToastLabel"
	label.theme_type_variation = &"MarketTitle"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	add_child(panel)
	_unlock_toast_panel = panel
	_unlock_toast_badge = badge
	_unlock_toast_label = label

func _format_story_unlock_toast(msg: String) -> Dictionary:
	var text := msg.strip_edges()
	if text.begins_with("【解锁】"):
		text = text.substr("【解锁】".length()).strip_edges()
	var badge := "解锁"
	var icon := "◇"
	var tab := 0
	var target_id := ""
	if text.contains("获得札"):
		badge = "札入手"
		icon = "◆"
		tab = 0
		target_id = _resolve_story_unlock_target_id("cards", text)
	elif text.contains("获得称号"):
		badge = "称号获得"
		icon = "★"
		tab = 1
		target_id = _resolve_story_unlock_target_id("titles", text)
	elif text.contains("关系突破"):
		badge = "关系进展"
		icon = "◎"
		tab = 2
		target_id = _resolve_story_unlock_target_id("relationships", text)
	return {
		"badge": badge,
		"icon": icon,
		"text": text,
		"tab": tab,
		"target_id": target_id,
	}

func _resolve_story_unlock_target_id(section: String, text: String) -> String:
	var display_name := _extract_story_unlock_display_name(text)
	if display_name == "":
		return ""
	var entries: Dictionary = STORY_TABLE_REGISTRY.get_entries(section)
	for raw_id in entries.keys():
		var entry = entries[raw_id]
		if not entry is Dictionary:
			continue
		var key := "label" if section == "relationships" else "name"
		if str(entry.get(key, "")) == display_name:
			return str(raw_id)
	return ""

func _extract_story_unlock_display_name(text: String) -> String:
	var start := text.find("「")
	if start < 0:
		return ""
	var end := text.find("」", start + 1)
	if end < 0:
		return ""
	return text.substr(start + 1, end - start - 1).strip_edges()

func _show_story_unlock_toast(msg: String) -> void:
	var toast := _format_story_unlock_toast(msg)
	var text := str(toast.get("text", "")).strip_edges()
	if text == "":
		return
	_unlock_toast_tab = int(toast.get("tab", 0))
	_unlock_toast_target_id = str(toast.get("target_id", ""))
	_setup_story_unlock_toast()
	if _unlock_toast_panel == null or _unlock_toast_badge == null or _unlock_toast_label == null:
		return
	_unlock_toast_badge.text = "%s %s" % [toast.get("icon", "◇"), toast.get("badge", "解锁")]
	_unlock_toast_label.text = text
	_unlock_toast_panel.visible = true
	_unlock_toast_panel.modulate.a = 0.0
	_unlock_toast_panel.scale = Vector2(0.96, 0.96)

	if _unlock_toast_tween != null and _unlock_toast_tween.is_valid():
		_unlock_toast_tween.kill()
	if not is_inside_tree():
		_unlock_toast_panel.modulate.a = 1.0
		_unlock_toast_panel.scale = Vector2.ONE
		return

	_unlock_toast_tween = create_tween()
	_unlock_toast_tween.tween_property(_unlock_toast_panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_unlock_toast_tween.parallel().tween_property(_unlock_toast_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_unlock_toast_tween.tween_interval(STORY_UNLOCK_TOAST_HOLD)
	_unlock_toast_tween.tween_property(_unlock_toast_panel, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_unlock_toast_tween.tween_callback(func(): _unlock_toast_panel.visible = false)


func _on_story_unlock_toast_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_open_story_unlock_toast_target()

func _open_story_unlock_toast_target() -> void:
	if _unlock_toast_tab < 0:
		return
	if game_shell != null and is_instance_valid(game_shell):
		game_shell.show_storybook(_unlock_toast_tab, _unlock_toast_target_id)

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
		get_tree().change_scene_to_file(ResourcePaths.SCENE_WORLD_MAP)
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
		
	var bg_path: String = scene_data.get("bg", ResourcePaths.BG_DEFAULT)
	if scene_data.get("type", "") == "port":
		bg_path = AssetPlaceholder.pick_background_path(bg_path)
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
		GameState.set_last_port(scene_data.get("location", scene_id.replace("port_", "")))
		_set_status_bar_visible(true)
		# NK1-P6: 左侧信息面板改为日志弹窗，不再常驻
		left_panel.visible = false
		left_title.text = "◆ 情报札记"
		title_mode.visible = false
		investigation_mode.visible = false
		npc_mode.visible = false
		port_mode.visible = true
		port_mode.setup(scene_data, scene_id)
		_show_port_intro_if_needed(scene_data, scene_id)
		_set_port_guide(scene_data)
	else:
		_set_status_bar_visible(true)
		# NK1-P6: 左侧信息面板改为日志弹窗，不再常驻
		left_panel.visible = false
		left_title.text = "◆ 情报札记"
		title_mode.visible = false
		port_mode.visible = false
		npc_mode.visible = false
		investigation_mode.visible = true
		investigation_mode.setup_investigation(scene_data, scene_id, focus_action_id)
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
	# NK1-P6: 港口引导信息 — 显示经济状态
	var market = GameState.market
	if market != null:
		var port_id: String = scene_data.get("location", "")
		if not port_id.is_empty():
			var prosperity: float = market.get_prosperity(port_id)
			var aff_label: String = market.get_affinity_label(port_id)
			var p_str := "平稳"
			if prosperity > 1.1: p_str = "繁荣"
			elif prosperity < 0.9: p_str = "萧条"
			_guide_text = "[color=#3d1f0a]港市状况：[/color] %s · [color=#3d1f0a]声誉：[/color] %s" % [p_str, aff_label]
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
	# NK1-P5-ECON-002: 显示最近经济动态
	if GameState.economy_log != null:
		var latest = GameState.economy_log.get_latest()
		if not latest.is_empty():
			parts.append(latest)
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
	# P7-X: 港口抵达过场（可选，数据驱动，缺失则静默）
	if cutscene_player == null:
		return
	var port_id: String = scene_data.get("location", scene_id.replace("port_", ""))
	var cs_id: String = cutscene_player.get_cutscene_id_for("port_arrival", port_id)
	if cs_id != "":
		cutscene_player.play(cs_id)

func _setup_missing_scene(scene_id: String) -> void:
	_set_status_bar_visible(true)
	left_panel.visible = false
	left_title.text = "◆ 情报札记"
	title_mode.visible = false
	port_mode.visible = false
	npc_mode.visible = false
	investigation_mode.visible = true
	investigation_mode.setup_missing(scene_id)
	_guide_text = ""
	_refresh_message_panel()
	update_status_panel()
