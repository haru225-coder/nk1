extends RefCounted
## 酒馆 / 旅店页（TavernPage）：酒馆正文与工席（行情「打听」、在侧人物卡、旧事挑签）、募人（在船卡 + 候选人物卡 + 朱印雇入钮）、
## 人物卡小件（右栏 + 底行 + 朱印）与旅店「歇息・候风」工席。Lane main4 从 Main.gd 原样搬出（第四刀，整页 + 回调）。
## Main 留同名同签名的一行转发（_setup_tavern / _setup_story_hooks / _on_story_hook / _on_gather_intel / _setup_hiring /
## _person_slip / _person_foot / _seal_chip / _setup_inn），调用点、节点路径、信号目标都不动：旧事挑签、「打听」、「雇入」、
## 「辞退」、「歇 N 日」仍 connect 到 Main 的同名方法。
## 留在 Main 的：_setup_news_wall（市井札薄的薄调，门禁直读 Main.gd 核 _TAVERN_NEWS_WALL.mount）、_skill_rank（船籍簿也用）、
## INN_RATE / HIRE_PIC 常量（simulate_run 直读 Main.gd 的 INN_RATE），经 main 取；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


static func setup_tavern(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・酒馆" % GameManager.get_port_name(port_id)
	main.body_text.text = "劣酒与潮气同在，邻桌谈远港价目。闻讯、募人都在这几张桌边。月俸按月；欠饷三月，则人去。"

	# 墙上贴最近三条已投放新闻；旧事仍走挑签。打听和募人进工席。
	main._setup_news_wall()
	main._setup_story_hooks(port_id)
	main._begin_benches()

	if port_id.begins_with("quanzhou"):
		main._add_npc_button("merchant_lin", "林阿舶")
	elif port_id.begins_with("ryukyu"):
		main._add_npc_button("pilot_ana", "阿那")

	var intel: VBoxContainer = main._slip_body()
	main._slip_title(intel, "行情", "费一日")
	# 「打听」费一日（advance_days：耗水粮、推逐日结算）：花时间的动作和花钱的一样不做整卡可点，免得点卡误过一天（第 2 轮工程 m5）
	main._slip_chip(main._slip_row(intel), "打听", main._on_gather_intel.bind(port_id))

	main._setup_hiring(port_id)
	main._end_benches()

	main._add_leave_button(port_id)
	main.choices_label.visible = false


static func setup_story_hooks(main: Control, port_id: String) -> void:
	var hooks: Array = GameState.story_hooks_at(port_id)
	if hooks.is_empty():
		return
	var sep := Label.new()
	sep.text = "旧事"
	UiTheme.style_section_label(sep)
	main.choices_container.add_child(sep)
	for h in hooks:
		var btn := Button.new()
		btn.text = str(h.get("label", "追问"))
		btn.pressed.connect(main._on_story_hook.bind(h, port_id))
		main.choices_container.add_child(btn)
		UiTheme.style_choice_button(btn)


static func on_story_hook(main: Control, hook: Dictionary, port_id: String) -> void:
	var flag_name := str(hook.get("flag", ""))
	if flag_name != "":
		GameState.set_flag(flag_name)
	var msg := str(hook.get("text", ""))
	if msg != "":
		main.log_msg(msg)
	main.update_status_panel()
	main.load_scene(main.current_scene_id if main.current_scene_id != "" else port_id + "_tavern")


static func on_gather_intel(main: Control, port_id: String) -> void:
	GameManager.advance_days(1)
	main.log_msg(main._gather_price_intel(port_id))
	main.load_scene(main.current_scene_id)


## 酒馆募人。每种职事至多一人，故已雇之职不再列出候选。
## characters 线：候选人与在船人员都排成横向人物卡（小立绘 + 名 + 职事品级 + 五维迷你条 + 钱数 + 钮）；
## 卡上文案与数值照旧（「火长　初习」「入伙 120　月俸 60」「雇入」「辞退」），钮的回调不变。
static func setup_hiring(main: Control, port_id: String) -> void:
	# 在船的人
	if not Crew.hired.is_empty():
		for c in Crew.roster():
			var rname: String = Crew.role_def(c.get("role", "")).get("name", "")
			var aboard: VBoxContainer = main._person_slip(GameManager.character_for_crew(str(c.get("id", ""))), str(c.get("name", "")),
				"%s　%s　月俸 %d" % [rname, main._skill_rank(int(c.get("level", 1))), int(c.get("wage", 0))],
				int(c.get("level", 1)))
			var aboard_hint := aboard.get_node("Head/Aside") as Label
			aboard_hint.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.MOSS))
			var rid: String = str(c.get("role", ""))
			var foot: HBoxContainer = main._person_foot(aboard, "在船")
			var off: Button = main._slip_chip(foot, "辞退", main._on_dismiss_crew.bind(rid))
			off.tooltip_text = "辞退即上岸。入伙钱不退。"

	# 募人题签：有候选、无候选都先出这一张，旁注只记事实（Lane AB）
	var cands := Crew.candidates_at(port_id)
	var head: VBoxContainer = main._slip_body()
	if cands.is_empty():
		main._slip_title(head, "募人", "本港眼下无人可雇")
		if not Crew.hired.is_empty():
			main._slip_note(head, "已雇之职不再列名。")
		return
	main._slip_title(head, "募人", "本港可雇 %d 人　一职一人" % cands.size())
	main._slip_note(head, "入伙钱当场付清，月俸按月扣。")

	for c in cands:
		var cid: String = str(c.get("id", ""))
		var role: Dictionary = Crew.role_def(c.get("role", ""))
		var cch: Dictionary = GameManager.character_for_crew(cid)
		var card: VBoxContainer = main._person_slip(cch, str(c.get("name", "")), "%s　%s" % [
			role.get("name", ""), main._skill_rank(int(c.get("level", 1))),
		], int(c.get("level", 1)))
		# 职事真正管用的是这一句（航程、价差、减员……），写在品级下面；五维只作展示，压淡（第 1 轮评审 UX M5）
		var eff := str(role.get("effect_hint", ""))
		if eff != "":
			var eff_lbl := Label.new()
			eff_lbl.name = "EffectHint"
			eff_lbl.text = eff
			eff_lbl.add_theme_font_override("font", UiTheme.font())
			eff_lbl.add_theme_font_size_override("font_size", 16)
			eff_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT))
			eff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(eff_lbl)
			card.move_child(eff_lbl, 1)
		# 只压淡细条，字不压：整条 modulate 0.55 时纸上 16px 字实渲染只剩 2.2–3.2:1（返工自查，cap3 rend 实测）
		var strip := card.get_node_or_null("AttrStrip") as Control
		if strip != null:
			for col in strip.get_children():
				for part in col.get_children():
					if not (part is HBoxContainer):
						(part as CanvasItem).modulate = Color(1, 1, 1, 0.55)
		# 在酒馆里见过画像与五维的候选，人物志里记作已识（本会话，不入存档）
		main._CHAR_ART.note_met(str(cch.get("id", "")))
		var foot: HBoxContainer = main._person_foot(card, "入伙 %d　月俸 %d" % [Crew.signing_fee(cid), int(c.get("wage", 0))])
		var hire: Button = main._slip_chip(foot, "雇入", main._on_hire_candidate.bind(cid), true)
		main._seal_chip(hire)
		hire.tooltip_text = "%s\n\n%s\n%s" % [
			c.get("bio", ""), role.get("desc", ""), role.get("effect_hint", ""),
		]


## 人物卡的右栏：名（绢本马善政）+ 品级点 / 旁注 / 五维迷你条。返回右栏，调用方再往下接 _person_foot。
## ch 为空（设定集里查无此人）时画框里是一方墨，五维条不出，文案照旧。
static func person_slip(main: Control, ch: Dictionary, title: String, aside: String, level := 0) -> VBoxContainer:
	var body: VBoxContainer = main._slip_body()
	var row := HBoxContainer.new()
	row.name = "PersonRow"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(row)
	var tex: Texture2D = main._CHAR_ART.thumb(ch, main.HIRE_PIC) if not ch.is_empty() else null
	row.add_child(main._CHAR_ART.framed(tex, Vector2(main.HIRE_PIC), true))
	var info := VBoxContainer.new()
	info.name = "Info"
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var head := VBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 与其它工席抬头同一写法：绢本宣纸上是马善政靛青（大四号），夜潮是石青正文字。这里直接写定，不等卡片换色
	name_lbl.add_theme_font_override("font", UiTheme.title_font() if UiTheme.IS_JUANBEN else UiTheme.font())
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY + (4 if UiTheme.IS_JUANBEN else 0))
	name_lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TIDE))
	name_lbl.set_meta(&"nk1_title", true)
	name_row.add_child(name_lbl)
	if level > 0:
		name_row.add_child(main._CHAR_ART.pips(level, true))
	var hint := Label.new()
	hint.name = "Aside"
	hint.text = aside
	UiTheme.style_footnote(hint)
	hint.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
	head.add_child(hint)
	if not ch.is_empty():
		var strip: HBoxContainer = main._CHAR_ART.attr_strip(ch, 56.0, true)
		info.add_child(strip)
	return info


## 人物卡底行：左边一句钱数 / 在船，右边钮。返回放钮的那一格。
static func person_foot(info: VBoxContainer, note: String) -> HBoxContainer:
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(foot)
	var lbl := Label.new()
	lbl.text = note
	UiTheme.style_footnote(lbl)
	lbl.add_theme_color_override("font_color", UiTheme.on_paper(UiTheme.TEXT_DIM))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(lbl)
	return foot


## 募人钮放大成一方朱印：马善政、四周留足，一眼看得见（仍是 style_chip 的朱砂四态与印面字）。
static func seal_chip(btn: Button) -> void:
	if not UiTheme.IS_JUANBEN:
		return
	btn.add_theme_font_override("font", UiTheme.title_font())
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(78, 34)


## 旅店：候风。季风按月转向，等到对的月份再发舶是这个游戏最要紧的判断之一。
static func setup_inn(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・旅店" % GameManager.get_port_name(port_id)
	main.body_text.text = "通铺草席还潮着。风信不对时，海商在这儿候着。"
	main._begin_benches()

	var rest: VBoxContainer = main._slip_body()
	main._slip_title(rest, "歇息", "%s　%s" % [Calendar.get_date_string(), Calendar.get_monsoon_desc()])
	main._slip_note(rest, main._monsoon_forecast(), UiTheme.HONEY)
	# 在身委办的期限提醒（云端 bed9），嵌进主干的歇息工席
	var rest_cst := GameState.contract_status()
	if not rest_cst.is_empty():
		var rest_left := int(rest_cst.get("days_left", 0))
		if rest_left < 0:
			main._slip_note(rest, "在身委办已经逾期，歇着也会被牙行扣钱。", UiTheme.CINNABAR)
		else:
			main._slip_note(rest, "在身委办还剩 %d 日。歇过这个数，牙行要扣钱、掉名声。" % rest_left, UiTheme.CINNABAR)
	var rest_row: HFlowContainer = main._slip_row(rest)
	for n in [1, 10]:
		var nights := int(n)
		main._slip_chip(rest_row, "歇 %d 日　%d%s" % [nights, nights * main.INN_RATE, main._contract_rest_mark(nights)], main._on_rest.bind(nights, port_id))
	var to_next: int = Calendar.DAYS_PER_MONTH - Calendar.day + 1
	main._slip_chip(
		rest_row,
		"候 %d 日　%d%s" % [to_next, to_next * main.INN_RATE, main._contract_rest_mark(to_next)],
		main._on_rest.bind(to_next, port_id),
		true
	)

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false

