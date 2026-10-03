extends SceneTree
## lane w53-8：市舶纪事册页（VisionStage）画布适配探针。
## 证：在宽画布（aspect=expand，1920×720 → 视口 ≥ 1280）下，钉画缘的件——墨边（LetterTop/LetterBot）、
## 题签（SlipClip）、副题（SlipSub）、立像裱框（PortraitPane）、右下 hint——须随画布重排：
##   1. 墨边宽度 == 画布宽（VisionStage._build 里 cv 取自 Kit.canvas_size）。
##   2. 右下 hint 右沿落在画布内（x + size.x == cv.x − 20 一带）；钉死 1280 时它离右缘还差 640 px。
##   3. viewport.size_changed 后（窗宽从 1920 收到 1300，视口变小）整页重建、LetterTop 宽同步为新画布宽。
## 旧病（回退即红）：VisionStage.gd 的 _build 用 cv := Vector2(1280, 720)，LetterTop.size.x 恒 1280，
## 1920 画布下断言 1 报错「顶墨边只盖住 1280/1920」；改尺寸后断言 3 报错「resize 后未重建」。

const TAG := "QA_VS_LAYOUT"
const VIEW_WIDE := Vector2i(1920, 720)
const VIEW_NARROW := Vector2i(1300, 720)
const VS_SCENE_PATH := "res://scenes/vision/VisionStage.tscn"

var _vs: Control
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


func _run() -> void:
	root.size = VIEW_WIDE
	var packed: PackedScene = load(VS_SCENE_PATH)
	_vs = packed.instantiate() as Control
	root.add_child(_vs)
	for _i in 6:
		await process_frame
	var canvas := _vs.get_viewport_rect().size
	_check(canvas.x >= 1900.0, "宽画布落在 1920（视口＝%s）" % str(canvas))

	# ── 断言 1：墨边宽度 == 画布宽 ──
	var top := _vs.get_node_or_null("LetterTop") as Control
	var bot := _vs.get_node_or_null("LetterBot") as Control
	_check(top != null and bot != null, "LetterTop / LetterBot 在树")
	if top != null:
		_check(is_equal_approx(top.size.x, canvas.x),
			"顶墨边宽 == 画布宽（墨边 %s vs 画布 %s）" % [str(top.size.x), str(canvas.x)])
	if bot != null:
		_check(is_equal_approx(bot.size.x, canvas.x),
			"底墨边宽 == 画布宽（墨边 %s vs 画布 %s）" % [str(bot.size.x), str(canvas.x)])

	# ── 断言 2：右下 hint 右沿落在画布右缘 40 px 内 ──
	var hint := _vs.get_node_or_null("Hint") as Control
	_check(hint != null, "Hint 在树")
	if hint != null:
		var right := hint.position.x + hint.size.x
		_check(right >= canvas.x - 40.0 and right <= canvas.x + 1.0,
			"Hint 右沿贴近画布右缘（右沿 %s vs 画布右缘 %s）" % [str(right), str(canvas.x)])

	# ── 断言 3：副题 SlipSub 居中（中心偏在 20 px 内）──
	var sub := _vs.get_node_or_null("SlipSub") as Control
	_check(sub != null, "SlipSub 在树")
	if sub != null:
		# SlipSub 用 position 0 起点 + size = cv.x
		_check(is_equal_approx(sub.position.x, 0.0) and is_equal_approx(sub.size.x, canvas.x),
			"SlipSub 均布画布（w %s vs %s）" % [str(sub.size.x), str(canvas.x)])

	# ── 断言 4：换小窗（视口收缩）→ 整页重排，新 LetterTop 宽 == 新画布宽 ──
	# SceneTree 脚本里 root.size 只读写根 Window 的 size 属性，不一定踢到 size_changed；
	# 显式 DisplayServer.window_set_size 才走引擎那条「窗框重调 → emit size_changed」
	DisplayServer.window_set_size(VIEW_NARROW)
	root.size = VIEW_NARROW
	for _i in 12:
		await process_frame
	var canvas2 := _vs.get_viewport_rect().size
	_check(canvas2.x < 1310.0, "视口已收缩（视口＝%s）" % str(canvas2))
	# VisionStage 经 size_changed → _on_viewport_resized 现调量 _layout：LetterTop（同一个节点）的
	# size.x 须已换到新画布宽；不改 = resize 后仍 1920，「画布右 620 px 无墨边」残留在屏。
	var top2 := _vs.get_node_or_null("LetterTop") as Control
	_check(top2 != null, "resize 后 LetterTop 仍在树")
	if top2 != null:
		_check(is_equal_approx(top2.size.x, canvas2.x),
			"resize 后顶墨边宽 == 新画布宽（墨边 %s vs 画布 %s）" % [str(top2.size.x), str(canvas2.x)])
	# 右下 hint 也须跟到新画布右缘
	var hint2 := _vs.get_node_or_null("Hint") as Control
	if hint2 != null:
		var right2: float = hint2.position.x + hint2.size.x
		_check(right2 >= canvas2.x - 40.0 and right2 <= canvas2.x + 1.0,
			"resize 后 Hint 右沿贴近新画布右缘（右沿 %s vs 画布 %s）" % [str(right2), str(canvas2.x)])

	print("DONE fails=%d" % _fails.size())
	for f in _fails:
		print("  RED %s" % f)
	quit(1 if not _fails.is_empty() else 0)
