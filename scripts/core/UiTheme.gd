class_name UiTheme
extends RefCounted
## 「绢本墨笔」：熟漆底、泥金线、朱砂主钮。面板不透底图。
## class_name 全局可解析，不占 autoload。

const INK := Color(0.145, 0.098, 0.064, 0.96)       # 熟漆面板
const INK_SOFT := Color(0.227, 0.165, 0.108, 0.98)  # 港卡，几乎不透
const GOLD := Color(0.86, 0.70, 0.34)               # 泥金
const TEXT := Color(0.95, 0.91, 0.82)               # 绢色正文
const TEXT_DIM := Color(0.73, 0.65, 0.52)           # 旁注
const SEAL := Color(0.70, 0.24, 0.16)               # 朱砂
const SEAL_HI := Color(0.82, 0.32, 0.20)
const MOSS := Color(0.62, 0.74, 0.48)               # 顺风 / 已办
const HONEY := Color(0.90, 0.72, 0.38)              # 紧缺 / 欠账
const CINNABAR := Color(0.86, 0.46, 0.34)           # 告警字，比钮浅一档
const VEIL := Color(0.07, 0.04, 0.02, 0.50)         # 压暗照片，字才站得住

# 字阶从 Main.tscn 实测收口。标题页大题仍可单独加大。
const SIZE_PORT := 32
const SIZE_HEAD := 28
const SIZE_CARD := 22
const SIZE_BODY := 18
const SIZE_FOOT := 13
const LINE_BODY := 6

const _FONT_NAMES: PackedStringArray = [
	"Songti SC",
	"STSong",
	"Noto Serif CJK SC",
	"Source Han Serif SC",
	"Noto Serif CJK JP",
	"KaiTi",
	"SimSun",
	"WenQuanYi Micro Hei",
	"Droid Sans Fallback",
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
	t.set_color("font_hover_color", "Button", Color(1.0, 0.97, 0.90))
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.97, 0.90))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_focus_color", "Button", TEXT)
	var ink_n := _button_box(Color(0.20, 0.145, 0.095, 0.98), Color(GOLD, 0.32))
	var ink_h := _button_box(Color(0.30, 0.22, 0.15, 1.0), Color(GOLD, 0.72))
	var ink_p := _button_box(Color(0.14, 0.10, 0.07, 1.0), Color(GOLD, 0.40))
	var ink_d := _button_box(Color(0.14, 0.11, 0.08, 0.55), Color(GOLD, 0.12))
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

	var track := _flat(Color(0.05, 0.03, 0.02, 0.35), Color(0, 0, 0, 0), 3, 0)
	var grab := _flat(Color(GOLD, 0.55), Color(0, 0, 0, 0), 3, 0)
	var grab_hi := _flat(Color(GOLD, 0.85), Color(0, 0, 0, 0), 3, 0)
	for kind in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", kind, track)
		t.set_stylebox("grabber", kind, grab)
		t.set_stylebox("grabber_highlight", kind, grab_hi)
		t.set_stylebox("grabber_pressed", kind, grab_hi)

	var pop := panel()
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.97, 0.90))
	t.set_font("font", "PopupMenu", f)
	t.set_font_size("font_size", "PopupMenu", SIZE_FOOT)
	t.set_stylebox("hover", "PopupMenu", _flat(Color(GOLD, 0.22), Color(0, 0, 0, 0), 2, 0))

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


## 熟漆面板：泥金细边，从画上浮起来，底图不再透进字里。
static func panel() -> StyleBoxFlat:
	var st := _flat(INK, Color(GOLD, 0.48), 8)
	st.shadow_color = Color(0, 0, 0, 0.40)
	st.shadow_size = 8
	st.shadow_offset = Vector2(0, 3)
	return st


## 港名匾、卷首不用大圆角。
static func plaque() -> StyleBoxFlat:
	var st := _flat(Color(0.11, 0.07, 0.04, 0.94), Color(GOLD, 0.88), 2, 1)
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
	var st := _flat(Color(0.08, 0.05, 0.03, 1.0), Color(GOLD, 0.72), 3, 1)
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	return st


static func log_well() -> StyleBoxFlat:
	var st := _flat(Color(0.07, 0.045, 0.028, 0.72), Color(GOLD, 0.22), 4, 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st


static func card() -> StyleBoxFlat:
	var st := _flat(INK_SOFT, Color(GOLD, 0.36), 5, 1)
	st.border_width_left = 3
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


static func card_hover() -> StyleBoxFlat:
	var st := _flat(Color(0.32, 0.23, 0.15, 1.0), Color(GOLD, 0.80), 5, 1)
	st.border_width_left = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var st := _flat(bg, border, 6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 7
	st.content_margin_bottom = 7
	return st


static func _paint_font(ctrl: Control) -> void:
	ctrl.add_theme_font_override("font", font())


## 四态按钮。accent=朱砂主钮（升帆 / 开局），其余墨金。
static func style_button(btn: Button, accent := false) -> void:
	_paint_font(btn)
	if accent:
		btn.add_theme_stylebox_override("normal", _button_box(Color(SEAL, 0.96), Color(0.93, 0.78, 0.42, 0.55)))
		btn.add_theme_stylebox_override("hover", _button_box(SEAL_HI, Color(0.97, 0.84, 0.50, 0.85)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(0.48, 0.15, 0.11), Color(GOLD, 0.40)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.28, 0.15, 0.12, 0.6), Color(GOLD, 0.14)))
		btn.add_theme_stylebox_override("focus", _button_box(SEAL_HI, Color(GOLD, 0.7)))
		btn.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.98, 0.92))
		btn.add_theme_color_override("font_disabled_color", Color(0.62, 0.54, 0.48))
	else:
		btn.add_theme_stylebox_override("normal", _button_box(Color(0.20, 0.145, 0.095, 0.98), Color(GOLD, 0.32)))
		btn.add_theme_stylebox_override("hover", _button_box(Color(0.30, 0.22, 0.15, 1.0), Color(GOLD, 0.72)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(0.14, 0.10, 0.07, 1.0), Color(GOLD, 0.40)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.14, 0.11, 0.08, 0.55), Color(GOLD, 0.12)))
		btn.add_theme_stylebox_override("focus", _button_box(Color(0.30, 0.22, 0.15, 1.0), Color(GOLD, 0.72)))
		btn.add_theme_color_override("font_color", TEXT)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.90))
		btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 牙行价目上的小钮，不能用正文钮的大内边距，否则一行排不下。
static func style_chip(btn: Button, accent := false) -> void:
	_paint_font(btn)
	var bg := Color(SEAL, 0.94) if accent else Color(0.20, 0.145, 0.095, 0.98)
	var hi := SEAL_HI if accent else Color(0.30, 0.22, 0.15, 1.0)
	var border := Color(0.93, 0.78, 0.42, 0.55) if accent else Color(GOLD, 0.36)
	var mk := func(c: Color) -> StyleBoxFlat:
		var st := _flat(c, border, 3, 1)
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		return st
	btn.add_theme_stylebox_override("normal", mk.call(bg))
	btn.add_theme_stylebox_override("hover", mk.call(hi))
	btn.add_theme_stylebox_override("pressed", mk.call(Color(0.14, 0.10, 0.07, 1.0)))
	btn.add_theme_stylebox_override("disabled", mk.call(Color(0.14, 0.11, 0.08, 0.45)))
	btn.add_theme_stylebox_override("focus", mk.call(hi))
	btn.add_theme_font_size_override("font_size", SIZE_FOOT)
	btn.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88) if accent else TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.90))
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 剧情选项「挑签」：静息细金杠，hover 左杠加宽、正文右让一截。
static func _choice_box(hover: bool) -> StyleBoxFlat:
	var st := _flat(
		Color(0.30, 0.22, 0.15, 1.0) if hover else Color(0.20, 0.145, 0.10, 0.98),
		Color(GOLD, 0.78) if hover else Color(GOLD, 0.32),
		4
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


static func style_choice_button(btn: Button) -> void:
	_paint_font(btn)
	btn.add_theme_stylebox_override("normal", _choice_box(false))
	btn.add_theme_stylebox_override("hover", _choice_box(true))
	btn.add_theme_stylebox_override("pressed", _choice_box(true))
	btn.add_theme_stylebox_override("disabled", _choice_box(false))
	btn.add_theme_stylebox_override("focus", _choice_box(true))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.90))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.97, 0.90))
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


## 分隔标题：泥金小字。
static func style_section_label(lbl: Label) -> void:
	_paint_font(lbl)
	lbl.add_theme_font_size_override("font_size", SIZE_FOOT)
	lbl.add_theme_color_override("font_color", Color(GOLD, 0.92))


## 给 AcceptDialog 套绢本面板。accent_ok=朱砂确定钮。
static func style_dialog(dlg: AcceptDialog, accent_ok := false) -> void:
	dlg.theme = theme()
	dlg.add_theme_stylebox_override("panel", panel())
	dlg.add_theme_color_override("title_color", GOLD)
	dlg.add_theme_font_override("title_font", font())
	var ok := dlg.get_ok_button()
	if ok:
		style_button(ok, accent_ok)
