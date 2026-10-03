extends SceneTree
## lane w53-8：市舶纪事册页（VisionStage）画布适配探针。
## 证：在宽画布（aspect=expand，1920×720 → 视口 ≥ 1280）下，钉画缘的件——墨边（LetterTop/LetterBot）、
## 题签（SlipClip）、副题（SlipSub）、立像裱框（PortraitPane）、右下 hint——须随画布重排：
##   1. 墨边宽度 == 画布宽（VisionStage._build 里 cv 取自 Kit.canvas_size）。
##   2. 右下 hint 右沿落在画布内（x + size.x == cv.x − 20 一带）；钉死 1280 时它离右缘还差 640 px。
##   3. viewport.size_changed 后（窗宽从 1920 收到 1300，视口变小）整页重建、LetterTop 宽同步为新画布宽。
##   4. 「中板」飘字（HitFloat）贴着红帆快船（Falcon）、战事字（CombatTag）整条压在海图残片内——
##      1920 宽、收到 1300 宽、改 4:3 窗（画布加高到 1280×960）三处都量。
## 旧病（回退即红）：VisionStage.gd 的 _build 用 cv := Vector2(1280, 720)，LetterTop.size.x 恒 1280，
## 1920 画布下断言 1 报错「顶墨边只盖住 1280/1920」；改尺寸后断言 3 报错「resize 后未重建」。
## 二轮旧病（回退即红）：飘字 / 战事字按画布比例折（x = 0.8 cv.x、y = 0.722 cv.y），host 只挪 0.5625 cv.x——
## 1920 宽下「中板」离船心 204 px、飘到海图右缘外；4:3 窗下战事字掉出海图下缘。

const TAG := "QA_VS_LAYOUT"
const VIEW_WIDE := Vector2i(1920, 720)
const VIEW_NARROW := Vector2i(1300, 720)
const VIEW_TALL := Vector2i(800, 600)   # 4:3 窗：expand 把画布加高到 1280×960
## 飘字中心到船心的上限：1280×720 原版静置实量 49.7 px，开场上浮到顶 61 px；脱船（按 0.8 cv.x 折）1920 下实量 204 px
const LABEL_SHIP_MAX := 90.0
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


## 红帆快船：定格 host 里贴 ship_falcon.png 的那张 Sprite2D（按贴图认，不靠节点名）
func _falcon() -> Sprite2D:
	for c in _vs.find_children("*", "Sprite2D", true, false):
		var s := c as Sprite2D
		if s.texture != null and s.texture.resource_path.ends_with("ship_falcon.png"):
			return s
	return null


func _check_combat_labels(where: String) -> void:
	var falcon := _falcon()
	var hit := _vs.find_child("HitFloat", true, false) as Control
	var tag := _vs.find_child("CombatTag", true, false) as Control
	_check(falcon != null and hit != null and tag != null, "%s：红帆快船 / 中板 / 战事字在树" % where)
	if falcon == null or hit == null or tag == null:
		return
	var d := hit.get_global_rect().get_center().distance_to(falcon.global_position)
	_check(d <= LABEL_SHIP_MAX,
		"%s：「中板」贴着红帆快船（飘字中心距船心 %.1f px，限 %.0f）" % [where, d, LABEL_SHIP_MAX])
	var chart := _vs.find_child("ChartFragment", true, false) as Sprite2D
	if chart == null or chart.texture == null:
		print("SKIP %s：海图残片贴图缺（回落程序椭圆），战事字压图不量" % where)
		return
	var sz := chart.texture.get_size() * chart.global_scale
	var chart_rect := Rect2(chart.global_position - sz * 0.5, sz)
	_check(chart_rect.encloses(tag.get_global_rect()),
		"%s：战事字整条压在海图内（字 %s vs 图 %s）" % [where, str(tag.get_global_rect()), str(chart_rect)])


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

	_check_combat_labels("1920×720")

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
	_check_combat_labels("收到 1300×720")

	# ── 断言 5：改 4:3 窗 → 画布加高到 1280×960，飘字 / 战事字仍跟着定格 host 走 ──
	DisplayServer.window_set_size(VIEW_TALL)
	root.size = VIEW_TALL
	for _i in 12:
		await process_frame
	var canvas3 := _vs.get_viewport_rect().size
	_check(canvas3.y > 900.0, "4:3 窗画布已加高（视口＝%s）" % str(canvas3))
	_check_combat_labels("4:3 窗 %s" % str(canvas3))

	print("DONE fails=%d" % _fails.size())
	for f in _fails:
		print("  RED %s" % f)
	quit(1 if not _fails.is_empty() else 0)
