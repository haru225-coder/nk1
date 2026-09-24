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
	_finish()


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
	var ch: Control = chart.get("chart")
	_check(ch.size.y + 0.5 >= ch.custom_minimum_size.y, "%s 海图不低于 %d（现 %.0f）" % [
		tag, int(ch.custom_minimum_size.y), ch.size.y,
	])
	var sail: Button = chart.get("sail_button")
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
	_check(_is_dark(normal_col), "珊瑚主钮常态是深字")
	_check(_is_dark(focus_col), "珊瑚主钮聚焦仍是深字")
	var chip := Button.new()
	UiTheme.style_chip(chip, true)
	_check(_is_dark(chip.get_theme_color("font_color", "Button")), "珊瑚小钮常态是深字")
	_check(_is_dark(chip.get_theme_color("font_focus_color", "Button")), "珊瑚小钮聚焦仍是深字")
	_check(_is_dark(chip.get_theme_color("font_pressed_color", "Button")), "珊瑚小钮按下仍是深字")
	chip.free()


func _is_dark(c: Color) -> bool:
	return c.r < 0.25 and c.b > c.r


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
