class_name MapPortStyle
extends RefCounted

const PORT_MAIN := Color(0.65, 0.15, 0.15, 0.95) # 朱砂红
const PORT_THREAD := Color(0.3, 0.25, 0.2, 0.85) # 浓墨
const PORT_DISTANT := Color(0.4, 0.4, 0.4, 0.6)  # 淡墨
const PORT_LOCKED := Color(0.5, 0.5, 0.45, 0.4)  # 枯墨
const HOVER_RING := Color(0.8, 0.2, 0.2, 0.8)    # 朱砂圈
const LABEL_COLOR := Color(0.1, 0.08, 0.05, 1.0) # 墨黑字
const LABEL_BG := Color(0.85, 0.8, 0.7, 0.85)    # 旧纸黄

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