## 主题预览（开发工具，不进正式流程）。展示 nk1_theme.tres 的全部控件与 type variation，
## 并模拟四张真实页面：港口页、酒馆募人卡、弹窗、NPC 页，外加标题屏与控件总表。
##   交互：<godot> --path . res://tools/art/ThemePreview.tscn          （数字键 1–6 切页）
##   截帧：<godot> --path . --write-movie /tmp/x/f.png --fixed-fps 10 --quit-after 8 \
##           --resolution 1280x720 res://tools/art/ThemePreview.tscn -- --page=tavern
##   量对比度用：-- --page=port --hide-text   所有 Label / RichTextLabel 透明（与正常帧逐像素相减取字形）
##               -- --page=port --fill-off    只把字的填充色调成透明、描边与墨晕照画（量「字下面实际垫着什么」）
##               -- --page=port --dump-labels 打印每个文字控件的全局矩形与字色（NK1LBL|{json}）
## headless 下只搭一遍全部页面做冒烟检查，立即退出。
## 人物数据读 data/characters.json（属性 / 特长 / 立绘路径）与 data/crew.json（职事 / 月俸），
## 立绘优先 characters.json 的 portrait（立绘线产物）；未落地时仅在编辑器里读 Codex 原稿（portrait_src）。
extends Control

const THEME_PATH := "res://assets/theme/nk1_theme.tres"
const UI := "res://assets/ui/nk1/"
const PAGES := ["port", "tavern", "dialog", "npc", "title", "widgets"]
const CHAR_DATA := "res://data/characters.json"
const CREW_DATA := "res://data/crew.json"
## 港口页用的年月（与状态栏一致）；弹窗页演示第二章，另用景定元年
const DATE_PORT := "宝祐三年 四月"
const DATE_CH2 := "景定元年 十月"

var _page_root: Control
var _page := "port"
var _hide_text := false
var _fill_off := false
var _dump_labels := false
var _chars := {}
var _crew := {}
var _attr_def: Array = []
var _trait_def := {}
var _role_name := {}


func _ready() -> void:
	theme = load(THEME_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			_page = a.substr(7)
		elif a == "--hide-text":
			_hide_text = true
		elif a == "--fill-off":
			_fill_off = true
		elif a == "--dump-labels":
			_dump_labels = true
	_load_data()
	if DisplayServer.get_name() == "headless":
		for p in PAGES:
			_show(p)
		print("THEME_PREVIEW headless ok pages=", PAGES.size(), " chars=", _chars.size(), " crew=", _crew.size())
		get_tree().quit(0)
		return
	_show(_page)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var idx: int = int(k.keycode) - int(KEY_1)
	if idx >= 0 and idx < PAGES.size():
		_show(PAGES[idx])


func _show(p: String) -> void:
	if _page_root != null:
		_page_root.queue_free()
	for c in get_children():
		if c is Window:
			c.queue_free()
	_page_root = Control.new()
	_page_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page_root)
	_page = p
	match p:
		"port":
			_page_port()
		"tavern":
			_page_tavern()
		"dialog":
			_page_dialog()
		"npc":
			_page_npc()
		"title":
			_page_title()
		_:
			_page_widgets()
	if _hide_text:
		_set_text_alpha(self)
	if _fill_off:
		_set_fill_off(self)
	if _dump_labels:
		_dump.call_deferred()


# ─────────────────────────────────────────────── 量测辅助
func _set_text_alpha(n: Node) -> void:
	if n is Label or n is RichTextLabel:
		(n as CanvasItem).self_modulate.a = 0.0
	for c in n.get_children():
		_set_text_alpha(c)


func _set_fill_off(n: Node) -> void:
	if n is Label:
		var l := n as Label
		l.add_theme_color_override("font_color", Color(l.get_theme_color("font_color"), 0.0))
	elif n is RichTextLabel:
		var r := n as RichTextLabel
		r.add_theme_color_override("default_color", Color(r.get_theme_color("default_color"), 0.0))
	for c in n.get_children():
		_set_fill_off(c)


## 等两帧布局落定后打印文字控件矩形（给对比度脚本按真实位置取样）。
func _dump() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_dump_node(self)


func _dump_node(n: Node) -> void:
	if (n is Label or n is RichTextLabel) and (n as CanvasItem).is_visible_in_tree():
		var c := n as Control
		var r := c.get_global_rect()
		var info := {"page": _page, "class": c.get_class(), "var": str(c.theme_type_variation),
			"text": (c as Label).text if c is Label else (c as RichTextLabel).get_parsed_text(),
			"rect": [r.position.x, r.position.y, r.size.x, r.size.y]}
		if c is Label:
			info["color"] = c.get_theme_color("font_color").to_html(false)
		else:
			info["color"] = c.get_theme_color("default_color").to_html(false)
		var w := c.get_window()
		if w != null and w != get_window():
			info["window"] = [w.position.x, w.position.y]
		print("NK1LBL|", JSON.stringify(info))
	for ch in n.get_children():
		_dump_node(ch)


# ─────────────────────────────────────────────── 数据
func _load_data() -> void:
	var d: Variant = _read_json(CHAR_DATA)
	if d is Dictionary:
		var meta: Dictionary = (d as Dictionary).get("meta", {})
		_attr_def = meta.get("attr_def", [])
		_trait_def = meta.get("trait_def", {})
		for c in (d as Dictionary).get("characters", []):
			if c is Dictionary:
				_chars[str(c.get("id", ""))] = c
	var cr: Variant = _read_json(CREW_DATA)
	if cr is Dictionary:
		for r in (cr as Dictionary).get("roles", []):
			if r is Dictionary:
				_role_name[str(r.get("id", ""))] = str(r.get("name", ""))
		for c in (cr as Dictionary).get("candidates", []):
			if c is Dictionary:
				_crew[str(c.get("id", ""))] = c


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _char(cid: String) -> Dictionary:
	return _chars.get(cid, {})


# ─────────────────────────────────────────────── 小工具
func _tex(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path) if ResourceLoader.exists(path) else null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## 立绘：characters.json 的 portrait（仓库内，立绘线产物）→ 仅编辑器下的 Codex 原稿 → 旧 sprite。
func _portrait(cid: String, fallback: String) -> Texture2D:
	var c := _char(cid)
	var p := str(c.get("portrait", ""))
	if p != "" and ResourceLoader.exists(p):
		return load(p)
	var src := str(c.get("portrait_src", ""))
	if OS.has_feature("editor") and src.begins_with("codex:"):
		var codex_dir := OS.get_environment("NK1_CODEX_PORTRAITS")
		if codex_dir == "":
			codex_dir = OS.get_environment("HOME").path_join("tmp/nk1-codex/assets/portraits")
		var t := _tex(codex_dir.path_join(src.substr(6)))
		if t != null:
			return t
	return _tex(fallback)


func _bg(file: String, dim: float = 0.0) -> void:
	var trect := TextureRect.new()
	trect.texture = _tex("res://assets/" + file)
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	trect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_root.add_child(trect)
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0.03, 0.03, 0.04, dim)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_page_root.add_child(shade)


func _label(text: String, variation: String = "", fsize: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if fsize > 0:
		l.add_theme_font_size_override("font_size", fsize)
	return l


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, variation: String = "", min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	return b


func _img(path: String, sz: Vector2) -> TextureRect:
	var trect := TextureRect.new()
	trect.texture = _tex(path)
	trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trect.custom_minimum_size = sz
	trect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return trect


func _place(c: Control, pos: Vector2, sz: Vector2 = Vector2.ZERO) -> Control:
	_page_root.add_child(c)
	c.position = pos
	if sz != Vector2.ZERO:
		c.size = sz
	return c


func _vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## 立绘 + 画框。scale=1 时逻辑 296×400，窗口 (20,20) 起 256×320。
func _framed_portrait(tex: Texture2D, scale_f: float, plate: String = "") -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(296, 400) * scale_f
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.position = Vector2(20, 20) * scale_f
	pic.size = Vector2(256, 320) * scale_f
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pic.clip_contents = true
	box.add_child(pic)
	var fr := TextureRect.new()
	fr.texture = _tex(UI + "portrait_frame.png")
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.stretch_mode = TextureRect.STRETCH_SCALE
	fr.size = Vector2(296, 400) * scale_f
	fr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	box.add_child(fr)
	if plate != "":
		var l := _label(plate, "HeadingLabel", maxi(16, int(26 * scale_f)))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(48, 350) * scale_f
		l.size = Vector2(200, 38) * scale_f
		box.add_child(l)
	return box


## 墨刷底标题块：ink_splash_plate 前六成是实心段（规范第 5 节给出安全区），标题 + 副题都落在实心段里。
## plate_pos 为墨刷左上角；安全区（逻辑，贴图 1:1）约 x 12–538、y 27–137。
func _ink_plate_title(plate_pos: Vector2, title: String, caption: String, seal: String = "") -> void:
	var plate := _img(UI + "ink_splash_plate.png", Vector2(751, 184))
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	_place(plate, plate_pos)
	var zone := Rect2(plate_pos + Vector2(12, 27), Vector2(526, 110))
	var t := _label(title, "TitleLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(t, zone.position + Vector2(0, 2), Vector2(zone.size.x, 62))
	var cap := _label(caption, "OverlayCaption")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(cap, zone.position + Vector2(0, 70), Vector2(zone.size.x, 26))
	if seal != "":
		_place(_img(UI + seal + ".png", Vector2(44, 44)), zone.position + Vector2(zone.size.x * 0.5 + 92, 10))


func _status_bar(date_line: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InkPanel"
	_place(panel, Vector2(0, 0), Vector2(300, 720))
	var v := _vbox(6)
	panel.add_child(v)
	var head := _label("情报与状态", "HeadingLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	v.add_child(HSeparator.new())
	var st := RichTextLabel.new()
	st.bbcode_enabled = true
	st.fit_content = true
	st.scroll_active = false
	st.text = ("[b]陈子龙[/b]　%s\n[color=#cdb88f]东北信风将歇，南风未起[/color]\n\n" % date_line
		+ "金钱：1,250 贯\n名声：38\n[color=#e39a55]战况：泉州 蒲氏盯梢[/color]\n\n"
		+ "[u]舰队[/u]\n船数：2　水手：46\n舱位：120 / 300 料\n耐久：180 / 200\n士气：72\n"
		+ "水：40　粮：36　[color=#e8c46a]（足 9 日）[/color]")
	v.add_child(st)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(HSeparator.new())
	var msg := RichTextLabel.new()
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.scroll_active = false
	msg.text = ("[color=#e98a6e]【市舶】公凭验讫，抽解十一。[/color]\n"
		+ "[color=#cdb88f]【牙行】胡椒行情看涨三成。[/color]")
	v.add_child(msg)


# ─────────────────────────────────────────────── 页面
func _page_port() -> void:
	_bg("bg_quanzhou_harbor.jpg")
	_status_bar(DATE_PORT)
	_ink_plate_title(Vector2(392, -12), "泉州港", "宝祐三年 · 市舶司治所　蕃舶云集", "seal_dongya_bai")
	var facs := [["market", "牙行", "买卖货物 · 打听行情"], ["yamen", "市舶司", "请公凭 · 呈报所见"],
		["shipyard", "船场", "修船 · 募水手 · 添补"], ["tavern", "酒馆", "打听消息 · 募人"],
		["inn", "客舍", "歇脚 · 候风信"], ["temple", "天后宫", "祈风 · 旧事"]]
	for i in range(facs.size()):
		var f: Array = facs[i]
		var card := _fac_card(f[0], f[1], f[2], i == 3)
		var col := i % 2
		var row := floori(i / 2.0)
		_place(card, Vector2(330 + col * 640, 180 + row * 114), Vector2(300, 96))
	var strip := PanelContainer.new()
	strip.theme_type_variation = "InkPanel"
	_place(strip, Vector2(500, 612), Vector2(580, 0))
	var bar := _hbox(18)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(_button("升帆出海（海图）", "SealButton", 220))
	bar.add_child(_button("存档", "", 110))
	bar.add_child(_button("离港", "GhostButton"))
	strip.add_child(bar)


## 设施图标：沿用 main 线 icon_*.png；icon_shipyard 画的是西洋三桅船（穿帮，待图标线换福船），
## 样张改用船场背景里正在起造的福船船壳裁一块。
func _fac_icon(icon_id: String) -> Texture2D:
	if icon_id == "shipyard":
		var at := AtlasTexture.new()
		at.atlas = _tex("res://assets/bg_shipyard.jpg")
		at.region = Rect2(150, 60, 520, 520)
		return at
	return _tex("res://assets/icon_%s.png" % icon_id)


func _fac_card(icon_id: String, title: String, sub: String, hovered: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "PaperPanel"
	var h := _hbox(12)
	card.add_child(h)
	var ic := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0d0b09")
	sb.set_content_margin_all(2)
	ic.add_theme_stylebox_override("panel", sb)
	var pic := _img("", Vector2(60, 60))
	pic.texture = _fac_icon(icon_id)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ic.add_child(pic)
	h.add_child(ic)
	var v := _vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label(title, "InkHeading", 26))
	v.add_child(_label(sub, "InkCaption"))
	h.add_child(v)
	if hovered:
		var mark := _img(UI + "seal_haishang_zhu.png", Vector2(26, 44))
		h.add_child(mark)
	return card


func _page_tavern() -> void:
	_bg("bg_xinghua_wine_shed.jpg", 0.25)
	_status_bar(DATE_PORT)
	var head := _label("兴化・酒棚　牙人荐帖", "HeadingLabel", 32)
	_place(head, Vector2(336, 14))
	var cap := _label("牙人荐来三人，各在本港候雇。月俸按月支给，欠饷三月则去。", "OverlayCaption")
	_place(cap, Vector2(338, 60))
	# [人物 id, 回落 sprite, 不可用时按钮字]
	var people := [["zhou_suanchou", "res://assets/sprite_servant.png", ""],
		["he_wenzhou", "res://assets/sprite_veteran.png", ""],
		["cai_qixing", "res://assets/sprite_veteran.png", "第二章可雇"]]
	for i in range(people.size()):
		var p: Array = people[i]
		_place(_crew_card(p[0], p[1], p[2]), Vector2(330 + i * 316, 94), Vector2(296, 0))


func _crew_card(cid: String, fallback: String, locked: String) -> Control:
	var c := _char(cid)
	var cr: Dictionary = _crew.get(cid, {})
	var role := str(_role_name.get(str(cr.get("role", "")), "水手"))
	var card := PanelContainer.new()
	card.theme_type_variation = "SilkPanel"
	var v := _vbox(4)
	card.add_child(v)
	var pic := _framed_portrait(_portrait(cid, fallback), 0.6, role)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	var nh := _hbox(8)
	nh.add_child(_label(str(c.get("name", cid)), "InkHeading", 28))
	var lv := int(cr.get("level", 1))
	var role_l := _label("%s %s" % [str(c.get("origin", "")).left(2), "★".repeat(lv)], "InkCaption")
	role_l.size_flags_vertical = Control.SIZE_SHRINK_END
	nh.add_child(role_l)
	v.add_child(nh)
	var attrs: Dictionary = c.get("attrs", {})
	for ad in _attr_def:
		var row := _hbox(8)
		var nl := _label(str(ad.get("name", "")), "InkText", 16)
		nl.custom_minimum_size.x = 36
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.theme_type_variation = "AttrBar"
		bar.show_percentage = false
		bar.value = float(attrs.get(str(ad.get("key", "")), 0))
		bar.custom_minimum_size = Vector2(150, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(_label(str(int(bar.value)), "InkText", 16))
		v.add_child(row)
	var traits := PackedStringArray()
	for tk in c.get("traits", []):
		traits.append(str((_trait_def.get(str(tk), {}) as Dictionary).get("name", tk)))
	v.add_child(_label("特长　" + " · ".join(traits), "InkCaption"))
	v.add_child(InkSep.make())
	v.add_child(_label("月俸 %d 钱" % int(cr.get("wage", 0)), "InkText", 16))
	var b := _button("雇 佣", "SealButton")
	if locked != "":
		b.disabled = true
		b.text = locked
	v.add_child(b)
	return card


func _page_dialog() -> void:
	_bg("bg_linan.jpg")
	_status_bar(DATE_CH2)
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", theme.get_stylebox("panel", "TooltipPanel"))
	var tl := _label("贾似道当国，公田法行于浙西。\n此去临安，须备厚礼。", "InkText", 16)
	tip.add_child(tl)
	_place(tip, Vector2(930, 600))
	var dlg := AcceptDialog.new()
	dlg.title = "第二章　景定年间"
	dlg.ok_button_text = "……"
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 18)
	m.add_theme_constant_override("margin_right", 18)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var v := _vbox(10)
	m.add_child(v)
	v.add_child(_label("临安来信", "HeadingLabel"))
	var body := RichTextLabel.new()
	body.fit_content = true
	body.custom_minimum_size = Vector2(560, 200)
	body.text = ("景定元年，忽必烈北还争位，鄂州之围解。贾似道匿和议、报大捷，入朝专政。\n\n"
		+ "泉州市舶司来文：凡蕃舶入港，须先验公凭，抽解之外另征「和籴」。"
		+ "你在兴化的旧交托人带话——朝中有人盯上了海上这门生意。")
	v.add_child(body)
	dlg.add_child(m)
	add_child(dlg)
	dlg.popup_centered()


func _page_npc() -> void:
	_bg("bg_quanzhou_office.jpg", 0.15)
	_status_bar(DATE_PORT)
	var c := _char("customs_official")
	var pic := _framed_portrait(_portrait("customs_official", "res://assets/sprite_servant.png"), 1.2, "市舶司吏")
	_place(pic, Vector2(1280 - 296 * 1.2 - 36, 176))
	var panel := PanelContainer.new()
	panel.theme_type_variation = "InkPanel"
	_place(panel, Vector2(330, 360), Vector2(530, 330))
	var v := _vbox(8)
	panel.add_child(v)
	v.add_child(_label(str(c.get("name", "市舶司小吏")), "HeadingLabel"))
	v.add_child(HSeparator.new())
	var d := RichTextLabel.new()
	d.fit_content = true
	var lines: Array = c.get("lines", [])
	d.text = "他颠了颠手里的碎银，压低声音：「%s」" % (str(lines[0]) if lines.size() > 0 else "……")
	v.add_child(d)
	for t in ["打听情报", "塞钱疏通（50 钱，降低关注度）", "离开"]:
		var b := _button("· " + t, "GhostButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	_ink_plate_title(Vector2(318, -12), "市舶司", "泉州 · 验引签押房")


func _page_title() -> void:
	_bg("bg_world_map.jpg")
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.28)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_root.add_child(shade)
	var wash := _img(UI + "ink_splash_wash.png", Vector2(1000, 560))
	wash.modulate = Color(1, 1, 1, 0.55)
	_place(wash, Vector2(140, 60))
	var logo := _img(UI + "logo_title_h_gold.png", Vector2(880, 240))
	_place(logo, Vector2(200, 150))
	var sub := _label("宝祐三年，宋室将倾。兴化海口的礁石上，一个年轻人望向大洋彼岸。", "OverlayText", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(sub, Vector2(0, 420), Vector2(1280, 30))
	var v := _vbox(14)
	var b1 := _button("开始旅程", "SealButton", 240)
	b1.custom_minimum_size.y = 50
	v.add_child(b1)
	var b2 := _button("读取存档", "", 240)
	b2.custom_minimum_size.y = 44
	v.add_child(b2)
	_place(v, Vector2(520, 490))


func _page_widgets() -> void:
	_bg("bg_sea_route.jpg", 0.45)
	var left := PanelContainer.new()
	left.theme_type_variation = "InkPanel"
	_place(left, Vector2(24, 20), Vector2(600, 680))
	var v := _vbox(10)
	left.add_child(v)
	v.add_child(_label("深墨面板 InkPanel", "HeadingLabel"))
	v.add_child(_wrap(_label("正文 18：文楷 Medium，宣纸色压靛墨。泉州、兴化、临安、博多。")))
	v.add_child(_wrap(_label("CaptionLabel 16：旧绢色说明小字 · 月俸按月支给", "CaptionLabel")))
	var gband := PanelContainer.new()
	gband.theme_type_variation = "BandHuiwenGold"
	v.add_child(gband)
	var r1 := _hbox(10)
	r1.add_child(_button("墨底按钮"))
	var hv := _button("悬停")
	hv.add_theme_stylebox_override("normal", theme.get_stylebox("hover", "Button"))
	hv.add_theme_color_override("font_color", theme.get_color("font_hover_color", "Button"))
	r1.add_child(hv)
	var pr := _button("按下")
	pr.add_theme_stylebox_override("normal", theme.get_stylebox("pressed", "Button"))
	pr.add_theme_color_override("font_color", theme.get_color("font_pressed_color", "Button"))
	r1.add_child(pr)
	var ds := _button("不可用")
	ds.disabled = true
	r1.add_child(ds)
	v.add_child(r1)
	var r2 := _hbox(10)
	r2.add_child(_button("朱印主按钮", "SealButton"))
	var sh := _button("悬停", "SealButton")
	sh.add_theme_stylebox_override("normal", theme.get_stylebox("hover", "SealButton"))
	r2.add_child(sh)
	var sd := _button("不可用", "SealButton")
	sd.disabled = true
	r2.add_child(sd)
	r2.add_child(_button("· 文字选项", "GhostButton"))
	v.add_child(r2)
	var r3 := _hbox(14)
	var cb := CheckBox.new()
	cb.text = "带公凭"
	cb.button_pressed = true
	r3.add_child(cb)
	var cb2 := CheckBox.new()
	cb2.text = "夜航"
	r3.add_child(cb2)
	var ob := OptionButton.new()
	for s in ["一号船 · 福船", "二号船 · 广船"]:
		ob.add_item(s)
	r3.add_child(ob)
	v.add_child(r3)
	var le := LineEdit.new()
	le.placeholder_text = "船名（例：顺风）"
	le.custom_minimum_size.x = 260
	v.add_child(le)
	var pb := ProgressBar.new()
	pb.value = 62
	pb.custom_minimum_size = Vector2(0, 24)
	v.add_child(pb)
	for pair in [["AttrBarGold", 78], ["AttrBarRed", 35]]:
		var b := ProgressBar.new()
		b.theme_type_variation = pair[0]
		b.value = pair[1]
		b.show_percentage = false
		b.custom_minimum_size = Vector2(0, 14)
		v.add_child(b)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 124)
	for n in ["货舱", "水手", "航志"]:
		var sc := ScrollContainer.new()
		sc.name = n
		var inner := _vbox(4)
		for i in range(8):
			inner.add_child(_label("胡椒 ×%d　苏木 ×%d　乳香 ×%d" % [i * 3 + 2, i + 1, 12 - i]))
		sc.add_child(inner)
		tabs.add_child(sc)
	v.add_child(tabs)
	var right := PanelContainer.new()
	right.theme_type_variation = "SilkPanel"
	_place(right, Vector2(650, 20), Vector2(606, 420))
	var rv := _vbox(8)
	right.add_child(rv)
	rv.add_child(_label("绢面板 SilkPanel", "InkHeading"))
	rv.add_child(_wrap(_label("InkText 18：绢 / 纸上一律用墨色字，不用宣纸色；注文用 InkCaption。", "InkText")))
	rv.add_child(_wrap(_label("InkCaption 16：注文、出处、签押。", "InkCaption")))
	rv.add_child(InkSep.make())
	var sr := _hbox(14)
	for s in ["seal_lizhi_zhu", "seal_lizhi_bai", "seal_haishang_zhu", "seal_daihui_bai"]:
		sr.add_child(_img(UI + s + ".png", Vector2(42, 70)))
	for s in ["seal_dongya_zhu", "seal_xinghua_bai", "seal_blank"]:
		sr.add_child(_img(UI + s + ".png", Vector2(70, 70)))
	rv.add_child(sr)
	var band := PanelContainer.new()
	band.theme_type_variation = "BandHuiwenInk"
	rv.add_child(band)
	var ink := _hbox(8)
	for s in ["ink_splash_plate", "ink_splash_sweep", "ink_splash_ring", "ink_splash_burst", "ink_splash_stroke"]:
		ink.add_child(_img(UI + s + ".png", Vector2(84, 84)))
	# 朱色墨迹：ink_tint 材质按 alpha 换色（modulate 只能压暗）
	var zhu := _img(UI + "ink_splash_ring.png", Vector2(84, 84))
	zhu.material = load("res://assets/theme/ink_tint_zhu.tres")
	ink.add_child(zhu)
	rv.add_child(ink)
	var paper := PanelContainer.new()
	paper.theme_type_variation = "PaperPanel"
	_place(paper, Vector2(650, 460), Vector2(606, 240))
	var pv := _vbox(6)
	paper.add_child(pv)
	pv.add_child(_label("宣纸卡 PaperPanel", "InkHeading"))
	var rt := RichTextLabel.new()
	rt.theme_type_variation = "InkRichText"
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = "[b]InkRichText[/b]：市舶司公凭一纸，许往[color=#8e2420]三佛齐[/color]、[color=#1f3a4d]阇婆[/color]贸易，限期一年。"
	pv.add_child(rt)
	var gb := PanelContainer.new()
	gb.theme_type_variation = "BandCloudGold"
	gb.modulate = Color(0.78, 0.66, 0.46)
	pv.add_child(gb)
	pv.add_child(_button("墨底按钮也能压在纸上"))


## 浅底用墨线分隔（HSeparator 的 InkSeparator variation）。
class InkSep:
	static func make() -> HSeparator:
		var s := HSeparator.new()
		s.theme_type_variation = "InkSeparator"
		return s
