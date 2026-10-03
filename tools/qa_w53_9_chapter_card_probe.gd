extends SceneTree
## lane w53-9：章节卡的题记读得完、题记一句一列（四章 × 1280×720 / 1024×768 两种窗口）。
## 原先退场钉死在 6.3 秒：题记全显 1.8–2.1 秒、出处全显 1.0–1.5 秒就开始淡去；「点击继续」章名一写出（约 2.05 秒）就亮，
## 那时点一下只是补全题记；题记只靠 max_extent 折列——720 高下二、三章对句两列、一、四章一列到底，4:3 下四章全成一列。
## 断言（每章每种窗口）：
##   一、题记列数 = 句数（按「，。？！；」切，上句在右）；出处一列。
##   二、题记与出处全部全显之后、开始淡去之前，至少留「（题记 + 出处字数）÷ 5」秒，夹在 2.5–5 秒（留 0.1 秒帧差）。
##   三、「点击继续」不早于全部全显才亮，且淡去前亮过。
##   四、卡在 14 秒内收场（不挂住）。
## 另验点击（第二章、1280×720）：写到题记中途点一下 = 补全且不退场、再停 0.6 秒仍不退场，第二下才退场；
## 印已落定（6 秒档旧口径 T_SEAL + 0.5）而出处还没写完时点一下 = 补全出处，不是直接退场（出处没露全就淡去）。
## 驱动：卡建好后停掉它自己的 _process，按 1/60 秒逐帧调 _step（与 _process 每帧的调用同一入口），时间线确定、不吃机器忙闲。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_w53_9_chapter_card_probe.gd   # 须带窗口：headless 下章节卡当帧收场
## 输出末行 QA_W53_9_CHAPTER_CARD OK | FAIL <n>；rc 0 / 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W53_9_CHAPTER_CARD"
const DATA := "res://data/cutscenes.json"
const INK_TEXT := "res://scripts/cutscene/cs_ink_text.gd"
const DT := 1.0 / 60.0
const SIZES := [Vector2i(1280, 720), Vector2i(1024, 768)]
const CANVAS := {Vector2i(1280, 720): Vector2(1280, 720), Vector2i(1024, 768): Vector2(1280, 960)}
const CLAUSE := "，。？！；"
## 旧口径「印落定」时刻（T_SEAL 4.6 + 0.5）：点击分界的回退判据用
const OLD_READY := 5.1

var _tally: ScriptErrTally
var _fails := 0
var _reported := false
var _card: GDScript
var _chapters: Dictionary = {}


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _expect(ok: bool, msg: String) -> void:
	if ok:
		print("  ✓ " + msg)
	else:
		print("  ✗ " + msg)
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		_expect(false, "须带窗口跑（headless 下章节卡当帧收场，量不了时间线与版式）")
		_report()
		return
	_card = load("res://scripts/cutscene/ChapterCard.gd") as GDScript
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if _card == null or typeof(parsed) != TYPE_DICTIONARY:
		_expect(false, "ChapterCard.gd / cutscenes.json 取不到")
		_report()
		return
	_chapters = (parsed as Dictionary).get("chapters", {})
	for wh in SIZES:
		root.size = wh
		await _frames(8)
		for n in [1, 2, 3, 4]:
			await _natural(n, wh)
	root.size = SIZES[0]
	await _frames(8)
	await _clicks()
	_report()


## 卡建好、停掉它自己的逐帧推进，交给探针按 DT 调 _step
func _spawn(n: int) -> Node:
	var c: Node = _card.call("play", root, n, DATA)
	await process_frame
	c.set_process(false)
	return c


## 取题记 / 出处两段字（InkText）与全部文字段
func _parts(c: Node) -> Dictionary:
	var epi := str(c.get("_epi"))
	var out := {"ep": null, "sr": null, "texts": []}
	for it in c.get("_items"):
		var node: Node = it["node"]
		var scr: Script = node.get_script()
		if scr == null or scr.resource_path != INK_TEXT:
			continue
		(out["texts"] as Array).append(node)
		var tx := str(node.get("text")).replace("\n", "")
		if tx == epi:
			out["ep"] = node
		elif tx.begins_with("——"):
			out["sr"] = node
			out["sr_start"] = float(it["start"])
	return out


func _cols(node: Node) -> int:
	var xs := {}
	var gl: Array = node.get("_glyphs")
	for g in gl:
		xs[int(roundf(float(g["x"]) + float(g["w"]) * 0.5))] = true
	return xs.size()


func _clauses(s: String) -> int:
	var n := 0
	var seg := ""
	for i in range(s.length()):
		seg += s[i]
		if CLAUSE.contains(s[i]):
			n += 1
			seg = ""
	return n + (1 if seg.strip_edges() != "" else 0)


func _all_revealed(texts: Array) -> bool:
	for x in texts:
		if not (x as Node).call("is_revealed"):
			return false
	return true


func _natural(n: int, wh: Vector2i) -> void:
	var entry: Dictionary = _chapters.get(str(n), {})
	var epi := str(entry.get("epigraph", ""))
	var src := "——" + str(entry.get("epigraph_src", ""))
	var c: Node = await _spawn(n)
	var where := "第%d章 %dx%d" % [n, wh.x, wh.y]
	var cv: Vector2 = c.get("_canvas")
	_expect(cv == CANVAS[wh], "%s 画布 %s（应 %s，不然 4:3 这一档没量到）" % [where, cv, CANVAS[wh]])
	var p := _parts(c)
	var ep: Node = p["ep"]
	var sr: Node = p["sr"]
	if ep == null or sr == null:
		_expect(false, "%s 找不到题记 / 出处两段字（题记「%s」）" % [where, epi])
		c.queue_free()
		return
	_expect(_cols(ep) == _clauses(epi) and _cols(sr) == 1,
		"%s 题记一句一列：「%s」%d 句 → %d 列；出处 %d 列" % [where, epi, _clauses(epi), _cols(ep), _cols(sr)])
	var t_all := -1.0
	var t_fade := -1.0
	var t_hint := -1.0
	var guard := 0
	while not bool(c.get("_done")) and guard < int(20.0 / DT):
		guard += 1
		c.call("_step", DT)
		var t := float(c.get("_t"))
		if t_all < 0.0 and _all_revealed(p["texts"]):
			t_all = t
		if t_fade < 0.0 and bool(ep.call("is_fading")):
			t_fade = t
		var h: Label = c.get("_hint")
		if t_hint < 0.0 and h != null and h.modulate.a > 0.05:
			t_hint = t
	var t_end := float(c.get("_t"))
	var need := clampf(float(epi.length() + src.length()) / 5.0, 2.5, 5.0)
	_expect(t_all > 0.0 and t_fade > 0.0 and t_fade - t_all >= need - 0.1,
		"%s 全部全显 %.2f 秒、淡去起 %.2f 秒：留读 %.2f 秒 ≥ %.2f 秒（%d 字 ÷ 5，夹 2.5–5）" % [where, t_all, t_fade, t_fade - t_all, need, epi.length() + src.length()])
	_expect(t_hint >= t_all - 0.02 and t_hint < t_fade,
		"%s 「点击继续」%.2f 秒亮：不早于全部全显（%.2f）、淡去（%.2f）前亮过" % [where, t_hint, t_all, t_fade])
	_expect(bool(c.get("_done")) and t_end <= 14.0, "%s 卡 %.2f 秒收场（≤ 14 秒，不挂住）" % [where, t_end])
	if is_instance_valid(c):
		c.queue_free()
	await process_frame


func _click(c: Node) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(640, 360)
	c.call("_input", ev)


func _step_to(c: Node, t: float) -> void:
	while float(c.get("_t")) < t - 1e-4 and not bool(c.get("_done")):
		c.call("_step", minf(DT, t - float(c.get("_t"))))


func _clicks() -> void:
	# 一、题记写到中途点一下：补全、不退场；停 0.6 秒仍不退场；第二下才退场
	var c: Node = await _spawn(2)
	var p := _parts(c)
	var ep: Node = p["ep"]
	if ep == null or p["sr"] == null:
		_expect(false, "点击：第二章找不到题记 / 出处")
		c.queue_free()
		return
	_step_to(c, 3.6)
	var mid := not bool(ep.call("is_revealed"))
	_click(c)
	var done1 := _all_revealed(p["texts"]) and not bool(ep.call("is_fading"))
	_step_to(c, float(c.get("_t")) + 0.6)
	var hold := not bool(ep.call("is_fading"))
	_click(c)
	c.call("_step", DT)
	var gone := bool(ep.call("is_fading"))
	_expect(mid and done1 and hold and gone,
		"点击：题记写到中途（%s）点一下补全且不退场（%s）、再停 0.6 秒仍不退场（%s）、第二下退场（%s）" % [mid, done1, hold, gone])
	c.queue_free()
	await process_frame
	# 二、印已落定、出处还没写完时点一下：补全出处，不直接退场
	c = await _spawn(2)
	p = _parts(c)
	var sr: Node = p["sr"]
	var src_done := float(p.get("sr_start", 0.0)) + float(sr.call("reveal_duration"))
	var at := OLD_READY + 0.02
	_expect(src_done > at + DT, "点击分界：第二章出处 %.2f 秒才写完、晚于印落定 %.2f 秒（这一窗才量得到）" % [src_done, OLD_READY])
	_step_to(c, at)
	var partial := not bool(sr.call("is_revealed"))
	_click(c)
	var whole := bool(sr.call("is_revealed")) and not bool((p["ep"] as Node).call("is_fading"))
	_expect(partial and whole,
		"点击分界：%.2f 秒（印已落定、出处未写完=%s）点一下 = 补全出处且不退场（%s），不是出处没露全就淡去" % [at, partial, whole])
	c.queue_free()
	await process_frame


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("%s %s" % [TAG, "OK" if _fails == 0 else "FAIL %d" % _fails])
	quit(1 if _fails > 0 else 0)
