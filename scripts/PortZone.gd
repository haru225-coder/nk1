extends Area2D

@export var port_id: String = "quanzhou"
@export var port_name: String = "泉州港"

var player_in_zone: bool = false
var port_status: String = "main"

const _ICON_TEX: Texture2D = preload("res://assets/icons_128/icon_shipyard_koei.png")
const _HOVER_RADIUS := 92.0

@onready var _icon: Sprite2D = $Visual/Icon
@onready var _name_label: Label = $Visual/NameLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_visuals()


func setup(port_data: Dictionary) -> void:
	port_id = port_data.get("id", port_id)
	port_name = port_data.get("name", port_name)
	port_status = port_data.get("status", "thread")
	if is_node_ready():
		_apply_visuals()


func _apply_visuals() -> void:
	if _icon:
		_icon.texture = _ICON_TEX
		_icon.scale = Vector2.ONE * MapPortStyle.ICON_SCALE_WORLD
		_icon.modulate = MapPortStyle.port_modulate(port_status)
	if _name_label:
		_name_label.text = port_name
		_name_label.visible = false


func _process(_delta: float) -> void:
	if _name_label:
		_name_label.visible = player_in_zone
	queue_redraw()


func _draw() -> void:
	if not player_in_zone:
		return
	draw_arc(Vector2.ZERO, _HOVER_RADIUS, 0.0, TAU, 48, MapPortStyle.HOVER_RING, 3.0, true)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		player_in_zone = true
		if _name_label:
			_name_label.text = port_name + " (按 Enter 停靠)"


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player_ship"):
		player_in_zone = false
		if _name_label:
			_name_label.text = port_name


func _input(event: InputEvent) -> void:
	if player_in_zone and event.is_action_pressed("ui_accept"):
		var player_ship := get_tree().get_first_node_in_group("player_ship") as Node2D
		if player_ship:
			GameState.save_world_map_ship_pose(player_ship.position, player_ship.rotation)
		GameState.set_return_port(port_id)
		get_tree().change_scene_to_file(ResourcePaths.SCENE_MAIN)