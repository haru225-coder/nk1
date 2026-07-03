class_name MainScenePresenter extends RefCounted

var _title_mode: Control = null
var _investigation_mode: Control = null
var _port_mode: Control = null
var _npc_mode: Control = null
var _message_panel: MainMessagePanel = null
var _set_status_bar_visible: Callable = Callable()

func bind(
	title_mode: Control,
	investigation_mode: Control,
	port_mode: Control,
	npc_mode: Control,
	message_panel: MainMessagePanel,
	set_status_bar_visible: Callable
) -> void:
	_title_mode = title_mode
	_investigation_mode = investigation_mode
	_port_mode = port_mode
	_npc_mode = npc_mode
	_message_panel = message_panel
	_set_status_bar_visible = set_status_bar_visible

func present_scene(scene_data: Dictionary, scene_id: String, focus_action_id: String) -> Node:
	var type := str(scene_data.get("type", "investigation"))
	if type == "title":
		_set_status_bar(false)
		_prepare_panel()
		_show_modes(true, false, false, false)
		_title_mode.call("setup", scene_data)
		return _title_mode
	if type == "port":
		GameState.set_last_port(str(scene_data.get("location", scene_id.replace("port_", ""))))
		_set_status_bar(true)
		_prepare_panel()
		_show_modes(false, false, true, false)
		_port_mode.call("setup", scene_data, scene_id)
		_message_panel.set_port_guide(scene_data)
		return _port_mode
	_set_status_bar(true)
	_prepare_panel()
	_show_modes(false, true, false, false)
	_investigation_mode.call("setup_investigation", scene_data, scene_id, focus_action_id)
	_message_panel.clear_guide()
	return _investigation_mode

func present_missing(scene_id: String) -> Node:
	_set_status_bar(true)
	_prepare_panel()
	_show_modes(false, true, false, false)
	_investigation_mode.call("setup_missing", scene_id)
	_message_panel.clear_guide()
	return _investigation_mode

func _set_status_bar(show_bar: bool) -> void:
	if _set_status_bar_visible.is_valid():
		_set_status_bar_visible.call(show_bar)

func _prepare_panel() -> void:
	if _message_panel != null:
		_message_panel.prepare_hidden_info_panel()

func _show_modes(title_visible: bool, investigation_visible: bool, port_visible: bool, npc_visible: bool) -> void:
	if _title_mode != null:
		_title_mode.visible = title_visible
	if _investigation_mode != null:
		_investigation_mode.visible = investigation_visible
	if _port_mode != null:
		_port_mode.visible = port_visible
	if _npc_mode != null:
		_npc_mode.visible = npc_visible
