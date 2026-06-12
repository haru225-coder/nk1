extends Area2D

@export var port_id: String = "quanzhou"
@export var port_name: String = "泉州港"

var player_in_zone: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Ship":
		player_in_zone = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "Ship":
		player_in_zone = false

func _input(event: InputEvent) -> void:
	if player_in_zone and event.is_action_pressed("ui_accept"):
		# Trigger docking
		GameState.flags["return_to_port"] = true
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
