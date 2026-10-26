extends RefCounted
## 城中各处的页：一港一张名单，一处一张事页。工席走 Main 的潮玻璃，离开钮在页脚。
## 不改 current_scene_id，存档仍记港口。筹码在工席里，不挂在 choices_container 的直接子级上。

const Book := preload("res://scripts/core/Districts.gd")


static func open_index(main, port_id: String) -> void:
	main._enter_panel_mode()
	main.scene_title.text = "城中各处"
	var pname := GameManager.get_port_name(port_id)
	main.body_text.text = "%s城里不止码头这一处。坊巷、寺观、衙廊，各有各的事。" % pname
	# 按类分组，长名单不挤成一排。
	var rows := Book.districts_of(port_id)
	var groups: Dictionary = {}
	var order: Array = []
	for row in rows:
		var k := str(row.get("kind", ""))
		if not groups.has(k):
			groups[k] = []
			order.append(k)
		(groups[k] as Array).append(row)
	for k in order:
		var kk := str(k)
		var header := Label.new()
		header.name = "DistrictGroupHeader"
		header.text = Book.kind_label(kk)
		UiTheme.style_section_label(header)
		main.choices_container.add_child(header)
		main._begin_benches()
		for row in (groups[kk] as Array):
			var card: VBoxContainer = main._slip_body()
			main._slip_title(card, str(row.get("name", "")), Book.kind_label(str(row.get("kind", ""))))
			main._slip_note(card, str(row.get("description", "")))
			var line: HFlowContainer = main._slip_row(card)
			var why := Book.district_reason(row)
			if why == "":
				var chip: Button = main._slip_chip(line, "进去", _enter.bind(main, port_id, str(row.get("id", ""))), true)
				chip.tooltip_text = str(row.get("description", ""))
			else:
				var stamp: Button = main._slip_stamp(line, why)
				stamp.tooltip_text = why
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
	# 按事类分组。
	var ixs: Array = []
	for ix in row.get("interactions", []):
		if typeof(ix) != TYPE_DICTIONARY:
			continue
		if Book.hidden(ix):
			continue
		ixs.append(ix)
	var groups: Dictionary = {}
	var order: Array = []
	for ix in ixs:
		var cat := _ix_group(ix)
		if not groups.has(cat):
			groups[cat] = []
			order.append(cat)
		(groups[cat] as Array).append(ix)
	for cat in order:
		var header := Label.new()
		header.name = "DistrictGroupHeader"
		header.text = cat
		UiTheme.style_section_label(header)
		main.choices_container.add_child(header)
		main._begin_benches()
		for ix in (groups[cat] as Array):
			_paint(main, port_id, dist_id, ix)
		main._end_benches()
	_leave(main, _back.bind(main, port_id))


static func _ix_group(ix: Dictionary) -> String:
	var t := str(ix.get("type", ""))
	match t:
		"buy", "sell":
			return "买卖"
		"invest":
			return "入股"
		"hire":
			return "雇人"
		"rumor":
			return "传闻"
		"licence":
			return "公凭"
		"choice":
			return "抉择"
		"favour":
			return "行事"
		_:
			return "事"


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
	var cd := int(ix.get("cooldown_days", 0))
	if cd > 0:
		note += "\n办后 %d 日可再办。" % cd
	main._slip_note(card, note)
	var line: HFlowContainer = main._slip_row(card)
	var mode := str(v.get("mode", "stamp"))
	if mode == "dismiss":
		var chip: Button = main._slip_chip(line, "辞退", _dismiss.bind(main, port_id, dist_id, str(ix.get("id", ""))))
		chip.tooltip_text = "辞退帮手，月俸不再发。"
		return
	if mode == "choice":
		for opt in ix.get("options", []):
			if typeof(opt) != TYPE_DICTIONARY:
				continue
			var ov: Dictionary = Book.view_option(port_id, ix, opt)
			var chip: Button = main._slip_chip(line, str(ov.get("label", "就这样")), _press.bind(main, port_id, dist_id, str(ix.get("id", "")), str(opt.get("id", ""))))
			chip.disabled = not bool(ov.get("open", false))
			var reason := str(ov.get("reason", ""))
			if reason != "":
				chip.tooltip_text = reason
			elif not bool(ov.get("open", false)):
				chip.tooltip_text = "囊中不足"
			else:
				var cost := int(opt.get("cost", 0))
				if cost > 0:
					chip.tooltip_text = "费 %d 钱" % cost
				else:
					chip.tooltip_text = "办理"
		return
	if mode == "chip":
		var chip2: Button = main._slip_chip(line, str(v.get("label", "办理")), _press.bind(main, port_id, dist_id, str(ix.get("id", "")), ""), true)
		chip2.disabled = not bool(v.get("affordable", false))
		if not bool(v.get("affordable", false)):
			chip2.tooltip_text = "囊中不足"
		else:
			var hint := _cost_hint(port_id, ix, v)
			if cd > 0:
				hint += "　办后 %d 日可再办" % cd
			chip2.tooltip_text = hint if hint != "" else "办理"
		return
	var stamp: Button = main._slip_stamp(line, str(v.get("reason", "眼下办不了")))
	stamp.tooltip_text = str(v.get("reason", "眼下办不了"))


static func _cost_hint(port_id: String, ix: Dictionary, v: Dictionary) -> String:
	var t := str(ix.get("type", ""))
	var money := 0
	if t == "buy" or t == "sell":
		money = Book.unit_price(port_id, ix) * maxi(1, int(ix.get("qty", 1)))
	elif t == "invest":
		var costs: Array = ix.get("costs", [])
		var level := Book.level_of(str(ix.get("id", "")))
		if level >= 0 and level < costs.size():
			money = int(costs[level])
	else:
		money = int(ix.get("cost", 0))
	var parts: Array = []
	if money > 0:
		parts.append("费 %d 钱" % money)
	var req := str(ix.get("needs_licence", ""))
	if req != "":
		parts.append("需公凭")
	var hire := str(ix.get("needs_hire", ""))
	if hire != "":
		parts.append("需帮手")
	if bool(ix.get("unlock", {}).get("siege", false)):
		parts.append("需城防")
	return "　".join(parts)


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