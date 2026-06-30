class_name MapPortStyle
extends RefCounted

const PORT_MAIN := Color(0.45, 0.92, 0.52, 1.0)
const PORT_THREAD := Color(0.55, 0.78, 0.62, 0.85)
const PORT_DISTANT := Color(0.55, 0.72, 0.82, 0.55)
const PORT_LOCKED := Color(0.42, 0.42, 0.46, 0.55)
const HOVER_RING := Color(0.77, 0.66, 0.36, 0.85)
const LABEL_COLOR := Color(0.95, 0.9, 0.72, 1.0)
const LABEL_BG := Color(0.12, 0.1, 0.06, 0.82)

const ICON_SCALE_WORLD := 0.42
const ICON_SCALE_MINIMAP := 1.0


static func port_color(status: String) -> Color:
	match status:
		"main":
			return PORT_MAIN
		"distant", "rumor":
			return PORT_DISTANT
		"locked":
			return PORT_LOCKED
		_:
			return PORT_THREAD


static func port_modulate(status: String) -> Color:
	return port_color(status)


static func dot_radius(status: String) -> float:
	return 4.0 if status == "main" else 3.0