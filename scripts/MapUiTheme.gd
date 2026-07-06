class_name MapUiTheme
extends RefCounted

const PAPER := Color(0.85, 0.78, 0.65, 1.0)
const PAPER_DARK := Color(0.75, 0.68, 0.55, 1.0)
const WOOD_BORDER := Color(0.25, 0.18, 0.12, 0.9)
const INK := Color(0.15, 0.12, 0.08, 1.0)
const CINNABAR := Color(0.65, 0.15, 0.15, 1.0)


static func parchment_panel_style(alpha: float) -> StyleBoxFlat:
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


static func apply_world_map_hud(
	left_panel: Control,
	right_panel: Control,
	main_label: Control,
	fleet_label: Label,
	weather_label: Label
) -> void:
	var style := parchment_panel_style(0.90)
	for panel in [left_panel, right_panel]:
		if panel:
			panel.add_theme_stylebox_override("panel", style)

	if main_label:
		main_label.add_theme_color_override("default_color", INK)
	if fleet_label:
		fleet_label.add_theme_color_override("font_color", INK)
	if weather_label:
		weather_label.add_theme_color_override("font_color", INK)


static func apply_strategic_popup(
	popup: PanelContainer,
	title: Label,
	info: Label,
	buttons: Array
) -> void:
	var panel_style := parchment_panel_style(0.95)
	if popup:
		popup.add_theme_stylebox_override("panel", panel_style)
	if title:
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
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = PAPER
	hover.border_color = CINNABAR
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", CINNABAR)
