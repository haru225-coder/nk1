extends Control
## 海图。风每一手发至多三向，选定后按日推进，逐日抽事件，到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

var origin_port: String = ""
var selected_port: String = ""
var _hand: PackedStringArray = PackedStringArray()
var _marker_at: Dictionary = {}
var _coast: Dictionary = {}
var _coast_ready := false

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
var _strip_line: RichTextLabel
var _condition_layer: Control
var _latest_note := ""


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

	# 顶匾。左栏船况和右栏日志收起来之后，日期和刚写下的一句留在这里。
	var strip := PanelContainer.new()
	strip.custom_minimum_size = Vector2(0, 80)
	strip.add_theme_stylebox_override("panel", UiTheme.plaque())
	root.add_child(strip)
	var strip_row := HBoxContainer.new()
	strip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	strip_row.add_theme_constant_override("separation", 12)
	strip.add_child(strip_row)
	_strip_line = RichTextLabel.new()
	_strip_line.bbcode_enabled = true
	_strip_line.fit_content = false
	_strip_line.scroll_active = false
	_strip_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip_line.clip_contents = true
	_strip_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_line.custom_minimum_size = Vector2(0, 56)
	UiTheme.style_body(_strip_line)
	strip_row.add_child(_strip_line)
	var cond_btn := Button.new()
	cond_btn.text = "船况"
	cond_btn.custom_minimum_size = Vector2(120, 40)
	cond_btn.pressed.connect(_toggle_condition)
	UiTheme.style_button(cond_btn, false)
	strip_row.add_child(cond_btn)

	# 图铺满匾和航向牌之间。三张 372 宽的牌仍在底栏。
	var center := PanelContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(center)
	var center_m := MarginContainer.new()
	_set_margins(center_m, 8)
	center.add_child(center_m)
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 160)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.clip_contents = true
	chart.draw.connect(func(): _draw_chart(chart))
	chart.gui_input.connect(_on_chart_input)
	center_m.add_child(chart)

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
	_mount_condition()


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


## 船况和这趟日志。点开才盖在图上，不占海图的宽。
func _mount_condition() -> void:
	var layer := Control.new()
	layer.name = "ConditionLayer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.05, 0.08, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_condition_dim)
	layer.add_child(dim)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	var sheet := PanelContainer.new()
	sheet.custom_minimum_size = Vector2(520, 0)
	sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	holder.add_child(sheet)
	var margin := MarginContainer.new()
	_set_margins(margin, 18)
	sheet.add_child(margin)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(480, 0)
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var head := Label.new()
	head.text = "船况"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_heading(head)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.scroll_active = false
	status_label.custom_minimum_size = Vector2(460, 0)
	UiTheme.style_body(status_label)
	body.add_child(status_label)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.custom_minimum_size = Vector2(460, 0)
	UiTheme.style_body(log_label)
	body.add_child(log_label)
	var close := Button.new()
	close.text = "合上"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(_close_condition)
	UiTheme.style_button(close, true)
	col.add_child(close)
	_condition_layer = layer


func _toggle_condition() -> void:
	if _condition_layer == null:
		return
	if _condition_layer.visible:
		_close_condition()
		return
	_condition_layer.visible = true
	move_child(_condition_layer, get_child_count() - 1)


func _close_condition() -> void:
	if _condition_layer != null:
		_condition_layer.visible = false


func _on_condition_dim(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			_close_condition()


func _open_event_panel() -> void:
	_close_condition()
	event_panel.visible = true


func _monsoon_short() -> String:
	var desc := Calendar.get_monsoon_desc()
	if desc.begins_with("东北"):
		return "东北风"
	if desc.begins_with("西南"):
		return "西南风"
	return "转换期"


func _plain_note(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\[[^\\]]*\\]")
	var plain := rx.sub(text, "", true)
	return plain.get_slice("\n", 0).strip_edges()


func _refresh_strip() -> void:
	if _strip_line == null:
		return
	var supply_d := Fleet.supply_days()
	var supply_color := UiTheme.MOSS
	if supply_d <= 3:
		supply_color = UiTheme.CINNABAR
	elif supply_d <= 7:
		supply_color = UiTheme.HONEY
	var line1 := "%s　%s　钱 %d　[color=#%s]水粮 %d 日[/color]" % [
		Calendar.get_date_string(),
		_monsoon_short(),
		GameState.money,
		UiTheme.hex(supply_color),
		supply_d,
	]
	var note := _latest_note
	if sailing:
		var pct := 0
		if total_li > 0.0:
			pct = int(clampf((total_li - remaining_li) / total_li, 0.0, 1.0) * 100.0)
		note = "航行中　第 %d 日　已行 %d / 100　余程 %d 里" % [days_elapsed, pct, int(remaining_li)]
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	_strip_line.text = line1 + "\n[color=#%s]%s[/color]" % [dim, note]


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
	_refresh_strip()
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

const CHART_COAST := "res://data/chart_coast.json"

## 等比投影已解锁港口的经纬度。经度按平均纬度收窄，否则高纬处会被拉宽。
## 系数 0.78 与 tools/verify_economy.py 的海图投影校验锁在一起，不要单独改。
func _draw_chart(c: Control) -> void:
	var pts: Array = GameManager.unlocked_ports()
	if pts.size() < 2:
		return

	var size := c.size
	if size.x < 8.0 or size.y < 8.0:
		return
	var frame := _chart_frame(pts, size)

	RenderingServer.canvas_item_set_clip(c.get_canvas_item(), true)
	_draw_chart_leaf(c, size)
	_draw_world(c, frame, size)
	_draw_monsoon(c, size, frame)

	# 已知航路：淡墨勾出港口间的连接关系。绢纸上不用泥金，否则线会发飘。
	for p in pts:
		var a: Vector2 = _chart_xy(frame, float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
		for cid in p.get("connections", []):
			var q := GameManager.get_port_by_id(cid)
			if q.is_empty() or not GameState.is_chapter_reached(q.get("unlock", "ch1")):
				continue
			var b: Vector2 = _chart_xy(frame, float(q.get("lat", 0.0)), float(q.get("lon", 0.0)))
			_draw_rhumb(c, a, b, Color(0.40, 0.26, 0.12, 0.62))

	# 当前航段
	if selected_port != "":
		var o := GameManager.get_port_by_id(origin_port)
		var d := GameManager.get_port_by_id(selected_port)
		if not o.is_empty() and not d.is_empty():
			var a: Vector2 = _chart_xy(frame, float(o.get("lat", 0.0)), float(o.get("lon", 0.0)))
			var b: Vector2 = _chart_xy(frame, float(d.get("lat", 0.0)), float(d.get("lon", 0.0)))
			var along := b - a
			var span := along.length()
			if span > 22.0:
				var step := along / span
				a += step * 9.0
				b -= step * 9.0
			var wf := Voyage.wind_factor(Voyage.bearing(origin_port, selected_port))
			# 顺风泛绿、逆风泛红——季风是否有利，一眼能看出来
			# 绢纸上的顺风/横风/逆风要比面板上的亮色深一档，否则会糊进纸色。
			var col := Color(0.30, 0.42, 0.22) if wf >= 1.15 else (
				Color(0.62, 0.24, 0.16) if wf <= 0.75 else Color(0.55, 0.36, 0.10))
			c.draw_line(a, b, Color(col, 0.35), 5.0)
			c.draw_line(a, b, col, 2.5)

	var font := UiTheme.font()
	var marks: Array[Dictionary] = []
	_marker_at = {}
	for p in pts:
		var pid: String = p.get("id", "")
		var v: Vector2 = _chart_xy(frame, float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))
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
		var radius := 5.2 if (is_here or is_target) else 4.0
		c.draw_colored_polygon(PackedVector2Array([
			v + Vector2(0, -radius),
			v + Vector2(radius, 0),
			v + Vector2(0, radius),
			v + Vector2(-radius, 0),
		]), dot_col)
		c.draw_circle(v, 1.35, Color(0.96, 0.90, 0.78, dot_col.a))
		if is_here or is_target:
			c.draw_arc(v, radius + 3.4, 0, TAU, 24, dot_col, 1.3)
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
	_draw_sea_names(c, frame, size, font, occupied)
	_draw_chart_title(c, frame, size, font, occupied)
	_draw_margin_degrees(c, frame, size, font, occupied)
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
	_draw_scale(c, frame, size, font, occupied)
	_draw_compass(c, size, occupied)
	_draw_chart_frame(c, size)


func _chart_frame(pts: Array, size: Vector2) -> Dictionary:
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
	var scale := minf(size.x / span_x, size.y / span_y) * 0.78
	return {
		"mean_lat": mean_lat,
		"mean_lon": mean_lon,
		"kx": kx,
		"scale": scale,
		"mid": size * 0.5,
	}


func _chart_xy(frame: Dictionary, lat: float, lon: float) -> Vector2:
	var mid: Vector2 = frame["mid"]
	var kx := float(frame["kx"])
	var scale := float(frame["scale"])
	return mid + Vector2((lon - float(frame["mean_lon"])) * kx * scale, -(lat - float(frame["mean_lat"])) * scale)


func _chart_unproject(frame: Dictionary, p: Vector2) -> Vector2:
	var scale := float(frame["scale"])
	var kx := float(frame["kx"])
	if scale < 0.001 or kx < 0.001:
		return Vector2.ZERO
	var mid: Vector2 = frame["mid"]
	var lon := (p.x - mid.x) / (kx * scale) + float(frame["mean_lon"])
	var lat := -(p.y - mid.y) / scale + float(frame["mean_lat"])
	return Vector2(lon, lat)


func _coast_data() -> Dictionary:
	if _coast_ready:
		return _coast
	_coast_ready = true
	if not FileAccess.file_exists(CHART_COAST):
		return _coast
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHART_COAST))
	if parsed is Dictionary:
		_coast = parsed
	return _coast


func _ring_has(lat: float, lon: float, ring: Array) -> bool:
	var inside := false
	var n := ring.size()
	if n < 3:
		return false
	var j := n - 1
	for i in n:
		var a: Array = ring[i]
		var b: Array = ring[j]
		if a.size() < 2 or b.size() < 2:
			j = i
			continue
		var yi := float(a[0])
		var xi := float(a[1])
		var yj := float(b[0])
		var xj := float(b[1])
		var denom := yj - yi
		if is_zero_approx(denom):
			j = i
			continue
		if ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / denom + xi):
			inside = not inside
		j = i
	return inside


func _ashore(lat: float, lon: float) -> bool:
	for ring in _coast_data().get("land", []):
		if ring is Array and _ring_has(lat, lon, ring):
			return true
	return false


func _project_ring(frame: Dictionary, ring: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for pair in ring:
		if pair is Array and pair.size() >= 2:
			pts.append(_chart_xy(frame, float(pair[0]), float(pair[1])))
	return pts


## 绢纸上的东亚海岸。陆地盖住西边的空白，外海往东略深，海名和罗盘留在海上。
func _draw_world(c: Control, frame: Dictionary, size: Vector2) -> void:
	var data := _coast_data()
	if data.is_empty():
		return
	_draw_sea_depth(c, size)
	_draw_graticule(c, frame, size)
	_draw_waves(c, frame, size)
	var harbors := _harbor_marks(frame)
	var lands: Array = data.get("land", [])
	var mainland := Color(0.776, 0.635, 0.408, 1.0)
	var island := Color(0.690, 0.604, 0.392, 1.0)
	var shore := Color(0.42, 0.26, 0.12, 0.55)
	var ink := Color(0.24, 0.13, 0.06, 1.0)
	for i in lands.size():
		var ring: Array = lands[i]
		var pts := _project_ring(frame, ring)
		if pts.size() < 3:
			continue
		var soft := _soft_coast(frame, ring, pts, i == 0)
		c.draw_colored_polygon(soft, mainland if i == 0 else island)
		var stroke := soft.duplicate()
		stroke.append(soft[0])
		c.draw_polyline(stroke, shore, 4.2, true)
		c.draw_polyline(stroke, ink, 1.55, true)
		_draw_shoal(c, frame, soft, i == 0, harbors)
	_draw_land_grain(c, frame, size)
	_draw_inland(c, frame, size)
	_draw_ranges(c, frame, size)
	var river_col := Color(0.32, 0.48, 0.55, 0.80)
	for river in data.get("rivers", []):
		if river is Array:
			var river_pts := _project_ring(frame, river)
			if river_pts.size() >= 2:
				_draw_river(c, frame, river_pts, river_col)
	_draw_reefs(c, frame, size)


func _geo_bounds(frame: Dictionary, size: Vector2) -> Dictionary:
	var corners: Array[Vector2] = [
		_chart_unproject(frame, Vector2.ZERO),
		_chart_unproject(frame, Vector2(size.x, 0)),
		_chart_unproject(frame, size),
		_chart_unproject(frame, Vector2(0, size.y)),
	]
	var lon_min := corners[0].x
	var lon_max := corners[0].x
	var lat_min := corners[0].y
	var lat_max := corners[0].y
	for corner in corners:
		lon_min = minf(lon_min, corner.x)
		lon_max = maxf(lon_max, corner.x)
		lat_min = minf(lat_min, corner.y)
		lat_max = maxf(lat_max, corner.y)
	return {
		"lon_min": lon_min,
		"lon_max": lon_max,
		"lat_min": lat_min,
		"lat_max": lat_max,
	}


## 近图 5 度，中图 10 度，远图 20 度。线和边上的数字用同一档。
func _grid_step(span: float) -> float:
	if span > 70.0:
		return 20.0
	if span > 36.0:
		return 10.0
	return 5.0


## 海角收圆、长边略向陆弯。凹进去的海湾保持原样，免得把湾口封死。
func _soft_coast(frame: Dictionary, ring: Array, pts: PackedVector2Array, mainland: bool) -> PackedVector2Array:
	var n := mini(ring.size(), pts.size())
	var count := n
	if n >= 2 and pts[0].distance_to(pts[n - 1]) < 0.8:
		count = n - 1
	if count < 3:
		return pts
	var out := PackedVector2Array()
	for i in count:
		var i0 := (i + count - 1) % count
		var i1 := (i + 1) % count
		var prev: Vector2 = pts[i0]
		var cur: Vector2 = pts[i]
		var nxt: Vector2 = pts[i1]
		var hard := mainland and (
			float(ring[i][1]) < 104.0
			or float(ring[i0][1]) < 104.0
			or float(ring[i1][1]) < 104.0
		)
		var back := cur - prev
		var fore := nxt - cur
		var back_len := back.length()
		var fore_len := fore.length()
		if hard or back_len < 8.0 or fore_len < 8.0:
			out.append(cur)
			continue
		var cut := minf(8.0, minf(back_len, fore_len) * 0.28)
		var a := cur - back / back_len * cut
		var b := cur + fore / fore_len * cut
		var chord_mid := (a + b) * 0.5
		var geo := _chart_unproject(frame, chord_mid)
		if not _ashore(geo.y, geo.x):
			out.append(cur)
			continue
		var dir := b - a
		if dir.length() < 0.5:
			out.append(cur)
			continue
		var nrm := Vector2(-dir.y, dir.x).normalized()
		var sea_probe := _chart_unproject(frame, chord_mid + nrm * 4.0)
		if _ashore(sea_probe.y, sea_probe.x):
			nrm = -nrm
		out.append(a)
		# 窄岬只削角，不再往里拱，免得两侧对穿。
		var bow_amp := 2.8
		var deep := _chart_unproject(frame, chord_mid - nrm * bow_amp * 2.4)
		if _ashore(deep.y, deep.x):
			out.append(chord_mid - nrm * bow_amp)
		out.append(b)
	if out.size() < 3:
		return pts
	return _bow_long_edges(frame, out)


func _bow_long_edges(frame: Dictionary, poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		out.append(a)
		var span := b - a
		var length := span.length()
		if length < 22.0:
			continue
		var nrm := Vector2(-span.y, span.x).normalized()
		var sea_probe := _chart_unproject(frame, (a + b) * 0.5 + nrm * 4.0)
		if _ashore(sea_probe.y, sea_probe.x):
			nrm = -nrm
		var amp := minf(5.5, length * 0.055)
		var stations := [0.5]
		if length >= 78.0:
			stations = [0.34, 0.67]
		for t in stations:
			var at := a.lerp(b, t)
			var bow := at - nrm * amp
			var geo := _chart_unproject(frame, bow)
			var deep := _chart_unproject(frame, at - nrm * amp * 2.3)
			if _ashore(geo.y, geo.x) and _ashore(deep.y, deep.x):
				out.append(bow)
	return out


func _draw_river(c: Control, frame: Dictionary, pts: PackedVector2Array, col: Color) -> void:
	var curved := PackedVector2Array()
	var last := pts.size() - 1
	for i in last:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		curved.append(a)
		var span := b - a
		var length := span.length()
		if length < 28.0:
			continue
		var nrm := Vector2(-span.y, span.x).normalized()
		var amp := minf(7.5, length * 0.045)
		if i % 2 == 1:
			amp = -amp
		var waves := 2 if length >= 90.0 else 1
		var steps := 5 * waves
		var extra := PackedVector2Array()
		var ok := true
		for s in steps:
			var t := float(s + 1) / float(steps + 1)
			var bend := a.lerp(b, t) + nrm * sin(t * TAU * float(waves)) * amp
			var geo := _chart_unproject(frame, bend)
			if not _ashore(geo.y, geo.x):
				ok = false
				break
			extra.append(bend)
		if ok:
			for bend in extra:
				curved.append(bend)
	curved.append(pts[last])
	c.draw_polyline(curved, Color(0.55, 0.68, 0.72, 0.42), 2.8, true)
	c.draw_polyline(curved, col, 1.15, true)


func _draw_graticule(c: Control, frame: Dictionary, size: Vector2) -> void:
	var bounds := _geo_bounds(frame, size)
	var col := Color(0.45, 0.32, 0.16, 0.18)
	var lat_step := _grid_step(float(bounds["lat_max"]) - float(bounds["lat_min"]))
	var lon_step := _grid_step(float(bounds["lon_max"]) - float(bounds["lon_min"]))
	var lat := floorf(float(bounds["lat_min"]) / lat_step) * lat_step
	while lat <= float(bounds["lat_max"]):
		_draw_dashed_line(
			c,
			_chart_xy(frame, lat, float(bounds["lon_min"])),
			_chart_xy(frame, lat, float(bounds["lon_max"])),
			col, 1.0, 9.0, 7.0)
		lat += lat_step
	var lon := floorf(float(bounds["lon_min"]) / lon_step) * lon_step
	while lon <= float(bounds["lon_max"]):
		_draw_dashed_line(
			c,
			_chart_xy(frame, float(bounds["lat_min"]), lon),
			_chart_xy(frame, float(bounds["lat_max"]), lon),
			col, 1.0, 9.0, 7.0)
		lon += lon_step


func _draw_dashed_line(c: Control, a: Vector2, b: Vector2, col: Color, width: float, dash: float, gap: float) -> void:
	var delta := b - a
	var total := delta.length()
	if total < 1.0:
		return
	var dir := delta / total
	var t := 0.0
	while t < total:
		var t2 := minf(t + dash, total)
		c.draw_line(a + dir * t, a + dir * t2, col, width)
		t += dash + gap


## 东边外海略深。叠色仍是浅青，绢底要透出来，不能画成夜航图。
func _draw_sea_depth(c: Control, size: Vector2) -> void:
	var strips := 16
	for i in strips:
		var t := float(i) / float(strips - 1)
		var x0 := size.x * float(i) / float(strips)
		var w := size.x / float(strips) + 1.0
		var alpha := 0.04 + t * t * 0.28
		c.draw_rect(Rect2(x0, 0, w, size.y), Color(0.50, 0.78, 0.84, alpha), true)


func _draw_waves(c: Control, frame: Dictionary, size: Vector2) -> void:
	var col := Color(0.22, 0.40, 0.46, 0.32)
	var step := 58.0
	var row := 0
	var y := 34.0
	while y < size.y - 18.0:
		var x := 26.0 + float(row % 3) * 18.0
		while x < size.x - 18.0:
			var salt := int(x) * 3 + row * 5
			if salt % 5 == 0:
				x += step
				continue
			var at := Vector2(
				x + float((salt * 17) % 17) - 8.0,
				y + float((salt * 13) % 13) - 6.0)
			if not _open_water(frame, at, 22.0):
				x += step
				continue
			var lift := 1.0 + float(salt % 3) * 0.4
			var span := 5.0 + float((salt / 3) % 3) * 1.6
			var tilt := float((salt % 5) - 2) * 0.35
			c.draw_polyline(PackedVector2Array([
				at + Vector2(-span, tilt),
				at + Vector2(-span * 0.25, -lift),
				at + Vector2(span * 0.35, tilt * 0.3),
				at + Vector2(span, -lift * 0.45 + tilt),
			]), col, 1.0, true)
			x += step
		y += 40.0
		row += 1


func _open_water(frame: Dictionary, p: Vector2, pad: float) -> bool:
	var here := _chart_unproject(frame, p)
	if _ashore(here.y, here.x):
		return false
	var probes: Array[Vector2] = [
		Vector2(pad, 0.0),
		Vector2(-pad, 0.0),
		Vector2(0.0, pad * 0.75),
		Vector2(0.0, -pad * 0.75),
	]
	for dir in probes:
		var geo := _chart_unproject(frame, p + dir)
		if _ashore(geo.y, geo.x):
			return false
	return true


func _harbor_marks(frame: Dictionary) -> PackedVector2Array:
	var marks := PackedVector2Array()
	for p in GameManager.unlocked_ports():
		marks.append(_chart_xy(frame, float(p.get("lat", 0.0)), float(p.get("lon", 0.0))))
	return marks


func _near_harbor(harbors: PackedVector2Array, p: Vector2, radius: float) -> bool:
	for mark in harbors:
		if mark.distance_to(p) < radius:
			return true
	return false


## 岸线外侧两三道浅水，内侧一条沙岸。大陆西边的封口边不画。港点附近让开。
func _draw_shoal(c: Control, frame: Dictionary, pts: PackedVector2Array, mainland: bool, harbors: PackedVector2Array) -> void:
	var n := pts.size()
	if n < 2:
		return
	var bands: Array = [
		{"off": 5.0, "width": 5.0, "col": Color(0.78, 0.74, 0.56, 0.55), "clear": 11.0},
		{"off": 11.0, "width": 2.4, "col": Color(0.32, 0.52, 0.56, 0.38), "clear": 16.0},
		{"off": 18.0, "width": 8.0, "col": Color(0.40, 0.64, 0.72, 0.14), "clear": 26.0},
		{"off": 30.0, "width": 10.0, "col": Color(0.34, 0.58, 0.68, 0.16), "clear": 38.0},
		{"off": 44.0, "width": 12.0, "col": Color(0.28, 0.52, 0.64, 0.14), "clear": 52.0},
	]
	var beach := Color(0.88, 0.76, 0.54, 0.78)
	var page := Rect2(Vector2(-40, -40), c.size + Vector2(80, 80))
	for i in n:
		var j := (i + 1) % n
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if mainland:
			var ga := _chart_unproject(frame, a)
			var gb := _chart_unproject(frame, b)
			if ga.x < 104.0 or gb.x < 104.0:
				continue
		if not page.has_point(a) and not page.has_point(b):
			continue
		var delta := b - a
		if delta.length() < 3.0:
			continue
		var dir := delta.normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var geo := _chart_unproject(frame, (a + b) * 0.5 + nrm * 7.0)
		if _ashore(geo.y, geo.x):
			nrm = -nrm
		var mid_beach := (a + b) * 0.5 - nrm * 6.0
		if not _near_harbor(harbors, mid_beach, 10.0):
			c.draw_line(a - nrm * 6.0, b - nrm * 6.0, beach, 7.0)
		for band in bands:
			var spec: Dictionary = band
			var off := float(spec["off"])
			var mid := (a + b) * 0.5 + nrm * off
			if _near_harbor(harbors, mid, float(spec["clear"])):
				continue
			c.draw_line(a + nrm * off, b + nrm * off, spec["col"], float(spec["width"]))


func _draw_land_grain(c: Control, frame: Dictionary, size: Vector2) -> void:
	var col := Color(0.48, 0.32, 0.14, 0.28)
	var y := 16.0
	var row := 0
	while y < size.y - 8.0:
		var x := 12.0 + float(row % 3) * 7.0
		while x < size.x - 8.0:
			if _deep_inland(frame, Vector2(x, y), 14.0):
				c.draw_line(Vector2(x, y), Vector2(x + 5.0, y + 1.4), col, 1.0)
			x += 18.0
		y += 13.0
		row += 1


## 离岸远一点的内陆铺一层暖赭，沿海那条沙岸留亮。
func _draw_inland(c: Control, frame: Dictionary, size: Vector2) -> void:
	var col := Color(0.52, 0.36, 0.16, 0.18)
	var y := 20.0
	var row := 0
	while y < size.y - 12.0:
		var x := 16.0 + float(row % 2) * 10.0
		while x < size.x - 12.0:
			if _deep_inland(frame, Vector2(x, y)):
				c.draw_circle(Vector2(x, y), 12.0, col)
			x += 18.0
		y += 16.0
		row += 1


func _deep_inland(frame: Dictionary, p: Vector2, pad: float = 30.0) -> bool:
	var here := _chart_unproject(frame, p)
	if not _ashore(here.y, here.x):
		return false
	var probes: Array[Vector2] = [Vector2(pad, 0), Vector2(-pad, 0), Vector2(0, pad), Vector2(0, -pad)]
	for dir in probes:
		var geo := _chart_unproject(frame, p + dir)
		if not _ashore(geo.y, geo.x):
			return false
	return true


func _draw_ranges(c: Control, frame: Dictionary, size: Vector2) -> void:
	var chains: Array = [
		[[27.2, 117.8], [26.4, 117.0], [25.6, 116.4]],
		[[28.8, 118.4], [28.0, 117.6], [27.2, 116.8]],
		[[32.4, 116.0], [31.6, 114.4], [30.6, 112.6]],
		[[24.2, 112.4], [23.6, 110.8], [23.2, 109.2]],
		[[35.2, 118.2], [34.4, 116.6], [33.4, 114.8]],
		[[24.5, 121.15], [23.7, 120.85], [22.7, 120.55]],
		[[19.7, 109.5], [19.2, 109.9]],
		[[38.2, 128.0], [36.8, 128.3], [35.4, 127.6]],
	]
	var col := Color(0.36, 0.22, 0.10, 0.78)
	var page := Rect2(Vector2.ZERO, size)
	for chain in chains:
		var prev := Vector2.ZERO
		var has_prev := false
		for pair in chain:
			var lat := float(pair[0])
			var lon := float(pair[1])
			if not _ashore(lat, lon):
				has_prev = false
				continue
			var p := _chart_xy(frame, lat, lon)
			if not page.has_point(p):
				has_prev = false
				continue
			_draw_peak(c, p, col, 1.0)
			if has_prev:
				c.draw_line(prev, p, Color(col, 0.20), 0.9)
				if prev.distance_to(p) > 18.0:
					_draw_peak(c, (prev + p) * 0.5, col, 0.72)
			prev = p
			has_prev = true


func _draw_peak(c: Control, p: Vector2, col: Color, scale: float) -> void:
	var s := scale
	c.draw_polyline(PackedVector2Array([
		p + Vector2(-7.2, 3.4) * s,
		p + Vector2(-4.0, -0.6) * s,
		p + Vector2(-1.6, 2.2) * s,
	]), col, 1.15, true)
	c.draw_polyline(PackedVector2Array([
		p + Vector2(-2.4, 2.4) * s,
		p + Vector2(0.0, -6.4) * s,
		p + Vector2(2.4, 2.4) * s,
	]), col, 1.25, true)
	c.draw_polyline(PackedVector2Array([
		p + Vector2(1.6, 2.2) * s,
		p + Vector2(4.2, -1.0) * s,
		p + Vector2(7.4, 3.4) * s,
	]), col, 1.15, true)


func _draw_reefs(c: Control, frame: Dictionary, size: Vector2) -> void:
	var spots: Array[Vector2] = [
		Vector2(119.9, 24.2),
		Vector2(122.4, 26.6),
		Vector2(114.8, 21.6),
		Vector2(125.2, 29.4),
	]
	var col := Color(0.30, 0.40, 0.42, 0.55)
	var page := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	for spot in spots:
		if _ashore(spot.y, spot.x):
			continue
		var p := _chart_xy(frame, spot.y, spot.x)
		if not page.has_point(p):
			continue
		c.draw_line(p + Vector2(-3.5, -2.5), p + Vector2(3.5, 2.5), col, 1.0)
		c.draw_line(p + Vector2(-3.5, 2.5), p + Vector2(3.5, -2.5), col, 1.0)


## 已知航路用虚线，港点两边留出空，菱形才站得住。
func _draw_rhumb(c: Control, a: Vector2, b: Vector2, col: Color) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 18.0:
		c.draw_line(a, b, col, 1.15)
		return
	var dir := delta / length
	var start := a + dir * 8.0
	var end := b - dir * 8.0
	var span := end - start
	var total := span.length()
	var step_dir := span / total
	var t := 0.0
	var dash := 6.0
	var gap := 4.5
	while t < total:
		var t2 := minf(t + dash, total)
		c.draw_line(start + step_dir * t, start + step_dir * t2, col, 1.15)
		t += dash + gap


func _draw_sea_names(c: Control, frame: Dictionary, size: Vector2, font: Font, occupied: Array[Rect2]) -> void:
	var bounds := Rect2(Vector2(12, 30), size - Vector2(24, 44))
	var col := Color(0.30, 0.20, 0.10, 0.78)
	var gap := 5.0
	for entry in _coast_data().get("seas", []):
		if not (entry is Dictionary):
			continue
		var text := str(entry.get("name", ""))
		var lat := float(entry.get("lat", 0.0))
		var lon := float(entry.get("lon", 0.0))
		if text == "" or _ashore(lat, lon):
			continue
		var baseline := _chart_xy(frame, lat, lon) + Vector2(0, 4)
		var width := _spaced_text_width(font, text, UiTheme.SIZE_FOOT, gap)
		var metric := _ink_metrics(font)
		var rect := Rect2(
			baseline + Vector2(-3.0, -metric.x - 3.0),
			Vector2(width + 6.0, metric.x + metric.y + 6.0)
		)
		if not bounds.encloses(rect) or _chart_label_hits(rect, occupied):
			continue
		_draw_spaced_text(c, font, baseline, text, UiTheme.SIZE_FOOT, col, gap)
		c.draw_line(
			Vector2(baseline.x, baseline.y + 3.0),
			Vector2(baseline.x + width, baseline.y + 3.0),
			Color(col.r, col.g, col.b, 0.45),
			0.8)
		occupied.append(rect)


func _spaced_text_width(font: Font, text: String, size: int, gap: float) -> float:
	var width := 0.0
	for i in text.length():
		width += font.get_string_size(text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if i < text.length() - 1:
			width += gap
	return width


func _draw_spaced_text(c: Control, font: Font, baseline: Vector2, text: String, size: int, col: Color, gap: float) -> void:
	var x := baseline.x
	for i in text.length():
		var ch := text.substr(i, 1)
		c.draw_string(font, Vector2(x, baseline.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + gap


func _draw_chart_title(c: Control, frame: Dictionary, size: Vector2, font: Font, occupied: Array[Rect2]) -> void:
	var text := "东南海图"
	var sub := "针路"
	var title_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY).x
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
	var box := Vector2(maxf(title_w, sub_w) + 22.0, 48.0)
	# 经度, 纬度。都在陆上，图放大到福建时也能落在画面左侧。
	var spots: Array[Vector2] = [
		Vector2(113.8, 27.4),
		Vector2(108.5, 30.2),
		Vector2(112.0, 26.0),
		Vector2(106.5, 22.5),
	]
	var page := Rect2(Vector2(16, 16), size - Vector2(32, 32))
	for spot in spots:
		if not _ashore(spot.y, spot.x):
			continue
		var anchor := _chart_xy(frame, spot.y, spot.x)
		if anchor.x > size.x * 0.62:
			continue
		var rect := Rect2(anchor + Vector2(-10.0, -20.0), box)
		if not page.encloses(rect) or _chart_label_hits(rect.grow(6.0), occupied):
			continue
		var ink := Color(0.32, 0.18, 0.08, 0.88)
		var edge := Color(0.42, 0.26, 0.12, 0.72)
		c.draw_rect(rect, Color(0.95, 0.89, 0.76, 0.94), true)
		c.draw_rect(rect, edge, false, 1.3)
		var inner := rect.grow(-3.0)
		c.draw_rect(inner, Color(edge, 0.40), false, 1.0)
		c.draw_string(font, rect.position + Vector2(11.0, 20.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY, ink)
		c.draw_string(font, rect.position + Vector2(11.0, 38.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, Color(ink, 0.62))
		occupied.append(rect)
		return


## 图廓上的经纬度。近图 5 度一格，远图放宽，碰到港签或图题就空过。
func _draw_margin_degrees(c: Control, frame: Dictionary, size: Vector2, font: Font, occupied: Array[Rect2]) -> void:
	var bounds := _geo_bounds(frame, size)
	var ink := Color(0.32, 0.18, 0.08, 0.92)
	var chip := Color(0.95, 0.89, 0.76, 0.90)
	var page := Rect2(Vector2(6, 8), size - Vector2(12, 16))
	var lat_step := _grid_step(float(bounds["lat_max"]) - float(bounds["lat_min"]))
	var lon_step := _grid_step(float(bounds["lon_max"]) - float(bounds["lon_min"]))
	var lat := ceilf(float(bounds["lat_min"]) / lat_step) * lat_step
	while lat < float(bounds["lat_max"]):
		var y := _chart_xy(frame, lat, float(frame["mean_lon"])).y
		var text := "%d度" % roundi(lat)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
		var baseline := Vector2(12.0, y + 4.0)
		var rect := Rect2(baseline + Vector2(-2.0, -14.0), Vector2(width + 6.0, 18.0))
		if page.encloses(rect) and not _chart_label_hits(rect, occupied):
			c.draw_rect(rect, chip, true)
			c.draw_line(Vector2(6.0, y), Vector2(11.0, y), ink, 1.0)
			c.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, ink)
			occupied.append(rect)
		lat += lat_step
	var lon := ceilf(float(bounds["lon_min"]) / lon_step) * lon_step
	while lon < float(bounds["lon_max"]):
		var x := _chart_xy(frame, float(frame["mean_lat"]), lon).x
		var text := "%d度" % roundi(lon)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
		var baseline := Vector2(x - width * 0.5, 26.0)
		var rect := Rect2(baseline + Vector2(-2.0, -14.0), Vector2(width + 6.0, 18.0))
		if page.encloses(rect) and not _chart_label_hits(rect, occupied):
			c.draw_rect(rect, chip, true)
			c.draw_line(Vector2(x, 6.0), Vector2(x, 12.0), ink, 1.0)
			c.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, ink)
			occupied.append(rect)
		lon += lon_step


## 纬度上一里约 193 宋里。条长跟着当前图尺走，太长就改二百里、一百里。
func _draw_scale(c: Control, frame: Dictionary, size: Vector2, font: Font, occupied: Array[Rect2]) -> void:
	var li_per_deg := (Voyage.EARTH_R_KM * PI / 180.0) / Voyage.KM_PER_LI
	var scale := float(frame["scale"])
	if li_per_deg < 1.0 or scale < 0.001:
		return
	var choices: Array[Dictionary] = [
		{"li": 200.0, "label": "二百里"},
		{"li": 500.0, "label": "五百里"},
		{"li": 1000.0, "label": "千里"},
	]
	var pick: Dictionary = choices[0]
	var pick_px := 200.0 / li_per_deg * scale
	for choice in choices:
		var trial := float(choice["li"]) / li_per_deg * scale
		if trial <= 156.0 and trial >= pick_px:
			pick = choice
			pick_px = trial
	if pick_px > 156.0:
		pick = {"li": 100.0, "label": "一百里"}
		pick_px = 100.0 / li_per_deg * scale
	var label := str(pick["label"])
	var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT).x
	var bar := maxf(pick_px, 28.0)
	var box := Vector2(maxf(bar, text_w) + 18.0, 40.0)
	var candidates: Array[Vector2] = [
		Vector2(16.0, size.y - box.y - 12.0),
		Vector2(size.x * 0.5 - box.x * 0.5, size.y - box.y - 12.0),
		Vector2(16.0, 40.0),
	]
	var origin := Vector2.ZERO
	var found := false
	for cand in candidates:
		var rect := Rect2(cand, box)
		if cand.x < 8.0 or cand.y < 8.0:
			continue
		if cand.x + box.x > size.x - 8.0 or cand.y + box.y > size.y - 8.0:
			continue
		if _chart_label_hits(rect, occupied):
			continue
		origin = cand
		found = true
		break
	if not found:
		return
	var rect := Rect2(origin, box)
	var ink := Color(0.32, 0.18, 0.08, 0.88)
	var edge := Color(0.45, 0.32, 0.16, 0.62)
	c.draw_rect(rect, Color(0.95, 0.89, 0.76, 0.94), true)
	c.draw_rect(rect, edge, false, 1.0)
	c.draw_string(font, origin + Vector2(9.0, 15.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, ink)
	var x0 := origin.x + 9.0
	var y := origin.y + 27.0
	var half := bar * 0.5
	c.draw_rect(Rect2(x0, y - 3.5, half, 7.0), ink, true)
	c.draw_rect(Rect2(x0, y - 3.5, bar, 7.0), ink, false, 1.1)
	c.draw_line(Vector2(x0 + half, y - 3.5), Vector2(x0 + half, y + 3.5), ink, 1.0)
	occupied.append(rect)


func _draw_compass(c: Control, size: Vector2, occupied: Array[Rect2]) -> void:
	var radius := clampf(minf(size.x, size.y) * 0.085, 22.0, 34.0)
	var extent := radius + 16.0
	var candidates: Array[Vector2] = [
		Vector2(size.x - extent - 14.0, size.y - extent - 12.0),
		Vector2(extent + 16.0, size.y - extent - 12.0),
		Vector2(size.x - extent - 14.0, extent + 22.0),
	]
	var center := Vector2.ZERO
	var found := false
	for cand in candidates:
		var box := Rect2(cand - Vector2(extent, extent), Vector2(extent * 2.0, extent * 2.0))
		if _chart_label_hits(box, occupied):
			continue
		center = cand
		found = true
		break
	if not found:
		return
	var ink := Color(0.32, 0.18, 0.08, 0.88)
	var pale := Color(0.45, 0.32, 0.16, 0.55)
	c.draw_circle(center, radius + 8.0, Color(0.95, 0.89, 0.76, 0.92))
	c.draw_arc(center, radius, 0.0, TAU, 48, ink, 1.25)
	c.draw_arc(center, radius - 5.0, 0.0, TAU, 40, pale, 1.0)
	var dirs: Array[Vector2] = [
		Vector2(0, -1),
		Vector2(0.7071, -0.7071),
		Vector2(1, 0),
		Vector2(0.7071, 0.7071),
		Vector2(0, 1),
		Vector2(-0.7071, 0.7071),
		Vector2(-1, 0),
		Vector2(-0.7071, -0.7071),
	]
	for i in dirs.size():
		var dir: Vector2 = dirs[i]
		var inner := radius - (8.0 if i % 2 == 0 else 4.5)
		c.draw_line(center + dir * inner, center + dir * (radius - 1.2), ink, 1.15 if i % 2 == 0 else 0.9)
	c.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius + 3.0),
		center + Vector2(-4.6, 1.5),
		center,
		center + Vector2(4.6, 1.5),
	]), Color(0.62, 0.22, 0.14, 0.92))
	c.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, radius - 3.0),
		center + Vector2(4.2, -1.5),
		center,
		center + Vector2(-4.2, -1.5),
	]), Color(0.32, 0.18, 0.08, 0.55))
	var font := UiTheme.font()
	var names: PackedStringArray = ["北", "东", "南", "西"]
	var place: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i in names.size():
		var ch := names[i]
		var glyph := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT)
		var at := center + place[i] * (radius + 11.0)
		var baseline := Vector2(at.x - glyph.x * 0.5, at.y + glyph.y * 0.32)
		c.draw_string(font, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, ink)


## 海图中栏是一张绢纸，不再在熟漆面板上再铺一层熟漆。
func _draw_chart_leaf(c: Control, size: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.91, 0.84, 0.70, 1.0), true)
	_draw_paper(c, size)


## 纸纹很淡，海色盖上去之后西边浅水还能看见丝缕。
func _draw_paper(c: Control, size: Vector2) -> void:
	var col := Color(0.55, 0.40, 0.22, 0.08)
	var y := 4.0
	var row := 0
	while y < size.y:
		var x := fmod(float(row * 13), 17.0)
		while x < size.x:
			var span := 7.0 + fmod(float(row * 5) + x, 11.0)
			var x1 := minf(x + span, size.x)
			c.draw_line(Vector2(x, y), Vector2(x1, y + 0.3), col, 1.0)
			x += span + 18.0
		y += 6.0
		row += 1


func _draw_chart_frame(c: Control, size: Vector2) -> void:
	var frame := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	if frame.size.x < 8.0 or frame.size.y < 8.0:
		return
	var edge := Color(0.45, 0.32, 0.16, 0.55)
	c.draw_rect(frame, edge, false, 1.0)
	var inner := frame.grow(-3.0)
	if inner.size.x > 4.0 and inner.size.y > 4.0:
		c.draw_rect(inner, Color(0.45, 0.32, 0.16, 0.28), false, 1.0)
	var ink := Color(0.42, 0.26, 0.12, 0.78)
	var arm := 12.0
	var corners: Array[Vector2] = [
		frame.position,
		Vector2(frame.end.x, frame.position.y),
		Vector2(frame.position.x, frame.end.y),
		frame.end,
	]
	var signs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for i in corners.size():
		var p: Vector2 = corners[i]
		var s: Vector2 = signs[i]
		c.draw_line(p, p + Vector2(s.x * arm, 0.0), ink, 1.6)
		c.draw_line(p, p + Vector2(0.0, s.y * arm), ink, 1.6)


## 季风方向：全图统一的斜箭头。风信是大尺度的，不必逐点画。陆地上不画。
func _draw_monsoon(c: Control, size: Vector2, frame: Dictionary) -> void:
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
			var geo := _chart_unproject(frame, mid)
			if not _ashore(geo.y, geo.x):
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
	_latest_note = _plain_note(text)
	_refresh_strip()


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

	_open_event_panel()


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
	_close_condition()
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
	_open_event_panel()


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
	_open_event_panel()


func _return_to_port() -> void:
	Fleet.at_sea = false
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
