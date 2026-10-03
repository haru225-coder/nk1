extends RefCounted
## 住处 / 寺观页（ResidencePage）：住处「边记」「歇息」两张工席；兴化玉湖陈宅；寺观近侧旧迹工席
## （未勘「细看一日」、已勘未拓「拓碑一日」）与细看 / 拓碑两个回调、拓记字样两个小件。Lane main9 从 Main.gd 原样搬出（第九刀，
## _setup_residence … _on_temple_rub，夹在中间的 TEMPLE_LOOK_DAYS / TEMPLE_RUB_DAYS 常量不搬）；
## lane w20-a9 第十三刀二追加搬入 _setup_residence_chen（台账头注与第九刀那节都标了它）。
## Main 留同名同签名的一行转发（_setup_residence / _setup_temple / _setup_residence_chen / _temple_rub_note / _has_temple_rub /
## _on_temple_look / _on_temple_rub），调用点、信号目标都不动：_setup_dynamic_scene 仍调 Main._setup_residence / _setup_temple；
## 「歇 N 日」仍 bind 到 Main._on_rest，「细看一日」「拓碑一日」仍 bind 到 Main 的同名方法；smoke 仍在 Main 实例上直调
## _temple_rub_note / _has_temple_rub。
## 留在 Main 的：HOME_RATE / TEMPLE_* / CHEN_ZAN_* 常量（verify_economy / check_symbols / story 的 zan_cases 直读 / 直调）、
## _on_rest、工席小件，经 main 取；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文；lambda 里捕获
## log_msg / load_scene / current_scene_id 的，拼回后换回 self，与搬走前的逐字正文一致）。


## 住宅：看边记、便宜歇息。候风仍去旅店——下处等不到风向。
static func setup_residence(main: Control, port_id: String) -> void:
	if port_id == "xinghua":
		main._setup_residence_chen(port_id)
		return
	main.scene_title.text = "%s・住处" % GameManager.get_port_name(port_id)
	main.body_text.text = "租来的下处。比旅店便宜，听不见风信。"
	main._begin_benches()

	var book: VBoxContainer = main._slip_body()
	main._slip_title(book, "边记", "学者 %d　海路 %d" % [GameState.scholar_tendency, GameState.sea_tendency])
	if GameState.ledger_notes.is_empty():
		main._slip_note(book, "案上只有叔父那几卷未清的旧账。")
	else:
		for note in GameState.ledger_notes:
			main._slip_note(book, str(note))

	var home: VBoxContainer = main._slip_body()
	main._slip_title(home, "歇息", "候风仍去旅店")
	var home_row: HFlowContainer = main._slip_row(home)
	for n in [1, 3]:
		var nights := int(n)
		main._slip_chip(
			home_row,
			"歇 %d 日　%d" % [nights, nights * main.HOME_RATE],
			main._on_rest.bind(nights, port_id, main.HOME_RATE, "下处")
		)

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


## 寺观：上陆勘见近侧旧迹。记入册子，拓纸入边记；赏格仍回市舶司呈报——不在这里发名声。
static func setup_temple(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・寺观" % GameManager.get_port_name(port_id)
	main.body_text.text = "住持不谈功名。细看记入册子，拓纸带回住处，赏格回市舶司。"
	if GameState.has_flag("japan_temple_network"):
		main.body_text.text += "\n袖底那张寺社短札，这里的沙弥看过一眼就不再多问。"
	main._begin_benches()

	var near: Array = GameManager.discoveries_near(port_id)
	if near.is_empty():
		var empty: VBoxContainer = main._slip_body()
		main._slip_title(empty, "近侧旧迹", "没有可勘的")
		main._slip_note(empty, "海上撞见的，回市舶司呈报即可。")
	else:
		for d in near:
			var did := str(d.get("id", ""))
			var name := str(d.get("name", did))
			var hook := str(d.get("historical_hook", ""))
			var slip: VBoxContainer = main._slip_body()
			if not GameState.has_found(did):
				main._slip_title(slip, name, "未勘")
				var look: Button = main._slip_chip(main._slip_row(slip), "细看一日", main._on_temple_look.bind(did, name), true)
				look.tooltip_text = "%s\n%s" % [d.get("location", ""), hook]
				continue
			if did in GameState.discoveries_found:
				main._slip_title(slip, name, "已入册")
				main._slip_note(slip, "赏格回市舶司。")
			else:
				main._slip_title(slip, name, "已呈案")
			if main._has_temple_rub(name):
				main._slip_note(slip, "拓纸已入边记，回住处可翻。", UiTheme.MOSS)
			else:
				var rub: Button = main._slip_chip(main._slip_row(slip), "拓碑一日", main._on_temple_rub.bind(did, name, hook))
				rub.tooltip_text = hook

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


static func temple_rub_note(name: String, hook: String) -> String:
	var body := hook.strip_edges()
	if body == "":
		return "拓「%s」。" % name
	return "拓「%s」　%s" % [name, body]


static func has_temple_rub(name: String) -> bool:
	var needle := "拓「%s」" % name
	for note in GameState.ledger_notes:
		if str(note).begins_with(needle):
			return true
	return false


static func on_temple_look(main: Control, did: String, name: String) -> void:
	GameManager.advance_days(main.TEMPLE_LOOK_DAYS)
	if GameState.record_discovery(did):
		main.log_msg("【勘见】廊下细看 %d 日，「%s」记入册子。赏格回市舶司呈报。如今是 %s。" % [
			main.TEMPLE_LOOK_DAYS, name, Calendar.get_date_string(),
		])
	else:
		main.log_msg("沿廊走了一圈，「%s」与册上所记并无出入。" % name)
	main.load_scene(main.current_scene_id)


static func on_temple_rub(main: Control, did: String, name: String, hook: String) -> void:
	if did == "" or not GameState.has_found(did):
		main.log_msg("还没细看过，「%s」纸上拓不出字。" % name)
		main.load_scene(main.current_scene_id)
		return
	GameManager.advance_days(main.TEMPLE_RUB_DAYS)
	if main._has_temple_rub(name):
		main.log_msg("纸上墨迹未干，「%s」已经拓过了。" % name)
	else:
		GameState.add_ledger_note(main._temple_rub_note(name, hook))
		main.log_msg("【拓碑】在寺观廊下拓了 %d 日，把「%s」写入边记。回住处可翻。如今是 %s。" % [
			main.TEMPLE_RUB_DAYS, name, Calendar.get_date_string(),
		])
	main.load_scene(main.current_scene_id)


## 兴化玉湖陈宅：1268 殿试前替族里跑事（唯一的「乡土」早期写入点）、1270 起族叔陈瓒愿入船股一分。
## （lane w20-a9 第十三刀二：从 Main.gd 原样搬出；原来两个 lambda 捕获的是 Main 的 log_msg / load_scene / current_scene_id，
## 搬来后改捕获 main——按下时才读，与搬走前行为一致；CHEN_ZAN_* 三个常量留在 Main，经 main. 取）
static func setup_residence_chen(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・玉湖陈宅" % GameManager.get_port_name(port_id)
	var mother: String = "母亲黄氏在隔壁厢房摇着织机，一声声像是催你动笔。" if Calendar.year < 1270 else "母亲黄氏的织机停了，她的手已经摇不动。她坐在织机旁边看你。"
	main.body_text.text = "祠堂的灯还是二十年前那盏。%s\n案上压着一叠策论草稿，纸边微硬。" % mother

	# 1268 殿试前：替族里跑事。这是「乡土」这条身份唯一的早期写入点。
	if GameState.identity == "undecided":
		var errand := Button.new()
		errand.text = "替族里跑一趟事（费 6 日・30 钱，乡土 +3）"
		errand.disabled = GameState.money < 30
		errand.pressed.connect(func():
			if not GameState.spend_money(30):
				return
			GameState.hometown_tendency += 3
			GameManager.advance_days(6)
			main.log_msg("修祠堂的木料、外姓那桩田讼、三房的婚事——都不是你的事，可族里只找得到你。")
			main.load_scene(main.current_scene_id)
		)
		main.choices_container.add_child(errand)

	if GameState.has_flag("chen_zan_stake"):
		var l := Label.new()
		l.text = "族叔陈瓒的船股一分，记在账上。他说过：「几时回，走哪条水，要先说。」"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.65, 0.9, 0.7))
		main.choices_container.add_child(l)
	elif Calendar.year >= main.CHEN_ZAN_FROM_YEAR and main._chen_zan_alive() and main._chen_zan_stake_open():
		var b := Button.new()
		if GameState.fame >= main.CHEN_ZAN_MIN_FAME:
			b.text = "族叔陈瓒愿入船股一分（得 %d 钱，乡土 +5）" % main.CHEN_ZAN_STAKE
			b.pressed.connect(func():
				GameState.add_money(main.CHEN_ZAN_STAKE)
				GameState.hometown_tendency += 5
				GameState.set_flag("chen_zan_stake")
				GameState.add_ledger_note("陈瓒船股一分")
				main.log_msg("陈瓒把三千钱推过案来，没数。「要多少、走哪条水、几时回——这三句先说清，钱就是你的。」")
				main.load_scene(main.current_scene_id)
			)
		else:
			b.text = "族叔陈瓒——「名声不到 %d，钱不能给你」" % main.CHEN_ZAN_MIN_FAME
			b.disabled = true
		main.choices_container.add_child(b)

	main.choices_label.visible = true
	# 搬进本件时漏了搬前的这一行（lane w53-6 补回）：没有它陈宅页回不了港——身份已定又不到 1270 年连一枚钮都没有
	main._add_leave_button(port_id)

