extends Control
## 人物志（characters 线）：全部人物的名册网格 + 单人详页。港口页底「人物志」、标题页「人物志」都能进。
## 一层盖在 Main 上的浮页：Esc / 返回键 / 鼠标后退键先退一页（详页 → 上一个详页 → 名册），名册页再按就合上。
## 不入存档：筛选页签只记在本会话（static），「已识」由 CharacterArt.is_known() 从现有状态推得。
## 用法（Main）：var cx := CharacterCodex.new(); add_child(cx); cx.begin(focus_id)。focus_id 非空直接开此人详页。

signal closed

const Art := preload("res://scripts/ui/CharacterArt.gd")

## 名册一格：画 104×130（立绘 4:5），九列；1280 宽里扣掉浮页边距与滚动条正好排下
const CELL_PIC := Vector2i(104, 130)
const COLS := 9
const DETAIL_PIC := Vector2i(256, 320)
const HEAD_PIC := Vector2i(34, 34)
## 名册分组：[键, 页签名, 含哪些 tier]
const GROUPS := [
	["major", "主角・要人", ["protagonist", "major"]],
	["crew", "职事", ["crew"]],
	["minor", "市井", ["minor"]],
	["historical", "史实", ["historical"]],
]
## 每帧补缩略图的时间预算（微秒）：75 张分十来帧补完，打开时不卡一下
const THUMB_BUDGET_US := 6000

## 上次看的页签（本会话）
static var last_filter := "all"

var _sheet: PanelContainer
var _header_right: HBoxContainer
var _count_lbl: Label
var _page_host: Control
var _page: Control
var _tabs: Dictionary = {}
var _order: Array = []
var _pending: Array = []
var _current := ""
var _history: Array = []
var _closing := false
var _live := true


func _init() -> void:
	name = "CharacterCodex"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_live = DisplayServer.get_name() != "headless"


func begin(focus_id := "") -> void:
	_build_frame()
	if focus_id != "" and not GameManager.get_character(focus_id).is_empty():
		show_detail(focus_id, false)
	else:
		show_grid()
	if _live:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)


## 名册页当前还在补的缩略图张数（巡检等它补完再截）
func pending_thumbs() -> int:
	return _pending.size()


func current_id() -> String:
	return _current


# ── 框 ─────────────────────────────────────────────

func _build_frame() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.024, 0.018, 0.82) if UiTheme.IS_JUANBEN else Color(UiTheme.DIM, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_sheet = PanelContainer.new()
	_sheet.name = "CodexSheet"
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 顶边贴到状态匾上缘（y=8）之上，状态匾的字不再从浮页上缘露出来
	_sheet.offset_left = 26
	_sheet.offset_top = 6
	_sheet.offset_right = -26
	_sheet.offset_bottom = -12
	_sheet.add_theme_stylebox_override("panel", UiTheme.panel())
	add_child(_sheet)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	_sheet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := Art.label("人物志", 38, UiTheme.GOLD_HI, true)
	title.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var seal_path := "res://assets/ui/nk1/seal_lizhi_zhu.png"
	if UiTheme.IS_JUANBEN and ResourceLoader.exists(seal_path):
		var seal := TextureRect.new()
		seal.texture = load(seal_path)
		seal.custom_minimum_size = Vector2(22, 36)
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seal.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(seal)
	_count_lbl = Art.label("", UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM)
	_count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	_header_right = HBoxContainer.new()
	_header_right.add_theme_constant_override("separation", 6)
	_header_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_header_right)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "合上"
	close.custom_minimum_size = Vector2(112, 40)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_codex)
	UiTheme.style_button(close, true)
	head.add_child(close)

	col.add_child(_gold_band())

	_page_host = Control.new()
	_page_host.name = "PageHost"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_page_host)
	_refresh_count()


## 页眉下一道回纹泥金带（绢本）；夜潮是一道潮光细线。
func _gold_band() -> Control:
	var path := "res://assets/theme/tex/band_huiwen_gold.res"
	if UiTheme.IS_JUANBEN and ResourceLoader.exists(path):
		var band := PanelContainer.new()
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.custom_minimum_size = Vector2(0, 12)
		var st := StyleBoxTexture.new()
		st.texture = load(path)
		st.texture_margin_left = 8
		st.texture_margin_right = 8
		st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		st.modulate_color = Color(1, 1, 1, 0.55)
		band.add_theme_stylebox_override("panel", st)
		return band
	return Art.rule(0.5)


func _refresh_count() -> void:
	var all: Array = GameManager.all_characters()
	var known := 0
	for ch in all:
		if Art.is_known(ch):
			known += 1
	_count_lbl.text = "已识 %d / %d" % [known, all.size()]


## 换页。旧页上还没补的缩略图作废（新页建的时候已经把自己的排进 _pending，这里只剔掉旧页的）。
func _swap_page(page: Control) -> void:
	if _page != null and is_instance_valid(_page):
		var fresh: Array = []
		for job in _pending:
			if is_instance_valid(job[0]) and page.is_ancestor_of(job[0]):
				fresh.append(job)
		_pending = fresh
		_page_host.remove_child(_page)
		_page.queue_free()
	_page = page
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_host.add_child(page)
	if _live:
		page.modulate.a = 0.0
		create_tween().tween_property(page, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE)


func _clear_header_right() -> void:
	for c in _header_right.get_children():
		_header_right.remove_child(c)
		c.queue_free()
	_tabs.clear()


func _small_button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 34)
	b.pressed.connect(cb)
	UiTheme.style_button(b, false)
	b.add_theme_font_size_override("font_size", UiTheme.SIZE_FOOT + 1)
	return b


# ── 名册 ─────────────────────────────────────────────

func _members(filter: String) -> Array:
	var out: Array = []
	for g in GROUPS:
		if filter != "all" and filter != str(g[0]):
			continue
		for ch in GameManager.all_characters():
			if str(ch.get("tier", "")) in g[2]:
				out.append(ch)
	return out


func show_grid() -> void:
	_current = ""
	_history.clear()
	_clear_header_right()
	var tabs: Array = [["all", "全部"]]
	for g in GROUPS:
		tabs.append([g[0], g[1]])
	for t in tabs:
		var key := str(t[0])
		var b := _small_button(str(t[1]), _on_tab.bind(key), 0.0)
		b.toggle_mode = true
		b.button_pressed = key == last_filter
		_style_tab(b, key == last_filter)
		_header_right.add_child(b)
		_tabs[key] = b
	_swap_page(_build_grid(last_filter))


func _style_tab(b: Button, on: bool) -> void:
	# 选中的页签：泥金字 + 泥金底线，像名册上夹了一条签
	b.add_theme_color_override("font_color", UiTheme.GOLD_HI if on else UiTheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UiTheme.GOLD_HI)
	if on:
		var st := StyleBoxFlat.new()
		st.bg_color = Color(UiTheme.GOLD, 0.16)
		st.border_color = UiTheme.GOLD_HI if UiTheme.IS_JUANBEN else UiTheme.TIDE
		st.border_width_bottom = 2
		st.content_margin_left = 14
		st.content_margin_right = 14
		st.content_margin_top = 5
		st.content_margin_bottom = 5
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("pressed", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_stylebox_override("hover_pressed", st)


func _on_tab(key: String) -> void:
	last_filter = key
	show_grid()


func _build_grid(filter: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_order.clear()
	if GameManager.all_characters().is_empty():
		list.add_child(Art.label("人物设定集未载入。", UiTheme.SIZE_BODY, UiTheme.TEXT_DIM))
		return scroll
	for g in GROUPS:
		if filter != "all" and filter != str(g[0]):
			continue
		var members: Array = []
		for ch in GameManager.all_characters():
			if str(ch.get("tier", "")) in g[2]:
				members.append(ch)
		if members.is_empty():
			continue
		var known := 0
		for ch in members:
			if Art.is_known(ch):
				known += 1
		var sec := HBoxContainer.new()
		sec.add_theme_constant_override("separation", 10)
		sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sl := Art.label(str(g[1]), 24, UiTheme.GOLD, true)
		sec.add_child(sl)
		var sc := Art.label("%d / %d" % [known, members.size()], UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
		sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sec.add_child(sc)
		var line := Art.rule(0.30)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sec.add_child(line)
		list.add_child(sec)
		var grid := GridContainer.new()
		grid.columns = COLS
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.size_flags_horizontal = Control.SIZE_FILL
		list.add_child(grid)
		for ch in members:
			_order.append(str(ch.get("id", "")))
			grid.add_child(_make_cell(ch))
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 8)
	list.add_child(tail)
	# 末排立绘原先被视口底边一刀截断：底边 28px 渐隐（第 2 轮美术 M3）
	return UiTheme.fade_scroll(scroll, 28)


func _make_cell(ch: Dictionary) -> Button:
	var id := str(ch.get("id", ""))
	var known := Art.is_known(ch)
	var cell := Button.new()
	cell.name = "Cell_" + id
	cell.custom_minimum_size = Vector2(CELL_PIC.x + 12, CELL_PIC.y + 60)
	cell.focus_mode = Control.FOCUS_ALL
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		cell.add_theme_stylebox_override(s, empty)
	cell.pressed.connect(show_detail.bind(id, false))

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(v)
	var mat := PanelContainer.new()
	mat.name = "Mat"
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mat.add_theme_stylebox_override("panel", Art.mat_style(false))
	v.add_child(mat)
	var name_lbl: Label
	if known:
		var pic := Art.picture(null, Vector2(CELL_PIC))
		pic.name = "Pic"
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(CELL_PIC)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(pic)
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		# 阵营色一道绢带压在画脚
		var fd := Art.faction_def(str(ch.get("faction", "")))
		var band := ColorRect.new()
		band.color = Color.from_string(str(fd.get("color", "#54585c")), Color(0.33, 0.35, 0.36))
		band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		band.offset_top = -4
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(band)
		mat.add_child(stack)
		_queue_thumb(pic, ch)
		name_lbl = Art.label(Art.display_name(ch), 19, UiTheme.TEXT, true)
	else:
		# 未识：此人的画像压到一成半的墨影，角上钤一方「未识」——比一方「？」安静，也看得出格里有个人
		var dark := Art.picture(null, Vector2(CELL_PIC))
		dark.name = "Pic"
		dark.modulate = Color(0.13, 0.115, 0.10)
		var dstack := Control.new()
		dstack.custom_minimum_size = Vector2(CELL_PIC)
		dstack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dstack.clip_contents = true
		dstack.add_child(dark)
		dark.set_anchors_preset(Control.PRESET_FULL_RECT)
		var seal := Art.stamp("未识", 34.0)
		seal.position = Vector2(CELL_PIC.x - 40, CELL_PIC.y - 42)
		seal.modulate = Color(1, 1, 1, 0.82)
		dstack.add_child(seal)
		mat.add_child(dstack)
		_queue_thumb(dark, ch)
		name_lbl = Art.label("未识", 17, UiTheme.TEXT_DIM)
	name_lbl.name = "Name"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.custom_minimum_size.x = CELL_PIC.x + 12
	v.add_child(name_lbl)
	var title := Art.codex_title(ch)
	var role := Art.label(title if title != "" else "未详", UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	role.custom_minimum_size.x = CELL_PIC.x + 12
	v.add_child(role)
	if known:
		cell.tooltip_text = "%s　%s" % [Art.display_name(ch), Art.identity_line(ch)]
	var base_name := name_lbl.get_theme_color("font_color")
	var hot := func(on: bool) -> void:
		mat.add_theme_stylebox_override("panel", Art.mat_style(false, on))
		# 悬停：画像提亮一成，像灯移到了这一幅前面
		mat.modulate = Color(1.12, 1.09, 1.04) if on else Color.WHITE
		name_lbl.add_theme_color_override("font_color", UiTheme.GOLD_HI if on else base_name)
	cell.mouse_entered.connect(hot.bind(true))
	cell.mouse_exited.connect(func() -> void:
		if not cell.has_focus():
			hot.call(false))
	cell.focus_entered.connect(hot.bind(true))
	cell.focus_exited.connect(hot.bind(false))
	return cell


func _queue_thumb(pic: TextureRect, ch: Dictionary, logical := CELL_PIC, head := false) -> void:
	var have := Art.cached_thumb(ch, logical, head)
	if have != null or not _live:
		pic.texture = have if have != null else Art.thumb(ch, logical, head)
		return
	Art.request_portrait(ch)
	_pending.append([pic, ch, logical, head])


## 后台读好的立绘按名册顺序在主线程缩好补上，每帧不超过 THUMB_BUDGET_US；每张补上时淡入。
func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < _pending.size():
		var job: Array = _pending[i]
		if not is_instance_valid(job[0]):
			_pending.remove_at(i)
			continue
		if not Art.portrait_ready(job[1]):
			i += 1
			continue
		_pending.remove_at(i)
		var pic := job[0] as TextureRect
		pic.texture = Art.thumb(job[1], job[2], job[3])
		pic.modulate.a = 0.0
		create_tween().tween_property(pic, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
		if Time.get_ticks_usec() - t0 > THUMB_BUDGET_US:
			break


# ── 详页 ─────────────────────────────────────────────

func show_detail(id: String, push := true) -> void:
	var ch: Dictionary = GameManager.get_character(id)
	if ch.is_empty():
		return
	if push and _current != "" and _current != id:
		_history.append(_current)
	if _order.is_empty():
		for m in _members(last_filter):
			_order.append(str(m.get("id", "")))
	_current = id
	_clear_header_right()
	_header_right.add_child(_small_button("返回名册", show_grid, 108))
	var prev := _small_button("上一位", _step.bind(-1), 88)
	var next := _small_button("下一位", _step.bind(1), 88)
	prev.disabled = _order.find(id) <= 0
	next.disabled = _order.find(id) < 0 or _order.find(id) >= _order.size() - 1
	_header_right.add_child(prev)
	_header_right.add_child(next)
	_swap_page(_build_detail(ch))


func _step(d: int) -> void:
	var i := _order.find(_current)
	if i < 0:
		return
	var j := clampi(i + d, 0, _order.size() - 1)
	if j != i:
		_history.clear()
		show_detail(str(_order[j]), false)


func _build_detail(ch: Dictionary) -> Control:
	var known := Art.is_known(ch)
	var page := HBoxContainer.new()
	page.name = "Detail"
	page.add_theme_constant_override("separation", 26)

	# 左：大立绘 + 阵营签
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size.x = 300
	page.add_child(left)
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pic := Art.picture(Art.thumb(ch, DETAIL_PIC), Vector2(DETAIL_PIC))
	frame.add_child(pic)
	if not UiTheme.frame_portrait(frame, pic):
		frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	if not known:
		# 未识：画像先糊掉（约 12px 高斯）再压成一成半的墨影——只压暗时铠甲、脸还认得出，等于提前露脸（第 2 轮美术 minor 9）
		var soft := Art.blurred(pic.texture, 12.0)
		if soft != null:
			pic.texture = soft
		pic.modulate = Color(0.13, 0.115, 0.10)
	var plate := frame.get_node_or_null("NamePlate/Name") as Label
	if plate != null:
		plate.text = Art.display_name(ch) if known else "未识"
		plate.add_theme_font_override("font", Art.title_font_for(plate.text))
	left.add_child(frame)
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 8)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tags)
	if known:
		tags.add_child(Art.faction_chip(ch))
	var tier_l := Art.label(str(Art.TIER_NAME.get(str(ch.get("tier", "")), "")), UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	tier_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tags.add_child(tier_l)
	if known:
		var appear := Art.label(Art.appear_line(ch), UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
		appear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(appear)

	# 右：可滚动的传记（底边渐隐，长传记不被一刀切断）
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var faded := UiTheme.fade_scroll(scroll, 24)
	faded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(faded)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	if known:
		_fill_known(body, ch)
	else:
		_fill_unknown(body, ch)
	return page


func _name_row(body: VBoxContainer, name_text: String, courtesy: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Art.label(name_text, 40, color, true)
	n.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	n.add_theme_constant_override("outline_size", 4)
	row.add_child(n)
	if courtesy != "":
		var c := Art.label(courtesy, UiTheme.SIZE_FOOT + 2, UiTheme.TEXT_DIM)
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		c.add_theme_constant_override("line_spacing", 0)
		row.add_child(c)
	body.add_child(row)
	return row


func _section(body: VBoxContainer, title: String) -> void:
	var l := Art.label(title, 20, UiTheme.GOLD, true)
	body.add_child(l)


func _para(text: String, px: int, color: Color) -> Label:
	var l := Art.label(text, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_constant_override("line_spacing", 5)
	return l


func _fill_known(body: VBoxContainer, ch: Dictionary) -> void:
	_name_row(body, Art.display_name(ch), Art.courtesy_of(ch), UiTheme.GOLD_HI)
	var ident := Art.identity_line(ch)
	var life := Art.life_line(ch)
	if life != "":
		ident = "%s　%s" % [ident, life] if ident != "" else life
	body.add_child(_para(ident, UiTheme.SIZE_BODY - 1, UiTheme.TEXT))
	var alts := Art.codex_alts(ch)
	if not alts.is_empty():
		body.add_child(_para("又称　" + "、".join(alts), UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM))
	body.add_child(Art.rule(0.40))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 30)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stats)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	stats.add_child(left)
	_section(left, "五维")
	left.add_child(Art.attr_block(ch, 176.0, 16))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(right)
	_section(right, "特技")
	var traits := Art.traits_of(ch)
	if traits.is_empty():
		right.add_child(_para("无专长可记。", UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM))
	for t in traits:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 10)
		trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge := Art.trait_badge(str(t), 17)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		trow.add_child(badge)
		trow.add_child(_para(str(Art.trait_def(str(t)).get("desc", "")), UiTheme.SIZE_FOOT + 1, UiTheme.TEXT))
		right.add_child(trow)
	var per := str(ch.get("personality", ""))
	if per != "":
		right.add_child(Control.new())
		_section(right, "性情")
		right.add_child(_para(per, UiTheme.SIZE_FOOT + 1, UiTheme.TEXT))

	body.add_child(Art.rule(0.40))
	_section(body, "小传")
	# 上屏文本层（characters_codex.json）按年份 / 进度取可见段；设定集原稿 bio 不上屏
	var bio := Art.codex_bio(ch)
	if Art.codex_bio_pending(ch):
		bio += ("" if bio == "" else "\n") + "此后之事，尚在将来。"
	body.add_child(_para(bio, UiTheme.SIZE_BODY - 1, UiTheme.TEXT))

	var lines := Art.codex_lines(ch)
	if not lines.is_empty():
		_section(body, "其言")
		for ln in lines:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tick := ColorRect.new()
			tick.color = Color(UiTheme.GOLD, 0.75)
			tick.custom_minimum_size = Vector2(2, 0)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tick)
			row.add_child(_para("「%s」" % str(ln), UiTheme.SIZE_BODY - 1, UiTheme.GOLD_HI))
			body.add_child(row)

	var look := Art.codex_look(ch)
	if look != "":
		_section(body, "形貌")
		body.add_child(_para(look, UiTheme.SIZE_FOOT + 1, UiTheme.TEXT_DIM))

	var rels = ch.get("relations", [])
	if typeof(rels) == TYPE_ARRAY and not (rels as Array).is_empty():
		var flow: HFlowContainer = null
		for r in rels:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var other: Dictionary = GameManager.get_character(str(r.get("id", "")))
			var rel := str(r.get("rel", ""))
			if other.is_empty() or not _rel_visible(rel, other):
				continue
			if flow == null:
				_section(body, "关系")
				flow = HFlowContainer.new()
				flow.add_theme_constant_override("h_separation", 8)
				flow.add_theme_constant_override("v_separation", 8)
				flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.add_child(flow)
			flow.add_child(_relation_chip(other, rel))
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(0, 6)
	body.add_child(tail)


## 关系签也会透底：「旧识叛将」「恩主亦仇」「车裂之俘」「庙前殉节者」这类签，终局了结前不露；
## 对方本人还没到能认识的年份（未出生、未登场）的也先不露。
const REL_SPOILER := ["叛", "降", "仇", "杀", "诛", "殉", "车裂", "俘", "扣押", "扣留", "城破", "决裂", "所负"]


func _rel_visible(rel: String, other: Dictionary) -> bool:
	if GameState.is_ended():
		return true
	if not Art.rel_visible(rel):
		return false
	for w in REL_SPOILER:
		if rel.find(w) >= 0:
			return false
	var born = other.get("born")
	if born != null and Calendar.year < int(born):
		return false
	return true


func _fill_unknown(body: VBoxContainer, ch: Dictionary) -> void:
	var nrow := _name_row(body, "未识之人", "", UiTheme.TEXT_DIM)
	nrow.add_child(Art.stamp("待访", 50.0))
	var title := Art.codex_title(ch)
	body.add_child(_para(title if title != "" else "来历未详", UiTheme.SIZE_BODY, UiTheme.TEXT))
	body.add_child(Art.rule(0.40))
	var hint := "其人其事，尚未传到你耳中。"
	var port := Art.hire_port_name(ch)
	if Art.crew_id_of(ch) != "":
		hint = "雇过此人，册上才有其详。" + ("据牙人说，在%s一带候雇。" % port if port != "" else "")
	body.add_child(_para(hint, UiTheme.SIZE_BODY - 1, UiTheme.TEXT_DIM))
	# 已识之人的关系表里提到过此人：名字不露，点过去看那位已识的人。
	# 签上写「此人之于那位」：优先取此人自己关系表里指向那位的一条（陈瓒表里「族侄」→ 陈子龙　族侄，
	# 与已识页的读法一致）；此人表里没有，才把那位表里的一条改写成「此人为其族叔」——
	# 旧写法「陈子龙　为其族叔」读作陈子龙是族叔，主客颠倒。带结局的签（叛、降、仇……）终局前不露。
	var uid := str(ch.get("id", ""))
	var own := {}
	var own_rels = ch.get("relations", [])
	if typeof(own_rels) == TYPE_ARRAY:
		for r in own_rels:
			if typeof(r) == TYPE_DICTIONARY:
				own[str(r.get("id", ""))] = str(r.get("rel", ""))
	var flow: HFlowContainer = null
	for other in GameManager.all_characters():
		if not Art.is_known(other):
			continue
		var rels = other.get("relations", [])
		if typeof(rels) != TYPE_ARRAY:
			continue
		for r in rels:
			if typeof(r) != TYPE_DICTIONARY or str(r.get("id", "")) != uid:
				continue
			var oid := str(other.get("id", ""))
			var label := str(own.get(oid, ""))
			var raw := label if label != "" else str(r.get("rel", ""))
			if not _rel_visible(raw, other):
				continue
			if label == "":
				label = "此人为其%s" % raw
			if flow == null:
				body.add_child(Control.new())
				_section(body, "旁人提起")
				flow = HFlowContainer.new()
				flow.add_theme_constant_override("h_separation", 8)
				flow.add_theme_constant_override("v_separation", 8)
				flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.add_child(flow)
			flow.add_child(_relation_chip(other, label))
	# 右栏下面一方淡墨大水印「未识」，页面不再空落落的
	var mark := Art.label("未识", 132, Color(UiTheme.GOLD, 0.07), true)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mark)


func _relation_chip(other: Dictionary, rel: String) -> Control:
	var oid := str(other.get("id", ""))
	var known := Art.is_known(other)
	var chip := PanelContainer.new()
	chip.name = "Rel_" + oid
	var calm := _chip_box(false)
	chip.add_theme_stylebox_override("panel", calm)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(h)
	var mat := PanelContainer.new()
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ms := Art.mat_style(false)
	ms.set_content_margin_all(1)
	mat.add_theme_stylebox_override("panel", ms)
	if known:
		var head_pic := Art.picture(null, Vector2(HEAD_PIC))
		mat.add_child(head_pic)
		_queue_thumb(head_pic, other, HEAD_PIC, true)
	else:
		mat.add_child(Art.unknown_face(Vector2(HEAD_PIC), 20))
	mat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(mat)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var nm := Art.label(Art.display_name(other) if known else "未识", 16, UiTheme.TEXT if known else UiTheme.TEXT_DIM)
	v.add_child(nm)
	v.add_child(Art.label(rel, UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM))
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		hit.add_theme_stylebox_override(s, empty)
	hit.tooltip_text = "%s　%s" % [rel, Art.display_name(other) if known else str(other.get("title", ""))]
	hit.pressed.connect(show_detail.bind(oid, true))
	var lit := func(on: bool) -> void:
		chip.add_theme_stylebox_override("panel", _chip_box(on))
		nm.add_theme_color_override("font_color", UiTheme.GOLD_HI if on else (UiTheme.TEXT if known else UiTheme.TEXT_DIM))
	hit.mouse_entered.connect(lit.bind(true))
	hit.mouse_exited.connect(lit.bind(false))
	hit.focus_entered.connect(lit.bind(true))
	hit.focus_exited.connect(lit.bind(false))
	chip.add_child(hit)
	return chip


func _chip_box(hot: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = UiTheme.BTN_HI if hot else Color(UiTheme.BTN, 0.92)
	st.border_color = Color(UiTheme.GOLD_HI, 0.9) if hot else Color(UiTheme.GOLD if UiTheme.IS_JUANBEN else UiTheme.TIDE, 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.corner_detail = 1
	st.content_margin_left = 5
	st.content_margin_right = 12
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	return st


# ── 退与合 ─────────────────────────────────────────────

## 退一页：详页先回上一个详页（点关系跳过来的），再回名册；名册页就合上。
func go_back() -> void:
	if _current != "":
		if not _history.is_empty():
			show_detail(str(_history.pop_back()), false)
		else:
			show_grid()
		return
	close_codex()


func close_codex() -> void:
	if _closing:
		return
	_closing = true
	_pending.clear()
	closed.emit()
	if not _live or not is_inside_tree():
		queue_free()
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close_codex()


func _gui_input(event: InputEvent) -> void:
	_mouse_back(event)


func _mouse_back(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
			return true
	return false


## 浮页开着时吃掉所有按键：Esc / 返回键退一页，左右键在详页翻人，其余不漏给底下的 Main（回车不会误点底下的选项）。
func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if _mouse_back(event):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_BACK):
		go_back()
	elif _current != "" and event.is_action_pressed("ui_left"):
		_step(-1)
	elif _current != "" and event.is_action_pressed("ui_right"):
		_step(1)
	elif _current == "" and _page != null and get_viewport().gui_get_focus_owner() == null:
		# 名册页首次按方向键：焦点落到第一格，之后方向键在格间走
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			var first := _page.find_child("Cell_*", true, false) as Control
			if first != null:
				first.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree() and not _closing:
		go_back()
