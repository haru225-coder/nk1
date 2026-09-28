extends PanelContainer
## 人物面板（chars 线）：左为旧绢画框立绘（UiTheme.frame_portrait，名牌题名），下接阵营签与品级；
## 右为题名、字号、身份籍贯、生卒、登场、短注（上屏文本层）、五维、特技、画像设色情况。
## 只读：数据经 GameManager.get_character，文字经 CharacterArt 的上屏层取（不读设定集原稿 bio）。

const Art := preload("res://scripts/ui/CharacterArt.gd")

const PIC := Vector2i(256, 320)
const INFO_W := 276.0

var current_id := ""
var _frame: PanelContainer
var _pic: TextureRect
var _chips: HBoxContainer
var _info: VBoxContainer


func _init() -> void:
	name = "CharPortraitPanel"
	add_theme_stylebox_override("panel", UiTheme.panel())
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	if _info == null:
		_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.name = "Left"
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	_frame = PanelContainer.new()
	_frame.name = "PortraitFrame"
	_pic = Art.picture(null, Vector2(PIC))
	_pic.name = "Portrait"
	_frame.add_child(_pic)
	if not UiTheme.frame_portrait(_frame, _pic):
		_frame.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	left.add_child(_frame)
	_chips = HBoxContainer.new()
	_chips.name = "Chips"
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", 8)
	left.add_child(_chips)

	var scroll := ScrollContainer.new()
	scroll.name = "InfoScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = INFO_W
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var faded := UiTheme.fade_scroll(scroll, 20)
	faded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(faded)
	_info = VBoxContainer.new()
	_info.name = "Info"
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_constant_override("separation", 7)
	scroll.add_child(_info)


func show_character(ch: Dictionary) -> void:
	if _info == null:
		_build()
	current_id = str(ch.get("id", ""))
	_pic.texture = Art.thumb(ch, PIC)
	var plate := _frame.get_node_or_null("NamePlate/Name") as Label
	var nm := Art.display_name(ch)
	if plate != null:
		plate.text = nm
		plate.add_theme_font_override("font", Art.title_font_for(nm))
	for c in _chips.get_children():
		c.queue_free()
	_chips.add_child(Art.faction_chip(ch))
	var tier := Art.label(str(Art.TIER_NAME.get(str(ch.get("tier", "")), "")), UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chips.add_child(tier)
	_fill_info(ch, nm)
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		_pic.modulate.a = 0.0
		create_tween().tween_property(_pic, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE)


func _fill_info(ch: Dictionary, nm: String) -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var head := Art.label(nm, 36, UiTheme.GOLD_HI, true)
	head.name = "Name"
	head.add_theme_color_override("font_outline_color", Color(0.051, 0.043, 0.035, 0.70))
	head.add_theme_constant_override("outline_size", 4)
	_info.add_child(head)
	var courtesy := Art.courtesy_of(ch)
	if courtesy != "":
		_info.add_child(_para(courtesy, UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM))
	_info.add_child(Art.rule())
	_kv("身份", _glue_origin(Art.identity_line(ch)))
	_kv("生卒", Art.life_line(ch))
	_kv("登场", _appear_tail(ch))
	var short := Art.codex_short(ch)
	if short != "":
		var s := _para(short, 16, UiTheme.TEXT)
		s.name = "Short"
		_info.add_child(s)
	_info.add_child(Art.rule(0.30))
	_info.add_child(Art.attr_block(ch, 132.0, 15))
	var traits := Art.trait_row(ch, 15)
	if traits.get_child_count() > 0:
		_info.add_child(traits)
	_kv("画像", _paint_state(ch))


## appear_line 自带「登场」「见于」动词，这里只留章次；史实人物照写「见于」。
func _appear_tail(ch: Dictionary) -> String:
	var line := Art.appear_line(ch)
	if line.begins_with("登场　"):
		return line.substr(3)
	return line


## 身份一行在这一栏里常要折行：别从地名中间折开（「参知政事、知兴化军・兴化军莆田／县玉湖」）。
## 最后一个「・」后面的籍贯逐字垫字连接符 U+2060（零宽、禁折），要折就折在「・」之后。只作显示，别处照读原串。
func _glue_origin(ident: String) -> String:
	var cut := ident.rfind("・")
	if cut < 0 or cut == ident.length() - 1:
		return ident
	return ident.substr(0, cut + 1) + String.chr(0x2060).join(ident.substr(cut + 1).split(""))


func _paint_state(ch: Dictionary) -> String:
	if Art.portrait_path(ch) == "":
		return "未画"
	# 按日期换画的人（林华辞船前挂剪影墨卡）看此刻挂的那张
	return "剪影，未设色" if Art.portrait_is_card(ch) else "设色"


func _kv(key: String, value: String) -> void:
	if value == "":
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := Art.label(key, UiTheme.SIZE_FOOT, UiTheme.GOLD)
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	var v := _para(value, UiTheme.SIZE_FOOT + 1, UiTheme.TEXT)
	row.add_child(v)
	_info.add_child(row)


func _para(text: String, px: int, color: Color) -> Label:
	var l := Art.label(text, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 60
	return l
