extends SceneTree
## Lane w53-p5-econ：headless 探针——军需涨价（战斗系统方案 §八）：牙行价按港口战况 × 货的战时货类
## （goods.json war_class / war_price）乘倍数，开关 CombatSwitches「war_prices」。
##   一、开关关态逐字回旧：六个月份（平年、耽罗降元、泉州对峙、兴化被围、兴化再陷、广州再降）× 全部（港, 货）
##      × 五档行情，Economy.price_at_rate 买卖两价与本探针抄下的改前原式逐格相等，buy_price / sell_price、
##      逐件推演（estimate_sell_revenue）也逐字回旧，war_price_factor 恒 1、短注恒空；开关开时平年也逐格不变。
##   二、被围港米价倍数：兴化围城月 war_price_factor(米) = 1.8、军械（日本刀）= 1.5；闯封锁按
##      「平年米价 × 倍数」算得约 1.8 倍；牙行价里米不叠两遍——行情已撑在 SIEGE_GRAIN_TARGET，开关开关同价，
##      约平年 1.8 倍而不是 3.24 倍；军械牙行价开 / 关之比 = 1.5。
##   三、降元港方向：明州降元后奢侈货（参、貂、螺钿、青白瓷）倍数 > 1、价比关态贵；米粮翻牌头两个月不打折、第三个月起
##      倍数 < 1、价比关态贱（泉州降元当月、次月光杆米价仍显得出抽解加倍与站蒲家八折）；普通货（砂金）不动。
##   四、对峙港小幅涨：泉州对峙时米、铁器倍数在 (1, 1.3]，价比关态贵；奢侈货不涨。
##   五、牙行看得见：明州柜上参那张卡价格右边挂短注「已降元・贵二成」，悬停写「明州已降元，奢侈货比平年贵二成…」；
##      价格行原字照旧（「买 N　卖 M」= 现价）；关开关、或平年，不挂短注、卡面与原先同一结构。
##   六、价差地板：五个战况月、开关开，全部开门的（港, 货）买价 ≥ 卖价（倍数乘在共有因子上，站着不动印不出钱）。
## 用法：godot --headless --path . -s res://tools/qa_w53_p5_war_prices_probe.gd
## 输出末行 W53_P5_WAR_PRICES_PROBE cases=N fails=M；M>0 时 exit 1。

## 本进程 SCRIPT ERROR 即红：接共用件 tools/script_err_tally.gd，写法同 qa_w53_3_rumor_probe。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 抽查的月份：[年, 月, 说明]
const MONTHS := [
	[1255, 3, "平年"], [1273, 6, "耽罗降元"], [1276, 6, "泉州对峙・明州温州降元"],
	[1276, 11, "兴化广州被围・福州降元"], [1277, 12, "兴化再陷"], [1278, 4, "广州再降"],
]
const RATES := [0.4, 0.73, 1.0, 1.37, 2.2]

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var eco: Node
var crew: Node
var cases := 0
var fails := 0
var _tally: ScriptErrTally
var _reported := false


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


## _run 被脚本错半路掐断时 _report() 不会被调到——回到这里就地判红收尾，不留空转给外层 timeout
func _run_guarded() -> void:
	await _run()
	if not _reported:
		_expect(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("/root/GameState")
	gm = root.get_node("/root/GameManager")
	cal = root.get_node("/root/Calendar")
	eco = root.get_node("/root/Economy")
	crew = root.get_node("/root/Crew")
	eco.initialize()
	gs.money = 50000
	print("── 一、开关关态逐字回旧（六个月份 × 全部港货 × 五档行情）")
	_off_verbatim()
	print("── 二、被围港米价、军械倍数（兴化 1276-11）")
	_besieged()
	print("── 三、降元港奢侈贵、米粮贱（明州 1276-02）")
	_fallen()
	print("── 四、对峙港小幅涨（泉州 1276-06）")
	_contested()
	print("── 五、牙行卡价格旁的短注")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if _main.has_method("load_scene"):
		await _market_note()
	else:
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
	print("── 六、价差地板（开关开，五个战况月）")
	_spread_floor()
	CombatSwitches.reset()
	_report()


func _expect(ok: bool, what: String) -> void:
	cases += 1
	if ok:
		print("  ✓ " + what)
	else:
		fails += 1
		print("  ✗ " + what)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_expect(v[0], v[1])
	print("W53_P5_WAR_PRICES_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 日历拨到某月（战况是 Calendar 的纯函数），行情全部归 1.0
func _at(year: int, month: int) -> void:
	cal.from_dict({"year": year, "month": month, "day": 10})
	for pid in eco.rates.keys():
		for gid in eco.rates[pid].keys():
			eco.rates[pid][gid] = 1.0


func _ports() -> Array:
	var out: Array = []
	for p in gm.ports_data.get("ports", []):
		out.append(str(p.get("id", "")))
	return out


## 改前的 Economy.price_at_rate 原样抄一份（f443e6e8，本 lane 动手前）：开关关时逐格对账，回退 / 漏乘一处即红
func _old_price_at_rate(port_id: String, good_id: String, rate: float, is_buy: bool) -> int:
	var base: float = float(eco._good_def(good_id).get("base_value", 0))
	var role: String = eco.get_role(port_id, good_id)
	var mod: float = eco.ROLE_MOD.get(role, 1.0)
	var edge: float = crew.interpreter_edge(port_id)
	var v := base * mod * rate
	var ie: float = eco.invest_edge(port_id)
	if role == "origin":
		v *= (1.0 - ie)
	elif role == "consumer":
		v *= (1.0 + ie)
	var bare_buy: float = v * (1.0 + float(eco._base_tariff(port_id)))
	var bare_sell: float = v * (1.0 - float(eco.broker_fee))
	var cap: float = bare_buy / float(eco.PRICE_SPREAD_MIN)
	var sell_v := minf(v * (1.0 - float(eco._effective_broker())) * (1.0 + edge), cap)
	sell_v = maxf(sell_v, minf(bare_sell, cap))
	if not is_buy:
		return int(round(sell_v))
	var buy_v := maxf(v * (1.0 + float(eco._effective_tariff(port_id))) * (1.0 - edge), sell_v * float(eco.PRICE_SPREAD_MIN))
	return int(round(minf(buy_v, maxf(bare_buy, sell_v * float(eco.PRICE_SPREAD_MIN)))))


## 改前 estimate_sell_revenue 的逐件推演，单价走改前原式
func _old_sell_revenue(port_id: String, good_id: String, amount: int) -> int:
	var total := 0
	var depth: float = eco._depth(port_id)
	var r: float = eco.get_rate(port_id, good_id)
	for i in range(amount):
		if r == eco.RATE_MIN:
			return total + _old_price_at_rate(port_id, good_id, r, false) * (amount - i)
		total += _old_price_at_rate(port_id, good_id, r, false)
		r = clampf(r - 1.0 / depth, eco.RATE_MIN, eco.RATE_MAX)
	return total


## 某月、某开关态下，全部（港, 货）× 五档行情的买卖两价与改前原式不符的格数；附带 buy/sell_price 与现行情
func _diff_vs_old(year: int, month: int) -> Array:
	_at(year, month)
	var n := 0
	var bad := 0
	var ex := ""
	for pid in _ports():
		for raw_gid in eco.goods_at(pid):
			var gid := str(raw_gid)
			for r in RATES:
				for is_buy in [true, false]:
					n += 1
					var got: int = eco.price_at_rate(pid, gid, r, is_buy)
					var want := _old_price_at_rate(pid, gid, r, is_buy)
					if got != want:
						bad += 1
						if ex == "":
							ex = "%s/%s 行情 %.2f %s %d（原式 %d）" % [pid, gid, r, "买" if is_buy else "卖", got, want]
			if eco.buy_price(pid, gid) != _old_price_at_rate(pid, gid, 1.0, true) or eco.sell_price(pid, gid) != _old_price_at_rate(pid, gid, 1.0, false):
				bad += 1
				if ex == "":
					ex = "%s/%s buy_price/sell_price 与原式不符" % [pid, gid]
	return [n, bad, ex]


func _off_verbatim() -> void:
	CombatSwitches.set_on("war_prices", false)
	var total := 0
	var bad := 0
	var ex := ""
	var factor_bad := 0
	var note_bad := 0
	for m in MONTHS:
		var res := _diff_vs_old(int(m[0]), int(m[1]))
		total += int(res[0])
		bad += int(res[1])
		if ex == "" and str(res[2]) != "":
			ex = "%d-%02d %s" % [int(m[0]), int(m[1]), res[2]]
		for pid in _ports():
			for raw_gid in eco.goods_at(pid):
				if float(eco.war_price_factor(pid, str(raw_gid))) != 1.0:
					factor_bad += 1
				if str(eco.war_price_note(pid, str(raw_gid))) != "":
					note_bad += 1
	_expect(total > 0 and bad == 0, "开关关：%d 格买卖价与改前原式逐字相等（不符 %d%s）" % [total, bad, "；例 " + ex if ex != "" else ""])
	_expect(factor_bad == 0 and note_bad == 0, "开关关：六个月份 war_price_factor 恒 1.0、牙行短注恒空（不符 %d / %d）" % [factor_bad, note_bad])
	# 逐件推演（砸盘序列）也回旧：明州降元月卖 60 件参
	_at(1276, 2)
	var rev_off: int = eco.estimate_sell_revenue("mingzhou", "korean_ginseng", 60)
	var rev_old := _old_sell_revenue("mingzhou", "korean_ginseng", 60)
	_expect(rev_off == rev_old, "开关关：明州降元月卖 60 件高丽参逐件推演 %d = 改前 %d" % [rev_off, rev_old])
	CombatSwitches.set_on("war_prices", true)
	var res0 := _diff_vs_old(1255, 3)
	_expect(int(res0[1]) == 0, "开关开、平年（1255-03）：%d 格买卖价与改前逐字相等（不符 %d）——倍数只在战况月起作用" % [int(res0[0]), int(res0[1])])
	CombatSwitches.reset()


func _besieged() -> void:
	CombatSwitches.reset()
	_at(1276, 11)
	var st := str(eco.war_status("xinghua"))
	var fg: float = eco.war_price_factor("xinghua", "grain")
	var fa: float = eco.war_price_factor("xinghua", "japanese_sword")
	_expect(st == "besieged" and is_equal_approx(fg, 1.8) and is_equal_approx(fa, 1.5),
		"兴化 1276-11 %s：米 ×%.2f、军械（日本刀，%s）×%.2f" % [st, fg, eco.war_class("japanese_sword"), fa])
	# 闯封锁：平年米价（行情 1.0）× 倍数
	var peace_sell := _old_price_at_rate("xinghua", "grain", 1.0, false)
	var base_sell: int = eco.price_at_rate("xinghua", "grain", 1.0, false)
	var run_sell := float(base_sell) * fg
	_expect(base_sell == peace_sell and absf(run_sell / float(peace_sell) - 1.8) < 0.01,
		"闯封锁卖粮：平年米价 price_at_rate(兴化, 米, 1.0) = %d（=平年 %d）× %.2f = %.1f，约平年 1.8 倍" % [base_sell, peace_sell, fg, run_sell])
	# 牙行价里米不叠两遍：行情已撑在 SIEGE_GRAIN_TARGET
	eco.rates["xinghua"]["grain"] = eco.SIEGE_GRAIN_TARGET
	var on_sell: int = eco.sell_price("xinghua", "grain")
	var on_buy: int = eco.buy_price("xinghua", "grain")
	CombatSwitches.set_on("war_prices", false)
	var off_sell: int = eco.sell_price("xinghua", "grain")
	var off_buy: int = eco.buy_price("xinghua", "grain")
	CombatSwitches.reset()
	var twice := float(peace_sell) * fg * float(eco.SIEGE_GRAIN_TARGET)
	_expect(on_sell == off_sell and on_buy == off_buy and absf(float(on_sell) / float(peace_sell) - 1.8) < 0.15 and float(on_sell) < twice - 2.0,
		"围城米行情撑在 %.1f 时牙行价开 / 关同价（卖 %d/%d、买 %d/%d），约平年 %d 的 1.8 倍，不叠成 3.24 倍（%.1f）" % [
			eco.SIEGE_GRAIN_TARGET, on_sell, off_sell, on_buy, off_buy, peace_sell, twice])
	_expect(is_equal_approx(float(eco._war_price_mul("xinghua", "grain")), 1.0) and is_equal_approx(float(eco._war_price_mul("xinghua", "japanese_sword")), 1.5),
		"算价实乘：围城米 ×%.2f（围城溢价在行情里）、军械 ×%.2f" % [eco._war_price_mul("xinghua", "grain"), eco._war_price_mul("xinghua", "japanese_sword")])
	# 军械牙行价开 / 关之比
	var arm_on: int = eco.price_at_rate("xinghua", "japanese_sword", 1.0, false)
	var arm_off := _old_price_at_rate("xinghua", "japanese_sword", 1.0, false)
	_expect(absf(float(arm_on) / float(arm_off) - 1.5) < 0.01, "兴化围城日本刀卖价 %d / 关态 %d = %.3f（约 1.5）" % [arm_on, arm_off, float(arm_on) / float(arm_off)])
	_expect(not eco.is_market_open("xinghua"), "兴化围城牙行照旧闭门（倍数只给闯封锁、传闻用，不开门卖）")


func _fallen() -> void:
	CombatSwitches.reset()
	_at(1276, 2)
	var st := str(eco.war_status("mingzhou"))
	var lux_bad: Array = []
	var lux_n := 0
	for raw_gid in eco.goods_at("mingzhou"):
		var gid := str(raw_gid)
		if eco.war_class(gid) != "luxury":
			continue
		lux_n += 1
		var f: float = eco.war_price_factor("mingzhou", gid)
		var on_s: int = eco.sell_price("mingzhou", gid)
		var off_s := _old_price_at_rate("mingzhou", gid, 1.0, false)
		if not (f > 1.0 and on_s > off_s):
			lux_bad.append("%s ×%.2f %d/%d" % [gid, f, on_s, off_s])
	_expect(st == "fallen" and lux_n >= 3 and lux_bad.is_empty(), "明州 1276-02 %s：奢侈货 %d 样倍数 > 1、卖价比关态贵（不合：%s）" % [st, lux_n, lux_bad])
	var fg_early: float = eco.war_price_factor("mingzhou", "grain")
	_at(1276, 4)
	var fg: float = eco.war_price_factor("mingzhou", "grain")
	var g_on: int = eco.buy_price("mingzhou", "grain")
	var g_off := _old_price_at_rate("mingzhou", "grain", 1.0, true)
	_expect(is_equal_approx(fg_early, 1.0) and fg < 1.0 and g_on < g_off,
		"明州降元米粮：翻牌次月（1276-02）×%.2f 不打折，第三个月（1276-04）×%.2f、买价 %d < 关态 %d" % [fg_early, fg, g_on, g_off])
	# 头两个月不打折，泉州降元当月光杆米买价仍显得出抽解加倍、次月显得出站蒲家八折（与 godot_story_check 两条断言同条件）
	_at(1276, 12)
	var qz_fall: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	_at(1255, 3)
	var qz_peace: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	_at(1277, 1)
	var qz_plain: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	gs.set_flag("sided_pu")
	var qz_pu: int = eco.price_at_rate("quanzhou", "grain", 1.0, true)
	gs.flags.erase("sided_pu")
	_expect(qz_fall > qz_peace and qz_pu < qz_plain,
		"泉州降元当月光杆米买价 %d > 平年 %d（抽解加倍）、次月站蒲家 %d < %d（八折）——米头两个月不打折" % [qz_fall, qz_peace, qz_pu, qz_plain])
	_at(1276, 2)
	var gold_on: int = eco.sell_price("mingzhou", "placer_gold")
	var gold_off := _old_price_at_rate("mingzhou", "placer_gold", 1.0, false)
	_expect(eco.war_class("placer_gold") == "common" and gold_on == gold_off, "普通货砂金不随战况涨落（卖 %d = 关态 %d）" % [gold_on, gold_off])
	# 逐件推演跟着倍数走：卖 60 件参，开态进账高于关态
	var rev_on: int = eco.estimate_sell_revenue("mingzhou", "korean_ginseng", 60)
	var rev_old := _old_sell_revenue("mingzhou", "korean_ginseng", 60)
	_expect(rev_on > rev_old, "明州卖 60 件高丽参逐件推演：开 %d > 关 %d" % [rev_on, rev_old])


func _contested() -> void:
	CombatSwitches.reset()
	_at(1276, 6)
	var st := str(eco.war_status("quanzhou"))
	var fg: float = eco.war_price_factor("quanzhou", "grain")
	var fi: float = eco.war_price_factor("quanzhou", "ironware")
	var g_on: int = eco.sell_price("quanzhou", "grain")
	var g_off := _old_price_at_rate("quanzhou", "grain", 1.0, false)
	var i_on: int = eco.sell_price("quanzhou", "ironware")
	var i_off := _old_price_at_rate("quanzhou", "ironware", 1.0, false)
	_expect(st == "contested" and fg > 1.0 and fg <= 1.3 and fi > 1.0 and fi <= 1.3 and g_on > g_off and i_on > i_off,
		"泉州 1276-06 %s：米 ×%.2f（卖 %d/%d）、铁器 ×%.2f（卖 %d/%d），小幅涨" % [st, fg, g_on, g_off, fi, i_on, i_off])
	var fl: float = eco.war_price_factor("quanzhou", "ivory")
	_expect(fl <= 1.0, "泉州对峙奢侈货（象牙）不涨（×%.2f）" % fl)


## 卡上的 Label 们（含嵌在价格行里的）
func _labels_under(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels_under(c, out)


func _card_texts(card: Node) -> PackedStringArray:
	var labels: Array = []
	_labels_under(card, labels)
	var out := PackedStringArray()
	for l in labels:
		out.append(str((l as Label).text))
	return out


func _market_note() -> void:
	CombatSwitches.reset()
	gs.last_port = "mingzhou"
	_at(1276, 2)
	var note: String = eco.war_price_note("mingzhou", "korean_ginseng")
	var tip: String = eco.war_price_tip("mingzhou", "korean_ginseng")
	_expect(note == "已降元・贵二成" and tip.begins_with("明州已降元，奢侈货比平年贵二成"),
		"明州降元高丽参：短注「%s」、悬停「%s」" % [note, tip])
	var gnote_early: String = eco.war_price_note("mingzhou", "grain")
	_at(1276, 4)
	var gnote: String = eco.war_price_note("mingzhou", "grain")
	_expect(gnote_early == "" and gnote == "已降元・贱一成半", "明州降元米粮：次月不挂（「%s」），第三个月短注「%s」" % [gnote_early, gnote])
	_at(1276, 6)
	var qnote: String = eco.war_price_note("quanzhou", "grain")
	var lnote: String = eco.war_price_note("quanzhou", "ivory")
	_expect(qnote == "对峙・贵二成" and lnote == "对峙・贱半成", "泉州对峙：米「%s」、象牙「%s」" % [qnote, lnote])
	_at(1255, 3)
	_expect(str(eco.war_price_note("mingzhou", "korean_ginseng")) == "", "平年不挂短注")

	_at(1276, 2)
	var card: Control = _main._make_market_row("mingzhou", "korean_ginseng")
	root.add_child(card)
	await _settle(2)
	var war_lbl := card.find_child("WarPrice", true, false) as Label
	var want_price := "买 %d　卖 %d" % [eco.buy_price("mingzhou", "korean_ginseng"), eco.sell_price("mingzhou", "korean_ginseng")]
	var texts := _card_texts(card)
	_expect(war_lbl != null and war_lbl.text == note and war_lbl.tooltip_text == tip and war_lbl.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"明州柜上参那张卡价格右边挂「%s」，悬停弹得出（%s）" % [war_lbl.text if war_lbl != null else "（没挂）", war_lbl.tooltip_text if war_lbl != null else ""])
	_expect(want_price in texts and war_lbl != null and war_lbl.get_parent().get_child(0) is Label and (war_lbl.get_parent().get_child(0) as Label).text == want_price,
		"价格行原字照旧「%s」，短注与它同一行（卡上：%s）" % [want_price, " | ".join(texts)])
	var on_min := card.get_combined_minimum_size()
	card.queue_free()

	CombatSwitches.set_on("war_prices", false)
	var card_off: Control = _main._make_market_row("mingzhou", "korean_ginseng")
	root.add_child(card_off)
	await _settle(2)
	var off_price := "买 %d　卖 %d" % [_old_price_at_rate("mingzhou", "korean_ginseng", 1.0, true), _old_price_at_rate("mingzhou", "korean_ginseng", 1.0, false)]
	var off_texts := _card_texts(card_off)
	var price_parent_ok := false
	for l in _all_labels(card_off):
		if (l as Label).text == off_price:
			price_parent_ok = not (l.get_parent() is HBoxContainer)
	_expect(card_off.find_child("WarPrice", true, false) == null and card_off.find_child("PriceRow", true, false) == null
		and off_price in off_texts and price_parent_ok,
		"开关关：不挂短注，价格行「%s」照旧直接挂在卡的五行列里" % off_price)
	var off_min := card_off.get_combined_minimum_size()
	_expect(on_min.y <= off_min.y + 0.5 and on_min.x <= off_min.x + 40.0,
		"挂短注不加高、不把卡撑宽（最小 %.0f×%.0f，关态 %.0f×%.0f）" % [on_min.x, on_min.y, off_min.x, off_min.y])
	card_off.queue_free()
	CombatSwitches.reset()

	# 真进明州牙行（降元第四个月）：柜上三张卡，有战时倍数的那几张挂着同字短注，没有的不挂
	_at(1276, 4)
	_main.load_scene("mingzhou_market")
	await _settle(2)
	var slips: Node = _main.get("choices_container").get_node_or_null("BrokerSlips")
	var hand: PackedStringArray = _main.get("broker_hand")
	var page_bad: Array = []
	var noted := 0
	if slips != null:
		for i in range(mini(slips.get_child_count(), hand.size())):
			var want := str(eco.war_price_note("mingzhou", hand[i]))
			var lbl := slips.get_child(i).find_child("WarPrice", true, false) as Label
			var got := lbl.text if lbl != null else ""
			if got != want:
				page_bad.append("%s「%s」≠「%s」" % [hand[i], got, want])
			if want != "":
				noted += 1
	_expect(slips != null and hand.size() == 3 and noted >= 1 and page_bad.is_empty(),
		"明州 1276-04 牙行页：柜上 %s，挂短注 %d 张，与 war_price_note 逐张同字（不符 %s）" % [hand, noted, page_bad])


func _all_labels(n: Node) -> Array:
	var out: Array = []
	_labels_under(n, out)
	return out


func _spread_floor() -> void:
	CombatSwitches.reset()
	var n := 0
	var bad: Array = []
	for m in MONTHS.slice(1):
		_at(int(m[0]), int(m[1]))
		for pid in _ports():
			if not eco.is_market_open(pid):
				continue
			for raw_gid in eco.goods_at(pid):
				var gid := str(raw_gid)
				n += 1
				var b: int = eco.buy_price(pid, gid)
				var s: int = eco.sell_price(pid, gid)
				if b < s:
					bad.append("%d-%02d %s/%s 买 %d < 卖 %d" % [int(m[0]), int(m[1]), pid, gid, b, s])
	_expect(n > 0 and bad.is_empty(), "五个战况月开门的 %d 个（港, 货）买价都不低于卖价（倒挂 %s）" % [n, bad])
