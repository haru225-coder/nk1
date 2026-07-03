class_name MainMessagePanel extends RefCounted

const MAX_LOG_LENGTH := 1000
const INFO_TITLE := "◆ 情报札记"

var _left_panel: PanelContainer = null
var _left_title: Label = null
var _message_label: RichTextLabel = null
var _event_log: String = ""
var _guide_text: String = ""

func bind(panel: PanelContainer, title: Label, label: RichTextLabel, guide_clicked: Callable) -> void:
	_left_panel = panel
	_left_title = title
	_message_label = label
	prepare_hidden_info_panel()
	if _message_label != null:
		_message_label.text = ""
		if guide_clicked.is_valid() and not _message_label.meta_clicked.is_connected(guide_clicked):
			_message_label.meta_clicked.connect(guide_clicked)

func prepare_hidden_info_panel() -> void:
	if _left_panel != null:
		_left_panel.visible = false
	if _left_title != null:
		_left_title.text = INFO_TITLE

func prepend_event_log(msg: String) -> void:
	_event_log = msg + _event_log
	if _event_log.length() > MAX_LOG_LENGTH:
		_event_log = _event_log.substr(0, MAX_LOG_LENGTH)
	_refresh()

func show_log(shell: GameShell) -> void:
	if shell != null and is_instance_valid(shell):
		shell.show_log(_event_log.strip_edges())

func set_port_guide(scene_data: Dictionary) -> void:
	_guide_text = ""
	var market = GameState.market
	if market != null:
		var port_id := str(scene_data.get("location", ""))
		if not port_id.is_empty():
			var prosperity: float = market.get_prosperity(port_id)
			var aff_label: String = market.get_affinity_label(port_id)
			var p_str := "平稳"
			if prosperity > 1.1:
				p_str = "繁荣"
			elif prosperity < 0.9:
				p_str = "萧条"
			_guide_text = "[color=#3d1f0a]港市状况：[/color] %s · [color=#3d1f0a]声誉：[/color] %s" % [p_str, aff_label]
	_refresh()

func clear_guide() -> void:
	_guide_text = ""
	_refresh()

func get_log_text() -> String:
	return _event_log.strip_edges()

func _refresh() -> void:
	if _left_panel == null or not _left_panel.visible or _message_label == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	if _guide_text != "":
		parts.append(_guide_text)
	if GameState.economy_log != null:
		var latest = GameState.economy_log.get_latest()
		if not latest.is_empty():
			parts.append(latest)
	if _event_log != "":
		if parts.size() > 0:
			parts.append("")
		parts.append(_event_log.strip_edges())
	_message_label.text = "\n".join(parts)
