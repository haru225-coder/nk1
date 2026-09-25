extends SceneTree
## 巡检：把主场景挂上，走开局、三港、九个设施页，再量海图。
## 非滚动区的按钮必须落在 1280×720 里；珊瑚主钮聚焦时仍是深字。
## 海图三张航向牌必须整张在画面内，水粮不够时牌上写着告警，账条变高时海图不低于自己的最小高度。
## （合并时按 7f92 晨潮三向改写：原版量的是已拆掉的港口列表。）
## godot --path . -s res://tools/patrol_shell.gd

const VIEW := Vector2(1280, 720)
const PORTS := ["quanzhou", "fuzhou", "xinghua"]
const FACILITIES := [
	"market", "yamen", "shipyard", "tavern", "inn",
	"guild", "exam", "residence", "temple",
]

var _main: Node
var _fails: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(VIEW)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	for _i in 6:
		await process_frame

	_check_accent_focus()
	_check_screen("开局", true)

	for port in PORTS:
		_main.load_scene(port)
		for _i in 3:
			await process_frame
		_check_screen(port, true)
		var title := ""
		if _main.get("port_title") != null:
			title = str(_main.port_title.text)
		_check(title != "", "%s 港匾有字" % port)
		for fac in FACILITIES:
			var sid := "%s_%s" % [port, fac]
			_main.load_scene(sid)
			for _i in 3:
				await process_frame
			_check_screen(sid, false)
			var head := ""
			if _main.get("scene_title") != null and _main.scene_title.visible:
				head = str(_main.scene_title.text).strip_edges()
			_check(head != "" and head != "未命名设施" and head != "无人应门",
				"%s 标题是「%s」" % [sid, head])

	await _check_sea_chart()
	await _check_market_fold()
	await _check_endgame_pages()
	_finish()


## 1280×720 牙行：委办收成一行摘要后，第一张货卡的「卖 1」整颗在滚动视口里（第 2 轮 UX M2：原先在折线下）
func _check_market_fold() -> void:
	var state: Node = root.get_node("GameState")
	state.last_port = "quanzhou"
	_main.load_scene("quanzhou_market")
	for _i in 4:
		await process_frame
	var slips: Node = _main.find_child("BrokerSlips", true, false)
	_check(slips != null and slips.get_child_count() > 0, "牙行有柜上货卡")
	if slips == null or slips.get_child_count() == 0:
		return
	var sell: Button = _find_button(slips.get_child(0), "卖 1")
	var scroll := _scroll_of(slips)
	_check(sell != null and scroll != null, "第一张货卡有「卖 1」且在滚动区里")
	if sell == null or scroll == null:
		return
	var view := scroll.get_global_rect().grow(0.5)
	_check(view.encloses(sell.get_global_rect()), "1280×720 第一张货卡的「卖 1」整颗在视口内（钮 %s，视口 %s）" % [
		sell.get_global_rect(), scroll.get_global_rect()])


## 守城页 / 终局后港口页（第 2 轮 UX B1）：先进泉州港页再进，旧岸门不残留；进出设施一次、重读一次结局，门与账不翻倍，匾不累加
func _check_endgame_pages() -> void:
	var gs: Node = root.get_node("GameState")
	var cal: Node = root.get_node("Calendar")
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	gs.from_dict({})
	gs.set_flag("renamed_wenlong")
	gs.identity = "scholar"
	cal.from_dict({"year": 1276, "month": 11, "day": 3})
	gs.siege_begin()
	gs.chapter = 4
	gs.last_port = "xinghua"
	_main.load_scene("xinghua")
	for _i in 3:
		await process_frame
	_check_siege_band("守城页（先进过泉州）")
	_check_screen("守城页", true)
	_main._on_facility_pressed({"id": "siege_grain", "title": "市场"})
	for _i in 2:
		await process_frame
	_main.load_scene("xinghua")
	for _i in 3:
		await process_frame
	_check_siege_band("守城页（进出市场一次）")
	_check_screen("守城页-回", false)

	gs.from_dict({})
	cal.from_dict({"year": 1285, "month": 3, "day": 1})
	gs.last_port = "quanzhou"
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	gs.set_flag("sided_pu")
	gs.finish("泉州蒲氏的船", "巡检")
	_main.load_scene("quanzhou")
	for _i in 3:
		await process_frame
	var want := "泉州・泉州蒲氏的船"
	_check(str(_main.port_title.text) == want, "终局港名匾「%s」（现「%s」）" % [want, _main.port_title.text])
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	var acts0 := _count_buttons(band.get_node_or_null("ShoreActions")) if band != null else -1
	_check(_count_named(band, "EpilogueSlip") == 1 and _visible_button(band, "重读结局"),
		"终局港口页有一方航海札记与「重读结局」（札记 %d）" % _count_named(band, "EpilogueSlip"))
	_check(not _visible_button(band, "看风") and _count_named(band, "ShoreDoors") <= 1,
		"终局港口页没有「看风」，也没有残留的岸门")
	_check_screen("终局港口页", true)
	_main._on_reread_ending()
	for _i in 2:
		await process_frame
	_main._confirm_chapter_sheet()
	for _i in 3:
		await process_frame
	band = _main.port_mode.get_node_or_null("ShoreBand")
	_check(str(_main.port_title.text) == want, "重读结局后港名匾不累加（现「%s」）" % _main.port_title.text)
	_check(_count_named(band, "EpilogueSlip") == 1, "重读结局后札记仍一方（现 %d）" % _count_named(band, "EpilogueSlip"))
	_check(_count_buttons(band.get_node_or_null("ShoreActions")) == acts0, "重读结局后动作行钮数不变（%d → %d）" % [
		acts0, _count_buttons(band.get_node_or_null("ShoreActions"))])
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _check_siege_band(tag: String) -> void:
	var band: Node = _main.port_mode.get_node_or_null("ShoreBand")
	_check(band != null, "%s 有岸带" % tag)
	if band == null:
		return
	var doors: Node = band.get_node_or_null("ShoreDoors")
	var n_doors := doors.get_child_count() if doors != null else -1
	var hand: PackedStringArray = _main.shore_hand
	_check(n_doors == hand.size() and hand.size() == 5, "%s 门排恰五扇、与手上的卡同数（门 %d，卡 %d）" % [tag, n_doors, hand.size()])
	_check(_visible_label(doors, "囊山"), "%s「囊山」卡看得见" % tag)
	_check(_count_named(band, "SiegeStat") == 1, "%s 城防账一方（现 %d）" % [tag, _count_named(band, "SiegeStat")])
	_check(not _visible_button(band, "看风"), "%s 没有「看风」" % tag)
	_check(not _visible_label(band, "牙行") and not _visible_label(band, "贡院"), "%s 没有残留泉州的岸门" % tag)
	var lf: Control = _main.left_facilities
	var rf: Control = _main.right_facilities
	_check(lf.get_child_count() == 0 and rf.get_child_count() == 0, "%s 旧左右栏清空（%d / %d）" % [
		tag, lf.get_child_count(), rf.get_child_count()])


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _scroll_of(node: Node) -> ScrollContainer:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _count_named(node: Node, n: String) -> int:
	if node == null:
		return 0
	var k := 0
	for c in node.get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		if c.name == n or str(c.name).begins_with(n + "@"):
			k += 1
		k += _count_named(c, n)
	return k


func _count_buttons(node: Node) -> int:
	if node == null:
		return -1
	var k := 0
	for c in node.get_children():
		if c is Button and not (c as Node).is_queued_for_deletion():
			k += 1
	return k


func _visible_button(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Button and (node as Button).text == text and (node as CanvasItem).is_visible_in_tree() \
			and not (node as Node).is_queued_for_deletion():
		return true
	for c in node.get_children():
		if _visible_button(c, text):
			return true
	return false


func _visible_label(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Label and (node as Label).text == text and (node as CanvasItem).is_visible_in_tree() \
			and not (node as Node).is_queued_for_deletion():
		return true
	for c in node.get_children():
		if _visible_label(c, text):
			return true
	return false


func _check_sea_chart() -> void:
	var state: Node = root.get_node("GameState")
	state.last_port = "quanzhou"
	var chart: Node = load("res://scenes/SeaChart.tscn").instantiate()
	root.add_child(chart)
	for _i in 4:
		await process_frame
	_check_heading_cards(chart, "海图未选")
	var hand: PackedStringArray = chart.get("_hand")
	_check(hand.size() == 3, "海图晨潮发三向（现 %d）" % hand.size())
	if hand.size() > 0:
		chart._select_heading(hand[0])
		for _i in 4:
			await process_frame
		_check_heading_cards(chart, "海图选牌")
		_check_chart_floor(chart, "海图选牌")
		var sail: Button = chart.get("sail_button")
		_check(sail != null and not sail.disabled, "海图选牌后「就这一向」可按")
	_shot_chart(chart, "seachart-quanzhou")

	var fleet: Node = root.get_node("Fleet")
	fleet.water = 0
	fleet.food = 0
	chart._refresh_hand()
	for _i in 4:
		await process_frame
	_check_heading_cards(chart, "海图水粮告警")
	_check_chart_floor(chart, "海图水粮告警")
	_check_warn_lines(chart, "海图水粮告警")
	_shot_chart(chart, "seachart-warning")


func _check_heading_cards(chart: Node, tag: String) -> void:
	var row: HBoxContainer = chart.get("heading_row")
	_check(row != null, "%s 有航向牌栏" % tag)
	if row == null:
		return
	var cards := 0
	var stray := 0
	for c in row.get_children():
		if not (c is Control) or (c as CanvasItem).is_queued_for_deletion():
			continue
		var r := (c as Control).get_global_rect()
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		cards += 1
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > VIEW.x + 0.5 or r.end.y > VIEW.y + 0.5:
			stray += 1
	_check(cards == 3 and stray == 0, "%s 三张航向牌整张在画面内（牌 %d，越界 %d）" % [tag, cards, stray])


func _check_chart_floor(chart: Node, tag: String) -> void:
	# 海图重制（a6b5a25）后 SeaChart 没有 chart 成员了，海图画面是全屏的 map_container（SubViewportContainer）。
	# 原先 chart.get("chart") 取回 null，函数在第一条 _check 之前就崩掉，下面三条一次都没跑（第 1 轮工程评审）。
	# 取不到就记一条 ✗，不让函数崩；底线取「自身最小高度」与「画面高一半」的大者（全屏海图最小高度是 0，只比它等于恒真）。
	var ch := chart.get("map_container") as Control
	if ch == null:
		_check(false, "%s 海图画面节点 map_container 取得到" % tag)
		return
	var floor_y := maxf(ch.custom_minimum_size.y, VIEW.y * 0.5)
	_check(ch.size.y + 0.5 >= floor_y, "%s 海图不低于 %d（现 %.0f）" % [
		tag, int(floor_y), ch.size.y,
	])
	var sail := chart.get("sail_button") as Button
	if sail == null:
		_check(false, "%s 发舶钮取得到" % tag)
		return
	_check(sail.get_global_rect().end.y <= VIEW.y + 0.5, "%s 发舶在画面内" % tag)
	var back_end := _named_button_end(chart, "回")
	_check(back_end > 0.0 and back_end <= VIEW.y + 0.5, "%s 回港在画面内（底 %.0f）" % [tag, back_end])


func _named_button_end(node: Node, prefix: String) -> float:
	if node is Button and (node as CanvasItem).is_visible_in_tree() and not _inside_scroll(node):
		var btn := node as Button
		if btn.text.begins_with(prefix):
			return btn.get_global_rect().end.y
	for child in node.get_children():
		var found := _named_button_end(child, prefix)
		if found > 0.0:
			return found
	return 0.0


func _check_warn_lines(chart: Node, tag: String) -> void:
	var row: Node = chart.get("heading_row")
	var warn := 0
	var lost := 0
	var labels: Array = []
	_collect_labels(row, labels)
	for l in labels:
		var lbl := l as Label
		if lbl.text != "水粮不够":
			continue
		warn += 1
		if not _color_near(lbl.get_theme_color("font_color", "Label"), UiTheme.CINNABAR):
			lost += 1
	_check(warn > 0 and lost == 0, "%s 牌上写着朱色「水粮不够」（写 %d，失色 %d）" % [tag, warn, lost])


func _collect_labels(node: Node, out: Array) -> void:
	if node == null:
		return
	if node is Label and (node as CanvasItem).is_visible_in_tree():
		out.append(node)
	for child in node.get_children():
		_collect_labels(child, out)


func _color_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.05 and absf(a.g - b.g) < 0.05 and absf(a.b - b.b) < 0.05


func _shot_chart(chart: Node, name: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		return
	var dir := "/tmp/patrol-shots"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, name])


func _check_accent_focus() -> void:
	var start: Button = _main.start_button
	_check(start != null, "开局有主钮")
	if start == null:
		return
	var focus_col: Color = start.get_theme_color("font_focus_color", "Button")
	var normal_col: Color = start.get_theme_color("font_color", "Button")
	var chip := Button.new()
	UiTheme.style_chip(chip, true)
	if UiTheme.SKIN == "yechao":
		# 夜潮原断言：珊瑚底上深字。
		_check(_is_dark(normal_col), "珊瑚主钮常态是深字")
		_check(_is_dark(focus_col), "珊瑚主钮聚焦仍是深字")
		_check(_is_dark(chip.get_theme_color("font_color", "Button")), "珊瑚小钮常态是深字")
		_check(_is_dark(chip.get_theme_color("font_focus_color", "Button")), "珊瑚小钮聚焦仍是深字")
		_check(_is_dark(chip.get_theme_color("font_pressed_color", "Button")), "珊瑚小钮按下仍是深字")
	else:
		# 绢本：朱砂底上印面浅字，且对朱砂实测 ≥4.5:1。
		_check(_is_seal_text(normal_col), "朱砂主钮常态是印面浅字")
		_check(_is_seal_text(focus_col), "朱砂主钮聚焦仍是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_color", "Button")), "朱砂小钮常态是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_focus_color", "Button")), "朱砂小钮聚焦仍是印面浅字")
		_check(_is_seal_text(chip.get_theme_color("font_pressed_color", "Button")), "朱砂小钮按下仍是印面浅字")
	chip.free()


func _is_dark(c: Color) -> bool:
	return c.r < 0.25 and c.b > c.r


func _is_seal_text(c: Color) -> bool:
	return c.is_equal_approx(UiTheme.SEAL_TEXT) and c.get_luminance() > 0.7 and _contrast(c, UiTheme.SEAL) >= 4.5


## WCAG 相对亮度对比度（sRGB 线性化，不计 alpha）。
func _contrast(a: Color, b: Color) -> float:
	var la := _rel_lum(a)
	var lb := _rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _rel_lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


func _check_screen(tag: String, shot: bool) -> void:
	var stray := _offscreen_buttons(_main)
	_check(stray.is_empty(), "%s 按钮都在画面里（越界 %s）" % [tag, stray])
	if shot:
		var img := root.get_texture().get_image()
		if img != null:
			var dir := "/tmp/patrol-shots"
			DirAccess.make_dir_recursive_absolute(dir)
			img.save_png("%s/%s.png" % [dir, tag])


func _offscreen_buttons(node: Node) -> Array:
	var out: Array = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array) -> void:
	if node is Button and (node as CanvasItem).is_visible_in_tree():
		var btn := node as Button
		if btn.text.strip_edges() != "" and not _inside_scroll(btn):
			var r := btn.get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				if r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > VIEW.x + 2.0 or r.end.y > VIEW.y + 2.0:
					out.append("%s「%s」%s" % [btn.name, btn.text.substr(0, 12), r])
	for child in node.get_children():
		_walk(child, out)


func _inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _check(cond: bool, msg: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + msg)
	if not cond:
		_fails.append(msg)


func _finish() -> void:
	if _fails.is_empty():
		print("PATROL SHELL PASS")
		quit(0)
	else:
		print("PATROL SHELL FAIL")
		for f in _fails:
			print("  ✗ ", f)
		quit(1)
