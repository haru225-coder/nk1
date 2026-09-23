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

## 与 tools/verify_economy.py 的 project() 同一组常数，改一边必须改另一边。
## 墨卡托：y = ln(tan(π/4 + φ/2))。纬线方向的比例随纬度变化，但局部保形，
## 海岸形状和恒向线（针路）才是直的。等比纬度投影会把闽浙海岸拉变形。
const CHART_PAD_MIN_DEG := 1.6
const CHART_PAD_FRAC := 0.14
const CHART_FIT_MARGIN := 0.82
const CHART_EARTH_R_KM := 6371.0
const CHART_KM_PER_LI := 0.576

var _proj_ok: bool = false
var _proj_scale: float = 1.0
var _proj_cx: float = 0.0
var _proj_cy: float = 0.0
var _proj_mid: Vector2 = Vector2.ZERO
var _view_south: float = 0.0
var _view_north: float = 0.0
var _view_west: float = 0.0
var _view_east: float = 0.0
var _coast_cache_key: String = ""
var _coast_polys: Array = []


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

	# 真实海岸的墨卡托海图。视窗随已解锁港口移动，岸线来自 Natural Earth。
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 340)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.size_flags_stretch_ratio = 2.4
	chart.mouse_filter = Control.MOUSE_FILTER_STOP
	chart.draw.connect(func(): _draw_chart(chart))
	chart.gui_input.connect(_on_chart_input)
	center_v.add_child(chart)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 96)
	scroll.size_flags_stretch_ratio = 1.0
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

func _mercator_y(lat: float) -> float:
	var clamped := clampf(lat, -80.0, 80.0)
	var r := deg_to_rad(clamped)
	return log(tan(PI * 0.25 + r * 0.5))


## 视窗包住已解锁港口，再向外留出海岸。返回 [south, north, west, east]。
func _chart_bounds(pts: Array) -> Array:
	var lat_min := 999.0
	var lat_max := -999.0
	var lon_min := 999.0
	var lon_max := -999.0
	for p in pts:
		lat_min = minf(lat_min, float(p.get("lat", 0.0)))
		lat_max = maxf(lat_max, float(p.get("lat", 0.0)))
		lon_min = minf(lon_min, float(p.get("lon", 0.0)))
		lon_max = maxf(lon_max, float(p.get("lon", 0.0)))
	var pad_lat := maxf(CHART_PAD_MIN_DEG, (lat_max - lat_min) * CHART_PAD_FRAC)
	var pad_lon := maxf(CHART_PAD_MIN_DEG, (lon_max - lon_min) * CHART_PAD_FRAC)
	return [lat_min - pad_lat, lat_max + pad_lat, lon_min - pad_lon, lon_max + pad_lon]


func _fit_projection(size: Vector2) -> void:
	var x0 := deg_to_rad(_view_west)
	var x1 := deg_to_rad(_view_east)
	var y0 := _mercator_y(_view_south)
	var y1 := _mercator_y(_view_north)
	var span_x := maxf(0.01, x1 - x0)
	var span_y := maxf(0.01, y1 - y0)
	_proj_scale = minf(size.x / span_x, size.y / span_y) * CHART_FIT_MARGIN
	_proj_cx = (x0 + x1) * 0.5
	_proj_cy = (y0 + y1) * 0.5
	_proj_mid = size * 0.5
	_proj_ok = true


func _project(lat: float, lon: float) -> Vector2:
	var x := _proj_mid.x + (deg_to_rad(lon) - _proj_cx) * _proj_scale
	var y := _proj_mid.y - (_mercator_y(lat) - _proj_cy) * _proj_scale
	return Vector2(x, y)


func _ring_in_view(ring: Array) -> bool:
	var lon0 := 999.0
	var lon1 := -999.0
	var lat0 := 999.0
	var lat1 := -999.0
	for pt in ring:
		var lon := float(pt[0])
		var lat := float(pt[1])
		lon0 = minf(lon0, lon)
		lon1 = maxf(lon1, lon)
		lat0 = minf(lat0, lat)
		lat1 = maxf(lat1, lat)
	return not (lon1 < _view_west or lon0 > _view_east or lat1 < _view_south or lat0 > _view_north)


func _ensure_coast_polys() -> void:
	# Godot 的 % 格式不吃 %0.3f，视窗用 snapped 拼进缓存键。
	var key := "%s|%s|%s|%s|%d|%d" % [
		snapped(_view_west, 0.001), snapped(_view_east, 0.001),
		snapped(_view_south, 0.001), snapped(_view_north, 0.001),
		int(_proj_mid.x * 2.0), int(_proj_mid.y * 2.0),
	]
	if key == _coast_cache_key:
		return
	_coast_cache_key = key
	_coast_polys = []
	for ring in GameManager.coastline_data.get("land", []):
		if not _ring_in_view(ring):
			continue
		var poly := PackedVector2Array()
		for pt in ring:
			poly.append(_project(float(pt[1]), float(pt[0])))
		if poly.size() >= 3:
			_coast_polys.append(poly)


## 绕开陆地的折线。没有记录时退回两港直线。方向按 key 的字母序。
func _route_points(from_id: String, to_id: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var a := GameManager.get_port_by_id(from_id)
	var b := GameManager.get_port_by_id(to_id)
	if a.is_empty() or b.is_empty():
		return pts
	var lo := from_id
	var hi := to_id
	var reverse := false
	if hi < lo:
		lo = to_id
		hi = from_id
		reverse = true
	var lane: Array = GameManager.sealanes_data.get("lanes", {}).get("%s|%s" % [lo, hi], [])
	if reverse:
		lane = lane.duplicate()
		lane.reverse()
	pts.append(_project(float(a.get("lat", 0.0)), float(a.get("lon", 0.0))))
	for w in lane:
		pts.append(_project(float(w[1]), float(w[0])))
	pts.append(_project(float(b.get("lat", 0.0)), float(b.get("lon", 0.0))))
	return pts


func _point_along(pts: PackedVector2Array, frac: float) -> Vector2:
	if pts.size() == 0:
		return Vector2.ZERO
	if pts.size() == 1 or frac <= 0.0:
		return pts[0]
	var total := 0.0
	var lengths: Array = []
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		lengths.append(seg)
		total += seg
	if total < 0.001:
		return pts[0]
	var target := clampf(frac, 0.0, 1.0) * total
	var acc := 0.0
	for i in range(lengths.size()):
		var seg: float = lengths[i]
		if acc + seg >= target and seg > 0.0:
			return pts[i].lerp(pts[i + 1], (target - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]


func _draw_chart(c: Control) -> void:
	var size := c.size
	if size.x < 8.0 or size.y < 8.0:
		return
	var pts: Array = GameManager.unlocked_ports()
	if pts.size() < 2:
		return

	var bounds: Array = _chart_bounds(pts)
	_view_south = bounds[0]
	_view_north = bounds[1]
	_view_west = bounds[2]
	_view_east = bounds[3]
	_fit_projection(size)

	# 海图底：浅海。陆地盖在上面，风矢画在海里。
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.729, 0.812, 0.839, 1.0))
	_draw_monsoon_arrows(c, size)
	_ensure_coast_polys()
	var land_col := Color(0.839, 0.769, 0.627, 1.0)
	var coast_col := Color(0.35, 0.29, 0.20, 1.0)
	for poly in _coast_polys:
		var outline := PackedVector2Array()
		outline.append_array(poly)
		if outline.size() >= 3:
			outline.append(outline[0])
		# 自交的环三角化会失败。失败就只描岸，不让整张图报错。
		if Geometry2D.triangulate_polygon(poly).size() >= 3:
			c.draw_colored_polygon(poly, land_col)
		if outline.size() >= 2:
			c.draw_polyline(outline, coast_col, 1.0, true)

	_draw_graticule(c)
	_draw_routes(c, pts)
	_draw_sea_labels(c, pts)
	_draw_ports(c, pts)
	_draw_ship(c)
	_draw_scale_bar(c)
	_draw_compass(c)
	_draw_monsoon_caption(c)


func _draw_graticule(c: Control) -> void:
	var lat_span := _view_north - _view_south
	var lon_span := _view_east - _view_west
	var lat_step := 5.0
	if lat_span <= 8.0:
		lat_step = 1.0
	elif lat_span <= 16.0:
		lat_step = 2.0
	var lon_step := 5.0
	if lon_span <= 8.0:
		lon_step = 1.0
	elif lon_span <= 16.0:
		lon_step = 2.0
	var col := Color(0.25, 0.36, 0.42, 0.28)
	var font := ThemeDB.fallback_font
	var lat: float = ceil(_view_south / lat_step) * lat_step
	while lat < _view_north - 0.02:
		var a := _project(lat, _view_west)
		var b := _project(lat, _view_east)
		c.draw_line(a, b, col, 1.0)
		c.draw_string(font, Vector2(6, a.y - 2), "%d°N" % int(round(lat)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.22, 0.32, 0.38, 0.85))
		lat += lat_step
	var lon: float = ceil(_view_west / lon_step) * lon_step
	while lon < _view_east - 0.02:
		var a := _project(_view_south, lon)
		var b := _project(_view_north, lon)
		c.draw_line(a, b, col, 1.0)
		c.draw_string(font, Vector2(a.x - 12, c.size.y - 16), "%d°E" % int(round(lon)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.22, 0.32, 0.38, 0.85))
		lon += lon_step


func _draw_routes(c: Control, pts: Array) -> void:
	var seen := {}
	for p in pts:
		var pid: String = p.get("id", "")
		for cid in p.get("connections", []):
			var q := GameManager.get_port_by_id(str(cid))
			if q.is_empty() or not GameState.is_chapter_reached(q.get("unlock", "ch1")):
				continue
			var cid_s := str(cid)
			var key := (pid + "|" + cid_s) if pid < cid_s else (cid_s + "|" + pid)
			if seen.has(key):
				continue
			seen[key] = true
			var line := _route_points(pid, str(cid))
			if line.size() >= 2:
				c.draw_polyline(line, Color(0.12, 0.32, 0.45, 0.55), 1.25, true)

	if selected_port == "":
		return
	var line := _route_points(origin_port, selected_port)
	if line.size() < 2:
		return
	var wf := Voyage.wind_factor(Voyage.bearing(origin_port, selected_port))
	var col := Color(0.12, 0.45, 0.28) if wf >= 1.15 else (
		Color(0.70, 0.22, 0.16) if wf <= 0.75 else Color(0.55, 0.40, 0.08))
	c.draw_polyline(line, col, 2.5, true)


func _draw_sea_labels(c: Control, pts: Array) -> void:
	var span := _view_north - _view_south
	var font := ThemeDB.fallback_font
	var size := c.size
	for lab in GameManager.chart_labels_data.get("labels", []):
		var min_s := float(lab.get("min_span", 0.0))
		var max_s := float(lab.get("max_span", 99.0))
		if span < min_s or span > max_s:
			continue
		var v := _project(float(lab.get("lat", 0.0)), float(lab.get("lon", 0.0)))
		if v.x < 36.0 or v.y < 28.0 or v.x > size.x - 36.0 or v.y > size.y - 28.0:
			continue
		var crowded := false
		for p in pts:
			var pv := _project(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
			if pv.distance_to(v) < 42.0:
				crowded = true
				break
		if crowded:
			continue
		c.draw_string(font, v, str(lab.get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.16, 0.34, 0.44, 0.72))


func _draw_ports(c: Control, pts: Array) -> void:
	var font := ThemeDB.fallback_font
	for p in pts:
		var pid: String = p.get("id", "")
		var v := _project(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		var visited: bool = pid in GameState.visited_ports
		var is_here := pid == origin_port
		var is_target := pid == selected_port
		var col := Color(0.18, 0.22, 0.28)
		if visited:
			col = Color(0.10, 0.16, 0.28)
		if is_target:
			col = Color(0.62, 0.32, 0.05)
		if is_here:
			col = Color(0.05, 0.32, 0.48)
		c.draw_circle(v, 4.5 if (is_here or is_target) else 3.2, col)
		if is_here:
			c.draw_arc(v, 8.0, 0, TAU, 20, col, 1.5)
		c.draw_string(font, v + Vector2(7, 4), str(p.get("name", pid)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _draw_ship(c: Control) -> void:
	if not sailing or selected_port == "" or total_li <= 0.0:
		return
	var frac := clampf((total_li - remaining_li) / total_li, 0.0, 1.0)
	var line := _route_points(origin_port, selected_port)
	if line.size() < 2:
		return
	var pos := _point_along(line, frac)
	var ahead := _point_along(line, minf(1.0, frac + 0.02))
	var dir := ahead - pos
	if dir.length() < 0.5:
		var brg := Voyage.bearing(origin_port, selected_port)
		dir = Vector2(sin(deg_to_rad(brg)), -cos(deg_to_rad(brg)))
	else:
		dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 8.0
	var left := pos - dir * 5.0 + perp * 4.5
	var right := pos - dir * 5.0 - perp * 4.5
	c.draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.55, 0.10, 0.08, 1.0))


func _draw_scale_bar(c: Control) -> void:
	var lat_c := (_view_south + _view_north) * 0.5
	# 墨卡托 x 是经度弧度。东西向地面距离 = R · cosφ · Δλ。
	var km_per_px := (CHART_EARTH_R_KM * cos(deg_to_rad(lat_c))) / _proj_scale
	var li_per_px := km_per_px / CHART_KM_PER_LI
	if li_per_px <= 0.0:
		return
	var raw := 110.0 * li_per_px
	var nice := 100
	for n in [100, 200, 500, 1000, 2000, 5000]:
		if float(n) <= raw * 1.35:
			nice = n
	var bar := float(nice) / li_per_px
	var origin := Vector2(14, c.size.y - 22)
	var col := Color(0.15, 0.18, 0.2, 0.9)
	c.draw_line(origin, origin + Vector2(bar, 0), col, 2.0)
	c.draw_line(origin, origin + Vector2(0, -5), col, 2.0)
	c.draw_line(origin + Vector2(bar, 0), origin + Vector2(bar, -5), col, 2.0)
	c.draw_string(ThemeDB.fallback_font, origin + Vector2(0, -18), "%d 里" % nice,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_compass(c: Control) -> void:
	var o := Vector2(c.size.x - 28, 34)
	var col := Color(0.15, 0.2, 0.24, 0.9)
	c.draw_arc(o, 14, 0, TAU, 24, col, 1.0)
	c.draw_line(o + Vector2(0, 8), o + Vector2(0, -12), col, 1.5)
	c.draw_line(o + Vector2(-6, 4), o + Vector2(6, 4), Color(0.15, 0.2, 0.24, 0.45), 1.0)
	c.draw_string(ThemeDB.fallback_font, o + Vector2(-6, -26), "北",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## 点港口即选定。离得太近的两个点（兴化 / 海口）不抢，仍走左边的列表。
func _on_chart_input(event: InputEvent) -> void:
	if sailing or not _proj_ok:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var best_id := ""
	var best_d := 1e9
	var second := 1e9
	for p in GameManager.unlocked_ports():
		if float(p.get("depth", 0)) <= 0.0:
			continue
		var pid: String = p.get("id", "")
		if pid == origin_port:
			continue
		var v := _project(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		# gui_input 的 event.position 是视口坐标，点选要用海图控件自己的局部坐标。
		var d := v.distance_to(chart.get_local_mouse_position())
		if d < best_d:
			second = best_d
			best_d = d
			best_id = pid
		elif d < second:
			second = d
	if best_id != "" and best_d < 18.0 and best_d + 8.0 < second:
		chart.accept_event()
		_on_port_selected(best_id)


## 季风箭头画在陆地之下，只留在海面上。说明文字最后再画，避免被岸线盖住。
func _draw_monsoon_arrows(c: Control, size: Vector2) -> void:
	var wb := Calendar.get_wind_bearing()
	if wb < 0.0:
		return
	# 方位角 → 屏幕向量（y 轴向下，故取负 cos）
	var dir := Vector2(sin(deg_to_rad(wb)), -cos(deg_to_rad(wb)))
	var col := Color(0.12, 0.32, 0.48, 0.16)
	var step := 62.0
	var arrow := 7.0
	var y := step * 0.5
	while y < size.y:
		var x := step * 0.5
		while x < size.x:
			var mid := Vector2(x, y)
			var a := mid - dir * 13.0
			var b := mid + dir * 13.0
			c.draw_line(a, b, col, 1.0)
			var perp := Vector2(-dir.y, dir.x)
			c.draw_line(b, b - dir * arrow + perp * arrow * 0.5, col, 1.0)
			c.draw_line(b, b - dir * arrow - perp * arrow * 0.5, col, 1.0)
			x += step
		y += step


func _draw_monsoon_caption(c: Control) -> void:
	var text := Calendar.get_monsoon_desc()
	if Calendar.get_wind_bearing() < 0.0:
		text = "季风转换期・风微而多变"
	c.draw_string(ThemeDB.fallback_font, Vector2(10, 18), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.10, 0.24, 0.34, 0.95))


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
