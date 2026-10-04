extends SceneTree
## lane w53-9：章节卡的题记读得完、按宽度折列、油画窗不压字、点一下不刚写全就退（四章 × 1280×720 / 1024×768 / 720×1280 三种窗口）。
## 原先退场钉死在 6.3 秒：题记全显 1.8–2.1 秒、出处全显 1.0–1.5 秒就开始淡去；「点击继续」章名一写出（约 2.05 秒）就亮，
## 那时点一下只是补全题记。
## 断言（每章每种窗口）：
##   一、题记按宽度折列（w53-待拍板 9d 定「维持按宽度排」）：一列放得下（字数 × 列步 ≤ 列高，同 cs_ink_text._wrap）就一列；
##       放不下才折，且只折在句读后、不把一句拆成两截；出处一列。（七轮撤回五轮的「一句一列」：短题记也被拆开。）
##   二、题记与出处全部全显之后、开始淡去之前，至少留「（题记 + 出处字数）÷ 5」秒，夹在 2.5–5 秒（留 0.1 秒帧差）。
##   三、「点击继续」不早于全部全显才亮，且淡去前亮过。
##   四、卡在 14 秒内收场（不挂住）。
##   五、墨晕油画窗不压字：窗右缘（cs_ink_bloom 的 center / radius 换成像素，横向半宽 = radius × 画布高 ÷ 0.86）在文字块左缘
##       （各段竖排字与「立志」印的最左）左边至少 8px。原先窗半径下限是画布高的 0.25，竖屏（画布 1280×2275）窗横向半宽撑到
##       661px，油画盖过题记与出处；16:9、4:3 本就不压。
##   六、墨晕油画窗挨着文字块：窗的上下跨度（窗心 ± radius × 画布高）与文字块的上下跨度有交叠——竖屏不沉到画面中腰。
## 另验点击（第二章、1280×720）：写到题记中途点一下 = 补全且不退场；卡停 0.4 秒再点不认（9c 定：卡停满 0.8 秒才认），
## 停 0.9 秒再点才退场；
## 印已落定（6 秒档旧口径 T_SEAL + 0.5）而出处还没写完时点一下 = 补全出处，不是直接退场（出处没露全就淡去）。
## 驱动：卡建好后停掉它自己的 _process，按 1/60 秒逐帧调 _step（与 _process 每帧的调用同一入口），时间线确定、不吃机器忙闲。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_w53_9_chapter_card_probe.gd   # 须带窗口：headless 下章节卡当帧收场
## 输出末行 QA_W53_9_CHAPTER_CARD OK | FAIL <n>；rc 0 / 1。本进程 SCRIPT ERROR 即红（共用件 tools/script_err_tally.gd）。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")
const TAG := "QA_W53_9_CHAPTER_CARD"
const DATA := "res://data/cutscenes.json"
const INK_TEXT := "res://scripts/cutscene/cs_ink_text.gd"
const DT := 1.0 / 60.0
const SIZES := [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(720, 1280)]
const CANVAS := {Vector2i(1280, 720): Vector2(1280, 720), Vector2i(1024, 768): Vector2(1280, 960), Vector2i(720, 1280): Vector2(1280, 2275)}
const CLAUSE := "，。？！；"
## 竖排时句读换成竖排字形（cs_ink_text.V_FORMS）
const CLAUSE_V := "︐︒︖︕︔"
## 题记样式（ChapterCard._build 的 ep）：字号 23、字距 0.12；列高 = 画布高 × 0.5
const EPI_FS := 23.0
const EPI_SP := 0.12
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


## 各列（自右向左）最末一字
func _col_ends(node: Node) -> Array:
	var cols := {}
	var gl: Array = node.get("_glyphs")
	for g in gl:
		var x := int(roundf(float(g["x"]) + float(g["w"]) * 0.5))
		if not cols.has(x) or float(g["y"]) > float(cols[x]["y"]):
			cols[x] = g
	var xs: Array = cols.keys()
	xs.sort()
	xs.reverse()
	var out: Array = []
	for x in xs:
		out.append(str(cols[x]["ch"]))
	return out


## 五、油画窗不压字：窗右缘（像素）在文字块左缘左边至少 8px
func _window_clear(c: Node, cv: Vector2, where: String) -> void:
	var bloom: ColorRect = c.get("_bloom")
	var mat := bloom.material as ShaderMaterial if bloom != null else null
	if mat == null or not bloom.visible:
		_expect(false, "%s 墨晕油画窗没建起来（材质 %s）" % [where, mat])
		return
	var ctr: Vector2 = mat.get_shader_parameter("center")
	var rad := float(mat.get_shader_parameter("radius"))
	var right := ctr.x * cv.x + rad * cv.y / 0.86
	var text_left := INF
	for it in c.get("_items"):
		text_left = minf(text_left, (it["node"] as Control).position.x)
	_expect(right <= text_left - 8.0,
		"%s 油画窗右缘 %.0fpx 在文字块左缘 %.0fpx 左边 ≥ 8px（窗心 %.0fpx、横向半宽 %.0fpx）" % [where, right, text_left, ctr.x * cv.x, rad * cv.y / 0.86])
	var top := INF
	var bottom := -INF
	for it in c.get("_items"):
		var r := Rect2((it["node"] as Control).position, (it["node"] as Control).size)
		top = minf(top, r.position.y)
		bottom = maxf(bottom, r.end.y)
	var w_top := ctr.y * cv.y - rad * cv.y
	var w_bottom := ctr.y * cv.y + rad * cv.y
	_expect(w_top < bottom and w_bottom > top,
		"%s 油画窗挨着文字块：窗上下 %.0f–%.0fpx 与文字块 %.0f–%.0fpx 有交叠" % [where, w_top, w_bottom, top, bottom])


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
	_expect(cv.is_equal_approx(CANVAS[wh]) or (cv - CANVAS[wh]).length() < 1.0, "%s 画布 %s（应 %s，不然这一档窗口比例没量到）" % [where, cv, CANVAS[wh]])
	var p := _parts(c)
	var ep: Node = p["ep"]
	var sr: Node = p["sr"]
	if ep == null or sr == null:
		_expect(false, "%s 找不到题记 / 出处两段字（题记「%s」）" % [where, epi])
		c.queue_free()
		return
	var fits := float(epi.length()) * EPI_FS * (1.0 + EPI_SP) <= cv.y * 0.5 + EPI_FS * EPI_SP + 0.01
	var ends := _col_ends(ep)
	var clean := true
	for k in range(ends.size() - 1):
		clean = clean and (CLAUSE + CLAUSE_V).contains(str(ends[k]))
	_expect((_cols(ep) == 1 if fits else (_cols(ep) >= 2 and clean)) and _cols(sr) == 1,
		"%s 题记按宽度折列：「%s」%s → %d 列（各列收尾「%s」）；出处 %d 列" % [where, epi,
		"一列放得下" if fits else "一列放不下、须折在句读后", _cols(ep), "".join(ends), _cols(sr)])
	_window_clear(c, cv, where)
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
	# 一、题记写到中途点一下：补全、不退场；卡停 0.4 秒再点不认；停 0.9 秒再点才退场
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
	var t_rest := float(c.get("_t"))
	var done1 := _all_revealed(p["texts"]) and not bool(ep.call("is_fading"))
	_step_to(c, t_rest + 0.4)
	_click(c)
	c.call("_step", DT)
	var guarded := not bool(ep.call("is_fading"))
	_step_to(c, t_rest + 0.9)
	_click(c)
	c.call("_step", DT)
	var gone := bool(ep.call("is_fading"))
	_expect(mid and done1 and guarded and gone,
		"点击：题记写到中途（%s）点一下补全且不退场（%s）；卡停 0.4 秒再点不认（%s，9c 定停满 0.8 秒才认）；停 0.9 秒再点退场（%s）" % [mid, done1, guarded, gone])
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
