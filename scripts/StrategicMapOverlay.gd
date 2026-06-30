extends Control
class_name StrategicMapOverlay

signal opened
signal closed
signal destination_set(port_id: String)

@onready var _map_view: StrategicMapView = $Center/MapFrame/Margin/VBox/MapView
@onready var _summary: Label = $Center/MapFrame/Margin/VBox/Summary
@onready var _popup: PanelContainer = $PortActionPopup
@onready var _popup_title: Label = $PortActionPopup/Margin/VBox/Title
@onready var _popup_info: Label = $PortActionPopup/Margin/VBox/Info
@onready var _btn_set_dest: Button = $PortActionPopup/Margin/VBox/Actions/SetDestination
@onready var _btn_info: Button = $PortActionPopup/Margin/VBox/Actions/Info
@onready var _btn_cancel: Button = $PortActionPopup/Margin/VBox/Actions/Cancel

var _selected_port_id: String = ""
var _open: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.visible = false
	_map_view.port_clicked.connect(_on_port_clicked)
	_btn_set_dest.pressed.connect(_on_set_destination)
	_btn_info.pressed.connect(_on_show_port_info)
	_btn_cancel.pressed.connect(_hide_popup)


func is_open() -> bool:
	return _open


func open(ship: Node2D, time_of_day: float, weather_text: String, hull_hp: int, max_hp: int) -> void:
	_map_view.ship = ship
	_map_view.destination_port_id = GameState.voyage_destination_id
	_update_summary(time_of_day, weather_text, hull_hp, max_hp)
	_hide_popup()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_open = true
	_map_view.queue_redraw()
	opened.emit()


func close() -> void:
	if not _open:
		return
	_hide_popup()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open = false
	closed.emit()


func toggle(ship: Node2D, time_of_day: float, weather_text: String, hull_hp: int, max_hp: int) -> void:
	if _open:
		close()
	else:
		open(ship, time_of_day, weather_text, hull_hp, max_hp)


func refresh_destination(time_of_day: float = -1.0, weather_text: String = "", hull_hp: int = -1, max_hp: int = -1) -> void:
	_map_view.destination_port_id = GameState.voyage_destination_id
	_map_view.queue_redraw()
	if time_of_day >= 0.0 and hull_hp >= 0 and max_hp > 0:
		_update_summary(time_of_day, weather_text, hull_hp, max_hp)


func _update_summary(time_of_day: float, weather_text: String, hull_hp: int, max_hp: int) -> void:
	var hour := int(time_of_day) % 24
	var dest_line := "航行目标: 无"
	if GameState.voyage_destination_id != "":
		dest_line = "航行目标: %s" % _port_name(GameState.voyage_destination_id)
	_summary.text = "时辰 %02d:00  |  %s\n船体 %d/%d  |  %s\n%s\nM / Esc 关闭地图" % [
		hour, weather_text, hull_hp, max_hp, dest_line, "点击港口规划航线"
	]


func _on_port_clicked(port_id: String) -> void:
	_selected_port_id = port_id
	_popup_title.text = _port_name(port_id)
	_popup_info.text = _port_info_text(port_id)
	_popup.visible = true


func _hide_popup() -> void:
	_popup.visible = false
	_selected_port_id = ""


func _on_set_destination() -> void:
	if _selected_port_id == "":
		return
	if not GameState.set_voyage_destination(_selected_port_id):
		return
	_map_view.destination_port_id = _selected_port_id
	_map_view.queue_redraw()
	destination_set.emit(_selected_port_id)
	_hide_popup()


func _on_show_port_info() -> void:
	if _selected_port_id == "":
		return
	_popup_info.text = _port_info_text(_selected_port_id, true)


func _port_name(port_id: String) -> String:
	for port_data in MapLayout.get_ports_data():
		if port_data.get("id", "") == port_id:
			return port_data.get("name", port_id)
	return port_id


func _port_info_text(port_id: String, expanded: bool = false) -> String:
	for port_data in MapLayout.get_ports_data():
		if port_data.get("id", "") != port_id:
			continue
		var lines: PackedStringArray = []
		lines.append("区域: %s" % port_data.get("region", "未知"))
		lines.append("状态: %s" % port_data.get("status", "thread"))
		if expanded:
			var tags: Array = port_data.get("tags", [])
			if not tags.is_empty():
				lines.append("标签: %s" % ", ".join(tags))
			var conns: Array = port_data.get("connections", [])
			if not conns.is_empty():
				var names: PackedStringArray = []
				for conn_id in conns:
					names.append(_port_name(str(conn_id)))
				lines.append("航线: %s" % ", ".join(names))
		return "\n".join(lines)
	return ""