extends Control
class_name TownMapView

signal hotspot_pressed(scene_id: String)

const HOTSPOT_SCENE := preload(ResourcePaths.SCENE_TOWN_MAP_HOTSPOT)
const ENTRY_STAGGER := 0.045  ## 太阁风格：建筑依次淡入的时间间隔

@onready var _map_frame: NinePatchRect = $MapFrame
@onready var _map_clip: Control = $MapFrame/MapClip
@onready var _map_texture: TextureRect = $MapFrame/MapClip/MapTexture
@onready var _hotspot_layer: Control = $MapFrame/MapClip/HotspotLayer
@onready var _hint_label: Label = $MapFrame/MapClip/MapHint

var _hint_plaque: PanelContainer = null

func _ready() -> void:
	_ensure_koei_frame()
	_ensure_hint_plaque()
	call_deferred("_start_hint_pulse")

## 运行时兜底：保证木框贴图与 DialogueBox 同款 patch
func _ensure_koei_frame() -> void:
	if _map_frame == null:
		return
	if _map_frame.texture == null:
		_map_frame.texture = load(ResourcePaths.FRAME_KOEI) as Texture2D
	_map_frame.patch_margin_left = 40
	_map_frame.patch_margin_top = 40
	_map_frame.patch_margin_right = 40
	_map_frame.patch_margin_bottom = 40
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _map_clip:
		_map_clip.clip_contents = true

## 底部提示改朱砂/铜框小牌，避免白字贴在地图上发虚
func _ensure_hint_plaque() -> void:
	if _hint_label == null:
		return
	if _hint_plaque != null and is_instance_valid(_hint_plaque):
		return
	if _map_clip.has_node("HintPlaque"):
		_hint_plaque = _map_clip.get_node("HintPlaque") as PanelContainer
		return

	_hint_plaque = PanelContainer.new()
	_hint_plaque.name = "HintPlaque"
	_hint_plaque.theme_type_variation = UITheme.TOWN_HINT_PANEL
	_hint_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_plaque.layout_mode = 1
	_hint_plaque.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_hint_plaque.anchor_left = 0.5
	_hint_plaque.anchor_top = 1.0
	_hint_plaque.anchor_right = 0.5
	_hint_plaque.anchor_bottom = 1.0
	_hint_plaque.offset_left = -150.0
	_hint_plaque.offset_top = -42.0
	_hint_plaque.offset_right = 150.0
	_hint_plaque.offset_bottom = -8.0
	_hint_plaque.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_plaque.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# 把原 MapHint 挪进牌匾
	var parent := _hint_label.get_parent()
	if parent:
		parent.remove_child(_hint_label)
	_hint_label.layout_mode = 2
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.theme_type_variation = UITheme.TOWN_HINT_LABEL
	_hint_plaque.add_child(_hint_label)
	_map_clip.add_child(_hint_plaque)

func _start_hint_pulse() -> void:
	if _hint_plaque == null and _hint_label == null:
		return
	var target: CanvasItem = _hint_plaque if _hint_plaque else _hint_label
	var tween := create_tween().set_loops()
	tween.tween_property(target, "modulate:a", 0.55, 1.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(target, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)

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
