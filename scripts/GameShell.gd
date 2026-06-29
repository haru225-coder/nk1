extends Control
class_name GameShell

signal navigation_requested(scene_id: String)
signal log_requested
signal message_logged(msg: String)

const COMMAND_BAR_SCENE := preload(ResourcePaths.SCENE_COMMAND_BAR)

@onready var background_layer: Control = $BackgroundLayer
@onready var background: TextureRect = $BackgroundLayer/Background
@onready var vignette_layer: Control = $VignetteLayer
@onready var content_layer: Control = $ContentLayer
@onready var command_bar_host: PanelContainer = $CommandBarHost

var _command_bar: CommandBar
var _hotspot_source: TownMapView
var _log_popup: AcceptDialog

const COMMAND_BAR_HEIGHT := 88.0

func _ready() -> void:
	_apply_content_insets()
	_setup_command_bar()

func get_background_texture_rect() -> TextureRect:
	return background

func get_content_root() -> Control:
	return content_layer

func get_layout_root() -> Control:
	return content_layer.get_node_or_null("HBoxContainer") as Control

func set_status_bar_offset(offset_top: float) -> void:
	content_layer.offset_top = offset_top
	command_bar_host.offset_bottom = 0.0

func apply_scene(scene_id: String, scene_data: Dictionary, mode_node: Node = null) -> void:
	_bind_hotspot_listener(mode_node)
	var command_spec := _resolve_command_spec(scene_id, scene_data)
	_command_bar.build(command_spec)

func show_log(text: String) -> void:
	if _log_popup == null:
		_log_popup = AcceptDialog.new()
		_log_popup.title = "航海日志"
		_log_popup.dialog_hide_on_ok = true
		_log_popup.min_size = Vector2(480, 280)
		add_child(_log_popup)
	_log_popup.dialog_text = text if text != "" else "（尚无记录）"
	_log_popup.popup_centered()

func _setup_command_bar() -> void:
	for child in command_bar_host.get_children():
		child.queue_free()
	_command_bar = COMMAND_BAR_SCENE.instantiate()
	command_bar_host.add_child(_command_bar)
	_command_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_command_bar.command_pressed.connect(_on_command_pressed)

func _resolve_command_spec(scene_id: String, scene_data: Dictionary) -> Dictionary:
	var scene_type: String = scene_data.get("type", "investigation")
	var template := "investigation"
	match scene_type:
		"port":
			template = "port"
		"title":
			template = "title"
	return {
		"template": template,
		"scene_id": scene_id,
		"scene_data": scene_data,
		"port_location": scene_data.get("location", scene_id.replace("port_", "")),
	}

func _bind_hotspot_listener(mode_node: Node) -> void:
	_unbind_hotspot_listener()
	if mode_node == null:
		return
	var maybe_view: TownMapView = mode_node.get_node_or_null(
		"FacilityHub/Margin/VBox/TownMapView"
	)
	if maybe_view == null or not maybe_view.visible:
		return
	_hotspot_source = maybe_view
	if not _hotspot_source.hotspot_pressed.is_connected(_on_hotspot_pressed):
		_hotspot_source.hotspot_pressed.connect(_on_hotspot_pressed)

func _unbind_hotspot_listener() -> void:
	if _hotspot_source != null and is_instance_valid(_hotspot_source):
		if _hotspot_source.hotspot_pressed.is_connected(_on_hotspot_pressed):
			_hotspot_source.hotspot_pressed.disconnect(_on_hotspot_pressed)
	_hotspot_source = null

func _on_hotspot_pressed(scene_id: String) -> void:
	if GameManager.input_locked or scene_id == "":
		return
	navigation_requested.emit(scene_id)

func _on_command_pressed(action: Dictionary) -> void:
	if GameManager.input_locked:
		return
	match action.get("type", ""):
		"open_log":
			log_requested.emit()
		"navigate":
			var effects: Dictionary = action.get("effects", {})
			if not effects.is_empty():
				GameState.apply_effects(effects)
			var narration: String = action.get("narration", "")
			if narration != "":
				message_logged.emit(narration + "\n\n")
			var target: String = action.get("target", "")
			if target != "":
				navigation_requested.emit(target)
		_:
			pass

func _apply_content_insets() -> void:
	content_layer.offset_bottom = -COMMAND_BAR_HEIGHT
	command_bar_host.offset_top = -COMMAND_BAR_HEIGHT