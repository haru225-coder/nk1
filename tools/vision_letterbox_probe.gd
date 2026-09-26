extends SceneTree
## 进出海战墨边（scripts/ui/CombatLetterbox.gd）的有窗口探针：在真海战场面（WorldMap + pending_battle）上
## 演一次入战、一次带 on_black 的出战，按节拍截屏，并量排版与信号。
## Run: DISPLAY=:2 godot --path /workspace/nk1 -s res://tools/vision_letterbox_probe.gd
## 截图落 /workspace/nk1-qa-shots/vision/（绝对路径，不进仓库）。headless 下墨边不上场，本探针只验静态题签就退出。

const VIEW := Vector2i(1280, 720)
const OUT_DIR := "/workspace/nk1-qa-shots/vision"
const Letterbox := preload("res://scripts/ui/CombatLetterbox.gd")
const Kit := preload("res://scripts/cutscene/cs_kit.gd")

var _fails: Array = []
var _saved: Array = []
var _covered_hits := 0
var _on_black_hits := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEW
	_check_titles()
	if Kit.is_headless():
		_expect(Letterbox.enter(root, "刺桐外海・接舷") == null, "headless 下静态入口应返回 null")
		_report()
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var gm := root.get_node("GameManager")
	var enemy := [{"type": "sea_falcon", "count": 2}]
	gm.pending_battle = {"battle": true, "power": 300.0, "player_power": 300.0,
		"enemy": enemy, "source": {"scene": "probe"}}
	var wm: Node = (load("res://scenes/WorldMap.tscn") as PackedScene).instantiate()
	root.add_child(wm)
	for _i in 30:
		await process_frame
	await _shot("00_combat_plain")

	# 入战
	var sub := "咸淳三年六月十二　%s" % Letterbox.enemy_note(enemy)
	_expect(sub.ends_with("二艘"), "敌船副题未按船种表写数：%s" % sub)
	var lb := Letterbox.enter(root, Letterbox.sea_title("刺桐外海", "接舷"), sub)
	_expect(lb != null, "有窗口时入战墨边未上场")
	if lb == null:
		_report()
		return
	var enter_done := [false]
	lb.finished.connect(func() -> void: enter_done[0] = true)
	for _i in 6:
		await process_frame
	await _shot("01_enter_closing")
	await lb.caption_shown
	await _shot("02_enter_caption")
	_check_layout(lb, "入战")
	while not enter_done[0]:
		await process_frame
	for _i in 3:
		await process_frame
	_expect(not is_instance_valid(lb) or lb.is_queued_for_deletion(), "入战演完节点未自删")
	await _shot("03_enter_done")

	# 出战（带 on_black：全黑时把战场换成空场）
	var ex := Letterbox.exit(root, Letterbox.outcome_title("board", "刺桐外海"),
		"咸淳三年六月十二　夺得海鹘一艘", func() -> void:
			_on_black_hits += 1
			wm.queue_free())
	_expect(ex != null, "出战墨边未上场")
	if ex == null:
		_report()
		return
	ex.covered.connect(func() -> void: _covered_hits += 1)
	var exit_done := [false]
	ex.finished.connect(func() -> void: exit_done[0] = true)
	await ex.caption_shown
	await _shot("04_exit_caption")
	_check_layout(ex, "出战")
	await ex.covered
	await _shot("05_exit_black")
	var img := root.get_texture().get_image()
	var mid := img.get_pixel(VIEW.x / 2, VIEW.y / 2)
	_expect(mid.v < 0.08, "出战合拢时画面中线未全黑（v=%.3f）" % mid.v)
	while not exit_done[0]:
		await process_frame
	await _shot("06_exit_done")
	_expect(_on_black_hits == 1 and _covered_hits == 1,
		"出战 on_black / covered 应各调一次（%d / %d）" % [_on_black_hits, _covered_hits])

	# 同时只留一副：新的顶掉旧的，旧的若带 on_black 须补调
	var hits := [0]
	var a := Letterbox.exit(root, "外洋・脱战", "", func() -> void: hits[0] += 1)
	await process_frame
	var b := Letterbox.enter(root, "外洋・遇敌")
	await process_frame
	_expect(hits[0] == 1, "被顶掉的出战未补调 on_black")
	_expect(root.get_tree().get_nodes_in_group(Letterbox.GROUP).size() == 1, "同时留了不止一副墨边")
	if is_instance_valid(b):
		b.call("_abort")
	if is_instance_valid(a):
		a.call("_abort")
	_report()


func _check_titles() -> void:
	_expect(Letterbox.sea_title("刺桐外海", "接舷") == "刺桐外海・接舷", "sea_title 拼法不对")
	_expect(Letterbox.sea_title("", "接舷") == "接舷", "海名空时不应补地名")
	_expect(Letterbox.outcome_title("win", "耽罗海") == "耽罗海・战罢", "win 事由不对")
	_expect(Letterbox.outcome_title("flee") == "脱战", "flee 事由不对")
	_expect(Letterbox.outcome_title("lose", "外洋") == "外洋・败退", "lose 事由不对")
	for w in ["惊艳", "沉浸", "打造"]:
		var src := FileAccess.get_file_as_string("res://scripts/ui/CombatLetterbox.gd")
		_expect(not src.contains(w), "墨边脚本里出现了禁词「%s」" % w)


func _check_layout(lb: CanvasLayer, tag: String) -> void:
	var h: float = lb.call("bar_height")
	var r: Rect2 = lb.call("caption_rect")
	_expect(is_equal_approx(h, 90.0), "%s墨边高应为 90（%.1f）" % [tag, h])
	_expect(r.position.y >= VIEW.y - h - 1.0 and r.end.y <= VIEW.y + 1.0,
		"%s题签没落在下墨边里：%s" % [tag, r])
	_expect(r.position.x >= 0.0 and r.end.x <= VIEW.x, "%s题签冲出画布：%s" % [tag, r])
	print("  %s 墨边 %.0f  题签 %s" % [tag, h, r])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/letterbox_%s.png" % [OUT_DIR, name]
	var err := root.get_texture().get_image().save_png(path)
	if err == OK:
		_saved.append(path)
	else:
		_fails.append("截图失败 %s（%d）" % [path, err])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)


func _report() -> void:
	for p in _saved:
		print("  shot ", p)
	# headless 契约探针允许 shots=0；有窗口路径若零截图则失败。
	if not Kit.is_headless() and _saved.is_empty() and _fails.is_empty():
		_fails.append("有窗口路径未产出截图")
	if _fails.is_empty():
		print("VISION_LETTERBOX_PROBE_OK shots=%d" % _saved.size())
		quit(0)
	else:
		for f in _fails:
			print("  ✗ ", f)
		print("VISION_LETTERBOX_PROBE_FAIL %d" % _fails.size())
		quit(1)
