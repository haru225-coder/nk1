## nk-1 主题生成器（绢本墨笔）。headless 运行：
##   <godot 4.6.3> --headless --path <项目根> --script res://tools/art/build_theme.gd
## 先跑 python3 tools/art/build_ui_textures.py 出贴图（assets/ui/nk1/*.png，全部 2×）。
## 本脚本做三件事：
##   1. 把九宫贴图包成 PortableCompressedTexture2D（无损）并设 size_override = 原尺寸 ½，
##      存到 assets/theme/tex/*.res —— StyleBoxTexture 于是按逻辑像素切九宫、按 2× 纹素采样，
##      1280×720 基准下正好 1:1，2560×1440 / Retina 下不糊。
##   2. 小图标（icons/*.svg）包成 DPITexture，随画面缩放重新栅格化。
##   3. 组装 Theme 存 assets/theme/nk1_theme.tres（含 type variation，名单见 docs/美术规范.md）。
extends SceneTree

const UI := "res://assets/ui/nk1/"
const TEX_DIR := "res://assets/theme/tex/"
const THEME_PATH := "res://assets/theme/nk1_theme.tres"
const FONT_BODY := "res://assets/fonts/LXGWWenKai-Medium.ttf"
const FONT_TITLE := "res://assets/fonts/MaShanZheng-Regular.ttf"

# 色板
const JIAOMO := Color("#0d0b09")
const MO := Color("#1a1612")
const XUAN := Color("#e9dcc0")
const JIUJUAN := Color("#cdb88f")
const NIJIN := Color("#c9a14a")
const GOLD_HI := Color("#ecd08a")
const ZHUSHA := Color("#b0302a")
const DIANQING := Color("#1f3a4d")
const SHIQING := Color("#3b6e7a")
const ZHESHI := Color("#8a5a2b")
const YUEBAI := Color("#d6e4e8")
const DISABLED_TXT := Color("#9a9080")
const SEAL_TXT := Color("#f6eedb")

var _tex_cache := {}
var _saved := 0


func _initialize() -> void:
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))
	var theme := _build()
	var err := ResourceSaver.save(theme, THEME_PATH)
	print("BUILD_THEME save ", THEME_PATH, " err=", err, " textures=", _saved)
	quit(0 if err == OK else 1)


# ─────────────────────────────────────────────── 资源工具
## 2× PNG → size_override=½ 的无损便携纹理（外部 .res，主题只存引用）。
func _tex2x(png: String) -> Texture2D:
	if _tex_cache.has(png):
		return _tex_cache[png]
	var img := Image.load_from_file(ProjectSettings.globalize_path(UI + png))
	if img == null or img.is_empty():
		push_error("BUILD_THEME 缺贴图 " + png)
		return null
	var t := PortableCompressedTexture2D.new()
	t.keep_compressed_buffer = true
	t.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	t.size_override = Vector2(img.get_width() / 2.0, img.get_height() / 2.0)
	var path := TEX_DIR + png.get_file().get_basename() + ".res"
	ResourceSaver.save(t, path)
	_saved += 1
	var loaded: Texture2D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_tex_cache[png] = loaded
	return loaded


## SVG 图标 → DPITexture（外部 .tres）。
func _icon(svg_name: String) -> Texture2D:
	var key := "svg:" + svg_name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var src := FileAccess.get_file_as_string(UI + "icons/" + svg_name + ".svg")
	var d := DPITexture.create_from_string(src, 1.0)
	var path := TEX_DIR + svg_name + ".tres"
	ResourceSaver.save(d, path)
	_saved += 1
	var loaded: Texture2D = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_tex_cache[key] = loaded
	return loaded


## 九宫 StyleBoxTexture。margin / content / expand 都是逻辑像素 [左, 上, 右, 下]。
func _sbt(png: String, margin: Array, content: Array, expand: Array = [0, 0, 0, 0],
		tile_h: bool = false, tile_v: bool = false, draw_center: bool = true) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _tex2x(png)
	sb.texture_margin_left = margin[0]
	sb.texture_margin_top = margin[1]
	sb.texture_margin_right = margin[2]
	sb.texture_margin_bottom = margin[3]
	sb.content_margin_left = content[0]
	sb.content_margin_top = content[1]
	sb.content_margin_right = content[2]
	sb.content_margin_bottom = content[3]
	sb.expand_margin_left = expand[0]
	sb.expand_margin_top = expand[1]
	sb.expand_margin_right = expand[2]
	sb.expand_margin_bottom = expand[3]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT if tile_h else StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT if tile_v else StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.draw_center = draw_center
	return sb


func _empty(l: float = 0, t: float = 0, r: float = 0, b: float = 0) -> StyleBoxEmpty:
	var e := StyleBoxEmpty.new()
	e.content_margin_left = l
	e.content_margin_top = t
	e.content_margin_right = r
	e.content_margin_bottom = b
	return e


func _set_styles(th: Theme, type: String, styles: Dictionary) -> void:
	for k in styles:
		th.set_stylebox(k, type, styles[k])


func _set_colors(th: Theme, type: String, colors: Dictionary) -> void:
	for k in colors:
		th.set_color(k, type, colors[k])


# ─────────────────────────────────────────────── 主题
func _build() -> Theme:
	var th := Theme.new()
	var body: FontFile = load(FONT_BODY)
	var title := FontVariation.new()
	title.base_font = load(FONT_TITLE)
	title.fallbacks = [body]              # 马善政缺的少数生僻字落回文楷
	var bold := FontVariation.new()
	bold.base_font = body
	bold.variation_embolden = 0.55
	var italic := FontVariation.new()
	italic.base_font = body
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.18, 1), Vector2.ZERO)

	th.default_font = body
	th.default_font_size = 18
	var shadow := Color(0, 0, 0, 0.55)

	# 九宫
	var sb_ink := _sbt("panel_ink.png", [20, 20, 20, 20], [16, 14, 16, 14], [4, 4, 4, 4], true, true)
	var sb_silk := _sbt("panel_silk.png", [28, 28, 28, 28], [22, 18, 22, 18], [6, 6, 6, 6], true, true)
	var sb_paper := _sbt("panel_paper.png", [20, 20, 20, 20], [16, 14, 16, 14], [5, 5, 5, 5], true, true)
	var sb_tip := _sbt("panel_tip.png", [10, 10, 10, 10], [10, 6, 10, 7], [3, 3, 3, 3], true, true)
	var btn := {}
	var seal := {}
	for st in ["normal", "hover", "pressed", "disabled"]:
		var shift := 1 if st == "pressed" else 0
		btn[st] = _sbt("btn_ink_%s.png" % st, [12, 10, 12, 10], [18, 8 + shift, 18, 8 - shift], [0, 0, 0, 0], true, false)
		seal[st] = _sbt("btn_seal_%s.png" % st, [12, 10, 12, 10], [22, 6 + shift, 22, 6 - shift], [0, 0, 0, 0], true, false)
	var focus := _sbt("focus_frame.png", [10, 10, 10, 10], [0, 0, 0, 0], [4, 4, 4, 4], false, false, false)
	var hover_band := _sbt("hover_band.png", [6, 6, 6, 6], [12, 4, 8, 4], [0, 0, 0, 0], true, false)
	var field := _sbt("field_normal.png", [12, 8, 12, 8], [10, 6, 10, 6], [0, 0, 0, 0], true, false)
	var field_focus := _sbt("field_focus.png", [12, 8, 12, 8], [10, 6, 10, 6], [0, 0, 0, 0], true, false)
	var sep_gold := _sbt("divider_gold.png", [80, 6, 80, 6], [0, 6, 0, 6], [0, 0, 0, 0], true, false)
	var sep_ink := _sbt("divider_ink.png", [80, 6, 80, 6], [0, 6, 0, 6], [0, 0, 0, 0], true, false)
	var vsep_gold := _sbt("vdivider_gold.png", [6, 80, 6, 80], [6, 0, 6, 0], [0, 0, 0, 0], false, true)
	var vsep_ink := _sbt("vdivider_ink.png", [6, 80, 6, 80], [6, 0, 6, 0], [0, 0, 0, 0], false, true)

	# ── Label / RichTextLabel
	_set_colors(th, "Label", {"font_color": XUAN, "font_shadow_color": shadow,
		"font_outline_color": Color(JIAOMO, 0.0)})
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	th.set_constant("line_spacing", "Label", 4)
	th.set_font_size("font_size", "Label", 18)

	th.set_font("normal_font", "RichTextLabel", body)
	th.set_font("bold_font", "RichTextLabel", bold)
	th.set_font("italics_font", "RichTextLabel", italic)
	th.set_font("bold_italics_font", "RichTextLabel", bold)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		th.set_font_size(k, "RichTextLabel", 18)
	_set_colors(th, "RichTextLabel", {"default_color": XUAN, "font_shadow_color": shadow,
		"selection_color": Color(NIJIN, 0.35), "font_selected_color": Color(1, 1, 1, 0)})
	th.set_constant("shadow_offset_x", "RichTextLabel", 1)
	th.set_constant("shadow_offset_y", "RichTextLabel", 1)
	th.set_constant("line_separation", "RichTextLabel", 4)
	_set_styles(th, "RichTextLabel", {"normal": _empty(), "focus": _empty()})

	# ── Button（墨底泥金边）
	_set_styles(th, "Button", {"normal": btn["normal"], "hover": btn["hover"], "pressed": btn["pressed"],
		"hover_pressed": btn["pressed"], "disabled": btn["disabled"], "focus": focus})
	_set_colors(th, "Button", {"font_color": XUAN, "font_hover_color": GOLD_HI, "font_pressed_color": NIJIN,
		"font_hover_pressed_color": GOLD_HI, "font_focus_color": XUAN, "font_disabled_color": DISABLED_TXT,
		"font_outline_color": Color(JIAOMO, 0.0), "icon_normal_color": XUAN, "icon_hover_color": GOLD_HI,
		"icon_pressed_color": NIJIN, "icon_disabled_color": Color(DISABLED_TXT, 0.6)})
	th.set_font_size("font_size", "Button", 18)
	th.set_constant("h_separation", "Button", 8)

	# OptionButton / MenuButton 继承 Button 的样式；补箭头
	th.set_icon("arrow", "OptionButton", _icon("icon_arrow_down"))
	th.set_constant("arrow_margin", "OptionButton", 10)
	_set_styles(th, "OptionButton", {"normal": _sbt("btn_ink_normal.png", [12, 10, 12, 10], [18, 8, 34, 8], [0, 0, 0, 0], true, false),
		"hover": _sbt("btn_ink_hover.png", [12, 10, 12, 10], [18, 8, 34, 8], [0, 0, 0, 0], true, false),
		"pressed": _sbt("btn_ink_pressed.png", [12, 10, 12, 10], [18, 9, 34, 7], [0, 0, 0, 0], true, false),
		"disabled": _sbt("btn_ink_disabled.png", [12, 10, 12, 10], [18, 8, 34, 8], [0, 0, 0, 0], true, false),
		"focus": focus})

	# CheckBox / CheckButton：不吃按钮底板
	for tp in ["CheckBox", "CheckButton"]:
		_set_styles(th, tp, {"normal": _empty(4, 3, 4, 3), "pressed": _empty(4, 3, 4, 3), "hover": hover_band,
			"hover_pressed": hover_band, "disabled": _empty(4, 3, 4, 3), "focus": focus})
		_set_colors(th, tp, {"font_color": XUAN, "font_hover_color": GOLD_HI, "font_pressed_color": XUAN,
			"font_hover_pressed_color": GOLD_HI, "font_disabled_color": DISABLED_TXT})
		th.set_constant("h_separation", tp, 8)
	th.set_icon("checked", "CheckBox", _icon("icon_check_on"))
	th.set_icon("unchecked", "CheckBox", _icon("icon_check_off"))
	th.set_icon("radio_checked", "CheckBox", _icon("icon_radio_on"))
	th.set_icon("radio_unchecked", "CheckBox", _icon("icon_radio_off"))

	# ── 面板
	th.set_stylebox("panel", "PanelContainer", sb_ink)
	th.set_stylebox("panel", "Panel", sb_ink)
	th.set_stylebox("panel", "PopupPanel", sb_ink)
	th.set_stylebox("panel", "ScrollContainer", _empty())

	# ── 输入框
	for tp in ["LineEdit", "TextEdit"]:
		_set_styles(th, tp, {"normal": field, "focus": field_focus, "read_only": field})
		_set_colors(th, tp, {"font_color": XUAN, "font_placeholder_color": Color(JIUJUAN, 0.5),
			"caret_color": GOLD_HI, "selection_color": Color(NIJIN, 0.35), "font_selected_color": XUAN,
			"font_readonly_color": Color(XUAN, 0.6)})

	# ── 分隔线
	th.set_stylebox("separator", "HSeparator", sep_gold)
	th.set_constant("separation", "HSeparator", 16)
	th.set_stylebox("separator", "VSeparator", vsep_gold)
	th.set_constant("separation", "VSeparator", 16)

	# ── 滚动条
	var track_v := _sbt("scroll_track_v.png", [0, 8, 0, 8], [6, 0, 6, 0], [0, 0, 0, 0], false, true)
	var track_h := _sbt("scroll_track_h.png", [8, 0, 8, 0], [0, 6, 0, 6], [0, 0, 0, 0], true, false)
	_set_styles(th, "VScrollBar", {"scroll": track_v, "scroll_focus": track_v,
		"grabber": _sbt("scroll_grabber_v.png", [0, 8, 0, 8], [6, 8, 6, 8], [0, 0, 0, 0], false, true),
		"grabber_highlight": _sbt("scroll_grabber_hl_v.png", [0, 8, 0, 8], [6, 8, 6, 8], [0, 0, 0, 0], false, true),
		"grabber_pressed": _sbt("scroll_grabber_pressed_v.png", [0, 8, 0, 8], [6, 8, 6, 8], [0, 0, 0, 0], false, true)})
	_set_styles(th, "HScrollBar", {"scroll": track_h, "scroll_focus": track_h,
		"grabber": _sbt("scroll_grabber_h.png", [8, 0, 8, 0], [8, 6, 8, 6], [0, 0, 0, 0], true, false),
		"grabber_highlight": _sbt("scroll_grabber_hl_h.png", [8, 0, 8, 0], [8, 6, 8, 6], [0, 0, 0, 0], true, false),
		"grabber_pressed": _sbt("scroll_grabber_pressed_h.png", [8, 0, 8, 0], [8, 6, 8, 6], [0, 0, 0, 0], true, false)})

	# ── 弹出菜单
	_set_styles(th, "PopupMenu", {"panel": _sbt("panel_ink.png", [20, 20, 20, 20], [8, 8, 8, 8], [4, 4, 4, 4], true, true),
		"hover": hover_band, "separator": sep_gold, "labeled_separator_left": sep_gold,
		"labeled_separator_right": sep_gold})
	_set_colors(th, "PopupMenu", {"font_color": XUAN, "font_hover_color": GOLD_HI, "font_disabled_color": DISABLED_TXT,
		"font_separator_color": JIUJUAN, "font_accelerator_color": Color(JIUJUAN, 0.7)})
	th.set_font_size("font_size", "PopupMenu", 18)
	th.set_constant("v_separation", "PopupMenu", 8)
	th.set_constant("h_separation", "PopupMenu", 8)
	th.set_icon("checked", "PopupMenu", _icon("icon_check_on"))
	th.set_icon("unchecked", "PopupMenu", _icon("icon_check_off"))
	th.set_icon("radio_checked", "PopupMenu", _icon("icon_radio_on"))
	th.set_icon("radio_unchecked", "PopupMenu", _icon("icon_radio_off"))
	th.set_icon("submenu", "PopupMenu", _icon("icon_arrow_right"))

	# ── 提示框（宣纸小笺 + 墨字）
	th.set_stylebox("panel", "TooltipPanel", sb_tip)
	_set_colors(th, "TooltipLabel", {"font_color": MO, "font_shadow_color": Color(0, 0, 0, 0)})
	th.set_font_size("font_size", "TooltipLabel", 16)
	th.set_font("font", "TooltipLabel", body)

	# ── 嵌入式窗口 / AcceptDialog：旧绢题签 + 靛墨裱边
	var frame := _sbt("window_frame.png", [21, 57, 21, 21], [0, 0, 0, 0], [11, 47, 11, 11], true, true)
	var frame_dim := _sbt("window_frame.png", [21, 57, 21, 21], [0, 0, 0, 0], [11, 47, 11, 11], true, true)
	frame_dim.modulate_color = Color(0.82, 0.82, 0.82, 1)
	th.set_stylebox("embedded_border", "Window", frame)
	th.set_stylebox("embedded_unfocused_border", "Window", frame_dim)
	# 注意：Theme 设了 default_font 后，has_font() 对任何类型都返回 true，
	# 所以窗口标题字体必须写在最末端的类型上（AcceptDialog 先于 Window 被查到），否则拿到的是默认文楷。
	for tp in ["Window", "AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		th.set_font("title_font", tp, title)
		th.set_font_size("title_font_size", tp, 24)
	_set_colors(th, "Window", {"title_color": MO, "title_outline_modulate": Color(XUAN, 0.0)})
	th.set_constant("title_height", "Window", 38)
	th.set_constant("title_outline_size", "Window", 0)
	th.set_constant("close_h_offset", "Window", 32)
	th.set_constant("close_v_offset", "Window", 30)
	th.set_constant("resize_margin", "Window", 6)
	th.set_icon("close", "Window", _icon("icon_close_seal"))
	th.set_icon("close_pressed", "Window", _icon("icon_close_seal_pressed"))
	# 嵌入式窗口的内容区会先清成引擎灰，正文底必须不透明
	th.set_stylebox("panel", "AcceptDialog", _sbt("tex_ink_solid.png", [0, 0, 0, 0], [16, 12, 16, 12], [0, 0, 0, 0], true, true))
	th.set_constant("buttons_separation", "AcceptDialog", 16)
	th.set_constant("buttons_min_width", "AcceptDialog", 120)
	th.set_constant("buttons_min_height", "AcceptDialog", 40)

	# ── 进度条 / 页签
	_set_styles(th, "ProgressBar", {"background": _sbt("bar_bg.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false),
		"fill": _sbt("bar_fill_teal.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false)})
	_set_colors(th, "ProgressBar", {"font_color": XUAN, "font_outline_color": JIAOMO})
	th.set_font_size("font_size", "ProgressBar", 16)
	th.set_constant("outline_size", "ProgressBar", 4)

	var tab_sel := _sbt("tab_selected.png", [8, 8, 8, 8], [16, 6, 16, 6], [0, 0, 0, 0], true, false)
	var tab_un := _sbt("tab_unselected.png", [8, 8, 8, 8], [16, 6, 16, 6], [0, 0, 0, 0], true, false)
	var tab_hov := _sbt("tab_hover.png", [8, 8, 8, 8], [16, 6, 16, 6], [0, 0, 0, 0], true, false)
	for tp in ["TabContainer", "TabBar"]:
		_set_styles(th, tp, {"tab_selected": tab_sel, "tab_unselected": tab_un, "tab_hovered": tab_hov,
			"tab_disabled": tab_un, "tab_focus": _empty()})
		_set_colors(th, tp, {"font_selected_color": GOLD_HI, "font_unselected_color": JIUJUAN,
			"font_hovered_color": XUAN, "font_disabled_color": DISABLED_TXT, "font_outline_color": Color(JIAOMO, 0.0)})
		th.set_font("font", tp, title)
		th.set_font_size("font_size", tp, 20)
	th.set_stylebox("panel", "TabContainer", sb_ink)
	th.set_stylebox("tabbar_background", "TabContainer", _empty())
	th.set_constant("side_margin", "TabContainer", 10)

	# ── ItemList（列表选择）
	_set_styles(th, "ItemList", {"panel": sb_ink, "focus": _empty(), "hovered": hover_band, "selected": hover_band,
		"selected_focus": hover_band, "cursor": _empty(), "cursor_unfocused": _empty()})
	_set_colors(th, "ItemList", {"font_color": XUAN, "font_hovered_color": GOLD_HI, "font_selected_color": GOLD_HI})

	# ══════════════ type variations（集成者用：control.theme_type_variation = "&名字"）
	# 标题：马善政大字，宣纸色 + 焦墨描边投影，压画面用
	_variation(th, "TitleLabel", "Label")
	th.set_font("font", "TitleLabel", title)
	th.set_font_size("font_size", "TitleLabel", 48)
	_set_colors(th, "TitleLabel", {"font_color": XUAN, "font_outline_color": Color(JIAOMO, 0.55),
		"font_shadow_color": Color(0, 0, 0, 0.55)})
	th.set_constant("outline_size", "TitleLabel", 3)
	th.set_constant("shadow_offset_x", "TitleLabel", 2)
	th.set_constant("shadow_offset_y", "TitleLabel", 3)
	th.set_constant("shadow_outline_size", "TitleLabel", 12)
	# 小标题：马善政，亮泥金
	_variation(th, "HeadingLabel", "Label")
	th.set_font("font", "HeadingLabel", title)
	th.set_font_size("font_size", "HeadingLabel", 28)
	_set_colors(th, "HeadingLabel", {"font_color": GOLD_HI, "font_outline_color": Color(JIAOMO, 0.7),
		"font_shadow_color": Color(0, 0, 0, 0.5)})
	th.set_constant("outline_size", "HeadingLabel", 4)
	# 说明小字：文楷 16，旧绢色（放在墨面板 / 墨刷底上）
	_variation(th, "CaptionLabel", "Label")
	th.set_font_size("font_size", "CaptionLabel", 16)
	_set_colors(th, "CaptionLabel", {"font_color": JIUJUAN})
	# 直接压在画面上的小字（港口副题、页面说明）：焦墨紧描边 + 一圈半透明墨晕。
	# 画面亮处（天空、白墙、亮木柱）浅字只剩 1–2.6:1，这两层把字形周边压成墨色。
	for pair in [["OverlayCaption", 16, JIUJUAN], ["OverlayText", 18, XUAN]]:
		_variation(th, pair[0], "Label")
		th.set_font_size("font_size", pair[0], pair[1])
		_set_colors(th, pair[0], {"font_color": pair[2], "font_outline_color": Color(JIAOMO, 0.9),
			"font_shadow_color": Color(JIAOMO, 0.55)})
		th.set_constant("outline_size", pair[0], 4)
		th.set_constant("shadow_offset_x", pair[0], 0)
		th.set_constant("shadow_offset_y", pair[0], 1)
		th.set_constant("shadow_outline_size", pair[0], 10)
	# 浅底（绢 / 纸）上的墨字
	_variation(th, "InkText", "Label")
	_set_colors(th, "InkText", {"font_color": MO, "font_shadow_color": Color(0, 0, 0, 0)})
	_variation(th, "InkCaption", "Label")
	th.set_font_size("font_size", "InkCaption", 16)
	_set_colors(th, "InkCaption", {"font_color": Color("#3d3124"), "font_shadow_color": Color(0, 0, 0, 0)})
	_variation(th, "InkHeading", "Label")
	th.set_font("font", "InkHeading", title)
	th.set_font_size("font_size", "InkHeading", 28)
	_set_colors(th, "InkHeading", {"font_color": MO, "font_shadow_color": Color(0, 0, 0, 0)})
	_variation(th, "InkRichText", "RichTextLabel")
	_set_colors(th, "InkRichText", {"default_color": MO, "font_shadow_color": Color(0, 0, 0, 0)})
	th.set_font("bold_font", "InkRichText", bold)
	th.set_font("italics_font", "InkRichText", italic)
	th.set_font("bold_italics_font", "InkRichText", bold)
	# 朱砂主按钮
	_variation(th, "SealButton", "Button")
	_set_styles(th, "SealButton", {"normal": seal["normal"], "hover": seal["hover"], "pressed": seal["pressed"],
		"hover_pressed": seal["pressed"], "disabled": seal["disabled"], "focus": focus})
	_set_colors(th, "SealButton", {"font_color": SEAL_TXT, "font_hover_color": Color("#fff8e6"),
		"font_pressed_color": XUAN, "font_hover_pressed_color": XUAN, "font_focus_color": SEAL_TXT,
		"font_disabled_color": Color("#c9bcb0"), "font_outline_color": Color(0.35, 0.06, 0.05, 0.6)})
	th.set_font("font", "SealButton", title)
	th.set_font_size("font_size", "SealButton", 24)
	th.set_constant("outline_size", "SealButton", 3)
	# 无底板的文字按钮（对话选项 / 列表项）：悬停起一道泥金晕
	_variation(th, "GhostButton", "Button")
	_set_styles(th, "GhostButton", {"normal": _empty(12, 4, 8, 4), "hover": hover_band, "pressed": hover_band,
		"hover_pressed": hover_band, "disabled": _empty(12, 4, 8, 4), "focus": focus})
	_set_colors(th, "GhostButton", {"font_color": XUAN, "font_hover_color": GOLD_HI, "font_pressed_color": NIJIN})
	# 面板
	_variation(th, "InkPanel", "PanelContainer")
	th.set_stylebox("panel", "InkPanel", sb_ink)
	_variation(th, "SilkPanel", "PanelContainer")
	th.set_stylebox("panel", "SilkPanel", sb_silk)
	_variation(th, "PaperPanel", "PanelContainer")
	th.set_stylebox("panel", "PaperPanel", sb_paper)
	# 浅底上用的墨线分隔
	_variation(th, "InkSeparator", "HSeparator")
	th.set_stylebox("separator", "InkSeparator", sep_ink)
	_variation(th, "InkVSeparator", "VSeparator")
	th.set_stylebox("separator", "InkVSeparator", vsep_ink)
	# 属性条（五维）：细墨槽 + 泥金刷笔；集成者记得 show_percentage = false
	for tp in ["AttrBar", "AttrBarRed", "AttrBarGold"]:
		th.set_font_size("font_size", tp, 16)
	_variation(th, "AttrBar", "ProgressBar")
	_set_styles(th, "AttrBar", {"background": _sbt("attr_bg.png", [5, 4, 5, 4], [5, 1, 5, 1], [0, 0, 0, 0], true, false),
		"fill": _sbt("attr_fill_gold.png", [5, 4, 5, 4], [5, 1, 5, 1], [0, 0, 0, 0], true, false)})
	_variation(th, "AttrBarRed", "ProgressBar")
	_set_styles(th, "AttrBarRed", {"background": _sbt("bar_bg.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false),
		"fill": _sbt("bar_fill_red.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false)})
	_variation(th, "AttrBarGold", "ProgressBar")
	_set_styles(th, "AttrBarGold", {"background": _sbt("bar_bg.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false),
		"fill": _sbt("bar_fill_gold.png", [6, 6, 6, 6], [6, 2, 6, 2], [0, 0, 0, 0], true, false)})
	# 边饰条（PanelContainer：content_margin 上下各 14 → 空容器也自带 28 高，放进 VBox 即显示；横向平铺）
	for pair in [["BandHuiwenGold", "band_huiwen_gold.png"], ["BandHuiwenInk", "band_huiwen_ink.png"],
			["BandCloudGold", "band_cloud_gold.png"]]:
		_variation(th, pair[0], "PanelContainer")
		th.set_stylebox("panel", pair[0], _sbt(pair[1], [0, 14, 0, 14], [0, 14, 0, 14], [0, 0, 0, 0], true, false))
	_ink_tint_material()
	return th


## 墨迹着色材质：assets/theme/ink_tint.gdshader 按贴图 alpha 着色（modulate 只能压暗，出不了朱色墨迹）。
## 预置朱砂一份；要别的颜色就 duplicate() 后改 tint。
func _ink_tint_material() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/theme/ink_tint.gdshader")
	mat.set_shader_parameter("tint", ZHUSHA)
	var err := ResourceSaver.save(mat, "res://assets/theme/ink_tint_zhu.tres")
	if err != OK:
		push_error("BUILD_THEME ink_tint_zhu.tres 保存失败 %d" % err)


func _variation(th: Theme, name: String, base: String) -> void:
	th.set_type_variation(name, base)
