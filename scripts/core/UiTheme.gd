class_name UiTheme
extends RefCounted
## 「绢本墨笔」UI 主题：深绢底、金线、朱砂主钮。
## 静态工厂统一取色取形；各处 UI 不再散落硬编码色值。
## class_name 全局可解析，不占 autoload（autoload 顺序是既有门禁的敏感面）。

const INK := Color(0.08, 0.10, 0.15, 0.86)       # 深绢面板底
const INK_SOFT := Color(0.12, 0.14, 0.20, 0.72)  # 卡片底
const GOLD := Color(0.79, 0.64, 0.15)            # 金线 / 标题
const TEXT := Color(0.90, 0.88, 0.82)            # 正文
const TEXT_DIM := Color(0.58, 0.61, 0.65)        # 弱提示
const SEAL := Color(0.64, 0.22, 0.17)            # 朱砂主钮
const SEAL_HI := Color(0.76, 0.29, 0.21)         # 朱砂 hover

# 字阶从 Main.tscn 实测收口。标题页大题 64 仍走场景，不挤进正文栏。
const SIZE_PORT := 36     # 港口名（原 36）
const SIZE_HEAD := 28     # 调查页标题、人物名（原 32）
const SIZE_CARD := 22     # 设施卡 / 升帆（原 22）
const SIZE_BODY := 18     # 正文、选项（原正文 18、对话 20）
const SIZE_FOOT := 13     # 说明、分隔、行情旁注（原硬编码 13）
const LINE_BODY := 6      # 正文行距（原默认 0，挤）


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


## 深绢面板：金线细边 + 浅投影，面板从画上「浮」起来
static func panel() -> StyleBoxFlat:
	var st := _flat(INK, Color(GOLD, 0.30), 10)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 5
	st.shadow_offset = Vector2(0, 2)
	return st


## 设施卡：比面板浅半档，hover 由调用方接 mouse_entered 换 card_hover()
static func card() -> StyleBoxFlat:
	return _flat(INK_SOFT, Color(GOLD, 0.22), 8)


static func card_hover() -> StyleBoxFlat:
	return _flat(Color(0.17, 0.20, 0.28, 0.85), Color(GOLD, 0.55), 8)


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var st := _flat(bg, border, 8)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 7
	st.content_margin_bottom = 7
	return st


## 四态按钮。accent=朱砂主钮（升帆/迎战/开局），其余墨青。
static func style_button(btn: Button, accent := false) -> void:
	if accent:
		btn.add_theme_stylebox_override("normal", _button_box(Color(SEAL, 0.95), Color(0.90, 0.75, 0.40, 0.45)))
		btn.add_theme_stylebox_override("hover", _button_box(SEAL_HI, Color(0.95, 0.80, 0.45, 0.8)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(0.50, 0.16, 0.12), Color(GOLD, 0.35)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.30, 0.16, 0.14, 0.6), Color(GOLD, 0.12)))
		btn.add_theme_color_override("font_color", Color(0.97, 0.94, 0.87))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.90))
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.50, 0.46))
	else:
		btn.add_theme_stylebox_override("normal", _button_box(Color(0.16, 0.20, 0.28, 0.92), Color(GOLD, 0.25)))
		btn.add_theme_stylebox_override("hover", _button_box(Color(0.23, 0.28, 0.38, 0.95), Color(GOLD, 0.60)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(0.11, 0.14, 0.20, 1.0), Color(GOLD, 0.35)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.12, 0.14, 0.18, 0.55), Color(GOLD, 0.10)))
		btn.add_theme_color_override("font_color", TEXT)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
		btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 剧情选项「挑签」：静息细金杠，hover 左杠加宽、正文右让一截，像从签筒抽出。
static func _choice_box(hover: bool) -> StyleBoxFlat:
	var st := _flat(
		Color(0.23, 0.28, 0.38, 0.95) if hover else Color(0.16, 0.20, 0.28, 0.92),
		Color(GOLD, 0.70) if hover else Color(GOLD, 0.28),
		6
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
	btn.add_theme_stylebox_override("normal", _choice_box(false))
	btn.add_theme_stylebox_override("hover", _choice_box(true))
	btn.add_theme_stylebox_override("pressed", _choice_box(true))
	btn.add_theme_stylebox_override("disabled", _choice_box(false))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.85))
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.add_theme_font_size_override("font_size", SIZE_BODY)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func style_heading(lbl: Label, port := false) -> void:
	lbl.add_theme_font_size_override("font_size", SIZE_PORT if port else SIZE_HEAD)
	lbl.add_theme_color_override("font_color", GOLD)


static func style_body(rtl: RichTextLabel) -> void:
	rtl.add_theme_font_size_override("normal_font_size", SIZE_BODY)
	rtl.add_theme_color_override("default_color", TEXT)
	rtl.add_theme_constant_override("line_separation", LINE_BODY)


static func style_footnote(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", SIZE_FOOT)
	lbl.add_theme_color_override("font_color", TEXT_DIM)


## 递归给子树所有 Button 上默认样式（OptionButton 亦属 Button）。
## 在容器 child_entered_tree 上挂一次，之后任何代码 add 的按钮自动带样式。
static func hook_buttons(container: Node) -> void:
	container.child_entered_tree.connect(func(n: Node):
		if n is Button:
			style_button(n)
	)


## 分隔标题（「── 呈报所见 ──」这类）：金色小字
static func style_section_label(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", SIZE_FOOT)
	lbl.add_theme_color_override("font_color", Color(GOLD, 0.85))


## 给 AcceptDialog 套绢本面板。accent_ok=朱砂确定钮（了结 / 升章）。
static func style_dialog(dlg: AcceptDialog, accent_ok := false) -> void:
	dlg.add_theme_stylebox_override("panel", panel())
	dlg.add_theme_color_override("title_color", GOLD)
	var ok := dlg.get_ok_button()
	if ok:
		style_button(ok, accent_ok)
