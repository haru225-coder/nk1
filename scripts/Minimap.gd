extends Control

var ship: Node2D
var root: Node
## 雷达比例（屏幕 px / 世界 px）。原 0.02：盘面半径 67 px 合 3350 世界 px，旧刷船处 210—235 只落到离心 4—5 px，
## 正压在本船朱点的脉动圈（半径 6—9 px）底下，盘上看不到敌船（w19-g13 查小地图比例）。w19-g13 镜头拉远到一屏 2560×1440 后
## 改 0.04：盘边 67 px 合约 1675 世界 px，比一屏看得远，敌船遁走离场距离 1500（EnemyCaptainAI.ESCAPE_DIST）合 60 px 仍在盘内；
## 开战刷船处 560—600 合 22—24 px，炮程 760 合 30 px。
var map_scale: float = 0.04
var radar_radius: float = 75.0
var _pulse_phase: float = 0.0
## 子正午北、午正南、卯正东、酉正西——雷达十字旁的纪实短标，不写 NESW。
const CARDINAL := [
	[Vector2(0, -1), "子"],
	[Vector2(1, 0), "卯"],
	[Vector2(0, 1), "午"],
	[Vector2(-1, 0), "酉"],
]

func _ready() -> void:
	# WorldMap 可能是 add_child 到 SeaChart 上的子场景（P4 海战），
	# current_scene 不是 WorldMap 根。沿父链找到含 Ship 的场景根。
	var n: Node = self
	while n:
		if n.has_node("Ship"):
			root = n
			ship = n.get_node("Ship")
			break
		n = n.get_parent()

func _process(delta: float) -> void:
	_pulse_phase = fmod(_pulse_phase + delta, TAU)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(ship):
		return

	var center := Vector2(radar_radius, radar_radius)
	# 熟漆圆盘、泥金圈。本船朱砂，港口泥金，敌船更亮的朱砂。
	draw_circle(center, radar_radius, Color(0.10, 0.07, 0.04, 0.90))
	draw_arc(center, radar_radius - 1.0, 0, TAU, 48, UiTheme.GOLD, 1.5)
	# 两道淡刻线和十字定位，让无目标时也有稳定的航海仪器感。
	draw_arc(center, radar_radius * 0.52, 0, TAU, 40, Color(UiTheme.GOLD, 0.22), 1.0)
	draw_arc(center, radar_radius * 0.78, 0, TAU, 40, Color(UiTheme.GOLD, 0.18), 1.0)
	draw_line(center + Vector2(-radar_radius + 8.0, 0), center + Vector2(radar_radius - 8.0, 0), Color(UiTheme.GOLD, 0.14), 1.0)
	draw_line(center + Vector2(0, -radar_radius + 8.0), center + Vector2(0, radar_radius - 8.0), Color(UiTheme.GOLD, 0.14), 1.0)
	_draw_cardinals(center)

	# 本船脉动一圈，保留朱砂实心点作为视觉锚点。
	var pulse := 0.5 + 0.5 * sin(_pulse_phase * 2.0)
	draw_circle(center, 6.0 + pulse * 3.0, Color(UiTheme.CINNABAR, 0.14 + pulse * 0.10))
	draw_circle(center, 3.5, UiTheme.CINNABAR)

	# Draw ports (Green) and pirates (Red)
	if not is_instance_valid(root):
		return

	# Draw Ports
	if root.has_node("Ports"):
		for port in root.get_node("Ports").get_children():
			# 战斗模式隐藏港口，雷达不画：WorldMap 藏的是父节点 $Ports，子节点自身 visible 仍为真，原判 port.visible 拦不住，
			# 海战雷达照画场景里写死的泉州 / 兴化示意位（与真海图对不上，w19-g13）
			if not port.is_visible_in_tree(): continue
			var pname := ""
			if port.has_meta("port_name"):
				pname = str(port.get_meta("port_name"))
			elif "port_name" in port:
				pname = str(port.get("port_name"))
			_draw_blip(port.global_position, UiTheme.GOLD, pname)

	# Draw Pirates
	for child in root.get_children():
		if child.name.begins_with("PirateShip"):
			_draw_blip(child.global_position, UiTheme.SEAL_HI, "")

func _draw_cardinals(center: Vector2) -> void:
	var fnt: Font = UiTheme.font()
	var r := radar_radius - 14.0
	for entry in CARDINAL:
		var dir: Vector2 = entry[0]
		var ch: String = entry[1]
		var pos := center + dir * r
		var sz := fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		draw_string(fnt, pos - Vector2(sz.x * 0.5, -3.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTheme.GOLD, 0.55))

func _short_port_label(name: String) -> String:
	var t := name.strip_edges()
	if t.ends_with("港"):
		t = t.substr(0, t.length() - 1)
	# 密区只留两字，免得压船标（兴化海口 → 兴化）
	if t.length() > 2:
		t = t.substr(0, 2)
	return t

func _draw_blip(world_pos: Vector2, color: Color, port_name: String = "") -> void:
	var rel_pos := world_pos - ship.global_position
	var map_pos := rel_pos * map_scale
	var center := Vector2(radar_radius, radar_radius)
	var edge_radius := radar_radius - 8.0
	var dist := map_pos.length()
	if dist < 0.001:
		return
	if dist <= edge_radius:
		var alpha := clampf(1.0 - dist / (radar_radius * 2.0), 0.55, 1.0)
		var blip_color := color
		blip_color.a = alpha
		draw_circle(center + map_pos, 2.5, blip_color)
		# 近距港名短标；太贴本船（<18）不写，免得挡朱点
		if port_name != "" and dist >= 18.0 and dist <= edge_radius * 0.92:
			var label := _short_port_label(port_name)
			if label != "":
				var fnt: Font = UiTheme.font()
				var sz := fnt.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
				var lp := center + map_pos + Vector2(4.0, -3.0)
				# 靠右缘时改到左侧，避免出盘
				if lp.x + sz.x > center.x + edge_radius - 2.0:
					lp.x = center.x + map_pos.x - sz.x - 4.0
				draw_string(fnt, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.GOLD, 0.72 * alpha))
		return

	# Off-screen contacts stay legible as small edge chevrons instead of
	# disappearing, while the arrow direction still points toward their bearing.
	var dir := map_pos.normalized()
	var pos := center + dir * edge_radius
	var tangent := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 4.5
	var left := pos - dir * 3.0 + tangent * 3.2
	var right := pos - dir * 3.0 - tangent * 3.2
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
