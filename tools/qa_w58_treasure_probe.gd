extends SceneTree
## Lane treas1/treas2：宝物系统运行时探针——数据 / 传闻线索 / 职事加成 / 买入 / 鉴定 / 献纳 / 发现附赠 / 存档回环。
## 用法：godot --headless --path . -s res://tools/qa_w58_treasure_probe.gd
## 输出末行 TREASURE_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var fails := 0
var cases := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_fail("主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	await process_frame
	var gm := root.get_node_or_null("GameManager")
	var gs := root.get_node_or_null("GameState")
	var sl := root.get_node_or_null("SaveLoad")
	var fleet := root.get_node_or_null("Fleet")
	var crew := root.get_node_or_null("Crew")
	if gm == null or gs == null or sl == null or fleet == null or crew == null:
		_fail("autoload 缺席")
		_report()
		return

	_expect(int(gm.treasures_total()) == 27, "宝物图录 27 件")
	var rumor_total := 0
	for t in gm.treasures_data.get("treasures", []):
		if typeof(t) == TYPE_DICTIONARY and not gm.treasure_rumor_source(str(t.get("id", ""))).is_empty():
			rumor_total += 1
	_expect(rumor_total == 5, "传闻宝物 5 件")
	_expect(gm.treasures_with_rumor_at("guangzhou").size() == 2, "广州酒馆两桩传闻")
	_expect(gm.treasures_with_rumor_at("quanzhou").size() == 1, "泉州酒馆一桩传闻")
	_expect(not gm.get_treasure_by_id("ru_ware_washer").is_empty(), "按 id 取汝窑")
	_expect(gm.get_treasure_by_id("no_such_treasure").is_empty(), "查无宝物回空")
	var quanzhou: Array = gm.treasures_at_shop("quanzhou")
	var has_ru := false
	for t in quanzhou:
		if str(t.get("id", "")) == "ru_ware_washer":
			has_ru = true
	_expect(has_ru, "泉州唐物铺有汝窑")
	var jiu: Array = gm.treasures_for_discovery("jiuri_wind_stele")
	_expect(jiu.size() == 1 and str(jiu[0].get("id", "")) == "longxian_incense", "九日山发现附赠龙涎香")

	_rumor_and_duty(gs, gm, sl, crew)
	gs.money = 9000
	var hold_before := float(fleet.used_capacity())
	var money_before: int = gs.money
	var buy: Dictionary = gs.buy_treasure("ru_ware_washer", "quanzhou")
	_expect(buy.get("ok", false), "买入汝窑")
	_expect(gs.money == money_before - 2600, "扣标价 2600")
	_expect("ru_ware_washer" in gs.treasures_owned, "汝窑入手")
	_expect(not gs.treasure_appraised("ru_ware_washer"), "入手时未鉴定")
	_expect(is_equal_approx(float(fleet.used_capacity()), hold_before), "宝物不占舱位")
	var again: Dictionary = gs.buy_treasure("ru_ware_washer", "quanzhou")
	_expect(not again.get("ok", true), "同一件不能买第二次")

	money_before = gs.money
	var appraise: Dictionary = gs.appraise_treasure("ru_ware_washer")
	_expect(appraise.get("ok", false), "鉴定汝窑")
	_expect(gs.money == money_before - 260, "鉴定费 260")
	_expect(gs.treasure_appraised("ru_ware_washer"), "鉴定入册")
	_expect(gs.treasure_ready("ru_ware_washer"), "鉴定后可献纳")

	var fame_before: int = gs.fame
	var donate: Dictionary = gs.donate_treasure("ru_ware_washer")
	_expect(donate.get("ok", false), "献纳汝窑")
	_expect(gs.fame == fame_before + 60, "献纳名声加 60")
	_expect(not ("ru_ware_washer" in gs.treasures_owned), "献纳后离手")
	_expect("ru_ware_washer" in gs.treasures_donated, "献纳入册")
	_expect(not gs.donate_treasure("ru_ware_washer").get("ok", true), "同一件不能献第二次")

	gs.money = 9000
	_expect(gs.buy_treasure("ding_ware_bowl", "fuzhou").get("ok", false), "买入定窑")
	_expect(not gs.donate_treasure("ding_ware_bowl").get("ok", true), "非名声宝物不能献纳")

	var found: bool = gs.record_discovery("jiuri_wind_stele")
	_expect(found, "勘见九日山")
	var report: Dictionary = gs.report_discovery("jiuri_wind_stele")
	_expect(not report.is_empty(), "呈报九日山")
	_expect(str(report.get("treasure", "")) == "龙涎香", "呈报回执点名龙涎香")
	_expect("longxian_incense" in gs.treasures_owned, "发现附赠入手")

	var snap: Dictionary = gs.to_dict()
	_expect(snap.has("treasures_owned") and snap.has("treasures_appraised") and snap.has("treasures_donated"), "存档三录齐")
	gs.from_dict(snap)
	_expect("longxian_incense" in gs.treasures_owned, "存档回环：在手")
	_expect("ru_ware_washer" in gs.treasures_donated, "存档回环：已献")
	gs.from_dict({})
	_expect(gs.treasures_owned.is_empty() and gs.treasures_appraised.is_empty() and gs.treasures_donated.is_empty(), "旧档缺三录回空")

	var hard: Dictionary = sl._harden_state({
		"treasures_owned": ["ru_ware_washer", "ru_ware_washer", "longxian_incense"],
		"treasures_donated": ["ru_ware_washer"],
		"treasures_appraised": ["ru_ware_washer", "longxian_incense"],
	})
	_expect(hard.get("treasures_owned", []) == ["longxian_incense"], "清洗：已献胜过在手")
	_expect(hard.get("treasures_donated", []) == ["ru_ware_washer"], "清洗：已献去重")
	_expect(hard.get("treasures_appraised", []) == ["longxian_incense"], "清洗：鉴定只在手")

	_report()


func _rumor_and_duty(gs: Node, gm: Node, sl: Node, crew: Node) -> void:
	gs.from_dict({})
	crew.from_dict({})
	var src: Dictionary = gm.treasure_rumor_source("sunk_cargo_porcelain")
	_expect(str(src.get("port", "")) == "guangzhou", "传闻来自广州")
	_expect((src.get("near_ports", []) as Array).has("champa"), "传闻近港含占城")
	_expect(not gs.note_treasure_rumor("sunk_cargo_porcelain", "quanzhou").get("ok", true), "别港问不出")
	var heard: Dictionary = gs.note_treasure_rumor("sunk_cargo_porcelain", "guangzhou")
	_expect(heard.get("ok", false) and "sunk_cargo_porcelain" in gs.treasure_leads, "广州听来沉船瓷器箱")
	_expect(str(heard.get("hint", "")) != "", "线索带回方位")
	_expect(not gs.note_treasure_rumor("sunk_cargo_porcelain", "guangzhou").get("ok", true), "同一桩只记一次")
	_expect(not gs.note_treasure_rumor("ru_ware_washer", "quanzhou").get("ok", true), "非传闻物不能记线索")

	var snap: Dictionary = gs.to_dict()
	gs.from_dict(snap)
	_expect("sunk_cargo_porcelain" in gs.treasure_leads, "存档回环：线索")
	var hard: Dictionary = sl._harden_state({
		"treasures_owned": ["sunk_cargo_porcelain"],
		"treasure_leads": ["houzhu_sunk_incense", "houzhu_sunk_incense", "sunk_cargo_porcelain", "not_real"],
	})
	_expect(hard.get("treasure_leads", []) == ["houzhu_sunk_incense"], "清洗：线索去重、去已收、去无名")
	var found: bool = gs.find_treasure_lead("sunk_cargo_porcelain")
	_expect(found and gs.has_treasure("sunk_cargo_porcelain"), "循线索寻得宝物")
	_expect(not ("sunk_cargo_porcelain" in gs.treasure_leads), "寻得后线索销掉")

	gs.from_dict({})
	crew.from_dict({})
	crew.hired = {
		"huozhang": "wu_zhen",
		"duogong": "lin_awu",
		"zashi": "zhou_suanchou",
		"tongshi": "kondo_saburo",
	}
	for tid in ["water_compass", "needle_route_scroll", "song_edition_wenxuan", "suhe_oil"]:
		gs.add_treasure(str(tid))
	_expect(gs.treasure_duty_bonus("huozhang") == 1 and gs.treasure_duty_bonus("duogong") == 1
		and gs.treasure_duty_bonus("zashi") == 1 and gs.treasure_duty_bonus("tongshi") == 1, "四职事宝物在船生效")
	_expect(gs.owned_duty_treasures().size() == 4, "船籍簿列四件职事宝物")
	_expect(is_equal_approx(crew.speed_factor(), 1.08), "火长速 1.06 → 1.08")
	_expect(is_equal_approx(crew.wind_floor(), 0.465), "舵工逆风下限 0.45 → 0.465")
	_expect(is_equal_approx(crew.trade_cost_factor(), 0.86), "杂事抽佣 0.88 → 0.86")
	_expect(is_equal_approx(crew.interpreter_edge("hakata"), 0.23), "通事异国价差 0.21 → 0.23")
	_expect(crew.interpreter_edge("quanzhou") == 0.0, "通事只在异国港生效")

	crew.hired.erase("huozhang")
	_expect(gs.treasure_duty_bonus("huozhang") == 0 and is_equal_approx(crew.speed_factor(), 1.0), "火长下船，宝物不生效")
	crew.hired["huozhang"] = "wu_zhen"
	gs.treasures_owned.erase("water_compass")
	gs.treasures_donated.append("water_compass")
	_expect(gs.treasure_duty_bonus("huozhang") == 0 and is_equal_approx(crew.speed_factor(), 1.06), "已献宝物不生效")
	gs.from_dict({})
	crew.from_dict({})


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ ", what)
	else:
		fails += 1
		print("  ✗ ", what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 12:
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		if v[0]:
			print("  ✓ " + str(v[1]))
		else:
			_fail(str(v[1]))
	print("TREASURE_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
