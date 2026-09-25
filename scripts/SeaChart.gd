extends Control
## 海图。风每一手发至多三向，选定后按日推进，逐日抽事件，到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

var origin_port: String = ""
var selected_port: String = ""
var _hand: PackedStringArray = PackedStringArray()

## 航行状态
var sailing: bool = false
var remaining_li: float = 0.0
var total_li: float = 0.0
var course_bearing: float = 0.0
var days_elapsed: int = 0
var pending_event: Dictionary = {}

# UI（2026-09-25 海图重制：全屏 MapView，夜潮面板压在图上；见 docs/海图重制设计_2026-09-25.md）
var status_label: RichTextLabel
var map: MapView
var map_container: SubViewportContainer
var compass: Control
var scale_bar: Control
var mode_button: Button
## 中间露出图的那段占位（顶匾之下、牌区之上）；取景只用这段，见 _push_view_inset
var _map_clear: Control
var _actions_wrap: Control
var _deck_hint: Label
var terrain_mode: bool = false
var heading_row: HBoxContainer
var log_label: RichTextLabel
var sail_button: Button
var redraw_button: Button
var back_button: Button
## 航法三策（云端 bed9）：默认针路，与改航法之前的日速、事件表一致。
var course_order: int = 0
var order_row: HBoxContainer
## 一旦发舶，回港按钮就关掉。事件浮层盖不住整屏，否则可以点回港躲开海盗。（云端 bed9）
var voyage_started: bool = false
var event_panel: PanelContainer
var event_title: Label
var event_text: RichTextLabel
var event_actions: VBoxContainer
var _strip_line: RichTextLabel
var _condition_layer: Control
var _latest_note := ""
## 逐日推进时船标在图上走的秒数；按住空格加速。serial 用来作废回港后仍在等的协程。
const DAY_SECONDS := 0.42
const DAY_SECONDS_FAST := 0.05
var _sail_serial: int = 0
## 二十四向（自正北顺时针，每向 15 度）：宋元罗盘的方位字，海图罗盘与「某针」文案用它
const COMPASS_24 := ["子", "癸", "丑", "艮", "寅", "甲", "卯", "乙", "辰", "巽", "巳", "丙", "午", "丁", "未", "坤", "申", "庚", "酉", "辛", "戌", "乾", "亥", "壬"]
const MAP_INK := Color(0.165, 0.141, 0.114)
const MAP_PAPER := Color(0.894, 0.827, 0.682)
const MAP_CINNABAR := Color(0.659, 0.196, 0.165)
const MAP_AZURITE := Color(0.208, 0.376, 0.498)


func _ready() -> void:
	UiTheme.apply(self)
	origin_port = GameState.last_port
	selected_port = ""
	course_order = Voyage.CourseOrder.RUMB
	_hand = HeadingDraft.deal(origin_port, GameState.draft_salt)
	_build_ui()
	_sync_order_buttons()
	# 连接放在 _build_ui 之后：_log 依赖其中创建的 log_label
	GameManager.monthly_notice.connect(_log)
	# 海图数据接入：岸线、绕岸折线、标注、已至港。船标先停在起点港。
	map.setup(GameManager.unlocked_ports(), GameManager.coastline_data, GameManager.sealanes_data, GameManager.chart_labels_data, GameState.visited_ports)
	map.show_ship_at_port(origin_port)
	_refresh_hand()
	_refresh_status()
	_log("自 %s 起锚。%s。" % [GameManager.get_port_name(origin_port), Calendar.get_monsoon_desc()])
	# 首帧取景要等视口有尺寸
	await get_tree().process_frame
	_frame_home(0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_T:
			_toggle_mode()
		KEY_F:
			_frame_home(0.8)
		KEY_H:
			_toggle_deck()


## 收起 / 展开底部的航法栏、航向牌与按钮，只看图（H）
var _deck_hidden: bool = false
func _toggle_deck() -> void:
	_deck_hidden = not _deck_hidden
	for c in [order_row, heading_row, _actions_wrap]:
		if c:
			c.visible = not _deck_hidden
	if _deck_hint:
		_deck_hint.visible = _deck_hidden


# ══════════════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════════════

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# ── 海图：SubViewport 里的 MapView 铺满全屏，摄像机只影响它；容器挂后期纸纹 ──
	map_container = SubViewportContainer.new()
	# 验收 code:CR-3：原为 FULL_RECT + stretch=true，子视口恒按逻辑 1280x720 渲染再被根视口放大，Retina / 全屏发糊。
	# 改为不拉伸，容器尺寸、缩放与子视口分辨率由 _fit_map_viewport 按物理像素设（默认锚点即左上）
	map_container.stretch = false
	var post := ShaderMaterial.new()
	post.shader = load("res://assets/map/ChartPost.gdshader")
	map_container.material = post
	add_child(map_container)
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map_container.add_child(vp)
	map = MapView.new()
	vp.add_child(map)
	map.port_clicked.connect(_on_map_port_clicked)
	# CR-3：逻辑尺寸变（resized）或窗口像素变而逻辑尺寸不变（canvas_items 下只有 size_changed）都重配子视口
	resized.connect(_fit_map_viewport)
	get_viewport().size_changed.connect(_fit_map_viewport)
	_fit_map_viewport()

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	mode_button = Button.new()
	mode_button.text = "舆图"
	mode_button.tooltip_text = "海图 / 舆图（地形）切换　T"
	mode_button.custom_minimum_size = Vector2(96, 40)
	# 验收 code:CR-5：HUD 按钮不拿焦点，航行中按空格加速不会误触（下同）
	mode_button.focus_mode = Control.FOCUS_NONE
	mode_button.pressed.connect(_toggle_mode)
	UiTheme.style_button(mode_button, false)
	strip_row.add_child(mode_button)
	var home_btn := Button.new()
	home_btn.text = "全图"
	home_btn.tooltip_text = "取景到已知海域　F"
	home_btn.custom_minimum_size = Vector2(96, 40)
	home_btn.focus_mode = Control.FOCUS_NONE  # CR-5
	home_btn.pressed.connect(func(): _frame_home(0.8))
	UiTheme.style_button(home_btn, false)
	strip_row.add_child(home_btn)
	var cond_btn := Button.new()
	cond_btn.text = "船况"
	cond_btn.custom_minimum_size = Vector2(120, 40)
	cond_btn.focus_mode = Control.FOCUS_NONE  # CR-5
	cond_btn.pressed.connect(_toggle_condition)
	UiTheme.style_button(cond_btn, false)
	strip_row.add_child(cond_btn)

	# 中间留给图：透明占位，鼠标穿到 MapView。罗盘与比例尺挂在占位的角上。
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_map_clear = center
	# 占位一变（首帧布局、H 收牌、拉窗口）就把露出的图带高度告诉图
	center.resized.connect(_push_view_inset)
	compass = Control.new()
	compass.custom_minimum_size = Vector2(150, 172)
	compass.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	compass.offset_left = -150 - 6
	compass.offset_right = -6
	compass.offset_top = 8
	compass.offset_bottom = 8 + 172
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	center.add_child(compass)
	# 题记框：仿《禹迹图》图首方框，竖写图名与「每方折地百里」
	var cartouche := Control.new()
	cartouche.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	cartouche.offset_left = 8
	cartouche.offset_right = 8 + 62
	cartouche.offset_top = 8
	cartouche.offset_bottom = 8 + 190
	cartouche.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cartouche.draw.connect(func(): _draw_cartouche(cartouche))
	# 验收 code:CR-8：缩放换方格时题记旁注跟着重写
	map.camera_changed.connect(cartouche.queue_redraw)
	center.add_child(cartouche)
	scale_bar = Control.new()
	scale_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	scale_bar.offset_left = 6
	scale_bar.offset_right = 6 + 240
	scale_bar.offset_top = -40
	scale_bar.offset_bottom = -4
	scale_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale_bar.draw.connect(_draw_scale)
	center.add_child(scale_bar)
	map.camera_changed.connect(scale_bar.queue_redraw)
	# 收牌后牌区不在了，图带右下角留一句怎么展开；平时藏着，不压图
	_deck_hint = Label.new()
	_deck_hint.text = "H 展开牌区"
	_deck_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_deck_hint.offset_left = -160
	_deck_hint.offset_right = -6
	_deck_hint.offset_top = -26
	_deck_hint.offset_bottom = -4
	_deck_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_deck_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_footnote(_deck_hint)
	_deck_hint.add_theme_color_override("font_color", Color(MAP_INK, 0.7))
	_deck_hint.visible = false
	center.add_child(_deck_hint)

	# 航法三策一栏（云端 bed9），放在航向牌上方
	order_row = _build_order_row()
	# 验收 interact:F4：横贯全宽的空白处不吃鼠标，牌区两侧露出的图也能拖、能滚轮缩放（按钮自己仍是 STOP，照样可点）
	order_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(order_row)

	heading_row = HBoxContainer.new()
	heading_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heading_row.add_theme_constant_override("separation", 12)
	# 验收 visual:V1：148 只是下限（没牌时也留这么高）；牌高随行数长时 HBox 按最高那张撑开，center 随之 resized → _push_view_inset
	heading_row.custom_minimum_size = Vector2(0, 148)
	# 验收 interact:F4：同上，牌与牌之间、两侧空白让给图；牌上的覆盖 Button 仍接点击
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heading_row)

	# 底行：按钮居中；操作提示两行小字靠右，不再浮在图上压港名（snowchan27-02 走查）
	_actions_wrap = Control.new()
	_actions_wrap.custom_minimum_size = Vector2(0, 48)
	_actions_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_actions_wrap)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	actions.set_anchors_preset(Control.PRESET_FULL_RECT)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions_wrap.add_child(actions)
	var speed_hint := Label.new()
	speed_hint.text = "拖拽平移　滚轮缩放　航行中按住空格加速\nT 舆图　F 全图　H 收牌"
	speed_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	speed_hint.offset_left = -300
	speed_hint.offset_right = 0
	speed_hint.offset_top = -24
	speed_hint.offset_bottom = 24
	speed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speed_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_footnote(speed_hint)
	_actions_wrap.add_child(speed_hint)

	sail_button = Button.new()
	sail_button.text = "就这一向"
	sail_button.custom_minimum_size = Vector2(220, 48)
	sail_button.add_theme_font_size_override("font_size", UiTheme.SIZE_CARD)
	sail_button.disabled = true
	sail_button.focus_mode = Control.FOCUS_NONE  # CR-5
	sail_button.pressed.connect(_on_sail_pressed)
	actions.add_child(sail_button)
	UiTheme.style_button(sail_button, true)

	redraw_button = Button.new()
	redraw_button.text = "候风再发"
	redraw_button.custom_minimum_size = Vector2(160, 42)
	redraw_button.focus_mode = Control.FOCUS_NONE  # CR-5
	redraw_button.pressed.connect(_on_redraw_hand)
	actions.add_child(redraw_button)
	UiTheme.style_button(redraw_button)

	back_button = Button.new()
	back_button.text = "回港"
	back_button.custom_minimum_size = Vector2(120, 42)
	back_button.focus_mode = Control.FOCUS_NONE  # CR-5
	back_button.pressed.connect(_on_back_to_port)
	actions.add_child(back_button)
	UiTheme.style_button(back_button)

	# ── 事件浮层 ──
	_build_event_panel()
	_mount_condition()


func _toggle_mode() -> void:
	terrain_mode = not terrain_mode
	map.set_mode(terrain_mode)
	mode_button.text = "海图" if terrain_mode else "舆图"


## 取景到全部已解锁港口
func _frame_home(dur: float) -> void:
	_push_view_inset()
	var ids := []
	for p in GameManager.unlocked_ports():
		ids.append(str(p.get("id", "")))
	map.frame_ports(ids, 0.16, dur, origin_port)


## 把顶匾与底部牌区盖住的屏幕高度告诉图：取景只用中间露出的图带，起讫港不再躲在航向牌底下
func _push_view_inset() -> void:
	if map == null or _map_clear == null or not _map_clear.is_inside_tree():
		return
	var top := _map_clear.global_position.y - global_position.y
	var bottom := size.y - (top + _map_clear.size.y)
	map.set_view_inset(top, bottom)


## 验收 code:CR-3：海图子视口按物理像素渲染。容器铺成物理像素大小再缩回 logical/phys，
## 贴图经根视口放大后正好 1:1；size_2d_override 让 MapView 的 get_viewport_rect、镜头、输入仍是逻辑坐标（取景 inset 数学不变）。
## 不能只关 stretch 不缩容器：stretch=false 时容器按子视口原尺寸画、最小尺寸也跟子视口，会画大一倍并自激放大（实测）。
func _fit_map_viewport() -> void:
	if map == null or map_container == null:
		return
	var logical := size
	if logical.x < 1.0 or logical.y < 1.0:
		return
	var vp := map.get_viewport() as SubViewport
	var phys := (logical * get_viewport().get_final_transform().get_scale()).round()
	if phys.x < 1.0 or phys.y < 1.0:  # 窗口最小化时缩放可能为 0
		return
	vp.size = Vector2i(phys)
	vp.size_2d_override = Vector2i(logical.round())
	vp.size_2d_override_stretch = true
	map_container.position = Vector2.ZERO
	map_container.size = phys
	map_container.scale = logical / phys


## 把当前选择同步到图上：风向、手牌、当前航段（顺风绿 / 逆风朱 / 换风金）
func _sync_map() -> void:
	if map == null:
		return
	map.set_wind(Calendar.get_wind_bearing())
	map.set_calendar(Calendar.month, Calendar.year)
	var offered: Array = [origin_port]
	for pid in _hand:
		offered.append(str(pid))
	map.set_offered(offered)
	if selected_port == "":
		map.clear_route()
	else:
		var plan := Voyage.plan(origin_port, selected_port, course_order)
		var wf := float(plan.get("wind_factor", 1.0))
		var col := MapView.COL_ROUTE_MIXED
		if not plan.get("wind_changes", false):
			col = MapView.COL_ROUTE_FAIR if wf >= 1.15 else (MapView.COL_ROUTE_FOUL if wf <= 0.75 else MapView.COL_ROUTE_MIXED)
		map.set_route(origin_port, selected_port, col, Voyage.is_known_route(origin_port, selected_port))
	if compass:
		compass.queue_redraw()


## 图上点港：与航向牌同一套规则——只有这一手风放出的向才能选
func _on_map_port_clicked(pid: String) -> void:
	if sailing or pid == "" or pid == origin_port:
		return
	if pid in _hand:
		_select_heading(pid)
	else:
		_log("今日风不放这一向。")


## 二十四向罗盘（宋元针盘）：内环四维（朱砂）、中环十二支（墨）、外环八干（淡墨），最外 48 刻度（每 7.5 度，缝针短刻）。
## 朱针指当前航向并写「某针」或「某某针」（缝针 = 两向之间），青箭示季风。中心一圈淡青取「指南浮针」之意。
func _draw_compass() -> void:
	var c := compass
	var font := UiTheme.font()
	var center := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5 - 3.0
	c.draw_circle(center, r + 2.0, Color(MAP_INK, 0.35))
	c.draw_circle(center, r, Color(MAP_PAPER, 0.93))
	c.draw_arc(center, r, 0, TAU, 96, Color(MAP_INK, 0.85), 1.6, true)
	c.draw_arc(center, r * 0.74, 0, TAU, 96, Color(MAP_INK, 0.35), 1.0, true)
	c.draw_arc(center, r * 0.55, 0, TAU, 96, Color(MAP_INK, 0.30), 1.0, true)
	# 浮针水面
	c.draw_circle(center, r * 0.36, Color(MAP_AZURITE, 0.16))
	c.draw_arc(center, r * 0.36, 0, TAU, 64, Color(MAP_AZURITE, 0.45), 1.0, true)
	# 48 刻度
	for i in range(48):
		var ang := deg_to_rad(i * 7.5) - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var single := i % 2 == 0
		var major := i % 12 == 0
		var len := 7.0 if major else (5.0 if single else 2.5)
		c.draw_line(center + dir * r, center + dir * (r - len), Color(MAP_INK, 0.85 if single else 0.45), 1.0, true)
	# 三环文字：干（外）、支（中）、维（内）
	for i in range(24):
		var ang := deg_to_rad(i * 15.0) - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var ch: String = str(COMPASS_24[i])
		var is_branch := i % 2 == 0          # 子丑寅卯…（偶数位）
		var is_corner := ch in ["乾", "坤", "艮", "巽"]
		var ring := 0.645 if is_branch else 0.85
		var col := MAP_INK if is_branch else Color(MAP_INK, 0.62)
		var fs := 11 if is_branch else 10
		if is_corner:
			ring = 0.46
			col = MAP_CINNABAR
			fs = 11
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := center + dir * (r * ring)
		c.draw_string(font, tp + Vector2(-w * 0.5, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var wb := Calendar.get_wind_bearing()
	if wb >= 0.0:
		var d := Vector2(sin(deg_to_rad(wb)), -cos(deg_to_rad(wb)))
		var a := center - d * r * 0.30
		var b := center + d * r * 0.30
		var perp := Vector2(-d.y, d.x)
		c.draw_line(a, b, Color(MAP_AZURITE, 0.8), 2.0, true)
		c.draw_line(b, b - d * 6.0 + perp * 3.5, Color(MAP_AZURITE, 0.8), 2.0, true)
		c.draw_line(b, b - d * 6.0 - perp * 3.5, Color(MAP_AZURITE, 0.8), 2.0, true)
	if selected_port != "":
		var bearing := course_bearing if sailing else Voyage.bearing(origin_port, selected_port)
		var d2 := Vector2(sin(deg_to_rad(bearing)), -cos(deg_to_rad(bearing)))
		var perp2 := Vector2(-d2.y, d2.x)
		var tip := center + d2 * r * 0.70
		var tail := center - d2 * r * 0.18
		c.draw_colored_polygon(PackedVector2Array([tip, center + perp2 * 3.0, tail, center - perp2 * 3.0]), MAP_CINNABAR)
		var needle := needle_name(bearing)
		var w2 := font.get_string_size(needle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		c.draw_string_outline(font, center + Vector2(-w2 * 0.5, r + 16), needle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(MAP_PAPER, 0.9))
		c.draw_string(font, center + Vector2(-w2 * 0.5, r + 16), needle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MAP_CINNABAR)
	c.draw_circle(center, 2.5, MAP_INK)


## 针位读法：正对一向为「X针」，落在两向之间为「XY针」（分辨率 7.5 度，《真腊风土记》「行丁未针」）
## 验收 history:F6：「单X针」是《顺风相送》等明代针路簿写法，宋末只写「X针」（如「乙针」），缝针仍「乙辰针」
static func needle_name(bearing: float) -> String:
	var k := int(round(fposmod(bearing, 360.0) / 7.5)) % 48
	if k % 2 == 0:
		return "%s针" % str(COMPASS_24[k / 2])
	var a := str(COMPASS_24[(k - 1) / 2])
	var b := str(COMPASS_24[((k + 1) / 2) % 24])
	return "%s%s针" % [a, b]


## 题记框：墨线双框，竖写「東南海道圖」，旁注「每方折地百里」（《禹迹图》图首方框之制）
func _draw_cartouche(c: Control) -> void:
	var font: Font = map.font if (map != null and map.font != null) else UiTheme.font()
	var rect := Rect2(Vector2(2, 2), c.size - Vector2(4, 4))
	c.draw_rect(rect, Color(MAP_PAPER, 0.92), true)
	c.draw_rect(rect, Color(MAP_INK, 0.85), false, 1.5)
	c.draw_rect(rect.grow(-4.0), Color(MAP_INK, 0.45), false, 1.0)
	var title := "東南海道圖"
	var y := 22.0
	var x_main := rect.position.x + 14.0
	for ch in title:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		c.draw_string(font, Vector2(x_main + 12.0 - w * 0.5, y + 12.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MAP_INK)
		y += 21.0
	var note := "每方折地百里"
	# 验收 code:CR-8：旁注跟计里画方的实际方格走（MapView.grid_step_li 返回 100 / 500 / 1000）；图还没有该方法时仍写百里
	if map != null and map.has_method("grid_step_li"):
		note = "每方折地%s" % str({500: "五百里", 1000: "千里"}.get(int(map.call("grid_step_li")), "百里"))
	var y2 := 26.0
	var x_note := rect.end.x - 18.0
	for ch in note:
		var w2 := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		c.draw_string(font, Vector2(x_note - w2 * 0.5, y2 + 6.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(MAP_INK, 0.7))
		y2 += 13.0


## 比例尺：按当前缩放画一段整数里程（百里 / 二百里 / 五百里 / 千里）
func _draw_scale() -> void:
	var c := scale_bar
	if map == null or map.camera == null or not map.proj.loaded:
		return
	var font := UiTheme.font()
	var li_per_px := map.proj.km_per_px_at(120.0, 25.0) / map.camera.zoom.x / Voyage.KM_PER_LI
	var step_li := 100.0
	for cand: float in [100.0, 200.0, 500.0, 1000.0, 2000.0]:
		if cand / li_per_px <= 190.0:
			step_li = cand
	var w := step_li / li_per_px
	var y := c.size.y - 8.0
	var x0 := 6.0
	c.draw_line(Vector2(x0, y), Vector2(x0 + w, y), MAP_INK, 1.6, true)
	c.draw_line(Vector2(x0, y - 5), Vector2(x0, y + 1), MAP_INK, 1.6, true)
	c.draw_line(Vector2(x0 + w, y - 5), Vector2(x0 + w, y + 1), MAP_INK, 1.6, true)
	c.draw_line(Vector2(x0 + w * 0.5, y - 3), Vector2(x0 + w * 0.5, y + 1), MAP_INK, 1.0, true)
	var names := {100.0: "一百里", 200.0: "二百里", 500.0: "五百里", 1000.0: "千里", 2000.0: "二千里"}
	var label: String = names.get(step_li, "%d 里" % int(step_li))
	c.draw_string_outline(font, Vector2(x0, y - 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, 3, Color(MAP_PAPER, 0.9))
	c.draw_string(font, Vector2(x0, y - 9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_FOOT, MAP_INK)


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
		# 验收 sail:SAIL-3：末日进度会冲过头，余程钳到 0，不显示负数
		note = "航行中　第 %d 日　已行 %d / 100　余程 %d 里" % [days_elapsed, pct, maxi(0, int(remaining_li))]
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	_strip_line.text = line1 + "\n[color=#%s]%s[/color]" % [dim, note]


func _panel_style() -> StyleBoxFlat:
	return UiTheme.panel()


func _set_margins(m: MarginContainer, v: int) -> void:
	m.add_theme_constant_override("margin_left", v)
	m.add_theme_constant_override("margin_right", v)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)


func _build_order_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var specs: Array = [
		[Voyage.CourseOrder.RUMB, "针路"],
		[Voyage.CourseOrder.OFFSHORE, "外洋"],
		[Voyage.CourseOrder.COAST, "傍岸"],
	]
	for spec in specs:
		var b := Button.new()
		b.toggle_mode = true
		b.text = str(spec[1])
		b.custom_minimum_size = Vector2(120, 36)
		b.focus_mode = Control.FOCUS_NONE  # 验收 code:CR-5：航法按钮不拿焦点
		b.tooltip_text = Voyage.order_blurb(int(spec[0]))
		b.pressed.connect(_on_order_pressed.bind(int(spec[0])))
		row.add_child(b)
		UiTheme.style_button(b)
	return row


func _on_order_pressed(order: int) -> void:
	if sailing:
		_sync_order_buttons()
		return
	course_order = order
	_sync_order_buttons()
	_refresh_hand()


func _sync_order_buttons() -> void:
	if order_row == null:
		return
	var orders: Array = [Voyage.CourseOrder.RUMB, Voyage.CourseOrder.OFFSHORE, Voyage.CourseOrder.COAST]
	var i := 0
	for c in order_row.get_children():
		if c is Button and i < orders.size():
			c.button_pressed = course_order == int(orders[i])
			c.disabled = sailing
			i += 1


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
		# 余程钳 0（验收 sail:SAIL-3）
		t += "[color=#%s]航行中　第 %d 日・%s[/color]\n已行　%d / 100\n余程　%d 里\n" % [
			UiTheme.hex(UiTheme.HONEY), days_elapsed, Voyage.order_name(course_order), int(pct * 100), maxi(0, int(remaining_li)),
		]
	# 在身委办（云端 bed9）
	var cst := GameState.contract_status()
	if not cst.is_empty():
		var left: int = int(cst.get("days_left", 0))
		var left_s := "今日截止" if left == 0 else ("%d 日后截止" % left if left > 0 else "已逾期")
		t += "[color=#%s][b]委办[/b][/color]\n%s ×%d 运往 %s　%s\n" % [
			gold,
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("remaining", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			left_s,
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
	t += _course_detail_text(gold)
	status_label.text = t
	_refresh_strip()
	# 日期推进会改季风，图上的风向流线与航段配色随之变
	_sync_map()


## 选定航向后的航段细节（云端 bed9 `_refresh_detail` 改写成船况面板的文字段）：
## 三策的静风 / 遇事 / 八成日数、保货成数、受潮成数、委办赶不赶得上、水粮够不够。
func _course_detail_text(gold: String) -> String:
	if selected_port == "" or sailing:
		return ""
	var plan := Voyage.plan(origin_port, selected_port, course_order)
	var plan_rumb := Voyage.plan(origin_port, selected_port, Voyage.CourseOrder.RUMB)
	var plan_off := Voyage.plan(origin_port, selected_port, Voyage.CourseOrder.OFFSHORE)
	var plan_coast := Voyage.plan(origin_port, selected_port, Voyage.CourseOrder.COAST)
	var t := "[color=#%s][b]航段　%s[/b][/color]\n" % [gold, GameManager.get_port_name(selected_port)]
	t += "%s　静风 %d 日　遇事约 %d 日　八成 %d 日　水粮足 %d 日\n" % [
		Voyage.order_name(course_order), int(plan["days"]), int(plan["expected_days"]), int(plan["safe_days"]), int(plan["supply_days"]),
	]
	t += "静风　针路 %d　外洋 %d　傍岸 %d 日\n" % [int(plan_rumb["days"]), int(plan_off["days"]), int(plan_coast["days"])]
	t += "遇事　针路 %d　外洋 %d　傍岸 %d 日\n" % [
		int(plan_rumb["expected_days"]), int(plan_off["expected_days"]), int(plan_coast["expected_days"]),
	]
	t += "八成　针路 %d　外洋 %d　傍岸 %d 日（十次约有八次不迟于这个数）\n" % [
		int(plan_rumb["safe_days"]), int(plan_off["safe_days"]), int(plan_coast["safe_days"]),
	]
	t += "保货　针路 %d　外洋 %d　傍岸 %d（十次里至少有这么多次，逃走没被抢走货）\n" % [
		int(plan_rumb["hold_tenths"]), int(plan_off["hold_tenths"]), int(plan_coast["hold_tenths"]),
	]
	t += _ink(UiTheme.TEXT_DIM, Voyage.order_blurb(course_order)) + "\n"
	if plan.get("departs_on_new_wind", false):
		t += _ink(UiTheme.TEXT_DIM, "明日才启航，日数不按今天的风。") + "\n"
	if plan.get("wind_changes", false):
		t += _ink(UiTheme.TEXT_DIM, "途中换风，静风和遇事都按逐日的风累加。") + "\n"

	var cst := GameState.contract_status()
	var damp := Voyage.dampest_aboard()
	if not cst.is_empty():
		var maybe_id := str(cst.get("good_id", ""))
		var maybe_qty := Fleet.cargo_qty(maybe_id)
		var maybe_rate := Voyage.good_perish_rate(maybe_id)
		if maybe_qty > 0 and maybe_rate > 0.0:
			damp = {"good_id": maybe_id, "qty": maybe_qty, "rate": maybe_rate}
	if not damp.is_empty():
		t += "受潮　%s　针路 %d　外洋 %d　傍岸 %d（按八成日数，十次里至少有这么多次一件没潮）\n" % [
			GameManager.get_good_name(str(damp["good_id"])),
			Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(float(damp["rate"]), int(damp["qty"]), int(plan_rumb["safe_days"]))),
			Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(float(damp["rate"]), int(damp["qty"]), int(plan_off["safe_days"]))),
			Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(float(damp["rate"]), int(damp["qty"]), int(plan_coast["safe_days"]))),
		]
	if not cst.is_empty() and str(cst.get("dest", "")) == selected_port:
		var left: int = int(cst.get("days_left", 0))
		var calm_days := int(plan["days"])
		var rough_days := int(plan["expected_days"])
		var safe_days := int(plan["safe_days"])
		if calm_days > left:
			t += _ink(UiTheme.CINNABAR, "委办只剩 %d 日，静风预计就要 %d 日，赶不上。" % [left, calm_days]) + "\n"
		elif rough_days > left:
			t += _ink(UiTheme.HONEY, "委办还剩 %d 日。静风 %d 日赶得上，遇事约 %d 日，可能误期。" % [left, calm_days, rough_days]) + "\n"
		elif safe_days > left:
			t += _ink(UiTheme.HONEY, "委办还剩 %d 日。遇事约 %d 日，八成要 %d 日，不算稳。" % [left, rough_days, safe_days]) + "\n"
		else:
			var hold_shown := int(plan.get("hold_tenths", 0))
			var spoil_shown := 10
			if not damp.is_empty() and str(damp.get("good_id", "")) == str(cst.get("good_id", "")):
				spoil_shown = Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(float(damp["rate"]), int(damp["qty"]), safe_days))
			if hold_shown < 8:
				t += _ink(UiTheme.HONEY, "委办还剩 %d 日。遇事约 %d 日，八成 %d 日。保货只有 %d，不到八成。" % [left, rough_days, safe_days, hold_shown]) + "\n"
			elif spoil_shown < 8:
				t += _ink(UiTheme.HONEY, "委办还剩 %d 日。遇事约 %d 日，八成 %d 日。受潮只有 %d，不到八成。" % [left, rough_days, safe_days, spoil_shown]) + "\n"
			else:
				t += _ink(UiTheme.MOSS, "委办还剩 %d 日。遇事约 %d 日，八成 %d 日。" % [left, rough_days, safe_days]) + "\n"
	if not cst.is_empty():
		var need := int(cst.get("remaining", 0))
		var have := Fleet.cargo_qty(str(cst.get("good_id", "")))
		if have < need:
			t += _ink(UiTheme.HONEY, "舱里的%s只有 %d，委办还要 %d。不够也能开船，到港交不齐。" % [
				GameManager.get_good_name(str(cst.get("good_id", ""))), have, need,
			]) + "\n"
	if not Voyage.is_known_route(origin_port, selected_port):
		t += _ink(UiTheme.HONEY, "此非熟路。针路与外洋都可能迷航，傍岸靠岸影，迷航少一些。") + "\n"
	var supply_have := int(plan["supply_days"])
	var supply_mean := int(plan["expected_days"])
	var supply_safe := int(plan["safe_days"])
	if supply_have < supply_safe:
		if supply_have < supply_mean:
			t += _ink(UiTheme.CINNABAR, "水粮只够 %d 日，遇事大约要 %d 日，半途必要死人。" % [supply_have, supply_mean]) + "\n"
		else:
			t += _ink(UiTheme.HONEY, "水粮够遇事约 %d 日，八成要 %d 日，可能中途断粮。" % [supply_mean, supply_safe]) + "\n"
	return t


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
	if status_label:
		_refresh_status()
	_sync_map()
	# 选了去处就把起点与去处一起框进镜头
	if selected_port != "" and map:
		map.frame_ports([origin_port, selected_port], 0.30, 0.7)


func _make_heading_card(pid: String) -> Control:
	var plan := Voyage.plan(origin_port, pid, course_order)
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

	var wind_mark := str(plan["wind_desc"])
	if plan.get("wind_changes", false):
		wind_mark += "·换风"
	var wind_lbl := _card_line("%s　约 %d 日" % [wind_mark, int(plan["days"])], UiTheme.TEXT)
	var hz := Crew.level_of("huozhang")
	if hz > 0:
		wind_lbl.text += "　火长　%s" % Crew.rank_word(hz)
	var dg := Crew.level_of("duogong")
	if dg > 0 and str(plan["wind_desc"]) in ["斜逆风", "顶头逆风"]:
		wind_lbl.text += "　舵工抢风"
	box.add_child(wind_lbl)
	box.add_child(_card_line("%d 里　%s" % [int(plan["distance"]), _bearing_phrase(float(plan["bearing"]))], UiTheme.TEXT_DIM))
	# 航法下的遇事日数与八成日数（云端 bed9）
	box.add_child(_card_line("%s　遇事约 %d 日　八成 %d 日" % [
		Voyage.order_name(course_order), int(plan.get("expected_days", plan["days"])), int(plan.get("safe_days", plan["days"])),
	], UiTheme.TEXT_DIM))
	if not Voyage.is_known_route(origin_port, pid):
		box.add_child(_card_line("生路", UiTheme.HONEY))
	if not bool(plan["supply_ok"]):
		box.add_child(_card_line("水粮不够", UiTheme.CINNABAR))
	# 验收 visual:V1 / interact:F7：牌高随行数长。「生路」+「水粮不够」同现时六行最小高 147，超出 148-24 的内高；
	# 普通 Control 不按子节点撑高，这里跟着 box 的最小高重算（字体进树后才有尺寸，故挂 minimum_size_changed），至少仍 148
	var fit_card := func() -> void:
		wrap.custom_minimum_size.y = maxf(148.0, box.get_combined_minimum_size().y + 24.0)
	box.minimum_size_changed.connect(fit_card)
	fit_card.call()

	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.disabled = sailing
	hit.focus_mode = Control.FOCUS_NONE  # 验收 code:CR-5：牌不拿焦点
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


## 八方加上度数。字跟最近的一方，数目仍是航向。
func _bearing_phrase(deg: float) -> String:
	var dirs := PackedStringArray(["北", "东北", "东", "东南", "南", "西南", "西", "西北"])
	var wrapped := posmod(int(round(deg)), 360)
	var idx := int(round(float(wrapped) / 45.0)) % 8
	return "%s　%d 度" % [dirs[idx], wrapped]


# ══════════════════════════════════════════════════════
#  海图绘制已移到 scripts/chart/MapView.gd（2026-09-25 海图重制）
# ══════════════════════════════════════════════════════

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
	_sync_order_buttons()
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
	# 发舶后锁回港与航法（云端 bed9）
	voyage_started = true
	if back_button:
		back_button.disabled = true
	_sync_order_buttons()

	sail_button.disabled = true
	_lock_hand()
	# 图：船标启程，镜头框住起讫两港
	_sync_map()
	if map:
		map.frame_ports([origin_port, selected_port], 0.30, 0.9)

	_log(_ink(UiTheme.GOLD, "启程往 %s，航程 %d 里。" % [GameManager.get_port_name(selected_port), int(total_li)]))
	_sail_next_day()


func _day_progress(event: Dictionary) -> float:
	var wf := Voyage.wind_factor(course_bearing)
	var progress := Fleet.fleet_speed() * wf * Voyage.order_speed_mult(course_order)
	var kind: int = int(event.get("kind", Voyage.EventKind.NONE))
	if kind == Voyage.EventKind.CALM:
		return 0.0
	if kind == Voyage.EventKind.CURRENT:
		return progress * 1.5
	if event.has("progress_mult"):
		return progress * float(event["progress_mult"])
	return progress


func _sail_next_day() -> void:
	if not sailing:
		return

	GameManager.advance_days(1)
	days_elapsed += 1

	# 风向按段变（云端 2d51）：当日罗经取折线上已行里程所在那一段
	course_bearing = Voyage.bearing_at(origin_port, selected_port, maxf(0.0, total_li - remaining_li))

	# 士气已经在本日结算里掉过。低于线就闹舱，不再另抽风涛或海盗。
	var event: Dictionary = Voyage.mutiny_event() if Fleet.mutiny_ready() else Voyage.roll_day_event(course_bearing, origin_port, selected_port, course_order)
	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	remaining_li -= _day_progress(event)
	_refresh_status()

	# 船标沿折线走完这一日（按住空格加速）。回港或换场景后协程作废。
	var serial := _sail_serial
	await _advance_ship_marker()
	if serial != _sail_serial or not sailing or not is_inside_tree():
		return

	# 补给见底的警告
	if Fleet.supply_days() <= 0 and Fleet.total_crew() > 0:
		_log(_ink(UiTheme.CINNABAR, "第 %d 日・水粮已尽，舱里开始有人病倒。" % days_elapsed))

	if kind != Voyage.EventKind.NONE:
		_log("第 %d 日・%s" % [days_elapsed, event.get("title", "")])
		if Fleet.total_durability() <= 0.0:
			_sink(str(event.get("text", "")))
			return
		_show_event(event)
		return

	if remaining_li <= 0.0:
		_arrive()
		return

	# 无事之日直接推进下一天
	_sail_next_day()


## 把船标推到当前已行里程处；返回后这一日的动画已走完
func _advance_ship_marker() -> void:
	if map == null:
		return
	var traveled := clampf(total_li - remaining_li, 0.0, total_li)
	var at: Dictionary = Voyage.point_along_track(origin_port, selected_port, traveled)
	var heading := Voyage.bearing_at(origin_port, selected_port, traveled)
	var dur := DAY_SECONDS_FAST if Input.is_key_pressed(KEY_SPACE) else DAY_SECONDS
	var frac := 0.0 if total_li <= 0.0 else traveled / total_li
	var tw := map.move_ship_lonlat(float(at["lon"]), float(at["lat"]), heading, frac, dur)
	if tw:
		await tw.finished


func _show_event(event: Dictionary) -> void:
	pending_event = event
	event_title.text = "第 %d 日・%s" % [days_elapsed, event.get("title", "事")]
	event_text.text = event.get("text", "")
	for c in event_actions.get_children():
		c.queue_free()

	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	if kind == Voyage.EventKind.MERCHANT:
		var offer := str(event.get("offer", "rumor"))
		if offer == "sell":
			_add_event_action("卖出 %s ×%d（%d 钱）" % [
				GameManager.get_good_name(str(event.get("good_id", ""))),
				int(event.get("qty", 0)), int(event.get("unit", 0)) * int(event.get("qty", 0)),
			], _on_sea_sell)
		elif offer == "buy":
			_add_event_action("买下 %s ×%d（%d 钱）" % [
				GameManager.get_good_name(str(event.get("good_id", ""))),
				int(event.get("qty", 0)), int(event.get("unit", 0)) * int(event.get("qty", 0)),
			], _on_sea_buy)
		if str(event.get("rumor_port", "")) != "":
			_add_event_action("记下这条行情", _on_note_rumor)
		_add_event_action("继续航行", _on_event_continue)
	elif kind == Voyage.EventKind.PIRATE:
		_add_event_action("迎战", _on_fight_pirates)
		_add_event_action("扬帆逃走", _on_flee_pirates)
		_add_event_action("献上买路财", _on_pay_pirates)
	elif kind == Voyage.EventKind.DISCOVERY:
		_add_event_action("绕去细看　费一日", _on_investigate_discovery)
		_add_event_action("不理会　继续航行", _on_event_continue)
	elif kind == Voyage.EventKind.MUTINY:
		_add_event_action("散钱 %d" % Fleet.mutiny_bribe_cost(), _on_mutiny_bribe)
		_add_event_action("放走 %d 人" % Fleet.mutiny_dismiss_count(), _on_mutiny_dismiss)
		_add_event_action("压住", _on_mutiny_suppress)
	# 战时遭遇三类：处理函数一直在，云端合并时这里的路由丢了，2026-09-25 海图重制顺手接回
	elif kind == Voyage.EventKind.REQUISITION:
		if Fleet.ships.size() > 1:
			_add_event_action("交出一条船（名声 +）", _on_requisition_surrender)
		_add_event_action("塞钱免征", _on_requisition_bribe)
		_add_event_action("趁夜溜走", _on_requisition_flee)
	elif kind == Voyage.EventKind.YUAN_PATROL:
		_add_event_action("落帆受检", _on_patrol_submit)
		_add_event_action("迎战", _on_fight_patrol)
		_add_event_action("扬帆逃走", _on_flee_pirates)
	elif kind == Voyage.EventKind.REFUGEE:
		_add_event_action("载人同行（水粮 −2 成）", _on_refugee_take)
		_add_event_action("分些水粮，不载人", _on_refugee_share)
		_add_event_action("不停船", _on_refugee_pass)
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


func _on_mutiny_bribe() -> void:
	_finish_mutiny(Fleet.resolve_mutiny("bribe"))


func _on_mutiny_dismiss() -> void:
	_finish_mutiny(Fleet.resolve_mutiny("dismiss"))


func _on_mutiny_suppress() -> void:
	_finish_mutiny(Fleet.resolve_mutiny("suppress"))


func _finish_mutiny(result: Dictionary) -> void:
	var outcome := str(result.get("outcome", ""))
	var line := ""
	match outcome:
		"bribe":
			line = "[color=yellow]你把 %d 钱散到各舱。桨收回去了，人还在。[/color]" % int(result.get("paid", 0))
		"bribe_fail":
			line = "[color=red]钱匣是空的。有人自己下了舢板，走了 %d 人。[/color]" % int(result.get("crew_lost", 0))
		"dismiss":
			line = "[color=yellow]你点了 %d 个人下舢板。剩下的人重新升帆。[/color]" % int(result.get("crew_lost", 0))
		"suppress_ok":
			line = "[color=yellow]你站在桅下把话说明白。人散开了，眼神还硬。[/color]"
		"suppress_fail":
			line = "[color=red]压不住。走了 %d 人。[/color]" % int(result.get("crew_lost", 0))
		_:
			line = "舱里安静下来。"
	var cargo: Dictionary = result.get("cargo_lost", {})
	if not cargo.is_empty():
		var parts := []
		for gid in cargo.keys():
			parts.append("%s %d" % [GameManager.get_good_name(str(gid)), int(cargo[gid])])
		line += "抬走了" + "、".join(parts) + "。"
	line += "士气 %d。" % int(result.get("morale", Fleet.morale))
	_log(line)
	_refresh_status()
	_on_event_continue()


func _note_rumor_from_event(event: Dictionary) -> void:
	var pid := str(event.get("rumor_port", ""))
	var gid := str(event.get("rumor_good", ""))
	if pid == "" or gid == "":
		return
	GameState.note_rumor(pid, gid, float(event.get("rumor_rate", 1.0)))
	_log("记下行情：%s 的 %s。" % [GameManager.get_port_name(pid), GameManager.get_good_name(gid)])


func _on_note_rumor() -> void:
	event_panel.visible = false
	_note_rumor_from_event(pending_event)
	_on_event_continue()


func _on_sea_sell() -> void:
	event_panel.visible = false
	var ev := pending_event
	var gid := str(ev.get("good_id", ""))
	var qty := mini(int(ev.get("qty", 0)), Fleet.cargo_qty(gid))
	var unit := int(ev.get("unit", 0))
	if qty <= 0 or unit <= 0:
		_log("这批货已经不在舱里了。")
	else:
		Fleet.remove_cargo(gid, qty)
		GameState.add_money(unit * qty)
		_log("海上卖掉 %s ×%d，得 %d 钱。" % [GameManager.get_good_name(gid), qty, unit * qty])
		_note_rumor_from_event(ev)
	_on_event_continue()


func _on_sea_buy() -> void:
	event_panel.visible = false
	var ev := pending_event
	var gid := str(ev.get("good_id", ""))
	var unit := int(ev.get("unit", 0))
	var want := int(ev.get("qty", 0))
	var loaded := 0
	var spent := 0
	while loaded < want and unit > 0:
		if Fleet.max_loadable(gid) <= 0 or GameState.money < unit:
			break
		if not GameState.spend_money(unit):
			break
		if not Fleet.add_cargo(gid, 1, float(unit)):
			GameState.add_money(unit)
			break
		loaded += 1
		spent += unit
	if loaded <= 0:
		_log("没有买成。要么钱不够，要么舱位不够。")
	else:
		_log("海上买下 %s ×%d，付 %d 钱。" % [GameManager.get_good_name(gid), loaded, spent])
		_note_rumor_from_event(ev)
	_on_event_continue()


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
	back_button.disabled = true
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
		# WorldMap 只在旗舰沉没时发 lose。先按该船货舱全损记账，
		# 不要写成「部分」——护航船还在则只清旗舰，全队耐久归零再由沉没结算收尾。（云端 c148；00b4 同向但只判全队）
		if bool(data.get("sunk", false)) or Fleet.total_durability() <= 0.0:
			var lost := Fleet.clear_ship_cargo(0)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			if Fleet.total_durability() <= 0.0:
				_log(_ink(UiTheme.CINNABAR, "旗舰沉没，货舱随船没了。%s船体受损 %d。" % [lost_str, int(dmg)]))
			else:
				_log(_ink(UiTheme.CINNABAR, "旗舰沉没，该船货物随船没了。%s其余船只还在。船体受损 %d。" % [lost_str, int(dmg)]))
		else:
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
	back_button.disabled = voyage_started
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
	var chance := Voyage.flee_success_chance()
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


# ── 战时遭遇 ──────────────────────────────────────────

## 征船：交出最小的一条船（连船上的货）。朝廷记你的名。
func _on_requisition_surrender() -> void:
	event_panel.visible = false
	if Fleet.ships.size() <= 1:
		_on_event_continue()
		return
	var idx := 0
	for i in range(Fleet.ships.size()):
		if Fleet.ship_capacity(i) < Fleet.ship_capacity(idx):
			idx = i
	var s: Dictionary = Fleet.ships[idx]
	Fleet.ships.remove_at(idx)
	GameState.fame += 6
	Fleet.morale = maxi(0, Fleet.morale - 4)
	_log("[color=yellow]「%s」连船带货编入官军。小官在册子上记了你的名字，写得很工整。名声 +6。[/color]" % s.get("name", "一船"))
	_refresh_status()
	_on_event_continue()


func _on_requisition_bribe() -> void:
	event_panel.visible = false
	var cost: int = maxi(100, int(GameState.money * 0.15))
	if GameState.spend_money(cost):
		_log("[color=yellow]%d 钱换了册子上「已征」两个字。船一条没少。[/color]" % cost)
	else:
		# 拿不出钱，按逃走处理
		_on_requisition_flee()
		return
	_refresh_status()
	_on_event_continue()


func _on_requisition_flee() -> void:
	event_panel.visible = false
	var chance := clampf(Fleet.fleet_speed() / 240.0, 0.2, 0.85)
	if randf() < chance:
		remaining_li += Fleet.fleet_speed() * 0.5
		_log(_ink(UiTheme.MOSS, "熄灯落帆，借夜潮漂出哨船视线，多走了一程。"))
	else:
		var fine: int = maxi(80, int(GameState.money * 0.25))
		GameState.add_money(-fine)
		GameState.fame -= 4
		Fleet.morale = maxi(0, Fleet.morale - 5)
		_log("[color=red]被哨船追上。「抗征」二字记入册子，罚钱 %d，名声 −4。[/color]" % fine)
	_refresh_status()
	_on_event_continue()


## 元军哨船受检：有违禁货则没收加罚；无则放行
func _on_patrol_submit() -> void:
	event_panel.visible = false
	var contraband := GameState.contraband_units()
	if contraband > 0:
		var fine: int = mini(400, maxi(60, int(GameState.money * 0.2)))
		GameState.confiscate_contraband()
		GameState.add_money(-fine)
		Fleet.morale = maxi(0, Fleet.morale - 6)
		_log("[color=red]舱底被翻了个底朝天。%d 件违禁之物起获，罚钱 %d。那个泉州口音的人说：「往后规矩变了。」[/color]" % [contraband, fine])
	else:
		Fleet.morale = maxi(0, Fleet.morale - 2)
		_log("[color=yellow]查了半日，没查出什么。对方在你的引目上盖了一个你不认得的印，放行。[/color]")
	_refresh_status()
	_on_event_continue()


func _on_fight_patrol() -> void:
	event_panel.visible = false
	var power := _fleet_power()
	var enemy := randf_range(320.0, 760.0)
	GameManager.pending_battle = {
		"battle": true,
		"power": enemy,
		"player_power": power,
		"enemy": [{"type": "sea_falcon", "count": 3, "hull_hp": 120.0}],
		"source": {"scene": "SeaChart", "event": "yuan_patrol"},
	}
	_enter_battle()


## 难民：载人费水粮、长名声；不停船伤士气
func _on_refugee_take() -> void:
	event_panel.visible = false
	Fleet.water = maxi(0, Fleet.water - int(ceil(Fleet.water * 0.2)))
	Fleet.food = maxi(0, Fleet.food - int(ceil(Fleet.food * 0.2)))
	GameState.fame += 4
	Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 3)
	_log("[color=lime]把人接上船。甲板挤了，水粮吃得快了。有个老人一直握着你的手不放。名声 +4。[/color]")
	_refresh_status()
	_on_event_continue()


func _on_refugee_share() -> void:
	event_panel.visible = false
	Fleet.water = maxi(0, Fleet.water - int(ceil(Fleet.water * 0.1)))
	Fleet.food = maxi(0, Fleet.food - int(ceil(Fleet.food * 0.1)))
	GameState.fame += 1
	_log("[color=yellow]递过去几桶水和一袋米。他们没有道谢的力气，船慢慢漂远了。[/color]")
	_refresh_status()
	_on_event_continue()


func _on_refugee_pass() -> void:
	event_panel.visible = false
	Fleet.morale = maxi(0, Fleet.morale - 3)
	_log("[color=red]没有停。水手们都没说话，只有舵工朝海里啐了一口。士气 −3。[/color]")
	_refresh_status()
	_on_event_continue()


# ── 发现物 ──────────────────────────────────────────

func _on_investigate_discovery() -> void:
	# 按钮写「费 1 日」。这一日只扣水粮和历法，船不往前。
	# 续航交给下一次点击，避免同一次点击里再进 _sail_next_day 叠成两日。（云端 be04/c148 两版同此；00b4 改为不计日直接续航，未取）
	GameManager.advance_days(1)
	days_elapsed += 1
	var did: String = pending_event.get("discovery_id", "")
	var d := GameManager.get_discovery_by_id(did)
	var note := ""
	if GameState.record_discovery(did):
		note = "近岸细看，果然是%s。记入册子——回港上报市舶司，当有赏格。" % d.get("name", "旧泊地")
		_log(_ink(UiTheme.MOSS, note))
	else:
		note = "绕过去看了一圈，与册上所记并无出入。"
		_log(note)
	_refresh_status()
	pending_event = {}
	event_title.text = "第 %d 日・近岸" % days_elapsed
	event_text.text = note + "\n\n这一日水粮照耗，船没有往前挪。"
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("继续航行", _on_event_continue)
	event_panel.visible = true


# ── 结束 ────────────────────────────────────────────

func _arrive() -> void:
	sailing = false
	Fleet.at_sea = false
	GameState.record_trip(origin_port, selected_port)
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


func _sink(preface: String = "") -> void:
	sailing = false
	Fleet.at_sea = false
	Fleet.clear_cargo()
	if map:
		map.hide_ship()
	event_title.text = "沉　没"
	var lead := ""
	if preface != "":
		lead = preface + "\n\n"
	event_text.text = lead + "船身裂开，海水灌进货舱。等你再睁眼时，已被人捞上一条渔船，货与船都没了。"
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


func _on_back_to_port() -> void:
	if voyage_started:
		return
	_return_to_port()


func _return_to_port() -> void:
	# 海战进行中回港会丢掉 battle_finished，战中已扣的耐久和舱货留在舰队上，赏罚不结算。（云端 be04）
	if GameManager.pending_battle.get("battle", false):
		return
	_sail_serial += 1
	Fleet.at_sea = false
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══


