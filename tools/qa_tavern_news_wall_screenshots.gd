extends SceneTree
## Lane Q：酒馆新闻墙 / 市井札薄巡检。
## 截图落 ${NK1_SHOT_DIR:-/workspace/nk1-qa-shots}/tavern/（空墙 + 有札两条）。
## 用法：DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_tavern_news_wall_screenshots.gd
##       godot --headless --path /workspace/nk1 -s res://tools/qa_tavern_news_wall_screenshots.gd -- --contract   # 只验接线，不截图
## 默认严格须出 2 张：空视口 / 一色空图 / 张数不足 / headless 未开 --contract 一律非零退出（shot_gate.gd）。
## 等待按演出推进（lane gd14）：帧数只作排版下限，补间演完才截，上界按墙钟，见 probe_clock.gd；
##   压帧自检：NK1_PROBE_SLOW_MS=300 DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/qa_tavern_news_wall_screenshots.gd

const VIEW := Vector2i(1280, 720)
var OUT_DIR := ShotGate.out_dir("tavern")
const TAG := "QA_TAVERN_NEWS_WALL"
const EXPECTED_SHOTS := 2
const ShotGate := preload("res://tools/shot_gate.gd")
const Clock := preload("res://tools/probe_clock.gd")

var _main: Node
var _gs: Node
var _saved: Array = []
var _fails: Array = []
var _contract := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_contract = ShotGate.contract_mode()
	var no_render := ShotGate.no_render_reason()
	if not _contract and no_render != "":
		quit(ShotGate.fail_no_render(TAG, no_render, EXPECTED_SHOTS))
		return
	if not _contract:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("QA_TAVERN_NEWS_WALL_BEGIN")
	_check_wiring()
	if _contract:
		_report()
		return

	_gs = root.get_node("GameState")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	Clock.frame_pressure(self)
	root.add_child(_main)
	await _settle(8)

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
	await _settle(6)
	RenderingServer.force_draw()
	await process_frame


func _shot(name: String) -> void:
	if _contract:
		return
	RenderingServer.force_draw()
	await process_frame
	await RenderingServer.frame_post_draw
	var img := ShotGate.shot(root, "%s/%s.png" % [OUT_DIR, name], _saved, _fails)
	if img == null:
		return
	var sample := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var corner := img.get_pixel(8, 8)
	if sample.get_luminance() < 0.02 and corner.get_luminance() < 0.02:
		_fails.append("截屏过暗 %s lum=%.3f/%.3f" % [name, sample.get_luminance(), corner.get_luminance()])


## 先过 n 帧（排版 / 延迟调用按帧），再等补间演完；墙钟上界见 probe_clock.gd
func _settle(n: int) -> void:
	if not await Clock.settle(self, n):
		_expect(false, "演出 %d ms 内没静下来（有限补间仍在跑）" % Clock.WAIT_MS)


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
	# 旧写法 quit(1) 后未 return 又落到 quit(0)：有失败也退 0。统一交 ShotGate 收尾。
	quit(ShotGate.finish_contract(TAG, _fails) if _contract else ShotGate.finish_shots(TAG, _saved, EXPECTED_SHOTS, OUT_DIR, _fails))
