extends RefCounted
## 城中各处的页：一港一张名单，一处一张事页。工席走 Main 的潮玻璃，离开钮在页脚。
## 不改 current_scene_id，存档仍记港口。筹码在工席里，不挂在 choices_container 的直接子级上。

const Book := preload("res://scripts/core/Districts.gd")


static func open_index(main, port_id: String) -> void:
	main._enter_panel_mode()
	main.scene_title.text = "城中各处"
	var pname := GameManager.get_port_name(port_id)
	main.body_text.text = "%s城里不止码头这一处。坊巷、寺观、衙廊，各有各的事。" % pname
	main._begin_benches()
	for row in Book.districts_of(port_id):
		var card: VBoxContainer = main._slip_body()
		main._slip_title(card, str(row.get("name", "")), Book.kind_label(str(row.get("kind", ""))))
		main._slip_note(card, str(row.get("description", "")))
		var line: HFlowContainer = main._slip_row(card)
		var why := Book.district_reason(row)
		if why == "":
			main._slip_chip(line, "进去", _enter.bind(main, port_id, str(row.get("id", ""))), true)
		else:
			main._slip_stamp(line, why)
	main._end_benches()
	_leave(main, _to_port.bind(main, port_id))


static func open_district(main, port_id: String, dist_id: String, flash := "") -> void:
	var row := Book.district(dist_id)
	if row.is_empty() or str(row.get("port", "")) != port_id:
		open_index(main, port_id)
		return
	if Book.district_reason(row) != "":
		open_index(main, port_id)
		return
	main._enter_panel_mode()
	main._set_background_file(str(row.get("bg", "")))
	main.scene_title.text = str(row.get("name", "城中"))
	var body := str(row.get("description", ""))
	if flash != "":
		body += "\n\n" + flash
	main.body_text.text = body
	main._begin_benches()
	for ix in row.get("interactions", []):
		if typeof(ix) != TYPE_DICTIONARY:
			continue
		_paint(main, port_id, dist_id, ix)
	main._end_benches()
	_leave(main, _back.bind(main, port_id))


static func _paint(main, port_id: String, dist_id: String, ix: Dictionary) -> void:
	var v: Dictionary = Book.view(port_id, ix)
	if bool(v.get("hidden", false)):
		return
	var card: VBoxContainer = main._slip_body()
	main._slip_title(card, str(ix.get("label", "一事")), str(v.get("aside", "")))
	var note := str(ix.get("text", ""))
	var extra := str(v.get("note", ""))
	if extra != "" and extra != note:
		note += "\n" + extra
	if str(ix.get("type", "")) == "hire" and Book.is_hired(str(ix.get("id", ""))):
		var ease := int(ix.get("attention_ease", 0))
		if ease > 0:
			note += "\n在身边时，蒲家留意每月减 %d。" % ease
	main._slip_note(card, note)
	var line: HFlowContainer = main._slip_row(card)
	var mode := str(v.get("mode", "stamp"))
	if mode == "dismiss":
		main._slip_chip(line, "辞退", _dismiss.bind(main, port_id, dist_id, str(ix.get("id", ""))))
		return
	if mode == "choice":
		for opt in ix.get("options", []):
			if typeof(opt) != TYPE_DICTIONARY:
				continue
			var ov: Dictionary = Book.view_option(port_id, ix, opt)
			var chip: Button = main._slip_chip(line, str(ov.get("label", "就这样")), _press.bind(main, port_id, dist_id, str(ix.get("id", "")), str(opt.get("id", ""))))
			chip.disabled = not bool(ov.get("open", false))
			if str(ov.get("reason", "")) != "":
				chip.tooltip_text = str(ov.reason)
		return
	if mode == "chip":
		var chip2: Button = main._slip_chip(line, str(v.get("label", "办理")), _press.bind(main, port_id, dist_id, str(ix.get("id", "")), ""), true)
		chip2.disabled = not bool(v.get("affordable", false))
		if not bool(v.get("affordable", false)):
			chip2.tooltip_text = "囊中不足"
		return
	main._slip_stamp(line, str(v.get("reason", "眼下办不了")))


static func _press(main, port_id: String, dist_id: String, ix_id: String, opt_id: String) -> void:
	var res: Dictionary = Book.apply(ix_id, opt_id)
	var msg := str(res.get("msg", ""))
	if msg != "":
		main.log_msg(msg)
	open_district(main, port_id, dist_id, msg if bool(res.get("ok", false)) else "")


static func _dismiss(main, port_id: String, dist_id: String, ix_id: String) -> void:
	var ix := Book.interaction(ix_id)
	var where := str(Book.district(dist_id).get("name", "城中"))
	Book.dismiss(ix_id)
	var msg := "【%s】%s辞了。" % [where, str(ix.get("who", "帮手"))]
	main.log_msg(msg)
	open_district(main, port_id, dist_id, msg)


static func _enter(main, port_id: String, dist_id: String) -> void:
	open_district(main, port_id, dist_id, "")


static func _back(main, port_id: String) -> void:
	main._set_background_file(main._port_bg(port_id))
	open_index(main, port_id)


static func _to_port(main, port_id: String) -> void:
	main.load_scene(port_id)


static func _leave(main, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = "离开"
	btn.custom_minimum_size = Vector2(160, 42)
	btn.pressed.connect(cb)
	var host: Node = main._page_footer if main._page_footer != null else main.choices_container
	host.add_child(btn)
	UiTheme.style_leave_button(btn)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.choices_label.visible = false
