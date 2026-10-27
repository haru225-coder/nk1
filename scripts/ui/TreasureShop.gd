extends RefCounted
## 牙行侧柜「唐物铺」与鉴定：单件收藏，不占舱位。Lane treas1。
## 买 / 鉴定 / 献纳回调都在这里；献纳钮与图鉴行挂在市舶司页（MaritimeOfficePage.setup_reporting）。


static func setup(main: Control, port_id: String) -> void:
	var stock: Array = GameManager.treasures_at_shop(port_id)
	if not stock.is_empty():
		main.body_text.text += "\n\n唐物铺另设侧柜，单件不入舱。"
	# 先在树外搭好一排卡，再整块静默挂上（字后填），整页重排不卡（qa_w53_3）
	var shelf := HFlowContainer.new()
	shelf.name = "TreasureShelf"
	shelf.add_theme_constant_override("h_separation", 12)
	shelf.alignment = FlowContainer.ALIGNMENT_CENTER
	var old_host = main._slip_host
	main._slip_host = shelf
	for t in stock:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var tid := str(t.get("id", ""))
		if tid == "" or GameState.has_treasure(tid):
			continue
		var price := int(t.get("value", 0))
		var body: VBoxContainer = main._slip_body()
		main._slip_title(body, _display_name(t), "价 %d" % price)
		if t.has("unidentified_name"):
			main._slip_note(body, "旧物未鉴。买下后可请人看，看钱为标价十分之一。")
		else:
			main._slip_note(body, "%s・%s・%s" % [
				str(t.get("category", "")), str(t.get("grade", "")), str(t.get("origin", "")),
			])
		var chip: Button = main._slip_chip(main._slip_row(body, true), "购入　%d" % price,
			main._on_buy_treasure.bind(tid, port_id), true)
		chip.tooltip_text = "单件收藏，不占舱位。"

	for tid in GameState.treasures_owned:
		var t2 := GameManager.get_treasure_by_id(str(tid))
		if t2.is_empty() or not t2.has("unidentified_name") or GameState.treasure_appraised(str(tid)):
			continue
		var fee: int = maxi(1, int(t2.get("value", 0)) / 10)
		var body2: VBoxContainer = main._slip_body()
		main._slip_title(body2, str(t2.get("unidentified_name", "")), "看钱 %d" % fee)
		main._slip_note(body2, "请人看过，才知真名与品第。")
		var chip2: Button = main._slip_chip(main._slip_row(body2, true), "鉴定　%d" % fee,
			main._on_appraise_treasure.bind(str(tid)), true)
		chip2.tooltip_text = "鉴定后可在市舶司献纳名声宝物"
	main._slip_host = old_host
	if shelf.get_child_count() > 0:
		main._attach_quiet(main.choices_container, shelf)
	else:
		shelf.free()


static func on_buy(main: Control, tid: String, port_id: String) -> void:
	var res: Dictionary = GameState.buy_treasure(tid, port_id)
	if res.get("ok", false):
		main.log_msg("【唐物】收得「%s」，付 %d 钱，不占舱位。" % [res.get("name", tid), int(res.get("price", 0))])
	else:
		main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


static func on_appraise(main: Control, tid: String) -> void:
	var res: Dictionary = GameState.appraise_treasure(tid)
	if res.get("ok", false):
		main.log_msg("【鉴定】「%s」看真了，付 %d 钱。" % [res.get("name", tid), int(res.get("fee", 0))])
	else:
		main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


static func on_donate(main: Control, tid: String) -> void:
	var res: Dictionary = GameState.donate_treasure(tid)
	if res.get("ok", false):
		var extra := ""
		if res.get("promoted", false):
			extra = "案册改题「%s」。" % str(res.get("title", {}).get("name", ""))
		main.log_msg("【献纳】「%s」入市舶司，名声加 %d。%s" % [
			res.get("name", tid), int(res.get("fame", 0)), extra,
		])
	else:
		main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


## 酒馆里的宝物传闻：每件听过一次就记进线索册，本港不再摆；只列本港在传、未收、未记的
static func setup_rumors(main: Control, port_id: String) -> void:
	var rows: Array = []
	for t in GameManager.treasures_with_rumor_at(port_id):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var tid := str(t.get("id", ""))
		if tid == "" or GameState.has_treasure(tid) or tid in GameState.treasure_leads:
			continue
		var src := GameManager.treasure_rumor_source(tid)
		if src.is_empty():
			continue
		rows.append({"id": tid, "hint": str(src.get("hint", ""))})
	if rows.is_empty():
		return
	var body: VBoxContainer = main._slip_body()
	main._slip_title(body, "传闻", "酒客闲话")
	for row in rows:
		main._slip_note(body, str(row.get("hint", "")))
		main._slip_chip(main._slip_row(body), "记下这条线索",
			main._on_hear_treasure_rumor.bind(str(row.get("id", "")), port_id))


static func on_hear_rumor(main: Control, tid: String, port_id: String) -> void:
	var res: Dictionary = GameState.note_treasure_rumor(tid, port_id)
	if res.get("ok", false):
		main.log_msg("【传闻】记下一条线索：%s" % str(res.get("hint", "")))
	else:
		main.log_msg(str(res.get("msg", "")))
	main.update_status_panel()
	main.load_scene(main.current_scene_id)


static func _display_name(t: Dictionary) -> String:
	if t.has("unidentified_name"):
		return str(t.get("unidentified_name", ""))
	return str(t.get("name", ""))
