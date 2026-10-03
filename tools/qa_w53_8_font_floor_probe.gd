extends SceneTree
## lane w53-8：字阶下限——主场景搭的各页（港页、九处设施、泉州对峙征船名册、兴化围城募兵页、船籍簿、航海日志、
## 章节册页）上屏的字都不小于 UiTheme.SIZE_FOOT（文楷 14；13 太细，见 UiTheme 字阶注），「── X ──」分节小题
## 一律泥金小题样式（UiTheme.style_section_label 的泥金色）、字号 ≥ 16，与「石手军」那枚同款。
## 证（1280×720，挂主场景走真入口；headless 也跑——只量字号与色，不截图）：
##   1. 每页可见的 Label / Button / RichTextLabel（有字的）字号 ≥ SIZE_FOOT，逐页报最小字号；
##   2. 景炎元年六月（泉州 contested）进泉州市舶司：「── 征船名册 ──」在，字号 ≥ 16、泥金色；
##   3. 景炎元年十一月兴化围城募兵页：「── 石手军 ──」同判（旧有，作对照）。
## 旧病（回退即红）：Main._setup_quanzhou_standoff 把「── 征船名册 ──」钉成 13、默认宣纸色，夹在两张卡与对峙
## 正文之间几乎看不见；同一种分节小题「石手军」早已改成泥金 16（godot_story_check §13 钉着），这一枚漏了。
## 用法：godot --headless --path . -s res://tools/qa_w53_8_font_floor_probe.gd（带窗口 DISPLAY=:2 同样可跑）

const VIEW := Vector2i(1280, 720)
const FACILITIES := ["market", "yamen", "shipyard", "tavern", "inn", "guild", "exam", "residence", "temple"]
const HEAD_MIN := 16

var _fails: Array = []
var _main: Control
var _gs: Node
var _cal: Node


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


static func _text_of(c: Control) -> String:
	if c is Button:
		return (c as Button).text
	if c is Label:
		return (c as Label).text
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	return ""


static func _size_of(c: Control) -> int:
	if c is RichTextLabel:
		return c.get_theme_font_size("normal_font_size")
	return c.get_theme_font_size("font_size")


## 量一页：可见有字的控件字号都 ≥ SIZE_FOOT；返回这一页的「── X ──」分节小题
func _page(tag: String, scope: Node) -> Array:
	var small: Array = []
	var least := 999
	var heads: Array = []
	for n in scope.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		var t := _text_of(c).strip_edges()
		if t == "":
			continue
		var fs := _size_of(c)
		least = mini(least, fs)
		if fs < UiTheme.SIZE_FOOT:
			small.append("「%s」%d" % [t.replace("\n", "⏎").substr(0, 14), fs])
		if c is Label and t.begins_with("──"):
			heads.append(c)
	_check(small.is_empty(), "%s：上屏字号都不小于 %d（本页最小 %d）%s" % [tag, UiTheme.SIZE_FOOT, least,
		"" if small.is_empty() else "——小于下限：" + "、".join(small)])
	return heads


func _head(tag: String, heads: Array, word: String) -> void:
	var hit: Label = null
	for h in heads:
		if (h as Label).text.find(word) >= 0:
			hit = h
	_check(hit != null, "%s：分节小题「── %s ──」在页上" % [tag, word])
	if hit == null:
		return
	var fs := hit.get_theme_font_size("font_size")
	var col := hit.get_theme_color("font_color")
	var want := Color(UiTheme.GOLD, 0.92)
	_check(fs >= HEAD_MIN and col.is_equal_approx(want),
		"%s：「%s」是泥金分节小题（字号 %d ≥ %d，色 %s = %s）" % [tag, hit.text, fs, HEAD_MIN, col.to_html(), want.to_html()])


func _run() -> void:
	root.size = VIEW
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(10)
	_gs = root.get_node("GameState")
	_cal = root.get_node("Calendar")
	_page("标题页", _main)
	_gs.last_port = "quanzhou"
	for entry in ["monk", "merchant", "dock", "prepare", "return_quanzhou"]:
		_gs.beat_mark(entry)
	_main.load_scene("quanzhou")
	await _frames(6)
	_page("泉州港页", _main)
	for fac in FACILITIES:
		_main.load_scene("quanzhou_%s" % fac)
		await _frames(4)
		_page("泉州%s" % fac, _main)
	_main.load_scene("quanzhou")
	await _frames(4)
	_main._toggle_ledger()
	await _frames(4)
	_page("船籍簿", _main.left_panel)
	_main._close_ledger()
	_main._show_save_dialog(false)
	await _frames(4)
	_page("航海日志", _main)
	_main._close_save_sheet()
	_main._show_chapter_dialog({"title": "第一章　海口", "text": "宝祐三年三月，兴化海口。", "resolved": true, "scene": ""})
	await _frames(6)
	_page("章节册页", _main)
	_main._confirm_chapter_sheet()
	await _frames(6)

	# 泉州对峙：景炎元年六月泉州 contested，市舶司页下添征船名册
	_cal.set("year", 1276)
	_cal.set("month", 6)
	_main.load_scene("quanzhou_yamen")
	await _frames(6)
	_check(str(root.get_node("Economy").call("war_status", "quanzhou")) == "contested", "景炎元年六月泉州是对峙（contested）")
	_head("泉州市舶司（对峙）", _page("泉州市舶司（对峙）", _main), "征船名册")

	# 兴化围城募兵页（石手军，作对照）
	_gs.from_dict({})
	_gs.set_flag("renamed_wenlong")
	_gs.identity = "scholar"
	_cal.from_dict({"year": 1276, "month": 11, "day": 3})
	_gs.siege_begin()
	_gs.chapter = 4
	_gs.last_port = "xinghua"
	_main.load_scene("xinghua")
	await _frames(6)
	_main._on_facility_pressed({"id": "siege_muster"})
	await _frames(6)
	_head("兴化围城募兵", _page("兴化围城募兵", _main), "石手军")
	_finish()


func _finish() -> void:
	print("QA_W53_8_FONT_FLOOR_PROBE %s（%d 项不合）" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
