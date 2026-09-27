extends SceneTree
## Lane Q：酒馆新闻墙 / 市井札薄巡检。
## 截图落 /workspace/nk1-qa-shots/tavern/（空墙 + 有札两条）。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_tavern_news_wall_screenshots.gd
## headless：只验接线，不强制截图。

const VIEW := Vector2i(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/tavern"
const Kit := preload("res://scripts/cutscene/cs_kit.gd")

var _main: Node
var _gs: Node
var _saved: Array = []
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_TAVERN_NEWS_WALL_BEGIN")
	_check_wiring()
	if Kit.is_headless():
		_report()
		return

	_gs = root.get_node("GameState")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	for _i in 8:
		await process_frame

	_gs.last_port = "quanzhou"
	_gs.money = maxi(int(_gs.money), 500)
	# 清空已见新闻 → 空墙
	_gs.news_seen = []
	await _goto("quanzhou_tavern")
	_expect(_find_label(_main, "墙上") == null, "无新闻时不上「墙上」")
	await _shot("01_tavern_wall_empty")

	# 投放三条（新的在前：recent_news 逆序 news_seen）
	_gs.news_seen = [
		"n_1256_03_taixue",
		"n_1258_09_three_routes",
		"n_1273_03_fanfang_panic",
	]
	await _goto("quanzhou_tavern")
	_expect(_find_label(_main, "墙上") != null, "有新闻须现「墙上」分区")
	_expect(_find_label(_main, "断臂老兵") != null or _text_has(_main, "断臂老兵"), "札记含说话人「断臂老兵」")
	_expect(_text_has(_main, "蕃坊") or _text_has(_main, "香药") or _text_has(_main, "酒馆传闻"), "札记含已投放新闻正文片段")
	await _shot("02_tavern_wall_slips")

	_report()


func _check_wiring() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/Main.gd")
	_expect("_setup_news_wall" in main_src and "_TAVERN_NEWS_WALL.mount" in main_src, "Main 薄调 _TAVERN_NEWS_WALL.mount")
	_expect("_setup_news_wall()" in main_src, "_setup_tavern 调用 _setup_news_wall")
	var wall_src := FileAccess.get_file_as_string("res://scripts/ui/TavernNewsWall.gd")
	_expect("recent_news" in wall_src and "news_text" in wall_src, "TavernNewsWall 消费 recent_news/news_text")
	_expect("paper_card" in wall_src, "札记用 UiTheme.paper_card")
	_expect("墙上" in wall_src, "分区题「墙上」")
	for bad in ["惊艳", "沉浸", "打造", "视觉盛宴", "placeholder", "玩家"]:
		_expect(bad not in wall_src, "TavernNewsWall 无「%s」" % bad)


func _goto(scene_id: String) -> void:
	_main.load_scene(scene_id)
	for _i in 6:
		await process_frame
	RenderingServer.force_draw()
	await process_frame


func _shot(name: String) -> void:
	RenderingServer.force_draw()
	await process_frame
	var tex = root.get_texture()
	if tex == null:
		_fails.append("截屏失败 %s (null texture)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		_fails.append("截屏失败 %s (null image)" % name)
		return
	var sample := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var corner := img.get_pixel(8, 8)
	if sample.get_luminance() < 0.02 and corner.get_luminance() < 0.02:
		_fails.append("截屏过暗 %s lum=%.3f/%.3f" % [name, sample.get_luminance(), corner.get_luminance()])
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	if err != OK:
		_fails.append("save_png %s err=%d" % [path, err])
		return
	_saved.append(path)
	print("SHOT ", path, " size=", img.get_width(), "x", img.get_height())


func _find_label(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n
	for c in n.get_children():
		var hit := _find_label(c, text)
		if hit != null:
			return hit
	return null


func _text_has(n: Node, needle: String) -> bool:
	if n is Label and needle in (n as Label).text:
		return true
	if n is RichTextLabel and needle in (n as RichTextLabel).get_parsed_text():
		return true
	for c in n.get_children():
		if _text_has(c, needle):
			return true
	return false


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK ", msg)
	else:
		_fails.append(msg)
		print("FAIL ", msg)


func _report() -> void:
	print("QA_TAVERN_NEWS_WALL_SHOTS %d" % _saved.size())
	for p in _saved:
		print("  ", p)
	if not _fails.is_empty():
		print("QA_TAVERN_NEWS_WALL_FAIL")
		for f in _fails:
			print("  fail ", f)
		quit(1)
	if not Kit.is_headless() and _saved.size() < 2:
		print("QA_TAVERN_NEWS_WALL_FAIL need ≥2 shots")
		quit(1)
	print("QA_TAVERN_NEWS_WALL_OK")
	quit(0)
