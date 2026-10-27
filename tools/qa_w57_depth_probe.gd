extends SceneTree
## Lane bal2：按货深浅（depth_mul）探针——每货市场深度、买卖推演、按货冲击、存档结构。
## 用法：godot --headless --path . -s res://tools/qa_w57_depth_probe.gd
## 输出末行 DEPTH_PROBE fails=N；N>0 时 exit 1。

const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var eco: Node
var cal: Node
var gs: Node
var gm: Node
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
	eco = root.get_node_or_null("Economy")
	cal = root.get_node_or_null("Calendar")
	gs = root.get_node_or_null("GameState")
	gm = root.get_node_or_null("GameManager")
	if eco == null or cal == null or gs == null or gm == null:
		push_error("autoload missing")
		quit(1)
		return
	eco.initialize()

	var saved_month: int = cal.month
	var saved_year: int = cal.year
	var saved_day: int = cal.day
	var saved_rates: Dictionary = eco.rates.duplicate(true)

	# 1. _depth 带货参
	_expect(eco.has_method("_depth"), "Economy._depth 存在")
	var base_depth: float = (
		float(eco._port_def("quanzhou").get("depth", 100))
		* (1.0 + float(eco._invest_cfg().get("depth_per_level", 0.12)) * float(eco.investment_level("quanzhou")))
	)
	var d_gold: float = eco._depth("quanzhou", "placer_gold")
	var d_grain: float = eco._depth("quanzhou", "grain")
	_expect(is_equal_approx(d_gold, base_depth * 0.2), "砂金深度 %.1f = 港深 %.1f × 0.2" % [d_gold, base_depth])
	_expect(is_equal_approx(d_grain, base_depth * 4.0), "米粮深度 %.1f = 港深 %.1f × 4.0" % [d_grain, base_depth])
	_expect(d_gold < d_grain, "砂金深度 %.1f < 米粮深度 %.1f" % [d_gold, d_grain])
	_expect(is_equal_approx(eco._depth("quanzhou", ""), base_depth), "无货参退化为港深 %.1f" % base_depth)
	_expect(eco.blockade_grain_cap("xinghua") == int(eco._depth("xinghua", "grain")), "围城收粮上限用米粮深度")

	# 2. goods.json 全部 29 货都有 depth_mul
	var n_mul := 0
	var bad_mul := []
	for g in gm.goods_data.get("goods", []):
		if g.has("depth_mul") and float(g.get("depth_mul", 0.0)) > 0.0:
			n_mul += 1
		else:
			bad_mul.append(str(g.get("id", "?")))
	_expect(n_mul == 29 and bad_mul.is_empty(), "29 货皆有正 depth_mul（缺：%s）" % (", ".join(bad_mul) if bad_mul else "无"))

	# 3. 卖出推演与按货深度一致
	eco.rates = saved_rates.duplicate(true)
	eco.rates["quanzhou"]["placer_gold"] = 1.0
	var manual_sell: int = 0
	var r: float = 1.0
	var depth: float = eco._depth("quanzhou", "placer_gold")
	for i in range(5):
		manual_sell += eco.price_at_rate("quanzhou", "placer_gold", r, false)
		r = clampf(r - 1.0 / depth, eco.RATE_MIN, eco.RATE_MAX)
	var got_sell: int = eco.estimate_sell_revenue("quanzhou", "placer_gold", 5)
	_expect(got_sell == manual_sell, "卖 5 件砂金实得 %d = 按货深度推演 %d" % [got_sell, manual_sell])

	# 4. 买入推演 / 买满件数同走按货深度
	eco.rates = saved_rates.duplicate(true)
	eco.rates["quanzhou"]["placer_gold"] = 1.0
	var manual_buy: int = 0
	r = 1.0
	for i in range(5):
		manual_buy += eco.price_at_rate("quanzhou", "placer_gold", r, true)
		r = clampf(r + 1.0 / depth, eco.RATE_MIN, eco.RATE_MAX)
	var got_buy: int = eco.estimate_buy_cost("quanzhou", "placer_gold", 5)
	_expect(got_buy == manual_buy, "买 5 件砂金实付 %d = 按货深度推演 %d" % [got_buy, manual_buy])
	var five_cost: int = eco.estimate_buy_cost("quanzhou", "placer_gold", 5)
	_expect(eco.affordable_qty("quanzhou", "placer_gold", five_cost, 10) == 5, "现银 %d 按逐件抬价恰好买 5 件" % five_cost)
	_expect(eco.affordable_qty("quanzhou", "placer_gold", five_cost, 3) == 3, "舱位 cap 3 时买满 3 件")

	# 5. apply_buy/sell_impact 也带货参：同样 1 件，砂金比米粮动得大
	eco.rates = saved_rates.duplicate(true)
	eco.rates["quanzhou"]["placer_gold"] = 1.0
	eco.rates["quanzhou"]["grain"] = 1.0
	eco.apply_sell_impact("quanzhou", "placer_gold", 1)
	eco.apply_sell_impact("quanzhou", "grain", 1)
	var gold_down: float = float(eco.rates["quanzhou"]["placer_gold"])
	var grain_down: float = float(eco.rates["quanzhou"]["grain"])
	_expect(gold_down < grain_down, "卖 1 件砂金压到 %.4f < 卖 1 件米粮压到 %.4f" % [gold_down, grain_down])
	eco.rates = saved_rates.duplicate(true)
	eco.rates["quanzhou"]["placer_gold"] = 1.0
	eco.rates["quanzhou"]["grain"] = 1.0
	eco.apply_buy_impact("quanzhou", "placer_gold", 1)
	eco.apply_buy_impact("quanzhou", "grain", 1)
	var gold_up: float = float(eco.rates["quanzhou"]["placer_gold"])
	var grain_up: float = float(eco.rates["quanzhou"]["grain"])
	_expect(gold_up > grain_up, "买 1 件砂金抬到 %.4f > 买 1 件米粮抬到 %.4f" % [gold_up, grain_up])

	# 6. 存档结构不变：利率表逐键逐值读回
	eco.rates = saved_rates.duplicate(true)
	var d: Dictionary = eco.to_dict()
	_expect(d.has("rates") and d.has("tariff") and d.has("broker") and d.has("investments"), "to_dict 四键齐全")
	_expect(d.keys().size() == 4, "to_dict 仅四键（无深度字段）")
	var before: Dictionary = d.duplicate(true)
	eco.from_dict(d)
	var after: Dictionary = eco.to_dict()
	_expect(after.keys() == before.keys(), "from_dict 后键集不变")
	_expect(_rates_equal(after.get("rates", {}), before.get("rates", {})), "from_dict 后行情表逐键逐值不变")

	cal.month = saved_month
	cal.year = saved_year
	cal.day = saved_day
	_report()


func _rates_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for pid in a:
		if not b.has(pid) or typeof(a[pid]) != TYPE_DICTIONARY:
			return false
		var ra: Dictionary = a[pid]
		var rb: Dictionary = b[pid]
		if ra.size() != rb.size():
			return false
		for gid in ra:
			if not rb.has(gid) or not is_equal_approx(float(ra[gid]), float(rb[gid])):
				return false
	return true


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
	print("DEPTH_PROBE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
