extends SceneTree
## Lane w53-3：headless 探针——牙行「买满」不卡死，件数与总价照旧。
## 改前 Main._on_buy_max 从舱位件数起逐件往下减、每减一件把 estimate_buy_cost 从头推一遍（每件一次
## price_at_rate，约 25 μs），件数平方级：开局小艍 1000 钱买满经卷卡 2 秒，客舟卡二十多秒，大船买轻货卡几分钟。
## 改后 Economy.affordable_qty 与 estimate_buy_cost 同走 _walk_buy 一趟；行情顶到 RATE_MAX（卖砸到 RATE_MIN）
## 之后单价不变，余下件数一次算完。
##   一、Economy.affordable_qty / estimate_buy_cost / estimate_sell_revenue 与探针自带的逐件推演（不借 Economy
##      的推法，depth 按 ports.json 自算）逐格同数：三港 × 行情（地板 / 1.0 / 将顶 / 顶）× 件数 × 现银，含顶格之后。
##   二、实机按「买满」（Main._on_buy_max 真回调）：开局小艍 1000 钱、客舟 2000 钱各买满经卷，结算须 0.5 秒内
##      （按下的总耗时扣掉随后重排牙行页的耗时——重排另量一遍同一页），买到的件数 / 付的钱 = 逐件推演；
##      另「买 10」现银只够 4 件时照旧只买 4 件。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_buy_max_probe.gd
## 输出末行 W53_3_BUYMAX_PROBE cases=N fails=M；M>0 时 exit 1。

## lane w53-3（三轮）：本进程 SCRIPT ERROR 即红——接共用件 tools/script_err_tally.gd（子函数里出脚本错只中止那一个函数，
## 断言整段跳过、fails 不涨、headless -s 退出码守 0）；_run_guarded 包一层兜「_run 自己的代码行出错即中止、
## quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

## 结算（不含按完之后重排牙行页）的耗时上限。改前开局小艍一按约 2 秒、客舟约 25 秒；改后不到 10 毫秒
const PRESS_LIMIT_MS := 500

var _main: Node
var gs: Node
var gm: Node
var cal: Node
var fleet: Node
var crew: Node
var eco: Node
var _rates0: Dictionary = {}
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
	fleet = root.get_node("/root/Fleet")
	crew = root.get_node("/root/Crew")
	eco = root.get_node("/root/Economy")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	await _settle(10)
	if not _main.has_method("load_scene"):
		_expect(false, "Main.gd 未载入（先跑一遍 godot --headless --editor --quit 刷新类名缓存）")
		_report()
		return
	_rates0 = eco.rates.duplicate(true)

	_walk_matches()
	await _press_buy_max()

	eco.rates = _rates0.duplicate(true)
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
	print("W53_3_BUYMAX_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


## 深度 = ports.json depth × (1 + 修埠加深 × 等)，自算不借 Economy._depth
func _depth(port_id: String) -> float:
	var base := 100.0
	for p in gm.ports_data.get("ports", []):
		if str(p.get("id", "")) == port_id:
			base = float(p.get("depth", 100))
			break
	var cfg = gm.titles_data.get("invest", {})
	var per := float(cfg.get("depth_per_level", 0.12)) if typeof(cfg) == TYPE_DICTIONARY else 0.12
	return base * (1.0 + per * float(eco.investment_level(port_id)))


## 探针自带的逐件买入推演：每件报价后行情 +1/depth（钳在 RATE_MIN..RATE_MAX），买满 cap 件或 money ≥ 0 时付不起下一件即停
func _brute_buy(pid: String, gid: String, cap: int, money: int) -> Array:
	var r: float = eco.get_rate(pid, gid)
	var d := _depth(pid)
	var n := 0
	var total := 0
	while n < cap:
		var p: int = eco.price_at_rate(pid, gid, r, true)
		if money >= 0 and total + p > money:
			break
		total += p
		n += 1
		r = clampf(r + 1.0 / d, eco.RATE_MIN, eco.RATE_MAX)
	return [n, total]


func _brute_sell(pid: String, gid: String, amount: int) -> int:
	var r: float = eco.get_rate(pid, gid)
	var d := _depth(pid)
	var total := 0
	for i in amount:
		total += eco.price_at_rate(pid, gid, r, false)
		r = clampf(r - 1.0 / d, eco.RATE_MIN, eco.RATE_MAX)
	return total


# ── 一、逐格同数 ──────────────────────────────────────

func _walk_matches() -> void:
	print("── 一、affordable_qty / estimate_buy_cost / estimate_sell_revenue 与逐件推演同数（含顶格之后）")
	crew.from_dict({})
	gs.fame = 0
	eco.investments = {}
	var cells := [["quanzhou", "sutra_scrolls"], ["penghu", "fujian_porcelain"], ["hakata", "japanese_fan"]]
	var n_aff := 0
	var bad_aff := PackedStringArray()
	var n_buy := 0
	var bad_buy := PackedStringArray()
	var n_sell := 0
	var bad_sell := PackedStringArray()
	var saturated := 0
	# 回退到没有 affordable_qty 的旧式时照实判红，不让探针在调用处炸停
	var has_afford: bool = eco.has_method("affordable_qty")
	for cell in cells:
		var pid := str(cell[0])
		var gid := str(cell[1])
		for rate in [eco.RATE_MIN, 0.5, 1.0, 2.1, eco.RATE_MAX]:
			eco.rates = _rates0.duplicate(true)
			eco.rates[pid][gid] = rate
			var p0: int = eco.price_at_rate(pid, gid, rate, true)
			for cap in ([0, 1, 7, 60, 400] if has_afford else []):
				for money in [0, p0 - 1, p0, p0 * 5, p0 * 90, 1000000000]:
					n_aff += 1
					var want: int = int(_brute_buy(pid, gid, cap, money)[0])
					var got: int = eco.affordable_qty(pid, gid, money, cap)
					if got != want and bad_aff.size() < 4:
						bad_aff.append("%s/%s 行情%.2f 舱%d 钱%d：%d（应 %d）" % [pid, gid, rate, cap, money, got, want])
			for amount in [0, 1, 50, 400]:
				n_buy += 1
				var want_c: int = int(_brute_buy(pid, gid, amount, -1)[1])
				var got_c: int = eco.estimate_buy_cost(pid, gid, amount)
				if got_c != want_c and bad_buy.size() < 4:
					bad_buy.append("%s/%s 行情%.2f 买 %d：%d（应 %d）" % [pid, gid, rate, amount, got_c, want_c])
				if rate + float(amount) / _depth(pid) > eco.RATE_MAX:
					saturated += 1
				n_sell += 1
				var want_s := _brute_sell(pid, gid, amount)
				var got_s: int = eco.estimate_sell_revenue(pid, gid, amount)
				if got_s != want_s and bad_sell.size() < 4:
					bad_sell.append("%s/%s 行情%.2f 卖 %d：%d（应 %d）" % [pid, gid, rate, amount, got_s, want_s])
	eco.rates = _rates0.duplicate(true)
	_expect(has_afford and bad_aff.is_empty(), ("affordable_qty 与逐件推演同数（%d 格）%s" % [n_aff, "" if bad_aff.is_empty() else "：" + "；".join(bad_aff)])
		if has_afford else "Economy.affordable_qty 不在（买满减件仍逐件往下减）")
	_expect(bad_buy.is_empty() and saturated > 0,
		"estimate_buy_cost 与逐件推演同数（%d 格，其中 %d 格推过 RATE_MAX）%s" % [n_buy, saturated, "" if bad_buy.is_empty() else "：" + "；".join(bad_buy)])
	_expect(bad_sell.is_empty(), "estimate_sell_revenue 与逐件推演同数（%d 格，含砸到 RATE_MIN 之后）%s" % [n_sell, "" if bad_sell.is_empty() else "：" + "；".join(bad_sell)])
	_expect(has_afford and eco.affordable_qty("quanzhou", "sutra_scrolls", -100, 50) == 0
		and eco.affordable_qty("quanzhou", "sutra_scrolls", 100000, -3) == 0,
		"现银为负、件数为负都买 0 件（负钱不当无限）")


# ── 二、实机按「买满」 ───────────────────────────────

func _reset(port_id: String, money: int, ship_type: String) -> void:
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	eco.investments = {}
	gs.last_port = port_id
	gs.money = money
	gs.debt = 0
	fleet.ships = []
	fleet.add_ship(ship_type, "试船")
	fleet.water = 60
	fleet.food = 60


## 舱里先放一件经卷：柜上第一席是舱货，经卷必上柜（_on_buy 只认今日柜上的货）
func _press_buy_max() -> void:
	print("── 二、实机按「买满」（Main._on_buy_max）：结算 %d 毫秒内，件数 / 付钱 = 逐件推演" % PRESS_LIMIT_MS)
	var port := "quanzhou"
	var gid := "sutra_scrolls"
	for setup in [["sampan", 1000], ["keel_boat", 2000]]:
		_reset(port, int(setup[1]), str(setup[0]))
		fleet.add_cargo(gid, 1, 1.0, 0)
		_main.set("_market_ship", 0)
		_main.load_scene(port + "_market")
		await _settle(2)
		var hand: PackedStringArray = _main.get("broker_hand")
		var room: int = fleet.max_loadable(gid, 0)
		var want: Array = _brute_buy(port, gid, room, gs.money)
		var m0: int = gs.money
		var q0: int = fleet.cargo_qty(gid, 0)
		var t0 := Time.get_ticks_msec()
		_main._on_buy_max(port, gid, 0)
		var press_ms := Time.get_ticks_msec() - t0
		await _settle(2)
		var got_n: int = fleet.cargo_qty(gid, 0) - q0
		var paid: int = m0 - int(gs.money)
		# 按下去之后牙行页照例重排一遍（买卖每按一次都重排）；重排本身的耗时另量一遍同一页扣掉，只计结算
		t0 = Time.get_ticks_msec()
		_main.load_scene(port + "_market")
		var render_ms := Time.get_ticks_msec() - t0
		await _settle(2)
		var calc_ms := press_ms - render_ms
		_expect(gid in hand and calc_ms <= PRESS_LIMIT_MS and got_n == int(want[0]) and paid == int(want[1]),
			"%s（舱容 %d 件）%d 钱买满经卷：结算 %d 毫秒（按下共 %d、其中重排牙行页约 %d），买到 %d 件付 %d 钱（逐件推演 %d 件 %d 钱）" % [
				setup[0], room, m0, calc_ms, press_ms, render_ms, got_n, paid, want[0], want[1]])

	# 买 10 而现银只够 4 件：_on_buy 照旧按逐件总价减到 4 件
	_reset(port, 0, "sampan")
	fleet.add_cargo(gid, 1, 1.0, 0)
	gs.money = int(_brute_buy(port, gid, 4, -1)[1])
	_main.set("_market_ship", 0)
	_main.load_scene(port + "_market")
	await _settle(2)
	var m1: int = gs.money
	_main._on_buy(port, gid, 10, 0)
	await _settle(2)
	_expect(fleet.cargo_qty(gid, 0) == 5 and gs.money == 0,
		"买 10 而现银 %d 只够 4 件：买到 %d 件，余钱 %d" % [m1, fleet.cargo_qty(gid, 0) - 1, gs.money])
