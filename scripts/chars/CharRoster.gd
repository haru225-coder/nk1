extends VBoxContainer
## 名册（chars 线）：按品级分组的人物横条列表，一行一小立绘（头面）、名、字号、身份、阵营签。
## 只读：数据经 GameManager.all_characters()；不写状态、不入存档。选中行给「选中」态（泥金边）。
## 缩略图按 CharacterArt.thumb 现取（名册最多列到要人一级，一张 34×34 头面）。

signal picked(id: String)

const Art := preload("res://scripts/ui/CharacterArt.gd")

const HEAD := Vector2i(34, 34)
const ROW_H := 40.0
## 默认列的人：主角起，要人次之；「全部」一档给巡检与浏览用
const TIERS := [
	["主", ["protagonist", "major"]],
	["职事", ["crew"]],
	["市井", ["minor"]],
	["史实", ["historical"]],
]

var tab := "主"
var _list: VBoxContainer
var _tabs_row: HBoxContainer
var _rows: Dictionary = {}
var _selected := ""


func _init() -> void:
	name = "CharRoster"
	add_theme_constant_override("separation", 8)


func _ready() -> void:
	if _list == null:
		_build()


func _build() -> void:
	var head := HBoxContainer.new()
	head.name = "Tabs"
	head.add_theme_constant_override("separation", 6)
	add_child(head)
	_tabs_row = head
	for spec in TIERS:
		var key: String = spec[0]
		var b := Button.new()
		b.text = key
		b.name = "Tab_%s" % key
		b.toggle_mode = true
		b.button_pressed = key == tab
		b.focus_mode = Control.FOCUS_NONE
		UiTheme.style_chip(b, key == tab)
		b.pressed.connect(_on_tab.bind(key))
		head.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.name = "RosterScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "RosterList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	refresh()


func _on_tab(key: String) -> void:
	if tab == key:
		return
	tab = key
	for i in TIERS.size():
		var b := _tabs_row.get_child(i) as Button
		if b != null:
			b.button_pressed = str(TIERS[i][0]) == tab
			UiTheme.style_chip(b, str(TIERS[i][0]) == tab)
	refresh()


## 重排名册。keep 为要保留选中态的人物 id。
func refresh(keep := "") -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var tiers: Array = []
	for spec in TIERS:
		if str(spec[0]) == tab:
			tiers = spec[1]
	var n := 0
	for ch in GameManager.all_characters():
		if not (str(ch.get("tier", "")) in tiers):
			continue
		var row := _build_row(ch)
		_list.add_child(row)
		_rows[str(ch.get("id", ""))] = row
		n += 1
	if n == 0:
		_list.add_child(Art.label("本档暂无人物。", UiTheme.SIZE_FOOT + 2, UiTheme.TEXT_DIM))
	var want := keep if keep != "" else _selected
	if want != "" and _rows.has(want):
		_select(want)
	elif n > 0:
		_select(str((_list.get_child(0) as Control).get_meta(&"char_id", "")))


func select_id(id: String) -> void:
	if _rows.has(id):
		_select(id)


func selected_id() -> String:
	return _selected


func _build_row(ch: Dictionary) -> Control:
	var id := str(ch.get("id", ""))
	var row := PanelContainer.new()
	row.name = "Row_%s" % id
	row.set_meta(&"char_id", id)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.custom_minimum_size.y = ROW_H
	row.add_theme_stylebox_override("panel", _row_box(false))
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_select(id)
		elif e is InputEventMouseMotion:
			pass)
	row.mouse_entered.connect(func() -> void:
		if _selected != id:
			row.add_theme_stylebox_override("panel", _row_box(false, true)))
	row.mouse_exited.connect(func() -> void:
		if _selected != id:
			row.add_theme_stylebox_override("panel", _row_box(false)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var face := PanelContainer.new()
	face.add_theme_stylebox_override("panel", UiTheme.icon_frame())
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := Art.picture(Art.thumb(ch, HEAD, true), Vector2(HEAD))
	pic.name = "Head"
	face.add_child(pic)
	h.add_child(face)
	var nm := Art.label(Art.display_name(ch), 20, UiTheme.TEXT, true)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.custom_minimum_size.x = 96
	h.add_child(nm)
	var sub := Art.label(_subtitle(ch), UiTheme.SIZE_FOOT, UiTheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sub)
	var chip := Art.faction_chip(ch, false, 15)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	return row


## 一条短注：字号（占位者注「未设色」）＋身份籍贯。论文纪实，不写数值评语。
func _subtitle(ch: Dictionary) -> String:
	var parts := PackedStringArray()
	var courtesy := Art.courtesy_of(ch)
	if courtesy != "":
		parts.append(courtesy.split("；")[0])
	parts.append(Art.identity_line(ch))
	if str(ch.get("portrait_status", "")) == "placeholder":
		parts.append("画像未设色")
	return "　".join(parts)


func _row_box(selected: bool, hot := false) -> StyleBox:
	var st := StyleBoxFlat.new()
	if selected:
		st.bg_color = Color(0.176, 0.149, 0.114, 0.92)
		st.border_color = Color(UiTheme.GOLD_HI, 0.90)
	elif hot:
		st.bg_color = Color(0.137, 0.122, 0.106, 0.72)
		st.border_color = Color(UiTheme.GOLD, 0.45)
	else:
		st.bg_color = Color(0.10, 0.086, 0.071, 0.45)
		st.border_color = Color(UiTheme.GOLD, 0.18)
	st.set_border_width_all(1)
	st.corner_radius_top_left = 2
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 2
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 6
	st.content_margin_right = 10
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	return st


func _select(id: String) -> void:
	# 已选中则只保高亮，不重发 picked（避免 Demo._pick ↔ select_id 互调栈溢出）
	if id == _selected:
		if _rows.has(id):
			(_rows[id] as Control).add_theme_stylebox_override("panel", _row_box(true))
		return
	if _selected != "" and _rows.has(_selected):
		(_rows[_selected] as Control).add_theme_stylebox_override("panel", _row_box(false))
	_selected = id
	if _rows.has(id):
		(_rows[id] as Control).add_theme_stylebox_override("panel", _row_box(true))
	picked.emit(id)
