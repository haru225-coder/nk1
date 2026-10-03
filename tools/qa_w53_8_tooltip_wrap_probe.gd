extends SceneTree
## lane w53-8：悬停提示（tooltip）超宽折行——长提示不再一行拉过整幅画面、宽过画布两头被裁。
## 证（1280×720，挂主场景走真入口；headless 与带窗口都能跑——提示小笺是嵌入式子窗口，headless 下照样弹）：
##   1. 顶匾第二行记事的全文提示：泉州接下一单委办（记事前缀「委办 N 日」），月初通告投进 data/news.json 的
##      「泉州开城了」那条传闻（真文、真前缀、{target_name} 照 GameState.news_text 换字；记事去掉【】标签后 77 字、
##      连前缀 85 字），在泉州港页鼠标停在顶匾记事上：提示小笺整个落在画布里、
##      折成几行全显出来（可见行 = 总行数）、字面就是记事全文、小笺宽不过 480（UiTheme.TIP_MAX_W）加小笺边。
##   2. 住处勘见那类「地点\n史钩」两段提示（data/discoveries.json 最长的 heishui_gou 史钩）：同样不过定宽、整个在画布里。
##   3. 短提示（十来字）照旧一行、按字宽，不被硬撑成定宽。
## 旧病（回退即红）：引擎默认提示是不折行的单行 Label，85 字记事提示宽 1380 上下，左贴画布 0、右边冲出 1280，
## 末尾六七个字看不见（断言 1 红）；勘见提示 62 字宽 1012，一条横过大半幅画面（断言 2 的定宽红）。
## 用法：godot --headless --path . -s res://tools/qa_w53_8_tooltip_wrap_probe.gd（带窗口 DISPLAY=:2 同样可跑）

const VIEW := Vector2i(1280, 720)
const NEWS_ID := "n_1276_12_quanzhou_falls"
const DISCOVERY_ID := "heishui_gou"
const WAIT_MS := 3000
## 提示一行最宽（与 UiTheme.TIP_MAX_W 同值；探针自带一份，回退修法时 UiTheme 里没有这个名也照样跑到断言）
const TIP_MAX_W := 480.0

var _fails: Array = []
var _main: Control


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if ok:
		print("OK %s" % what)
	else:
		_fails.append(what)
		print("FAIL %s" % what)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## 眼下弹着的提示小笺：[Window, Label]；没有返回 []
func _tip_now() -> Array:
	for w in root.find_children("*", "Window", true, false):
		if not (w as Window).visible:
			continue
		for c in w.get_children():
			if c is Label and (c as Label).theme_type_variation == &"TooltipLabel":
				return [w, c]
	return []


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	root.push_input(ev, true)


## 鼠标挪到 c 中心、停住，等提示小笺弹出（上限 WAIT_MS）；弹不出返回 []
func _hover(c: Control) -> Array:
	_move(Vector2(2, VIEW.y - 2))
	await _frames(4)
	var p := c.get_global_rect().get_center()
	for k in 3:
		_move(p + Vector2(k, 0))
		await process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < WAIT_MS:
		await process_frame
		var got := _tip_now()
		if not got.is_empty():
			await _frames(2)
			return got
	return []


## 量一枚提示：整个在画布里、全文都显出来；cap_width 时再量宽不过定宽
func _judge(tag: String, got: Array, want_text: String, cap_width := true) -> void:
	if got.is_empty():
		_check(false, "%s：鼠标停住 %d ms 没弹出提示小笺" % [tag, WAIT_MS])
		return
	var w := got[0] as Window
	var tip := got[1] as Label
	var cv := root.get_visible_rect().size
	var r := Rect2(Vector2(w.position), Vector2(w.size))
	print("  %s：小笺 %s，%d 行（可见 %d），字 %d" % [tag, r, tip.get_line_count(), tip.get_visible_line_count(), tip.text.length()])
	_check(r.position.x >= 0.0 and r.end.x <= cv.x and r.position.y >= 0.0 and r.end.y <= cv.y,
		"%s：提示小笺整个落在画布 %s 里（小笺 %s）" % [tag, cv, r])
	_check(tip.text == want_text, "%s：提示字面是全文（%d 字）" % [tag, want_text.length()])
	_check(tip.get_visible_line_count() >= tip.get_line_count(),
		"%s：折出的行全显出来（共 %d 行、可见 %d）" % [tag, tip.get_line_count(), tip.get_visible_line_count()])
	if cap_width:
		var edge := w.size.x - tip.size.x
		_check(tip.size.x <= TIP_MAX_W + 0.5 and w.size.x <= TIP_MAX_W + edge + 0.5,
			"%s：一行不宽过定宽 %d（字区宽 %.0f，小笺宽 %d）" % [tag, int(TIP_MAX_W), tip.size.x, w.size.x])


func _run() -> void:
	root.size = VIEW
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(10)
	var gs: Node = root.get_node("GameState")
	var gm: Node = root.get_node("GameManager")
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	await _frames(8)

	# 1. 顶匾记事全文提示：先在泉州接一单委办（顶匾记事前缀「委办 N 日」，跑货的人多半身上有一单），
	#    再把真新闻条目、真前缀（GameManager._settle_history 同一写法）走月初通告投进来
	var offer: Dictionary = gs.call("contract_offer", "quanzhou")
	_check(not offer.is_empty() and bool(gs.call("accept_contract", offer)), "泉州牙行接下一单委办（顶匾记事带「委办 N 日」前缀）")
	var news: Dictionary = {}
	for n in gm.news_data.get("news", []):
		if str((n as Dictionary).get("id", "")) == NEWS_ID:
			news = n
	_check(not news.is_empty(), "data/news.json 里有「%s」这条传闻" % NEWS_ID)
	if not news.is_empty():
		var speaker := str(news.get("speaker", ""))
		var notice: String = ("【酒馆传闻】" if speaker == "" else "【%s】" % speaker) + str(gs.call("news_text", news))
		_main.call("_on_monthly_notice", notice)
		await _frames(4)
		var note: Label = _main.get("_status_note")
		var want := UiTheme.strip_bbcode(note.tooltip_text)
		print("顶匾记事提示 %d 字：%s" % [want.length(), want])
		_check(want.length() > 80 and want.begins_with("委办") and want.find("泉州开城了") >= 0,
			"顶匾记事挂着「委办 N 日」+ 这条传闻的全文提示（%d 字）" % want.length())
		_judge("顶匾记事全文提示", await _hover(note), note.tooltip_text)

	# 2. 住处勘见那类「地点\n史钩」两段提示：最长的史钩
	var hook := ""
	var where := ""
	var f := FileAccess.open("res://data/discoveries.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		var list: Array = []
		if parsed is Array:
			list = parsed
		elif parsed is Dictionary:
			list = (parsed as Dictionary).get("discoveries", [])
		for d in list:
			if d is Dictionary and str((d as Dictionary).get("id", "")) == DISCOVERY_ID:
				hook = str(d.get("historical_hook", ""))
				where = str(d.get("location", ""))
	_check(hook.length() > 50, "data/discoveries.json 里 %s 的史钩够长（%d 字）" % [DISCOVERY_ID, hook.length()])
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(host)
	var look := Button.new()
	look.text = "细看"
	look.tooltip_text = "%s\n%s" % [where, hook]
	look.position = Vector2(860, 360)
	look.size = Vector2(96, 40)
	host.add_child(look)
	await _frames(2)
	_judge("勘见「地点\\n史钩」提示", await _hover(look), look.tooltip_text)

	# 3. 短提示照旧一行、按字宽
	var short := Button.new()
	short.text = "修船"
	short.tooltip_text = "坞上坞外各船一并修好。"
	short.position = Vector2(200, 360)
	short.size = Vector2(96, 40)
	host.add_child(short)
	await _frames(2)
	var got := await _hover(short)
	_judge("短提示", got, short.tooltip_text, false)
	if not got.is_empty():
		var tip := got[1] as Label
		_check(tip.get_line_count() == 1 and tip.size.x < TIP_MAX_W * 0.6,
			"短提示照旧一行、按字宽（%d 行，字区宽 %.0f）" % [tip.get_line_count(), tip.size.x])
	_finish()


func _finish() -> void:
	print("QA_W53_8_TOOLTIP_WRAP_PROBE %s（%d 项不合）" % ["PASS" if _fails.is_empty() else "FAIL", _fails.size()])
	quit(0 if _fails.is_empty() else 1)
