extends CanvasLayer
class_name SeaEventController

signal event_finished

var event_data: Dictionary = {}
var panel: PanelContainer
var title_label: Label
var body_label: RichTextLabel
var vbox: VBoxContainer

func _ready() -> void:
	# 允许在树暂停时继续运行
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	
	# 半透明黑色背景遮罩
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 400)
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	
	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)
	
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title_label)
	
	body_label = RichTextLabel.new()
	body_label.bbcode_enabled = true
	body_label.fit_content = true
	body_label.custom_minimum_size = Vector2(500, 100)
	vbox.add_child(body_label)
	
	_populate_ui()

func _populate_ui() -> void:
	if event_data.is_empty(): return
	
	title_label.text = event_data.get("title", "未知遭遇")
	body_label.text = event_data.get("body", "")
	
	var choices = event_data.get("choices", [])
	
	if choices.is_empty():
		var btn = Button.new()
		btn.text = "继续"
		btn.pressed.connect(func(): _on_choice_made({}))
		vbox.add_child(btn)
	else:
		for choice in choices:
			var btn = Button.new()
			btn.text = choice.get("label", "...")
			btn.pressed.connect(func(): _on_choice_made(choice))
			vbox.add_child(btn)

func _on_choice_made(choice: Dictionary) -> void:
	if choice.has("intent_struct"):
		var istruct = choice["intent_struct"]
		var intent = load("res://scripts/systems/Intent.gd").new(
			istruct.get("type", "ignore"),
			istruct.get("source", "player_fleet"),
			istruct.get("target", "unknown_fleet"),
			istruct.get("parameters", {}),
			istruct.get("context", {})
		)
		IntentResolver.process(intent)
		
	event_finished.emit()
	queue_free()

# 静态工厂方法，方便直接调用
static func trigger_event(parent_node: Node, data: Dictionary) -> SeaEventController:
	var controller = SeaEventController.new()
	controller.event_data = data
	parent_node.add_child(controller)
	return controller
