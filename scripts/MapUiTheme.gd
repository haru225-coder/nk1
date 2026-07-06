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


static func parchment_panel_style(alpha: float) -> StyleBoxFlat:
	# Runtime style: strategic map popup alpha depends on overlay context.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER.r, PAPER.g, PAPER.b, alpha)
	style.border_color = WOOD_BORDER
	style.set_border_width_all(3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 6
	return style


static func nautical_hud_style(alpha: float) -> StyleBoxFlat:
	# Runtime style: world-map HUD alpha must animate separately from main_theme.tres.
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
			# Runtime override: world map HUD fades independently of the shared Theme.
			panel.add_theme_stylebox_override("panel", style)

	if main_label:
		# Runtime override: RichTextLabel needs map-only chart text contrast.
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
	var panel_style := parchment_panel_style(0.95)
	if popup:
		# Runtime override: popup reuses map-only parchment over the strategic chart.
		popup.add_theme_stylebox_override("panel", panel_style)
	if title:
		# Runtime override: popup title is selected-port state, not a global label class.
		title.add_theme_color_override("font_color", CINNABAR)
	if info:
		info.add_theme_color_override("font_color", INK)

	for button in buttons:
		if not (button is Button):
			continue
		_apply_button_theme(button, panel_style)


static func _apply_button_theme(button: Button, panel_style: StyleBoxFlat) -> void:
	var normal := panel_style.duplicate() as StyleBoxFlat
	normal.bg_color = Color(PAPER_DARK.r, PAPER_DARK.g, PAPER_DARK.b, 0.95)
	# Runtime override: strategic map popup buttons inherit the popup frame color.
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER
	hover.border_color = CINNABAR
	# Runtime override: these buttons only exist inside the map popup.
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", CINNABAR)
