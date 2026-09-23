extends SceneTree
## 巡检：把主场景挂上，走开局、三港、九个设施页。
## 非滚动区的按钮必须落在 1280×720 里；珊瑚主钮聚焦时仍是深字。
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

	_finish()


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
