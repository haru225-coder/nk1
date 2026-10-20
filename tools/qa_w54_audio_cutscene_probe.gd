extends SceneTree
## lane w54-audio：过场补挂的声（SfxCues 表里过场两行）。一段钉一条，回退即红。
##   过场原先一声不出（只有 Main.play_transition 那一幕墨幕敲一声磬）：朱印落纸（cs_seal 触纸、发 impacted、画面一颤）、
##   章节卡开卷（「第N章」那张卡）都只有画面。
##   一、表：两行都在、标 added、各带 gap_ms；章节卡那声与墨幕同在收声组 bell。
##   二、朱印（headless 真起 cs_seal 控件）：自 1.75 倍落下、触纸那一刻（advance 过 FALL）记一声 cs_seal，回弹、洇开不再响；
##       跳过过场一口气补全（finish_reveal）同样只在触纸那一下响一声；三方印同一帧补全（跳过整段过场）只响一声、其余记 gap。
##   三、章节卡（ChapterCard.play，headless 当帧收场）：开卷记一声磬 cs_chapter；墨幕紧接着起（400 毫秒内），章节卡那声收掉、只剩一声。
##   四、开关 sfx_cues 关：两处都记 off、不响；印照样触纸（impacted 照发）。
## 用法：godot --headless --path . -s res://tools/qa_w54_audio_cutscene_probe.gd（经门锁跑）
## 末行 QA_W54_AUDIO_CUTSCENE PASS|FAIL cases=N fails=M；fails>0 退 1。本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W54_AUDIO_CUTSCENE"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const _AUDIO := preload("res://scripts/audio/AudioHooks.gd")
const _SFX := preload("res://scripts/audio/SfxCues.gd")
const _Switches := preload("res://scripts/combat/CombatSwitches.gd")
const Seal := preload("res://scripts/cutscene/cs_seal.gd")
const Card := preload("res://scripts/cutscene/ChapterCard.gd")

var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _clock := 9_000_000
var _hits := 0


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
	_Switches.reset()
	print("== 一、表")
	_sec_table()
	print("== 二、朱印落纸")
	await _sec_seal()
	print("== 三、章节卡开卷")
	await _sec_card()
	print("== 四、开关 sfx_cues 关")
	await _sec_off()
	_Switches.reset()
	_AUDIO.clock_ms = -1
	_report()


func _fresh() -> void:
	_clock += 10_000
	_AUDIO.clock_ms = _clock
	_AUDIO.journal.clear()


static func _whys(hook: StringName) -> Array:
	var out: Array = []
	for r in _AUDIO.journal:
		if StringName(r.get("hook", &"")) == hook:
			out.append(str(r.get("why", "?")))
	return out


func _sec_table() -> void:
	var ok := true
	for hook in [&"cs_seal", &"cs_chapter"]:
		var row: Dictionary = _SFX.HOOKS.get(hook, {})
		ok = ok and bool(row.get("added", false)) and int(row.get("gap_ms", 0)) > 0
	_check(ok, "过场两行在、标 added、各带 gap_ms")
	_check(StringName(_SFX.HOOKS.get(&"cs_chapter", {}).get("group", &"")) == &"bell", "章节卡那声与墨幕同在收声组 bell")


func _seal(txt: String) -> Control:
	var s: Control = Seal.new()
	s.call("configure", txt, {"cell": 40.0})
	s.connect("impacted", func() -> void: _hits += 1)
	root.add_child(s)
	return s


func _sec_seal() -> void:
	var fall := float(Seal.FALL)
	var s := _seal("北")
	await process_frame
	_hits = 0
	_fresh()
	s.call("advance", fall * 0.5)
	_check(_whys(&"cs_seal").is_empty() and _hits == 0, "还在半空（落下一半）：不响")
	s.call("advance", fall * 0.5 + 0.01)
	_check(_whys(&"cs_seal") == [""] and _hits == 1, "触纸那一刻（impacted）记一声 cs_seal（%s）" % str(_whys(&"cs_seal")))
	_AUDIO.clock_ms = _clock + 500
	s.call("advance", 0.3)
	s.call("advance", 0.5)
	_check(_whys(&"cs_seal") == [""] and _hits == 1, "回弹、印泥洇开不再响")
	s.queue_free()
	# 跳过过场：一口气补全
	var t := _seal("扶桑")
	await process_frame
	_fresh()
	t.call("finish_reveal")
	t.call("finish_reveal")
	_check(_whys(&"cs_seal") == [""], "跳过过场一口气补全（finish_reveal）：触纸那一下响一声，再补不响（%s）" % str(_whys(&"cs_seal")))
	t.queue_free()
	# 三方印同一帧补全
	var three := [_seal("南"), _seal("西"), _seal("乙卯")]
	await process_frame
	_fresh()
	for x in three:
		x.call("finish_reveal")
	var w := _whys(&"cs_seal")
	_check(w.count("") == 1 and w.count("gap") == 2, "三方印同一帧补全（跳过整段）：只响一声、其余记 gap（%s）" % str(w))
	for x in three:
		x.queue_free()
	await process_frame


func _sec_card() -> void:
	_fresh()
	var card: Node = Card.play(root, 1)
	_check(card != null and _whys(&"cs_chapter") == [""], "章节卡（ChapterCard.play 第一章）开卷记一声磬 cs_chapter（%s）" % str(_whys(&"cs_chapter")))
	_AUDIO.clock_ms = _clock + 400
	var host := Node.new()
	root.add_child(host)
	_SFX.play(host, &"transition")
	var rows: Array = []
	for r in _AUDIO.journal:
		rows.append([String(r.get("hook", &"")), str(r.get("why", "?"))])
	_check(rows == [["cs_chapter", ""], ["cs_chapter", "cut"], ["transition", ""]],
		"墨幕 400 毫秒后紧接着起：章节卡那声收掉、只剩一声（%s）" % str(rows))
	for _i in 3:
		await process_frame
	_check(card == null or not is_instance_valid(card), "headless 下章节卡当帧收场（不卡流程）")
	host.queue_free()
	await process_frame


func _sec_off() -> void:
	_Switches.set_on(_SFX.SWITCH, false)
	var s := _seal("北")
	await process_frame
	_hits = 0
	_fresh()
	s.call("finish_reveal")
	Card.play(root, 2)
	_Switches.reset()
	_check(_whys(&"cs_seal") == ["off"] and _whys(&"cs_chapter") == ["off"] and _hits == 1,
		"开关关：朱印、章节卡都记 off、不响；印照样触纸（impacted %d 次）" % _hits)
	s.queue_free()
	for _i in 3:
		await process_frame
