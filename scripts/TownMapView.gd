extends Control
class_name TownMapView

signal hotspot_pressed(scene_id: String)

const HOTSPOT_SCENE := preload(ResourcePaths.SCENE_TOWN_MAP_HOTSPOT)
const ENTRY_STAGGER := 0.045  ## 太阁风格：建筑依次淡入的时间间隔

@onready var _map_texture: TextureRect = $MapTexture
@onready var _hotspot_layer: Control = $HotspotLayer
@onready var _hint_label: Label = $MapHint

func _ready() -> void:
	call_deferred("_start_hint_pulse")

func _start_hint_pulse() -> void:
	if _hint_label == null:
		return
	var tween := create_tween().set_loops()
	tween.tween_property(_hint_label, "modulate:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_hint_label, "modulate:a", 0.85, 1.4).set_trans(Tween.TRANS_SINE)

func setup(town_map: Dictionary, facilities: Array, port_location: String) -> int:
	_clear_hotspots()
	var bg_path: String = town_map.get("bg", "")
	if bg_path != "":
		_map_texture.texture = AssetPlaceholder.load_texture(bg_path, "bg")
	_map_hint_text(town_map)

	var facility_by_id := {}
	for fac in facilities:
		facility_by_id[fac.get("id", "")] = fac

	var valid_hotspots: Array[Dictionary] = []
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
		valid_hotspots.append({"hotspot": hotspot, "fac": fac, "scene_id": scene_id})

	# 太阁风格：建筑热点依次淡入，增强地图的「展开感」
	for i in valid_hotspots.size():
		var data := valid_hotspots[i]
		var display := GameManager.resolve_facility_subtitle(data["fac"])
		var node: TownMapHotspot = HOTSPOT_SCENE.instantiate()
		_hotspot_layer.add_child(node)
		node.setup(data["hotspot"], display, data["scene_id"], data["fac"])
		node.activated.connect(_on_hotspot_pressed.bind(data["scene_id"]))
		_animate_hotspot_entry(node, i * ENTRY_STAGGER)

	return _hotspot_layer.get_child_count()

func _animate_hotspot_entry(node: TownMapHotspot, delay: float) -> void:
	if not is_instance_valid(node):
		return
	node.modulate.a = 0.0
	node.scale = Vector2(0.92, 0.92)
	var tween := node.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(node, "modulate:a", 1.0, 0.22)
	tween.parallel().tween_property(node, "scale", Vector2.ONE, 0.28)

func _map_hint_text(town_map: Dictionary) -> void:
	if _hint_label == null:
		return
	var hint: String = town_map.get("hint", "")
	if hint == "":
		hint = "点击建筑进入"
	_hint_label.text = hint

func _clear_hotspots() -> void:
	for child in _hotspot_layer.get_children():
		child.queue_free()

func _on_hotspot_pressed(scene_id: String) -> void:
	hotspot_pressed.emit(scene_id)
