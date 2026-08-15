class_name MapUiTheme
extends RefCounted

const PAPER := Color(0.85, 0.78, 0.65, 1.0)
const PAPER_DARK := Color(0.75, 0.68, 0.55, 1.0)
const WOOD_BORDER := Color(0.25, 0.18, 0.12, 0.9)
const INK := Color(0.15, 0.12, 0.08, 1.0)
const CINNABAR := Color(0.65, 0.15, 0.15, 1.0)
const DEEP_SEA := Color(0.035, 0.065, 0.092, 1.0)
const BRASS := Color(0.82, 0.62, 0.24, 1.0)
const CHART_TEXT := Color(0.92, 0.86, 0.68, 1.0)
const WEATHER_BLUE := Color(0.55, 0.86, 0.95, 1.0)


static func nautical_hud_style(alpha: float) -> StyleBoxFlat:
	# [豁免] WorldMap HUD alpha 随壳层上下文变化，需从共享样式派生运行时透明度。
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DEEP_SEA.r, DEEP_SEA.g, DEEP_SEA.b, alpha)
	style.border_color = BRASS
	style.set_border_width_all(3)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 8
	style.shadow_offset = Vector2(2, 4)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	return style


static func apply_world_map_hud(
	left_panel: Control,
	right_panel: Control,
	main_label: Control,
	fleet_label: Label,
	weather_label: Label
) -> void:
	var style := nautical_hud_style(0.93)
	for panel in [left_panel, right_panel]:
		if panel:
			# [豁免] WorldMap HUD 透明度随壳层变化，无法由静态 variation 表达。
			panel.add_theme_stylebox_override("panel", style)

	if main_label:
		# [豁免] RichTextLabel 由地图模式在运行时注入，对比色随底图消费者切换。
		main_label.add_theme_color_override("default_color", CHART_TEXT)
	if fleet_label:
		fleet_label.add_theme_color_override("font_color", CHART_TEXT)
		fleet_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.025, 0.95))
		fleet_label.add_theme_constant_override("outline_size", 1)
	if weather_label:
		weather_label.add_theme_color_override("font_color", WEATHER_BLUE)


static func apply_strategic_popup(
	popup: PanelContainer,
	title: Label,
	info: Label,
	buttons: Array
) -> void:
	if popup:
		popup.theme_type_variation = UITheme.MAP_STRATEGIC_POPUP
	if title:
		title.theme_type_variation = UITheme.MAP_STRATEGIC_TITLE
	if info:
		info.theme_type_variation = UITheme.MAP_STRATEGIC_INFO

	for button in buttons:
		if not (button is Button):
			continue
		button.theme_type_variation = UITheme.MAP_STRATEGIC_BUTTON
