extends Control

signal scene_requested(scene_id: String)

@onready var main_title: Label = $VBoxContainer/MainTitle
@onready var sub_title: Label = $VBoxContainer/SubTitle
@onready var start_button: Button = $VBoxContainer/StartButton

var _button_connected: bool = false

func setup(scene_data: Dictionary) -> void:
	main_title.text = scene_data.get("cg_title", "南海立志传")
	sub_title.text = scene_data.get("cg_sub", "")
	
	if _button_connected:
		var conns = start_button.pressed.get_connections()
		for c in conns:
			start_button.pressed.disconnect(c.callable)
			
	var choices = scene_data.get("choices", [])
	var next_scene = "prologue_tabletop"
	if choices.size() > 0:
		start_button.text = choices[0].get("label", "开始旅程")
		next_scene = choices[0].get("next", "prologue_tabletop")
		
	start_button.pressed.connect(func():
		scene_requested.emit(next_scene)
	)
	_button_connected = true
