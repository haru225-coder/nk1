extends SceneTree
## lane w54-audio：同一帧连要几声，声部上限照样作数。一段钉一条，回退即红。
##   修前 AudioHooks 数「根下挂着 nk1_sfx 的播放器」当声部数，可播放器是 call_deferred 挂上去的——同一帧要的几声
##   一个也数不到，上限 6 形同虚设：一帧里要七声就叠七声（headless 下根下从来没有播放器，上限更是从不作数）。
##   现改为放行那一刻就占一格声部、按声样长度（播放器放完自己释放亦同）让出；headless 记同一本账。
##   一、同一刻要七样不同的声（不同声样，节流挡不着）：前六样响、第七样记 voices；此刻占着六格。
##   二、放完让出：探针钟拨过 250 毫秒，最短那一声（命中 0.2 秒）放完、空出一格，再要一声照响；拨过最长那一声，六格全空。
##   三、探针钟往回拨（拨回 −1 读真钟）不把声部卡死：远在将来的旧账算失效；节流时戳在将来的也不挡（开炮照响）。
##   四、带窗口（DISPLAY=:2，非 headless）才跑：-s 工具脚本缺省不建播放器（发声账照记；带窗口的门禁退出时不留半截在放的声——
##       Godot 会把没混完的 playback 报成「ObjectDB instances leaked at exit」）；探针开 players_in_tools 后，同一帧七声只在根下
##       建六个播放器；放完都自己释放、声部全空。headless 下印一行跳过。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_voices_probe.gd（经门锁跑；第四段要带窗口另跑一遍）
## 末行 QA_W54_AUDIO_VOICES PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_VOICES"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")

## 七样不同的声（SfxSynth 八样里去掉 combat_flee，第二段补要它）
const SEVEN := [&"transition", &"combat_start", &"combat_fire", &"combat_hit", &"combat_board", &"combat_win", &"combat_lose"]

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
	_host.name = "VoicesProbeHost"
	root.add_child(_host)
	await process_frame
	print("== 一、同一刻要七声")
	_sec_burst()
	print("== 二、放完让出声部")
	_sec_release()
	print("== 三、探针钟往回拨不卡死")
	_sec_clock_back()
	print("== 四、带窗口：根下的播放器")
	await _sec_window()
	_AUDIO.clock_ms = -1
	_report()


static func _whys() -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		out.append(str(r.get("why", "?")))
	return out


func _sec_burst() -> void:
	_AUDIO.clock_ms = 5_000_000
	_AUDIO.journal.clear()
	for cue in SEVEN:
		_AUDIO.play_cue(_host, cue, -6.0)
	var w := _whys()
	_check(w == ["", "", "", "", "", "", "voices"], "七样同一刻：前六样响、第七样记 voices（%s）" % str(w))
	_check(_AUDIO.voices_now() == 6, "此刻占着六格声部（%d）" % _AUDIO.voices_now())


func _sec_release() -> void:
	var hit_ms := int(ceil(_AUDIO.stream_for(&"combat_hit").get_length() * 1000.0))
	var longest := 0
	for cue in SEVEN:
		longest = maxi(longest, int(ceil(_AUDIO.stream_for(cue).get_length() * 1000.0)))
	_AUDIO.clock_ms = 5_000_000 + 250
	_check(hit_ms < 250 and _AUDIO.voices_now() == 5, "拨过 250 毫秒：命中那声（%d 毫秒）放完、空出一格，占着五格（%d）" % [hit_ms, _AUDIO.voices_now()])
	_AUDIO.journal.clear()
	_AUDIO.play_cue(_host, &"combat_flee", -6.0)
	_check(_whys() == [""], "空出那一格再要一声照响（%s）" % str(_whys()))
	_AUDIO.clock_ms = 5_000_000 + 250 + longest + 10
	_check(_AUDIO.voices_now() == 0, "拨过最长那一声（%d 毫秒）：六格全空（%d）" % [longest, _AUDIO.voices_now()])


func _sec_clock_back() -> void:
	_AUDIO.clock_ms = 9_000_000
	_AUDIO.journal.clear()
	for cue in SEVEN.slice(0, 6):
		_AUDIO.play_cue(_host, cue, -6.0)
	_check(_AUDIO.voices_now() == 6, "钟在 9 000 000 毫秒处占满六格")
	_AUDIO.clock_ms = -1
	_check(_AUDIO.voices_now() == 0, "钟拨回真钟（%d 毫秒）：远在将来的旧账失效，声部不卡死（%d）" % [Time.get_ticks_msec(), _AUDIO.voices_now()])
	_AUDIO.journal.clear()
	_AUDIO.play_cue(_host, &"combat_fire", -30.0)
	_check(_whys() == [""], "节流时戳停在将来（9 000 000 毫秒那一炮）也不挡真钟下的开炮（%s）" % str(_whys()))


static func _players(tree_root: Node) -> int:
	var n := 0
	for c in tree_root.get_children():
		if c is AudioStreamPlayer and c.has_meta(&"nk1_sfx"):
			n += 1
	return n


func _sec_window() -> void:
	if DisplayServer.get_name() == "headless":
		print("  · 跳过：headless 不建播放器（带窗口 DISPLAY=:2 另跑一遍走这一段）")
		return
	_AUDIO.clock_ms = -1
	# 前三段的声（工具脚本里不建播放器，只占声部账）：按墙钟等声部让出来（帧数不作准，无垂直同步时一帧不到一毫秒）
	var w0 := Time.get_ticks_msec()
	while (_AUDIO.voices_now() > 0 or _players(root) > 0) and Time.get_ticks_msec() - w0 < 8000:
		await process_frame
	_check(_players(root) == 0, "前几段的播放器都放完释放了（等了 %d 毫秒）" % (Time.get_ticks_msec() - w0))
	_AUDIO.journal.clear()
	_AUDIO.play_cue(_host, &"combat_board", -30.0)
	await process_frame
	await process_frame
	_check(_whys() == [""] and _players(root) == 0, "-s 工具脚本缺省不建播放器：发声账记响、根下没有播放器（%d）" % _players(root))
	var w1 := Time.get_ticks_msec()
	while _AUDIO.voices_now() > 0 and Time.get_ticks_msec() - w1 < 8000:
		await process_frame
	_AUDIO.players_in_tools = true
	_AUDIO.journal.clear()
	for cue in SEVEN:
		_AUDIO.play_cue(_host, cue, -30.0)
	await process_frame
	await process_frame
	_check(_players(root) == 6, "同一帧七声：根下只建六个播放器（%d）" % _players(root))
	var t0 := Time.get_ticks_msec()
	while (_players(root) > 0 or _AUDIO.voices_now() > 0) and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	_check(_players(root) == 0 and _AUDIO.voices_now() == 0, "放完都自己释放、声部全空（%d 毫秒内；播放器 %d、声部 %d）" % [
		Time.get_ticks_msec() - t0, _players(root), _AUDIO.voices_now()])
	_AUDIO.players_in_tools = false
