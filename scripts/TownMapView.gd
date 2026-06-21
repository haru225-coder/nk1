extends Control
class_name TownMapView

signal hotspot_pressed(scene_id: String)

const HOTSPOT_SCENE := preload("res://scenes/TownMapHotspot.tscn")

@onready var _map_frame: NinePatchRect = $MapFrame
@onready var _map_texture: TextureRect = $MapFrame/MapClip/MapTexture
@onready var _hotspot_layer: Control = $MapFrame/MapClip/HotspotLayer
@onready var _hint_label: Label = $MapHint

func setup(town_map: Dictionary, facilities: Array, port_location: String) -> int:
	_clear_hotspots()
	var bg_path: String = town_map.get("bg", "")
	if bg_path != "":
		_map_texture.texture = AssetPlaceholder.load_texture(bg_path, "bg")
	_map_hint_text(town_map)
	var facility_by_id := {}
	for fac in facilities:
		facility_by_id[fac.get("id", "")] = fac
	for hotspot in town_map.get("hotspots", []):
		var fac_id: String = hotspot.get("facility_id", "")
		if fac_id == "" or not facility_by_id.has(fac_id):
			continue
		var fac: Dictionary = facility_by_id[fac_id]
		if not GameManager.facility_available(fac):
			continue
		var scene_id := GameManager.resolve_hotspot_scene(hotspot, fac, port_location)
		if scene_id == "":
			continue
		var display := GameManager.resolve_facility_subtitle(fac)
		var node: TownMapHotspot = HOTSPOT_SCENE.instantiate()
		_hotspot_layer.add_child(node)
		node.setup(hotspot, display, scene_id)
		node.activated.connect(_on_hotspot_pressed.bind(scene_id))
	return _hotspot_layer.get_child_count()

func _map_hint_text(town_map: Dictionary) -> void:
	var hint: String = town_map.get("hint", "")
	if hint == "":
		hint = "点击地图上的建筑进入"
	_hint_label.text = "▸ " + hint

func _clear_hotspots() -> void:
	for child in _hotspot_layer.get_children():
		child.queue_free()

func _on_hotspot_pressed(scene_id: String) -> void:
	hotspot_pressed.emit(scene_id)