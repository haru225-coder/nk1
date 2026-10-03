extends SceneTree
## lane w53-8：人物志名册格的列数随页宽排（超宽画布不再只占左半页）。
## 证：
##   1. 1280×720：四组名册格都是九列（与原先逐像素一致），末格右沿不出名册页（不横向溢出）。
##   2. 窗放到 21:9 / 32:9（画布 1706×720 / 2560×720）：整排的名册格铺满页宽——最宽一排右边
##      空出的宽不足一格（一格 116 + 列距 12 = 128），且仍不出名册页。
## 旧病（回退即红）：CharacterCodex 把列数钉死 COLS = 9，32:9 下最宽一排右边空出 1306 px（还排得下十格），
## 21:9 下空 452 px（还排得下三格），断言 2 报「右边空出 … 还排得下 N 格」。
## 用法：DISPLAY=:2 godot --path . -s res://tools/qa_w53_8_codex_cols_probe.gd
##（headless 也能跑：只量排版，不截图）

## 人物志脚本引 GameManager 等自动加载单例：-s 脚本 preload 时单例还没注册、编不过，进 _run 后再 load
const CODEX_PATH := "res://scripts/ui/CharacterCodex.gd"
const VIEW := Vector2i(1280, 720)
const WIDE := [Vector2i(2560, 1080), Vector2i(3840, 1080)]   # 21:9 → 画布 1706×720；32:9 → 2560×720
const PITCH := 128.0   # 一格 116 + 列距 12

var _cx: Control
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


## 量名册页：[各组列数, 最宽一排的末格右沿, 名册页可排格的右沿（扣竖滚动条）]
func _measure() -> Array:
	var scroll := _cx.find_child("GridScroll", true, false) as ScrollContainer
	if scroll == null:
		return []
	var cols: Array = []
	var right := 0.0
	for g in scroll.find_children("*", "GridContainer", true, false):
		cols.append((g as GridContainer).columns)
		for c in g.get_children():
			right = maxf(right, (c as Control).get_global_rect().end.x)
	var bar_w := scroll.get_v_scroll_bar().get_combined_minimum_size().x
	return [cols, right, scroll.get_global_rect().end.x - bar_w]


func _resize(view: Vector2i) -> void:
	DisplayServer.window_set_size(view)
	root.size = view
	for _i in 12:
		await process_frame


func _run() -> void:
	root.size = VIEW
	if root.get_node_or_null("GameManager") == null or root.get_node("GameManager").all_characters().is_empty():
		print("FAIL 人物设定集未载入（GameManager.all_characters 为空），名册格量不了")
		quit(1)
		return
	var codex_scr := load(CODEX_PATH) as GDScript
	if codex_scr == null or not codex_scr.can_instantiate():
		print("FAIL 人物志脚本 %s 编不过" % CODEX_PATH)
		quit(1)
		return
	_cx = codex_scr.new()
	root.add_child(_cx)
	_cx.begin("")
	for _i in 12:
		await process_frame

	# ── 断言 1：1280×720 九列、不出页 ──
	var m := _measure()
	_check(not m.is_empty(), "名册页 GridScroll 在树")
	if m.is_empty():
		_finish()
		return
	var cols0: Array = m[0]
	_check(cols0.size() == 4, "名册四组（主角・要人 / 职事 / 市井 / 史实）各一张格（现 %d）" % cols0.size())
	var nine := true
	for c in cols0:
		nine = nine and int(c) == 9
	_check(nine, "1280×720 各组九列（现 %s）" % str(cols0))
	_check(float(m[1]) <= float(m[2]) + 0.5,
		"1280×720 末格右沿 %.0f 不出名册页（可排右沿 %.0f）" % [m[1], m[2]])

	# ── 断言 2：超宽画布整排铺满页宽、仍不出页 ──
	for view in WIDE:
		await _resize(view)
		var cv := root.get_visible_rect().size
		var w := _measure()
		if w.is_empty():
			_check(false, "%s 名册页仍在" % str(cv))
			continue
		var gap: float = float(w[2]) - float(w[1])
		_check(gap < PITCH,
			"画布 %s：最宽一排铺满页宽（右边空出 %.0f px，限一格 %.0f 以内；还排得下 %d 格）——列数 %s" % [
				str(cv), gap, PITCH, int(floor(maxf(gap, 0.0) / PITCH)), str(w[0])])
		_check(gap >= -0.5, "画布 %s：末格右沿 %.0f 不出名册页（可排右沿 %.0f）" % [str(cv), w[1], w[2]])

	_finish()


func _finish() -> void:
	print("DONE fails=%d" % _fails.size())
	for f in _fails:
		print("  RED %s" % f)
	quit(1 if not _fails.is_empty() else 0)
