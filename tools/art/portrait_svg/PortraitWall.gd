## 立绘墙（开发工具，不进正式流程）：按 data/characters.json 把 74 张立绘在引擎里铺出来看。
##   交互：<godot> --path . res://tools/art/portrait_svg/PortraitWall.tscn            （数字键 1–3 切页）
##   截帧：<godot> --path . --write-movie /tmp/x/f.png --fixed-fps 10 --quit-after 4 \
##           --resolution 1280x720 res://tools/art/portrait_svg/PortraitWall.tscn -- --page=npc
##   页：npc = 按 Main.gd NPC 页的 300px 实际显示宽度看四位会上屏的人；grid0 / grid1 = 全部 74 张总览。
## headless 下逐张 load 校验并打印计数后立即退出（缺图 rc=1）。
extends Control

const DATA_PATH := "res://data/characters.json"
const FONT_BODY := "res://assets/fonts/LXGWWenKai-Medium.ttf"
const FONT_TITLE := "res://assets/fonts/MaShanZheng-Regular.ttf"
const NPC_IDS := ["customs_official", "merchant_lin", "pilot_ana", "veteran"]
const PAGES := ["npc", "grid0", "grid1"]
const PER_PAGE := 40
const C_BG := Color("#1a1612")
const C_TEXT := Color("#e9dcc0")
const C_SUB := Color("#cdb88f")

var _chars: Array = []
var _root: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_chars = _load_chars()
	var page := "npc"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--page="):
			page = a.substr(7)
	if DisplayServer.get_name() == "headless":
		var ok := 0
		for c in _chars:
			var p: String = c.get("portrait", "")
			if ResourceLoader.exists(p) and load(p) is Texture2D:
				ok += 1
			else:
				push_error("立绘缺失：" + p)
		print("PORTRAIT_WALL headless ok=%d/%d" % [ok, _chars.size()])
		get_tree().quit(0 if ok == _chars.size() and ok > 0 else 1)
		return
	_show(page)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var idx: int = int(k.keycode) - int(KEY_1)
	if idx >= 0 and idx < PAGES.size():
		_show(PAGES[idx])


func _load_chars() -> Array:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("读不到 " + DATA_PATH)
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return (d as Dictionary).get("characters", [])


func _show(page: String) -> void:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	if page == "npc":
		_page_npc()
	else:
		_page_grid(1 if page == "grid1" else 0)


func _find(id: String) -> Dictionary:
	for c in _chars:
		if c.get("id", "") == id:
			return c
	return {}


func _label(text: String, font_path: String, font_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load(font_path))
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _portrait(c: Dictionary, w: int) -> TextureRect:
	var t := TextureRect.new()
	var p: String = c.get("portrait", "")
	if ResourceLoader.exists(p):
		t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(w, w * 5.0 / 4.0)
	return t


func _page_npc() -> void:
	var title := _label("NPC 页实际显示宽度 300px · 会上屏的四位", FONT_BODY, 18, C_SUB)
	title.position = Vector2(0, 16)
	title.size = Vector2(1280, 28)
	_root.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.position = Vector2(24, 60)
	_root.add_child(row)
	for id in NPC_IDS:
		var c := _find(id)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.add_child(_portrait(c, 296))
		col.add_child(_label(str(c.get("name", id)), FONT_TITLE, 30, C_TEXT))
		col.add_child(_label("%s · %s" % [c.get("title", ""), c.get("portrait_status", "")], FONT_BODY, 16, C_SUB))
		row.add_child(col)


func _page_grid(n: int) -> void:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	grid.position = Vector2(12, 6)
	_root.add_child(grid)
	var start := n * PER_PAGE
	for i in range(start, mini(start + PER_PAGE, _chars.size())):
		var c: Dictionary = _chars[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.add_child(_portrait(c, 122))
		col.add_child(_label(str(c.get("name", "")), FONT_BODY, 16, C_TEXT))
		grid.add_child(col)
