extends RefCounted
## 市舶司页（MaritimeOfficePage）：货引 / 抽解 / 违禁 / 蒲家留意一张工席与请领回调、未呈报发现逐件「呈报」工席与呈报回调、
## 职衔（抽解每百 / 赊贷上限 / 下一档）与修埠工席和投钱回调、蒲家留意档位短句。Lane main8 从 Main.gd 原样搬出（第八刀，_setup_yamen … _attention_desc）。
## Main 留同名同签名的一行转发（_setup_yamen / _on_apply_permit / _setup_reporting / _on_report_discovery / _setup_title_and_invest /
## _on_invest_port / _attention_desc），调用点、信号目标都不动：_setup_dynamic_scene 仍调 Main._setup_yamen；「请领」「呈报」「投钱」仍
## connect 到 Main 的同名方法；qa_discovery_probe 仍直调 Main._on_report_discovery。
## 留在 Main 的：泉州对峙征船名册 _setup_quanzhou_standoff、_duty_per_hundred（smoke 直调）、_add_npc_button、工席小件、离开钮，经 main 取；这里不存状态。
## 门禁 check_symbols 经 MAIN_SPLITS 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）。


static func setup_yamen(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・市舶司" % GameManager.get_port_name(port_id)
	main.body_text.text = "案上压着未批的货单。验引、呈报、修埠都在这里。"
	main._begin_benches()

	main._add_npc_button("customs_official", "市舶司小吏")

	var permit: VBoxContainer = main._slip_body()
	var duty := GameState.customs_duty()
	var contraband := GameState.contraband_units()
	if GameState.has_customs_permit:
		main._slip_title(permit, "货引", "已在手")
		main._slip_note(permit, "本次出港可合法验放。", UiTheme.MOSS)
	else:
		main._slip_title(permit, "货引", "按舱货抽解")
		main._slip_chip(main._slip_row(permit), "请领　%d" % duty, main._on_apply_permit, true)
	if contraband > 0:
		main._slip_note(permit, "舱底尚有违禁 %d 件。报不进明账，验引也遮不住。" % contraband, UiTheme.CINNABAR)
	main._slip_note(permit, "蒲家留意 %d　%s" % [GameState.pu_attention, main._attention_desc()])

	main._setup_reporting()
	# 本地 main：泉州对峙期（1276-77）征船名册三选一，非对峙期内部自行返回
	main._setup_quanzhou_standoff(port_id)
	main._setup_title_and_invest(port_id)

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


static func on_apply_permit(main: Control) -> void:
	var res: Dictionary = GameState.apply_for_permit()
	main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


## 上报发现：航中或寺观记下的东西要回市舶司呈报才换得赏格与名声
static func setup_reporting(main: Control) -> void:
	var pending := GameState.unreported_discoveries()
	if pending.is_empty():
		return

	for did in pending:
		var d := GameManager.get_discovery_by_id(did)
		if d.is_empty():
			continue
		var value: int = int(d.get("value", 50))
		var slip: VBoxContainer = main._slip_body()
		main._slip_title(slip, str(d.get("name", did)), "赏钱 %d　名声 %d" % [value, maxi(1, value / 10)])
		var chip: Button = main._slip_chip(main._slip_row(slip), "呈报", main._on_report_discovery.bind(str(did)), true)
		var tip := str(d.get("location", ""))
		var hook := str(d.get("historical_hook", "")).strip_edges()
		if hook != "":
			tip += "\n" + hook
		chip.tooltip_text = tip + "\n呈报入案，赏钱名声同领。"


static func on_report_discovery(main: Control, did: String) -> void:
	var res: Dictionary = GameState.report_discovery(did)
	if not res.is_empty():
		var extra := ""
		if res.get("promoted", false):
			extra = "案册改题「%s」。" % str(res.get("title", {}).get("name", ""))
		main.log_msg("【呈报】「%s」入案。赏钱 %d，名声添 %d。%s" % [
			res["name"], res["gold"], res["fame"], extra,
		])
	main.load_scene(main.current_scene_id)


static func setup_title_and_invest(main: Control, port_id: String) -> void:
	var rank: Dictionary = GameState.title_rank()
	var nxt: Dictionary = GameState.next_title()
	var rank_slip: VBoxContainer = main._slip_body()
	main._slip_title(rank_slip, "职衔", str(rank.get("name", "")))
	var duty_line := "抽解每百 %d　赊贷上限 %d" % [
		main._duty_per_hundred(float(rank.get("duty_factor", 1.0))),
		GameState.DEBT_CEILING + GameState.title_loan_bonus(),
	]
	if nxt.is_empty():
		main._slip_note(rank_slip, duty_line + "。")
	else:
		var need: int = maxi(0, int(nxt.get("min_fame", 0)) - GameState.fame)
		main._slip_note(rank_slip, "再记 %d 名声可题「%s」。%s。" % [
			need, str(nxt.get("name", "")), duty_line,
		])

	var lv: int = Economy.investment_level(port_id)
	var cost: int = Economy.invest_cost(port_id)
	var inv: VBoxContainer = main._slip_body()
	var inv_aside := "尚未修埠"
	if lv > 0:
		inv_aside = "已修至 %d 等" % lv
	main._slip_title(inv, "修埠", inv_aside)
	if cost <= 0:
		main._slip_note(inv, "本港埠头已修至 %d 等。产货更廉，紧缺易售，市面更宽。" % lv)
	elif lv <= 0:
		main._slip_note(inv, "修埠则埠头加深。本地产货更廉，紧缺货易售。")
	else:
		main._slip_note(inv, "再修一等。埠头加深，产货更廉，紧缺易售，市面更宽。")
	if cost > 0:
		var chip: Button = main._slip_chip(main._slip_row(inv), "投钱　%d" % cost, main._on_invest_port.bind(port_id), true)
		chip.tooltip_text = "向本港投钱修埠"


static func on_invest_port(main: Control, port_id: String) -> void:
	var res: Dictionary = Economy.invest(port_id)
	main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


static func attention_desc() -> String:
	var a := GameState.pu_attention
	if a >= 70:
		return "暗桩已盯死，出港必查"
	elif a >= 50:
		return "起了疑心"
	elif a >= 25:
		return "偶有闲话传出"
	return "尚无人留意"
