extends Control

signal layout_changed(height: float)

const ICON_DIR := "res://assets/icons_stat/"
const VALUE_COLOR_NORMAL := Color(0.98, 0.92, 0.72, 1)
const VALUE_COLOR_WARN := Color(1.0, 0.75, 0.4, 1)
const VALUE_COLOR_DANGER := Color(0.95, 0.45, 0.42, 1)
const METER_COLOR_NORMAL := Color(0.82, 0.62, 0.24, 1)
const METER_COLOR_WARN := Color(0.95, 0.72, 0.28, 1)
const METER_COLOR_DANGER := Color(0.92, 0.38, 0.32, 1)

@onready var voyage_row: HBoxContainer = $Panel/Body/VBox/VoyageRow
@onready var location_value: Label = $Panel/Body/VBox/PrimaryRow/Location/Margin/Row/VBox/Value
@onready var money_value: Label = $Panel/Body/VBox/PrimaryRow/Money/Margin/Row/VBox/Value
@onready var fame_value: Label = $Panel/Body/VBox/PrimaryRow/Fame/Margin/Row/VBox/Value
@onready var permit_value: Label = $Panel/Body/VBox/PrimaryRow/Permit/Margin/Row/VBox/Value
@onready var permit_icon: TextureRect = $Panel/Body/VBox/PrimaryRow/Permit/Margin/Row/Icon
@onready var pu_value: Label = $Panel/Body/VBox/PrimaryRow/PuAttention/Margin/Row/VBox/Value
@onready var pu_icon: TextureRect = $Panel/Body/VBox/PrimaryRow/PuAttention/Margin/Row/Icon
@onready var cargo_value: Label = $Panel/Body/VBox/PrimaryRow/Cargo/Margin/Row/VBox/Value
@onready var crew_value: Label = $Panel/Body/VBox/VoyageRow/Crew/Margin/Row/VBox/Value
@onready var crew_icon: TextureRect = $Panel/Body/VBox/VoyageRow/Crew/Margin/Row/Icon
@onready var crew_meter: ColorRect = $Panel/Body/VBox/VoyageRow/Crew/Margin/Row/VBox/MeterTrack/MeterFill
@onready var food_value: Label = $Panel/Body/VBox/VoyageRow/Food/Margin/Row/VBox/Value
@onready var food_icon: TextureRect = $Panel/Body/VBox/VoyageRow/Food/Margin/Row/Icon
@onready var food_meter: ColorRect = $Panel/Body/VBox/VoyageRow/Food/Margin/Row/VBox/MeterTrack/MeterFill
@onready var water_value: Label = $Panel/Body/VBox/VoyageRow/Water/Margin/Row/VBox/Value
@onready var water_icon: TextureRect = $Panel/Body/VBox/VoyageRow/Water/Margin/Row/Icon
@onready var water_meter: ColorRect = $Panel/Body/VBox/VoyageRow/Water/Margin/Row/VBox/MeterTrack/MeterFill
@onready var ship_value: Label = $Panel/Body/VBox/VoyageRow/Ship/Margin/Row/VBox/Value
@onready var ship_icon: TextureRect = $Panel/Body/VBox/VoyageRow/Ship/Margin/Row/Icon
@onready var ship_meter: ColorRect = $Panel/Body/VBox/VoyageRow/Ship/Margin/Row/VBox/MeterTrack/MeterFill

var _icon_cache: Dictionary = {}
var _prev_text: Dictionary = {}
var _pulse_tweens: Dictionary = {}
var _last_height: float = -1.0
var _ready_done: bool = false

func _ready() -> void:
	_preload_icons()
	_bind_tooltips()
	_ready_done = true
	_apply_layout_height()

func get_layout_height() -> float:
	return GameUILayout.STATUS_BAR_HEIGHT_FULL if _show_voyage_stats() else GameUILayout.STATUS_BAR_HEIGHT_COMPACT

func _preload_icons() -> void:
	for key in [
		"money", "fame", "permit", "permit_ok", "pu", "cargo", "location",
		"crew", "food", "water", "ship",
	]:
		var path := ICON_DIR + "icon_stat_%s.png" % key
		if ResourceLoader.exists(path):
			_icon_cache[key] = load(path)

func _bind_tooltips() -> void:
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/Location, "当前所在城关或地点")
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/Money, "所持金钱（文）")
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/Fame, "名声：影响招募与事件")
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/Permit, "市舶货引：无引时出海风险极高")
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/PuAttention, "蒲氏关注度：走私/贿赂会抬升，过高易触发缉私")
	_set_chip_tooltip($Panel/Body/VBox/PrimaryRow/Cargo, "货舱装载")
	_set_chip_tooltip($Panel/Body/VBox/VoyageRow/Crew, "船员人数 / 载员上限")
	_set_chip_tooltip($Panel/Body/VBox/VoyageRow/Food, "粮食储备")
	_set_chip_tooltip($Panel/Body/VBox/VoyageRow/Water, "淡水储备")
	_set_chip_tooltip($Panel/Body/VBox/VoyageRow/Ship, "船体耐久")

func _set_chip_tooltip(chip: Node, text: String) -> void:
	if chip:
		chip.tooltip_text = text

func refresh(_port_title: String = "") -> void:
	if not _ready_done:
		return
	var show_voyage := _show_voyage_stats()
	if voyage_row.visible != show_voyage:
		voyage_row.visible = show_voyage
		_apply_layout_height()

	location_value.text = _resolve_location_name()
	_set_value_with_pulse("money", money_value, str(LedgerSystem.get_balance()))
	_set_value_with_pulse("fame", fame_value, str(GameState.fame))

	var has_permit := GameState.has_customs_permit
	var permit_text := "合法" if has_permit else "无引"
	_set_value_with_pulse("permit", permit_value, permit_text)
	permit_value.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.7) if has_permit else Color(0.95, 0.55, 0.45)
	)
	if permit_icon:
		permit_icon.texture = _icon_cache.get("permit_ok" if has_permit else "permit")

	var pu_level := GameState.pu_attention
	var pu_text := _format_pu_attention(pu_level)
	var pu_color := _pu_attention_color(pu_level)
	_set_value_with_pulse("pu", pu_value, pu_text)
	pu_value.add_theme_color_override("font_color", pu_color)
	if pu_icon:
		pu_icon.modulate = pu_color

	var cargo_str := CargoSystem.to_display_string()
	_set_value_with_pulse("cargo", cargo_value, cargo_str if cargo_str != "" else "空")

	if show_voyage:
		_refresh_voyage_stats()

func _refresh_voyage_stats() -> void:
	var crew_text := "%d/%d" % [GameState.crew_count, GameState.max_crew]
	_set_value_with_pulse("crew", crew_value, crew_text)
	_apply_ratio_style(crew_value, crew_icon, crew_meter, float(GameState.crew_count), float(GameState.max_crew))

	var food_text := "%d" % int(GameState.food)
	_set_value_with_pulse("food", food_value, food_text)
	_apply_ratio_style(food_value, food_icon, food_meter, GameState.food, GameState.max_food)

	var water_text := "%d" % int(GameState.water)
	_set_value_with_pulse("water", water_value, water_text)
	_apply_ratio_style(water_value, water_icon, water_meter, GameState.water, GameState.max_water)

	var ship_text := "%d/%d" % [int(GameState.ship_hp), int(GameState.ship_max_hp)]
	_set_value_with_pulse("ship", ship_value, ship_text)
	_apply_ratio_style(ship_value, ship_icon, ship_meter, GameState.ship_hp, GameState.ship_max_hp)

func _show_voyage_stats() -> bool:
	return GameState.has_story_flag("met_lin_boyuan") \
		or GameState.has_story_flag("chapter1_complete")

func _apply_layout_height() -> void:
	var h := get_layout_height()
	offset_bottom = offset_top + h
	if h != _last_height:
		_last_height = h
		layout_changed.emit(h)

func _set_value_with_pulse(key: String, label: Label, new_text: String) -> void:
	if _prev_text.has(key) and _prev_text[key] != new_text:
		_pulse_label(label)
	label.text = new_text
	_prev_text[key] = new_text

func _pulse_label(label: Label) -> void:
	if label == null:
		return
	var label_id := label.get_instance_id()
	var tween: Tween = _pulse_tweens.get(label_id, null)
	if tween and is_instance_valid(tween):
		tween.kill()
	tween = label.create_tween()
	_pulse_tweens[label_id] = tween
	tween.tween_property(label, "modulate", Color(1.35, 1.2, 0.85), 0.06)
	tween.tween_property(label, "modulate", Color.WHITE, 0.12)

func _apply_ratio_style(
	value_lbl: Label,
	icon: TextureRect,
	meter: ColorRect,
	current: float,
	maximum: float
) -> void:
	var color := _ratio_color(current, maximum)
	value_lbl.add_theme_color_override("font_color", color)
	if icon:
		icon.modulate = color
	_update_meter(meter, current, maximum, color)

func _update_meter(meter: ColorRect, current: float, maximum: float, accent: Color) -> void:
	if meter == null:
		return
	var ratio := clampf(current / maximum if maximum > 0.0 else 1.0, 0.0, 1.0)
	meter.pivot_offset = Vector2(0.0, meter.size.y / 2.0)
	meter.scale = Vector2(ratio, 1.0)
	if ratio <= 0.1:
		meter.color = METER_COLOR_DANGER
	elif ratio <= 0.25:
		meter.color = METER_COLOR_WARN
	else:
		meter.color = METER_COLOR_NORMAL
	meter.modulate = accent

func _ratio_color(current: float, maximum: float) -> Color:
	if maximum <= 0.0:
		return VALUE_COLOR_NORMAL
	var ratio := current / maximum
	if ratio <= 0.1:
		return VALUE_COLOR_DANGER
	if ratio <= 0.25:
		return VALUE_COLOR_WARN
	return VALUE_COLOR_NORMAL

func _format_pu_attention(level: int) -> String:
	if level <= 4:
		return "平静"
	if level <= 9:
		return "风声渐起"
	if level <= 14:
		return "暗流涌动"
	return "蒲氏盯梢"

func _pu_attention_color(level: int) -> Color:
	if level <= 4:
		return VALUE_COLOR_NORMAL
	if level <= 9:
		return VALUE_COLOR_WARN
	return VALUE_COLOR_DANGER

func _resolve_location_name() -> String:
	var port_id: String = GameState.last_port
	if port_id == "":
		return "海上"
	var port_data := GameManager.get_port_data(port_id)
	if not port_data.is_empty():
		return port_data.get("name", port_id)
	return port_id