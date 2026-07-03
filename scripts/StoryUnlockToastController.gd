class_name StoryUnlockToastController extends Control

const STORY_UNLOCK_TOAST_NAME := "StoryUnlockToast"
const STORY_UNLOCK_TOAST_WIDTH := 640.0
const STORY_UNLOCK_TOAST_HEIGHT := 96.0
const STORY_UNLOCK_TOAST_TOP := 72.0
const STORY_UNLOCK_TOAST_HOLD := 2.0
const STORY_TABLE_REGISTRY := preload(ResourcePaths.SCRIPT_STORY_TABLE_REGISTRY)

var _unlock_toast_panel: PanelContainer = null
var _unlock_toast_badge: Label = null
var _unlock_toast_label: Label = null
var _unlock_toast_tween: Tween = null
var _unlock_toast_tab: int = -1
var _unlock_toast_target_id: String = ""
var _game_shell: GameShell = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func bind_shell(shell: GameShell) -> void:
	_game_shell = shell

func _setup_story_unlock_toast() -> void:
	if _unlock_toast_panel != null and is_instance_valid(_unlock_toast_panel):
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if _game_shell != null and is_instance_valid(_game_shell):
		_game_shell.show_storybook(_unlock_toast_tab, _unlock_toast_target_id)
