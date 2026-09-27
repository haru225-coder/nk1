extends SceneTree
## 章晋升册页巡检：截 01..N 到 /workspace/nk1-qa-shots/chapter/。
## 摆场仿 ShotTour._site_chapter_dialog：伪造章一→二晋升（years=2），_cinema 直通弹册页；
## 再调 UiTransition.promote_open 截「两年后・旧账」晋印题签帧。
## -s 工具脚本下 play_transition 当帧直通；这里直接调助手截墨幕那一帧。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_chapter_promote_probe.gd

const VIEW := Vector2(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/chapter"
const _UT := preload("res://scripts/ui/UiTransition.gd")

var _main: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_CHAPTER_BEGIN")

	_expect(str(_UT.promote_title(2, "旧账")) == "两年后・旧账", "晋升题签「%s」" % _UT.promote_title(2, "旧账"))
	_expect(str(_UT.promote_title(3, "")) == "三年后", "三年后无章名「%s」" % _UT.promote_title(3, ""))
	_expect(str(_UT.promote_title(0, "旧账")) == "旧账", "无跳年只写章名")

	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)

	var gs: Node = root.get_node("/root/GameState")
	var cal: Node = root.get_node("/root/Calendar")
	var gm: Node = root.get_node("/root/GameManager")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)

	# —— 章一→二：伪造晋升册页（跳过 ChapterCard；_cinema=true 直通）
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.chapter = 1
	gs.last_port = "quanzhou"
	gs.era_trips = 5
	gs.record_trip("quanzhou", "mingzhou")
	gs.record_trip("mingzhou", "quanzhou")
	gs.record_trip("quanzhou", "ryukyu")
	gs.merchant_credit = 22
	_main.load_scene("quanzhou")
	await _settle(6)

	var cur: Dictionary = gs.chapter_def(1)
	gs.chapter = 2
	_main.call("_show_chapter_dialog", {
		"advanced": true,
		"resolved": false,
		"title": cur.get("advance_title", "北路开"),
		"text": cur.get("advance_text", ""),
		"scene": str(cur.get("advance_scene", "")),
		"years": int(cur.get("advance_years", 2)),
		"_cinema": true,
	})
	await _settle(10)

	var host: Node = _main.get("_chapter_host")
	_expect(host != null and is_instance_valid(host), "晋升册页已建")
	_expect(bool(_main.get("_chapter_advanced")), "记住 advanced")
	_expect(int(_main.get("_chapter_years")) == 2, "记住 years=2（%s）" % str(_main.get("_chapter_years")))

	var body_txt := _sheet_body()
	_expect(body_txt.find("【两年后・") >= 0, "册页含【两年后・日期】抬头")
	_expect(body_txt.find("这一路") >= 0, "册页含「这一路」摘要标")
	_expect(body_txt.find("代价") >= 0, "册页含「代价」标")
	_expect(body_txt.find("自") >= 0 and body_txt.find("至于") >= 0, "代价含「自…至于…」历法串")
	_expect(body_txt.find("这两年") >= 0 or body_txt.find("跑了") >= 0, "摘要含航次纪实")
	await _shot("01_chapter1_promote_sheet")

	# 题签帧：两年后・旧账 印晋
	var ch_name := str(gs.chapter_def().get("name", "旧账"))
	var node: CanvasLayer = _UT.promote_open(_main, 2, ch_name, str(cal.call("get_date_string")), Callable())
	await _hold_shot(node, "02_transition_promote")

	# 章二→三（years=3）再截一帧册页，确认「三年后」
	gs.from_dict({})
	cal.from_dict({"year": 1257, "month": 3, "day": 1})
	gs.chapter = 2
	gs.last_port = "hakata"
	gs.era_trips = 3
	gs.record_trip("quanzhou", "hakata")
	_main.load_scene("hakata")
	await _settle(6)
	cur = gs.chapter_def(2)
	gs.chapter = 3
	_main.call("_show_chapter_dialog", {
		"advanced": true,
		"resolved": false,
		"title": cur.get("advance_title", "南海路"),
		"text": cur.get("advance_text", ""),
		"scene": str(cur.get("advance_scene", "")),
		"years": int(cur.get("advance_years", 3)),
		"_cinema": true,
	})
	await _settle(10)
	body_txt = _sheet_body()
	_expect(body_txt.find("【三年后・") >= 0, "章二晋升含【三年后・】")
	await _shot("03_chapter2_promote_sheet")

	var node3: CanvasLayer = _UT.promote_open(_main, 3, str(gs.chapter_def().get("name", "")),
			str(cal.call("get_date_string")), Callable())
	await _hold_shot(node3, "04_transition_promote_ch3")

	# skip_years 末行契约（不改数值）
	cal.from_dict({"year": 1260, "month": 5, "day": 1})
	var lines: Array = gm.call("skip_years", 1)
	var joined := "\n".join(lines)
	_expect(joined.find("自") >= 0 and joined.find("至于") >= 0, "skip_years 末行自…至于…")
	_expect(joined.find("年至") < 0 and joined.find(" 年") < 0, "末行不再用「公元 年」空格格式")

	print("QA_CHAPTER_SHOTS ", _saved.size())
	if _fails.is_empty():
		print("QA_CHAPTER_PASS")
		quit(0)
	for f in _fails:
		print("QA_CHAPTER_FAIL ", f)
	quit(1)


func _sheet_body() -> String:
	var host: Node = _main.get("_chapter_host")
	if host == null or not is_instance_valid(host):
		return ""
	var scroll: Node = host.find_child("SheetScroll", true, false)
	if scroll == null:
		return ""
	for c in scroll.get_children():
		if c is Label:
			return str((c as Label).text)
	return ""


func _expect(ok: bool, msg: String) -> void:
	if ok:
		print("QA_CHAPTER_OK ", msg)
	else:
		_fails.append(msg)
		print("QA_CHAPTER_BAD ", msg)


func _hold_shot(node: CanvasLayer, stem: String) -> void:
	if node == null:
		print("QA_CHAPTER_SKIP_TRANSITION %s (headless)" % stem)
		return
	await _settle(36)
	await _shot(stem)
	if is_instance_valid(node):
		node.call("_abort")
	await _settle(4)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(stem: String) -> void:
	await _settle(2)
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		_fails.append("空帧 %s" % stem)
		return
	var path := "%s/%s.png" % [OUT_DIR, stem]
	var err := img.save_png(path)
	if err != OK:
		_fails.append("写失败 %s (%s)" % [stem, str(err)])
		return
	_saved.append(path)
	print("QA_CHAPTER_SHOT ", path)
