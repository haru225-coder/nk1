extends SceneTree
## lane w55 城中各处探针（headless，经门锁跑）。
##   godot --headless --path . -s res://tools/qa_w55_districts_probe.gd
## 断言：
##   一、data/districts.json 每处有港、名、类、底图、正文和至少一条事；底图在 assets/；
##      事的类型、货、传闻港、入股、公凭、大比之年都说得通。泉州、兴化各至少十五处。
##   二、引擎真办：买海盐推价、塌房静卖不推价、委办货不上秤、茶坊入股月初只入这一级、
##      通事月俸与辞退、经师月课、传闻与冷却、细色公凭打折、窑凭、斗茶、石碑一年一次、
##      看榜的年与月、湄洲年份、祈风月份、围城送米、铁作不新造行情键、东廊一月一次、存档来回。
##   三、真起 Main：泉州「城中各处」进后渚再离开；福州没有这枚钮；1276 冬兴化守城页也没有。
## 判词：末行 QA_W55_DISTRICTS PASS|FAIL cases=N fails=K；有失败退 1；本进程 SCRIPT ERROR 也判红。

const TAG := "QA_W55_DISTRICTS"
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 不在文件顶 preload 城区账本。-s 脚本在 autoload 挂上之前就解析，
## 顶上的 preload 会让 Districts 在那一轮看不见 GameState，整本方法都编不出来。
var Book

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _cases := 0
var _fails := 0
var _tally: ScriptErrTally
var _reported := false
var _rows: Array = []


func _init() -> void:
	_tally = ScriptErrTally.new()
	OS.add_logger(_tally)
	call_deferred("_run_guarded")


func _run_guarded() -> void:
	await _run()
	if not _reported:
		_check(false, "主流程跑到收尾（%s）" % _tally.abort_note())
		_report()


func _check(ok: bool, msg: String) -> void:
	_cases += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _report() -> void:
	_reported = true
	for v in _tally.verdicts():
		_check(v[0], v[1])
	print("%s %s cases=%d fails=%d" % [TAG, "PASS" if _fails == 0 else "FAIL", _cases, _fails])
	quit(1 if _fails > 0 else 0)


func _run() -> void:
	var cine_src: GDScript = load("res://scripts/cutscene/Cinematics.gd") as GDScript
	if cine_src != null:
		cine_src.set("auto_opening", false)
		cine_src.set("opening_seen", true)
	gs = root.get_node("GameState")
	gm = root.get_node("GameManager")
	cal = root.get_node("Calendar")
	fleet = root.get_node("Fleet")
	crew = root.get_node("Crew")
	eco = root.get_node("Economy")
	Book = load(_book_path())
	if Book == null:
		_check(false, "城区账本没载入")
		_report()
		return
	_stage_boot()
	print("== 一、表")
	_sec_table()
	print("== 二、办事")
	_sec_engine()
	print("== 三、港页")
	await _sec_ui()
	_report()


func _stage_boot() -> void:
	gs.from_dict({})
	gs.chapter = 1
	gs.money = 30000
	gs.visited_ports = ["xinghua", "quanzhou"]
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.investments = {}
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	gs.last_port = "quanzhou"
	Book.wipe()


func _fresh() -> void:
	Book.wipe()
	gs.money = 30000
	gs.contract = {}
	gs.siege = {}
	gs.flags = {}
	gs.identity = "undecided"
	gs.player_name = "陈子龙"
	gs.pu_attention = 0
	gs.merchant_credit = 0
	gs.scholar_tendency = 0
	gs.hometown_tendency = 0
	gs.network = 0
	gs.fame = 0
	fleet.from_dict({"ships": [], "water": 600, "food": 600})
	fleet.add_ship("keel_boat", "旗舰")
	cal.from_dict({"year": 1255, "month": 3, "day": 1})


func _book_path() -> String:
	var path := "res://"
	path += "scripts/"
	path += "core/"
	path += "Districts.gd"
	return path


func _ix(id: String) -> Dictionary:
	return Book.interaction(id)


func _sec_table() -> void:
	var txt := FileAccess.get_file_as_string("res://data/districts.json")
	var parsed = JSON.parse_string(txt)
	_check(typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("districts", null)) == TYPE_ARRAY,
		"一、顶层是 districts 数组")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_rows = parsed.get("districts", [])
	var ports: Dictionary = {}
	var seen_d := {}
	var seen_i := {}
	var bad := 0
	var banned := 0
	var bag: Array = []
	_walk(parsed, bag)
	for s in bag:
		var line := str(s)
		if line.contains("石像") or line.contains("雕像") or line.contains("牌坊"):
			banned += 1
	_check(banned == 0, "一、全文没有石像、雕像、牌坊（撞上 %d 处）" % banned)
	for row in _rows:
		if typeof(row) != TYPE_DICTIONARY:
			bad += 1
			continue
		var id := str(row.get("id", ""))
		var port := str(row.get("port", ""))
		var bg := str(row.get("bg", ""))
		if id == "" or seen_d.has(id):
			bad += 1
		seen_d[id] = true
		if gm.get_port_by_id(port).is_empty():
			bad += 1
		ports[port] = int(ports.get(port, 0)) + 1
		if str(row.get("name", "")) == "" or str(row.get("kind", "")) == "" or str(row.get("description", "")) == "":
			bad += 1
		if not bg.begins_with("bg_dist_") or not bg.ends_with(".jpg") or not FileAccess.file_exists("res://assets/" + bg):
			bad += 1
			print("    缺底图 %s" % bg)
		var ixs = row.get("interactions", [])
		if typeof(ixs) != TYPE_ARRAY or ixs.is_empty():
			bad += 1
			continue
		for ix in ixs:
			if typeof(ix) != TYPE_DICTIONARY:
				bad += 1
				continue
			var iid := str(ix.get("id", ""))
			var typ := str(ix.get("type", ""))
			if iid == "" or iid == id or seen_i.has(iid) or not Book.TYPES.has(typ):
				bad += 1
			seen_i[iid] = true
			if str(ix.get("label", "")) == "" or str(ix.get("text", "")) == "":
				bad += 1
			if typ == "buy" or typ == "sell":
				if gm.get_good_by_id(str(ix.get("good", ""))).is_empty() or int(ix.get("qty", 0)) <= 0:
					bad += 1
			if typ == "rumor" and not _rumor_shape(ix):
				bad += 1
			if typ == "invest" and not _invest_shape(ix):
				bad += 1
			if typ == "licence":
				if not str(ix.get("licence", "")).begins_with("lic_"):
					bad += 1
			if typ == "hire" and (str(ix.get("who", "")) == "" or int(ix.get("wage", 0)) <= 0):
				bad += 1
			if typ == "choice":
				var opts = ix.get("options", [])
				if typeof(opts) != TYPE_ARRAY or opts.is_empty():
					bad += 1
				else:
					for opt in opts:
						if typeof(opt) != TYPE_DICTIONARY or str(opt.get("id", "")) == "":
							bad += 1
						elif opt.has("rumor") and not _rumor_shape(opt.get("rumor", {})):
							bad += 1
			if bool(ix.get("exam", false)):
				var gate: Dictionary = ix.get("unlock", {})
				if not _same_ints(gate.get("years", []), Book.EXAM_YEARS) or not _same_ints(gate.get("months", []), Book.EXAM_MONTHS):
					bad += 1
	_check(bad == 0, "一、三十处的字段、货、传闻、入股、公凭、大比都说得通（坏 %d）" % bad)
	_check(int(ports.get("quanzhou", 0)) >= 15 and int(ports.get("xinghua", 0)) >= 15 and not ports.has("xinghua_harbor"),
		"一、泉州 %d 处、兴化 %d 处，海口不单列" % [int(ports.get("quanzhou", 0)), int(ports.get("xinghua", 0))])
	var han: Dictionary = Book.district("xh_hanjiang")
	var gua: Dictionary = Book.district("xh_guanghua")
	_check(str(han.get("description", "")).contains("城内涵江渡"), "一、涵江渡写明是城内的渡")
	_check(str(gua.get("lock_reason", "")).contains("南山"), "一、广化寺关着时说到南山")


func _rumor_shape(spec) -> bool:
	if typeof(spec) != TYPE_DICTIONARY:
		return false
	var port := str(spec.get("port", ""))
	var good := str(spec.get("good", ""))
	var mul := float(spec.get("mul", 1.0))
	if gm.get_port_by_id(port).is_empty() or gm.get_good_by_id(good).is_empty():
		return false
	if mul <= 0.0 or is_equal_approx(mul, 1.0):
		return false
	return eco.is_traded(port, good) and eco.rates.get(port, {}).has(good)


func _invest_shape(ix: Dictionary) -> bool:
	var costs = ix.get("costs", [])
	var monthly = ix.get("monthly", [])
	if typeof(costs) != TYPE_ARRAY or typeof(monthly) != TYPE_ARRAY or costs.is_empty() or costs.size() != monthly.size():
		return false
	for c in costs:
		if int(c) <= 0:
			return false
	return str(ix.get("shop", "")) != ""


func _same_ints(got, want: Array) -> bool:
	if typeof(got) != TYPE_ARRAY or got.size() != want.size():
		return false
	for i in got.size():
		if int(got[i]) != int(want[i]):
			return false
	return true


func _walk(v, bag: Array) -> void:
	match typeof(v):
		TYPE_STRING:
			bag.append(v)
		TYPE_DICTIONARY:
			for k in v:
				_walk(v[k], bag)
		TYPE_ARRAY:
			for x in v:
				_walk(x, bag)


func _sec_engine() -> void:
	_fresh()
	var salt := _ix("qz_houzhu_salt")
	var rate0 := float(eco.rates["quanzhou"]["sea_salt"])
	var money0 := int(gs.money)
	var bought: Dictionary = Book.apply("qz_houzhu_salt")
	_check(bool(bought.get("ok", false)) and int(gs.money) < money0 and fleet.cargo_qty("sea_salt") == int(salt.get("qty", 0)) and float(eco.rates["quanzhou"]["sea_salt"]) > rate0,
		"二、后渚收海盐：钱少了、舱里有货、行情高了一点")
	_fresh()
	var quiet := _ix("qz_tafang_quiet")
	var good := str(quiet.get("good", ""))
	var qty := int(quiet.get("qty", 0))
	fleet.add_cargo(good, qty, 1.0)
	var still := float(eco.rates["quanzhou"][good])
	var sold: Dictionary = Book.apply("qz_tafang_quiet")
	_check(bool(sold.get("ok", false)) and is_equal_approx(float(eco.rates["quanzhou"][good]), still) and fleet.cargo_qty(good) == 0,
		"二、塌房静卖：成交，行情不动")
	fleet.add_cargo(good, qty, 1.0)
	gs.contract = {"good_id": good, "remaining": qty, "qty": qty}
	var held: int = fleet.cargo_qty(good)
	var blocked: Dictionary = Book.apply("qz_tafang_quiet")
	_check(not bool(blocked.get("ok", false)) and str(blocked.get("msg", "")) == "委办货不上秤" and fleet.cargo_qty(good) == held,
		"二、委办货还在舱里，塌房不收")
	_fresh()
	var stall := _ix("qz_citong_stall")
	var invested: Dictionary = Book.apply("qz_citong_stall")
	var pay := int(stall.get("monthly", [0])[0])
	var before := int(gs.money)
	var notices: Array = eco.on_month_changed()
	var joined := ""
	for line in notices:
		joined += str(line)
	_check(bool(invested.get("ok", false)) and Book.level_of("qz_citong_stall") == 1 and int(gs.money) - before == pay and joined.contains("入账") and joined.contains(str(pay)),
		"二、茶坊入了一级，月初只入这一级的 %d 钱，通告里有入账" % pay)
	_fresh()
	var who := _ix("qz_fanfang_interpreter")
	var wage := int(who.get("wage", 0))
	var ease := int(who.get("attention_ease", 0))
	_check(bool(Book.apply("qz_fanfang_interpreter").get("ok", false)), "二、蕃坊通事应了")
	gs.pu_attention = 5
	var purse := int(gs.money)
	var paid: String = str(Book.month_tick())
	_check(int(gs.money) == purse - wage and int(gs.pu_attention) == 5 - ease and paid.contains("月俸"),
		"二、通事月俸 %d，蒲家留意减 %d" % [wage, ease])
	gs.money = wage - 1
	var left: String = str(Book.month_tick())
	_check(not Book.is_hired("qz_fanfang_interpreter") and left.contains("人走了"), "二、月俸未发，人走了")
	_fresh()
	var scholar0 := int(gs.scholar_tendency)
	_check(bool(Book.apply("xh_academy_teacher").get("ok", false)), "二、经师应了")
	Book.month_tick()
	_check(int(gs.scholar_tendency) == scholar0 + 1, "二、经师的月课，学者加 1")
	_fresh()
	var rumor := _ix("qz_houzhu_rumor")
	var ivory0 := float(eco.rates["hakata"]["ivory"])
	var heard: Dictionary = Book.apply("qz_houzhu_rumor")
	var expect := clampf(ivory0 * float(rumor.get("mul", 1.0)), eco.RATE_MIN, eco.RATE_MAX)
	var rec: Dictionary = gs.rumor_of("hakata", "ivory")
	_check(bool(heard.get("ok", false)) and is_equal_approx(float(eco.rates["hakata"]["ivory"]), expect) and is_equal_approx(float(rec.get("rate", 0.0)), expect),
		"二、后渚的象牙传闻按倍数落在博多，并记了下来")
	var soon: Dictionary = Book.apply("qz_houzhu_rumor")
	cal.advance_days(int(rumor.get("cooldown_days", 0)))
	var later: Dictionary = Book.apply("qz_houzhu_rumor")
	_check(not bool(soon.get("ok", false)) and str(soon.get("msg", "")) == "过些日子再来" and bool(later.get("ok", false)),
		"二、传闻冷却没到不再收钱，日子够了可以再听")
	_fresh()
	var spice := _ix("qz_spice_med")
	var high: int = int(Book.unit_price("quanzhou", spice))
	Book.ensure().favour["quanzhou"] = 2
	var fine: Dictionary = Book.apply("qz_shibo_fine")
	var low: int = int(Book.unit_price("quanzhou", spice))
	var base: int = eco.buy_price("quanzhou", str(spice.get("good", "")))
	var want := maxi(1, int(round(float(base) * float(spice.get("price_mul", 1.0)) * float(spice.get("bonus_mul", 0.9)))))
	_check(bool(fine.get("ok", false)) and low == want and low < high, "二、细色公凭到手后，香料按折扣算")
	_fresh()
	var no_lic: Dictionary = Book.apply("qz_kiln_bulk")
	var got_lic: Dictionary = Book.apply("qz_kiln_licence")
	var bulk: Dictionary = Book.apply("qz_kiln_bulk")
	_check(not bool(no_lic.get("ok", false)) and str(no_lic.get("msg", "")) == "未有公凭" and bool(got_lic.get("ok", false)) and bool(bulk.get("ok", false)),
		"二、磁灶成批货要先有窑凭")
	_fresh()
	var tea0 := float(eco.rates["hakata"]["tea"])
	var credit0 := int(gs.merchant_credit)
	var purse2 := int(gs.money)
	var play: Dictionary = Book.apply("qz_citong_wager", "play")
	var opt_cost := 0
	for opt in _ix("qz_citong_wager").get("options", []):
		if str(opt.get("id", "")) == "play":
			opt_cost = int(opt.get("cost", 0))
	_check(bool(play.get("ok", false)) and int(gs.merchant_credit) == credit0 + 1 and purse2 - int(gs.money) == opt_cost and not is_equal_approx(float(eco.rates["hakata"]["tea"]), tea0),
		"二、斗茶押一盏：信用加 1，茶价动了")
	_fresh()
	var stele: Dictionary = Book.apply("qz_bang_stele")
	var stele2: Dictionary = Book.apply("qz_bang_stele")
	_check(bool(stele.get("ok", false)) and not bool(stele2.get("ok", false)) and str(stele2.get("msg", "")) == "已经办过",
		"二、贡院石碑一年按一回")
	_fresh()
	var early: Dictionary = Book.apply("qz_bang_look")
	cal.from_dict({"year": 1257, "month": 9, "day": 1})
	var offyear: Dictionary = Book.apply("qz_bang_look")
	cal.from_dict({"year": 1268, "month": 7, "day": 1})
	var early_month: Dictionary = Book.apply("qz_bang_look")
	cal.from_dict({"year": 1268, "month": 9, "day": 1})
	gs.identity = "scholar"
	gs.set_flag("renamed_wenlong")
	gs.player_name = "陈文龙"
	var looked: Dictionary = Book.apply("qz_bang_look")
	var look_msg := str(looked.get("msg", ""))
	_check(not bool(early.get("ok", false)) and str(offyear.get("msg", "")) == "不是大比之年" and str(early_month.get("msg", "")) == "还不是这个月的事" and bool(looked.get("ok", false)) and look_msg.contains("陈文龙") and look_msg.contains("那是你的名字"),
		"二、看榜只在大比之年的秋天，1268 年的榜上有陈文龙")
	_fresh()
	var young: Dictionary = Book.apply("xh_meizhou_rumor")
	cal.from_dict({"year": 1276, "month": 3, "day": 1})
	var older: Dictionary = Book.apply("xh_meizhou_rumor")
	_check(str(young.get("msg", "")) == "年份未到" and bool(older.get("ok", false)), "二、湄洲的盐讯要到年头才有")
	_fresh()
	var winter: Dictionary = Book.apply("qz_jiuri_summer")
	cal.from_dict({"year": 1255, "month": 5, "day": 1})
	var summer: Dictionary = Book.apply("qz_jiuri_summer")
	_check(str(winter.get("msg", "")) == "还不是这个月的事" and bool(summer.get("ok", false)), "二、九日山夏祈不在三月办")
	_fresh()
	var siege_ix := _ix("xh_mulan_siege")
	var take: Dictionary = siege_ix.get("effects", {}).get("cargo_take", {})
	var grain_n := int(take.get("qty", 0))
	var add_n := int(siege_ix.get("effects", {}).get("siege", {}).get("grain", 0))
	fleet.add_cargo("grain", grain_n, 1.0)
	var grain_held: int = fleet.cargo_qty("grain")
	var shut: Dictionary = Book.apply("xh_mulan_siege")
	_check(not bool(shut.get("ok", false)) and str(shut.get("msg", "")) == "城防的账还没开" and fleet.cargo_qty("grain") == grain_held,
		"二、城防没开，陂上的米一粒不动")
	gs.siege_begin()
	var g0: int = gs.siege_get("grain")
	var sent: Dictionary = Book.apply("xh_mulan_siege")
	_check(bool(sent.get("ok", false)) and fleet.cargo_qty("grain") == grain_held - grain_n and gs.siege_get("grain") == g0 + add_n,
		"二、城防开了，送走的米按表上的数进账")
	_fresh()
	var iron_keys: int = eco.rates["xinghua"].size()
	var had_iron: bool = eco.rates["xinghua"].has("ironware")
	var iron: Dictionary = Book.apply("xh_smith_iron")
	var iron_qty := int(_ix("xh_smith_iron").get("qty", 0))
	_check(bool(iron.get("ok", false)) and fleet.cargo_qty("ironware") == iron_qty and eco.rates["xinghua"].has("ironware") == had_iron and eco.rates["xinghua"].size() == iron_keys,
		"二、铁作的铁器进舱，兴化行情不新开铁器这一格")
	_fresh()
	var gift := _ix("qz_shibo_gift")
	var once: Dictionary = Book.apply("qz_shibo_gift")
	var twice: Dictionary = Book.apply("qz_shibo_gift")
	_check(bool(once.get("ok", false)) and not bool(twice.get("ok", false)) and str(twice.get("msg", "")) == "已经办过" and Book.favour_of("quanzhou") == int(gift.get("effects", {}).get("favour", 0)),
		"二、东廊送礼一个月一回，人情记在泉州")
	_fresh()
	Book.ensure().once["qz_bang_look"] = 120
	Book.ensure().year["qz_bang_look"] = 1268
	Book.ensure().cool["qz_jiuri_summer"] = 200
	Book.ensure().invest["qz_citong_stall"] = 1
	Book.ensure().hire["qz_fanfang_interpreter"] = true
	Book.ensure().licence["lic_qz_fine"] = true
	Book.ensure().favour["quanzhou"] = 2
	var raw := JSON.stringify(gs.to_dict())
	var back = JSON.parse_string(raw)
	gs.from_dict(back)
	var d: Dictionary = gs.districts
	_check(int(d.get("once", {}).get("qz_bang_look", 0)) == 120 and int(d.get("year", {}).get("qz_bang_look", 0)) == 1268 and int(d.get("cool", {}).get("qz_jiuri_summer", 0)) == 200 and int(d.get("invest", {}).get("qz_citong_stall", 0)) == 1 and d.get("hire", {}).get("qz_fanfang_interpreter", false) == true and d.get("licence", {}).get("lic_qz_fine", false) == true and int(d.get("favour", {}).get("quanzhou", 0)) == 2,
		"二、城区八个桶经 JSON 来回仍是整数和 true")
	_check(d.has("month") and typeof(d.get("month")) == TYPE_DICTIONARY, "二、空的月份桶也还在")


func _sec_ui() -> void:
	_fresh()
	gs.loaded_with_beats = true
	for b in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b as Dictionary).get("entry", "")))
	gs.visited_ports = ["xinghua", "quanzhou", "fuzhou"]
	gs.money = 30000
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	_fresh()
	gs.loaded_with_beats = true
	for b2 in gm.port_beats_data.get("beats", []):
		gs.beat_mark(str((b2 as Dictionary).get("entry", "")))
	gs.money = 30000
	_main.load_scene("quanzhou")
	await _settle(6)
	var door := _find_button(_main, "城中各处")
	_check(door != null, "三、泉州港页有城中各处")
	if door == null:
		return
	door.pressed.emit()
	await _settle(4)
	_check(str(_main.scene_title.text) == "城中各处", "三、名单题头是城中各处")
	var into := _find_button(_main, "进去")
	_check(into != null, "三、名单上有进去")
	if into == null:
		return
	into.pressed.emit()
	await _settle(4)
	_check(str(_main.get("_bg_file")) == "bg_dist_qz_houzhu.jpg" and str(_main.get("current_scene_id")) == "quanzhou",
		"三、第一处是后渚，人还在泉州")
	var leave := _find_button(_main, "离开")
	_check(leave != null, "三、事页有离开")
	if leave == null:
		return
	leave.pressed.emit()
	await _settle(4)
	_check(str(_main.scene_title.text) == "城中各处" and str(_main.get("_bg_file")) == str(_main._port_bg("quanzhou")),
		"三、离开后渚回到名单，底图换回港图")
	var leave2 := _find_button(_main, "离开")
	if leave2 != null:
		leave2.pressed.emit()
	await _settle(4)
	_check(bool((_main.get("port_mode") as CanvasItem).visible), "三、再离开回到港页")
	_main.load_scene("fuzhou")
	await _settle(6)
	_check(_find_button(_main, "城中各处") == null, "三、福州没有城中各处")
	cal.from_dict({"year": 1276, "month": 11, "day": 1})
	gs.set_flag("renamed_wenlong")
	_main.load_scene("xinghua")
	await _settle(6)
	_check(str(_main.get("_shore_mode")) == "siege" and _find_button(_main, "城中各处") == null,
		"三、1276 冬兴化守城页没有城中各处")


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null
