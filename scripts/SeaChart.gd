extends Control
## 海图。点选目的地 → 按日推进 → 逐日抽事件 → 到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

var origin_port: String = ""
var selected_port: String = ""

## 航行状态
var sailing: bool = false
var remaining_li: float = 0.0
var total_li: float = 0.0
var course_bearing: float = 0.0
var days_elapsed: int = 0
var pending_event: Dictionary = {}

# UI
var status_label: RichTextLabel
var chart: Control
var port_list: VBoxContainer
var detail_box: VBoxContainer
var log_label: RichTextLabel
var sail_button: Button
var event_panel: PanelContainer
var event_title: Label
var event_text: RichTextLabel
var event_actions: HBoxContainer

## 陆地环，x = 经度，y = 纬度。首尾不重复。
var _land_rings: Array = []
var _land_boxes: Array = []
var _land_bins: Array = []
var _land_ready: bool = false
var _lane_frame: Dictionary = {}
var _block_key: String = ""
var _block_cache: Dictionary = {}
var _lane_cache: Dictionary = {}


func _ready() -> void:
	origin_port = GameState.last_port
	selected_port = ""
	_build_ui()
	# 连接放在 _build_ui 之后：_log 依赖其中创建的 log_label
	GameManager.monthly_notice.connect(_log)
	_refresh_ports()
	_refresh_status()
	_log("【发舶】自 %s 起锚。%s。" % [GameManager.get_port_name(origin_port), Calendar.get_monsoon_desc()])


# ══════════════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = GameManager.load_texture("res://assets/bg_world_map.jpg")
	bg.modulate = Color(0.55, 0.6, 0.7, 1.0)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ── 左：状态 ──
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(left)
	var left_m := MarginContainer.new()
	_set_margins(left_m, 10)
	left.add_child(left_m)
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	left_m.add_child(status_label)

	# ── 中：港口与航段 ──
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(center)
	var center_m := MarginContainer.new()
	_set_margins(center_m, 12)
	center.add_child(center_m)
	var center_v := VBoxContainer.new()
	center_v.add_theme_constant_override("separation", 8)
	center_m.add_child(center_v)

	var head := Label.new()
	head.text = "海　图"
	head.add_theme_font_size_override("font_size", 26)
	center_v.add_child(head)

	var hint := Label.new()
	hint.text = "选定去处，量过风信与水粮，再决定发不发舶。"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	center_v.add_child(hint)

	# 真正的图。港口与陆地共用同一套经纬度投影。不缩放拖拽。
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 280)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.size_flags_stretch_ratio = 3.0
	chart.clip_contents = true
	chart.draw.connect(func(): _draw_chart(chart))
	center_v.add_child(chart)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.custom_minimum_size = Vector2(0, 120)
	center_v.add_child(scroll)
	port_list = VBoxContainer.new()
	port_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(port_list)

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	center_v.add_child(detail_box)

	sail_button = Button.new()
	sail_button.text = "发　舶"
	sail_button.custom_minimum_size = Vector2(0, 48)
	sail_button.add_theme_font_size_override("font_size", 20)
	sail_button.disabled = true
	sail_button.pressed.connect(_on_sail_pressed)
	center_v.add_child(sail_button)

	var back := Button.new()
	back.text = "回港（不出海）"
	back.pressed.connect(_return_to_port)
	center_v.add_child(back)

	# ── 右：航海日志 ──
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(right)
	var right_m := MarginContainer.new()
	_set_margins(right_m, 10)
	right.add_child(right_m)
	var right_v := VBoxContainer.new()
	right_m.add_child(right_v)
	var log_head := Label.new()
	log_head.text = "航海日志"
	log_head.add_theme_font_size_override("font_size", 18)
	right_v.add_child(log_head)
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_child(log_scroll)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.custom_minimum_size = Vector2(272, 0)
	log_scroll.add_child(log_label)

	# ── 事件浮层 ──
	_build_event_panel()


func _build_event_panel() -> void:
	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_CENTER)
	event_panel.custom_minimum_size = Vector2(560, 0)
	event_panel.position = Vector2(360, 200)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	st.border_width_left = 2
	st.border_width_top = 2
	st.border_width_right = 2
	st.border_width_bottom = 2
	st.border_color = Color(0.6, 0.5, 0.3)
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_left = 8
	st.corner_radius_bottom_right = 8
	event_panel.add_theme_stylebox_override("panel", st)
	event_panel.visible = false
	add_child(event_panel)

	var m := MarginContainer.new()
	_set_margins(m, 18)
	event_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	event_title = Label.new()
	event_title.add_theme_font_size_override("font_size", 24)
	v.add_child(event_title)

	event_text = RichTextLabel.new()
	event_text.bbcode_enabled = true
	event_text.fit_content = true
	event_text.custom_minimum_size = Vector2(520, 60)
	v.add_child(event_text)

	event_actions = HBoxContainer.new()
	event_actions.add_theme_constant_override("separation", 8)
	v.add_child(event_actions)


func _panel_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.08, 0.11, 0.88)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	return st


func _set_margins(m: MarginContainer, v: int) -> void:
	m.add_theme_constant_override("margin_left", v)
	m.add_theme_constant_override("margin_right", v)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)


# ══════════════════════════════════════════════════════
#  刷新
# ══════════════════════════════════════════════════════

func _refresh_status() -> void:
	var supply_d := Fleet.supply_days()
	var supply_color := "white"
	if supply_d <= 3:
		supply_color = "red"
	elif supply_d <= 7:
		supply_color = "yellow"

	var t := "[b]%s[/b]\n%s\n\n" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()]
	if sailing:
		var pct := 0.0
		if total_li > 0.0:
			pct = clampf((total_li - remaining_li) / total_li, 0.0, 1.0)
		t += "[color=aqua]航行中　第 %d 日[/color]\n已行 %d%%\n余程 %d 里\n\n" % [days_elapsed, int(pct * 100), int(remaining_li)]
	t += "金钱：%d\n名声：%d\n\n" % [GameState.money, GameState.fame]
	t += "[u]舰队[/u]\n船数：%d　水手：%d\n舱位：%d / %d 料\n耐久：%d / %d\n士气：%d\n" % [
		Fleet.ships.size(), Fleet.total_crew(),
		int(Fleet.used_capacity()), int(Fleet.total_capacity()),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水：%d　粮：%d　[color=%s]（足 %d 日）[/color]\n" % [Fleet.water, Fleet.food, supply_color, supply_d]
	status_label.text = t
	# 日期推进会改季风，图上的风向箭头与航段配色随之变
	if chart:
		chart.queue_redraw()


func _refresh_ports() -> void:
	for c in port_list.get_children():
		c.queue_free()

	for p in GameManager.unlocked_ports():
		var pid: String = p.get("id", "")
		if pid == origin_port:
			continue
		# 兴化与海口是陆路可达的剧情点，不列入海图
		if p.get("depth", 0) <= 0:
			continue

		var plan := Voyage.plan(origin_port, pid)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = (pid == selected_port)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 34)

		var known := "" if Voyage.is_known_route(origin_port, pid) else "　[生路]"
		btn.text = "%s　%d里　%s　约 %d 日%s" % [
			p.get("name", pid), int(plan["distance"]), plan["wind_desc"], plan["days"], known,
		]
		if not plan["supply_ok"]:
			btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
		elif plan["wind_desc"] == "顺风":
			btn.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))

		btn.pressed.connect(_on_port_selected.bind(pid))
		port_list.add_child(btn)


func _on_port_selected(pid: String) -> void:
	selected_port = pid
	_refresh_ports()
	_refresh_detail()
	if chart:
		chart.queue_redraw()


func _refresh_detail() -> void:
	for c in detail_box.get_children():
		c.queue_free()
	if selected_port == "":
		sail_button.disabled = true
		return

	var plan := Voyage.plan(origin_port, selected_port)
	var crew_note := ""
	var hz := Crew.level_of("huozhang")
	var dg := Crew.level_of("duogong")
	if hz > 0:
		crew_note += "　火长 +%d%%" % int(round((Crew.speed_factor() - 1.0) * 100))
	if dg > 0 and plan["wind_desc"] in ["斜逆风", "顶头逆风"]:
		crew_note += "　舵工抢风"

	var lines := [
		"目的：%s" % GameManager.get_port_name(selected_port),
		"航程：%d 里　方位 %d°" % [int(plan["distance"]), int(plan["bearing"])],
		"风信：%s（日速 %d 里）%s" % [plan["wind_desc"], int(plan["speed"]), crew_note],
		"预计：%d 日　水粮足 %d 日" % [plan["days"], plan["supply_days"]],
	]
	for l in lines:
		var lbl := Label.new()
		lbl.text = l
		detail_box.add_child(lbl)

	if not Voyage.is_known_route(origin_port, selected_port):
		var w := Label.new()
		w.text = "此非熟路，海图上只有传闻，途中易生变故。"
		w.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		detail_box.add_child(w)

	if not plan["supply_ok"]:
		var w := Label.new()
		w.text = "水粮不足以支撑此程——半途必要死人。"
		w.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		detail_box.add_child(w)

	sail_button.disabled = false


# ══════════════════════════════════════════════════════
#  海图绘制
# ══════════════════════════════════════════════════════

## 取景不会缩得比这一圈更小，也不会画出这一圈外的陆地。
const CHART_LAT_MIN := 10.0
const CHART_LAT_MAX := 37.0
const CHART_LON_MIN := 105.0
const CHART_LON_MAX := 134.0
const CHART_MIN_SPAN := 8.0
## 已解锁港口的包围盒占取景框的比例，剩下的边留给海岸和港名字。
const CHART_FRAME_FILL := 0.80
## 航线绕陆用的格子。只影响画法，里程仍按港口间的直线。
const LANE_CELL := 0.24
const LANE_INSET := 0.15
const LANE_HARBOR := 0.22
const LANE_SAMPLE := 0.10
const LANE_DEDUP := 0.08
const LANE_SHORE_PENALTY := 0.15
## 屏幕上近过这个距离的港名合成一列，避免叠字。
const LABEL_CLUSTER_PX := 18.0

const CHART_MARGIN := Color(0.04, 0.055, 0.07, 1.0)
const CHART_SEA := Color(0.07, 0.175, 0.25, 1.0)
const CHART_SHOAL := Color(0.20, 0.45, 0.54, 1.0)
const CHART_LAND := Color(0.78, 0.71, 0.54, 1.0)
const CHART_COAST := Color(0.29, 0.23, 0.16, 1.0)
const CHART_INK := Color(0.22, 0.17, 0.12, 1.0)
const CHART_HALO := Color(0.96, 0.93, 0.84, 0.92)
const CHART_GRID := Color(0.82, 0.74, 0.55, 0.18)
const CHART_FRAME := Color(0.82, 0.74, 0.55, 0.88)
const CHART_VERMILION := Color(0.72, 0.24, 0.16, 1.0)
const CHART_GOLD := Color(0.62, 0.44, 0.12, 1.0)


## 等比投影。经度按平均纬度收窄，否则高纬处会被拉宽。
## 取景至少 8 个经纬度，并留出边，所以福建几个港也能看见海峡和台湾。
func _draw_chart(c: Control) -> void:
	var pts: Array = GameManager.unlocked_ports()
	if pts.is_empty() or c.size.x < 2.0 or c.size.y < 2.0:
		return

	_ensure_land()
	var frame := _chart_frame(pts)
	var lat_min: float = frame["lat_min"]
	var lat_max: float = frame["lat_max"]
	var lon_min: float = frame["lon_min"]
	var lon_max: float = frame["lon_max"]

	var mean_lat := (lat_min + lat_max) * 0.5
	var mean_lon := (lon_min + lon_max) * 0.5
	var kx := cos(deg_to_rad(mean_lat))
	var span_x := maxf(0.5, (lon_max - lon_min) * kx)
	var span_y := maxf(0.5, lat_max - lat_min)

	var size := c.size
	var scale := minf(size.x / span_x, size.y / span_y)
	var mid := size * 0.5

	var proj := func(lat: float, lon: float) -> Vector2:
		return mid + Vector2((lon - mean_lon) * kx * scale, -(lat - mean_lat) * scale)

	var top_left: Vector2 = proj.call(lat_max, lon_min)
	var bottom_right: Vector2 = proj.call(lat_min, lon_max)
	var map_rect := Rect2(top_left, bottom_right - top_left).abs()

	c.draw_rect(Rect2(Vector2.ZERO, size), CHART_MARGIN)
	c.draw_rect(map_rect, CHART_SEA)
	_draw_graticule(c, proj, lat_min, lat_max, lon_min, lon_max)
	_draw_monsoon(c, map_rect)
	_draw_land(c, proj, lon_min, lat_min, lon_max, lat_max, scale)
	# 航程仍按直线里程。弯线只是躲开陆地的画法。
	_draw_known_routes(c, proj, pts, frame)

	if selected_port != "":
		var o := GameManager.get_port_by_id(origin_port)
		var d := GameManager.get_port_by_id(selected_port)
		if not o.is_empty() and not d.is_empty():
			var lane := _sea_lane(
				float(o.get("lon", 0.0)), float(o.get("lat", 0.0)),
				float(d.get("lon", 0.0)), float(d.get("lat", 0.0)), frame)
			var screen := _project_lane(proj, lane)
			var wf := Voyage.wind_factor(Voyage.bearing(origin_port, selected_port))
			var col := CHART_GOLD
			if wf >= 1.15:
				col = Color(0.18, 0.48, 0.32)
			elif wf <= 0.75:
				col = CHART_VERMILION
			# 顺风绿、逆风朱、侧风金。浅色垫底，浅滩上也看得见。
			_draw_lane_solid(c, screen, Color(0.96, 0.93, 0.84, 0.85), 4.5)
			_draw_lane_solid(c, screen, col, 2.2)

	var port_pts: Array = []
	for p in pts:
		port_pts.append(proj.call(float(p.get("lat", 0.0)), float(p.get("lon", 0.0))))
	_draw_sea_names(c, proj, lat_min, lat_max, lon_min, lon_max, port_pts)
	_draw_compass(c, map_rect, port_pts)
	_draw_ports(c, proj, pts, port_pts, map_rect)

	_draw_chart_frame(c, map_rect)
	_draw_monsoon_caption(c, map_rect)


func _chart_frame(pts: Array) -> Dictionary:
	var lat_lo := 999.0
	var lat_hi := -999.0
	var lon_lo := 999.0
	var lon_hi := -999.0
	for p in pts:
		var lat := float(p.get("lat", 0.0))
		var lon := float(p.get("lon", 0.0))
		lat_lo = minf(lat_lo, lat)
		lat_hi = maxf(lat_hi, lat)
		lon_lo = minf(lon_lo, lon)
		lon_hi = maxf(lon_hi, lon)
	var lat_pair: Array = _expand_axis(lat_lo, lat_hi, CHART_LAT_MIN, CHART_LAT_MAX)
	var lon_pair: Array = _expand_axis(lon_lo, lon_hi, CHART_LON_MIN, CHART_LON_MAX)
	return {
		"lat_min": lat_pair[0],
		"lat_max": lat_pair[1],
		"lon_min": lon_pair[0],
		"lon_max": lon_pair[1],
	}


func _expand_axis(lo: float, hi: float, bound_lo: float, bound_hi: float) -> Array:
	var mid := (lo + hi) * 0.5
	var half := maxf(CHART_MIN_SPAN, hi - lo) * 0.5 / CHART_FRAME_FILL
	lo = mid - half
	hi = mid + half
	if hi - lo > bound_hi - bound_lo:
		return [bound_lo, bound_hi]
	if lo < bound_lo:
		var shift: float = bound_lo - lo
		lo += shift
		hi += shift
	if hi > bound_hi:
		var shift_hi: float = hi - bound_hi
		lo -= shift_hi
		hi -= shift_hi
	return [maxf(lo, bound_lo), minf(hi, bound_hi)]


func _ensure_land() -> void:
	if _land_ready:
		return
	_land_ready = true
	for land in GameManager.coastline_data.get("lands", []):
		var ring := PackedVector2Array()
		for pt in land.get("ring", []):
			if typeof(pt) != TYPE_ARRAY or pt.size() < 2:
				continue
			ring.append(Vector2(float(pt[0]), float(pt[1])))
		if ring.size() >= 2 and ring[0].is_equal_approx(ring[ring.size() - 1]):
			ring.resize(ring.size() - 1)
		if ring.size() >= 3:
			_land_rings.append(ring)
			_land_boxes.append(_ring_box(ring))
			_land_bins.append(_ring_bins(ring))


func _ring_box(ring: PackedVector2Array) -> Rect2:
	var x0 := ring[0].x
	var x1 := ring[0].x
	var y0 := ring[0].y
	var y1 := ring[0].y
	for p in ring:
		x0 = minf(x0, p.x)
		x1 = maxf(x1, p.x)
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func _ring_bins(ring: PackedVector2Array) -> Dictionary:
	var edge_bins := {}
	var n := ring.size()
	for i in n:
		var ya: float = ring[i].y
		var yb: float = ring[(i + 1) % n].y
		var lo := int(floor(minf(ya, yb))) - 6
		var hi := int(floor(maxf(ya, yb))) - 6
		for b in range(lo, hi + 1):
			var edges: PackedInt32Array = edge_bins.get(b, PackedInt32Array())
			edges.append(i)
			edge_bins[b] = edges
	return edge_bins


func _draw_land(c: Control, proj: Callable, lon0: float, lat0: float, lon1: float, lat1: float, scale: float) -> void:
	var view := PackedVector2Array([
		Vector2(lon0, lat0),
		Vector2(lon1, lat0),
		Vector2(lon1, lat1),
		Vector2(lon0, lat1),
	])
	for ring in _land_rings:
		if not _ring_hits(ring, lon0, lat0, lon1, lat1):
			continue
		# 浅滩跟着比例尺走，小岛才不会被一圈固定的宽笔涂成饼。
		var shoal_w := clampf(scale * 0.11, 3.0, 7.5)
		_stroke_coast(c, proj, ring, lon0, lat0, lon1, lat1, CHART_SHOAL, shoal_w)
		var pieces: Array = Geometry2D.intersect_polygons(ring, view)
		for piece in pieces:
			var outline := PackedVector2Array(piece)
			if outline.size() >= 2 and outline[0].is_equal_approx(outline[outline.size() - 1]):
				outline.resize(outline.size() - 1)
			if outline.size() < 3:
				continue
			var screen := PackedVector2Array()
			screen.resize(outline.size())
			for i in outline.size():
				var ll: Vector2 = outline[i]
				screen[i] = proj.call(ll.y, ll.x)
			_fill_polygon(c, screen)
		_stroke_coast(c, proj, ring, lon0, lat0, lon1, lat1, CHART_COAST, 1.4)


func _fill_polygon(c: Control, screen: PackedVector2Array) -> void:
	var idx := Geometry2D.triangulate_polygon(screen)
	if idx.is_empty():
		screen.reverse()
		idx = Geometry2D.triangulate_polygon(screen)
	if idx.is_empty():
		return
	var tri := PackedVector2Array()
	tri.resize(3)
	var i := 0
	while i + 2 < idx.size():
		tri[0] = screen[idx[i]]
		tri[1] = screen[idx[i + 1]]
		tri[2] = screen[idx[i + 2]]
		c.draw_colored_polygon(tri, CHART_LAND)
		i += 3


func _ring_hits(ring: PackedVector2Array, lon0: float, lat0: float, lon1: float, lat1: float) -> bool:
	var rlon0 := ring[0].x
	var rlon1 := ring[0].x
	var rlat0 := ring[0].y
	var rlat1 := ring[0].y
	for p in ring:
		rlon0 = minf(rlon0, p.x)
		rlon1 = maxf(rlon1, p.x)
		rlat0 = minf(rlat0, p.y)
		rlat1 = maxf(rlat1, p.y)
	return rlon1 >= lon0 and rlon0 <= lon1 and rlat1 >= lat0 and rlat0 <= lat1


func _stroke_coast(c: Control, proj: Callable, ring: PackedVector2Array, lon0: float, lat0: float, lon1: float, lat1: float, color: Color, width: float) -> void:
	var run := PackedVector2Array()
	var n := ring.size()
	for i in n:
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		var clipped: Array = _clip_segment(a, b, lon0, lat0, lon1, lat1)
		if clipped.is_empty():
			_flush_coast(c, run, color, width)
			run = PackedVector2Array()
			continue
		var p0: Vector2 = proj.call(clipped[0].y, clipped[0].x)
		var p1: Vector2 = proj.call(clipped[1].y, clipped[1].x)
		if run.is_empty() or run[run.size() - 1].distance_to(p0) > 0.75:
			_flush_coast(c, run, color, width)
			run = PackedVector2Array()
			run.append(p0)
		run.append(p1)
	_flush_coast(c, run, color, width)


func _flush_coast(c: Control, run: PackedVector2Array, color: Color, width: float) -> void:
	if run.size() >= 2:
		c.draw_polyline(run, color, width, true)


func _draw_graticule(c: Control, proj: Callable, lat0: float, lat1: float, lon0: float, lon1: float) -> void:
	var step := 5.0 if (lat1 - lat0) > 16.0 else 2.0
	var lat: float = ceil(lat0 / step) * step
	while lat < lat1 - 0.05:
		c.draw_line(proj.call(lat, lon0), proj.call(lat, lon1), CHART_GRID, 1.0)
		lat += step
	var lon: float = ceil(lon0 / step) * step
	while lon < lon1 - 0.05:
		c.draw_line(proj.call(lat0, lon), proj.call(lat1, lon), CHART_GRID, 1.0)
		lon += step


func _draw_chart_frame(c: Control, map_rect: Rect2) -> void:
	c.draw_rect(map_rect, CHART_FRAME, false, 1.25)
	c.draw_rect(map_rect.grow(-4.0), Color(CHART_FRAME.r, CHART_FRAME.g, CHART_FRAME.b, 0.45), false, 1.0)
	var tick := 5.0
	var corners: Array[Vector2] = [
		map_rect.position,
		Vector2(map_rect.end.x, map_rect.position.y),
		map_rect.end,
		Vector2(map_rect.position.x, map_rect.end.y),
	]
	for corner in corners:
		c.draw_rect(Rect2(corner - Vector2(tick, tick) * 0.5, Vector2(tick, tick)), CHART_FRAME)


func _draw_port_mark(c: Control, v: Vector2, mark: Color, emphasized: bool, filled: bool) -> void:
	var r := 5.2 if emphasized else 3.6
	c.draw_circle(v, r + 1.6, CHART_HALO)
	c.draw_arc(v, r, 0.0, TAU, 20, mark, 1.5)
	if filled:
		c.draw_circle(v, r - 2.0, mark)
	else:
		c.draw_circle(v, 1.3, mark)


func _draw_ink(c: Control, font: Font, pos: Vector2, text: String, col: Color, font_size: int, halo: Color = CHART_HALO) -> void:
	for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1)]:
		c.draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, halo)
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_known_routes(c: Control, proj: Callable, pts: Array, frame: Dictionary) -> void:
	var route_col := Color(0.90, 0.82, 0.62, 0.38)
	var drawn := {}
	for p in pts:
		var pid: String = p.get("id", "")
		for cid in p.get("connections", []):
			var q := GameManager.get_port_by_id(cid)
			if q.is_empty() or not GameState.is_chapter_reached(q.get("unlock", "ch1")):
				continue
			var other: String = str(cid)
			var key := pid + "|" + other if pid < other else other + "|" + pid
			if drawn.has(key):
				continue
			drawn[key] = true
			var lane := _sea_lane(
				float(p.get("lon", 0.0)), float(p.get("lat", 0.0)),
				float(q.get("lon", 0.0)), float(q.get("lat", 0.0)), frame)
			_draw_dashed_poly(c, _project_lane(proj, lane), route_col, 1.0, 5.0, 4.0)


func _draw_ports(c: Control, proj: Callable, pts: Array, screen: Array, map_rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12
	var ascent := font.get_ascent(font_size)
	var n := pts.size()
	var parent: Array = []
	parent.resize(n)
	for i in n:
		parent[i] = i
		var pid: String = pts[i].get("id", "")
		var here := pid == origin_port
		var target := pid == selected_port
		var visited: bool = pid in GameState.visited_ports
		var mark := CHART_INK
		if target:
			mark = CHART_GOLD
		if here:
			mark = CHART_VERMILION
		_draw_port_mark(c, screen[i], mark, here or target, visited or here or target)
	for i in n:
		for j in range(i + 1, n):
			if screen[i].distance_to(screen[j]) < LABEL_CLUSTER_PX:
				_uf_union(parent, i, j)
	var groups := {}
	for i in n:
		var root := _uf_find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(i)
	var clusters: Array = []
	var singles: Array = []
	for key in groups:
		var members: Array = groups[key]
		if members.size() >= 2:
			clusters.append(members)
		else:
			singles.append(members[0])
	clusters.sort_custom(func(a, b): return a.size() > b.size())
	var spots: Array = []
	var bounds := map_rect.grow(-4.0)
	var ink_line := Color(CHART_INK.r, CHART_INK.g, CHART_INK.b, 0.55)
	for members in clusters:
		members.sort_custom(func(a, b):
			return float(pts[a].get("lat", 0.0)) > float(pts[b].get("lat", 0.0))
		)
		var member_set := {}
		var sizes: Array = []
		var max_w := 0.0
		var total_h := 0.0
		var lon := 0.0
		var lat := 0.0
		var max_x := -1e9
		var min_x := 1e9
		var mean_y := 0.0
		for i in members:
			member_set[i] = true
			var text: String = pts[i].get("name", "")
			var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			sizes.append(sz)
			max_w = maxf(max_w, sz.x)
			total_h += sz.y
			lon += float(pts[i].get("lon", 0.0))
			lat += float(pts[i].get("lat", 0.0))
			max_x = maxf(max_x, screen[i].x)
			min_x = minf(min_x, screen[i].x)
			mean_y += screen[i].y
		var count := float(members.size())
		lon /= count
		lat /= count
		mean_y /= count
		total_h += 2.0 * float(members.size() - 1)
		var sea := _seaward_sign(lon, lat)
		var best_cost := 1.0e9
		var best_side := sea
		var best_xs: Array = []
		var best_rects: Array = []
		var found := false
		for side in [sea, -sea]:
			for shift in [0.0, -16.0, 16.0, -32.0, 32.0, -48.0, 48.0, -64.0, 64.0]:
				var laid: Dictionary = _column_layout(side, shift, max_x, min_x, mean_y, max_w, total_h, sizes, bounds)
				var rects: Array = laid["rects"]
				var blocked := false
				for rect in rects:
					if _rect_hits(rect, spots, 1.0) or _covers_port(rect, screen, member_set, 5.0):
						blocked = true
						break
				if blocked:
					continue
				var cost := absf(shift) + (0.0 if is_equal_approx(side, sea) else 6.0)
				if not found or cost < best_cost:
					found = true
					best_cost = cost
					best_side = side
					best_xs = laid["xs"]
					best_rects = rects
			if found and best_cost < 6.0:
				break
		if not found:
			var laid_fallback: Dictionary = _column_layout(sea, 0.0, max_x, min_x, mean_y, max_w, total_h, sizes, bounds)
			best_side = sea
			best_xs = laid_fallback["xs"]
			best_rects = laid_fallback["rects"]
		for k in members.size():
			var i: int = members[k]
			var rect: Rect2 = best_rects[k]
			spots.append(rect)
			var text: String = pts[i].get("name", "")
			var attach := Vector2(rect.position.x if best_side > 0.0 else rect.end.x, rect.position.y + rect.size.y * 0.5)
			_draw_leader(c, screen[i], attach, ink_line)
			var col := _port_ink(pts[i].get("id", ""))
			_draw_ink(c, font, Vector2(best_xs[k], rect.position.y + ascent), text, col, font_size)
	for i in singles:
		var text: String = pts[i].get("name", "")
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var anchor: Vector2 = screen[i]
		var sea := _seaward_sign(float(pts[i].get("lon", 0.0)), float(pts[i].get("lat", 0.0)))
		var cands: Array[Vector2] = []
		for dist in [8.0, 22.0, 36.0]:
			var sea_x: float = anchor.x + sea * float(dist) - (0.0 if sea > 0.0 else sz.x)
			var back_x: float = anchor.x - sea * float(dist) - (sz.x if sea > 0.0 else 0.0)
			cands.append(Vector2(sea_x, anchor.y - sz.y * 0.5))
			cands.append(Vector2(sea_x, anchor.y + 4.0))
			cands.append(Vector2(sea_x, anchor.y - sz.y - 2.0))
			cands.append(Vector2(back_x, anchor.y - sz.y * 0.5))
			cands.append(Vector2(anchor.x - sz.x * 0.5, anchor.y - sz.y - dist))
			cands.append(Vector2(anchor.x - sz.x * 0.5, anchor.y + dist))
		var best := Vector2(anchor.x + 8.0, anchor.y - sz.y * 0.5)
		var best_cost := 1.0e9
		var own := {i: true}
		for cand in cands:
			var rect := Rect2(cand, sz)
			if not bounds.encloses(rect):
				continue
			var cost := 0.0
			if _rect_hits(rect, spots, 2.0):
				cost += 50.0
			if _covers_port(rect, screen, own, 5.0):
				cost += 80.0
			if sea > 0.0 and cand.x < anchor.x:
				cost += 3.0
			if sea < 0.0 and cand.x + sz.x > anchor.x:
				cost += 3.0
			if cost < best_cost:
				best_cost = cost
				best = cand
				if cost == 0.0:
					break
		var placed := Rect2(best, sz)
		spots.append(placed)
		_draw_ink(c, font, Vector2(best.x, best.y + ascent), text, _port_ink(pts[i].get("id", "")), font_size)


func _port_ink(pid: String) -> Color:
	if pid == origin_port:
		return CHART_VERMILION
	if pid == selected_port:
		return CHART_GOLD
	return CHART_INK


func _draw_leader(c: Control, anchor: Vector2, attach: Vector2, color: Color) -> void:
	var delta := attach - anchor
	if delta.length() <= 8.0:
		return
	c.draw_line(anchor + delta.normalized() * 6.0, attach, color, 1.0, true)


func _column_layout(side: float, shift: float, max_x: float, min_x: float, mean_y: float, max_w: float, total_h: float, sizes: Array, bounds: Rect2) -> Dictionary:
	var left := max_x + 12.0 if side > 0.0 else min_x - 12.0 - max_w
	var top := mean_y - total_h * 0.5 + shift
	left = clampf(left, bounds.position.x, maxf(bounds.position.x, bounds.end.x - max_w))
	top = clampf(top, bounds.position.y, maxf(bounds.position.y, bounds.end.y - total_h))
	var xs: Array = []
	var rects: Array = []
	var y := top
	for sz in sizes:
		var x: float = left if side > 0.0 else left + max_w - sz.x
		xs.append(x)
		rects.append(Rect2(Vector2(x, y), sz))
		y += sz.y + 2.0
	return {"xs": xs, "rects": rects}


func _rect_hits(rect: Rect2, spots: Array, pad: float) -> bool:
	var grow := rect.grow(pad)
	for prev in spots:
		if grow.intersects(prev):
			return true
	return false


func _covers_port(rect: Rect2, screen: Array, members: Dictionary, pad: float) -> bool:
	var grow := rect.grow(pad)
	for i in screen.size():
		if members.has(i):
			continue
		var p: Vector2 = screen[i]
		if p.x >= grow.position.x and p.x <= grow.end.x and p.y >= grow.position.y and p.y <= grow.end.y:
			return true
	return false


func _seaward_sign(lon: float, lat: float) -> float:
	var east := 0
	var west := 0
	for dist in [0.4, 0.85, 1.3]:
		var d := float(dist)
		if not _on_land(lon + d, lat):
			east += 1
		if not _on_land(lon - d, lat):
			west += 1
	if east > west:
		return 1.0
	if west > east:
		return -1.0
	return 1.0


func _uf_find(parent: Array, i: int) -> int:
	var root := i
	while int(parent[root]) != root:
		root = int(parent[root])
	var cursor := i
	while cursor != root:
		var nxt := int(parent[cursor])
		parent[cursor] = root
		cursor = nxt
	return root


func _uf_union(parent: Array, a: int, b: int) -> void:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra != rb:
		parent[rb] = ra


func _project_lane(proj: Callable, lane: PackedVector2Array) -> PackedVector2Array:
	var screen := PackedVector2Array()
	screen.resize(lane.size())
	for i in lane.size():
		var ll: Vector2 = lane[i]
		screen[i] = proj.call(ll.y, ll.x)
	return screen


func _draw_dashed_poly(c: Control, pts: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var draw_on := true
	var remain := dash
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dist := a.distance_to(b)
		if dist < 0.5:
			continue
		var dir := (b - a) / dist
		var t := 0.0
		while t < dist:
			var step := minf(remain, dist - t)
			if draw_on and step > 0.15:
				c.draw_line(a + dir * t, a + dir * (t + step), color, width, true)
			t += step
			remain -= step
			if remain <= 0.01:
				draw_on = not draw_on
				remain = dash if draw_on else gap


func _draw_lane_solid(c: Control, pts: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(1, pts.size() - 1):
		c.draw_circle(pts[i], width * 0.45, color)
	for i in pts.size() - 1:
		c.draw_line(pts[i], pts[i + 1], color, width, true)


func _sea_lane(alon: float, alat: float, blon: float, blat: float, frame: Dictionary) -> PackedVector2Array:
	_prepare_lane_frame(frame)
	var cache_key := "%s|%.4f|%.4f|%.4f|%.4f" % [_block_key, alon, alat, blon, blat]
	if _lane_cache.has(cache_key):
		return _lane_cache[cache_key]
	var built := _sea_lane_build(Vector2(alon, alat), Vector2(blon, blat))
	_lane_cache[cache_key] = built
	return built


func _prepare_lane_frame(frame: Dictionary) -> void:
	var key := "%.3f|%.3f|%.3f|%.3f" % [
		float(frame["lat_min"]), float(frame["lat_max"]),
		float(frame["lon_min"]), float(frame["lon_max"])]
	if key == _block_key:
		return
	_block_key = key
	_lane_frame = frame
	_block_cache = {}
	_lane_cache = {}


func _sea_lane_build(a: Vector2, b: Vector2) -> PackedVector2Array:
	if _line_clear(a, b, [a, b]):
		return PackedVector2Array([a, b])
	var start = _nearest_water(a.x, a.y, b)
	var goal = _nearest_water(b.x, b.y, a)
	var path: Array = _astar(start, goal)
	if path.is_empty():
		return PackedVector2Array([a, b])
	var pts: Array = []
	for cell in path:
		var iv: Vector2i = cell
		pts.append(Vector2((float(iv.x) + 0.5) * LANE_CELL, (float(iv.y) + 0.5) * LANE_CELL))
	pts = _shortcut(pts, [a, b])
	var full: Array = [a]
	for p in pts:
		var pv: Vector2 = p
		var last: Vector2 = full[full.size() - 1]
		if last.distance_to(pv) > LANE_DEDUP:
			full.append(pv)
	var tail: Vector2 = full[full.size() - 1]
	if tail.distance_to(b) > LANE_DEDUP:
		full.append(b)
	else:
		full[full.size() - 1] = b
	full = _shortcut(full, [a, b])
	var packed := PackedVector2Array()
	for p in full:
		packed.append(p)
	return packed


func _cell_inside(lon: float, lat: float) -> bool:
	return (
		lon >= float(_lane_frame["lon_min"]) + LANE_INSET
		and lon <= float(_lane_frame["lon_max"]) - LANE_INSET
		and lat >= float(_lane_frame["lat_min"]) + LANE_INSET
		and lat <= float(_lane_frame["lat_max"]) - LANE_INSET
	)


func _cell_blocked(ix: int, iy: int) -> bool:
	var key := Vector2i(ix, iy)
	if _block_cache.has(key):
		return _block_cache[key]
	var lon := (float(ix) + 0.5) * LANE_CELL
	var lat := (float(iy) + 0.5) * LANE_CELL
	var bad := (not _cell_inside(lon, lat)) or _on_land(lon, lat)
	_block_cache[key] = bad
	return bad


func _nearest_water(lon: float, lat: float, toward: Vector2):
	var ix := int(floor(lon / LANE_CELL))
	var iy := int(floor(lat / LANE_CELL))
	if not _cell_blocked(ix, iy):
		return Vector2i(ix, iy)
	var best = null
	var best_score := 1.0e9
	var vx := toward.x - lon
	var vy := toward.y - lat
	var vl := sqrt(vx * vx + vy * vy)
	if vl < 0.0001:
		vl = 1.0
	for rad in range(1, 14):
		var found := false
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var cx := ix + dx
				var cy := iy + dy
				if _cell_blocked(cx, cy):
					continue
				found = true
				var clon := (float(cx) + 0.5) * LANE_CELL
				var clat := (float(cy) + 0.5) * LANE_CELL
				var align := ((clon - lon) * vx + (clat - lat) * vy) / vl
				var score := sqrt((clon - lon) * (clon - lon) + (clat - lat) * (clat - lat)) - align * 0.35
				if score < best_score:
					best_score = score
					best = Vector2i(cx, cy)
		if found and best != null and rad >= 2:
			break
	return best


func _astar(start, goal) -> Array:
	if start == null or goal == null:
		return []
	var s: Vector2i = start
	var gcell: Vector2i = goal
	if s == gcell:
		return [s]
	var heap: Array = []
	_heap_push(heap, [_cell_h(s, gcell), 0.0, s.x, s.y])
	var came := {}
	var cost := {s: 0.0}
	var seen := 0
	while not heap.is_empty():
		var item: Array = _heap_pop(heap)
		var g: float = item[1]
		var x := int(item[2])
		var y := int(item[3])
		var here := Vector2i(x, y)
		if here == gcell:
			var path: Array = [here]
			while came.has(here):
				here = came[here]
				path.append(here)
			path.reverse()
			return path
		var known: float = cost.get(Vector2i(x, y), 1.0e18)
		if g > known + 0.000001:
			continue
		seen += 1
		if seen > 20000:
			return []
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = x + int(dx)
				var ny: int = y + int(dy)
				if _cell_blocked(nx, ny):
					continue
				if dx != 0 and dy != 0 and (_cell_blocked(x + dx, y) or _cell_blocked(x, y + dy)):
					continue
				var step := sqrt(float(dx * dx + dy * dy))
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _cell_blocked(nx + off.x, ny + off.y):
						step += LANE_SHORE_PENALTY
						break
				var ng := g + step
				var nxt := Vector2i(nx, ny)
				if ng < float(cost.get(nxt, 1.0e18)):
					cost[nxt] = ng
					came[nxt] = Vector2i(x, y)
					_heap_push(heap, [ng + _cell_h(nxt, gcell), ng, nx, ny])
	return []


func _cell_h(a: Vector2i, b: Vector2i) -> float:
	return sqrt(float((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)))


func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var tmp = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var smaller := left
		if right < heap.size() and float(heap[right][0]) < float(heap[left][0]):
			smaller = right
		if float(heap[i][0]) <= float(heap[smaller][0]):
			break
		var tmp = heap[i]
		heap[i] = heap[smaller]
		heap[smaller] = tmp
		i = smaller
	return top


func _line_clear(a: Vector2, b: Vector2, ends: Array) -> bool:
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceil(dist / LANE_SAMPLE)))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var near := false
		for e in ends:
			if p.distance_to(e) < LANE_HARBOR:
				near = true
				break
		if near:
			continue
		if _on_land(p.x, p.y):
			return false
	return true


func _shortcut(pts: Array, ends: Array) -> Array:
	if pts.size() <= 2:
		return pts
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _line_clear(pts[i], pts[j], ends):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func _draw_sea_names(c: Control, proj: Callable, lat0: float, lat1: float, lon0: float, lon1: float, port_pts: Array) -> void:
	# 只用宋时已有的海名，并且只写在开阔水面上。
	var names := [
		{"name": "东海", "lat": 27.6, "lon": 123.5},
		{"name": "南海", "lat": 15.4, "lon": 113.6},
	]
	var font := ThemeDB.fallback_font
	var col := Color(0.78, 0.88, 0.92, 0.72)
	for item in names:
		var lat := float(item["lat"])
		var lon := float(item["lon"])
		if lat < lat0 or lat > lat1 or lon < lon0 or lon > lon1:
			continue
		if _on_land(lon, lat):
			continue
		var v: Vector2 = proj.call(lat, lon)
		var near_port := false
		for p in port_pts:
			if v.distance_to(p) < 42.0:
				near_port = true
				break
		if near_port:
			continue
		var text: String = item["name"]
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		_draw_ink(c, font, v - Vector2(sz.x * 0.5, 0), text, col, 15, Color(0.04, 0.08, 0.12, 0.75))


func _on_land(lon: float, lat: float) -> bool:
	var bi := int(floor(lat)) - 6
	for r in _land_rings.size():
		var box: Rect2 = _land_boxes[r]
		if lon < box.position.x or lon > box.end.x or lat < box.position.y or lat > box.end.y:
			continue
		var edge_bins: Dictionary = _land_bins[r]
		if not edge_bins.has(bi):
			continue
		var edges: PackedInt32Array = edge_bins[bi]
		if edges.is_empty():
			continue
		var ring: PackedVector2Array = _land_rings[r]
		var n := ring.size()
		var inside := false
		for i in edges:
			var j := (int(i) + 1) % n
			var yi: float = ring[i].y
			var yj: float = ring[j].y
			if (yi > lat) != (yj > lat):
				var xi: float = ring[i].x
				var xj: float = ring[j].x
				if lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
					inside = not inside
		if inside:
			return true
	return false


func _draw_compass(c: Control, map_rect: Rect2, port_pts: Array) -> void:
	var spots: Array[Vector2] = [
		map_rect.end + Vector2(-48, -48),
		Vector2(map_rect.position.x + 48, map_rect.end.y - 48),
		map_rect.position + Vector2(48, 52),
		Vector2(map_rect.end.x - 48, map_rect.position.y + 52),
	]
	var center: Vector2 = spots[0]
	for s in spots:
		var clear := true
		for p in port_pts:
			if s.distance_to(p) < 58.0:
				clear = false
				break
		if clear:
			center = s
			break
	var gold := Color(0.90, 0.82, 0.60, 0.95)
	var dim := Color(0.90, 0.82, 0.60, 0.45)
	c.draw_circle(center, 18.0, Color(0.05, 0.10, 0.14, 0.55))
	c.draw_arc(center, 15.0, 0.0, TAU, 28, dim, 1.0)
	c.draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), dim, 1.0)
	c.draw_line(center + Vector2(0, 11), center + Vector2(0, -14), gold, 1.4)
	var tip := center + Vector2(0, -16)
	c.draw_colored_polygon(PackedVector2Array([
		tip, tip + Vector2(-3.6, 7.5), tip + Vector2(3.6, 7.5)
	]), gold)
	var font := ThemeDB.fallback_font
	_draw_ink(c, font, tip + Vector2(-6, -13), "北", gold, 12, Color(0.04, 0.08, 0.12, 0.8))


func _out_code(lon: float, lat: float, lon0: float, lat0: float, lon1: float, lat1: float) -> int:
	var code := 0
	if lon < lon0:
		code |= 1
	elif lon > lon1:
		code |= 2
	if lat < lat0:
		code |= 4
	elif lat > lat1:
		code |= 8
	return code


func _clip_segment(a: Vector2, b: Vector2, lon0: float, lat0: float, lon1: float, lat1: float) -> Array:
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var c0 := _out_code(x0, y0, lon0, lat0, lon1, lat1)
	var c1 := _out_code(x1, y1, lon0, lat0, lon1, lat1)
	for _i in 12:
		if c0 == 0 and c1 == 0:
			return [Vector2(x0, y0), Vector2(x1, y1)]
		if (c0 & c1) != 0:
			return []
		var outside := c0 if c0 != 0 else c1
		var x := x0
		var y := y0
		var dx := x1 - x0
		var dy := y1 - y0
		if (outside & 8) != 0 and dy != 0.0:
			x = x0 + dx * (lat1 - y0) / dy
			y = lat1
		elif (outside & 4) != 0 and dy != 0.0:
			x = x0 + dx * (lat0 - y0) / dy
			y = lat0
		elif (outside & 2) != 0 and dx != 0.0:
			y = y0 + dy * (lon1 - x0) / dx
			x = lon1
		elif dx != 0.0:
			y = y0 + dy * (lon0 - x0) / dx
			x = lon0
		else:
			return []
		if outside == c0:
			x0 = x
			y0 = y
			c0 = _out_code(x0, y0, lon0, lat0, lon1, lat1)
		else:
			x1 = x
			y1 = y
			c1 = _out_code(x1, y1, lon0, lat0, lon1, lat1)
	return []


## 季风方向：只铺在海图框内。风信是大尺度的，不必逐点画。
func _draw_monsoon(c: Control, map_rect: Rect2) -> void:
	var wb := Calendar.get_wind_bearing()
	if wb < 0.0:
		return

	# 方位角 → 屏幕向量（y 轴向下，故取负 cos）
	var dir := Vector2(sin(deg_to_rad(wb)), -cos(deg_to_rad(wb)))
	var col := Color(0.45, 0.7, 0.95, 0.22)
	var step := 62.0
	var arrow := 7.0
	var y := map_rect.position.y + 20.0
	while y < map_rect.end.y - 16.0:
		var x := map_rect.position.x + 20.0
		while x < map_rect.end.x - 16.0:
			var mid := Vector2(x, y)
			var a := mid - dir * 13.0
			var b := mid + dir * 13.0
			c.draw_line(a, b, col, 1.0)
			var perp := Vector2(-dir.y, dir.x)
			c.draw_line(b, b - dir * arrow + perp * arrow * 0.5, col, 1.0)
			c.draw_line(b, b - dir * arrow - perp * arrow * 0.5, col, 1.0)
			x += step
		y += step


func _draw_monsoon_caption(c: Control, map_rect: Rect2) -> void:
	var wb := Calendar.get_wind_bearing()
	var text := "季风转换期・风微而多变" if wb < 0.0 else Calendar.get_monsoon_desc()
	var col := Color(0.7, 0.72, 0.75, 0.9) if wb < 0.0 else Color(0.6, 0.8, 1.0, 0.9)
	c.draw_string(ThemeDB.fallback_font, map_rect.position + Vector2(10, 18),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _log(text: String) -> void:
	log_label.text = text + "\n\n" + log_label.text


# ══════════════════════════════════════════════════════
#  航行
# ══════════════════════════════════════════════════════

func _on_sail_pressed() -> void:
	if selected_port == "" or sailing:
		return
	total_li = Voyage.distance_li(origin_port, selected_port)
	remaining_li = total_li
	course_bearing = Voyage.bearing(origin_port, selected_port)
	days_elapsed = 0
	sailing = true
	Fleet.at_sea = true

	sail_button.disabled = true
	for c in port_list.get_children():
		c.disabled = true

	_log("[color=aqua]启程往 %s，航程 %d 里。[/color]" % [GameManager.get_port_name(selected_port), int(total_li)])
	_sail_next_day()


func _sail_next_day() -> void:
	if not sailing:
		return

	GameManager.advance_days(1)
	days_elapsed += 1

	var event := Voyage.roll_day_event(course_bearing, origin_port, selected_port)
	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	var wf := Voyage.wind_factor(course_bearing)
	var progress := Fleet.fleet_speed() * wf

	if kind == Voyage.EventKind.CALM:
		progress = 0.0
	elif kind == Voyage.EventKind.CURRENT:
		progress *= 1.5

	remaining_li -= progress
	_refresh_status()

	# 补给见底的警告
	if Fleet.supply_days() <= 0 and Fleet.total_crew() > 0:
		_log("[color=red]第 %d 日・水粮已尽，舱里开始有人病倒。[/color]" % days_elapsed)

	if kind != Voyage.EventKind.NONE:
		_show_event(event)
		return

	if remaining_li <= 0.0:
		_arrive()
		return

	# 无事之日直接推进下一天
	_sail_next_day()


func _show_event(event: Dictionary) -> void:
	pending_event = event
	event_title.text = "第 %d 日・%s" % [days_elapsed, event.get("title", "事")]
	event_text.text = event.get("text", "")
	_log("第 %d 日・%s" % [days_elapsed, event.get("title", "")])

	for c in event_actions.get_children():
		c.queue_free()

	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	if kind == Voyage.EventKind.PIRATE:
		_add_event_action("迎战", _on_fight_pirates)
		_add_event_action("扬帆逃走", _on_flee_pirates)
		_add_event_action("献上买路财", _on_pay_pirates)
	elif kind == Voyage.EventKind.DISCOVERY:
		_add_event_action("绕过去看看（费 1 日）", _on_investigate_discovery)
		_add_event_action("不理会，继续航行", _on_event_continue)
	else:
		_add_event_action("继续航行", _on_event_continue)

	event_panel.visible = true


func _add_event_action(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	event_actions.add_child(b)


func _on_event_continue() -> void:
	event_panel.visible = false
	pending_event = {}
	if remaining_li <= 0.0:
		_arrive()
	else:
		_sail_next_day()


# ── 海盗 ────────────────────────────────────────────

## 舰队战力：耐久 + 水手 + 炮位 + 甲级，计入士气
func _fleet_power() -> float:
	var cannons := 0
	for s in Fleet.ships:
		cannons += int(Fleet.ship_def(s.get("type", "")).get("cannon_slots", 0))
	return (Fleet.total_durability() * 0.5 + Fleet.total_crew() * 4.0 + cannons * 25.0 + Fleet.fleet_armor_level() * 30.0) * Fleet.morale_factor()


func _on_fight_pirates() -> void:
	event_panel.visible = false
	var power := _fleet_power()
	var enemy := randf_range(180.0, 520.0)
	# P4-1 海战接入：构造战斗上下文，切 WorldMap 炮击分胜负
	GameManager.pending_battle = {
		"battle": true,
		"power": enemy,
		"player_power": power,
		"enemy": [{"type": "sea_falcon", "count": 2, "hull_hp": 100.0}],
		"source": {"scene": "SeaChart", "event": "pirate"},
	}
	_enter_battle()


## 实例化 WorldMap 叠加到 SeaChart 上（add_child 保留航行状态，战斗结束 queue_free 即回）
func _enter_battle() -> void:
	var wm := preload("res://scenes/WorldMap.tscn").instantiate()
	wm.battle_finished.connect(_on_battle_result)
	add_child(wm)


## 战斗结果写回：对齐现有文本结算公式（逐字保留），再续航行
func _on_battle_result(outcome: String, data: Dictionary) -> void:
	var dmg := float(data.get("player_damage", 0.0))
	if outcome == "win":
		var spoil := int(randf_range(150, 600))
		GameState.add_money(spoil)
		GameState.fame += 3
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 5)
		_log("[color=lime]击退海盗，夺得财货 %d 钱。战损 %d。[/color]" % [spoil, int(dmg)])
	elif outcome == "lose":
		Fleet.morale = maxi(0, Fleet.morale - 12)
		var lost := Fleet.lose_cargo_ratio(0.25)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log("[color=red]接舷失利，被夺去部分货物。%s船体受损 %d。[/color]" % [lost_str, int(dmg)])
	else:  # flee
		if data.get("flee_ok", false):
			remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
			_log("[color=lime]转舵抢上风头，把那两条快船甩在了后面（绕了些路）。[/color]")
		else:
			Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
			var lost := Fleet.lose_cargo_ratio(0.18)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			_log("[color=red]没能甩脱，被追上跳帮，抢走了货。%s[/color]" % lost_str)
	GameManager.pending_battle = {}
	_refresh_status()
	_after_combat()


func _on_flee_pirates() -> void:
	event_panel.visible = false
	# 逃跑成败取决于航速与士气
	var chance := clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)
	if randf() < chance:
		remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
		_log("[color=lime]转舵抢上风头，把那两条快船甩在了后面（绕了些路）。[/color]")
	else:
		var lost := Fleet.lose_cargo_ratio(0.18)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
		_log("[color=red]没能甩脱，被追上跳帮，抢走了货。%s[/color]" % lost_str)
	_refresh_status()
	_after_combat()


func _on_pay_pirates() -> void:
	event_panel.visible = false
	var toll: int = maxi(100, int(GameState.money * 0.15))
	if GameState.spend_money(toll):
		Fleet.morale = maxi(0, Fleet.morale - 4)
		_log("[color=yellow]递过去 %d 钱买路。对方点了点数目，掉头走了。[/color]" % toll)
	else:
		var lost := Fleet.lose_cargo_ratio(0.3)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log("[color=red]拿不出买路钱，他们自己动手搬空了半个货舱。%s[/color]" % lost_str)
	_refresh_status()
	_after_combat()


func _after_combat() -> void:
	pending_event = {}
	if Fleet.total_durability() <= 0.0:
		_sink()
		return
	if remaining_li <= 0.0:
		_arrive()
	else:
		_sail_next_day()


# ── 发现物 ──────────────────────────────────────────

func _on_investigate_discovery() -> void:
	event_panel.visible = false
	GameManager.advance_days(1)
	days_elapsed += 1
	var did: String = pending_event.get("discovery_id", "")
	var d := GameManager.get_discovery_by_id(did)
	if GameState.record_discovery(did):
		_log("[color=lime]近岸细看，果然是%s。记入册子——回港上报市舶司，当有赏格。[/color]" % d.get("name", "旧泊地"))
	else:
		_log("绕过去看了一圈，与册上所记并无出入。")
	_refresh_status()
	_on_event_continue()


# ── 结束 ────────────────────────────────────────────

func _arrive() -> void:
	sailing = false
	Fleet.at_sea = false
	GameState.last_port = selected_port
	_log("[color=aqua]历 %d 日，抵 %s。[/color]" % [days_elapsed, GameManager.get_port_name(selected_port)])

	event_title.text = "到　港"
	event_text.text = "历 %d 日海路，%s 的岸线终于在雾里显出来。\n\n%s" % [
		days_elapsed,
		GameManager.get_port_name(selected_port),
		"舱内尚存水 %d、粮 %d，士气 %d。" % [Fleet.water, Fleet.food, Fleet.morale],
	]
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("下船入港", _return_to_port)
	event_panel.visible = true


func _sink() -> void:
	sailing = false
	Fleet.at_sea = false
	Fleet.clear_cargo()
	event_title.text = "沉　没"
	event_text.text = "船身裂开，海水灌进货舱。等你再睁眼时，已被人捞上一条渔船，货与船都没了。"
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("……", func():
		# 保底：留一条小艍船，避免死档
		Fleet.ships.clear()
		Fleet.add_ship("sampan", "借来的小艍")
		Fleet.water = 20
		Fleet.food = 20
		Fleet.morale = 50
		GameState.last_port = origin_port
		_return_to_port()
	)
	event_panel.visible = true


func _return_to_port() -> void:
	Fleet.at_sea = false
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
