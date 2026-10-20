extends Control
## 海图。风每一手发至多三向，选定后按日推进，逐日抽事件，到港。
## 实时操船（WorldMap.tscn）降级为海战/风涛时切入的战术场景。

## 内部：船标一日走完 / 作废的唤醒（lane gd17），只由 _wake_marker 与 _cancel_marker 发
signal _marker_woken

const _CombatFx := preload("res://scripts/combat/CombatFx.gd")
const _Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const _AfterAction := preload("res://scripts/combat/AfterAction.gd")
const _Landing := preload("res://scripts/combat/LandingRaid.gd")
## lane w54-polish：一到六期新概念的旁注小笺（第一次露面出一张，看过记旗标不再出；开关 combat_notes）
const _Notes := preload("res://scripts/ui/CombatNotes.gd")
## lane w54-audio：音效挂点表（启程 / 风涛 / 浅滩 / 靠港钟 / 海上沉没各一行挂点；开关 sfx_cues）
const _SFX := preload("res://scripts/audio/SfxCues.gd")

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
var _cartouche: Control
var _actions_wrap: Control
var _deck_hint: Label
var terrain_mode: bool = false
var heading_row: HBoxContainer
var log_label: RichTextLabel
## 船况札记：新的在前（会话内，不入存档）。原先整串往 log_label 前头拼；lane w19-g9 起按条存，月初通告与港页记事栏
## 同一套折叠（scripts/core/LogFold.gd：一连 LogFold.FOLD_AT 则收成一行、跨月按月分组、点开就地看），下面五个字段口径见那边头注
var _log_lines: PackedStringArray = PackedStringArray()
var _log_folds: Dictionary = {}
var _log_fold_open := ""
var _notice_run := 0
var _notice_when: Array = []
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
var _event_tween: Tween
var _condition_tween: Tween
var _latest_note := ""
## 逐日推进时船标在图上走的秒数；按住空格加速。serial 用来作废回港后仍在等的协程。
const DAY_SECONDS := 0.42
const DAY_SECONDS_FAST := 0.05
var _sail_serial: int = 0
## 船标挂起点序号：作废（下一段顶掉 / 离树）后 +1，醒来对不上就是被作废
var _marker_seq: int = 0
## 二十四向（自正北顺时针，每向 15 度）：宋元罗盘的方位字，海图罗盘与「某针」文案用它
const COMPASS_24 := ["子", "癸", "丑", "艮", "寅", "甲", "卯", "乙", "辰", "巽", "巳", "丙", "午", "丁", "未", "坤", "申", "庚", "酉", "辛", "戌", "乾", "亥", "壬"]
const MAP_INK := Color(0.165, 0.141, 0.114)
const MAP_PAPER := Color(0.894, 0.827, 0.682)
const MAP_CINNABAR := Color(0.659, 0.196, 0.165)
const MAP_AZURITE := Color(0.208, 0.376, 0.498)
## 海战敌船条目（pending_battle.enemy 的一格）。type 决定船名、水手区间、夺船后按什么船型入列；
## sprite 只管海战精灵 assets/ship_<sprite>.png，缺省用 type，缺图回落 ship_falcon.png（船图契约，见 CombatFx.ship_sprite_path）。
## 海寇一律 pirate_boat「快船」（备忘 #7：海鹘只指船屋卖的宋水军战船）。
const PIRATE_ENEMY := {"type": "pirate_boat", "count": 2, "hull_hp": 100.0}
## 元军哨船：type 不动（ships.json 没有 yuan_patrol 这一型，改 type 夺船会悄悄失败），另挂 sprite。
const PATROL_ENEMY := {"type": "sea_falcon", "sprite": "yuan_patrol", "count": 3, "hull_hp": 120.0}
## 闯封锁（战斗系统方案 §七，开关 blockade_run）：图上点了被围的港、舱里带着米粮、选了「闯封锁」——这一程的去处。
## 只活在这一程里，不进存档（海图上不能存档）。到了港外掷一次（_run_gate）：撞上哨船挂「哨船拦港」一面
var _run_port := ""
## 闯进了港，每运进这许多件米粮记名声一点（至多 RUN_FAME_MAX 点）：给围城送粮是义举，一两件粮蹭不到名声
const RUN_FAME_PER := 100
const RUN_FAME_MAX := 5


func _ready() -> void:
	UiTheme.apply(self)
	origin_port = GameState.last_port
	selected_port = ""
	course_order = Voyage.CourseOrder.RUMB
	_hand = HeadingDraft.deal(origin_port, GameState.draft_salt)
	_build_ui()
	_sync_order_buttons(); _a11y_mount()  # lane w54-a11y：发舶前几颗钮收键盘焦点（函数在文件尾）
	# 连接放在 _build_ui 之后：_log / _on_monthly_notice 依赖其中创建的 log_label
	GameManager.monthly_notice.connect(_on_monthly_notice)
	log_label.meta_clicked.connect(_on_log_meta)
	# 海图数据接入：岸线、绕岸折线、标注、已至港。船标先停在起点港。
	map.setup(GameManager.unlocked_ports(), GameManager.coastline_data, GameManager.sealanes_data, GameManager.chart_labels_data, GameState.visited_ports)
	map.show_ship_at_port(origin_port)
	_refresh_hand()
	_refresh_status()
	_log_departure()
	# 首帧取景要等视口有尺寸
	await get_tree().process_frame
	_frame_home(0.0)
	# 进海图首帧淡入（美术线评审 M5 ③）：一层绢色盖住整屏，半秒褪去，不挡鼠标
	var veil := ColorRect.new()
	veil.color = MAP_PAPER
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.z_index = 100
	add_child(veil)
	var vt := create_tween()
	vt.tween_property(veil, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	vt.tween_callback(veil.queue_free)


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
	# Visibility changes resize the exposed map band on the next layout pass.
	# Re-push after that pass so the camera never leaves the ship under the deck.
	call_deferred("_push_view_inset")


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
	_strip_line.resized.connect(_refresh_strip)  # 匾宽定了（首帧排版、超宽屏、拉窗口）按新宽重收第二行
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
	_cartouche = cartouche
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
	speed_hint.text = "拖拽平移　滚轮缩放　航行中按住空格加速\nT 舆图　F 全图　H 收牌　C 船况"
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
	# 航行中点全图：看全图，镜头不再跟船（全图里有船标的话下一日接着跟，见 MapView.set_follow）
	map.set_follow(false)


## 把顶匾与底部牌区盖住的屏幕高度告诉图：取景只用中间露出的图带，起讫港不再躲在航向牌底下
func _push_view_inset() -> void:
	if map == null or _map_clear == null or not _map_clear.is_inside_tree():
		return
	var top := _map_clear.global_position.y - global_position.y
	var bottom := size.y - (top + _map_clear.size.y)
	map.set_view_inset(top, bottom)
	map.set_hud_rects(_hud_rects())


## 盖在图带上的几块 HUD（罗盘连盘下针名、题记框、比例尺），海图页坐标（= 海图屏幕坐标）。图上摆港名、地名、出带箭头时让开，
## 港位本身落在里头的不写港名（MapView.set_hud_rects）：原先不让，南岛海道北口的港名常落在罗盘盘面底下，盘下针名「丑针」
## 压进「南島海道北口」里；广州、漳州的港名压在比例尺「一百里」上（lane w53-1）
func _hud_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c: Control in [compass, _cartouche, scale_bar]:
		if c == null or not c.is_visible_in_tree():
			continue
		var r := Rect2(c.global_position - global_position, c.size)
		if c == compass:
			# 盘下针名写在罗盘框下沿外几 px（_draw_compass：盘心下 r + 16 处基线、12 px 字）
			r = r.grow_individual(0.0, 0.0, 0.0, 8.0)
		elif c == scale_bar:
			# 比例尺只有一道墨线连上方的里数（_draw_scale：线长至多 190 px），框里其余是透明的
			r = Rect2(r.position + Vector2(4.0, 3.0), Vector2(196.0, 28.0))
		out.append(r)
	return out


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
	map.set_sealed(HeadingDraft.sealed_ids())
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


## 图上点港：与航向牌同一套规则——只有这一手风放出的向才能选；港已封的只给「港已封」（待拍板 20b）
func _on_map_port_clicked(pid: String) -> void:
	if sailing or pid == "" or pid == origin_port:
		return
	if pid in _hand:
		_select_heading(pid)
		return
	var why := HeadingDraft.seal_of(pid)
	if why != "":
		_Notes.offer(self, "blockade")  # lane w54-polish：头一回点到封着的港，出一张「封港」旁注（排在闯封锁那张之前）
	if why == "":
		_log("今日风不放这一向。")
	elif _run_offerable(pid):
		_offer_run(pid)
	else:
		_log(_seal_note(pid, why))


## 点了封着的港那一句：「港已封」打头，后面写封因（HeadingDraft.seal_of 的 closed / banned / besieged）
func _seal_note(pid: String, why: String) -> String:
	var pname := str(GameManager.get_port_name(pid))
	match why:
		"closed":
			return "港已封。%s封港，海路不通。" % pname
		"banned":
			return "港已封。%s对你封港，船进不去。" % pname
		"besieged":
			var t := "港已封。%s被围，港外都是元军的哨船。" % pname
			if _Switches.on("blockade_run"):
				t += "舱里带上米粮，可以闯封锁。"
			return t
	return "港已封。"


# ── 闯封锁 ──────────────────────────────────────────

## 能不能闯：港是围城封着的（20b 的 besieged，剧情放行的港照常走、不算闯）、开关 blockade_run 开着、舱里有可卖的米粮
func _run_offerable(pid: String) -> bool:
	return _Switches.on("blockade_run") and HeadingDraft.seal_of(pid) == "besieged" and _run_grain_sellable() > 0


## 这一舱米粮闯进去卖得几何：[城里收的件数, 得钱, 名声]。城里一趟只收得下 Economy.blockade_grain_cap 件，多的留在舱里；
## 委办要留的米也不上秤（_run_grain_sellable）
func _run_take(pid: String) -> Array:
	var qty := mini(_run_grain_sellable(), Economy.blockade_grain_cap(pid))
	var gold := int(round(Economy.blockade_grain_unit(pid) * float(qty)))
	return [qty, gold, mini(RUN_FAME_MAX, int(qty / RUN_FAME_PER))]


## 闯封锁那一面：写清城里收粮价、这一舱约得多少、四成撞上哨船与输了的下场；钮「闯封锁」/「不去了」
func _offer_run(pid: String) -> void:
	var pname := str(GameManager.get_port_name(pid))
	var take := _run_take(pid)
	var aboard := Fleet.cargo_qty("grain")
	var cap_s := "，这一趟城里只收得下 %d 件" % int(take[0]) if aboard > int(take[0]) else ""
	var fame_s := "，名声加 %d" % int(take[2]) if int(take[2]) > 0 else ""
	event_title.text = "闯封锁・%s" % pname
	event_text.text = "%s被围，牙行闭门，城里缺粮。舱里有米粮 %d 件，城里按围城米价收，每件约 %d 钱（平年约 %d 钱）%s：约得 %d 钱%s。\n到了港外，四成会撞上元军哨船（海鹘一艘、快船两艘），要打一仗。打赢了或没撞上，照这个价卖粮；打输了、逃了或掉头，舱里的米粮就没了，船折回%s。" % [
		pname, aboard, int(round(Economy.blockade_grain_unit(pid))), int(round(Economy.blockade_grain_base(pid))),
		cap_s, int(take[1]), fame_s, GameManager.get_port_name(origin_port),
	]
	for c in event_actions.get_children():
		c.queue_free()
	_add_event_action("闯封锁", _choose_run.bind(pid))
	_add_event_action("不去了", func(): event_panel.visible = false)
	_open_event_panel()
	_Notes.offer(self, "blockade_run")  # lane w54-polish：闯封锁那一面头一回挂出，出一张旁注


func _choose_run(pid: String) -> void:
	event_panel.visible = false
	if sailing or not _run_offerable(pid):
		return
	_run_port = pid
	selected_port = pid
	_refresh_hand()


## 航段细节里那一行（发舶前）
func _run_brief() -> String:
	var take := _run_take(_run_port)
	return "闯封锁　四成撞上哨船　米粮 %d 件约得 %d 钱" % [int(take[0]), int(take[1])]


## 闯封锁到了港外（_arrive 先问它）：围解了照常进港、米粮留在舱里；还围着就掷一次（Voyage.blockade_patrol_met）——
## 撞上哨船挂「哨船拦港」一面（迎战 / 掉头回航），接手返回 true；没撞上按围城米价卖粮，返回 false 照常进港
func _run_gate() -> bool:
	var pid := _run_port
	if Economy.war_status(pid) != "besieged":
		_run_port = ""
		_log("到了港外，%s已经不在围中，哨船都撤了。米粮留在舱里。" % GameManager.get_port_name(pid))
		return false
	if Voyage.blockade_patrol_met():
		var ev := Voyage.blockade_event(pid)
		_log("第 %d 日・%s" % [days_elapsed, ev.get("title", "")])
		_show_event(ev)
		return true
	_log(_ink(UiTheme.MOSS, "港外的哨船正巧换班，趁潮进了港。"))
	_run_sell()
	return false


func _on_fight_blockade() -> void:
	event_panel.visible = false
	GameManager.pending_battle = {
		"battle": true,
		"power": randf_range(Voyage.BLOCKADE_POWER_MIN, Voyage.BLOCKADE_POWER_MAX),
		"player_power": _fleet_power(),
		"enemy": Voyage.BLOCKADE_PATROL.duplicate(true),
		"sea_name": _battle_sea_name(),
		"source": {"scene": "SeaChart", "event": "blockade", "port": _run_port},
	}
	_enter_battle()


## 拦港一面「掉头回航」：不打，落帆让哨船上来扣下米粮，放船折回起锚港
func _on_run_yield() -> void:
	event_panel.visible = false
	_run_seize("yield")
	_after_combat()


## 拦港那一仗打完（_on_battle_result 收尾前）：赢了，或大风 / 天黑两散（哨船收帆回泊，趁乱进港）照围城米价卖粮；
## 甩脱了（弃战逃成、甩开追船）米粮抛海轻船；输了、没逃成（被追上跳帮）米粮扣下——船还浮着就折回起锚港
func _run_settle(outcome: String, data: Dictionary) -> void:
	if outcome == "win" or outcome == "disengaged" or bool(data.get("parted", false)):
		_run_sell()
	elif outcome == "flee" and bool(data.get("flee_ok", false)):
		_run_seize("flee")
	else:
		_run_seize("lose")


## 闯进了港：舱里的米粮全按围城米价卖给城里（Economy.blockade_grain_unit），名声按件数记（_run_take）
func _run_sell() -> void:
	var pid := _run_port
	if pid == "":
		return
	_run_port = ""
	var take := _run_take(pid)
	var qty := int(take[0])
	if qty <= 0:
		_log("舱里的米粮一路上已经没了（或全是在身委办要留的），空手进的港。")
		return
	Fleet.remove_cargo("grain", qty)
	GameState.add_money(int(take[1]))
	var t := "城里按围城米价收粮：米粮 %d 件，得 %d 钱。" % [qty, int(take[1])]
	var left := Fleet.cargo_qty("grain")
	if left > 0:
		var kept := GameState.contract_kept("grain")
		if kept >= left:
			t += "余下 %d 件在身委办要留，没卖。" % left
		else:
			t += "余下 %d 件城里收不下，留在舱里。" % left
	if int(take[2]) > 0:
		var fame_res: Dictionary = GameState.add_fame(int(take[2]))
		t += "名声加 %d。" % int(fame_res.get("gained", 0))
		if fame_res.get("promoted", false):
			t += "案册改题「%s」。" % str(fame_res.get("title", {}).get("name", ""))
	_log(_ink(UiTheme.MOSS, t))
	_refresh_status()


## 没闯过去：舱里要卖的那批米一件不剩（输了被扣、逃了抛海、掉头交出），船还浮着就折回起锚港——
## 起讫对调，从港外照常一日日走回去（遇事照抽）；全队沉了不对调，由沉船那条路送回起锚港。
## 在身委办要留的米不上船去闯、也就不跟着赔进去（与 _run_take 同一个口径，lane w54-hunt）
func _run_seize(how: String) -> void:
	var pid := _run_port
	if pid == "":
		return
	_run_port = ""
	var qty := mini(Fleet.cargo_qty("grain"), _run_grain_sellable())
	if qty > 0:
		Fleet.remove_cargo("grain", qty)
	var t := ""
	match how:
		"lose":
			t = "米粮 %d 件被哨船扣下。" % qty
		"flee":
			t = "为了轻船甩开哨船，米粮 %d 件都抛下了海。" % qty
		_:
			t = "落帆让哨船上来，米粮 %d 件都扣下了。" % qty
	if Fleet.total_durability() > 0.0:
		var back := origin_port
		origin_port = pid
		selected_port = back
		total_li = Voyage.distance_li(origin_port, selected_port)
		remaining_li = total_li
		t += "船进不了%s，只得折回%s。" % [GameManager.get_port_name(pid), GameManager.get_port_name(back)]
	_log(_ink(UiTheme.CINNABAR, t))
	_refresh_status()


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
		var bearing := _compass_bearing()
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


## 罗盘朱针与盘下针名指的方位：航行中是当日所在那一段的罗经（course_bearing，逐日跟段）；未发舶时与去向牌同取起讫两港
## 直连的方位（Voyage.overall_bearing）。原先未发舶也取出港第一段：广州三向头一段都是出珠江口的「乙针」，牌上往占城写
## 「南　丁未针」、往漳州泉州写「东　寅甲针」，罗盘一律指「乙针」；明州往福州牌上写「西南　未针」，罗盘指「丑针」，
## 差 179 度——全港对 182 对里 113 对两处针名对不上（lane w53-1）
func _compass_bearing() -> float:
	if sailing:
		return course_bearing
	return Voyage.overall_bearing(origin_port, selected_port)


## 针位读法：正对一向为「X针」，落在两向之间为「XY针」（分辨率 7.5 度，《真腊风土记》「行丁未针」）
## 验收 history:F6：「单X针」是《顺风相送》等明代针路簿写法，宋末只写「X针」（如「乙针」），缝针仍「乙辰针」
static func needle_name(bearing: float) -> String:
	var k := int(round(fposmod(bearing, 360.0) / 7.5)) % 48
	if k % 2 == 0:
		return "%s针" % str(COMPASS_24[k / 2])
	var a := str(COMPASS_24[(k - 1) / 2])
	var b := str(COMPASS_24[((k + 1) / 2) % 24])
	return "%s%s针" % [a, b]


## 题记框：墨线双框，竖写「東南海道圖」，旁注「每方折地百里」（《禹迹图》图首方框之制）。图名用朱雀仿宋（宋刻本气），旁注小字仍文楷
func _draw_cartouche(c: Control) -> void:
	var font: Font = map.font if (map != null and map.font != null) else UiTheme.font()
	var title_font: Font = map.font_title if (map != null and map.font_title != null) else font
	var rect := Rect2(Vector2(2, 2), c.size - Vector2(4, 4))
	c.draw_rect(rect, Color(MAP_PAPER, 0.92), true)
	c.draw_rect(rect, Color(MAP_INK, 0.85), false, 1.5)
	c.draw_rect(rect.grow(-4.0), Color(MAP_INK, 0.45), false, 1.0)
	var title := "東南海道圖"
	var y := 22.0
	var x_main := rect.position.x + 14.0
	for ch in title:
		var w := title_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		c.draw_string(title_font, Vector2(x_main + 12.0 - w * 0.5, y + 12.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MAP_INK)
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
	_condition_layer.modulate.a = 0.0
	move_child(_condition_layer, get_child_count() - 1)
	if _condition_tween and _condition_tween.is_valid():
		_condition_tween.kill()
	_condition_tween = create_tween()
	_condition_tween.tween_property(_condition_layer, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _close_condition() -> void:
	if _condition_layer != null:
		if _condition_tween and _condition_tween.is_valid():
			_condition_tween.kill()
		_condition_layer.modulate.a = 1.0
		_condition_layer.visible = false


func _on_condition_dim(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed:
			_close_condition()


func _open_event_panel() -> void:
	_close_condition()
	event_panel.visible = true
	event_panel.modulate.a = 0.0
	if _event_tween and _event_tween.is_valid():
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_property(event_panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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
	# 委办在身：顶匾第一行短标（≤3 日或逾期朱砂），不折行
	var cst_strip := GameState.contract_status()
	if not cst_strip.is_empty():
		var left_st: int = int(cst_strip.get("days_left", 0))
		var tag := "委办已逾" if left_st < 0 else ("委办 %d 日" % left_st)
		var tag_col := UiTheme.CINNABAR if left_st <= 3 else UiTheme.HONEY
		line1 += "　[color=#%s]%s[/color]" % [UiTheme.hex(tag_col), tag]
	var note := _latest_note
	if sailing:
		var pct := 0
		if total_li > 0.0:
			pct = int(clampf((total_li - remaining_li) / total_li, 0.0, 1.0) * 100.0)
		# 验收 sail:SAIL-3：末日进度会冲过头，余程钳到 0，不显示负数
		note = "航行　第 %d 日　行成 %d　余 %d 里" % [days_elapsed, pct, maxi(0, int(remaining_li))]
	# Lane U：顶匾第二行截短，告警朱字与航讯不折行（strip 已 AUTOWRAP_OFF）；按匾宽、按句收，见 _strip_note_fit（lane w53-14）
	note = _strip_note_fit(note)
	var dim := UiTheme.hex(UiTheme.TEXT_DIM)
	_strip_line.text = line1 + "\n[color=#%s]%s[/color]" % [dim, note]


## 顶匾第二行收字（lane w53-14 定「28 字匾额截断」一题）：按匾上实宽收，不按死字数。1280 宽下这一格约 844 像素、放得下
## 四十来字，原先一律截 28 字——夺船、沉船这类交代句只剩「所夺「快…」，「「」也落了单，匾右边空着三百多像素。
## 放得下整句照上；放不下退到放得下的最后一个句末（。！？）收「…」；头一句都放不下才按宽硬截。札记里全句照旧。
## 匾还没排版（size 0：首帧前、不在树）按 1280 宽的匾宽算；排好后 resized 再按实宽重收一次。
const STRIP_NOTE_FALLBACK_PX := 844.0
const STRIP_NOTE_PAD_PX := 8.0


func _strip_note_fit(note: String) -> String:
	if _strip_line == null:
		return note
	var f: Font = _strip_line.get_theme_font("normal_font")
	var fs: int = _strip_line.get_theme_font_size("normal_font_size")
	var avail := (_strip_line.size.x if _strip_line.size.x > 0.0 else STRIP_NOTE_FALLBACK_PX) - STRIP_NOTE_PAD_PX
	return fit_strip_note(note, avail, func(s: String) -> float: return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


## 纯函数（探针可用假尺量）：measure(s) 给出 s 的宽。量得放得下原样返回；否则退到放得下的最后一个句末加「…」；
## 一句都放不下按宽硬截加「…」——硬截处有没合上的「就退到那个「之前，句读、空白不留在「…」前。
static func fit_strip_note(note: String, avail: float, measure: Callable) -> String:
	if float(measure.call(note)) <= avail:
		return note
	var room := avail - float(measure.call("…"))
	var best := 0
	for i in note.length():
		if not "。！？".contains(note[i]):
			continue
		if float(measure.call(note.substr(0, i + 1))) > room:
			break
		best = i + 1
	if best > 0:
		return note.substr(0, best) + "…"
	var n := 0
	while n < note.length() and float(measure.call(note.substr(0, n + 1))) <= room:
		n += 1
	var cut := note.substr(0, n)
	var open := cut.rfind("「")
	if open > 0 and cut.rfind("」") < open:
		cut = cut.substr(0, open)
	return cut.rstrip("，、；：　 ") + "…"


func _panel_style() -> StyleBox:
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
	# 船况每变一回（起锚、每日行程、遇事）顺手记下海上「所在位置」，月初推日时 Economy 按它排战况
	Economy.sea_here = _sea_here()
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
		t += "[color=#%s]航行　第 %d 日・%s[/color]\n行成　%d\n余程　%d 里\n" % [
			UiTheme.hex(UiTheme.HONEY), days_elapsed, Voyage.order_name(course_order), int(pct * 100), maxi(0, int(remaining_li)),
		]
	# 在身委办（云端 bed9）
	var cst := GameState.contract_status()
	if not cst.is_empty():
		var left: int = int(cst.get("days_left", 0))
		var left_s := "限今日" if left == 0 else ("剩 %d 日" % left if left > 0 else "已逾")
		t += "[color=#%s][b]委办[/b][/color]\n%s ×%d 运往 %s　%s\n" % [
			gold,
			GameManager.get_good_name(str(cst.get("good_id", ""))),
			int(cst.get("remaining", 0)),
			GameManager.get_port_name(str(cst.get("dest", ""))),
			left_s,
		]
	t += "金钱　[b]%d[/b]\n名声　%d　%s\n" % [GameState.money, GameState.fame, GameState.title_name()]
	t += "[color=#%s][b]船队[/b][/color]\n船数　%d　水手　%d\n舱位　%d / %d 料\n耐久　%d / %d\n士气　%d\n" % [
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
	if _run_port != "" and _run_port == selected_port:
		t += _ink(UiTheme.CINNABAR, _run_brief()) + "\n"
	# 1280 宽下这行连「水粮足」一起会折行、「日」字孤悬（-02 巡检），水粮拆到下一行
	t += "%s　静风 %d 日　遇事约 %d 日　八成 %d 日\n" % [
		Voyage.order_name(course_order), int(plan["days"]), int(plan["expected_days"]), int(plan["safe_days"]),
	]
	t += "水粮足 %d 日\n" % int(plan["supply_days"])
	t += "静风　针路 %d　外洋 %d　傍岸 %d 日\n" % [int(plan_rumb["days"]), int(plan_off["days"]), int(plan_coast["days"])]
	t += "遇事　针路 %d　外洋 %d　傍岸 %d 日\n" % [
		int(plan_rumb["expected_days"]), int(plan_off["expected_days"]), int(plan_coast["expected_days"]),
	]
	t += "八成　针路 %d　外洋 %d　傍岸 %d 日\n" % [
		int(plan_rumb["safe_days"]), int(plan_off["safe_days"]), int(plan_coast["safe_days"]),
	]
	t += "保货　针路 %d　外洋 %d　傍岸 %d\n" % [
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
		t += "受潮　%s　针路 %d　外洋 %d　傍岸 %d\n" % [
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
			t += _ink(UiTheme.CINNABAR, "委办剩 %d 日　静风 %d 日　赶不上" % [left, calm_days]) + "\n"
		elif rough_days > left:
			t += _ink(UiTheme.HONEY, "委办剩 %d 日　静风 %d　遇事约 %d　或误期" % [left, calm_days, rough_days]) + "\n"
		elif safe_days > left:
			t += _ink(UiTheme.HONEY, "委办剩 %d 日　遇事约 %d　八成 %d　未稳" % [left, rough_days, safe_days]) + "\n"
		else:
			var hold_shown := int(plan.get("hold_tenths", 0))
			var spoil_shown := 10
			if not damp.is_empty() and str(damp.get("good_id", "")) == str(cst.get("good_id", "")):
				spoil_shown = Voyage.cargo_hold_tenths(Voyage.spoil_hold_chance(float(damp["rate"]), int(damp["qty"]), safe_days))
			if hold_shown < 8:
				t += _ink(UiTheme.HONEY, "委办剩 %d 日　遇事约 %d　八成 %d　保货 %d，不到八成" % [left, rough_days, safe_days, hold_shown]) + "\n"
			elif spoil_shown < 8:
				t += _ink(UiTheme.HONEY, "委办剩 %d 日　遇事约 %d　八成 %d　受潮只有 %d" % [left, rough_days, safe_days, spoil_shown]) + "\n"
			else:
				t += _ink(UiTheme.MOSS, "委办剩 %d 日　遇事约 %d　八成 %d" % [left, rough_days, safe_days]) + "\n"
	if not cst.is_empty():
		var need := int(cst.get("remaining", 0))
		var have := Fleet.cargo_qty(str(cst.get("good_id", "")))
		if have < need:
			t += _ink(UiTheme.HONEY, "舱中%s　%d / 委办 %d　到港或交不齐" % [
				GameManager.get_good_name(str(cst.get("good_id", ""))), have, need,
			]) + "\n"
	if not Voyage.is_known_route(origin_port, selected_port):
		t += _ink(UiTheme.HONEY, "此非熟路。针路与外洋都可能迷航，傍岸靠岸影，迷航少一些。") + "\n"
	var supply_have := int(plan["supply_days"])
	var supply_mean := int(plan["expected_days"])
	var supply_safe := int(plan["safe_days"])
	if supply_have < supply_safe:
		if supply_have < supply_mean:
			t += _ink(UiTheme.CINNABAR, "水粮 %d 日　遇事约 %d 日　半途必尽" % [supply_have, supply_mean]) + "\n"
		else:
			t += _ink(UiTheme.HONEY, "水粮够遇事约 %d　八成 %d　或断粮" % [supply_mean, supply_safe]) + "\n"
	return t


func _refresh_hand() -> void:
	for c in heading_row.get_children():
		c.queue_free()
	_hand = HeadingDraft.deal(origin_port, GameState.draft_salt)
	# 闯封锁的去处不在三向里：选着它、还闯得（围着、有米粮）就留着，换了去处或闯不得了就作罢
	if not sailing and _run_port != "" and (_run_port != selected_port or not _run_offerable(_run_port)):
		_run_port = ""
	if selected_port not in _hand and selected_port != _run_port:
		selected_port = ""
	for pid in _hand:
		heading_row.add_child(_make_heading_card(str(pid)))
	sail_button.disabled = selected_port == "" or sailing
	sail_button.text = "闯封锁" if _run_port != "" else "就这一向"
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
	name_lbl.add_theme_color_override("font_color", UiTheme.GOLD_HI if UiTheme.IS_JUANBEN else UiTheme.TIDE)
	box.add_child(name_lbl)

	var wind_mark := str(plan["wind_desc"])
	if plan.get("wind_changes", false):
		wind_mark += "・换风"
	var wind_lbl := _card_line("%s　约 %d 日" % [wind_mark, int(plan["days"])], UiTheme.TEXT)
	var hz := Crew.level_of("huozhang")
	if hz > 0:
		wind_lbl.text += "　火长　%s" % Crew.rank_word(hz)
	var dg := Crew.level_of("duogong")
	if dg > 0 and str(plan["wind_desc"]) in ["斜逆风", "顶头逆风"]:
		wind_lbl.text += "　舵工抢风"
	box.add_child(wind_lbl)
	# 方位按起讫两港直连算（Voyage.overall_bearing），不用 plan 里出港第一段的方位——泉州三条线出湾都是 102 度，三张牌会全写「东」
	box.add_child(_card_line("%d 里　%s" % [int(plan["distance"]), _bearing_phrase(Voyage.overall_bearing(origin_port, pid))], UiTheme.TEXT_DIM))
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
	# A quiet lift on hover makes the three route slips feel tactile without
	# changing their layout or adding a modern glow to the paper palette.
	hit.mouse_entered.connect(func():
		if not sailing:
			panel.modulate = Color(1.08, 1.08, 1.08, 1.0)
	)
	hit.mouse_exited.connect(func():
		panel.modulate = Color.WHITE
	)
	wrap.add_child(hit)
	if sailing:
		wrap.modulate = Color(1, 1, 1, 0.45)
	return wrap


func _card_line(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _select_heading(pid: String) -> void:
	if sailing:
		return
	if pid not in _hand:
		_log("今日风不放这一向。")
		return
	event_panel.visible = false
	_run_port = ""
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
## 去向牌上的方位：八方 + 针位（宋元舟师说「行乙针」「行丁未针」，不说度数；美术线评审 UX M4）
func _bearing_phrase(deg: float) -> String:
	var dirs := PackedStringArray(["北", "东北", "东", "东南", "南", "西南", "西", "西北"])
	var wrapped := posmod(int(round(deg)), 360)
	var idx := int(round(float(wrapped) / 45.0)) % 8
	return "%s　%s" % [dirs[idx], needle_name(deg)]


# ══════════════════════════════════════════════════════
#  海图绘制已移到 scripts/chart/MapView.gd（2026-09-25 海图重制）
# ══════════════════════════════════════════════════════

func _log(text: String) -> void:
	LogFold.push_line(self, UiTheme.plain_log(text), 0)
	_render_log()
	_latest_note = _plain_note(text)
	_refresh_strip()


## 海上的月初通告（GameManager.monthly_notice）：与港页记事栏同一套折叠，一连多则收成一行、原文一则不丢；
## 顶匾那一格仍取最上那则（「所在位置」那港的战况由 Economy 排在本批最后发，见 Economy.sea_here）
func _on_monthly_notice(text: String) -> void:
	LogFold.push_notice(self, UiTheme.plain_log(text), 0)
	_render_log()
	_latest_note = _plain_note(LogFold.latest(self))
	_refresh_strip()


## 札记正文：各条照原墨、空一行隔开（新的在上）；折起那一行可点
func _render_log() -> void:
	log_label.text = LogFold.render(self, "\n\n", false)


## 札记里点折起的通告那一行（或按月分组的某月）：就地展开 / 收起
func _on_log_meta(meta: Variant) -> void:
	if LogFold.toggle(self, meta):
		_render_log()


## 海上「所在位置」那一港：按船标当前坐标取最近的港——沿途中间港（航线折线傍过的他港）也算候选；
## 未定去向 / 没航程时即起锚港（lane w20-a5，修 w19-g9 遗留的里程过半判法；实现与等远先后口径见 Economy.nearest_sea_port）。
## 月初战况里这一港那条排到本批最后发、落在札记最上（与港页「所在港那条排最上」同一条规矩，lane w19-g9）
func _sea_here() -> String:
	if selected_port == "" or total_li <= 0.0:
		return origin_port
	return Economy.nearest_sea_port(origin_port, selected_port, total_li - remaining_li)


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
	sailing = true; _a11y_sync()  # lane w54-a11y：起锚即全退回不拿焦点（验收 CR-5）
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
	Voyage.begin_voyage()  # 上一程了结过的战时遭遇清掉（lane w54-seaevents）
	if back_button:
		back_button.disabled = true
	_sync_order_buttons()

	sail_button.disabled = true
	_lock_hand()
	# 图：船标启程，镜头框住起讫两港
	_sync_map()
	_frame_departure()

	event_panel.visible = false
	if _run_port != "":
		_log(_ink(UiTheme.CINNABAR, "闯封锁：运米粮 %d 件往%s，航程 %d 里。" % [
			Fleet.cargo_qty("grain"), GameManager.get_port_name(selected_port), int(total_li)]))
	else:
		_log(_ink(UiTheme.GOLD, "启程往 %s，航程 %d 里。" % [GameManager.get_port_name(selected_port), int(total_li)]))
	_SFX.play(self, &"chart_depart")  # lane w54-audio：帆吃满风、船头破浪
	_sail_next_day()


## 发舶取景：框住起讫两港（缩到最小也装不下就保起点），镜头从此跟船（lane w53-1，见 MapView.set_follow）
func _frame_departure() -> void:
	if map:
		map.frame_ports([origin_port, selected_port], 0.30, 0.9)
		map.set_follow(true)


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
	if not await _advance_ship_marker() or serial != _sail_serial or not sailing or not is_inside_tree():
		return

	# 补给见底的警告
	if Fleet.supply_days() <= 0 and Fleet.total_crew() > 0:
		_log(_ink(UiTheme.CINNABAR, "第 %d 日・水粮已尽　舱中有人病倒" % days_elapsed))

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


## 把船标推到当前已行里程处；这一日的动画走完返回 true。被下一段顶掉或离树返回 false，调用方自退。
## 不直接 await 补间的 finished（lane gd17）：move_ship_* 起新一段会 kill 上一段，kill 掉的补间永不发 finished；
## 回港换场景时补间随 MapView 作废也不发。协程永不醒，栈上的补间与挂起的协程互相引住，退出报 ObjectDB 泄漏。
## 改等自有信号：补间放完 / 作废（_cancel_marker：起新一段前、离树时）都会唤醒，按序号分辨。
func _advance_ship_marker() -> bool:
	_cancel_marker()
	if map == null:
		return true
	var traveled := clampf(total_li - remaining_li, 0.0, total_li)
	var at: Dictionary = Voyage.point_along_track(origin_port, selected_port, traveled)
	var heading := Voyage.bearing_at(origin_port, selected_port, traveled)
	var dur := DAY_SECONDS_FAST if Input.is_key_pressed(KEY_SPACE) else DAY_SECONDS
	var frac := 0.0 if total_li <= 0.0 else traveled / total_li
	var tw := map.move_ship_lonlat(float(at["lon"]), float(at["lat"]), heading, frac, dur)
	if tw == null:
		return true
	var seq := _marker_seq
	tw.finished.connect(_wake_marker.bind(seq), CONNECT_ONE_SHOT)
	await _marker_woken
	return seq == _marker_seq


func _wake_marker(seq: int) -> void:
	if seq == _marker_seq:
		_marker_woken.emit()


## 作废还挂着的船标等待并当场唤醒（醒来见序号已变返回 false）；没人等时空发一声无妨。
func _cancel_marker() -> void:
	_marker_seq += 1
	_marker_woken.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_cancel_marker()
		Economy.sea_here = ""


func _show_event(event: Dictionary) -> void:
	pending_event = event
	event_title.text = "第 %d 日・%s" % [days_elapsed, event.get("title", "事")]
	event_text.text = event.get("text", "")
	for c in event_actions.get_children():
		c.queue_free()

	var kind: int = event.get("kind", Voyage.EventKind.NONE)
	if kind == Voyage.EventKind.STORM or kind == Voyage.EventKind.SHOAL:
		_SFX.play(self, &"chart_storm" if kind == Voyage.EventKind.STORM else &"chart_shoal")  # lane w54-audio：风涛 / 浅滩各一声
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
		_add_event_action("献上买路财", _on_pay_pirates); _tutorial_pirate()  # 新手小笺（lane w54-tutorial）
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
			_add_event_action("交出一条船（名声 +6）", _on_requisition_surrender)
		_add_event_action("塞钱免征", _on_requisition_bribe)
		_add_event_action("趁夜溜走", _on_requisition_flee)
	elif kind == Voyage.EventKind.YUAN_PATROL:
		_add_event_action("落帆受检", _on_patrol_submit)
		_add_event_action("迎战", _on_fight_patrol)
		_add_event_action("扬帆逃走", _on_flee_pirates)
	elif kind == Voyage.EventKind.BLOCKADE:
		_add_event_action("迎战", _on_fight_blockade)
		_add_event_action("掉头回航（米粮扣下）", _on_run_yield)
	elif kind == Voyage.EventKind.REFUGEE:
		_add_event_action("载人同行（水粮 −2 成）", _on_refugee_take)
		_add_event_action("分些水粮，不载人（水粮 −1 成）", _on_refugee_share)
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
			line = "[color=red]钱匣里凑不齐这个数。有人自己下了舢板，走了 %d 人。[/color]" % int(result.get("crew_lost", 0))
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


## Lane L：海战题签用港外海域名（「泉州外海」）；无起运港则退回「外海」。
## 港取船这一日的所在（_sea_here：船标所在里程处离得最近的港），不取起锚港——原先恒写起锚港，泉州往博多走到九成、
## 船离泉州两千三百里、就在博多唐房外，题签仍写「泉州外海・遇敌」，海战的流也按闽海定（SeaState 按题签里的港名认海域），
## 不是那一带的黑潮（lane w53-1）
func _battle_sea_name() -> String:
	var pid := _sea_here()
	if pid == "":
		pid = str(GameState.last_port)
	var pname := str(GameManager.get_port_name(pid))
	if pname.strip_edges() == "" or pname == pid:
		return "外海"
	return "%s外海" % pname


func _on_fight_pirates() -> void:
	event_panel.visible = false
	var power := _fleet_power()
	var enemy := randf_range(180.0, 520.0)
	# P4-1 海战接入：构造战斗上下文，切 WorldMap 炮击分胜负
	GameManager.pending_battle = {
		"battle": true,
		"power": enemy,
		"player_power": power,
		"enemy": [PIRATE_ENEMY.duplicate()],
		"sea_name": _battle_sea_name(),
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
	_battle_notes(outcome, data)  # lane w54-polish：赏钱分账 / 人心 / 大风两散 / 接任旗舰的旁注小笺（只读 data 与船队，不动账）
	# 闯封锁拦港那一仗（_on_fight_blockade 起的）：这一程途中撞上的海寇、哨船不算，只认 source.event
	var run_fight := str((GameManager.pending_battle.get("source", {}) as Dictionary).get("event", "")) == "blockade"
	# w53-p6-landing：剿寨那一行要看这一仗打的是谁（海寇还是官军），下船的人与所在港也取收战这一刻的——
	# 胜局底下 _after_action_offer 挂卡就读这两样，得在分胜负之前扣住（原先扣在尾段，挂卡读到的是上一仗的，lane w54-hunt）；
	# 尾段清空 pending_battle 之后再取不到，卡是异步等的也不再现取。
	_landing_src = (GameManager.pending_battle.get("source", {}) as Dictionary).duplicate()
	_landing_port = _sea_here()
	if outcome == "win":
		# combat12：按敌船下场分账（win_kind）——敌降全赏走受降句；只是遁走的赏半（spoil_rule half）走敌遁句。
		# w53-16 一期：开关 bounty_by_outcome 开时，赏钱改读 combat_phases.json「spoil」分赃规则——
		# 击沉 1/3、逼降全赏、夺船给船（不另加钱）、敌逃一半；读不到数据退回旧区间。
		var kind := win_kind(data)
		var surrendered := kind == "surrender"
		var fled_only := kind == "fled"
		var spoil := _spoil_by_outcome(data, fled_only) if _Switches.on("bounty_by_outcome") \
			else (int(randf_range(75, 300)) if fled_only else int(randf_range(150, 600)))
		GameState.add_money(spoil)
		var fame_res: Dictionary = GameState.add_fame(3)
		Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 5)
		# 名声照修埠 / 赴试 / 呈报的口径写进注记，改题跟在名声后（原先只在改题时提一句，平常加 3 不吭声；lane w53-10 八轮）
		var promo := "名声加 %d。" % int(fame_res.get("gained", 0))
		if fame_res.get("promoted", false):
			promo += "案册改题「%s」。" % str(fame_res.get("title", {}).get("name", ""))
		# Lane N：战果注记走 CombatFx 论文纪实句；接舷夺船时附一句并入注记
		var win_msg := _CombatFx.sea_win_note(spoil, int(dmg), promo)
		if surrendered:
			win_msg = _CombatFx.sea_surrender_note(spoil, int(dmg), promo)
		elif fled_only:
			win_msg = _CombatFx.sea_fled_note(spoil, int(dmg), promo)
		if bool(data.get("boarded", false)):
			win_msg = "接舷既定。" + win_msg
		# w53-16 一期战后单子：先两三行写这一仗的下场（谁降了、沉几艘、救起几人），再写账目原句（一个 Enter 结束）
		if _Switches.on("after_action"):
			var sheet := _Letterbox.aftermath_note(_Letterbox.fates_of(data), int(data.get("rescued", 0)))
			if sheet != "":
				win_msg = sheet + win_msg
		_log(_ink(UiTheme.MOSS, win_msg))
		# w53-p4-after 四期：战后收拾小卡（押船 / 救人 / 俘虏 / 索赎 / 追击）——札记落下后挂卡，
		# 玩家 Enter 或点「收拾停当」再续航行（返程收尾随卡走）；开关全关 / 无可挂行 = 旧形直落。
		_after_action_offer(outcome, data)
	elif outcome == "lose":
		Fleet.morale = maxi(0, Fleet.morale - 12)
		# WorldMap 只在旗舰沉没时发 lose。先按该船货舱全损记账，
		# 不要写成「部分」——护航船还在则只清旗舰，全队耐久归零再由沉没结算收尾。（云端 c148；00b4 同向但只判全队）
		if bool(data.get("sunk", false)) or Fleet.total_durability() <= 0.0:
			var lost := Fleet.clear_ship_cargo(0)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			# lane w19-g2：沉前本场夺来、收战时仍在册的船（WorldMap._prize_ledger 按名册格认）在沉船句里交代；全队俱没不写
			var fleet_gone := Fleet.total_durability() <= 0.0
			var mv_s: Dictionary = data.get("stores_moved", {})
			var prize_s := "" if fleet_gone else _CombatFx.sea_prize_note(data.get("prizes", []), int(mv_s.get("water", 0)), int(mv_s.get("food", 0)))
			var sunk_msg := _CombatFx.sea_sunk_note(lost_str, int(dmg), fleet_gone, prize_s)
			# w53-16 一期 13c：旗舰沉了、护航还在时，把沉船移出船队、旗舰交给护航船；开关 flagship_handoff 关掉照旧
			var handoff_s := _flagship_handoff() if _Switches.on("flagship_handoff") else ""
			_log(_ink(UiTheme.CINNABAR, _lose_aftermath(data) + sunk_msg + handoff_s))
		else:
			var lost := Fleet.lose_cargo_ratio(0.25)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			# lane w53-14：我方降幡写降幡句（不写失守的「白刃不利」）；两式都交代本场夺来、收战时仍在册的船
			var mv_l: Dictionary = data.get("stores_moved", {})
			var prize_l := _CombatFx.sea_prize_note(data.get("prizes", []), int(mv_l.get("water", 0)), int(mv_l.get("food", 0)))
			if str(data.get("morale_verdict", "")) == "player_struck" or bool(data.get("struck", false)):
				_log(_ink(UiTheme.CINNABAR, _lose_aftermath(data) + _CombatFx.sea_struck_note(lost_str, int(dmg), prize_l)))
			else:
				_log(_ink(UiTheme.CINNABAR, _lose_aftermath(data) + _CombatFx.sea_board_lose_note(lost_str, int(dmg), prize_l)))
	else:  # flee / disengaged
		# lane fx3：夺过船再脱身，夺船句接在脱战句之后（同一行注记；无夺船时为空串，原句不变）
		var mv: Dictionary = data.get("stores_moved", {})
		var prize := _CombatFx.sea_prize_note(data.get("prizes", []), int(mv.get("water", 0)), int(mv.get("food", 0)))
		if bool(data.get("parted", false)) or outcome == "disengaged":
			# w53-16 一期：大风两散与天黑两散分开写——风到七级以上不能战（combat_phases.json t_gale，
			# 机制归 w53-17 的 gale 键对接：outcome=disengaged 且 data.gale 时写风，flee{parted} 照旧写天晚）
			if bool(data.get("gale", false)):
				_log(_ink(UiTheme.INK, "海风转厉，两边各自收帆。" + prize))
			else:
				_log(_ink(UiTheme.INK, _CombatFx.sea_parted_note() + prize))
		elif data.get("flee_ok", false):
			remaining_li += Fleet.fleet_speed() * 0.5  # 绕路
			if prize == "":
				_log_shook_pursuers()
			else:
				_log(_ink(UiTheme.MOSS, _CombatFx.sea_flee_ok_note() + prize))
		else:
			Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
			var lost := Fleet.lose_cargo_ratio(0.18)
			var lost_str := ""
			for gid in lost.keys():
				lost_str += "%s %d　" % [GameManager.get_good_name(gid), lost[gid]]
			var fail_msg := _CombatFx.sea_flee_fail_note(lost_str)
			if prize != "":
				# 被夺货物清单收尾是全角空格、不带句号（strip_edges 不去全角空格）：接夺船句前去掉空格补句号
				fail_msg = fail_msg.rstrip("　 ")
				if not fail_msg.ends_with("。"):
					fail_msg += "。"
			_log(_ink(UiTheme.CINNABAR, fail_msg + prize))
	# lane w53-p6-escort：护航上阵的下场（沉 / 被夺 / 退出战阵 / 受损 / 跳帮夺船）——WorldMap 收战时已照实记回 Fleet，这里只写一句札记
	var escort_note := _EscortWing.settle_note(data)
	if escort_note != "":
		_log(_ink(UiTheme.INK, escort_note))
	if run_fight and _run_port != "":
		_run_settle(outcome, data)
	GameManager.pending_battle = {}
	if not _after_action_pending():
		# 没挂卡（开关全关 / 无可挂行 / 非胜局）：照旧当帧续航行
		_finish_battle(outcome)
		return
	# 挂了卡：返程收尾（札记以外的航行 / 底栏 / 条件页）等卡按「收拾停当」再走（见 _on_after_action_done）


## 返程收尾（原 _on_battle_result 尾段）：等卡按下一张才走；没卡时照旧当帧
func _finish_battle(outcome: String) -> void:
	back_button.disabled = voyage_started
	for c in get_children():
		if c is CanvasItem:
			c.visible = true
	_close_condition()
	_refresh_status()
	_after_combat()


## 战后收拾卡是不是还挂着（_after_action_offer 挂上了等玩家 Enter）：挂着 = true
var _aa_pending := false
func _after_action_pending() -> bool:
	return _aa_pending


## w53-p6-landing 剿寨那一行挂卡时要用的两样，在清空 pending_battle 之前扣住（见 _on_battle_result 尾段）：
## _landing_src = 这一仗的 source（认「是不是海寇」），_landing_port = 挂牌那一刻船所在的那一港（认「在不在宋土沿海」）。
## 卡是异步等的，等玩家 Enter 时 pending_battle 早清了、船也走了一段，两样都不能现取。
var _landing_src: Dictionary = {}
var _landing_port: String = ""


## 追击挨舷炮的一发船体伤（w53-p4-after）：WorldMap 侧现码（lane w53-2 后）敌一发 Ship._hull_loss 按
## DamageModel.apply_hit 折算（弹道种类 / 部位 / 距离衰减分摊），没有单一常量可引——这里取战后门闸一发的
## 明文量（5.0 船体 = Ship._fire_broadside 旧账「铁球」中一发的中位量，挨 3 发 ≈ 挨一舷轻伤）。
## 折算过程走 _AfterAction.pursuit_damage（按敌船体 × after_action.pursue.broadside_hits 乘开）。
const WAA_HIT_DMG := 5.0


## 挂战后收拾小卡（win 才挂；lose / flee 直落）。空卡不挂——_aa_pending 留 false，调用方当帧续航行。
## w53-p6-landing：海战赢了、敌是海寇、船在宋土沿海时，单子末尾再添一行「登岸剿寨」（开关 landing_raid）。
## 那一行不走 AfterAction（押船 / 救人那一套是海上的事），走 LandingRaid——挂法一样，落账各走各的。
func _after_action_offer(outcome: String, data: Dictionary) -> void:
	if outcome != "win":
		return
	# 剿寨读数每场清零（挂没挂那一行都清）：探针 / 复看读 last_landing_report() 时不会拿到上一场的数
	_landing_report = {}
	var choices: Array = _AfterAction.choices_for(outcome, data)
	for row in _Landing.choices_for(outcome, _landing_src, _landing_port):
		choices.append(row)
	if choices.is_empty():
		return
	# 真挂卡（窗口）：挂上等 Enter；headless 下 attach 返回 null——探针 / 门检不挂卡，走探针直接落账那一路
	var lb := _Letterbox.attach_after_action(self, choices, _on_after_action_done.bind(choices, data))
	if lb == null:
		return
	_aa_pending = true
	_card_notes(choices)  # lane w54-polish：卡上头一回有押船救人那几行 / 登岸剿寨那一行，各出一张旁注


## 卡按下「收拾停当」：照选择逐项落账（钱 / 名声 / 收编 / 夺船漂走 / 追击一舷），注记句缀进札记，再续航行
func _on_after_action_done(chosen: Dictionary, choices: Array, data: Dictionary) -> void:
	_aa_pending = false
	var notes: PackedStringArray = []
	for row in choices:
		if not row is Dictionary:
			continue
		var key := str(row.get("key", ""))
		var c := (row as Dictionary).duplicate()
		c["chosen"] = str(chosen.get(key, ""))
		# w53-p6-landing 剿寨那一行不走 AfterAction（那一套是海上的账：押船 / 救人 / 俘虏 / 索赎 / 追击）——
		# 认 key 岔出来走 LandingRaid，落账与注记各归各的，AfterAction.apply 对认不得的 key 本来就返 ok=false
		if key == "landing":
			var lres: Dictionary = _Landing.layout(c, Fleet.total_crew(), Fleet.captain_power(), Fleet.morale_factor())
			if bool(lres.get("ok", false)):
				_landing_settle(lres, notes)
			continue
		var r: Dictionary = _AfterAction.apply(c, "win", data)
		if not bool(r.get("ok", false)):
			continue
		var note := str(r.get("note", ""))
		if note != "":
			notes.append(note)
		# 落账
		if int(r.get("money", 0)) != 0:
			GameState.add_money(int(r.get("money", 0)))
		if int(r.get("fame_gained", 0)) != 0:
			var fr: Dictionary = GameState.add_fame(int(r.get("fame_gained", 0)))
			if bool(fr.get("promoted", false)):
				notes.append("案册改题「%s」。" % str(fr.get("title", {}).get("name", "")))
		if int(r.get("crew_delta", 0)) > 0:
			Fleet.hire_crew(int(r.get("crew_delta", 0)))
		# 追击追上：比照夺船并入船队（WorldMap 原路——add_ship + settle_prize 按满体）
		if str(r.get("ship_added", "")) != "":
			var type_id := str(r.get("ship_added", ""))
			if Fleet.add_ship(type_id):
				Fleet.settle_prize(Fleet.ships.size() - 1, 1.0)
		# 追击没追上：挨一顿舷炮
		if str(r.get("pursuit_roll", "")) == "missed":
			Fleet.damage_fleet(_AfterAction.pursuit_damage(data, WAA_HIT_DMG))
		# 押船漂走：夺来 / 受降的船从名册摘掉（WorldMap 夺船已在册；派不出人看守的船放它漂）
		# 账：boarded_drifted 艘从名册尾往前摘（夺来 / 受降的船在 WorldMap 并入时排在尾）
		if int(r.get("boarded_drifted", 0)) > 0:
			_drift_prizes(int(r.get("boarded_drifted", 0)))
	if not notes.is_empty():
		_log(_ink(UiTheme.MOSS, "".join(notes)))
	_finish_battle("win")


## 押船漂走：从名册尾摘掉 drifted 艘夺来 / 受降的船（它们的 cargo 跟着沉，不进账——
## WorldMap 并入时夺船舱货本来就按「打捞所得」给了 spoil，名册格摘了就摘了）。
func _drift_prizes(drifted: int) -> void:
	for _i in drifted:
		if Fleet.ships.size() > 1:
			Fleet.ships.remove_at(Fleet.ships.size() - 1)


## 胜局分账（combat12）：surrender = 有敌船降幡（士气收场 enemy_struck / enemy_broken，或下场明细里有受降）；
## fled = 敌船一艘没沉、没焚、没夺、没降，只是遁走（combat_phases.json enemy_fled.spoil_rule half）；其余 ""（照胜局全赏）。
## 下场艘数走 CombatLetterbox.fate_counts（data.fates / struck_types / enemy_fled / 旗标），与出战题签同一口径：
## 士气收场的 morale_verdict 只看收场时在场的船，先沉一艘、后遁一艘也报 enemy_fled，所以不单凭它。
static func win_kind(data: Dictionary) -> String:
	var n: Dictionary = _Letterbox.fate_counts(data)
	var verdict := str(data.get("morale_verdict", ""))
	if int(n["struck"]) > 0 or verdict == "enemy_struck" or verdict == "enemy_broken":
		return "surrender"
	if bool(data.get("boarded", false)) or int(n["boarded"]) > 0 or int(n["sunk"]) > 0 or int(n["burned"]) > 0:
		return ""
	return "fled" if int(n["fled"]) > 0 else ""


## 赏钱按打法分（w53-16 一期，方案一页结论 3）：整场赏钱一笔，读 combat_phases.json「spoil」分赃规则——
## 有降幡全赏（base 150–600）；只是一群全遁一半（base × 0.5 = 75–300）；其余（击沉 / 焚毁收场，或什么都没捞着）
## 按 1/3（50–200）；夺船不加钱（船本身就是赏）。方案：击沉 1/3、逼降全赏、夺船给船、敌逃一半。
## 读不到数据（json 打不开、spoil 缺节、base 不足两档）退回旧区间原样（fled_only 半赏 75–300 / 全赏 150–600）。
## 二职业事「杂事缴获」：杂事每级按 spoil.zashi_spoil_mul_per_level（0.1）加赏；开关 crew_role_effects 关掉时不加。
static func _spoil_zashi_mul(cfg: Dictionary) -> float:
	return float(cfg.get("zashi_spoil_mul_per_level", 0.1))


static func _spoil_by_outcome(data: Dictionary, fled_only: bool) -> int:
	var d := _phases_data()
	var spoil_cfg: Dictionary = d.get("spoil", {}) if d is Dictionary else {}
	var base: Array = spoil_cfg.get("base", []) if spoil_cfg is Dictionary else []
	if base.size() != 2:
		return int(randf_range(75, 300)) if fled_only else int(randf_range(150, 600))
	var lo := float(base[0])
	var hi := float(base[1])
	var by_fate: Dictionary = spoil_cfg.get("by_fate", {})
	var mul := func(fate: String, fallback: float) -> float:
		return float((by_fate.get(fate, {}) as Dictionary).get("mul", fallback))
	var n: Dictionary = _Letterbox.fate_counts(data)
	var verdict := str(data.get("morale_verdict", ""))
	var has_struck := int(n.get("struck", 0)) > 0 or verdict == "enemy_struck" or verdict == "enemy_broken"
	var has_boarded := bool(data.get("boarded", false)) or int(n.get("boarded", 0)) > 0
	var total := 0.0
	if has_struck:
		total = randf_range(lo, hi)  # 逼降全赏
	elif fled_only:
		total = randf_range(lo, hi) * mul.call("fled", 0.5)  # 敌逃一半
	elif has_boarded:
		total = 0.0  # 夺船给船：钱不给，船就是赏
	else:
		total = randf_range(lo, hi) * mul.call("sunk", 0.333)  # 击沉 / 焚毁 / 什么都没捞着：三分之一
	# 二职业事「杂事缴获」：杂事会点，每级多一成
	if _Switches.on("crew_role_effects"):
		total *= 1.0 + _spoil_zashi_mul(spoil_cfg) * float(Crew.level_of("zashi"))
	return maxi(0, int(round(total)))


## 败局的战后单子头（w53-16）：把敌船下场明细成句垫在败局原句前面（同样一个 Enter 结束）；开关 off 时返 ""
static func _lose_aftermath(data: Dictionary) -> String:
	if not _Switches.on("after_action"):
		return ""
	return _Letterbox.aftermath_note(_Letterbox.fates_of(data), int(data.get("rescued", 0)))


## 13c：旗舰沉了、护航还在时，把沉船移出船队、旗舰交给护航船（新旗舰即首艘耐久 > 0 的船）。
## 坞位指着的船跟着沉船移出一道拨：坞位 0 → 归 0；坞位原在旗舰后面 → −1。返回接任句（没有护航返 ""，沉船不移）。
static func _flagship_handoff() -> String:
	if Fleet.ships.is_empty() or float((Fleet.ships[0] as Dictionary).get("durability", 0.0)) > 0.0:
		return ""
	var next := -1
	for i in range(1, Fleet.ships.size()):
		if float((Fleet.ships[i] as Dictionary).get("durability", 0.0)) > 0.0:
			next = i
			break
	if next < 0:
		return ""
	var lost_name := str((Fleet.ships[0] as Dictionary).get("name", "旗舰"))
	Fleet.ships.remove_at(0)
	GameState.berth_index = maxi(0, int(GameState.berth_index) - 1)
	return "「%s」沉入海底，「%s」接任旗舰。" % [lost_name, str((Fleet.ships[0] as Dictionary).get("name", "护航船"))]


## combat_phases.json 整表（_spoil_by_outcome 自取 spoil 节；读不到返回 {}）
static func _phases_data() -> Dictionary:
	var f := FileAccess.open("res://data/combat_phases.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _log_shook_pursuers() -> void:
	_log(_ink(UiTheme.MOSS, _CombatFx.sea_flee_ok_note()))


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
		var hull_was := float(Fleet.flagship().get("durability", 0.0))
		Fleet.damage_fleet(30.0 * Fleet.armor_damage_reduction())
		_log(_ink(UiTheme.CINNABAR, _flee_fail_note(lost_str, hull_was - float(Fleet.flagship().get("durability", 0.0)))))
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
		_log(_ink(UiTheme.CINNABAR, "拿不出买路钱，他们自己动手，逐船逐样搬走三成的货，零头也算一件。%s" % lost_str if not lost.is_empty() else "拿不出买路钱，舱里也翻不出货来。他们骂了几句，掉头走了。"))  # 舱空一件没搬不说搬货；lose_cargo_ratio 逐船逐样向上取整，一两件的货整批被搬（lane w54-seaevents）
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
	if idx == GameState.berth_index:
		GameState.berth_index = 0
	elif idx < GameState.berth_index:
		GameState.berth_index -= 1  # 交出的是坞位之前的船：坞位序号跟顺（待拍板 20h）
	Fleet.ships.remove_at(idx)
	GameState.add_fame(6)
	Fleet.morale = maxi(0, Fleet.morale - 4)
	Voyage.settle_war_event(Voyage.EventKind.REQUISITION)  # 册上记了名，这一程不再征（lane w54-seaevents）
	_log("[color=yellow]「%s」连船带货编入官军。小官在册子上记了你的名字，写得很工整。名声加 6。[/color]" % s.get("name", "一船"))
	_refresh_status()
	_on_event_continue()


func _on_requisition_bribe() -> void:
	event_panel.visible = false
	var cost: int = maxi(100, int(GameState.money * 0.15))
	if GameState.spend_money(cost):
		_log("[color=yellow]%d 钱换了册子上「已征」两个字。船一条没少。[/color]" % cost)
		Voyage.settle_war_event(Voyage.EventKind.REQUISITION)  # 「已征」了，这一程不再征（lane w54-seaevents）
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
		fine = mini(fine, GameState.money)
		_log("[color=red]被哨船追上。「抗征」二字记入册子，罚钱 %d%s。[/color]" % [fine, "，名声减 %d" % mini(4, GameState.fame) if GameState.fame > 0 else ""])  # 名声封底 0，写实扣（lane w54-voyage）
		GameState.add_money(-fine)
		GameState.add_fame(-4)
		Fleet.morale = maxi(0, Fleet.morale - 5)
		Voyage.settle_war_event(Voyage.EventKind.REQUISITION)  # 「抗征」记了册、罚过了，这一程不再征（lane w54-seaevents）
	_refresh_status()
	_on_event_continue()


## 元军哨船受检：有违禁货则没收加罚；无则放行
func _on_patrol_submit() -> void:
	event_panel.visible = false
	var contraband := GameState.contraband_units()
	if contraband > 0:
		var fine: int = mini(400, maxi(60, int(GameState.money * 0.2)))
		fine = mini(fine, GameState.money)
		_log("[color=red]舱底被翻了个底朝天。%d 件违禁之物起获，罚钱 %d。那个泉州口音的人说：「往后规矩变了。」[/color]" % [contraband, fine])
		GameState.confiscate_contraband()
		GameState.add_money(-fine)
		Fleet.morale = maxi(0, Fleet.morale - 6)
	else:
		Fleet.morale = maxi(0, Fleet.morale - 2)
		_log("[color=yellow]查了半日，没查出什么。对方在你的引目上盖了一个你不认得的印，放行。[/color]")
	Voyage.settle_war_event(Voyage.EventKind.YUAN_PATROL)  # 受检过了，这一程不再拦检（lane w54-seaevents）
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
		"enemy": [PATROL_ENEMY.duplicate()],
		"sea_name": _battle_sea_name(),
		"source": {"scene": "SeaChart", "event": "yuan_patrol"},
	}
	_enter_battle()


## 难民：载人费水粮、长名声；不停船伤士气
func _on_refugee_take() -> void:
	event_panel.visible = false
	Fleet.water = maxi(0, Fleet.water - int(ceil(Fleet.water * 0.2)))
	Fleet.food = maxi(0, Fleet.food - int(ceil(Fleet.food * 0.2)))
	GameState.add_fame(4)
	Fleet.morale = mini(Fleet.MORALE_MAX, Fleet.morale + 3)
	_log("[color=lime]把人接上船。甲板挤了，水粮吃得快了。有个老人一直握着你的手不放。名声加 4。[/color]")
	_refresh_status()
	_on_event_continue()


func _on_refugee_share() -> void:
	event_panel.visible = false
	Fleet.water = maxi(0, Fleet.water - int(ceil(Fleet.water * 0.1)))
	Fleet.food = maxi(0, Fleet.food - int(ceil(Fleet.food * 0.1)))
	GameState.add_fame(1)
	_log("[color=yellow]递过去几桶水和一袋米。他们没有道谢的力气，船慢慢漂远了。名声加 1。[/color]")
	_refresh_status()
	_on_event_continue()


func _on_refugee_pass() -> void:
	event_panel.visible = false
	_log("[color=red]没有停。水手们都没说话，只有舵工朝海里啐了一口。%s[/color]" % ("士气减 %d。" % mini(3, Fleet.morale) if Fleet.morale > 0 else ""))  # 士气封底 0，写实扣（lane w54-voyage）
	Fleet.morale = maxi(0, Fleet.morale - 3)
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
		note = "近岸细看，果然是%s。记入册子，赏格回市舶司呈报。" % d.get("name", "旧泊地")
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
	if _run_port != "" and _run_gate():
		return
	sailing = false
	Fleet.at_sea = false
	GameState.record_trip(origin_port, selected_port)
	GameState.last_port = selected_port
	_log(_ink(UiTheme.GOLD, "历 %d 日，抵 %s。" % [days_elapsed, GameManager.get_port_name(selected_port)]))
	GameManager.settle_ashore()  # 海上到了月份没走成的人，靠岸这会儿下船（lane w54-tavern）
	_SFX.play(self, &"chart_arrive")  # lane w54-audio：靠港钟

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
	_SFX.play(self, &"chart_sink")  # lane w54-audio：船身裂开
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
		GameState.last_port = _rescue_port()  # 捞回这一程的起锚港（闯封锁折回时 origin_port 已换成围城那港）
		_return_to_port()
	)
	_open_event_panel()


func _on_back_to_port() -> void:
	if voyage_started:
		return
	_return_unsailed()  # 没发舶就回港：船没离岸，候风再发候过的日子不算出过港（lane w54-voyage）


func _return_to_port() -> void:
	# 海战进行中回港会丢掉 battle_finished，战中已扣的耐久和舱货留在舰队上，赏罚不结算。（云端 be04）
	if GameManager.pending_battle.get("battle", false):
		return
	_sail_serial += 1
	Fleet.at_sea = false
	GameState.set_flag("return_to_port")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ══ 以下为本地 main 的新增函数，合并时因所在区块让位云端而被丢，按「本地纯新增保留」原样补回（2026-09-25） ══


# ══ w53-p6-landing 小规模登陆战（战斗系统方案 §十 第六期「复用陆战骰子」）══
# 新代码一律收在文件尾：docs/待策划拍板清单按行号引 Main.gd / SeaChart.gd 等，往中间插行会让
# check_decision_refs 判 DRIFT（COMMON 六期补充）。上面 `_after_action_offer` / `_on_after_action_done`
# 里各只留三五行接头，实体（判定、落账、注记）都在这一块。
#
# 入口：海战赢了、敌是海寇（pending_battle.source.event == "pirate"）、船停在宋土沿海的港外——
# 战后收拾小卡末尾多一行「登岸剿寨」。海寇寨不是城：不攻城、不占地，烧了窝、把东西搬回舱
# （方案 §七「不做大规模攻城战术层」，附 c3「不采纳攻打占城」）。
# 数量全在 scripts/combat/LandingRaid.gd（纯静态，骰子借 SiegeMelee.clash——与守城那一路同源）。
# 落账只动现有账：钱、舱货、名声（add_fame）、人手折损、士气；不加新账本、不加存档字段。

## 剿寨这一笔的读数（探针 / 后续复看用；没打过是空字典）：last_landing_report()
##   {won, enemy, landing, crew_lost, money, fame_gained, morale_delta, cargo:{货:件数}, loaded:{货:件数}}
var _landing_report: Dictionary = {}


func last_landing_report() -> Dictionary:
	return _landing_report.duplicate(true)


## 剿寨那一行落账：钱 / 名声 / 人手折损 / 士气 / 搬回舱的货，逐样真动全局，注记句缀进 notes（同一行札记）。
## 胜：寨里的钱掷一次进钱匣、寨里的老实货按上限搬进舱（装不下的留在岸上）、名声与士气各加一笔。
## 败：下船的人折一成半（LOSE_LOSS_RATE；Fleet.lose_crew_random 跨船摊扣、每船至少留一人）、士气掉一笔。
## 落账次序照 w53-p4-after 那一套（先钱后名声、先名声后折兵），与战后收拾卡其余各行同一路。
## 札记一句：胜「寨里的人没撑住，寨子烧了。搜出 N 钱，米粮 12 件、海盐 6 件、鹿皮 2 件搬回舱里。名声加 3。」；
## 败「寨门没打开，下船的人退回船上。折了 N 人。名声加 1。」——钱与货各说一遍，不重话。
func _landing_settle(res: Dictionary, notes: PackedStringArray) -> void:
	var won := bool(res.get("won", false))
	if int(res.get("landing", 0)) > 0:  # lane w54-audio：真下了船才有这一仗（收队回船、没人可下都不响）——一阵鼓，随后胜负磬音
		_SFX.play(self, &"landing_win" if won else &"landing_lose")
	if int(res.get("money", 0)) > 0:
		GameState.add_money(int(res.get("money", 0)))
	var fame_note := ""
	if int(res.get("fame_gained", 0)) != 0:
		var fr: Dictionary = GameState.add_fame(int(res.get("fame_gained", 0)))
		fame_note = "名声加 %d。" % int(fr.get("gained", 0))
		if bool(fr.get("promoted", false)):
			fame_note += "案册改题「%s」。" % str(fr.get("title", {}).get("name", ""))
	var crew_lost := 0
	if int(res.get("crew_lost", 0)) > 0:
		crew_lost = Fleet.lose_crew_random(int(res.get("crew_lost", 0)))
	Fleet.morale = clampi(Fleet.morale + int(res.get("morale_delta", 0)), 0, Fleet.MORALE_MAX)
	# 寨里的货搬进舱（按件数逐样试装：舱里装不下的件数留在岸上，不掉钱不报错——与牙行装不下同一口径）
	var cargo: Dictionary = res.get("cargo", {})
	var loaded := _landing_load(cargo)
	var line := _Landing.note_of(res)
	if won:
		line += "搜出 %d 钱" % int(res.get("money", 0))
		var cnote := _Landing.cargo_note(loaded, Callable(GameManager, "get_good_name"))
		if cnote != "":
			line += "，%s搬回舱里" % cnote
		line += "。"
		var left := _Landing.cargo_units(cargo) - _Landing.cargo_units(loaded)
		if left > 0:
			line += "舱里塞不下，%d 件留在岸上。" % left
	elif crew_lost > 0:
		line += "折了 %d 人。" % crew_lost
	line += fame_note
	notes.append(line)
	res["loaded"] = loaded
	_landing_report = res.duplicate(true)
	_refresh_status()


## 寨里搬回舱：{货: 请求件数} → {货: 实装件数}。逐样按 Fleet.add_cargo 的自动挑船口径试装
## （装不进这一样就少装几件，再装不下的留给下一样），均价成本记 WIN_CARGO_COST（剿来的，记 0）。
func _landing_load(cargo: Dictionary) -> Dictionary:
	var out := {}
	for gid in cargo.keys():
		var want := int(cargo[gid])
		var took := 0
		for _i in maxi(0, want):
			if not Fleet.add_cargo(str(gid), 1, _Landing.WIN_CARGO_COST):
				break
			took += 1
		if took > 0:
			out[str(gid)] = took
	return out


## lane w53-p6-escort：护航上阵的战后札记句（EscortWing.settle_note）
const _EscortWing := preload("res://scripts/combat/EscortWing.gd")


# ── 旁注小笺（lane w54-polish，CombatNotes；开关 combat_notes）──────────
## 收战这一拍（_on_battle_result 开头调，账还没落）：按这一仗带回的 data 与此刻船队判哪几样头一回露面——
## 赏钱按打法分（胜局）、人心（士气带回航程，data.morale_carry）、大风两散（data.gale）、
## 接任旗舰（旗舰沉了、船队里还有浮着的船——_flagship_handoff 同一判据，开关 flagship_handoff 归小笺自己那条认）。
## 看过的、开关关着的由 CombatNotes.want 挡掉；这里只排队，不改任何账
func _battle_notes(outcome: String, data: Dictionary) -> void:
	if outcome == "win":
		_Notes.offer(self, "bounty")
	if data.has("morale_carry"):
		_Notes.offer(self, "morale_carry")
	if bool(data.get("gale", false)):
		_Notes.offer(self, "gale")
	if outcome == "lose" and bool(data.get("sunk", false)) and _handoff_ready():
		_Notes.offer(self, "handoff")


## 旗舰沉了、后头还有一条浮着的船（_flagship_handoff 接任的条件，只看不动）
static func _handoff_ready() -> bool:
	if Fleet.ships.size() < 2 or float((Fleet.ships[0] as Dictionary).get("durability", 0.0)) > 0.0:
		return false
	for i in range(1, Fleet.ships.size()):
		if float((Fleet.ships[i] as Dictionary).get("durability", 0.0)) > 0.0:
			return true
	return false


## 战后收拾小卡真挂上了（_after_action_offer 里 _aa_pending 之后调）：卡上有押船 / 救人 / 俘虏 / 索赎 / 追击那几行
## 出「战后取舍」，有登岸剿寨那一行出「登岸剿寨」
func _card_notes(choices: Array) -> void:
	for row in choices:
		if row is Dictionary:
			_Notes.offer(self, "landing" if str(row.get("key", "")) == "landing" else "after_choices")


## lane w54-hunt 闯封锁（_run_offerable / _run_take / _run_seize 共用，函数体从上面原样搬来）：舱里能卖的米——
## 全队米粮减去在身委办要留着交货的（同牙行卖钮 / 守城押粮的口径，GameState.contract_kept）。
## 原先不分，闯一趟把委办要的米也一起卖了，委办再没有米可交，只能毁约。
func _run_grain_sellable() -> int:
	return maxi(0, Fleet.cargo_qty("grain") - GameState.contract_kept("grain"))


## lane w54-voyage：沉船被渔船捞回的港 = 这一程的起锚港。闯封锁没闯过去会起讫对调（_run_seize：origin_port 换成围城那港、
## 从港外往回走），回程再沉（风涛、海寇），原先拿 origin_port 当起锚港——人被捞进闯不进去的那座围城。
## 起锚港整程都记在 GameState.last_port（航行中只有 _arrive 改它），照它取；它空着才退回 origin_port
func _rescue_port() -> String:
	var home := str(GameState.last_port)
	return home if home != "" else origin_port


## lane w54-voyage：没发舶就点「回港」。Main 出港那一下记了（港、日）（Cinematics.note_departure），回港时「走了日子或换了港」
## 才挂抵港签（Cinematics.take_arrival，头注「海图上点『回港』原路折回不算」）——可海图上「候风再发」一回过三日，
## 候过再回港，船没离岸也挂一张抵港签。这里把出港那一笔改记成此刻此港，原地回港就不算抵港
const _Cine := preload("res://scripts/cutscene/Cinematics.gd")


func _return_unsailed() -> void:
	_keep_unused_permit()  # 没走成这一趟，出港时销掉的货引还回去（lane w54-tutorial）
	_Cine.note_departure(origin_port, Calendar.absolute_day())
	_return_to_port()


# ══ lane w54-a11y：海图只用键盘也走得通 ══
## 发舶前这几颗钮——航法三策、三张航向牌、「就这一向 / 候风再发 / 回港」——原先同顶上三颗一起都是 FOCUS_NONE
## （验收 CR-5：航行中按住空格加速，拿着焦点的钮会被空格按下），Tab / 方向键 / 回车一样都按不到，只用键盘出了港
## 就卡在海图上。改成：没起锚时这几颗收 Tab / 方向键焦点（焦点框照主题，牌上那颗覆盖钮原是空框），回车 / 空格按；
## 灰着的不收（Tab 不停在按不动的钮上）；鼠标 / 触屏点过不留焦点（点完即放，空格不会再按到刚点过的「候风再发」）；
## 一起锚（_lock_hand）全退回 FOCUS_NONE、放掉焦点——航行中照旧没有钮拿焦点，CR-5 不破。顶上「舆图 / 全图 / 船况」
## 航行中也按得，照旧不拿焦点：T / F 早有键，船况补 C 键。Esc：「船况」开着先合上，没发舶即「回港」。
## 选了航向牌整排重发（_refresh_hand 先 queue_free 旧排再排新排），焦点跟到新排同一位置那张牌上，不丢。
func _a11y_mount() -> void:
	heading_row.child_entered_tree.connect(_a11y_dress_card)
	for b in _a11y_deck_buttons():
		_a11y_drop_click_focus(b)
	_a11y_sync()


## 航法三策 + 「就这一向 / 候风再发 / 回港」（牌上的覆盖钮另由 _a11y_card_hits 取）
func _a11y_deck_buttons() -> Array:
	var out: Array = []
	if order_row != null:
		for c in order_row.get_children():
			if c is Button:
				out.append(c)
	for b in [sail_button, redraw_button, back_button]:
		if b != null:
			out.append(b)
	return out


## 眼下这一排三张牌的覆盖钮（queue_free 了还没走的旧排不算）
func _a11y_card_hits() -> Array:
	var out: Array = []
	if heading_row == null:
		return out
	for w in heading_row.get_children():
		if w.is_queued_for_deletion():
			continue
		var hit := _a11y_card_hit(w)
		if hit != null:
			out.append(hit)
	return out


func _a11y_card_hit(wrap: Node) -> Button:
	for c in wrap.get_children():
		if c is Button:
			return c
	return null


## 收不收焦点：航行中、灰着的不收；正拿着焦点又不该收的当场放掉
func _a11y_sync() -> void:
	for c in _a11y_deck_buttons() + _a11y_card_hits():
		var b := c as BaseButton
		var take := not sailing and not b.disabled
		if not take and b.has_focus():
			b.release_focus()
		b.focus_mode = Control.FOCUS_ALL if take else Control.FOCUS_NONE


## 新排进来的牌：覆盖钮挂上主题焦点框、点过不留焦点；旧排第 i 张拿着焦点，就把焦点交给新排第 i 张
func _a11y_dress_card(node: Node) -> void:
	var hit := _a11y_card_hit(node)
	if hit == null:
		return
	hit.add_theme_stylebox_override("focus", UiTheme.theme().get_stylebox("focus", "Button"))
	_a11y_drop_click_focus(hit)
	hit.focus_mode = Control.FOCUS_NONE if sailing else Control.FOCUS_ALL
	var vp := get_viewport()
	var held: Control = vp.gui_get_focus_owner() if vp != null else null
	if held is Button and held.get_parent() != null and held.get_parent().is_queued_for_deletion() \
			and held.get_parent().get_parent() == heading_row:
		var old_i := 0
		for w in heading_row.get_children():
			if w == held.get_parent():
				break
			if w.is_queued_for_deletion():
				old_i += 1
		if old_i == _a11y_card_hits().find(hit):
			_a11y_refocus.call_deferred(hit)
	# 「就这一向」灰不灰在 _refresh_hand 排完牌之后才定，排完再对一遍
	_a11y_sync.call_deferred()


func _a11y_refocus(hit: Button) -> void:
	if is_instance_valid(hit) and hit.is_visible_in_tree() and hit.focus_mode != Control.FOCUS_NONE:
		hit.grab_focus()


## 鼠标 / 触屏（引擎把触点模拟成左键）按下时引擎给的那份焦点，松手、钮按完之后即放（按下当中放焦点，引擎当这一下没点成）
func _a11y_drop_click_focus(b: BaseButton) -> void:
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			_a11y_unfocus.call_deferred(b)
	)


func _a11y_unfocus(b: BaseButton) -> void:
	if is_instance_valid(b) and b.has_focus():
		b.release_focus()


## Esc 合船况 / 没发舶回港，C 开合船况。海战一层叠在海图上时（pending_battle.battle）不收，Esc 照旧归海战（B / Esc 弃战）
func _shortcut_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or GameManager.pending_battle.get("battle", false):
		return
	if k.keycode == KEY_ESCAPE:
		if _condition_layer != null and _condition_layer.visible:
			get_viewport().set_input_as_handled()
			_close_condition()
		elif not sailing and not voyage_started and not event_panel.visible and back_button != null and not back_button.disabled:
			get_viewport().set_input_as_handled()
			_on_back_to_port()
	elif k.keycode == KEY_C:
		get_viewport().set_input_as_handled()
		_toggle_condition()


# ── 出港验引那句（lane w54-tutorial）──────────────────
## 港页「看风」过了验引当帧就换海图（Main._on_set_sail），验引那一句原先记在港页记事栏、随港页一起换掉：新开一局头一日市舶司
## 不在三扇门里，头一回出海多半无引塞钱、蒲家留意涨二十，屏上一个字也没有，塞到第四回整舱充公才头一回见到验引的话。
## Main 放行时把那句交给 GameManager.depart_note，这里先记它、再记起锚那句（札记照先后，新的在上），顶匾第二行先报验引那句；
## 读完即清，不留到下一回开海图
func _log_departure() -> void:
	var note := str(GameManager.depart_note)
	GameManager.depart_note = ""
	if note != "":
		_log(note)
	_log("自 %s 起锚。%s。" % [GameManager.get_port_name(origin_port), Calendar.get_monsoon_desc()])
	if note != "":
		_latest_note = _plain_note(note)
		_refresh_strip()


## lane w54-seaevents：海图上「扬帆逃走」没甩脱（_on_flee_pirates，海寇与元军哨船两面共用）那一句。原先只写「未能甩脱。被追上跳帮，
## 货舱被夺。」加被抢清单——旗舰挨的那一下（damage_fleet 30 × 甲档减伤）一字不提，舱里空着一件没抢也说货舱被夺。
## 现写：有货被抢照旧句加清单，舱里空着写没什么可抢；旗舰船体实扣了几（扣到 0 为止）写「船体受损 N」，一点没扣着不写
func _flee_fail_note(lost_str: String, hull_cut: float) -> String:
	var s := _CombatFx.sea_flee_fail_note(lost_str) if lost_str != "" else "未能甩脱。被追上跳帮，舱里空着，没什么可抢。"
	if int(hull_cut) > 0:
		s += "船体受损 %d。" % int(hull_cut)
	return s


	_tutorial_chart()


# ── 新手上手小笺（lane w54-tutorial，scripts/ui/TutorialNotes.gd；只给本机没有存档时新开的一局，开关 tutorial_notes）──
const _Tutorial := preload("res://scripts/ui/TutorialNotes.gd")


## 开海图（_log_departure 末尾）：出「看风」；发了舶还没轮到的撤下
func _tutorial_chart() -> void:
	_Tutorial.offer(self, "chart", func() -> bool: return not sailing)


## 海上遇盗（_show_event 海盗那一支）：先让路——这一页别的新手小笺收起 / 撤下——再排「遇盗」，随事件面板走：
## 选了怎么办（面板收起，开打、逃、给钱都算）就撤，不压到海战的小笺上
func _tutorial_pirate() -> void:
	if not _Tutorial.want("pirate"):
		return
	_Tutorial.clear_others(self, "pirate")
	_Tutorial.offer(self, "pirate", func() -> bool:
		return event_panel.visible and int(pending_event.get("kind", -1)) == Voyage.EventKind.PIRATE, true)


## 没发舶就回港（_return_unsailed）：「看风」放行那一下 Main 已 consume_permit（一引一航次），可这一趟没走——这回出港用的是货引就还回去，
## 报过的舱货（permit_base，补抽解补到哪儿）照旧，再出港不另请领、只按添的货补抽解。无引塞钱那一路钱与蒲家留意已给了小吏，不退
func _keep_unused_permit() -> void:
	if GameManager.depart_permit:
		GameState.has_customs_permit = true
	GameManager.depart_permit = false
