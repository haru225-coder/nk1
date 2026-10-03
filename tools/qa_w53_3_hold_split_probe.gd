extends SceneTree
## Lane w53-3：headless 探针——分船货舱不得越过全队载重（Fleet.ship_free_capacity 的水粮摊派）。
## 水粮是全队池，按载重比例摊到各船。某船货已装满、摊到的那份放不下时，旧式把那艘钳成 0 了事，
## 那份水粮就从账上消失：别的船凭空多出同样多的「空舱」。
##   一、实机三步（走 Main 的真钮回调）：牙行把小艍买满 → 船屋连补水粮到全队只剩不到 50 料 →
##      换装客舟再买满。改前客舟钮写「空 165」、全队只剩 28 料，买完舱位 937 / 800 料。
##   二、没有船满时与旧式（只按比例摊）逐位相同——平常的装货不受影响。
##   三、两艘满、一艘空：两艘放不下的水粮全挪给第三艘；船船都满时各船空舱为 0、不为负。
##   四、随机三百步（装货 / 补水粮 / 卸货 / 海上吃水粮）：每步之后全队占用 ≤ 载重、各船货 ≤ 该船载重、
##      Σ 各船空舱 == 全队空舱。
## 用法：godot --headless --path . -s res://tools/qa_w53_3_hold_split_probe.gd
## 输出末行 W53_3_HOLD_PROBE cases=N fails=M；M>0 时 exit 1。

## lane w53-3（三轮）：本进程 SCRIPT ERROR 即红——接共用件 tools/script_err_tally.gd（子函数里出脚本错只中止那一个函数，
## 断言整段跳过、fails 不涨、headless -s 退出码守 0）；_run_guarded 包一层兜「_run 自己的代码行出错即中止、
## quit 不再执行、进程空转到超时」那一形（就地判红退 1）。
const ScriptErrTally := preload("res://tools/script_err_tally.gd")

var _main: Node
var gs: Node
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

	await _ui_three_steps()
	_unsaturated_identical()
	_spill_and_full()
	_fuzz()

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
	print("W53_3_HOLD_PROBE cases=%d fails=%d" % [cases, fails])
	quit(1 if fails > 0 else 0)


func _settle(n: int) -> void:
	for _i in n:
		await process_frame


func _find(n: Node, pred: Callable) -> Node:
	if n == null:
		return null
	if pred.call(n):
		return n
	for c in n.get_children():
		var hit := _find(c, pred)
		if hit != null:
			return hit
	return null


func _fleet_of(types: Array, water: int, food: int) -> void:
	fleet.ships = []
	var names := ["甲", "乙", "丙", "丁"]
	for i in types.size():
		fleet.add_ship(str(types[i]), "%s号" % names[i])
	fleet.water = water
	fleet.food = food


func _sum_free() -> float:
	var s := 0.0
	for i in fleet.ships.size():
		s += float(fleet.ship_free_capacity(i))
	return s


## 账目三条：全队占用 ≤ 载重；各船货 ≤ 该船载重；Σ 各船空舱 == 全队空舱
func _books_ok() -> bool:
	if float(fleet.used_capacity()) > float(fleet.total_capacity()) + 1e-6:
		return false
	for i in fleet.ships.size():
		if float(fleet.ship_cargo_bulk(i)) > float(fleet.ship_capacity(i)) + 1e-6:
			return false
		if float(fleet.ship_free_capacity(i)) < 0.0:
			return false
	return absf(_sum_free() - float(fleet.free_capacity())) < 1e-6


func _books_str() -> String:
	var bits := PackedStringArray()
	for i in fleet.ships.size():
		bits.append("%s 货 %.1f / %.0f 空 %.1f" % [
			fleet.display_name(i), fleet.ship_cargo_bulk(i), fleet.ship_capacity(i), fleet.ship_free_capacity(i)])
	return "全队 %.1f / %.0f 料、空 %.1f；%s" % [
		fleet.used_capacity(), fleet.total_capacity(), fleet.free_capacity(), "；".join(bits)]


# ── 一、实机三步 ──────────────────────────────────────

func _ui_three_steps() -> void:
	print("── 一、牙行买满一艘 → 船屋补水粮 → 换装另一艘再买满（Main 真钮回调）")
	var port := "quanzhou"
	gs.from_dict({})
	cal.from_dict({"year": 1255, "month": 3, "day": 1})
	crew.from_dict({})
	eco.rates = _rates0.duplicate(true)
	gs.last_port = port
	gs.money = 200000
	gs.debt = 0
	_fleet_of(["sampan", "keel_boat"], 60, 60)

	_main.load_scene(port + "_market")
	await _settle(3)
	var hand: PackedStringArray = _main.get("broker_hand")
	_expect(hand.size() > 0, "泉州牙行柜上有货")
	if hand.is_empty():
		return
	var gid0 := str(hand[0])
	var bulk0: float = fleet.call("_bulk", gid0)
	_main._on_buy_max(port, gid0, 0)
	await _settle(2)
	_expect(fleet.cargo_qty(gid0, 0) > 0 and float(fleet.ship_free_capacity(0)) < bulk0,
		"牙行把甲号买满（%s ×%d）：%s" % [gid0, fleet.cargo_qty(gid0, 0), _books_str()])

	var gp: int = eco.buy_price(port, "grain")
	var pressed := 0
	while float(fleet.free_capacity()) >= 50.0 and pressed < 40:
		_main._on_buy_supplies(100, 1, gp)
		await _settle(1)
		pressed += 1
	_expect(float(fleet.free_capacity()) < 50.0 and fleet.water > 1000,
		"船屋「水粮各 100」按 %d 次补到水 %d 粮 %d：%s" % [pressed, fleet.water, fleet.food, _books_str()])
	_expect(_books_ok(), "补完水粮后 Σ 各船空舱 %.1f == 全队空舱 %.1f" % [_sum_free(), fleet.free_capacity()])

	_main._select_market_ship(1)
	await _settle(2)
	var ship_name: String = fleet.display_name(1)
	var chip := _find(_main, func(n: Node) -> bool:
		return n is Button and str((n as Button).text).begins_with(ship_name + "　空 ")) as Button
	var chip_room := -1
	if chip != null:
		chip_room = int(str(chip.text).get_slice("空 ", 1))
	_expect(chip != null and chip_room <= int(fleet.free_capacity()),
		"牙行「装至」钮写「%s」，不多于全队空舱 %d 料" % [chip.text if chip != null else "（找不到钮）", int(fleet.free_capacity())])

	hand = _main.get("broker_hand")
	var gid1 := str(hand[0]) if hand.size() > 0 else ""
	if gid1 != "":
		_main._on_buy_max(port, gid1, 1)
		await _settle(2)
	_expect(gid1 != "" and _books_ok(),
		"乙号再买满（%s ×%d）后舱位 %d / %d 料，不越载重：%s" % [
			gid1, fleet.cargo_qty(gid1, 1), int(fleet.used_capacity()), int(fleet.total_capacity()), _books_str()])


# ── 二、没有船满时与旧式逐位相同 ─────────────────────────

## 旧式（只按载重比例摊），没有船满时新旧两式应逐位相同
func _old_free(i: int) -> float:
	var tc: float = fleet.total_capacity()
	var wf := float(fleet.water + fleet.food) * float(fleet.SUPPLY_BULK)
	var share := wf * (float(fleet.ship_capacity(i)) / tc) if tc > 0.0 else wf / float(fleet.ships.size())
	return maxf(0.0, float(fleet.ship_capacity(i)) - float(fleet.ship_cargo_bulk(i)) - share)


func _unsaturated_identical() -> void:
	print("── 二、没有船满时与只按比例摊逐位相同")
	var setups := [
		[["sampan"], 60, 60, [{"grain": 40}]],
		[["sampan", "fu_ship_medium"], 100, 100, [{"fujian_porcelain": 20}, {"qingbai_porcelain": 60}]],
		[["sampan", "keel_boat", "fu_ship_large"], 300, 300, [{"raw_silk": 10}, {"tea": 33}, {"ivory": 8}]],
		[["keel_boat", "canton_ship"], 0, 0, [{"sappanwood": 100}, {}]],
	]
	for s in setups:
		_fleet_of(s[0], int(s[1]), int(s[2]))
		var cargo: Array = s[3]
		for i in cargo.size():
			for gid in (cargo[i] as Dictionary).keys():
				fleet.add_cargo(str(gid), int(cargo[i][gid]), 1.0, i)
		var same := true
		var got := PackedStringArray()
		for i in fleet.ships.size():
			var a: float = fleet.ship_free_capacity(i)
			var b := _old_free(i)
			got.append("%.4f/%.4f" % [a, b])
			if a != b:
				same = false
		_expect(same and _books_ok(), "%s 水粮 %d/%d：各船空舱新旧逐位相同（%s）" % [str(s[0]), s[1], s[2], ", ".join(got)])


# ── 三、挪摊与船船都满 ──────────────────────────────────

func _spill_and_full() -> void:
	print("── 三、两艘满、一艘空：放不下的水粮挪给第三艘；船船都满时空舱为 0")
	# 小艍 200 + 客舟 600 + 福船中 800 = 1600 料。小艍、客舟各装满米，水粮 400/400 = 200 料全归福船。
	_fleet_of(["sampan", "keel_boat", "fu_ship_medium"], 400, 400)
	fleet.ships[0]["cargo"] = {"grain": {"qty": 200, "avg_cost": 1.0}}
	fleet.ships[1]["cargo"] = {"grain": {"qty": 600, "avg_cost": 1.0}}
	var f2: float = fleet.ship_free_capacity(2)
	_expect(fleet.ship_free_capacity(0) == 0.0 and fleet.ship_free_capacity(1) == 0.0 and absf(f2 - 600.0) < 1e-6 and _books_ok(),
		"两艘满载：福船空 %.1f 料（800 − 水粮 200），Σ == 全队空舱 %.1f" % [f2, fleet.free_capacity()])
	_expect(fleet.max_loadable("grain", 2) == 600 and not fleet.add_cargo("grain", 601, 1.0, 2) and fleet.add_cargo("grain", 600, 1.0, 2),
		"福船再装米：容 600 件，601 件装不下")
	_expect(_books_ok() and absf(float(fleet.used_capacity()) - 1600.0) < 1e-6,
		"三船装满后舱位 %.1f / 1600 料，不越载重" % fleet.used_capacity())
	# 补水粮之外的路子把水粮推过余舱（剧情给粮、征船交出一艘）：各船空舱为 0，不为负
	fleet.water += 40
	fleet.food += 40
	var all_zero := true
	for i in fleet.ships.size():
		if fleet.ship_free_capacity(i) != 0.0:
			all_zero = false
	_expect(all_zero and fleet.free_capacity() == 0.0 and fleet.max_loadable("grain", 0) == 0,
		"水粮被推过余舱：各船空舱皆 0、全队空舱 0、一件也装不进")


# ── 四、随机三百步 ──────────────────────────────────────

func _fuzz() -> void:
	print("── 四、随机三百步：装货 / 补水粮 / 卸货 / 海上吃水粮，每步之后账目三条都成立")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5303
	var kinds := ["grain", "tea", "qingbai_porcelain", "sappanwood", "placer_gold"]
	_fleet_of(["sampan", "keel_boat", "fu_ship_medium"], 60, 60)
	var bad_step := -1
	var bad_what := ""
	var loads := 0
	for step in 300:
		var op := rng.randi_range(0, 3)
		var what := ""
		if op == 0:
			var i := rng.randi_range(0, fleet.ships.size() - 1)
			var gid: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var n: int = fleet.max_loadable(gid, i)
			if n > 0:
				var q := rng.randi_range(1, n)
				fleet.add_cargo(gid, q, 1.0, i)
				loads += 1
				what = "装 %s×%d 进船%d" % [gid, q, i]
		elif op == 1:
			var pairs := int(floor(float(fleet.free_capacity()) / (2.0 * float(fleet.SUPPLY_BULK))))
			if pairs > 0:
				var p := rng.randi_range(1, pairs)
				fleet.water += p
				fleet.food += p
				what = "补水粮 %d" % p
		elif op == 2:
			var i := rng.randi_range(0, fleet.ships.size() - 1)
			var sc: Dictionary = fleet.ships[i].get("cargo", {})
			if not sc.is_empty():
				var gid := str(sc.keys()[rng.randi_range(0, sc.size() - 1)])
				var q := rng.randi_range(1, int(sc[gid]["qty"]))
				fleet.remove_cargo(gid, q, i)
				what = "卸 %s×%d 出船%d" % [gid, q, i]
		else:
			var d := rng.randi_range(1, 40)
			fleet.water = maxi(0, fleet.water - d)
			fleet.food = maxi(0, fleet.food - d)
			what = "吃水粮 %d" % d
		if bad_step < 0 and not _books_ok():
			bad_step = step
			bad_what = "%s 之后 %s" % [what, _books_str()]
	_expect(bad_step < 0 and loads > 20,
		"三百步（装货 %d 次）每步账目三条都成立%s" % [loads, "" if bad_step < 0 else "；第 %d 步破：%s" % [bad_step, bad_what]])
