extends SceneTree
## lane w54-audio：墨幕被新墨幕顶掉时，旧幕那声磬跟着收，不叠成两声。一段钉一条，回退即红。
##   修前 Main.play_transition 一调就敲一声磬（0.9 秒），UiTransition.play 起新幕时把旧幕当场收掉（「同时只留一幕」），
##   旧幕那声磬却照响：晋升翻页（ChapterSheet）全黑时 load_scene、排守城 / 终局岸带头一回再起一幕题签（_shore_title_once），
##   0.32 秒后第二声磬叠在第一声上。现在墨幕那行入收声组「磬」：同组新声一响，还在响的旧声当场收掉。
##   一、表：墨幕过渡那行在收声组 bell。
##   二、声部账（headless，探针钟）：两声磬隔 320 毫秒——第二声响、第一声记 cut、只占一格；不同组的声（开炮）不受牵连。
##   三、真起 Main（headless）：play_transition 的全黑回调里再 play_transition（_shore_title_once 那一路的形状）——
##       两声都要过、头一声被收，同一刻只剩一声磬。
##   四、带窗口（DISPLAY=:2）才跑：真建的播放器——第二声起来后根下只剩一个墨幕磬，第一声那只停了、释放了。headless 下印一行跳过。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_bell_probe.gd（经门锁跑；第四段要带窗口另跑一遍）
## 末行 QA_W54_AUDIO_BELL PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_BELL"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _host: Node = null


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	await process_frame
	_host = Node.new()
	root.add_child(_host)
	await process_frame
	print("== 一、表")
	var row: Dictionary = _SFX.HOOKS.get(&"transition", {})
	_check(StringName(row.get("group", &"")) == &"bell", "墨幕过渡那行在收声组 bell（%s）" % str(row.get("group", "（无）")))
	print("== 二、声部账：两声磬隔 320 毫秒")
	_sec_book()
	print("== 三、真起 Main：全黑回调里再起一幕")
	await _sec_main()
	print("== 四、带窗口：根下的播放器")
	await _sec_window()
	_AUDIO.clock_ms = -1
	_report()


## 发声账里各笔 [挂点, why]
static func _rows() -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		out.append([String(r.get("hook", &"")), str(r.get("why", "?"))])
	return out


func _sec_book() -> void:
	_AUDIO.clock_ms = 7_000_000
	_AUDIO.journal.clear()
	_SFX.play(_host, &"sea_fire")
	_SFX.play(_host, &"transition")
	_AUDIO.clock_ms = 7_000_320
	_SFX.play(_host, &"transition")
	var rows := _rows()
	_check(rows == [["sea_fire", ""], ["transition", ""], ["transition", "cut"], ["transition", ""]],
		"第二声磬响、第一声记 cut（%s）" % str(rows))
	_check(_AUDIO.voices_now() == 2, "此刻只占两格：一声磬 + 一排炮（%d）" % _AUDIO.voices_now())
	_AUDIO.clock_ms = 7_000_000 + 2_000
	_check(_AUDIO.voices_now() == 0, "放完让出（%d）" % _AUDIO.voices_now())


func _sec_main() -> void:
	var main: Node = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 3:
		await process_frame
	_AUDIO.clock_ms = 8_000_000
	_AUDIO.journal.clear()
	var inner_done := [false]
	# headless 下 play_transition 不演墨幕、当帧调全黑回调就返回（不挂起），两幕在同一刻
	main.call("play_transition", "甲", "", func() -> void:
		main.call("play_transition", "乙", "", func() -> void: inner_done[0] = true))
	var bells := 0
	var cuts := 0
	for r in _rows():
		if r[0] == "transition":
			if r[1] == "":
				bells += 1
			elif r[1] == "cut":
				cuts += 1
	_check(inner_done[0], "全黑回调里那一幕也走完了（headless 当帧直通）")
	_check(bells == 2 and cuts == 1, "两幕各要一声磬、头一声被收（响 %d、收 %d；%s）" % [bells, cuts, str(_rows())])
	_check(_AUDIO.voices_now() == 1, "同一刻只剩一声磬（声部 %d）" % _AUDIO.voices_now())
	main.queue_free()
	await process_frame
	_AUDIO.clock_ms = 8_000_000 + 2_000


static func _bell_players(tree_root: Node) -> Array:
	var out: Array = []
	for c in tree_root.get_children():
		if c is AudioStreamPlayer and StringName(c.get_meta(&"nk1_sfx", &"")) == &"transition":
			out.append(c)
	return out


func _sec_window() -> void:
	if DisplayServer.get_name() == "headless":
		print("  · 跳过：headless 不建播放器（带窗口 DISPLAY=:2 另跑一遍走这一段）")
		return
	_AUDIO.clock_ms = -1
	var w0 := Time.get_ticks_msec()
	while (_AUDIO.voices_now() > 0 or not _bell_players(root).is_empty()) and Time.get_ticks_msec() - w0 < 8000:
		await process_frame
	_AUDIO.journal.clear()
	var first := _AUDIO.play_cue(_host, &"transition", -30.0, {"hook": &"transition", "group": &"bell"})
	await process_frame
	await process_frame
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 320:
		await process_frame
	var first_playing := first != null and is_instance_valid(first) and first.playing
	_SFX.play(_host, &"transition")
	await process_frame
	await process_frame
	var bells := _bell_players(root)
	_check(first_playing, "头一声磬在响（320 毫秒处）")
	_check(bells.size() == 1 and not bells.has(first), "第二声起来后根下只剩一个墨幕磬，头一声那只停了、释放了（%d 只）" % bells.size())
