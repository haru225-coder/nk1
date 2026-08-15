extends CanvasLayer
class_name EndingSettlementController

## 通关后结算屏：展示结局标题/摘要，提供回标题 / 新航程 / 保存。

signal closed(action: String)

const FRAME_PATH := ResourcePaths.FRAME_KOEI
const LAYER_Z := 120

var _root: Control = null
var _ending_id: String = ""
var _display: Dictionary = {}

func _ready() -> void:
	layer = LAYER_Z
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func present(display: Dictionary) -> void:
	_display = display.duplicate(true) if display is Dictionary else {}
	_ending_id = str(_display.get("ending_id", ""))
	if _root == null:
		_build_ui()
	_apply_display()
	visible = true
	if _root:
		_root.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 1.0, 0.28)

func _build_ui() -> void:
	if _root != null and is_instance_valid(_root):
		return
	_root = Control.new()
	_root.name = "SettlementRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.03, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var frame := NinePatchRect.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(720, 480)
	frame.texture = load(FRAME_PATH) as Texture2D
	frame.patch_margin_left = 40
	frame.patch_margin_top = 40
	frame.patch_margin_right = 40
	frame.patch_margin_bottom = 40
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 36)
	frame.add_child(margin)

	var panel := PanelContainer.new()
	panel.theme_type_variation = UITheme.PANEL_DIALOGUE_INNER
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var kicker := Label.new()
	kicker.name = "Kicker"
	kicker.text = "— 航程终章 —"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.theme_type_variation = UITheme.ENDING_KICKER
	vbox.add_child(kicker)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = UITheme.ENDING_TITLE
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = UITheme.ENDING_SUBTITLE
	vbox.add_child(subtitle)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(200, 2)
	rule.color = Color(0.88, 0.68, 0.28, 0.75)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(rule)

	var meta := Label.new()
	meta.name = "Meta"
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.theme_type_variation = UITheme.ENDING_META
	vbox.add_child(meta)

	var summary := RichTextLabel.new()
	summary.name = "Summary"
	summary.bbcode_enabled = true
	summary.fit_content = true
	summary.scroll_active = false
	summary.custom_minimum_size = Vector2(560, 0)
	summary.theme_type_variation = UITheme.ENDING_SUMMARY
	vbox.add_child(summary)

	var epilogue := RichTextLabel.new()
	epilogue.name = "Epilogue"
	epilogue.bbcode_enabled = true
	epilogue.fit_content = true
	epilogue.scroll_active = false
	epilogue.custom_minimum_size = Vector2(560, 0)
	epilogue.theme_type_variation = UITheme.ENDING_EPILOGUE
	vbox.add_child(epilogue)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions)

	_add_action_button(actions, "返回标题", "return_title", UITheme.BTN_TITLE_MENU)
	_add_action_button(actions, "再启航程", "new_run", UITheme.BTN_SET_SAIL)
	_add_action_button(actions, "保存终局", "save", UITheme.BTN_CHOICE)

func _add_action_button(parent: Control, label: String, action: String, variation: String) -> void:
	var btn := UIBuilder.make_button(label, variation, 46)
	btn.custom_minimum_size = Vector2(280, 46)
	btn.pressed.connect(func(): _on_action(action))
	parent.add_child(btn)

func _apply_display() -> void:
	if _root == null:
		return
	var title: Label = _root.find_child("Title", true, false) as Label
	var subtitle: Label = _root.find_child("Subtitle", true, false) as Label
	var meta: Label = _root.find_child("Meta", true, false) as Label
	var summary: RichTextLabel = _root.find_child("Summary", true, false) as RichTextLabel
	var epilogue: RichTextLabel = _root.find_child("Epilogue", true, false) as RichTextLabel

	if title:
		title.text = "结局 · %s" % str(_display.get("title", "终章"))
	if subtitle:
		subtitle.text = str(_display.get("subtitle", ""))
		subtitle.visible = subtitle.text != ""
	if meta:
		var rank_title := str(_display.get("rank_title", ""))
		var date_key := str(_display.get("date_key", ""))
		var bits: PackedStringArray = []
		if rank_title != "":
			bits.append("秩禄：%s" % rank_title)
		if date_key != "":
			bits.append(date_key)
		meta.text = " · ".join(bits)
		meta.visible = meta.text != ""
	if summary:
		summary.text = "[center]%s[/center]" % str(_display.get("summary", ""))
	if epilogue:
		var epi := str(_display.get("epilogue", ""))
		epilogue.visible = epi != ""
		if epi != "":
			epilogue.text = "[center][i]%s[/i][/center]" % epi

func _on_action(action: String) -> void:
	closed.emit(action)
