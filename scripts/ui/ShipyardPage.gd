extends RefCounted
## 船屋页（ShipyardPage）：坞位一艘（升帆 / 升甲 / 添人 / 换坞）、补给（水粮 / 修船 / 补齐人手）、蕃商赊贷、坞外待售四张工席，
## 与各钮的回调（换坞 / 修船 / 补齐 / 赊 / 还 / 购入 / 添人 / 升级 / 水粮），船屋成功题签过场，外加酒馆「雇入」「辞退」钮的两支回调。
## Lane main10 从 Main.gd 原样搬出（第十刀，_yard_port_name … _on_buy_supplies，15 支）。
## Main 留同名同签名的一行转发（_yard_port_name / _yard_success_transition / _setup_shipyard / _yard_offer / _on_berth_switch /
## _on_repair_hull / _on_hire_to_min / _on_borrow / _on_repay / _on_buy_ship / _on_dismiss_crew / _on_hire_candidate / _on_hire_crew /
## _on_upgrade / _on_buy_supplies；五支协程转发带 await），调用点、信号目标都不动：_setup_dynamic_scene 仍调 Main._setup_shipyard；
## 船屋各钮仍 connect 到 Main 的同名方法；TavernPage 的「雇入」「辞退」仍经 main. 接 Main._on_hire_candidate / _on_dismiss_crew。
## 留在 Main 的：连点闸 _upgrade_busy（qa_yard_transition_probe 直读）、_fit_rank / _sail_fit_phrase / _armor_fit_phrase（smoke 直调、
## LedgerPage 也用）、play_transition、_UI_TRANSITION、工席小件、离开钮，经 main 取；这里不存状态。
## 门禁 check_symbols 经 main_splits.txt 把这里的函数体拼回 Main 再做源码断言（main. 前缀去掉即搬走前的原文）；
## verify_economy 的船屋回调 / 补齐人手几条直接切这里（去 main. 前缀）。


## 船屋页港名（题签用）。scene_id 形如 quanzhou_shipyard。
static func yard_port_name(main: Control) -> String:
	var pid: String = main.current_scene_id.trim_suffix("_shipyard")
	if pid == "" or pid == main.current_scene_id:
		pid = str(GameState.last_port)
	return GameManager.get_port_name(pid)


## 船屋成功题签：港名・事由 + 历法日期；朱印见 UiTransition.drydock_seal。失败路径不走这里。
static func yard_success_transition(main: Control, act: String) -> void:
	await main.play_transition(
		main._UI_TRANSITION.drydock_title(main._yard_port_name(), act),
		Calendar.get_date_string(),
		main.load_scene.bind(main.current_scene_id),
		main._UI_TRANSITION.drydock_seal(act)
	)


static func setup_shipyard(main: Control, port_id: String) -> void:
	main.scene_title.text = "%s・船屋" % GameManager.get_port_name(port_id)
	main.body_text.text = "坞上只搁一艘。帆和甲对着这一艘。水粮与赊贷仍在码头。"
	var on := DrydockBerth.berth_index(Fleet.ships.size(), GameState.berth_index)
	if GameState.berth_index != on:
		GameState.berth_index = on
	main._begin_benches()

	# 坞位：一张工席，帆、甲、添人只对着坞上这一艘（云端 5588 坞位一艘，嵌进 c8fb/7f92 的工席壳）
	if Fleet.ships.is_empty():
		var empty: VBoxContainer = main._slip_body()
		main._slip_title(empty, "坞位", "眼下没有船")
	else:
		var hull: Dictionary = Fleet.ships[on]
		var sname := str(hull.get("name", "船"))
		var slv := Fleet.sail_level(on)
		var alv := Fleet.armor_level(on)
		var berth: VBoxContainer = main._slip_body()
		main._slip_title(berth, "坞位　%s" % sname, "帆　%s　甲　%s" % [main._fit_rank(slv), main._fit_rank(alv)])
		main._slip_note(berth, "水手 %d / %d　耐久 %d / %d　载 %d 料" % [
			Fleet.ship_crew(on),
			Fleet.ship_crew_max(on),
			int(hull.get("durability", 0)),
			int(hull.get("max_durability", 0)),
			int(Fleet.ship_capacity(on)),
		], UiTheme.TEXT)
		var fit_row: HFlowContainer = main._slip_row(berth)
		if Fleet.is_sail_max(on):
			main._slip_note(berth, "帆已是三等。")
		else:
			var scost: int = Fleet.upgrade_cost(on, "sail")
			var sail_chip: Button = main._slip_chip(fit_row, "升帆　%d" % scost, main._on_upgrade.bind(on, "sail", scost))
			var sail_phrase: String = main._sail_fit_phrase(slv)
			sail_chip.tooltip_text = sail_phrase
			main._slip_note(berth, sail_phrase)
		if Fleet.is_armor_max(on):
			main._slip_note(berth, "甲已是三等。")
		else:
			var acost: int = Fleet.upgrade_cost(on, "armor")
			var armor_chip: Button = main._slip_chip(fit_row, "升甲　%d" % acost, main._on_upgrade.bind(on, "armor", acost))
			var armor_phrase: String = main._armor_fit_phrase(alv)
			armor_chip.tooltip_text = armor_phrase
			main._slip_note(berth, armor_phrase)
		var room: int = Fleet.ship_crew_room(on)
		if room > 0:
			var hire_n: int = mini(10, room)
			var hire_cost := hire_n * 20
			var hire_chip: Button = main._slip_chip(
				fit_row,
				"%s　添 %d 人　%d" % [sname, hire_n, hire_cost],
				main._on_hire_crew.bind(on, hire_n, hire_cost)
			)
			hire_chip.tooltip_text = "码头短雇的水手，只上坞上这一艘。现有 %d，尚可添 %d。" % [Fleet.ship_crew(on), room]
		var fleet_full := true
		for j in Fleet.ships.size():
			if Fleet.ship_crew_room(j) > 0:
				fleet_full = false
				break
		if fleet_full:
			main._slip_note(berth, "各船人手已满。")

		var others := DrydockBerth.other_hulls(Fleet.ships.size(), on)
		if others.size() > 0:
			var swap_row: HFlowContainer = main._slip_row(berth)
			for idx in others:
				var other: Dictionary = Fleet.ships[idx]
				main._slip_chip(swap_row, "换上　%s" % str(other.get("name", "船")), main._on_berth_switch.bind(int(idx)))

	var grain_price := Economy.buy_price(port_id, "grain") if Economy.is_traded(port_id, "grain") else 12
	var water_price := 1
	var supply: VBoxContainer = main._slip_body()
	main._slip_title(supply, "补给", "水 %d　粮 %d　每日耗 %d" % [
		water_price, grain_price, Fleet.daily_supply_use(),
	])
	var supply_row: HFlowContainer = main._slip_row(supply)
	for n in [30, 100]:
		var packs := int(n)
		main._slip_chip(
			supply_row,
			"水粮各 %d　付 %d" % [packs, packs * (water_price + grain_price)],
			main._on_buy_supplies.bind(packs, water_price, grain_price)
		)
	var rc := Fleet.repair_cost()
	if rc > 0:
		main._slip_chip(supply_row, "修船　%d" % rc, main._on_repair_hull.bind(rc))
	var below_min: int = Fleet.crew_to_min_needed()
	if below_min > 0:
		var top_cost := below_min * 20
		var top_chip: Button = main._slip_chip(
			supply_row,
			"补齐 %d 人　%d" % [below_min, top_cost],
			main._on_hire_to_min.bind(top_cost)
		)
		top_chip.tooltip_text = "各船缺到最低人手的，码头一并雇齐。"

	var loan: VBoxContainer = main._slip_body()
	main._slip_title(loan, "蕃商赊贷", "月息每百 %d　上限 %d" % [
		int(GameState.DEBT_MONTHLY_RATE * 100),
		GameState.DEBT_CEILING + GameState.title_loan_bonus(),
	])
	if GameState.debt > 0:
		main._slip_note(loan, "现欠 %d，每月生息 %d。" % [
			GameState.debt, int(ceil(GameState.debt * GameState.DEBT_MONTHLY_RATE)),
		], UiTheme.HONEY)
	var loan_row: HFlowContainer = main._slip_row(loan)
	var borrow_cap := GameState.borrow_limit()
	for amt in [500, 2000]:
		if amt > borrow_cap:
			continue
		var borrowed := int(amt)
		main._slip_chip(loan_row, "赊 %d" % borrowed, main._on_borrow.bind(borrowed))
	if GameState.debt > 0 and GameState.money > 0:
		var pay: int = mini(GameState.debt, GameState.money)
		main._slip_chip(loan_row, "还 %d" % pay, main._on_repay.bind(pay), true)
	# 坞外待售：本章够到的船全部排在坞外，一艘一个购入小钮
	var reached := PackedStringArray()
	for mark in ["ch1", "ch2", "ch3", "ch4"]:
		if GameState.is_chapter_reached(mark):
			reached.append(mark)
	var catalog: Array = GameManager.ships_data.get("ships", [])
	var for_sale := DrydockBerth.sale_ids(catalog, reached)
	if for_sale.size() > 0:
		var sale: VBoxContainer = main._slip_body()
		main._slip_title(sale, "坞外待售", "新买的船泊在坞外，不自动占坞")
		var sale_row: HFlowContainer = main._slip_row(sale)
		for sid in for_sale:
			var offer: Dictionary = main._yard_offer(catalog, sid)
			if offer.is_empty():
				continue
			var price: int = int(offer.get("price", 0))
			var tid := str(offer.get("id", ""))
			var buy: Button = main._slip_chip(sale_row, "%s　购入　%d" % [str(offer.get("name", "船")), price], main._on_buy_ship.bind(tid, price), true)
			buy.tooltip_text = "载 %d 料　水手 %d 至 %d　耐久 %d" % [
				int(offer.get("capacity", 0)), int(offer.get("crew_min", 0)),
				int(offer.get("crew_max", 0)), int(offer.get("durability", 0)),
			]
			var hist := str(offer.get("historical_note", ""))
			if hist != "":
				buy.tooltip_text += "\n" + hist

	main._end_benches()
	main._add_leave_button(port_id)
	main.choices_label.visible = false


static func yard_offer(catalog: Array, sid: String) -> Dictionary:
	for raw_ship in catalog:
		if typeof(raw_ship) != TYPE_DICTIONARY:
			continue
		var ship_row: Dictionary = raw_ship
		if str(ship_row.get("id", "")) == sid:
			return ship_row
	return {}


static func on_berth_switch(main: Control, ship_index: int) -> void:
	var on := DrydockBerth.berth_index(Fleet.ships.size(), ship_index)
	if on == GameState.berth_index:
		return
	GameState.berth_index = on
	var hull: Dictionary = Fleet.ships[on]
	main.log_msg("把「%s」拖上坞位。帆和甲对着这一艘。" % str(hull.get("name", "船")))
	await main._yard_success_transition("换坞")


static func on_repair_hull(main: Control, cost: int) -> void:
	# 过场未落前旧页的修船钮一律不理（墨幕不吞 ui_accept 动作）：一次修船只扣一次钱
	if main._upgrade_busy:
		return
	if GameState.spend_money(cost):
		main._upgrade_busy = true
		Fleet.repair_all()
		main.log_msg("船匠敲了一日。船体按簿修好。")
		await main._yard_success_transition("修船")
		main._upgrade_busy = false
	else:
		main.log_msg("【钱不够】船匠摇摇头，把凿子收了。")
		main.load_scene(main.current_scene_id)


static func on_hire_to_min(main: Control, cost: int) -> void:
	if GameState.spend_money(cost):
		var got: int = Fleet.hire_to_min()
		main.log_msg("码头上雇齐 %d 人，各船补到最低人手。" % got)
	else:
		main.log_msg("【钱不够】码头上没人肯赊着上船。")
	main.load_scene(main.current_scene_id)


static func on_borrow(main: Control, amt: int) -> void:
	if GameState.borrow(amt):
		main.log_msg("蕃商掂了掂你的船和名声，点了头。赊得 %d 钱，月息每百 %d。" % [
			amt, int(GameState.DEBT_MONTHLY_RATE * 100),
		])
	main.load_scene(main.current_scene_id)


static func on_repay(main: Control, pay: int) -> void:
	var paid: int = GameState.repay(pay)
	main.log_msg("还了 %d 钱，尚欠 %d。" % [paid, GameState.debt])
	main.load_scene(main.current_scene_id)


static func on_buy_ship(main: Control, type_id: String, price: int) -> void:
	# 同修船：过场未落前旧页的购入钮不再买第二条
	if main._upgrade_busy:
		return
	if GameState.spend_money(price):
		main._upgrade_busy = true
		Fleet.add_ship(type_id)
		main.log_msg("买下一条%s，泊在坞外。水手未齐。" % Fleet.ship_def(type_id).get("name", "船"))
		await main._yard_success_transition("购入")
		main._upgrade_busy = false
	else:
		main.log_msg("【钱不够】船行掌柜未点头。")
		main.load_scene(main.current_scene_id)


static func on_dismiss_crew(main: Control, role_id: String) -> void:
	var res: Dictionary = Crew.dismiss(role_id)
	if res.get("ok", false):
		main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


static func on_hire_candidate(main: Control, crew_id: String) -> void:
	var res: Dictionary = Crew.hire(crew_id)
	main.log_msg(str(res.get("msg", "")))
	main.load_scene(main.current_scene_id)


static func on_hire_crew(main: Control, ship_index: int, hire_n: int, hire_cost: int) -> void:
	if GameState.spend_money(hire_cost):
		var got: int = Fleet.hire_crew(hire_n, ship_index)
		var s: Dictionary = Fleet.ships[ship_index]
		main.log_msg("码头上雇了 %d 人，上了「%s」。" % [got, s.get("name", "")])
	else:
		main.log_msg("【钱不够】码头上没人肯赊着上船。")
	main.load_scene(main.current_scene_id)


static func on_upgrade(main: Control, ship_index: int, kind: String, shown_cost: int) -> void:
	# 过场未落前的连点、旧页按钮一律不理：一次升级只扣一次钱
	if main._upgrade_busy:
		return
	if ship_index < 0 or ship_index >= Fleet.ships.size():
		main.load_scene(main.current_scene_id)
		return
	var is_armor := kind == "armor"
	var level_key := "armor_level" if is_armor else "sail_level"
	var prev_lv: int = Fleet.armor_level(ship_index) if is_armor else Fleet.sail_level(ship_index)
	if (Fleet.is_armor_max(ship_index) if is_armor else Fleet.is_sail_max(ship_index)):
		main.log_msg("【满级】甲已无可再加。" if is_armor else "【满级】帆已无可再换。")
		main.load_scene(main.current_scene_id)
		return
	# 按眼下等级重算，不信按钮上 bind 的旧价
	var cost: int = Fleet.upgrade_cost(ship_index, kind)
	if cost <= 0 or GameState.money < cost:
		main.log_msg("【钱不够】船匠掂了掂银袋，摇了摇头。")
		main.load_scene(main.current_scene_id)
		return
	var ok: bool = Fleet.upgrade_armor(ship_index) if is_armor else Fleet.upgrade_sail(ship_index)
	if not ok:
		main.log_msg("【满级】甲已无可再加。" if is_armor else "【满级】帆已无可再换。")
		main.load_scene(main.current_scene_id)
		return
	if not GameState.spend_money(cost):
		# 升级已落而钱没扣成：还原到原等级，不白升
		Fleet.ships[ship_index][level_key] = prev_lv
		main.log_msg("【钱不够】船匠掂了掂银袋，摇了摇头。")
		main.load_scene(main.current_scene_id)
		return
	main._upgrade_busy = true
	var s: Dictionary = Fleet.ships[ship_index]
	if cost != shown_cost:
		main.log_msg("船匠照眼下的等重开了价，%d 钱。" % cost)
	var act := ""
	if is_armor:
		main.log_msg("「%s」加厚了船壳，甲升至%s。" % [s.get("name", "船"), main._fit_rank(Fleet.armor_level(ship_index))])
		act = "升甲"
	else:
		main.log_msg("「%s」换了新帆，帆升至%s。" % [s.get("name", "船"), main._fit_rank(Fleet.sail_level(ship_index))])
		act = "升帆"
	await main._yard_success_transition(act)
	main._upgrade_busy = false


static func on_buy_supplies(main: Control, n: int, wp: int, gp: int) -> void:
	var cost := n * (wp + gp)
	var need_space := float(n * 2) * Fleet.SUPPLY_BULK
	if Fleet.free_capacity() < need_space:
		main.log_msg("【舱满】水粮也要占舱位，还差 %d 料。" % int(ceil(need_space - Fleet.free_capacity())))
		return
	if not GameState.spend_money(cost):
		main.log_msg("【钱不够】买不起这许多水粮。")
		return
	Fleet.water += n
	Fleet.food += n
	main.log_msg("补入水 %d 份、粮 %d 份，付 %d 钱。现可支撑 %d 日。" % [n, n, cost, Fleet.supply_days()])
	main.load_scene(main.current_scene_id)
