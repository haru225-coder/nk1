extends Control
## 海图。风每一手发至多三向，选定后按日推进，逐日抽事件，到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

var origin_port: String = ""
var selected_port: String = ""
var _hand: PackedStringArray = PackedStringArray()
var _marker_at: Dictionary = {}

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
var heading_row: HBoxContainer
var log_label: RichTextLabel
var sail_button: Button
var redraw_button: Button
var event_panel: PanelContainer
var event_title: Label
var event_text: RichTextLabel
var event_actions: VBoxContainer


func _ready() -> void:
	UiTheme.apply(self)
	origin_port = GameState.last_port
	selected_port = ""
	_hand = HeadingDraft.deal(origin_port, GameState.draft_salt)
	_build_ui()
	# 连接放在 _build_ui 之后：_log 依赖其中创建的 log_label
	GameManager.monthly_notice.connect(_log)
	_refresh_hand()
	_refresh_status()
	_log("自 %s 起锚。%s。" % [GameManager.get_port_name(origin_port), Calendar.get_monsoon_desc()])


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
	bg.modulate = Color(0.94, 0.88, 0.76, 1.0)
	add_child(bg)

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = UiTheme.VEIL
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	# ── 左：状态 ──
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_stylebox_override("panel", _panel_style())
	columns.add_child(left)
	var left_m := MarginContainer.new()
	_set_margins(left_m, 10)
	left.add_child(left_m)
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	UiTheme.style_body(status_label)
	left_m.add_child(status_label)

	# ── 中：绢纸海图。航向牌不放这里，三张 372 宽的牌在底栏才排得下。 ──
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_stylebox_override("panel", _panel_style())
	columns.add_child(center)
	var center_m := MarginContainer.new()
	_set_margins(center_m, 12)
	center.add_child(center_m)
	var center_v := VBoxContainer.new()
	center_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_v.add_theme_constant_override("separation", 8)
	center_m.add_child(center_v)

	var head := Label.new()
	head.text = "海图"
	UiTheme.style_heading(head)
	center_v.add_child(head)

	var hint := Label.new()
	hint.text = "风这一手只发三向。看中一张，再决定发不发舶。"
	UiTheme.style_footnote(hint)
	center_v.add_child(hint)

	# 真正的图。数据用 ports.json 的经纬度，CanvasItem.draw 信号接 lambda，
	# 不另建节点树——一张静态海图不需要缩放拖拽。
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 160)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.draw.connect(func(): _draw_chart(chart))
	chart.gui_input.connect(_on_chart_input)
	center_v.add_child(chart)

	# ── 右：航海日志 ──
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	right.add_theme_stylebox_override("panel", _panel_style())
	columns.add_child(right)
	var right_m := MarginContainer.new()
	_set_margins(right_m, 10)
	right.add_child(right_m)
	var right_v := VBoxContainer.new()
	right_m.add_child(right_v)
	var log_head := Label.new()
	log_head.text = "航海日志"
	log_head.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	log_head.add_theme_color_override("font_color", UiTheme.GOLD)
	right_v.add_child(log_head)
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_v.add_child(log_scroll)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.custom_minimum_size = Vector2(272, 0)
	UiTheme.style_body(log_label)
	log_scroll.add_child(log_label)

	heading_row = HBoxContainer.new()
	heading_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heading_row.add_theme_constant_override("separation", 12)
	heading_row.custom_minimum_size = Vector2(0, 148)
	root.add_child(heading_row)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)

	sail_button = Button.new()
	sail_button.text = "就这一向"
	sail_button.custom_minimum_size = Vector2(220, 48)
	sail_button.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	sail_button.disabled = true
	sail_button.pressed.connect(_on_sail_pressed)
	actions.add_child(sail_button)
	UiTheme.style_button(sail_button, true)

	redraw_button = Button.new()
	redraw_button.text = "候风再发"
	redraw_button.custom_minimum_size = Vector2(160, 42)
	redraw_button.pressed.connect(_on_redraw_hand)
	actions.add_child(redraw_button)
	UiTheme.style_button(redraw_button)

	var back := Button.new()
	back.text = "回港"
	back.custom_minimum_size = Vector2(120, 42)
	back.pressed.connect(_return_to_port)
	actions.add_child(back)
	UiTheme.style_button(back)

	# ── 事件浮层 ──
	_build_event_panel()


func _build_event_panel() -> void:
	var overlay := CenterContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	event_panel = PanelContainer.new()
	event_panel.custom_minimum_size = Vector2(560, 0)
	event_panel.add_theme_stylebox_override("panel", UiTheme.panel())
	event_panel.visible = false
	overlay.add_child(event_panel)

	var m := MarginContainer.new()
	_set_margins(m, 18)
	event_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	event_title = Label.new()
	UiTheme.style_heading(event_title)
	v.add_child(event_title)

	event_text = RichTextLabel.new()
	event_text.bbcode_enabled = true
	event_text.fit_content = true
	event_text.custom_minimum_size = Vector2(520, 60)
	UiTheme.style_body(event_text)
	v.add_child(event_text)

	event_actions = VBoxContainer.new()
	event_actions.add_theme_constant_override("separation", 6)
	v.add_child(event_actions)


func _panel_style() -> StyleBoxFlat:
	return UiTheme.panel()


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
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY

	var gold := UiTheme.hex(UiTheme.GOLD)
	var t := "[color=#%s][b]%s[/b][/color]\n[color=#%s]%s[/color]\n" % [
		gold, Calendar.get_date_string(), UiTheme.hex(UiTheme.TEXT_DIM), Calendar.get_monsoon_desc(),
	]
	if sailing:
		var pct := 0.0
		if total_li > 0.0:
			pct = clampf((total_li - remaining_li) / total_li, 0.0, 1.0)
		t += "[color=#%s]航行中　第 %d 日[/color]\n已行　%d / 100\n余程　%d 里\n" % [
			UiTheme.hex(UiTheme.HONEY), days_elapsed, int(pct * 100), int(remaining_li),
		]
	t += "金钱　[b]%d[/b]\n名声　%d　%s\n" % [GameState.money, GameState.fame, GameState.title_name()]
	t += "[color=#%s][b]舰队[/b][/color]\n船数　%d　水手　%d\n舱位　%d / %d 料\n耐久　%d / %d\n士气　%d\n" % [
		gold,
		Fleet.ships.size(), Fleet.total_crew(),
		int(Fleet.used_capacity()), int(Fleet.total_capacity()),
		int(Fleet.total_durability()), int(Fleet.total_max_durability()),
		Fleet.morale,
	]
	t += "水　%d　粮　%d　[color=#%s]足 %d 日[/color]\n" % [
		Fleet.water, Fleet.food, UiTheme.hex(supply_color), supply_d,
	]
	status_label.text = t
	# 日期推进会改季风，图上的风向箭头与航段配色随之变
	if chart:
		chart.queue_redraw()


func _refresh_hand() -> void:
	for c in heading_row.get_children():
		c.queue_free()
	_hand = HeadingDraft.deal(origin_port, GameState.draft_salt)
	if selected_port not in _hand:
		selected_port = ""
	for pid in _hand:
		heading_row.add_child(_make_heading_card(str(pid)))
	sail_button.disabled = selected_port == "" or sailing
	redraw_button.disabled = sailing
	if chart:
		chart.queue_redraw()


func _make_heading_card(pid: String) -> Control:
	var plan := Voyage.plan(origin_port, pid)
	var selected := pid == selected_port
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(372, 148)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.heading_card(selected))
	wrap.add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -14
	box.offset_bottom = -12
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	wrap.add_child(box)

	var name_lbl := Label.new()
	name_lbl.text = str(GameManager.get_port_name(pid))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_override("font", UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	name_lbl.add_theme_color_override("font_color", UiTheme.TIDE)
	box.add_child(name_lbl)

	var wind_lbl := _card_line("%s　约 %d 日" % [str(plan["wind_desc"]), int(plan["days"])], UiTheme.TEXT)
	var hz := Crew.level_of("huozhang")
	if hz > 0:
		wind_lbl.text += "　火长　%s" % Crew.rank_word(hz)
	var dg := Crew.level_of("duogong")
	if dg > 0 and str(plan["wind_desc"]) in ["斜逆风", "顶头逆风"]:
		wind_lbl.text += "　舵工抢风"
	box.add_child(wind_lbl)
	box.add_child(_card_line("%d 里　%s" % [int(plan["distance"]), _bearing_phrase(float(plan["bearing"]))], UiTheme.TEXT_DIM))
	if not Voyage.is_known_route(origin_port, pid):
		box.add_child(_card_line("生路", UiTheme.HONEY))
	if not bool(plan["supply_ok"]):
		box.add_child(_card_line("水粮不够", UiTheme.CINNABAR))

	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.disabled = sailing
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	hit.pressed.connect(_select_heading.bind(pid))
	wrap.add_child(hit)
	if sailing:
		wrap.modulate = Color(1, 1, 1, 0.45)
	return wrap


func _card_line(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _select_heading(pid: String) -> void:
	if sailing:
		return
	if pid not in _hand:
		_log("今日风不放这一向。")
		return
	selected_port = pid
	_refresh_hand()


func _on_redraw_hand() -> void:
	if sailing:
		return
	GameState.draft_salt += 1
	GameManager.advance_days(3)
	selected_port = ""
	_log("在船上候了三日，风又换了一手。")
	_refresh_hand()
	_refresh_status()


func _on_chart_input(event: InputEvent) -> void:
	if sailing or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var pid := _port_at(mb.position)
	if pid == "" or pid == origin_port:
		return
	if pid in _hand:
		_select_heading(pid)
	else:
		_log("今日风不放这一向。")


func _port_at(at: Vector2) -> String:
	var best := ""
	var best_d := 16.0
	for key in _marker_at.keys():
		var pos: Vector2 = _marker_at[key]
		var d := pos.distance_to(at)
		if d < best_d:
			best_d = d
			best = str(key)
	return best


## 八方加上度数。字跟最近的一方，数目仍是航向。
func _bearing_phrase(deg: float) -> String:
	var dirs := PackedStringArray(["北", "东北", "东", "东南", "南", "西南", "西", "西北"])
	var wrapped := posmod(int(round(deg)), 360)
	var idx := int(round(float(wrapped) / 45.0)) % 8
	return "%s　%d 度" % [dirs[idx], wrapped]


# ══════════════════════════════════════════════════════
#  海图绘制
# ══════════════════════════════════════════════════════

## 等比投影已解锁港口的经纬度。经度按平均纬度收窄，否则高纬处会被拉宽。
func _draw_chart(c: Control) -> void:
	var pts: Array = GameManager.unlocked_ports()
	if pts.size() < 2:
		return

	var lat_min := 999.0
	var lat_max := -999.0
	var lon_min := 999.0
	var lon_max := -999.0
	for p in pts:
		lat_min = minf(lat_min, float(p.get("lat", 0.0)))
		lat_max = maxf(lat_max, float(p.get("lat", 0.0)))
		lon_min = minf(lon_min, float(p.get("lon", 0.0)))
		lon_max = maxf(lon_max, float(p.get("lon", 0.0)))

	var mean_lat := (lat_min + lat_max) * 0.5
	var mean_lon := (lon_min + lon_max) * 0.5
	var kx := cos(deg_to_rad(mean_lat))
	var span_x := maxf(0.5, (lon_max - lon_min) * kx)
	var span_y := maxf(0.5, lat_max - lat_min)

	var size := c.size
	var scale := minf(size.x / span_x, size.y / span_y) * 0.78
	var mid := size * 0.5

	var proj := func(lat: float, lon: float) -> Vector2:
		return mid + Vector2((lon - mean_lon) * kx * scale, -(lat - mean_lat) * scale)

	_draw_chart_leaf(c, size)

	_draw_monsoon(c, size)

	# 已知航路：淡墨勾出港口间的连接关系。绢纸上不用泥金，否则线会发飘。
	for p in pts:
		var a: Vector2 = proj.call(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		for cid in p.get("connections", []):
			var q := GameManager.get_port_by_id(cid)
			if q.is_empty() or not GameState.is_chapter_reached(q.get("unlock", "ch1")):
				continue
			var b: Vector2 = proj.call(float(q.get("lat", 0.0)), float(q.get("lon", 0.0)))
			c.draw_line(a, b, Color(0.40, 0.26, 0.12, 0.45), 1.0)

	# 当前航段
	if selected_port != "":
		var o := GameManager.get_port_by_id(origin_port)
		var d := GameManager.get_port_by_id(selected_port)
		if not o.is_empty() and not d.is_empty():
			var a: Vector2 = proj.call(float(o.get("lat", 0.0)), float(o.get("lon", 0.0)))
			var b: Vector2 = proj.call(float(d.get("lat", 0.0)), float(d.get("lon", 0.0)))
			var wf := Voyage.wind_factor(Voyage.bearing(origin_port, selected_port))
			# 顺风泛绿、逆风泛红——季风是否有利，一眼能看出来
			# 绢纸上的顺风/横风/逆风要比面板上的亮色深一档，否则会糊进纸色。
			var col := Color(0.30, 0.42, 0.22) if wf >= 1.15 else (
				Color(0.62, 0.24, 0.16) if wf <= 0.75 else Color(0.55, 0.36, 0.10))
			c.draw_line(a, b, col, 2.5)

	var font := UiTheme.font()
	var marks: Array[Dictionary] = []
	_marker_at = {}
	for p in pts:
		var pid: String = p.get("id", "")
		var v: Vector2 = proj.call(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		_marker_at[pid] = v
		var visited: bool = pid in GameState.visited_ports
		var is_here := pid == origin_port
		var is_target := pid == selected_port
		var offered := is_here or pid in _hand
		# 圆点落在绢纸上，要用深墨；签上的字仍是浅色，两套不能混。
		var label_col := UiTheme.TEXT_DIM
		var dot_col := Color(0.42, 0.32, 0.22)
		if visited:
			label_col = UiTheme.TEXT
			dot_col = Color(0.24, 0.16, 0.10)
		if is_target:
			label_col = UiTheme.GOLD
			dot_col = Color(0.55, 0.36, 0.10)
		if is_here:
			label_col = UiTheme.CINNABAR
			dot_col = Color(0.62, 0.22, 0.14)
		if not offered:
			label_col.a = 0.35
			dot_col.a = 0.35
		c.draw_circle(v, 4.0 if (is_here or is_target) else 3.0, dot_col)
		if is_here:
			c.draw_arc(v, 8.0, 0, TAU, 20, dot_col, 1.5)
		marks.append({
			"at": v,
			"name": str(p.get("name", pid)),
			"col": label_col,
			"accent": is_here or is_target,
		})

	var bounds := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	var occupied: Array[Rect2] = []
	for mark in marks:
		var at: Vector2 = mark["at"]
		occupied.append(Rect2(at - Vector2(7, 7), Vector2(14, 14)))
	var wind_bearing := Calendar.get_wind_bearing()
	var monsoon_text := Calendar.get_monsoon_desc()
	var monsoon_col := UiTheme.GOLD if wind_bearing >= 0.0 else UiTheme.TEXT_DIM
	occupied.append(_draw_ink_label(c, font, Vector2(12, 18), monsoon_text, monsoon_col, false))
	for mark in marks:
		var label: String = str(mark["name"])
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
		var baseline := _place_chart_label(
			font, mark["at"] as Vector2, label, text_w, bounds, occupied, bool(mark["accent"])
		)
		if baseline.x > -1000.0:
			occupied.append(_draw_ink_label(
				c, font, baseline, label, mark["col"] as Color, bool(mark["accent"])
			))


## 海图中栏是一张绢纸，不再在熟漆面板上再铺一层熟漆。
func _draw_chart_leaf(c: Control, size: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.91, 0.84, 0.70, 1.0), true)
	var frame := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	if frame.size.x < 8.0 or frame.size.y < 8.0:
		return
	c.draw_rect(frame, Color(0.45, 0.32, 0.16, 0.55), false, 1.0)
	var inner := frame.grow(-3.0)
	if inner.size.x > 4.0 and inner.size.y > 4.0:
		c.draw_rect(inner, Color(0.45, 0.32, 0.16, 0.28), false, 1.0)


## 季风方向：全图统一的斜箭头。风信是大尺度的，不必逐点画。
func _draw_monsoon(c: Control, size: Vector2) -> void:
	var wb := Calendar.get_wind_bearing()
	if wb < 0.0:
		return

	# 方位角 → 屏幕向量（y 轴向下，故取负 cos）
	var dir := Vector2(sin(deg_to_rad(wb)), -cos(deg_to_rad(wb)))
	var col := Color(0.42, 0.28, 0.14, 0.38)
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


## 港名与风信短句垫一块熟漆。裸字会压在季风箭头和航线上。
func _ink_metrics(font: Font) -> Vector2:
	var size := UiTheme.SIZE_FOOT
	var ascent := font.get_ascent(size)
	var descent := font.get_descent(size)
	if ascent < 1.0:
		ascent = float(size) * 0.82
		descent = float(size) * 0.18
	return Vector2(ascent, descent)


func _ink_label_rect(font: Font, baseline: Vector2, text: String) -> Rect2:
	var metric := _ink_metrics(font)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
	if width < 1.0:
		width = float(text.length()) * float(UiTheme.SIZE_FOOT)
	var pad_x := 4.0
	var pad_y := 2.0
	return Rect2(
		baseline + Vector2(-pad_x, -metric.x - pad_y),
		Vector2(width + pad_x * 2.0, metric.x + metric.y + pad_y * 2.0)
	)


func _draw_ink_label(c: Control, font: Font, baseline: Vector2, text: String, col: Color, accent: bool) -> Rect2:
	var rect := _ink_label_rect(font, baseline, text)
	var ink := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.94)
	var edge_a := 0.78 if accent else 0.34
	c.draw_rect(rect, ink, true)
	c.draw_rect(rect, Color(UiTheme.GOLD, edge_a), false, 1.0)
	c.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, col)
	return rect


func _place_chart_label(
	font: Font, marker: Vector2, text: String, text_w: float,
	bounds: Rect2, occupied: Array[Rect2], must: bool
) -> Vector2:
	for side in [0, 1]:
		for row in [0, -1, 1, -2, 2]:
			var baseline := _chart_label_baseline(marker, text_w, side, row)
			var rect := _ink_label_rect(font, baseline, text)
			if not bounds.encloses(rect):
				continue
			if _chart_label_hits(rect, occupied):
				continue
			return baseline
	if must:
		return _chart_label_baseline(marker, text_w, 0, 0)
	return Vector2(-9999, 0)


func _chart_label_baseline(marker: Vector2, text_w: float, side: int, row: int) -> Vector2:
	var x := marker.x + 9.0
	if side == 1:
		x = marker.x - 9.0 - text_w - 8.0
	return Vector2(x, marker.y + 4.0 + float(row) * 16.0)


func _chart_label_hits(rect: Rect2, occupied: Array[Rect2]) -> bool:
	var padded := rect.grow(1.0)
	for prev in occupied:
		if padded.intersects(prev):
			return true
	return false


func _log(text: String) -> void:
	log_label.text = UiTheme.plain_log(text) + "\n\n" + log_label.text


func _ink(c: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [UiTheme.hex(c), text]


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_debug_force_pirate()
		get_viewport().set_input_as_handled()


## 调试局直接刷出「不明船影」。逐日抽海盗大约 6%，云电脑点验用。
func _debug_force_pirate() -> void:
	if not sailing:
		if selected_port == "":
			selected_port = "penghu"
		total_li = Voyage.distance_li(origin_port, selected_port)
		if total_li <= 0.0:
			total_li = 300.0
		remaining_li = maxf(total_li, 80.0)
		course_bearing = Voyage.bearing(origin_port, selected_port)
		days_elapsed = maxi(days_elapsed, 1)
		sailing = true
		Fleet.at_sea = true
		sail_button.disabled = true
		_lock_hand()
		_log(_ink(UiTheme.HONEY, "点验　中途遭遇。"))
		_refresh_status()
	_show_event(Voyage.pirate_sighting())


# ══════════════════════════════════════════════════════
#  航行
# ══════════════════════════════════════════════════════

func _lock_hand() -> void:
	sailing = true
	redraw_button.disabled = true
	for wrap in heading_row.get_children():
		wrap.modulate = Color(1, 1, 1, 0.45)
		for ch in wrap.get_children():
			if ch is Button:
				ch.disabled = true


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
	_lock_hand()

	_log(_ink(UiTheme.GOLD, "启程往 %s，航程 %d 里。" % [GameManager.get_port_name(selected_port), int(total_li)]))
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
		_log(_ink(UiTheme.CINNABAR, "第 %d 日・水粮已尽，舱里开始有人病倒。" % days_elapsed))

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
		_add_event_action("绕去细看　费一日", _on_investigate_discovery)
		_add_event_action("不理会　继续航行", _on_event_continue)
	else:
		_add_event_action("继续航行", _on_event_continue)

	event_panel.visible = true


func _add_event_action(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	event_actions.add_child(b)
	UiTheme.style_choice_button(b)
	if text == "迎战":
		b.add_theme_color_override("font_color", UiTheme.CINNABAR)
		b.add_theme_color_override("font_hover_color", UiTheme.CINNABAR)


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
	if not wm.has_signal("battle_finished"):
		_log(_ink(UiTheme.CINNABAR, "海战脚本没挂上，未能开打。"))
		wm.queue_free()
		_after_combat()
		return
	wm.battle_finished.connect(_on_battle_result)
	# 海图三栏是全屏 Control，盖在 Node2D 海战上面会挡住船和 HUD。
	for c in get_children():
		if c is CanvasItem:
			c.visible = false
	add_child(wm)
	wm.visible = true


## 战斗结果写回：对齐现有文本结算公式（逐字保留），再续航行
func _on_battle_result(outcome: String, data: Dictionary) -> void:
	var dmg := float(data.get("player_damage", 0.0))
	if outcome == "win":
		var spoil := int(randf_range(150, 600))
		GameState.add_money(spoil)
		var fame_res: Dictionary = GameState.add_fame(3)
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 5)
		var promo := ""
		if fame_res.get("promoted", false):
			promo = "案册改题「%s」。" % str(fame_res.get("title", {}).get("name", ""))
		_log(_ink(UiTheme.MOSS, "击退海盗，夺得财货 %d 钱。战损 %d。%s" % [spoil, int(dmg), promo]))
	elif outcome == "lose":
		Fleet.morale = maxi(0, Fleet.morale - 12)
		var lost := Fleet.lose_cargo_ratio(0.25)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log(_ink(UiTheme.CINNABAR, "接舷失利，被夺去部分货物。%s船体受损 %d。" % [lost_str, int(dmg)]))
	else:  # flee
		if data.get("flee_ok", false):
			remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
			_log_shook_pursuers()
		else:
			Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
			var lost := Fleet.lose_cargo_ratio(0.18)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			_log(_ink(UiTheme.CINNABAR, "没能甩脱，被追上跳帮，抢走了货。%s" % lost_str))
	GameManager.pending_battle = {}
	for c in get_children():
		if c is CanvasItem:
			c.visible = true
	_refresh_status()
	_after_combat()


func _log_shook_pursuers() -> void:
	_log(_ink(UiTheme.MOSS, "转舵抢上风头，把那两条快船甩在了后面。绕了些路。"))


func _on_flee_pirates() -> void:
	event_panel.visible = false
	# 逃跑成败取决于航速与士气
	var chance := clampf(Fleet.fleet_speed() / 220.0, 0.25, 0.9)
	if randf() < chance:
		remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
		_log_shook_pursuers()
	else:
		var lost := Fleet.lose_cargo_ratio(0.18)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
		_log(_ink(UiTheme.CINNABAR, "没能甩脱，被追上跳帮，抢走了货。%s" % lost_str))
	_refresh_status()
	_after_combat()


func _on_pay_pirates() -> void:
	event_panel.visible = false
	var toll: int = maxi(100, int(GameState.money * 0.15))
	if GameState.spend_money(toll):
		Fleet.morale = maxi(0, Fleet.morale - 4)
		_log(_ink(UiTheme.HONEY, "递过去 %d 钱买路。对方点了点数目，掉头走了。" % toll))
	else:
		var lost := Fleet.lose_cargo_ratio(0.3)
		var lost_str := ""
		for gid in lost.keys():
			lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
		_log(_ink(UiTheme.CINNABAR, "拿不出买路钱，他们自己动手搬空了半个货舱。%s" % lost_str))
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
		_log(_ink(UiTheme.MOSS, "近岸细看，果然是%s。记入册子——回港上报市舶司，当有赏格。" % d.get("name", "旧泊地")))
	else:
		_log("绕过去看了一圈，与册上所记并无出入。")
	_refresh_status()
	_on_event_continue()


# ── 结束 ────────────────────────────────────────────

func _arrive() -> void:
	sailing = false
	Fleet.at_sea = false
	GameState.last_port = selected_port
	_log(_ink(UiTheme.GOLD, "历 %d 日，抵 %s。" % [days_elapsed, GameManager.get_port_name(selected_port)]))

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
