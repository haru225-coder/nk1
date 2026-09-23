extends SceneTree
## 巡检：把主场景挂上，走开局、三港、九个设施页，再量海图。
## 非滚动区的按钮必须落在 1280×720 里；珊瑚主钮聚焦时仍是深字。
## 海图港口列表露出的每一行必须完整，账条变高时海图不低于自己的最小高度。
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
	_check_port_rows(chart, "海图未选")
	chart._on_port_selected("fuzhou")
	for _i in 4:
		await process_frame
	_check_port_rows(chart, "海图福州")
	_check_chart_floor(chart, "海图福州")
	_shot_chart(chart, "seachart-fuzhou")

	var fleet: Node = root.get_node("Fleet")
	fleet.water = 0
	fleet.food = 0
	chart.origin_port = "xinghua"
	chart._refresh_ports()
	for _i in 4:
		await process_frame
	chart._on_port_selected("ryukyu")
	for _i in 4:
		await process_frame
	_check_port_rows(chart, "海图生路告警")
	_check_chart_floor(chart, "海图生路告警")
	_check_tint_holds(chart, "海图生路告警")
	_shot_chart(chart, "seachart-warning")


func _check_port_rows(chart: Node, tag: String) -> void:
	var scroll: ScrollContainer = chart.get("_port_scroll")
	_check(scroll != null, "%s 有港口列表" % tag)
	if scroll == null:
		return
	var sr := scroll.get_global_rect()
	var partial := 0
	var shown := 0
	var list: Node = chart.get("port_list")
	for c in list.get_children():
		if not (c is Button) or (c as CanvasItem).is_queued_for_deletion():
			continue
		var r := (c as Button).get_global_rect()
		if r.size.y <= 1.0 or not r.intersects(sr):
			continue
		shown += 1
		var inside := r.position.y >= sr.position.y - 0.5 and r.end.y <= sr.end.y + 0.5
		if not inside:
			partial += 1
	_check(shown > 0 and partial == 0, "%s 可见港口都是整行（露出 %d，切到 %d，列表高 %.0f）" % [
		tag, shown, partial, sr.size.y,
	])


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


func _check_tint_holds(chart: Node, tag: String) -> void:
	var list: Node = chart.get("port_list")
	var tinted := 0
	var lost := 0
	for c in list.get_children():
		if not (c is Button):
			continue
		var btn := c as Button
		var normal: Color = btn.get_theme_color("font_color", "Button")
		var focus: Color = btn.get_theme_color("font_focus_color", "Button")
		var pressed: Color = btn.get_theme_color("font_pressed_color", "Button")
		if _color_near(normal, UiTheme.TEXT):
			continue
		tinted += 1
		if not _color_near(focus, normal) or not _color_near(pressed, normal):
			lost += 1
	_check(tinted > 0 and lost == 0, "%s 警告色在聚焦和按下时还在（着色 %d，丢色 %d）" % [tag, tinted, lost])


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
