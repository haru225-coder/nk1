extends Control
## 岸上名册浮页（chars 线薄接入）：左 CharRoster、右 CharPortraitPanel。
## 从港口岸带「名册」或人物志「立绘册」打开；Esc / 合上 / 点暗幕关闭。不入存档、不改玩法数值。

signal closed

const Art := preload("res://scripts/ui/CharacterArt.gd")
const Roster := preload("res://scripts/chars/CharRoster.gd")
const PortraitPanel := preload("res://scripts/chars/CharPortraitPanel.gd")

var _sheet: PanelContainer
var _roster: VBoxContainer
var _panel: PanelContainer
var _closing := false
var _live := true
var current_id := ""


func _init() -> void:
	name = "CharsShoreOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_live = DisplayServer.get_name() != "headless"


func begin(focus_id := "") -> void:
	_build()
	if focus_id != "" and not GameManager.get_character(focus_id).is_empty():
		_pick(focus_id)
	elif _roster != null:
		var sid := str(_roster.call("selected_id"))
		if sid != "":
			_pick(sid)
	if _live:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)


func focus_id(id: String) -> void:
	_pick(id)


func selected_id() -> String:
	return current_id


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.024, 0.018, 0.82) if UiTheme.IS_JUANBEN else Color(UiTheme.DIM, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_sheet = PanelContainer.new()
	_sheet.name = "WireSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = 26
	_sheet.offset_top = 6
	_sheet.offset_right = -26
	_sheet.offset_bottom = -12
	_sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	add_child(_sheet)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	_sheet.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := Art.label("名册", 36, UiTheme.GOLD_HI, true)
	title.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var sub := Art.label("立绘册　按品级浏览", UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "合上"
	close.custom_minimum_size = Vector2(112, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_overlay)
	UiTheme.style_button(close, true)
	head.add_child(close)

	var row := HBoxContainer.new()
	row.name = "Body"
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := PanelContainer.new()
	left.name = "RosterHost"
	left.add_theme_stylebox_override("panel", UiTheme.panel())
	row.add_child(left)
	var lm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		lm.add_theme_constant_override("margin_%s" % side, 12)
	left.add_child(lm)
	_roster = Roster.new()
	lm.add_child(_roster)
	_roster.picked.connect(_pick)

	_panel = PortraitPanel.new()
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_panel)
	# 左栏按比例分宽（名册 : 立绘面板 = Roster.COLUMN_RATIO : 1，不窄于 Roster.COLUMN_MIN_W，与人物志内嵌名册、CharsDemo 同一支）；短注按栏宽省略，整页最小宽不越视口
	Roster.split_columns(left, _panel)


func _pick(id: String) -> void:
	if id == "":
		return
	var ch := GameManager.get_character(id)
	if ch.is_empty():
		return
	current_id = id
	if _panel != null:
		_panel.call("show_character", ch)
	if _roster != null and str(_roster.call("selected_id")) != id:
		_roster.call("select_id", id)


func close_overlay() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	if not _live or not is_inside_tree():
		queue_free()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE):
		close_overlay()
	elif event is InputEventKey:
		var k := (event as InputEventKey).keycode
		if k == KEY_UP:
			_step(-1)
		elif k == KEY_DOWN:
			_step(1)


func _step(d: int) -> void:
	if _roster == null:
		return
	var rows: Dictionary = _roster.get("_rows")
	if rows.is_empty():
		return
	var keys: Array = rows.keys()
	var i := keys.find(current_id)
	if i < 0:
		i = 0
	else:
		i = clampi(i + d, 0, keys.size() - 1)
	_pick(str(keys[i]))
