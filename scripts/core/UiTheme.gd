class_name UiTheme
extends RefCounted
## 两套皮肤，改 SKIN 一个常量切换，调用点零改动：
##   "juanben"（默认）绢本墨笔：靛墨面板 + 泥金细线 + 朱砂印钮 + 宣纸工席；正文霞鹜文楷子集，标题马善政。
##   "yechao"（旧皮肤）夜潮：深青底、潮光线、珊瑚主钮。原值原样留在 YECHAO 里，函数里的夜潮分支逐行照旧。
## 颜色、字阶仍是 const（按皮肤从字典里取，编译期定值），SeaChart / Main 里当常量用的地方照常编译。
## 绢本面板、按钮走 assets/theme/tex/*.res（size_override=½ 的 2× 九宫）；贴图缺了回落到委角 StyleBoxFlat。
## class_name 全局可解析，不占 autoload。

const SKIN := "juanben"   # "juanben" 绢本（默认） / "yechao" 夜潮（旧皮肤）
const IS_JUANBEN := SKIN == "juanben"

## 夜潮原值（3cac590 UiTheme.gd 逐项照抄，不许改）。
const YECHAO := {
	"INK": Color(0.055, 0.141, 0.200, 0.96),       # 夜潮面板
	"INK_SOFT": Color(0.086, 0.188, 0.267, 0.98),  # 港卡，几乎不透
	"TIDE": Color(0.243, 0.878, 0.773),            # 潮光
	"GOLD": Color(0.243, 0.878, 0.773),            # 调用点仍写 GOLD，夜潮里就是潮光
	"GOLD_HI": Color(0.243, 0.878, 0.773),
	"TEXT": Color(0.949, 0.984, 0.988),            # 壳白正文
	"TEXT_DIM": Color(0.608, 0.722, 0.769),        # 旁注
	"SEAL": Color(1.0, 0.420, 0.290),              # 珊瑚主钮
	"SEAL_HI": Color(1.0, 0.541, 0.431),
	"SEAL_TEXT": Color(0.055, 0.141, 0.200, 1.0),  # 珊瑚上必须是深字（= INK_SOLID）
	"MOSS": Color(0.490, 0.871, 0.541),            # 顺风 / 已办
	"HONEY": Color(0.941, 0.757, 0.290),           # 紧缺 / 欠账
	"CINNABAR": Color(1.0, 0.561, 0.478),          # 告警字
	"VEIL": Color(0.02, 0.05, 0.09, 0.55),         # 压暗照片，字才站得住
	"DIM": Color(0.02, 0.05, 0.08, 0.62),          # 浮层后面的压暗
	"BTN": Color(0.10, 0.22, 0.31, 0.98),
	"BTN_HI": Color(0.15, 0.32, 0.42, 1.0),
	"BTN_DOWN": Color(0.06, 0.14, 0.20, 1.0),
	"INK_SOLID": Color(0.055, 0.141, 0.200, 1.0),
	"SIZE_PORT": 32,
	"SIZE_HEAD": 28,
	"SIZE_CARD": 22,
	"SIZE_BODY": 18,
	"SIZE_FOOT": 13,
	"LINE_BODY": 6,
}

## 绢本：色板见 docs/美术规范.md 第 2 节。深底字色一律实测 ≥4.5:1（最坏按靛墨面板压在亮画上 #2d312e 算）。
const JUANBEN := {
	"INK": Color(0.082, 0.071, 0.059, 0.96),       # 暖墨 #15120f（= panel_ink 贴图中段；第 1 轮返工由靛墨 #12171a 移到暖墨）
	"INK_SOFT": Color(0.098, 0.086, 0.071, 0.98),  # #191612
	"TIDE": Color(0.561, 0.722, 0.741),            # 石青（浅，深底作字）#8fb8bd：航向、港名、工席抬头
	"GOLD": Color(0.788, 0.631, 0.290),            # 泥金 #c9a14a：线、抬头
	"GOLD_HI": Color(0.925, 0.816, 0.541),         # 亮泥金 #ecd08a：深底小标题、悬停
	"TEXT": Color(0.914, 0.863, 0.753),            # 宣纸 #e9dcc0 正文
	"TEXT_DIM": Color(0.804, 0.722, 0.561),        # 旧绢 #cdb88f 旁注
	"SEAL": Color(0.690, 0.188, 0.165),            # 朱砂 #b0302a 主钮
	"SEAL_HI": Color(0.737, 0.224, 0.176),         # #bc392d 悬停
	"SEAL_TEXT": Color(0.965, 0.933, 0.859),       # 印面字 #f6eedb（朱砂上 5.5:1）
	"MOSS": Color(0.616, 0.780, 0.604),            # 石绿（浅）#9dc79a
	"HONEY": Color(0.910, 0.659, 0.376),           # 藤黄橙 #e8a860
	"CINNABAR": Color(0.925, 0.561, 0.447),        # 提示朱 #ec8f72（深底告警字）
	"VEIL": Color(0.05, 0.035, 0.02, 0.40),        # 暖墨压暗，油画仍透出来
	"DIM": Color(0.04, 0.03, 0.02, 0.62),
	"BTN": Color(0.098, 0.090, 0.090, 0.96),       # 墨钮 #191717（= btn_ink_normal 中段）
	"BTN_HI": Color(0.137, 0.122, 0.106, 0.98),
	"BTN_DOWN": Color(0.051, 0.043, 0.035, 1.0),   # 焦墨 #0d0b09
	"INK_SOLID": Color(0.051, 0.043, 0.035, 1.0),
	"SIZE_PORT": 54,                               # 港名在墨刷底上，放大（44 撑不起约 330×110 的墨团，第 1 轮返工改 54）
	"SIZE_HEAD": 28,
	"SIZE_CARD": 22,
	"SIZE_BODY": 18,
	"SIZE_FOOT": 14,                               # 文楷 13 太细，14 起
	"LINE_BODY": 6,
}

const _P: Dictionary = JUANBEN if IS_JUANBEN else YECHAO

const INK: Color = _P["INK"]
const INK_SOFT: Color = _P["INK_SOFT"]
const TIDE: Color = _P["TIDE"]
const GOLD: Color = _P["GOLD"]
const GOLD_HI: Color = _P["GOLD_HI"]
const TEXT: Color = _P["TEXT"]
const TEXT_DIM: Color = _P["TEXT_DIM"]
const SEAL: Color = _P["SEAL"]
const SEAL_HI: Color = _P["SEAL_HI"]
const SEAL_TEXT: Color = _P["SEAL_TEXT"]
const MOSS: Color = _P["MOSS"]
const HONEY: Color = _P["HONEY"]
const CINNABAR: Color = _P["CINNABAR"]
const VEIL: Color = _P["VEIL"]
const DIM: Color = _P["DIM"]
const BTN: Color = _P["BTN"]
const BTN_HI: Color = _P["BTN_HI"]
const BTN_DOWN: Color = _P["BTN_DOWN"]
const INK_SOLID: Color = _P["INK_SOLID"]

# 字阶从 Main.tscn 实测收口。标题页大题仍可单独加大。
const SIZE_PORT: int = _P["SIZE_PORT"]
const SIZE_HEAD: int = _P["SIZE_HEAD"]
const SIZE_CARD: int = _P["SIZE_CARD"]
const SIZE_BODY: int = _P["SIZE_BODY"]
const SIZE_FOOT: int = _P["SIZE_FOOT"]
const LINE_BODY: int = _P["LINE_BODY"]

## 宣纸上的字色（绢本工席用；夜潮没有浅底，按原色）。按「未点亮」的宣纸卡 #dbcaa8 实测全部 ≥5.3:1。
const PAPER_TEXT := Color(0.102, 0.086, 0.071)      # 墨 #1a1612
const PAPER_DIM := Color(0.227, 0.180, 0.122)       # 注文 #3a2e1f（第 1 轮返工由 #4f402c 加深：文楷 14 在纸上实渲染只剩 3.6–4.1）
const PAPER_TIDE := Color(0.122, 0.227, 0.302)      # 靛青 #1f3a4d
const PAPER_GOLD := Color(0.361, 0.263, 0.059)      # 赭金 #5c430f
const PAPER_MOSS := Color(0.157, 0.314, 0.184)      # 石绿（深）#28502f
const PAPER_HONEY := Color(0.431, 0.235, 0.063)     # 赭 #6e3c10
const PAPER_CINNABAR := Color(0.557, 0.141, 0.125)  # 朱砂深 #8e2420
## 未点亮的宣纸卡（panel_paper 中段 #ebdec1 × 卡的压暗 0.93/0.91/0.87），量纸上字色用它。
const PAPER_CARD := Color(0.859, 0.792, 0.659)
## 港页岸门（工席）的纸面再压一档到旧绢调：宣纸是港画上最亮的一块，抢画（第 2 轮美术 minor 1）。self_modulate 只染纸面不染字。
## 压到 (0.95,0.93,0.89) 为止：再深，纸上朱砂深字（「船还开不出去」）对纸只剩 4.36:1（smoke 实测）
const DOOR_PAPER_TINT := Color(0.95, 0.93, 0.89)

const FONT_BODY_PATH := "res://assets/fonts/LXGWWenKai-Medium.ttf"
const FONT_TITLE_PATH := "res://assets/fonts/MaShanZheng-Regular.ttf"
const NK1_THEME_PATH := "res://assets/theme/nk1_theme.tres"
const TEX_DIR := "res://assets/theme/tex/"

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
static var _title_font: Font
static var _bold_font: Font
static var _sys_font: Font
static var _theme: Theme
static var _tex_cache: Dictionary = {}


## 系统 CJK 回落（夜潮正文用）。整个会话只建一个：每个 SystemFont 量行高时都会把整本系统字库
## （宋体 Songti.ttc 66.9MB）读进内存，建两个就是两份（第 2 轮工程 M1）。
static func _system_font() -> Font:
	if _sys_font != null:
		return _sys_font
	var f := SystemFont.new()
	f.font_names = _FONT_NAMES
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	_sys_font = f
	return f


static func _font_file(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Font


## 正文字体。绢本：霞鹜文楷子集；夜潮：系统字体。
## 绢本不挂 SystemFont 回落：文楷子集汉字零缺字（subset_fonts.py --verify），FontFile 默认 allow_system_fallback，
## 真缺字（个别符号）时由 TextServer 按字懒加载系统字。原先正文与粗体各挂一个 SystemFont，一量行高就各读一整本宋体，
## 静态内存多出约 128MB（第 2 轮工程 M1，探针实测）。
static func font() -> Font:
	if _font == null:
		var body: Font = _font_file(FONT_BODY_PATH) if IS_JUANBEN else null
		if body == null:
			_font = _system_font()
		else:
			var v := FontVariation.new()
			v.base_font = body
			_font = v
	return _font


## 标题字体：马善政，缺字（祐、恮等）落回文楷。夜潮没有标题字，等于 font()。
static func title_font() -> Font:
	if _title_font == null:
		var head: Font = _font_file(FONT_TITLE_PATH) if IS_JUANBEN else null
		if head == null:
			_title_font = font()
		else:
			var v := FontVariation.new()
			v.base_font = head
			var fb: Array[Font] = [font()]
			v.fallbacks = fb
			_title_font = v
	return _title_font


static var _seal_fonts: Dictionary = {}
static var _body_spaced: Dictionary = {}


## 正文字加字距（px）：册页小题「第二章・旧账」这类短题，16px 文楷字挤在一起显碎（第 2 轮美术 minor 3）。
static func body_spaced(spacing: int) -> Font:
	if _body_spaced.has(spacing):
		return _body_spaced[spacing]
	var v := FontVariation.new()
	v.base_font = font()
	v.spacing_glyph = spacing
	_body_spaced[spacing] = v
	return v


## 印钮上的字：标题字加字距（px）。「开卷」这类两字印面，字挤在中间显得印面空（第 1 轮评审）。
## 字距加在每个字后面，按钮居中时整串略偏左 spacing/2，对两三字的印钮看不出来。
static func seal_font(spacing: int) -> Font:
	if _seal_fonts.has(spacing):
		return _seal_fonts[spacing]
	var base := title_font()
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = spacing
	_seal_fonts[spacing] = v
	return v


## 富文本 [b] 用的粗体：文楷加粗一档（夜潮与正文同一字体）。
static func _bold() -> Font:
	if _bold_font == null:
		var body: Font = _font_file(FONT_BODY_PATH) if IS_JUANBEN else null
		if body == null:
			_bold_font = font()
		else:
			var v := FontVariation.new()
			v.base_font = body
			v.variation_embolden = 0.45
			_bold_font = v
	return _bold_font


static func hex(c: Color) -> String:
	return c.to_html(false)


## 挂到场景根上。缺的项继续落到引擎默认主题，这里只锁字体、钮和分隔线。
static func apply(node: Control) -> void:
	node.theme = theme()


static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = _theme_juanben() if IS_JUANBEN else _theme_yechao()
	return _theme


static func _theme_yechao() -> Theme:
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
	return t


## 绢本主题：以第一轮 nk1_theme.tres 为底（窗口题签、滚动条、提示小笺、页签、type variation 全在里面），
## 再按本表锁正文字体、字阶与字色。nk1_theme 不在时按同一色板用委角平面盒兜底。
static func _theme_juanben() -> Theme:
	var t: Theme = null
	if ResourceLoader.exists(NK1_THEME_PATH):
		var base = load(NK1_THEME_PATH)
		if base is Theme:
			t = (base as Theme).duplicate()
	var from_nk1 := t != null
	if t == null:
		t = Theme.new()
	var f := font()
	t.default_font = f
	t.default_font_size = SIZE_BODY

	t.set_font("font", "Label", f)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_color("font_color", "Label", TEXT)

	t.set_font("font", "Button", f)
	t.set_font_size("font_size", "Button", SIZE_BODY)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_HI)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", _DISABLED_ON_INK)
	t.set_color("font_focus_color", "Button", TEXT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "Button", _ink_button_box(state))
	t.set_stylebox("focus", "Button", _focus_box())

	t.set_font("normal_font", "RichTextLabel", f)
	t.set_font("bold_font", "RichTextLabel", _bold())
	t.set_font("italics_font", "RichTextLabel", f)
	t.set_font("bold_italics_font", "RichTextLabel", _bold())
	t.set_font_size("normal_font_size", "RichTextLabel", SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", SIZE_BODY)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_constant("line_separation", "RichTextLabel", LINE_BODY)

	if not from_nk1:
		var rule := StyleBoxLine.new()
		rule.color = Color(GOLD, 0.40)
		rule.thickness = 1
		t.set_stylebox("separator", "HSeparator", rule)
		t.set_stylebox("separator", "VSeparator", rule)
		var track := _flat(Color(0.05, 0.04, 0.03, 0.55), Color(0, 0, 0, 0), 2, 0)
		var grab := _flat(Color(GOLD, 0.80), Color(0, 0, 0, 0), 2, 0)
		var grab_hi := _flat(GOLD_HI, Color(0, 0, 0, 0), 2, 0)
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
		t.set_stylebox("panel", "PopupMenu", panel())
		t.set_stylebox("hover", "PopupMenu", _flat(Color(GOLD, 0.22), Color(0, 0, 0, 0), 2, 0))
		t.set_stylebox("panel", "AcceptDialog", _dialog_box())
		t.set_color("title_color", "AcceptDialog", GOLD_HI)
		t.set_font("title_font", "AcceptDialog", title_font())
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD_HI)
	t.set_font("font", "PopupMenu", f)
	t.set_font_size("font_size", "PopupMenu", SIZE_FOOT)
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


# ── 绢本用的小件 ────────────────────────────────────────

## 墨底上不可用的字（#9a9080，不可用控件不要求 4.5:1）。
const _DISABLED_ON_INK := Color(0.604, 0.565, 0.502)


## 委角平面盒：corner_detail=1 让圆角退成一刀斜切，绢本里所有平面盒都用它，不出圆角胶囊。
static func _chamfer(bg: Color, border: Color, cut: int, bw := 1) -> StyleBoxFlat:
	var st := _flat(bg, border, cut, bw)
	st.corner_detail = 1
	st.anti_aliasing = true
	return st


static func _tex(tex_name: String) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var path := TEX_DIR + tex_name + ".res"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[tex_name] = tex
	return tex


## 2× 九宫（build_theme.gd 已把贴图包成 size_override=½），margin / content / expand 都按逻辑像素。
## 贴图缺了返回 fallback（委角平面盒）。
static func _nine(tex_name: String, margin: Vector4, content: Vector4, expand: Vector4, fallback: StyleBox, tile_v := true) -> StyleBox:
	var tex := _tex(tex_name)
	if tex == null:
		return fallback
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.texture_margin_left = margin.x
	st.texture_margin_top = margin.y
	st.texture_margin_right = margin.z
	st.texture_margin_bottom = margin.w
	st.content_margin_left = content.x
	st.content_margin_top = content.y
	st.content_margin_right = content.z
	st.content_margin_bottom = content.w
	st.expand_margin_left = expand.x
	st.expand_margin_top = expand.y
	st.expand_margin_right = expand.z
	st.expand_margin_bottom = expand.w
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	if tile_v:
		st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return st


## 靛墨面板（panel_ink：半透明靛墨 + 泥金内线 + 包角金钩）。content 由调用方给，保持原版面尺寸。
## dense=true：面板内里垫到不透明度 0.96（与夜潮 INK 相同），浮在港页上的册页不再透出后面的港名与门。
static func _ink_panel(content: Vector4, dense := false) -> StyleBox:
	var fb := _chamfer(INK, Color(GOLD, 0.55), 4)
	fb.content_margin_left = content.x
	fb.content_margin_top = content.y
	fb.content_margin_right = content.z
	fb.content_margin_bottom = content.w
	var st := _nine("panel_ink", Vector4(20, 20, 20, 20), content, Vector4(4, 4, 4, 4), fb)
	if dense and st is StyleBoxTexture:
		var solid := _dense_ink()
		if solid != null:
			(st as StyleBoxTexture).texture = solid
	return st


static var _dense_ink_tex: Texture2D
static var _dense_ink_tried := false


## panel_ink 垫一层同色实墨：外沿（投影与干笔框，贴图外圈 10px）不动，内里 alpha 抬到 ≥0.96。
static func _dense_ink() -> Texture2D:
	if _dense_ink_tried:
		return _dense_ink_tex
	_dense_ink_tried = true
	var base := _tex("panel_ink")
	if base == null:
		return null
	var img := base.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var inset := 10
	var under := Image.create(w, h, false, Image.FORMAT_RGBA8)
	under.fill_rect(Rect2i(inset, inset, w - inset * 2, h - inset * 2), Color(INK, 0.96))
	under.blend_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var it := ImageTexture.create_from_image(under)
	it.set_size_override(Vector2i(base.get_size()))
	_dense_ink_tex = it
	return it


## 宣纸卡（panel_paper：焦墨干笔框 + 角钩）。lit=false 时压暗一成，悬停时点亮，像纸被灯照到。
static func _paper(content: Vector4, lit: bool) -> StyleBox:
	var fb := _chamfer(Color(0.914, 0.863, 0.753), Color(0.051, 0.043, 0.035, 0.85), 4, 2)
	fb.content_margin_left = content.x
	fb.content_margin_top = content.y
	fb.content_margin_right = content.z
	fb.content_margin_bottom = content.w
	if not lit:
		fb.bg_color = Color(0.86, 0.81, 0.70)
	var st := _nine("panel_paper", Vector4(20, 20, 20, 20), content, Vector4(5, 5, 5, 5), fb)
	var paper := st as StyleBoxTexture
	if paper != null:
		paper.modulate_color = Color(1, 1, 1) if lit else Color(0.93, 0.91, 0.87)
		if lit:
			paper.expand_margin_left = 6
			paper.expand_margin_top = 6
			paper.expand_margin_right = 6
			paper.expand_margin_bottom = 6
	return st


## 墨钮四态（btn_ink_*：墨底泥金边，委角，横向刷痕）。
static func _ink_button_box(state: String) -> StyleBox:
	var bg := BTN
	var edge := Color(GOLD, 0.45)
	match state:
		"hover":
			bg = BTN_HI
			edge = Color(GOLD_HI, 0.85)
		"pressed":
			bg = BTN_DOWN
			edge = Color(GOLD, 0.55)
		"disabled":
			bg = Color(BTN, 0.55)
			edge = Color(GOLD, 0.15)
	var fb := _chamfer(bg, edge, 5)
	var top := 8 if state == "pressed" else 7
	fb.content_margin_left = 14
	fb.content_margin_right = 14
	fb.content_margin_top = top
	fb.content_margin_bottom = 14 - top
	return _nine("btn_ink_" + state, Vector4(12, 10, 12, 10), Vector4(14, top, 14, 14 - top), Vector4.ZERO, fb, false)


## 朱砂主钮四态（btn_seal_*）。
static func _seal_button_box(state: String) -> StyleBox:
	var bg := SEAL
	match state:
		"hover":
			bg = SEAL_HI
		"pressed":
			bg = Color(0.525, 0.133, 0.114)
		"disabled":
			bg = Color(0.48, 0.21, 0.18, 0.82)
	var fb := _chamfer(bg, Color(0.93, 0.78, 0.62, 0.55), 5)
	var top := 8 if state == "pressed" else 7
	fb.content_margin_left = 14
	fb.content_margin_right = 14
	fb.content_margin_top = top
	fb.content_margin_bottom = 14 - top
	return _nine("btn_seal_" + state, Vector4(12, 10, 12, 10), Vector4(14, top, 14, 14 - top), Vector4.ZERO, fb, false)


## 焦点：四角泥金角钩（focus_frame，中空）。
static func _focus_box() -> StyleBox:
	var fb := _chamfer(Color(0, 0, 0, 0), Color(GOLD_HI, 0.85), 5)
	fb.draw_center = false
	var st := _nine("focus_frame", Vector4(10, 10, 10, 10), Vector4(0, 0, 0, 0), Vector4(4, 4, 4, 4), fb)
	if st is StyleBoxTexture:
		(st as StyleBoxTexture).draw_center = false
	return st


## 弹窗正文底：不透明靛墨（嵌入式窗口内容区先清成引擎灰，半透明会透灰）。
static func _dialog_box() -> StyleBox:
	var fb := _chamfer(INK_SOLID, Color(GOLD, 0.45), 2)
	fb.content_margin_left = 16
	fb.content_margin_right = 16
	fb.content_margin_top = 12
	fb.content_margin_bottom = 12
	return _nine("tex_ink_solid", Vector4(0, 0, 0, 0), Vector4(16, 12, 16, 12), Vector4.ZERO, fb)


# ── 面板与卡 ────────────────────────────────────────────
# 返回类型是 StyleBox：绢本给 StyleBoxTexture，夜潮仍是原来的 StyleBoxFlat。
# 调用点只把它交给 add_theme_stylebox_override，不读平面盒专有字段。

## 夜潮面板：潮光细边，从画上浮起来，底图不再透进字里。
## 绢本：靛墨面板，泥金内线与包角，内容边距与原版相同（1），版面不变。
static func panel() -> StyleBox:
	if IS_JUANBEN:
		return _ink_panel(Vector4(1, 1, 1, 1), true)
	var st := _flat(INK, Color(TIDE, 0.55), 2)
	st.shadow_color = Color(0, 0, 0, 0.40)
	st.shadow_size = 8
	st.shadow_offset = Vector2(0, 3)
	return st


## 港名匾、卷首不用大圆角。
static func plaque() -> StyleBox:
	if IS_JUANBEN:
		return _ink_panel(Vector4(28, 6, 28, 6))
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


static func icon_frame() -> StyleBox:
	if IS_JUANBEN:
		# 小画框：焦墨底 + 泥金细边，委角。
		var fr := _chamfer(INK_SOLID, Color(GOLD, 0.78), 3, 1)
		fr.content_margin_left = 2
		fr.content_margin_right = 2
		fr.content_margin_top = 2
		fr.content_margin_bottom = 2
		fr.shadow_color = Color(0, 0, 0, 0.35)
		fr.shadow_size = 3
		fr.shadow_offset = Vector2(0, 1)
		return fr
	var st := _flat(Color(0.04, 0.10, 0.15, 1.0), Color(TIDE, 0.72), 2, 1)
	st.content_margin_left = 2
	st.content_margin_right = 2
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	return st


static func log_well() -> StyleBox:
	if IS_JUANBEN:
		var well := _chamfer(Color(0.035, 0.03, 0.025, 0.72), Color(GOLD, 0.26), 3, 1)
		well.content_margin_left = 8
		well.content_margin_right = 8
		well.content_margin_top = 6
		well.content_margin_bottom = 6
		return well
	var st := _flat(Color(0.03, 0.08, 0.12, 0.78), Color(TIDE, 0.28), 2, 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	return st


## 港卡。绢本是宣纸卡（压暗一成），悬停点亮。
static func card() -> StyleBox:
	if IS_JUANBEN:
		return _paper(Vector4(8, 5, 8, 5), false)
	var st := _flat(INK_SOFT, Color(TIDE, 0.90), 16, 0)
	st.border_width_left = 3
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


static func card_hover() -> StyleBox:
	if IS_JUANBEN:
		return _paper(Vector4(8, 5, 8, 5), true)
	var st := _flat(BTN_HI, Color(TIDE, 1.0), 16, 0)
	st.border_width_left = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	return st


## 岸上开着的门。夜潮：潮光边，深青底，半径 16。绢本：宣纸卡，内容边距 2（与夜潮边宽相同）。
static func shore_door() -> StyleBox:
	if IS_JUANBEN:
		return _paper(Vector4(2, 2, 2, 2), false)
	return _flat(INK, TIDE, 16, 2)


## 岸门悬停。底抬一档，边仍是潮光。绢本：纸被照亮、微微浮起。
static func shore_door_hover() -> StyleBox:
	if IS_JUANBEN:
		return _paper(Vector4(2, 2, 2, 2), true)
	return _flat(BTN_HI, TIDE, 16, 2)


## 今日没开的门。暗边，字另用旁注色。
static func shore_shut() -> StyleBox:
	if IS_JUANBEN:
		var shut := _chamfer(Color(0.05, 0.043, 0.035, 0.66), Color(GOLD, 0.22), 4, 1)
		shut.content_margin_left = 10
		shut.content_margin_right = 10
		shut.content_margin_top = 4
		shut.content_margin_bottom = 4
		return shut
	var st := _flat(INK, BTN, 16, 1)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	return st


## 航向牌。未选中暗边，选中潮光边。半径与港卡同为 16。
## 绢本：暖墨委角牌，未选中泥金淡边（第 1 轮返工加到 0.5，平涂石板色不再没有泥金细节），选中泥金实边两道宽。
static func heading_card(selected: bool) -> StyleBox:
	if IS_JUANBEN:
		var hc := _chamfer(INK if selected else Color(INK, 0.90),
			GOLD_HI if selected else Color(GOLD, 0.50), 8, 2 if selected else 1)
		hc.content_margin_left = 14
		hc.content_margin_right = 12
		hc.content_margin_top = 10
		hc.content_margin_bottom = 10
		hc.shadow_color = Color(0, 0, 0, 0.45 if selected else 0.30)
		hc.shadow_size = 8 if selected else 4
		hc.shadow_offset = Vector2(0, 2)
		return hc
	var edge := TIDE if selected else BTN
	var st := _flat(INK, edge, 16, 2 if selected else 1)
	st.content_margin_left = 14
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	return st


# ── 画面上的大字：港名墨刷底、标题书法、标题屏墨晕 ─────────────

const UI_DIR := "res://assets/ui/nk1/"
static var _half_cache: Dictionary = {}


## 2× 独立图（墨迹、logo）包成逻辑尺寸的 ImageTexture，给 StyleBoxTexture 当九宫用。
## StyleBoxTexture 的边距按贴图尺寸切、按画布像素画，2× 原图不减半会把笔头放大一倍。
static func _half_tex(png_name: String) -> Texture2D:
	if _half_cache.has(png_name):
		return _half_cache[png_name]
	var out: Texture2D = null
	var path := UI_DIR + png_name
	if ResourceLoader.exists(path):
		var src := load(path) as Texture2D
		var img: Image = src.get_image() if src != null else null
		# headless（假渲染器）下贴图没有像素，拿不到就回落，不报错
		if img != null and not img.is_empty():
			var it := ImageTexture.create_from_image(img)
			it.set_size_override(Vector2i(Vector2(img.get_size()) * 0.5))
			out = it
	_half_cache[png_name] = out
	return out


## 港名匾。夜潮同 plaque()。绢本：港名墨刷底 ink_splash_plate（近水平一笔，左笔头右飞白）。
## 九宫：笔头 48、飞白收锋 231 不拉伸，中段实心墨随字宽伸缩；字落在实心段（安全区 x 12–538）里。
static func port_plaque() -> StyleBox:
	if not IS_JUANBEN:
		return plaque()
	var tex := _half_tex("ink_splash_plate.png")
	if tex == null:
		return plaque()
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.texture_margin_left = 48
	st.texture_margin_top = 20
	st.texture_margin_right = 231
	st.texture_margin_bottom = 36
	st.content_margin_left = 104
	st.content_margin_top = 22
	st.content_margin_right = 176
	st.content_margin_bottom = 34
	return st


## 标题屏衬底。夜潮同 plaque()。绢本：一团淡墨晕（ink_splash_wash），不画框。
static func title_plaque() -> StyleBox:
	if not IS_JUANBEN:
		return plaque()
	var tex := _half_tex("ink_splash_wash.png")
	if tex == null:
		return plaque()
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.modulate_color = Color(1, 1, 1, 0.82)
	st.expand_margin_left = 90
	st.expand_margin_right = 90
	st.expand_margin_top = 40
	st.expand_margin_bottom = 50
	return st


## 标题书法（泥金字墨描边，末钤「立志」白文印）。夜潮返回 null，调用方照旧用文字标题。
## 只替「东亚海域立志传」这一个题名（LOGO_TEXT）；四方沙盘（cg_world_*）的标题仍用文字，由 sync_title_logo() 切换。
const LOGO_TEXT := "东亚海域立志传"


static func title_logo() -> TextureRect:
	if not IS_JUANBEN:
		return null
	var path := UI_DIR + "logo_title_h_gold.png"
	if not ResourceLoader.exists(path):
		return null
	var logo := TextureRect.new()
	logo.name = "TitleLogo"
	logo.texture = load(path)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.custom_minimum_size = Vector2(640, 174)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return logo


## 标题文字换过之后调一次：题名是 LOGO_TEXT 时显示书法、藏起文字，否则反过来。没有书法节点（夜潮）时什么都不做。
static func sync_title_logo(main_title: Label) -> void:
	var parent := main_title.get_parent()
	var logo := parent.get_node_or_null("TitleLogo") as Control if parent != null else null
	if logo == null:
		return
	logo.visible = main_title.text.strip_edges() == LOGO_TEXT
	main_title.visible = not logo.visible


## 立绘裱框（portrait_frame：旧绢裱边 + 双泥金线 + 靛墨名牌）。夜潮返回 false，调用方的原画框不动。
## 绢本：frame 定成 296×400，立绘恰落在窗口 (20,20) 256×320；名牌 (48,350)–(248,388) 上挂一个
## 名为 NamePlate/Name 的 Label，由调用方写人名。
static func frame_portrait(frame: PanelContainer, portrait: TextureRect) -> bool:
	if not IS_JUANBEN:
		return false
	var tex := _half_tex("portrait_frame.png")
	if tex == null:
		return false
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.texture_margin_left = 20
	st.texture_margin_top = 20
	st.texture_margin_right = 20
	st.texture_margin_bottom = 60
	st.content_margin_left = 20
	st.content_margin_top = 20
	st.content_margin_right = 20
	st.content_margin_bottom = 60
	frame.add_theme_stylebox_override("panel", st)
	frame.custom_minimum_size = Vector2(296, 400)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = false
	portrait.custom_minimum_size = Vector2(256, 320)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if frame.get_node_or_null("NamePlate") == null:
		# PanelContainer 把子节点排进窗口；名牌在窗口外，挂在一个不参与排版的 Control 下按窗口原点偏移。
		var plate := Control.new()
		plate.name = "NamePlate"
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(plate)
		var name_lbl := Label.new()
		name_lbl.name = "Name"
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.position = Vector2(28, 330)
		name_lbl.size = Vector2(200, 38)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_override("font", title_font())
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", GOLD_HI)
		name_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		plate.add_child(name_lbl)
	return true


## 直接压在画面上的字（标题屏引言等）：焦墨紧描边 + 墨晕。夜潮不动。
static func style_overlay(lbl: Label) -> void:
	if not IS_JUANBEN:
		return
	lbl.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_shadow_color", Color(0.051, 0.043, 0.035, 0.55))
	lbl.add_theme_constant_override("shadow_outline_size", 10)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


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
## 珊瑚上必须是深字。主题默认 font_focus_color 是壳白，不覆盖的话
## Tab 聚焦或按下时白字叠珊瑚，对比约 2.2:1。
## 绢本：accent=朱砂印钮（马善政、印面字 SEAL_TEXT，朱砂上 ≥4.8:1），其余墨钮泥金边。
static func style_button(btn: Button, accent := false) -> void:
	if IS_JUANBEN:
		_style_button_juanben(btn, accent)
		return
	_paint_font(btn)
	var ink := INK_SOLID if accent else TEXT
	if accent:
		btn.add_theme_stylebox_override("normal", _button_box(SEAL, Color(1, 0.78, 0.70, 0.45)))
		btn.add_theme_stylebox_override("hover", _button_box(SEAL_HI, Color(1, 0.86, 0.80, 0.70)))
		btn.add_theme_stylebox_override("pressed", _button_box(Color(1.0, 0.376, 0.251), Color(1, 0.70, 0.60, 0.40)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(0.35, 0.18, 0.16, 0.55), Color(TIDE, 0.12)))
		btn.add_theme_stylebox_override("focus", _button_box(SEAL_HI, Color(TIDE, 0.7)))
	else:
		btn.add_theme_stylebox_override("normal", _button_box(BTN, Color(TIDE, 0.35)))
		btn.add_theme_stylebox_override("hover", _button_box(BTN_HI, Color(TIDE, 0.85)))
		btn.add_theme_stylebox_override("pressed", _button_box(BTN_DOWN, Color(TIDE, 0.45)))
		btn.add_theme_stylebox_override("disabled", _button_box(Color(BTN_DOWN, 0.55), Color(TIDE, 0.12)))
		btn.add_theme_stylebox_override("focus", _button_box(BTN_HI, Color(TIDE, 0.85)))
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink)
	btn.add_theme_color_override("font_pressed_color", ink)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", ink)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func _style_button_juanben(btn: Button, accent: bool) -> void:
	if accent:
		# 朱砂印钮：马善政加字距（印面不空），字号 ≥22；大主钮（开卷）由调用方再放到 28
		btn.add_theme_font_override("font", seal_font(4))
		btn.add_theme_font_size_override("font_size", 22)
		for state in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, _seal_button_box(state))
		btn.add_theme_stylebox_override("focus", _focus_box())
		btn.add_theme_color_override("font_color", SEAL_TEXT)
		btn.add_theme_color_override("font_hover_color", SEAL_TEXT)
		btn.add_theme_color_override("font_pressed_color", SEAL_TEXT)
		btn.add_theme_color_override("font_focus_color", SEAL_TEXT)
		btn.add_theme_color_override("font_hover_pressed_color", SEAL_TEXT)
		btn.add_theme_color_override("font_disabled_color", Color(SEAL_TEXT, 0.55))
		# 印面字加一圈朱褐描边，亮画面上也不糊。
		btn.add_theme_color_override("font_outline_color", Color(0.35, 0.06, 0.05, 0.55))
		btn.add_theme_constant_override("outline_size", 2)
	else:
		_paint_font(btn)
		for state in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, _ink_button_box(state))
		btn.add_theme_stylebox_override("focus", _focus_box())
		if btn.toggle_mode:
			# 页签式开关钮（海图「针路 / 外洋 / 傍岸」）：选中态用不透明焦墨底 + 两道亮泥金边——
			# 原先选中走 btn_ink_pressed 半透明贴图，透出底下地名的笔画（第 2 轮美术 M5）
			var on := _chamfer(BTN_DOWN, GOLD_HI, 5, 2)
			on.content_margin_left = 14
			on.content_margin_right = 14
			on.content_margin_top = 8
			on.content_margin_bottom = 6
			btn.add_theme_stylebox_override("pressed", on)
			btn.add_theme_stylebox_override("hover_pressed", on)
		btn.add_theme_color_override("font_color", TEXT)
		btn.add_theme_color_override("font_hover_color", GOLD_HI)
		btn.add_theme_color_override("font_pressed_color", GOLD)
		btn.add_theme_color_override("font_focus_color", TEXT)
		btn.add_theme_color_override("font_hover_pressed_color", GOLD_HI)
		btn.add_theme_color_override("font_disabled_color", _DISABLED_ON_INK)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 牙行价目上的小钮，不能用正文钮的大内边距，否则一行排不下。
## 绢本：小钮贴在宣纸工席上——墨钮泥金边 / 朱砂小印，委角平面盒（九宫角在 22 高里会挤坏）。
static func style_chip(btn: Button, accent := false) -> void:
	_paint_font(btn)
	if IS_JUANBEN:
		_style_chip_juanben(btn, accent)
		return
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
	var ink := INK_SOLID if accent else TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink)
	btn.add_theme_color_override("font_pressed_color", ink)
	btn.add_theme_color_override("font_focus_color", ink)
	btn.add_theme_color_override("font_disabled_color", TEXT_DIM)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func _style_chip_juanben(btn: Button, accent: bool) -> void:
	var mk := func(bg: Color, edge: Color, top: int) -> StyleBoxFlat:
		var st := _chamfer(bg, edge, 3, 1)
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = top
		st.content_margin_bottom = 4 - top
		return st
	if accent:
		btn.add_theme_stylebox_override("normal", mk.call(Color(0.655, 0.176, 0.149), Color(0.35, 0.06, 0.05, 0.70), 2))
		btn.add_theme_stylebox_override("hover", mk.call(SEAL_HI, Color(0.93, 0.78, 0.62, 0.70), 2))
		btn.add_theme_stylebox_override("pressed", mk.call(Color(0.525, 0.133, 0.114), Color(0.35, 0.06, 0.05, 0.80), 3))
		btn.add_theme_stylebox_override("focus", mk.call(SEAL_HI, Color(GOLD_HI, 0.85), 2))
	else:
		btn.add_theme_stylebox_override("normal", mk.call(Color(0.110, 0.094, 0.078, 0.96), Color(GOLD, 0.55), 2))
		btn.add_theme_stylebox_override("hover", mk.call(Color(0.176, 0.149, 0.114, 1.0), Color(GOLD_HI, 0.90), 2))
		btn.add_theme_stylebox_override("pressed", mk.call(BTN_DOWN, Color(GOLD, 0.60), 3))
		btn.add_theme_stylebox_override("focus", mk.call(Color(0.176, 0.149, 0.114, 1.0), Color(GOLD_HI, 0.90), 2))
	# 不可用：宣纸上一道淡墨框，字用纸上注文色（小钮只出现在宣纸工席上）。
	btn.add_theme_stylebox_override("disabled", mk.call(Color(0.051, 0.043, 0.035, 0.08), Color(0.051, 0.043, 0.035, 0.30), 2))
	# 热区至少 64×32、字 16（「见」「记录」原先只有 30×24 / 44×24，第 1 轮评审 UX M6）
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(maxf(btn.custom_minimum_size.x, 64.0), maxf(btn.custom_minimum_size.y, 32.0))
	var ink := SEAL_TEXT if accent else TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink if accent else GOLD_HI)
	btn.add_theme_color_override("font_pressed_color", ink)
	btn.add_theme_color_override("font_focus_color", ink)
	btn.add_theme_color_override("font_hover_pressed_color", ink)
	btn.add_theme_color_override("font_disabled_color", Color(PAPER_DIM, 0.75))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 弹出的册页 / 浮层：0.18 秒淡入，外加 0.98→1 的微缩放（第 1 轮评审 M4：册页原先一帧弹出）。
## headless 与 -s 工具脚本（门禁、巡检）下什么都不做：它们量的是排版与状态，不等动画。
static func pop_in(ctrl: Control, dur := 0.18) -> void:
	if ctrl == null or not ctrl.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var ml := Engine.get_main_loop()
	if ml != null and ml.get_script() != null:
		return
	ctrl.modulate.a = 0.0
	ctrl.scale = Vector2(0.98, 0.98)
	var center_pivot := func() -> void:
		if is_instance_valid(ctrl):
			ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.get_tree().process_frame.connect(center_pivot, CONNECT_ONE_SHOT)
	var tw := ctrl.create_tween().set_parallel(true)
	tw.tween_property(ctrl, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2.ONE, dur + 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 滚动区底边渐隐：返回一个包好的 Control（调用方把它加进版面，代替直接加 scroll）。
## 还有下文时底边 px 高一道墨色渐隐，滚到底或本来就放得下时收起。
static func fade_scroll(scroll: ScrollContainer, px := 24) -> Control:
	var wrap := Control.new()
	wrap.name = "FadeScroll"
	wrap.custom_minimum_size = scroll.custom_minimum_size
	wrap.size_flags_horizontal = scroll.size_flags_horizontal
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(scroll)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color(INK, 0.0))
	grad.set_color(1, Color(INK, 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 32
	var fade := TextureRect.new()
	fade.name = "BottomFade"
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fade.offset_top = -px
	fade.offset_right = -10  # 让开滚动条
	fade.visible = false
	wrap.add_child(fade)
	var bar := scroll.get_v_scroll_bar()
	var refresh := func() -> void:
		if not is_instance_valid(fade) or not is_instance_valid(bar):
			return
		fade.visible = bar.max_value - bar.page > 2.0 and bar.value < bar.max_value - bar.page - 2.0
	bar.value_changed.connect(func(_v: float) -> void: refresh.call())
	bar.changed.connect(refresh)
	return wrap


## 「离开 / 返回上一处」这类短钮：绢本走墨钮（居中、委角泥金边、实底），与旁边的「明日再看」同一种钮，
## 不再用挑签（字左对齐、无角钩、底色半透明会透出面板底饰）；夜潮仍是挑签，原样不变。
static func style_leave_button(btn: Button) -> void:
	if not IS_JUANBEN:
		style_choice_button(btn)
		return
	style_button(btn, false)
	btn.add_theme_font_size_override("font_size", SIZE_BODY)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if btn.custom_minimum_size.x < 120:
		btn.custom_minimum_size = Vector2(maxf(btn.custom_minimum_size.x, 140), maxf(btn.custom_minimum_size.y, 42))


## 剧情选项「挑签」：静息潮光线，hover 左杠加宽、正文右让一截。
## 绢本：墨签泥金线，左杠泥金。
static func _choice_box(hover: bool) -> StyleBoxFlat:
	if IS_JUANBEN:
		var cb := _flat(
			BTN_HI if hover else Color(BTN, 0.92),
			Color(GOLD_HI, 0.95) if hover else Color(GOLD, 0.40),
			0
		)
		cb.border_width_left = 6 if hover else 3
		cb.border_width_top = 1
		cb.border_width_right = 1
		cb.border_width_bottom = 1
		cb.content_margin_left = 20 if hover else 12
		cb.content_margin_right = 14
		cb.content_margin_top = 8
		cb.content_margin_bottom = 8
		return cb
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
	btn.add_theme_color_override("font_hover_color", GOLD_HI if IS_JUANBEN else TEXT)
	btn.add_theme_color_override("font_pressed_color", GOLD_HI if IS_JUANBEN else TEXT)
	btn.add_theme_color_override("font_disabled_color", _DISABLED_ON_INK if IS_JUANBEN else TEXT_DIM)
	btn.add_theme_color_override("font_focus_color", GOLD_HI if IS_JUANBEN else TEXT)
	btn.add_theme_font_size_override("font_size", SIZE_BODY)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 抬头。绢本：马善政亮泥金，焦墨细描边，画面上也站得住；港名（port=true）是墨刷底上的宣纸大字。
static func style_heading(lbl: Label, port := false) -> void:
	if IS_JUANBEN:
		lbl.add_theme_font_override("font", title_font())
		lbl.add_theme_font_size_override("font_size", SIZE_PORT if port else SIZE_HEAD)
		lbl.add_theme_color_override("font_color", TEXT if port else GOLD_HI)
		lbl.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		return
	_paint_font(lbl)
	lbl.add_theme_font_size_override("font_size", SIZE_PORT if port else SIZE_HEAD)
	lbl.add_theme_color_override("font_color", GOLD)


static func style_body(rtl: RichTextLabel) -> void:
	var f := font()
	rtl.add_theme_font_override("normal_font", f)
	rtl.add_theme_font_override("bold_font", _bold() if IS_JUANBEN else f)
	rtl.add_theme_font_override("italics_font", f)
	rtl.add_theme_font_override("bold_italics_font", _bold() if IS_JUANBEN else f)
	rtl.add_theme_font_size_override("normal_font_size", SIZE_BODY)
	if IS_JUANBEN:
		rtl.add_theme_font_size_override("bold_font_size", SIZE_BODY)
	rtl.add_theme_color_override("default_color", TEXT)
	rtl.add_theme_constant_override("line_separation", LINE_BODY)


## 旁注。直接压在画上的旁注（港口「今日只开三处」）另由调用方加 style_overlay()；
## 这里不加描边——海图上的旁注会被调用方改成深墨字，深字配焦墨描边会糊成一团。
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


## 分隔标题：潮光小字。绢本：泥金小字。
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
## 绢本：正文底不透明靛墨，题签（旧绢）上是马善政墨字。
static func style_dialog(dlg: AcceptDialog, accent_ok := false) -> void:
	dlg.theme = theme()
	if IS_JUANBEN:
		dlg.add_theme_stylebox_override("panel", _dialog_box())
		dlg.add_theme_color_override("title_color", PAPER_TEXT)
		dlg.add_theme_font_override("title_font", title_font())
	else:
		dlg.add_theme_stylebox_override("panel", panel())
		dlg.add_theme_color_override("title_color", GOLD)
		dlg.add_theme_font_override("title_font", font())
	var ok := dlg.get_ok_button()
	if ok:
		style_button(ok, accent_ok)


# ── 宣纸工席 ────────────────────────────────────────────

## 工席 / 岸门 / 货签的卡：套上 shore_door()。
## 绢本下卡是宣纸，卡里的字随后按 on_paper() 换成纸上墨色（抬头石青换靛青并改马善政、去掉深底用的描边与投影）。
## 调用方照旧往卡里加 Label；卡每次重排（sort_children）都会再过一遍，后加的字也换得到，已换过的不再动。
## 小钮（Button）自带墨底 / 朱底，不换。夜潮下只是套 shore_door()，与原来一行 add_theme_stylebox_override 等价。
static func paper_card(slip: Control) -> void:
	slip.add_theme_stylebox_override("panel", shore_door())
	if not IS_JUANBEN:
		return
	slip.set_meta(&"nk1_paper", true)
	var inked := func() -> void:
		if is_instance_valid(slip):
			_ink_on_paper(slip)
	if slip is Container:
		(slip as Container).sort_children.connect(inked)
	inked.call_deferred()


## 深底字色 → 宣纸上的同色系墨色。已经够深（亮度 < 0.4，纸上墨色都在 0.32 以下）的原样返回，所以可以反复调用。
static func on_paper(c: Color) -> Color:
	if not IS_JUANBEN or c.get_luminance() < 0.4:
		return c
	var out := PAPER_TEXT
	if c.is_equal_approx(TEXT):
		out = PAPER_TEXT
	elif c.is_equal_approx(TEXT_DIM):
		out = PAPER_DIM
	elif c.is_equal_approx(TIDE):
		out = PAPER_TIDE
	elif c.is_equal_approx(GOLD) or c.is_equal_approx(GOLD_HI):
		out = PAPER_GOLD
	elif c.is_equal_approx(MOSS):
		out = PAPER_MOSS
	elif c.is_equal_approx(HONEY):
		out = PAPER_HONEY
	elif c.is_equal_approx(CINNABAR) or c.is_equal_approx(SEAL) or c.is_equal_approx(SEAL_HI):
		out = PAPER_CINNABAR
	elif c.s < 0.15:
		out = PAPER_TEXT if c.v > 0.85 else PAPER_DIM
	elif c.h < 0.04 or c.h > 0.93:
		out = PAPER_CINNABAR
	elif c.h < 0.17:
		out = PAPER_HONEY
	elif c.h < 0.45:
		out = PAPER_MOSS
	elif c.h < 0.75:
		out = PAPER_TIDE
	return Color(out, c.a)


const _INK_CLEAR := Color(0, 0, 0, 0)
## 宣纸卡上字号下限
const PAPER_MIN_PX := 16


static func _ink_on_paper(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			continue
		if child is Label:
			_ink_label(child as Label)
		elif child is RichTextLabel:
			var rtl := child as RichTextLabel
			var rc := rtl.get_theme_color("default_color")
			var rm := on_paper(rc)
			if not rm.is_equal_approx(rc):
				rtl.add_theme_color_override("default_color", rm)
			if rtl.get_theme_color("font_shadow_color").a > 0.0:
				rtl.add_theme_color_override("font_shadow_color", _INK_CLEAR)
		_ink_on_paper(child)


static func _ink_label(lbl: Label) -> void:
	var c := lbl.get_theme_color("font_color")
	var m := on_paper(c)
	if not m.is_equal_approx(c):
		lbl.add_theme_color_override("font_color", m)
	if lbl.get_theme_color("font_shadow_color").a > 0.0:
		lbl.add_theme_color_override("font_shadow_color", _INK_CLEAR)
	if lbl.get_theme_constant("outline_size") != 0:
		lbl.add_theme_constant_override("outline_size", 0)
	# 纸上的字不小于 16：文楷 14 在宣纸上抗锯齿后变浅，声明对比度够、实渲染只有 3.6–4.1（第 1 轮评审 UX M7）。
	# 折行的注文按新字号重算一次高度（_lock_slip_wrap 是按旧字号锁的）。
	var fs := lbl.get_theme_font_size("font_size")
	if fs > 0 and fs < PAPER_MIN_PX:
		lbl.add_theme_font_size_override("font_size", PAPER_MIN_PX)
		if lbl.autowrap_mode != TextServer.AUTOWRAP_OFF and lbl.custom_minimum_size.x > 0.0:
			var f := lbl.get_theme_font("font")
			if f != null:
				var sz := f.get_multiline_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, lbl.custom_minimum_size.x, PAPER_MIN_PX)
				lbl.custom_minimum_size.y = ceilf(maxf(sz.y, float(PAPER_MIN_PX)))
	# 卡上的抬头（原石青字或 ≥ SIZE_CARD 的字）改马善政，大四号。只做一次。
	if not lbl.has_meta(&"nk1_title") and (c.is_equal_approx(TIDE) or lbl.get_theme_font_size("font_size") >= SIZE_CARD):
		lbl.set_meta(&"nk1_title", true)
		lbl.add_theme_font_override("font", title_font())
		lbl.add_theme_font_size_override("font_size", lbl.get_theme_font_size("font_size") + 4)
