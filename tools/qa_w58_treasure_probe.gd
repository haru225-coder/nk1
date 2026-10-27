extends SceneTree
## Lane treas1：宝物系统运行时探针——数据 / 买入 / 鉴定 / 献纳 / 发现附赠 / 存档回环。
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
	if gm == null or gs == null or sl == null or fleet == null:
		_fail("autoload 缺席")
		_report()
		return

	_expect(int(gm.treasures_total()) == 22, "宝物图录 22 件")
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
