class_name UiTheme
extends RefCounted
## 「夜潮」：深青底、潮光线、珊瑚主钮。面板不透底图。
## 调用点仍写 GOLD，颜色已是潮光，不再是泥金。
## class_name 全局可解析，不占 autoload。

const INK := Color(0.055, 0.141, 0.200, 0.96)       # 夜潮面板
const INK_SOFT := Color(0.086, 0.188, 0.267, 0.98)  # 港卡，几乎不透
const TIDE := Color(0.243, 0.878, 0.773)            # 潮光
const GOLD := TIDE
const TEXT := Color(0.949, 0.984, 0.988)            # 壳白正文
const TEXT_DIM := Color(0.608, 0.722, 0.769)        # 旁注
const SEAL := Color(1.0, 0.420, 0.290)              # 珊瑚主钮
const SEAL_HI := Color(1.0, 0.541, 0.431)
const MOSS := Color(0.490, 0.871, 0.541)            # 顺风 / 已办
const HONEY := Color(0.941, 0.757, 0.290)           # 紧缺 / 欠账
const CINNABAR := Color(1.0, 0.561, 0.478)          # 告警字
const VEIL := Color(0.02, 0.05, 0.09, 0.55)         # 压暗照片，字才站得住
const BTN := Color(0.10, 0.22, 0.31, 0.98)
const BTN_HI := Color(0.15, 0.32, 0.42, 1.0)
const BTN_DOWN := Color(0.06, 0.14, 0.20, 1.0)
const INK_SOLID := Color(0.055, 0.141, 0.200, 1.0)

# 字阶从 Main.tscn 实测收口。标题页大题仍可单独加大。
const SIZE_PORT := 32
const SIZE_HEAD := 28
const SIZE_CARD := 22
const SIZE_BODY := 18
const SIZE_FOOT := 13
const LINE_BODY := 6

const _FONT_NAMES: PackedStringArray = [
	"WenQuanYi Micro Hei",
	"Noto Sans CJK SC",
	"Source Han Sans SC",
	"Droid Sans Fallback",
	"Songti SC",
	"STSong",
	"Noto Serif CJK SC",
	"Source Han Serif SC",
	"KaiTi",
	"SimSun",
]

static var _font: Font
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = _FONT_NAMES
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		_font = f
	return _font


static func hex(c: Color) -> String:
	return c.to_html(false)


## 挂到场景根上。缺的项继续落到引擎默认主题，这里只锁字体、钮和分隔线。
static func apply(node: Control) -> void:
	node.theme = theme()


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := font()
	t.default_font = f
	t.default_font_size = SIZE_BODY

	t.set_font("font", "Label", f)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_color("font_color", "Label", TEXT)

	t.set_font("font", "Button", f)
	t.set_font_size("font_size", "Button", SIZE_BODY)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_focus_color", "Button", TEXT)
	var ink_n := _button_box(BTN, Color(TIDE, 0.35))
	var ink_h := _button_box(BTN_HI, Color(TIDE, 0.85))
	var ink_p := _button_box(BTN_DOWN, Color(TIDE, 0.45))
	var ink_d := _button_box(Color(BTN_DOWN, 0.55), Color(TIDE, 0.12))
	t.set_stylebox("normal", "Button", ink_n)
	t.set_stylebox("hover", "Button", ink_h)
	t.set_stylebox("pressed", "Button", ink_p)
	t.set_stylebox("disabled", "Button", ink_d)
	t.set_stylebox("focus", "Button", ink_h)

	t.set_font("normal_font", "RichTextLabel", f)
	t.set_font("bold_font", "RichTextLabel", f)
	t.set_font("italics_font", "RichTextLabel", f)
	t.set_font("bold_italics_font", "RichTextLabel", f)
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", LINE_BODY)

	var rule := StyleBoxLine.new()
	rule.color = Color(GOLD, 0.40)
	rule.thickness = 1
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_stylebox("separator", "VSeparator", rule)

	var track := _flat(Color(0.03, 0.08, 0.12, 0.55), Color(0, 0, 0, 0), 2, 0)
	var grab := _flat(Color(TIDE, 0.85), Color(0, 0, 0, 0), 2, 0)
	var grab_hi := _flat(TIDE, Color(0, 0, 0, 0), 2, 0)
	# 空边距的 StyleBox 会把滚动条压成 0 宽，滚轮能动、条却看不见。
	for st in [track, grab, grab_hi]:
		st.content_margin_left = 4
		st.content_margin_right = 4
		st.content_margin_top = 6
		st.content_margin_bottom = 6
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", kind, track)
		t.set_stylebox("grabber", kind, grab)
		t.set_stylebox("grabber_highlight", kind, grab_hi)
		t.set_stylebox("grabber_pressed", kind, grab_hi)

	var pop := panel()
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_font("font", "PopupMenu", f)
	t.set_font_size("font_size", "PopupMenu", SIZE_FOOT)
	t.set_stylebox("hover", "PopupMenu", _flat(Color(TIDE, 0.22), Color(0, 0, 0, 0), 2, 0))

	t.set_stylebox("panel", "AcceptDialog", panel())
	t.set_color("title_color", "AcceptDialog", GOLD)
	t.set_font("title_font", "AcceptDialog", f)

	_theme = t
	return t


static func _flat(bg: Color, border: Color, radius: int, bw := 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.border_width_left = bw
	st.border_width_top = bw
	st.border_width_right = bw
	st.border_width_bottom = bw
	st.corner_radius_top_left = radius
	st.corner_radius_top_right = radius
	st.corner_radius_bottom_left = radius
	st.corner_radius_bottom_right = radius
	return st


## 夜潮面板：潮光细边，从画上浮起来，底图不再透进字里。
static func panel() -> StyleBoxFlat:
	var st := _flat(INK, Color(TIDE, 0.55), 2)
	st.shadow_color = Color(0, 0, 0, 0.40)
	st.shadow_size = 8
	st.shadow_offset = Vector2(0, 3)
	return st


## 港名匾、卷首不用大圆角。
static func plaque() -> StyleBoxFlat:
	var st := _flat(Color(0.04, 0.12, 0.18, 0.94), Color(TIDE, 0.90), 2, 1)
	st.border_width_top = 2
	st.border_width_bottom = 2
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 10
	st.shadow_offset = Vector2(0, 4)
	return st


static func icon_frame() -> StyleBoxFlat:
	var st := _flat(Color(0.04, 0.10, 0.15, 1.0), Color(TIDE, 0.72), 2, 1)
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	return st


static func log_well() -> StyleBoxFlat:
	var st := _flat(Color(0.03, 0.08, 0.12, 0.78), Color(TIDE, 0.28), 2, 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st


static func card() -> StyleBoxFlat:
	var st := _flat(INK_SOFT, Color(TIDE, 0.90), 16, 0)
	st.border_width_left = 3
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


static func card_hover() -> StyleBoxFlat:
	var st := _flat(BTN_HI, Color(TIDE, 1.0), 16, 0)
	st.border_width_left = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


## 航向牌。未选中暗边，选中潮光边。半径与港卡同为 16。
static func heading_card(selected: bool) -> StyleBoxFlat:
	var edge := TIDE if selected else BTN
	var st := _flat(INK, edge, 16, 2 if selected else 1)
	st.content_margin_left = 14
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var st := _flat(bg, border, 2)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 7
	st.content_margin_bottom = 7
	return st


static func _paint_font(ctrl: Control) -> void:
	ctrl.add_theme_font_override("font", font())


## 四态按钮。accent=珊瑚主钮（升帆 / 开局），其余夜潮。
static func style_button(btn: Button, accent := false) -> void:
	_paint_font(btn)
	if accent:
		btn.add_theme_stylebox_override("normal", _button_box(SEAL, Color(1, 0.78, 0.70, 0.45)))
		btn.add_theme_stylebox_override("hover", _button_box(SEAL_HI, Color(1, 0.86, 0.80, 0.70)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(1.0, 0.376, 0.251), Color(1, 0.70, 0.60, 0.40)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.35, 0.18, 0.16, 0.55), Color(TIDE, 0.12)))
		btn.add_theme_stylebox_override("focus", _button_box(SEAL_HI, Color(TIDE, 0.7)))
		btn.add_theme_color_override("font_color", INK_SOLID)
		btn.add_theme_color_override("font_hover_color", INK_SOLID)
		btn.add_theme_color_override("font_pressed_color", INK_SOLID)
		btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	else:
		btn.add_theme_stylebox_override("normal", _button_box(BTN, Color(TIDE, 0.35)))
		btn.add_theme_stylebox_override("hover", _button_box(BTN_HI, Color(TIDE, 0.85)))
		btn.add_theme_stylebox_override("pressed", _button_box(BTN_DOWN, Color(TIDE, 0.45)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(BTN_DOWN, 0.55), Color(TIDE, 0.12)))
		btn.add_theme_stylebox_override("focus", _button_box(BTN_HI, Color(TIDE, 0.85)))
		btn.add_theme_color_override("font_color", TEXT)
		btn.add_theme_color_override("font_hover_color", TEXT)
		btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 牙行价目上的小钮，不能用正文钮的大内边距，否则一行排不下。
static func style_chip(btn: Button, accent := false) -> void:
	_paint_font(btn)
	var bg := SEAL if accent else BTN
	var hi := SEAL_HI if accent else BTN_HI
	var border := Color(1, 0.78, 0.70, 0.45) if accent else Color(TIDE, 0.40)
	var mk := func(c: Color) -> StyleBoxFlat:
		var st := _flat(c, border, 2, 1)
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		return st
	btn.add_theme_stylebox_override("normal", mk.call(bg))
	btn.add_theme_stylebox_override("hover", mk.call(hi))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(1.0, 0.376, 0.251) if accent else BTN_DOWN))
	btn.add_theme_stylebox_override("disabled", mk.call(Color(BTN_DOWN, 0.45)))
	btn.add_theme_stylebox_override("focus", mk.call(hi))
	btn.add_theme_font_size_override("font_size", SIZE_FOOT)
	btn.add_theme_color_override("font_color", INK_SOLID if accent else TEXT)
	btn.add_theme_color_override("font_hover_color", INK_SOLID if accent else TEXT)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 剧情选项「挑签」：静息潮光线，hover 左杠加宽、正文右让一截。
static func _choice_box(hover: bool) -> StyleBoxFlat:
	var st := _flat(
		BTN_HI if hover else BTN,
		Color(TIDE, 0.95) if hover else Color(TIDE, 0.40),
		0
	)
	st.border_width_left = 6 if hover else 3
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 1
	st.content_margin_left = 20 if hover else 12
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return st


static func style_choice_button(btn: Button, selected := false) -> void:
	_paint_font(btn)
	btn.add_theme_stylebox_override("normal", _choice_box(selected))
	btn.add_theme_stylebox_override("hover", _choice_box(true))
	btn.add_theme_stylebox_override("pressed", _choice_box(true))
	btn.add_theme_stylebox_override("disabled", _choice_box(false))
	btn.add_theme_stylebox_override("focus", _choice_box(true))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_pressed_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.add_theme_font_size_override("font_size", SIZE_BODY)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func style_heading(lbl: Label, port := false) -> void:
	_paint_font(lbl)
	lbl.add_theme_font_size_override("font_size", SIZE_PORT if port else SIZE_HEAD)
	lbl.add_theme_color_override("font_color", GOLD)


static func style_body(rtl: RichTextLabel) -> void:
	var f := font()
	rtl.add_theme_font_override("normal_font", f)
	rtl.add_theme_font_override("bold_font", f)
	rtl.add_theme_font_override("italics_font", f)
	rtl.add_theme_font_override("bold_italics_font", f)
	rtl.add_theme_font_size_override("normal_font_size", SIZE_BODY)
	rtl.add_theme_color_override("default_color", TEXT)
	rtl.add_theme_constant_override("line_separation", LINE_BODY)


static func style_footnote(lbl: Label) -> void:
	_paint_font(lbl)
	lbl.add_theme_font_size_override("font_size", SIZE_FOOT)
	lbl.add_theme_color_override("font_color", TEXT_DIM)


## 在容器 child_entered_tree 上挂一次，之后任何代码 add 的按钮自动带样式。
## choice=true 走挑签，设施页选项与剧情选项同一套。
static func hook_buttons(container: Node, choice := false) -> void:
	container.child_entered_tree.connect(func(n: Node):
		if n is Button:
			if choice:
				style_choice_button(n)
			else:
				style_button(n)
	)


## 分隔标题：潮光小字。
static func style_section_label(lbl: Label) -> void:
	_paint_font(lbl)
	lbl.add_theme_font_size_override("font_size", SIZE_FOOT)
	lbl.add_theme_color_override("font_color", Color(GOLD, 0.92))


## 日志开头的【舱满】【钱不够】一类标签是原型告警，句子留下。
## 色标包在外面时也去掉标签，不拆 bbcode。
static func plain_log(text: String) -> String:
	var open := text.find("【")
	if open < 0 or open > 24:
		return text
	var close := text.find("】", open + 1)
	if close < 0 or close - open > 8:
		return text
	var head := text.substr(0, open).strip_edges()
	if head != "" and not head.begins_with("[color="):
		return text
	return (text.substr(0, open) + text.substr(close + 1)).strip_edges()


## 给 AcceptDialog 套绢本面板。accent_ok=朱砂确定钮。
static func style_dialog(dlg: AcceptDialog, accent_ok := false) -> void:
	dlg.theme = theme()
	dlg.add_theme_stylebox_override("panel", panel())
	dlg.add_theme_color_override("title_color", GOLD)
	dlg.add_theme_font_override("title_font", font())
	var ok := dlg.get_ok_button()
	if ok:
		style_button(ok, accent_ok)
