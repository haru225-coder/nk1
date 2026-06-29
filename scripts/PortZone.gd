extends Area2D

@export var port_id: String = "quanzhou"
@export var port_name: String = "泉州港"

var player_in_zone: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if has_node("Label"):
		$Label.text = port_name + " (按 Enter 停靠)"

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		player_in_zone = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		player_in_zone = false

func _input(event: InputEvent) -> void:
	if player_in_zone and event.is_action_pressed("ui_accept"):
		var player_ship := get_tree().get_first_node_in_group("player_ship") as Node2D
		if player_ship:
			GameState.save_world_map_ship_pose(player_ship.position, player_ship.rotation)
		GameState.set_return_port(port_id)
		get_tree().change_scene_to_file(ResourcePaths.SCENE_MAIN)
