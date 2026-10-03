extends RefCounted
## 行会 / 贡院页（GuildExamPage）：行会「出港行情」抄本（海商信用够多抄两条）+ 会籍 / 入行工席、入行门槛与交会费回调；
## 贡院「誊录」「赴试」两张工席（别港只誊录、本章已赴只读）与两个回调。Lane main7 从 Main.gd 原样搬出（第七刀，_guild_port_id … _on_exam_sit，
## 夹在中间的公共件 play_transition 不搬）。
## Main 留同名同签名的一行转发（_guild_port_id / _setup_guild / _add_guild_join_slip / _guild_join_block / _on_guild_join /
## _setup_exam / _exam_slip / _on_exam_copy / _exam_sat_flag / _on_exam_sit），调用点、信号目标都不动：_setup_dynamic_scene 仍调 Main._setup_guild /
## _setup_exam；「交会费入行」「替人抄三日」「入场赴试」仍 connect 到 Main 的同名方法；p7 门禁仍直调 Main._on_guild_join / _on_exam_sit。
## 留在 Main 的：GUILD_* / EXAM_* 常量（verify_economy / simulate_run 直读 Main.gd）、play_transition、_collect_spreads、工席小件，经 main 取；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


## 行会页 id 是港卡 city_guild 按 current_scene_id 改写的 {港}_guild；入行港判定与 guild_<港> 旗标一律记在基港 id 上。
## 尾部 _guild 剥尽（{港}_guild_guild 也收回基港），否则三港在实际页 id 下认不出，或同港旗标记成两份、会费扣两次。
static func guild_port_id(page_id: String) -> String:
	var base := page_id
	while base.ends_with("_guild"):
		base = base.trim_suffix("_guild")
	return base


## 行会：出港行情抄本。酒馆打听仍费一日只吐一条；这里钉在墙上，不耗日。
static func setup_guild(main: Control, port_id: String) -> void:
	port_id = main._guild_port_id(port_id)
	main.scene_title.text = "%s・行会" % GameManager.get_port_name(port_id)
	main.body_text.text = "墙上钉着远港价目，墨迹有的还潮着。海商信用 %d，足的人会里肯多抄几条远路。" % GameState.merchant_credit
	main._begin_benches()
	main._center_benches()

	var limit: int = 5 if GameState.merchant_credit >= main.GUILD_CREDIT_WIDE else 3
	var rows: Array = main._collect_spreads(port_id, limit)
	if rows.is_empty():
		var empty: VBoxContainer = main._slip_body()
		main._slip_title(empty, "出港行情", "眼下抄不出能赚的路")
		main._slip_note(empty, "过几日行情回一回再来。")
	else:
		for row in rows:
			var slip: VBoxContainer = main._slip_body()
			var hint: Label = main._slip_title(
				slip,
				GameManager.get_good_name(row["good"]),
				"运往 %s　多 %d" % [GameManager.get_port_name(row["port"]), int(row["profit"])]
			)
			hint.add_theme_color_override("font_color", UiTheme.MOSS)
			main._slip_note(slip, "买 %d　卖 %d" % [int(row["buy"]), int(row["sell"])])

	main._add_guild_join_slip(port_id)

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


## 入行：只泉州 / 博多 / 广州。已入行只看账；条件不足按钮仍在，按下只说缘由。
static func add_guild_join_slip(main: Control, port_id: String) -> void:
	port_id = main._guild_port_id(port_id)
	var join: VBoxContainer = main._slip_body()
	var standing := "海商信用 %d　人脉 %d" % [GameState.merchant_credit, GameState.network]
	if not main.GUILD_JOIN_PORTS.has(port_id):
		main._slip_title(join, "会籍", standing)
		main._slip_note(join, "入行只在泉州、博多、广州三座行会。")
		main._slip_stamp(main._slip_row(join, true), "本港无会籍")
		return
	if GameState.has_flag("guild_%s" % port_id):
		main._slip_title(join, "会籍", "%s　名声 %d" % [standing, GameState.fame])
		main._slip_note(join, "会费已交，不再收。")
		main._slip_stamp(main._slip_row(join, true), "本港已入行")
		return
	main._slip_title(join, "入行", standing)
	# 门槛一行、收益一行：原先并成一句，折行后贴着朱钮
	main._slip_note(join, "会费 %d　海商信用须 %d。" % [main.GUILD_JOIN_FEE, main.GUILD_JOIN_CREDIT])
	main._slip_note(join, "入行海商信用加 %d，人脉加 %d；行情、抽解、佣金照旧。" % [
		main.GUILD_JOIN_CREDIT_GAIN, main.GUILD_JOIN_NETWORK_GAIN,
	])
	var chip: Button = main._slip_chip(main._slip_row(join, true), "交会费入行", main._on_guild_join.bind(port_id), true)
	main._slip_whole(chip)


## 返回不收的缘由；空串即可入行。
static func guild_join_block(main: Control, port_id: String) -> String:
	port_id = main._guild_port_id(port_id)
	if not main.GUILD_JOIN_PORTS.has(port_id):
		return "本港不设入行"
	if GameState.has_flag("guild_%s" % port_id):
		return "本港已入行"
	if GameState.merchant_credit < main.GUILD_JOIN_CREDIT:
		return "海商信用不足（%d，须 %d）" % [GameState.merchant_credit, main.GUILD_JOIN_CREDIT]
	if GameState.money < main.GUILD_JOIN_FEE:
		return "现钱不足（%d，会费 %d）" % [GameState.money, main.GUILD_JOIN_FEE]
	return ""


static func on_guild_join(main: Control, port_id: String) -> void:
	port_id = main._guild_port_id(port_id)
	var port_name := GameManager.get_port_name(port_id)
	var why: String = main._guild_join_block(port_id)
	if why != "":
		main.log_msg("【行会】%s行会还不收：%s。" % [port_name, why])
		return
	if not GameState.spend_money(main.GUILD_JOIN_FEE):
		return
	GameState.merchant_credit += main.GUILD_JOIN_CREDIT_GAIN
	GameState.network += main.GUILD_JOIN_NETWORK_GAIN
	GameState.set_flag("guild_%s" % port_id)
	main.log_msg("【入行】在%s行会交了会费 %d，簿上添了名字。海商信用 %d，人脉 %d。" % [
		port_name, main.GUILD_JOIN_FEE, GameState.merchant_credit, GameState.network,
	])
	await main.play_transition("行会・入行", "%s行会　%s" % [port_name, Calendar.get_date_string()],
		main.load_scene.bind(main.current_scene_id), "行")


## 贡院：誊录耗日换工钱与学者倾向，不给名声；赴试每章一次，费 15 日，按倾向记名声。
static func setup_exam(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・贡院" % GameManager.get_port_name(port_id)
	main.body_text.text = "今科未开。只能替人誊录，笔墨钱现结。"
	main._begin_benches()
	main._center_benches()

	var copy: VBoxContainer = main._exam_slip()
	main._slip_title(copy, "誊录", "学者 %d　海路 %d" % [GameState.scholar_tendency, GameState.sea_tendency])
	main._slip_note(copy, "工钱 %d　费 %d 日。" % [main.EXAM_STIPEND, main.EXAM_COPY_DAYS])
	main._slip_note(copy, "学者倾向加 1；不记名声。")
	main._slip_whole(main._slip_chip(main._slip_row(copy, true), "替人抄三日", main._on_exam_copy.bind(port_id), true))

	var sit: VBoxContainer = main._exam_slip()
	main._slip_title(sit, "赴试", "每章一次　费 %d 日" % main.EXAM_SIT_DAYS)
	if not main.EXAM_SIT_PORTS.has(port_id):
		main._slip_note(sit, "赴试只在兴化、泉州两处贡院。")
		main._slip_stamp(main._slip_row(sit, true), "本港无贡院科场")
	elif GameState.has_flag(main._exam_sat_flag()):
		main._slip_note(sit, "本章已赴过，下一章再来。")
		main._slip_note(sit, "名声 %d。" % GameState.fame)
		main._slip_stamp(main._slip_row(sit, true), "本章已赴")
	else:
		main._slip_note(sit, "学者不输海路：名声加 4，学者加 2。")
		main._slip_note(sit, "否则名声加 1，海路加 1。不发钱。")
		main._slip_whole(main._slip_chip(main._slip_row(sit, true), "入场赴试", main._on_exam_sit.bind(port_id), true))

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


static func exam_slip(main: Control) -> VBoxContainer:
	var body: VBoxContainer = main._slip_body()
	body.add_theme_constant_override("separation", 6)
	var card := body.get_parent().get_parent() as Control
	card.custom_minimum_size.y = main.EXAM_SLIP_MIN_H
	return body


## 誊录：与赴试同一时序——工钱与学者倾向先落袋，再 advance_days。
## 三月末誊录会跨入四月，月初 _settle_history 按倾向锁 1268 身份、pay_wages 按现银发饷。
static func on_exam_copy(main: Control, _port_id: String) -> void:
	GameState.add_money(main.EXAM_STIPEND)
	GameState.scholar_tendency += 1
	GameManager.advance_days(main.EXAM_COPY_DAYS)
	main.log_msg("【誊录】在贡院廊下抄了 %d 日试卷，得工钱 %d。学者倾向 %d。如今是 %s。" % [
		main.EXAM_COPY_DAYS, main.EXAM_STIPEND, GameState.scholar_tendency, Calendar.get_date_string(),
	])
	main.load_scene(main.current_scene_id)


static func exam_sat_flag() -> String:
	return "exam_sat_ch%d" % GameState.chapter


## 赴试：只兴化、泉州，每章一次，费 15 日。不发钱、不跳章、不改船。
## 身份相关旗标/倾向必须写在 advance_days 之前：三月下旬赴试会跨入四月，
## 月初 _settle_history 会按 exam_sat 与倾向锁 1268 身份。
static func on_exam_sit(main: Control, port_id: String) -> void:
	if not main.EXAM_SIT_PORTS.has(port_id):
		main.log_msg("【贡院】本港无贡院科场，赴试只在兴化、泉州。")
		return
	var chapter_flag: String = main._exam_sat_flag()
	if GameState.has_flag(chapter_flag):
		main.log_msg("【贡院】本章已赴过试，下一章再来。")
		return
	GameState.set_flag(chapter_flag)
	var res: Dictionary
	var line := ""
	if GameState.scholar_tendency >= GameState.sea_tendency:
		res = GameState.add_fame(4)
		GameState.scholar_tendency += 2
		GameState.set_flag("exam_sat")
		line = "卷子誊上了榜前的簿子。名声加 4，学者倾向 %d。" % GameState.scholar_tendency
	else:
		res = GameState.add_fame(1)
		GameState.sea_tendency += 1
		line = "策论写着写着成了海路账。名声加 1，海路倾向 %d。" % GameState.sea_tendency
	if res.get("promoted", false):
		line += "市舶司案册改题「%s」。" % str(res.get("title", {}).get("name", ""))
	GameManager.advance_days(main.EXAM_SIT_DAYS)
	main.log_msg("【赴试】在贡院坐了 %d 日。%s如今是 %s。" % [
		main.EXAM_SIT_DAYS, line, Calendar.get_date_string(),
	])
	await main.play_transition("贡院・赴试", "%s贡院　%s" % [GameManager.get_port_name(port_id), Calendar.get_date_string()],
		main.load_scene.bind(main.current_scene_id), "试")
